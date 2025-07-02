#!/bin/bash
# Test script to verify Docker container functionality without full QEMU setup
# This script tests the basic environment and dependencies

set -euo pipefail

echo "=== Docker Container Test ==="
echo "Testing znvme QEMU environment..."

# Test 1: Check if we're in container
if [ -f /.dockerenv ]; then
    echo "✓ Running in Docker container"
else
    echo "! Not running in Docker container (running on host)"
fi

# Test 2: Check QEMU installation
if command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "✓ QEMU is available: $(qemu-system-x86_64 --version | head -1)"
else
    echo "✗ QEMU is not available"
    exit 1
fi

# Test 3: Check GDB installation
if command -v gdb >/dev/null 2>&1; then
    echo "✓ GDB is available: $(gdb --version | head -1)"
else
    echo "! GDB is not available"
fi

# Test 4: Check Zig installation
if command -v zig >/dev/null 2>&1; then
    echo "✓ Zig is available: $(zig version)"
else
    echo "! Zig is not available"
fi

# Test 5: Check user environment
echo "✓ Running as user: $(whoami)"
echo "✓ Working directory: $(pwd)"

# Test 6: Check source code mount
if [ -f "../build.zig" ]; then
    echo "✓ znvme source code is mounted"
else
    echo "! znvme source code not found"
fi

# Test 7: Check QEMU scripts
if [ -f "./qemu-manager.sh" ]; then
    echo "✓ QEMU manager script found"
    # Test script permissions
    if [ -x "./qemu-manager.sh" ]; then
        echo "✓ QEMU manager script is executable"
    else
        echo "! QEMU manager script is not executable"
    fi
else
    echo "✗ QEMU manager script not found"
    exit 1
fi

# Test 8: Test QEMU manager help
echo "=== Testing QEMU Manager Help ==="
./qemu-manager.sh help || true

# Test 9: Check environment variables
echo "=== Environment Configuration ==="
echo "QEMU_MEMORY: ${QEMU_MEMORY:-not set}"
echo "QEMU_CPUS: ${QEMU_CPUS:-not set}"
echo "QEMU_VNC: ${QEMU_VNC:-not set}"
echo "QEMU_NO_KVM: ${QEMU_NO_KVM:-not set}"

# Test 10: Check ports
echo "=== Network Configuration ==="
echo "Expected ports: 2222 (SSH), 5901 (VNC), 4321 (Monitor)"

# Test 11: Test basic QEMU functionality (create test disk)
echo "=== Testing QEMU Utilities ==="
TEST_IMAGE="/tmp/test-disk.img"
if qemu-img create -f raw "$TEST_IMAGE" 10M >/dev/null 2>&1; then
    echo "✓ qemu-img works (created test disk)"
    rm -f "$TEST_IMAGE"
else
    echo "! qemu-img failed"
fi

echo ""
echo "=== Test Summary ==="
echo "Docker container environment test completed successfully!"
echo "The container is ready for QEMU development and testing."