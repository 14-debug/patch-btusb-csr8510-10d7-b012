#!/bin/bash

# Patches btusb.c to add fake CSR8510 A10 support (10d7:b012)
# Usage: sudo ./patch-btusb-csr8510.sh
set -euo pipefail

KVER=$(uname -r)
KDIR="/lib/modules/${KVER}/build"
MOD_DIR="/lib/modules/${KVER}/kernel/drivers/bluetooth"
BUILDDIR=$(mktemp -d /tmp/btusb-build.XXXXX)
KERNEL_TAG="v$(echo "$KVER" | grep -oP '^\d+\.\d+')"

VENDOR="0x10d7"
PRODUCT="0xb012"

[[ $EUID -eq 0 ]] || { echo "Error: run with sudo"; exit 1; }
[[ -d "$KDIR" ]] || { echo "Error: kernel-devel not installed. Run: dnf install kernel-devel"; exit 1; }

cleanup() { rm -rf "$BUILDDIR"; }
trap cleanup EXIT

insert_after() {
    local file=$1 line=$2 text=$3 tmp
    tmp=$(mktemp)
    head -n "$line" "$file" > "$tmp"
    printf '%s\n' "$text" >> "$tmp"
    tail -n +"$((line + 1))" "$file" >> "$tmp"
    mv "$tmp" "$file"
}

echo "==> Downloading btusb.c and headers (${KERNEL_TAG})..."
BASE_URL="https://raw.githubusercontent.com/torvalds/linux/${KERNEL_TAG}/drivers/bluetooth"
for f in btusb.c btintel.h btbcm.h btrtl.h btmtk.h; do
    curl -sfL "${BASE_URL}/${f}" -o "${BUILDDIR}/${f}" || { echo "Error downloading $f"; exit 1; }
done

echo "==> Patching for ${VENDOR}:${PRODUCT}..."
cd "$BUILDDIR"

# Patch 1: quirks_table — register device as CSR
L=$(grep -n '{ USB_DEVICE(0x0a12, 0x0001), .driver_info = BTUSB_CSR },' btusb.c | head -1 | cut -d: -f1)
insert_after btusb.c "$L" "$(printf '\n\t/* Fake CSR clone - CSR8510 A10 */\n\t{ USB_DEVICE(%s, %s), .driver_info = BTUSB_CSR },' "$VENDOR" "$PRODUCT")"

# Patch 2: interrupt transfer size
L=$(grep -n 'le16_to_cpu(data->udev->descriptor.idVendor)  == 0x0a12' btusb.c | head -1 | cut -d: -f1)
sed -i "${L}s/if (/if ((/" btusb.c
sed -i "$((L+1))s/== 0x0001)/== 0x0001) ||/" btusb.c
insert_after btusb.c "$((L+1))" "$(printf '\t    (le16_to_cpu(data->udev->descriptor.idVendor)  == %s &&\n\t     le16_to_cpu(data->udev->descriptor.idProduct) == %s))' "$VENDOR" "$PRODUCT")"

# Patch 3: setup function
L=$(grep -n 'Fake CSR devices with broken commands' btusb.c | head -1 | cut -d: -f1)
L=$((L+1))
sed -i "${L}s/if (/if ((/" btusb.c
sed -i "$((L+1))s/== 0x0001)/== 0x0001) ||/" btusb.c
insert_after btusb.c "$((L+1))" "$(printf '\t\t    (le16_to_cpu(udev->descriptor.idVendor)  == %s &&\n\t\t     le16_to_cpu(udev->descriptor.idProduct) == %s))' "$VENDOR" "$PRODUCT")"

echo "==> Compiling module..."
cat > Makefile <<'EOF'
KVER ?= $(shell uname -r)
KDIR ?= /lib/modules/$(KVER)/build
obj-m += btusb.o
ccflags-y += -DCONFIG_BT_HCIBTUSB_BCM=1 -DCONFIG_BT_HCIBTUSB_RTL=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_MTK=1 -DCONFIG_BT_HCIBTUSB_AUTOSUSPEND=1
ccflags-y += -DCONFIG_BT_HCIBTUSB_POLL_SYNC=1
all:
        $(MAKE) -C $(KDIR) M=$(PWD) modules
EOF

make KVER="$KVER" 2>&1
test -f btusb.ko || { echo "Error: compilation failed"; exit 1; }

echo "==> Installing module..."
if [[ -f "${MOD_DIR}/btusb.ko.zst" ]]; then
    cp "${MOD_DIR}/btusb.ko.zst" "${MOD_DIR}/btusb.ko.zst.bak"
    zstd -f btusb.ko -o btusb.ko.zst
    cp btusb.ko.zst "${MOD_DIR}/btusb.ko.zst"
elif [[ -f "${MOD_DIR}/btusb.ko.xz" ]]; then
    cp "${MOD_DIR}/btusb.ko.xz" "${MOD_DIR}/btusb.ko.xz.bak"
    xz -f btusb.ko
    cp btusb.ko.xz "${MOD_DIR}/btusb.ko.xz"
else
    echo "Error: btusb.ko.{zst,xz} not found in ${MOD_DIR}"
    exit 1
fi

echo "==> Reloading bluetooth module..."
rmmod btusb 2>/dev/null || true
modprobe btusb

echo "==> Done! Patched module installed. Backup at ${MOD_DIR}/btusb.ko.*.bak"
echo "    To revert: sudo cp ${MOD_DIR}/btusb.ko.*.bak ${MOD_DIR}/btusb.ko.zst"
