#!/bin/bash
# Demo script showing how to use the Docker QEMU environment
# This provides a step-by-step example of the Docker workflow

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_header() {
    echo ""
    echo "============================================="
    echo "$1"
    echo "============================================="
}

show_header "Docker QEMU Environment Demo"
echo "This demo shows how to use Docker for znvme QEMU development."
echo ""

log_info "Checking Docker availability..."
if ! command -v docker >/dev/null 2>&1; then
    log_error "Docker is not installed or not in PATH"
    exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
    log_error "Docker Compose v2 is not available"
    exit 1
fi

log_success "Docker environment is available"

show_header "Step 1: Build Docker Image"
echo "Building the znvme QEMU Docker image..."
echo "Command: ./docker-manager.sh build"
echo ""
read -p "Press Enter to continue or Ctrl+C to skip..."

# Note: In actual use, this would run the build
echo "$ ./docker-manager.sh build"
echo ""
log_info "This would build a Docker image with:"
echo "  - Ubuntu 22.04 base"
echo "  - QEMU and development tools"
echo "  - Zig toolchain"
echo "  - znvme source code"
echo ""

show_header "Step 2: Start Development Environment"
echo "Starting the Docker container for development..."
echo "Command: ./docker-manager.sh up"
echo ""

echo "$ ./docker-manager.sh up"
echo ""
log_info "This would start a container with:"
echo "  - Port 2222: SSH forwarding to QEMU guest"
echo "  - Port 5901: VNC display"
echo "  - Port 4321: QEMU monitor"
echo "  - Source code mounted for live editing"
echo "  - Persistent storage for QEMU disk images"
echo ""

show_header "Step 3: Connect to Container"
echo "Opening a shell in the running container..."
echo "Command: ./docker-manager.sh shell"
echo ""

echo "$ ./docker-manager.sh shell"
echo "znvme@container:/workspace/znvme/qemu$ "
echo ""
log_info "Inside the container, you can use:"
echo "  ./qemu-manager.sh setup    # Setup environment"
echo "  ./qemu-manager.sh start    # Start QEMU with virtual NVMe"
echo "  ./qemu-manager.sh test     # Run tests"
echo "  ./qemu-manager.sh debug    # Start GDB debugging"
echo ""

show_header "Step 4: Development Workflow"
echo "Typical development workflow in the container:"
echo ""
echo "1. Build znvme:"
echo "   znvme@container:~$ cd /workspace/znvme"
echo "   znvme@container:~$ zig build"
echo ""
echo "2. Start QEMU with virtual NVMe device:"
echo "   znvme@container:~$ cd qemu"
echo "   znvme@container:~$ ./qemu-manager.sh start"
echo ""
echo "3. In another terminal/shell:"
echo "   $ ./docker-manager.sh shell"
echo "   znvme@container:~$ ./qemu-manager.sh debug"
echo ""

show_header "Step 5: Running Tests"
echo "Running comprehensive tests in the container..."
echo "Command: ./docker-manager.sh test"
echo ""

echo "$ ./docker-manager.sh test"
echo ""
log_info "This would run tests including:"
echo "  - Environment validation"
echo "  - QEMU functionality tests"
echo "  - Virtual NVMe device creation"
echo "  - Network connectivity checks"
echo ""

show_header "Step 6: CI/Automated Testing"
echo "For CI environments without KVM support..."
echo "Command: ./docker-manager.sh ci"
echo ""

echo "$ ./docker-manager.sh ci"
echo ""
log_info "This runs tests with QEMU_NO_KVM=true for CI environments"
echo ""

show_header "Step 7: Cleanup"
echo "Cleaning up the Docker environment..."
echo "Command: ./docker-manager.sh clean"
echo ""

echo "$ ./docker-manager.sh clean"
echo ""
log_info "This would:"
echo "  - Stop all containers"
echo "  - Remove Docker images"
echo "  - Optionally remove data volumes"
echo ""

show_header "Available Docker Commands"
echo ""
echo "Build and Management:"
echo "  ./docker-manager.sh build     # Build Docker image"
echo "  ./docker-manager.sh up        # Start environment"
echo "  ./docker-manager.sh down      # Stop environment"
echo "  ./docker-manager.sh status    # Show status"
echo ""
echo "Development:"
echo "  ./docker-manager.sh shell     # Open container shell"
echo "  ./docker-manager.sh logs      # Show container logs"
echo ""
echo "Testing:"
echo "  ./docker-manager.sh test      # Run development tests"
echo "  ./docker-manager.sh ci        # Run CI tests (no KVM)"
echo ""
echo "Cleanup:"
echo "  ./docker-manager.sh clean     # Clean up everything"
echo ""

show_header "Docker Compose Direct Usage"
echo ""
echo "Alternative: Use docker compose directly:"
echo ""
echo "  # Build and start"
echo "  docker compose up -d"
echo ""
echo "  # Connect to container"
echo "  docker compose exec znvme-qemu bash"
echo ""
echo "  # Stop"
echo "  docker compose down"
echo ""
echo "  # Run CI tests"
echo "  docker compose --profile ci up znvme-qemu-ci"
echo ""

show_header "Benefits of Docker Approach"
echo ""
log_success "✓ Consistent Environment: Same setup across different hosts"
log_success "✓ Dependency Isolation: No need to install QEMU/GDB on host"
log_success "✓ Easy CI Integration: Container runs in any Docker-enabled CI"
log_success "✓ Reproducible Results: Eliminates host configuration differences"
log_success "✓ Safe Testing: Isolated from host system changes"
log_success "✓ Quick Setup: Single command to get development environment"
echo ""

show_header "Next Steps"
echo ""
echo "To start using the Docker environment:"
echo ""
echo "1. Build the environment:"
echo "   ./docker-manager.sh build"
echo ""
echo "2. Start development:"
echo "   ./docker-manager.sh up"
echo "   ./docker-manager.sh shell"
echo ""
echo "3. Inside container:"
echo "   ./qemu-manager.sh start"
echo ""
echo "For more information, see:"
echo "  - qemu/README.md (Docker section)"
echo "  - docs/QEMU.md (comprehensive guide)"
echo ""

log_success "Demo completed! Ready to use Docker for znvme QEMU development."