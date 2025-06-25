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

### Driver Setup

To use this driver, you need to switch your NVMe device from the default kernel `nvme` driver to the `uio_pci_generic` driver, which allows user space programs to access device registers directly.

Scripts for switching drivers are provided in the `misc/` directory.

#### Listing NVMe devices

First, check the NVMe devices connected to your system.  
The following command lists devices currently bound to the `nvme` driver:

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
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

#### Binding to the uio_pci_generic driver

Unbind the NVMe device from the `nvme` driver and bind it to the `uio_pci_generic` driver.  
Example for switching the device at PCI address `0000:06:00.0`:

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/bind_uio.sh 0000:06:00.0 1e0f 000d
Unbound 0000:06:00.0 from nvme driver.
grep: /sys/bus/pci/drivers/uio_pci_generic/new_id: Permission denied
Bound 0000:06:00.0 to uio_pci_generic driver.
Bound 0000:06:00.0 to uio_pci_generic driver.
Successfully bound 0000:06:00.0 to uio_pci_generic driver.
06:00.0 Non-Volatile memory controller: KIOXIA Corporation NVMe SSD Controller XG7
        Subsystem: KIOXIA Corporation NVMe SSD Controller XG7
        Kernel driver in use: uio_pci_generic
        Kernel modules: nvme
```

If you see `Permission denied` for `/sys/bus/pci/drivers/uio_pci_generic/new_id`, make sure you are running as root.  
After binding, confirm `Kernel driver in use: uio_pci_generic`.

##### Checking the unbound device

Devices bound to `uio_pci_generic` will not appear in tools like `nvme`.  
Example after switching:

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo nvme list
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme1n1          /dev/ng1n1            201008800819         WDC WD BLACK SDBPNTY-512G-1106           0x1        512.11  GB / 512.11  GB    512   B +  0 B   HPS2    
/dev/nvme2n1          /dev/ng2n1            TTSMA2513X09608      TWSC TSC3AN512-F8T40S                    0x1        512.11  GB / 512.11  GB    512   B +  0 B   SN13126 
```

#### Unbinding from the uio_pci_generic driver and rebinding to the nvme driver

After your work, you can return the device to the original `nvme` driver:

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo ./misc/unbind_uio.sh 0000:06:00.0
Unbound 0000:06:00.0 from uio_pci_generic driver.
Bound 0000:06:00.0 to nvme driver.
Successfully bound 0000:06:00.0 to nvme driver.
06:00.0 Non-Volatile memory controller: KIOXIA Corporation NVMe SSD Controller XG7
        Subsystem: KIOXIA Corporation NVMe SSD Controller XG7
        Kernel driver in use: nvme
        Kernel modules: nvme
```

##### Listing NVMe devices again

Once rebound to the `nvme` driver, the device will reappear in `nvme list`:

```bash
user in 🌐 nbg9 in toynvme on  master [!?] via ↯ v0.14.1 via ❄️  impure (nix-shell-env) 
❯ sudo nvme list
Node                  Generic               SN                   Model                                    Namespace  Usage                      Format           FW Rev  
--------------------- --------------------- -------------------- ---------------------------------------- ---------- -------------------------- ---------------- --------
/dev/nvme0n1          /dev/ng0n1            Z4HF716NF88S         KIOXIA-EXCERIA with Heatsink SSD         0x1          1.02  TB /   1.02  TB    512   B +  0 B   AJRA4101
/dev/nvme1n1          /dev/ng1n1            201008800819         WDC WD BLACK SDBPNTY-512G-1106           0x1        512.11  GB / 512.11  GB    512   B +  0 B   HPS2    
/dev/nvme2n1          /dev/ng2n1            TTSMA2513X09608      TWSC TSC3AN512-F8T40S                    0x1        512.11  GB / 512.11  GB    512   B +  0 B   SN13126 
```

## References

- [NVMe Specification](https://nvmexpress.org/specifications/)


## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.