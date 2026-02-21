# btusb-csr8510-fix

Patch for the `btusb` kernel module to restore support for fake CSR8510 A10 Bluetooth dongles (`10d7:b012`) broken by an upstream kernel change that only accounted for the original CSR vendor/product ID (`0a12:0001`).

## Problem

A kernel fix for fake CSR Bluetooth adapters hardcodes checks for `0a12:0001` in three places within `drivers/bluetooth/btusb.c`. Other fake CSR clones like `10d7:b012` are not handled, causing them to malfunction or stop working entirely after the update.

## What the patch does

Adds device ID `10d7:b012` to the three relevant code paths in `btusb.c`:

1. **`quirks_table`** — Registers the device with `BTUSB_CSR` driver info so it enters the CSR code path.
2. **Interrupt transfer size** — Uses `wMaxPacketSize` instead of `HCI_MAX_EVENT_SIZE`, matching the behavior required by fake CSR devices.
3. **Setup function** — Routes the device through `btusb_setup_csr()` to handle broken HCI commands.

## Requirements

- Fedora / Nobara (or any distro with `kernel-devel` packages)
- `kernel-devel` for your running kernel
- `gcc`, `make`, `curl`, `zstd`

```bash
sudo dnf install kernel-devel gcc make curl zstd
```

## Usage

```bash
git clone https://github.com/ewood/btusb-csr8510-fix.git
cd btusb-csr8510-fix
sudo ./patch.sh
```

The script will:
1. Download `btusb.c` and headers matching your running kernel
2. Apply the three patches
3. Compile the module
4. Back up the original module
5. Install the patched module
6. Reload `btusb`

## Reverting

```bash
sudo cp /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst.bak \
        /lib/modules/$(uname -r)/kernel/drivers/bluetooth/btusb.ko.zst
sudo rmmod btusb && sudo modprobe btusb
```

## After kernel updates

The patch applies to the compiled module, not the kernel source. You need to re-run the script after every kernel update.

## Verifying your device

Check if your adapter matches the affected device ID:

```bash
lsusb | grep -i 10d7
```

Expected output:
```
Bus XXX Device XXX: ID 10d7:b012 Majesty Internal ... CSR8510 A10
```

This was inspired by this comment: https://discussion.fedoraproject.org/t/bluetooth-not-working-on-fedora-41-csr8510-a10-linux-6-12-4-200-fc41-x86-64/139742/8

This patch modifies Linux kernel source code licensed under [GPL-2.0](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html).

