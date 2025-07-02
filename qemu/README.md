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

### Core Scripts
- `qemu-manager.sh` - **Unified management script for all QEMU operations**
- `start-qemu.sh` - Start QEMU with virtual NVMe device
- `debug-gdb.sh` - Connect GDB to QEMU for debugging
- `run-tests.sh` - Run znvme tests in QEMU environment
- `setup-guest.sh` - Setup script to run inside QEMU guest
- `ci-test.sh` - CI script for automated testing
- `bind-qemu-nvme.sh` - Auto-detect and bind QEMU virtual NVMe devices
- `test-environment.sh` - Validate QEMU environment setup

### Docker Scripts
- `docker-manager.sh` - **Docker environment management script**
- `Dockerfile` - Docker image definition
- `docker-compose.yml` - Docker Compose configuration
- `test-docker.sh` - Container environment validation
- `demo-docker.sh` - Interactive Docker workflow demo

## Configuration

- `kernel/` - Kernel configuration and build scripts
- `guest/` - Guest system setup and configuration
- `nvme-devices/` - Virtual NVMe device configurations

## Requirements

- QEMU (qemu-system-x86_64)
- GDB for debugging
- Linux kernel with NVMe and VFIO support
- Root filesystem image

## Docker Support

For a consistent and isolated environment, you can use Docker to run the QEMU test environment. This eliminates host system dependencies and provides a reproducible setup.

### Using Docker Manager (Recommended)

The `docker-manager.sh` script provides a simple interface for Docker operations:

```bash
# Build Docker image
./docker-manager.sh build

# Start development environment
./docker-manager.sh up

# Connect to container
./docker-manager.sh shell

# Run tests in container
./docker-manager.sh test

# Clean up
./docker-manager.sh clean
```

### Using Docker Compose (Recommended)

1. **Start the development environment:**
   ```bash
   docker compose up -d
   ```

2. **Connect to the container:**
   ```bash
   docker compose exec znvme-qemu bash
   ```

3. **Inside the container, use QEMU manager:**
   ```bash
   # Setup environment (already done in container)
   ./qemu-manager.sh status
   
   # Start QEMU with virtual NVMe
   ./qemu-manager.sh start
   
   # Run tests
   ./qemu-manager.sh test
   ```

4. **Clean up:**
   ```bash
   docker compose down
   ```

### Using Docker Directly

1. **Build the Docker image:**
   ```bash
   docker build -t znvme-qemu -f Dockerfile ..
   ```

2. **Run the container:**
   ```bash
   docker run -it --privileged \
     --device /dev/kvm:/dev/kvm \
     -p 2222:2222 -p 5901:5901 -p 4321:4321 \
     -v $(pwd)/..:/workspace/znvme \
     znvme-qemu
   ```

### Docker Configuration

**Environment Variables:**
- `QEMU_MEMORY` - Memory allocation (default: 4G in Docker)
- `QEMU_CPUS` - Number of CPUs (default: 4 in Docker)
- `QEMU_NO_KVM` - Disable KVM acceleration (default: false)
- `QEMU_DEBUG` - Enable debugging mode (default: false)

**Ports:**
- `2222` - SSH forwarding to QEMU guest
- `5901` - VNC display for guest console
- `4321` - QEMU monitor/serial console

**Volumes:**
- Source code mounted at `/workspace/znvme`
- Persistent data volume for QEMU disk images
- Optional X11 socket for GUI applications

### CI/Automated Testing

For automated testing environments:

```bash
# Run CI tests
docker compose --profile ci up znvme-qemu-ci

# Or with environment overrides
docker run --rm \
  -e QEMU_NO_KVM=true \
  -e QEMU_MEMORY=2G \
  -v $(pwd)/..:/workspace/znvme \
  znvme-qemu ./qemu-manager.sh test
```

### Docker Demo

For a comprehensive walkthrough, run the Docker demo:

```bash
./demo-docker.sh
```

This interactive demo shows:
- Step-by-step Docker workflow
- Available commands and options
- Development workflow examples
- Benefits of the Docker approach

### Benefits of Docker Approach

- **Consistent Environment**: Same setup across different host systems
- **Dependency Isolation**: No need to install QEMU/GDB on host
- **Easy CI Integration**: Container can run in any Docker-enabled CI
- **Reproducible Results**: Eliminates host configuration differences
- **Safe Testing**: Isolated from host system changes
- **Quick Setup**: Single command to get development environment