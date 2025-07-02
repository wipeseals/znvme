# QEMU Test Environment

This directory contains scripts and configuration for running znvme in a QEMU virtual environment with virtual NVMe devices.

## Quick Start

### Using the QEMU Manager (Recommended)

The unified QEMU manager script provides a simple interface for all operations:

```bash
# Install dependencies
./qemu-manager.sh setup

# Start QEMU with virtual NVMe device
./qemu-manager.sh start

# Check environment status
./qemu-manager.sh status

# Run tests
./qemu-manager.sh test

# Debug with GDB
./qemu-manager.sh debug

# Clean up when done
./qemu-manager.sh clean
```

### Using Individual Scripts

1. **Start QEMU with virtual NVMe device:**
   ```bash
   ./start-qemu.sh
   ```

2. **Connect with GDB for debugging:**
   ```bash
   ./debug-gdb.sh
   ```

3. **Run znvme tests in QEMU:**
   ```bash
   ./run-tests.sh
   ```

## Scripts

- `qemu-manager.sh` - **Unified management script for all QEMU operations**
- `start-qemu.sh` - Start QEMU with virtual NVMe device
- `debug-gdb.sh` - Connect GDB to QEMU for debugging
- `run-tests.sh` - Run znvme tests in QEMU environment
- `setup-guest.sh` - Setup script to run inside QEMU guest
- `ci-test.sh` - CI script for automated testing
- `bind-qemu-nvme.sh` - Auto-detect and bind QEMU virtual NVMe devices
- `test-environment.sh` - Validate QEMU environment setup

## Configuration

- `kernel/` - Kernel configuration and build scripts
- `guest/` - Guest system setup and configuration
- `nvme-devices/` - Virtual NVMe device configurations

## Requirements

- QEMU (qemu-system-x86_64)
- GDB for debugging
- Linux kernel with NVMe and VFIO support
- Root filesystem image