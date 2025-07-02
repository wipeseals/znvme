#!/bin/bash
# QEMU management script for znvme
# This script provides a unified interface for managing the QEMU test environment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Show help
show_help() {
    cat << EOF
QEMU Test Environment Manager for znvme

Usage: $0 <command> [options]

Commands:
    setup           Install QEMU and dependencies
    start           Start QEMU with virtual NVMe device
    stop            Stop running QEMU instances
    status          Show QEMU environment status
    test            Run environment tests
    build           Build znvme binary
    debug           Start GDB debugging session
    guest-setup     Setup guest environment (run after guest boot)
    bind            Bind virtual NVMe devices to VFIO (in guest)
    unbind          Unbind VFIO devices (in guest)
    ci              Run CI test suite
    clean           Clean up generated files
    help            Show this help message

Environment Variables:
    QEMU_MEMORY     Memory size (default: 2G)
    QEMU_CPUS       Number of CPUs (default: 2)
    QEMU_DEBUG      Enable debugging (true/false)
    QEMU_VNC        VNC display port (default: :1)
    
Examples:
    $0 setup           # Install dependencies
    $0 start           # Start QEMU
    $0 debug           # Debug with GDB
    $0 test            # Run tests
    $0 clean           # Clean up
EOF
}

# Setup function - install dependencies
setup() {
    log_info "Setting up QEMU test environment..."
    
    # Check OS
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command_exists apt-get; then
            log_info "Installing packages with apt-get..."
            sudo apt-get update
            sudo apt-get install -y qemu-system-x86 qemu-utils gdb openssh-client virt-viewer
        elif command_exists yum; then
            log_info "Installing packages with yum..."
            sudo yum install -y qemu-kvm qemu-img gdb openssh-clients virt-viewer
        elif command_exists pacman; then
            log_info "Installing packages with pacman..."
            sudo pacman -S qemu-full gdb openssh virt-viewer
        else
            log_error "Unsupported Linux distribution"
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            log_info "Installing packages with Homebrew..."
            brew install qemu gdb
        else
            log_error "Homebrew not found. Please install Homebrew first."
            exit 1
        fi
    else
        log_error "Unsupported operating system: $OSTYPE"
        exit 1
    fi
    
    log_success "Dependencies installed successfully"
}

# Start QEMU
start() {
    log_info "Starting QEMU with virtual NVMe device..."
    
    if ! command_exists qemu-system-x86_64; then
        log_error "QEMU not found. Run '$0 setup' first."
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
    ./start-qemu.sh
}

# Stop QEMU
stop() {
    log_info "Stopping QEMU instances..."
    pkill -f "qemu-system-x86_64.*znvme" || log_warning "No QEMU instances found"
    log_success "QEMU stopped"
}

# Show status
status() {
    log_info "QEMU Environment Status:"
    echo ""
    
    # Check if QEMU is installed
    if command_exists qemu-system-x86_64; then
        log_success "QEMU is installed: $(qemu-system-x86_64 --version | head -1)"
    else
        log_error "QEMU is not installed"
    fi
    
    # Check if GDB is installed
    if command_exists gdb; then
        log_success "GDB is installed: $(gdb --version | head -1)"
    else
        log_warning "GDB is not installed"
    fi
    
    # Check if QEMU is running
    if pgrep -f "qemu-system-x86_64.*znvme" >/dev/null; then
        log_success "QEMU is running"
        echo "  Processes:"
        pgrep -af "qemu-system-x86_64" | sed 's/^/    /'
    else
        log_info "QEMU is not running"
    fi
    
    # Check for virtual disk images
    echo ""
    log_info "Virtual disk images:"
    for img in "$SCRIPT_DIR"/*.img "$SCRIPT_DIR"/*.qcow2; do
        if [[ -e "$img" ]]; then
            size=$(du -h "$img" | cut -f1)
            echo "  $(basename "$img"): $size"
        fi
    done
    
    # Check ports
    echo ""
    log_info "Network ports:"
    if netstat -tlnp 2>/dev/null | grep -q ":2222"; then
        log_success "SSH port 2222 is listening"
    else
        log_info "SSH port 2222 is not listening"
    fi
    
    if netstat -tlnp 2>/dev/null | grep -q ":4321"; then
        log_success "Serial console port 4321 is listening"
    else
        log_info "Serial console port 4321 is not listening"
    fi
}

# Run tests
test() {
    log_info "Running QEMU environment tests..."
    cd "$SCRIPT_DIR"
    ./test-environment.sh
}

# Build znvme
build() {
    log_info "Building znvme..."
    cd "$ROOT_DIR"
    
    if command_exists zig; then
        zig build
        log_success "znvme built successfully"
    else
        log_error "Zig not found. Please install Zig first."
        exit 1
    fi
}

# Debug with GDB
debug() {
    log_info "Starting GDB debugging session..."
    cd "$SCRIPT_DIR"
    ./debug-gdb.sh
}

# Setup guest environment
guest_setup() {
    log_info "Setting up guest environment..."
    cd "$SCRIPT_DIR"
    ./run-tests.sh
}

# Bind virtual NVMe devices
bind() {
    log_info "Binding virtual NVMe devices to VFIO..."
    cd "$SCRIPT_DIR"
    ./bind-qemu-nvme.sh
}

# Unbind VFIO devices
unbind() {
    log_info "Unbinding VFIO devices..."
    cd "$SCRIPT_DIR"
    
    # Find all NVMe devices bound to vfio-pci
    for pci_addr in $(lspci | grep -i "Non-Volatile memory controller" | awk '{print $1}'); do
        if [[ -e "/sys/bus/pci/drivers/vfio-pci/$pci_addr" ]]; then
            log_info "Unbinding $pci_addr from vfio-pci..."
            ../misc/unbind_vfio.sh "$pci_addr"
        fi
    done
}

# Run CI tests
ci() {
    log_info "Running CI test suite..."
    cd "$SCRIPT_DIR"
    ./ci-test.sh
}

# Clean up
clean() {
    log_info "Cleaning up generated files..."
    cd "$SCRIPT_DIR"
    
    # Stop QEMU first
    stop
    
    # Remove generated files
    rm -f *.img *.qcow2 *.log
    rm -rf test-results/
    
    log_success "Cleanup completed"
}

# Main function
main() {
    case "${1:-help}" in
        setup)
            setup
            ;;
        start)
            start
            ;;
        stop)
            stop
            ;;
        status)
            status
            ;;
        test)
            test
            ;;
        build)
            build
            ;;
        debug)
            debug
            ;;
        guest-setup)
            guest_setup
            ;;
        bind)
            bind
            ;;
        unbind)
            unbind
            ;;
        ci)
            ci
            ;;
        clean)
            clean
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Run main with all arguments
main "$@"