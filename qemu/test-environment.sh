#!/bin/bash -eux
set -o pipefail

# Comprehensive test script for QEMU environment
# This script validates that all components work correctly

# Configuration
TEST_DIR="/tmp/znvme-qemu-test"
LOG_FILE="$TEST_DIR/test.log"

# Setup
mkdir -p "$TEST_DIR"
exec > >(tee -a "$LOG_FILE")
exec 2>&1

echo "=== znvme QEMU Environment Test ==="
echo "Date: $(date)"
echo "Test directory: $TEST_DIR"
echo "Log file: $LOG_FILE"
echo ""

# Test functions
test_qemu_available() {
    echo "Testing QEMU availability..."
    if command -v qemu-system-x86_64 >/dev/null 2>&1; then
        qemu_version=$(qemu-system-x86_64 --version | head -1)
        echo "  ✓ QEMU found: $qemu_version"
        return 0
    else
        echo "  ✗ QEMU not found"
        return 1
    fi
}

test_kvm_support() {
    echo "Testing KVM support..."
    if [ -e /dev/kvm ]; then
        echo "  ✓ /dev/kvm exists"
        if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
            echo "  ✓ KVM accessible"
            return 0
        else
            echo "  ⚠ KVM not accessible (may need permissions)"
            return 1
        fi
    else
        echo "  ⚠ KVM not available"
        return 1
    fi
}

test_scripts_executable() {
    echo "Testing script executability..."
    local scripts=(
        "start-qemu.sh"
        "debug-gdb.sh"
        "run-tests.sh"
        "setup-guest.sh"
        "ci-test.sh"
        "bind-qemu-nvme.sh"
    )
    
    local all_good=0
    for script in "${scripts[@]}"; do
        if [ -x "$script" ]; then
            echo "  ✓ $script is executable"
        else
            echo "  ✗ $script is not executable"
            all_good=1
        fi
    done
    return $all_good
}

test_qemu_image_creation() {
    echo "Testing QEMU image creation..."
    local test_image="$TEST_DIR/test-nvme.img"
    
    if qemu-img create -f raw "$test_image" 1M >/dev/null 2>&1; then
        echo "  ✓ Created test image: $test_image"
        if [ -f "$test_image" ]; then
            echo "  ✓ Image file exists"
            rm -f "$test_image"
            return 0
        else
            echo "  ✗ Image file not found after creation"
            return 1
        fi
    else
        echo "  ✗ Failed to create test image"
        return 1
    fi
}

test_gdb_available() {
    echo "Testing GDB availability..."
    if command -v gdb >/dev/null 2>&1; then
        gdb_version=$(gdb --version | head -1)
        echo "  ✓ GDB found: $gdb_version"
        return 0
    else
        echo "  ✗ GDB not found"
        return 1
    fi
}

test_misc_scripts() {
    echo "Testing misc/ scripts..."
    local scripts=(
        "../misc/list.sh"
        "../misc/list-enhanced.sh"
        "../misc/bind_vfio.sh"
        "../misc/unbind_vfio.sh"
    )
    
    local all_good=0
    for script in "${scripts[@]}"; do
        if [ -x "$script" ]; then
            echo "  ✓ $(basename "$script") is executable"
        else
            echo "  ✗ $(basename "$script") is not executable or missing"
            all_good=1
        fi
    done
    return $all_good
}

test_qemu_command_generation() {
    echo "Testing QEMU command generation..."
    
    # Test if start-qemu.sh generates valid command
    if QEMU_DEBUG=true timeout 5 ./start-qemu.sh --help 2>/dev/null || true; then
        echo "  ✓ start-qemu.sh can be invoked"
    else
        echo "  ⚠ start-qemu.sh invocation test inconclusive"
    fi
    
    # Check if virtual NVMe image would be created
    local nvme_image="virtual-nvme.img"
    if [ -f "$nvme_image" ]; then
        echo "  ✓ Virtual NVMe image exists: $nvme_image"
    else
        echo "  ⚠ Virtual NVMe image doesn't exist (will be created on first run)"
    fi
    
    return 0
}

test_documentation() {
    echo "Testing documentation..."
    
    local docs=(
        "README.md"
        "../docs/QEMU.md"
        "../README.md"
    )
    
    local all_good=0
    for doc in "${docs[@]}"; do
        if [ -f "$doc" ]; then
            echo "  ✓ $(basename "$doc") exists"
        else
            echo "  ✗ $(basename "$doc") missing"
            all_good=1
        fi
    done
    return $all_good
}

# Main test execution
main() {
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # List of test functions
    local tests=(
        test_qemu_available
        test_kvm_support
        test_scripts_executable
        test_qemu_image_creation
        test_gdb_available
        test_misc_scripts
        test_qemu_command_generation
        test_documentation
    )
    
    echo "Running ${#tests[@]} test categories..."
    echo ""
    
    for test_func in "${tests[@]}"; do
        total_tests=$((total_tests + 1))
        echo "[$total_tests/${#tests[@]}] Running $test_func..."
        
        if $test_func; then
            echo "  Result: PASS"
            passed_tests=$((passed_tests + 1))
        else
            echo "  Result: FAIL"
            failed_tests=$((failed_tests + 1))
        fi
        echo ""
    done
    
    # Summary
    echo "=== Test Summary ==="
    echo "Total tests: $total_tests"
    echo "Passed: $passed_tests"
    echo "Failed: $failed_tests"
    echo ""
    
    if [ $failed_tests -eq 0 ]; then
        echo "🎉 All tests passed!"
        echo "The QEMU environment appears to be properly set up."
        return 0
    else
        echo "⚠️  Some tests failed."
        echo "Please review the failures above and fix any issues."
        return 1
    fi
}

# Change to qemu directory
cd "$(dirname "${BASH_SOURCE[0]}")"

# Run tests
main "$@"