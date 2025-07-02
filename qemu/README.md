# QEMU Test Environment

This directory contains scripts and configuration for running znvme in a QEMU virtual environment with virtual NVMe devices.

## Quick Start

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

- `start-qemu.sh` - Start QEMU with virtual NVMe device
- `debug-gdb.sh` - Connect GDB to QEMU for debugging
- `run-tests.sh` - Run znvme tests in QEMU environment
- `setup-guest.sh` - Setup script to run inside QEMU guest
- `ci-test.sh` - CI script for automated testing

## Configuration

- `kernel/` - Kernel configuration and build scripts
- `guest/` - Guest system setup and configuration
- `nvme-devices/` - Virtual NVMe device configurations

## Requirements

- QEMU (qemu-system-x86_64)
- GDB for debugging
- Linux kernel with NVMe and VFIO support
- Root filesystem image