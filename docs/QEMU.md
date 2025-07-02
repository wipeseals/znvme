# QEMU Test Environment Guide

This guide explains how to set up and use the QEMU test environment for znvme development and testing.

## Overview

The QEMU test environment provides:
- Virtual NVMe devices for testing without physical hardware
- Debugging capabilities with GDB integration
- Automated CI/CD testing in GitHub Actions
- Isolation from host system during development

## Quick Start

### Prerequisites

Install required packages on Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install -y qemu-system-x86 qemu-utils gdb openssh-client
```

### Basic Usage

1. **Start QEMU with virtual NVMe device:**
   ```bash
   cd qemu
   ./start-qemu.sh
   ```

2. **Connect to the running guest:**
   ```bash
   # Via VNC (graphical)
   vncviewer localhost:5901
   
   # Via serial console (text)
   telnet localhost 4321
   
   # Via SSH (once guest is configured)
   ssh -p 2222 znvme@localhost
   ```

3. **Run tests in the guest:**
   ```bash
   ./run-tests.sh
   ```

## Detailed Setup

### QEMU Configuration

The `start-qemu.sh` script creates a QEMU environment with:
- **Virtual NVMe device**: 1GB raw disk image (`virtual-nvme.img`)
- **Intel IOMMU**: Enabled for VFIO testing
- **Memory**: 2GB (configurable with `QEMU_MEMORY`)
- **CPUs**: 2 cores (configurable with `QEMU_CPUS`)
- **Networking**: NAT with SSH port forwarding (2222 → 22)
- **Display**: VNC on port 5901
- **Serial console**: Telnet on port 4321

### Environment Variables

Customize the QEMU environment:
```bash
export QEMU_MEMORY=4G          # Memory size
export QEMU_CPUS=4             # Number of CPUs
export QEMU_NVME_SIZE=2G       # Virtual NVMe device size
export QEMU_DEBUG=true         # Enable GDB debugging
export QEMU_VNC=:2             # VNC display port
```

### Guest OS Setup

The guest OS should be configured with:
- Linux kernel with NVMe and VFIO support
- IOMMU enabled in kernel command line
- Required packages: `build-essential`, `pciutils`, `nvme-cli`, `gdb`
- VFIO modules loaded
- SSH server for remote access

Use `setup-guest.sh` to automate guest configuration:
```bash
# Inside the QEMU guest
sudo /path/to/setup-guest.sh
```

## Development Workflow

### Testing Cycle

1. **Modify znvme code**
2. **Build**: `zig build`
3. **Deploy to guest**: Copy binary via SSH/SCP
4. **Test**: Run znvme against virtual NVMe device
5. **Debug**: Use GDB if needed
6. **Iterate**

### Device Management

Use the enhanced device listing:
```bash
# In guest or via SSH
./list-enhanced.sh
```

Bind virtual NVMe device to VFIO:
```bash
# Find device info from list-enhanced.sh output
sudo ./bind_vfio.sh 00:04.0 1b36 0010  # Example PCI address and IDs

# Test znvme
./znvme 00:04.0 0  # PCI address and IOMMU group

# Unbind when done
sudo ./unbind_vfio.sh 00:04.0
```

## Debugging

### GDB Integration

Start QEMU with debugging enabled:
```bash
QEMU_DEBUG=true ./start-qemu.sh
```

Connect GDB from another terminal:
```bash
./debug-gdb.sh
```

Available GDB commands:
- `qemu-info` - Show QEMU system information
- `qemu-nvme-info` - Show NVMe device information
- `setup-nvme-breakpoints` - Set common breakpoints
- `help-znvme` - Show help

### Logging and Monitoring

QEMU provides several monitoring interfaces:
- **Monitor console**: Available in QEMU stdio
- **Serial console**: `telnet localhost 4321`
- **VNC display**: `vncviewer localhost:5901`

Useful monitor commands:
```
(qemu) info block          # Show block devices
(qemu) info pci            # Show PCI devices
(qemu) info registers      # Show CPU registers
(qemu) info tlb            # Show TLB entries
```

### Common Issues

1. **NVMe device not visible**
   - Check QEMU command line includes NVMe device
   - Verify guest kernel has NVMe support
   - Check `lspci | grep -i nvme`

2. **VFIO binding fails**
   - Ensure IOMMU is enabled in kernel command line
   - Check VFIO modules are loaded: `lsmod | grep vfio`
   - Verify IOMMU groups: `find /sys/kernel/iommu_groups -type l`

3. **Permission errors**
   - Check VFIO device permissions: `ls -la /dev/vfio/`
   - Ensure user is in correct groups
   - May need `sudo` for device operations

## CI/CD Integration

### GitHub Actions

The workflow runs automatically on push/PR:
- Builds znvme with Zig
- Starts QEMU environment
- Runs test suite
- Uploads test results as artifacts

### Local CI Testing

Run the same tests locally:
```bash
cd qemu
./ci-test.sh
```

Test results are saved in `test-results/` directory.

## Advanced Usage

### Custom Kernel

To use a custom kernel:
```bash
export QEMU_KERNEL=/path/to/vmlinuz
export QEMU_INITRD=/path/to/initrd.img
./start-qemu.sh
```

### Multiple NVMe Devices

Modify `start-qemu.sh` to add more NVMe devices:
```bash
# Add to QEMU_ARGS
"-drive" "file=nvme2.img,format=raw,id=nvme1"
"-device" "nvme,drive=nvme1,serial=znvme-test-device-2"
```

### Performance Testing

For performance testing, consider:
- Increasing QEMU memory and CPU allocation
- Using KVM acceleration (`-enable-kvm`)
- Optimizing virtual disk performance
- Monitoring host system resources

## Troubleshooting

### QEMU Won't Start

1. Check virtualization support: `grep -E "(vmx|svm)" /proc/cpuinfo`
2. Verify KVM access: `ls -la /dev/kvm`
3. Check QEMU version: `qemu-system-x86_64 --version`
4. Review error messages in QEMU output

### Guest Boot Issues

1. Verify kernel and initrd paths
2. Check kernel command line parameters
3. Ensure sufficient memory allocation
4. Review guest boot messages

### Network Issues

1. Check port forwarding: `netstat -tlnp | grep 2222`
2. Verify guest SSH service: `systemctl status ssh`
3. Test guest connectivity: `ping` from within guest

## Files and Scripts

### Scripts
- `start-qemu.sh` - Main QEMU startup script
- `debug-gdb.sh` - GDB debugging helper
- `run-tests.sh` - Test orchestration
- `setup-guest.sh` - Guest environment setup
- `ci-test.sh` - CI/CD test runner
- `list-enhanced.sh` - Enhanced device listing

### Configuration Files
- Virtual disk images (`.img`, `.qcow2`)
- Guest OS images
- Kernel and initrd files

### Generated Files
- `test-results/` - Test output and logs
- `/tmp/gdb_init_znvme` - GDB initialization
- QEMU monitor and log files

## Contributing

When adding new features to the QEMU environment:
1. Update relevant scripts
2. Test with both virtual and physical devices
3. Update documentation
4. Add CI tests if applicable
5. Consider backward compatibility

## References

- [QEMU Documentation](https://www.qemu.org/docs/master/)
- [NVMe Specification](https://nvmexpress.org/specifications/)
- [VFIO Documentation](https://www.kernel.org/doc/Documentation/vfio.txt)
- [GDB Manual](https://www.gnu.org/software/gdb/documentation/)