#!/bin/bash -eux
set -o pipefail

# Test runner script for znvme in QEMU environment
# This script orchestrates the complete testing process

# Configuration
GUEST_USER=${GUEST_USER:-znvme}
GUEST_HOST=${GUEST_HOST:-localhost}
GUEST_PORT=${GUEST_PORT:-2222}
TEST_TIMEOUT=${TEST_TIMEOUT:-120}

# Directories
QEMU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$QEMU_DIR")"

echo "=== znvme QEMU Test Runner ==="

# Function to run command in guest via SSH
run_in_guest() {
    local cmd="$1"
    echo "Running in guest: $cmd"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -p "$GUEST_PORT" "$GUEST_USER@$GUEST_HOST" "$cmd"
}

# Function to copy file to guest
copy_to_guest() {
    local src="$1"
    local dst="$2"
    echo "Copying $src to guest:$dst"
    scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -P "$GUEST_PORT" "$src" "$GUEST_USER@$GUEST_HOST:$dst"
}

# Wait for guest to be ready
wait_for_guest() {
    echo "Waiting for guest to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
               -o ConnectTimeout=5 -p "$GUEST_PORT" "$GUEST_USER@$GUEST_HOST" \
               "echo 'Guest ready'" 2>/dev/null; then
            echo "Guest is ready!"
            return 0
        fi
        
        echo "Attempt $attempt/$max_attempts - guest not ready yet"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    echo "ERROR: Guest did not become ready within expected time"
    return 1
}

# Setup guest environment
setup_guest() {
    echo "Setting up guest environment..."
    
    # Copy setup script
    copy_to_guest "$QEMU_DIR/setup-guest.sh" "/tmp/setup-guest.sh"
    
    # Run setup script
    run_in_guest "sudo /tmp/setup-guest.sh"
    
    echo "Guest setup complete"
}

# Build and copy znvme
deploy_znvme() {
    echo "Deploying znvme to guest..."
    
    # Build znvme if possible
    cd "$ROOT_DIR"
    if command -v zig >/dev/null 2>&1; then
        zig build
        if [ -f "zig-out/bin/znvme" ]; then
            copy_to_guest "zig-out/bin/znvme" "/home/$GUEST_USER/znvme"
            run_in_guest "chmod +x /home/$GUEST_USER/znvme"
        else
            echo "WARNING: znvme binary not found after build"
        fi
    else
        echo "WARNING: zig not available, cannot build znvme"
    fi
    
    # Copy misc scripts
    for script in misc/*.sh; do
        if [ -f "$script" ]; then
            copy_to_guest "$script" "/home/$GUEST_USER/$(basename "$script")"
            run_in_guest "chmod +x /home/$GUEST_USER/$(basename "$script")"
        fi
    done
    
    echo "znvme deployment complete"
}

# Run actual tests
run_znvme_tests() {
    echo "Running znvme tests..."
    
    # Check environment
    run_in_guest "/home/$GUEST_USER/test-znvme.sh"
    
    # List NVMe devices
    echo "Listing NVMe devices in guest..."
    run_in_guest "/home/$GUEST_USER/list.sh" || echo "list.sh not available"
    
    # Test basic functionality
    if run_in_guest "[ -f /home/$GUEST_USER/znvme ]"; then
        echo "Testing znvme binary..."
        # Note: This would need actual PCI addresses and IOMMU group numbers
        # run_in_guest "/home/$GUEST_USER/znvme --help" || echo "znvme help failed"
        echo "znvme binary found - implement specific tests based on available devices"
    else
        echo "znvme binary not found in guest"
    fi
    
    echo "Tests completed"
}

# Main execution
main() {
    echo "Starting znvme test runner..."
    echo "Make sure QEMU is already running with guest SSH access"
    echo ""
    
    # Wait for guest
    if ! wait_for_guest; then
        echo "ERROR: Cannot connect to guest"
        exit 1
    fi
    
    # Setup guest
    setup_guest
    
    # Deploy znvme
    deploy_znvme
    
    # Run tests
    run_znvme_tests
    
    echo "Test runner completed successfully!"
}

# Run if called directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi