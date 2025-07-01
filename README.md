# znvme

[![zig test](https://github.com/wipeseals/znvme/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/wipeseals/znvme/actions/workflows/test.yml)

A Zig library for accessing NVMe devices in user space.  
This library provides a user space interface to NVMe devices, allowing direct access to device registers and features without needing to go through the kernel's NVMe driver.

## Features

- Direct access to NVMe device registers and features from user space.
- Support for multiple NVMe devices.
- Easy integration with Zig applications.

## Requirements

- Zig 0.14.0 or later
- Linux kernel with `uio_pci_generic` support
- NVMe devices connected to the system

## Installation

To use this library, you need to clone the repository and build the Zig package.

```bash
git clone https://github.com/wipeseals/znvme.git
cd znvme
zig build test
```

## Usage


### Basic Example

TODO

### Advanced Example

TODO

## IOMMU Setup

Ensure the kernel command line includes `intel_iommu=on` or `amd_iommu=on` depending on your CPU architecture.

```bash
cat /proc/cmdline
sudo dmesg | grep -e DMAR -e IOMMU
```

#### For Intel CPUs

Add `intel_iommu=on` to the kernel command line in your bootloader configuration (e.g., GRUB):

```bash
sudo vim /etc/default/grub
```

```text
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on"
```

Then update GRUB

```bash
sudo update-grub
```

## VFIO Setup

To access NVMe devices from user space, you need to switch the kernel driver from `nvme` to `vfio-pci`.

Driver switching scripts are available in the `misc/` directory.

#### Listing NVMe devices

First, check the NVMe devices connected to your system.  
The following command lists devices currently bound to the `nvme` driver:

```bash
user in 🌐 nbg9 in znvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/list.sh
# Listing NVMe devices
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme0n1          /dev/ng0n1            Z4HF716NF88S         KIOXIA-EXCERIA with Heatsink SSD         0x1          1.02  TB /   1.02  TB    512   B +  0 B   AJRA4101
/dev/nvme1n1          /dev/ng1n1            201008800819         WDC WD BLACK SDBPNTY-512G-1106           0x1        512.11  GB / 512.11  GB    512   B +  0 B   HPS2    
/dev/nvme2n1          /dev/ng2n1            TTSMA2513X09608      TWSC TSC3AN512-F8T40S                    0x1        512.11  GB / 512.11  GB    512   B +  0 B   SN13126 

# Listing NVMe devices with PCI addresses, VID, PID, and manufacturer/model info
PCI Address: 01:00.0, VID: 15b7, PID: 5006, Info: Sandisk Corp SanDisk Extreme Pro / WD Black SN750 / PC SN730 / Red SN700 NVMe SSD
PCI Address: 06:00.0, VID: 1e0f, PID: 000d, Info: KIOXIA Corporation NVMe SSD Controller XG7
PCI Address: 07:00.0, VID: 1e4b, PID: 1202, Info: MAXIO Technology (Hangzhou) Ltd. NVMe SSD Controller MAP1202 (DRAM-less) (rev 01)
```

You can also check each device's PCI address, vendor ID, and product ID.  
This information is required for driver switching.

#### Binding to the vfio-pci driver

Unbind the NVMe device from the `nvme` driver and bind it to the `vfio-pci` driver.  
Example for switching the device at PCI address `0000:06:00.0`:

```bash
user in 🌐 nbg9 in znvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/bind_vfio.sh 0000:06:00.0 1e0f 000d
Unbound 0000:06:00.0 from nvme driver.
grep: /sys/bus/pci/drivers/vfio-pci/new_id: Permission denied
Bound 0000:06:00.0 to vfio-pci driver.
Bound 0000:06:00.0 to vfio-pci driver.
Successfully bound 0000:06:00.0 to vfio-pci driver.
06:00.0 Non-Volatile memory controller: KIOXIA Corporation NVMe SSD Controller XG7
        Subsystem: KIOXIA Corporation NVMe SSD Controller XG7
        Kernel driver in use: vfio-pci
        Kernel modules: nvme
```

If you see `Permission denied` for `/sys/bus/pci/drivers/vfio-pci/new_id`, make sure you are running as root.  
After binding, confirm `Kernel driver in use: vfio-pci`.


#### Unbinding from the vfio-pci driver and rebinding to the nvme driver

After your work, you can return the device to the original `nvme` driver:

```bash
user in 🌐 nbg9 in znvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/unbind_vfio.sh 0000:06:00.0
Unbound 0000:06:00.0 from vfio-pci driver.
Bound 0000:06:00.0 to nvme driver.
Successfully bound 0000:06:00.0 to nvme driver.
06:00.0 Non-Volatile memory controller: KIOXIA Corporation NVMe SSD Controller XG7
        Subsystem: KIOXIA Corporation NVMe SSD Controller XG7
        Kernel driver in use: nvme
        Kernel modules: nvme
```

## References

- [NVMe Specification](https://nvmexpress.org/specifications/)
  - [NVM Express Base Specification Revision 2.1](https://nvmexpress.org/wp-content/uploads/NVM-Express-Base-Specification-Revision-2.1-2024.08.05-Ratified.pdf)
  - [NVM Express PCI Express Transport Specification Revision 1.1](https://nvmexpress.org/wp-content/uploads/NVM-Express-PCI-Express-Transport-Specification-Revision-1.1-2024.08.05-Ratified.pdf)


## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.