#!/bin/bash -eux
set -o pipefail

# QEMU startup script with virtual NVMe device for znvme testing
# This script starts QEMU with a virtual NVMe device that can be used for testing znvme

# Configuration
QEMU_MEMORY=${QEMU_MEMORY:-2G}
QEMU_CPUS=${QEMU_CPUS:-2}
# Set default kernel paths only if not already set
if [ -z "${QEMU_KERNEL+x}" ]; then
    QEMU_KERNEL="/boot/vmlinuz"
fi
if [ -z "${QEMU_INITRD+x}" ]; then
    QEMU_INITRD="/boot/initrd.img"
fi
QEMU_DRIVE=${QEMU_DRIVE:-guest-disk.qcow2}
QEMU_NVME_SIZE=${QEMU_NVME_SIZE:-1G}
QEMU_VNC=${QEMU_VNC:-:1}
QEMU_DEBUG=${QEMU_DEBUG:-false}
QEMU_NO_KVM=${QEMU_NO_KVM:-false}

# Directories
QEMU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$QEMU_DIR")"

# Create guest disk if it doesn't exist
if [ ! -f "$QEMU_DRIVE" ]; then
    echo "Creating guest disk image: $QEMU_DRIVE"
    qemu-img create -f qcow2 "$QEMU_DRIVE" 10G
fi

# Create virtual NVMe device file if it doesn't exist
NVME_IMAGE="virtual-nvme.img"
if [ ! -f "$NVME_IMAGE" ]; then
    echo "Creating virtual NVMe device: $NVME_IMAGE ($QEMU_NVME_SIZE)"
    qemu-img create -f raw "$NVME_IMAGE" "$QEMU_NVME_SIZE"
fi

# Build QEMU command
QEMU_CMD="qemu-system-x86_64"

# Check KVM availability and configuration
if [ "$QEMU_NO_KVM" = "true" ]; then
    echo "KVM disabled by QEMU_NO_KVM environment variable"
    ACCEL_OPT="tcg"
    MACHINE_OPT="q35"
elif [ -w /dev/kvm ]; then
    echo "KVM available and accessible"
    ACCEL_OPT="kvm"
    MACHINE_OPT="q35,accel=kvm"
elif [ -e /dev/kvm ]; then
    echo "Warning: KVM exists but not accessible, falling back to TCG emulation"
    ACCEL_OPT="tcg"
    MACHINE_OPT="q35"
else
    echo "KVM not available, using TCG emulation"
    ACCEL_OPT="tcg"
    MACHINE_OPT="q35"
fi

QEMU_ARGS=(
    "-m" "$QEMU_MEMORY"
    "-smp" "$QEMU_CPUS"
    "-drive" "file=$QEMU_DRIVE,format=qcow2,if=none,id=hd0"
    "-device" "virtio-blk-pci,drive=hd0"
    # Add virtual NVMe device
    "-drive" "file=$NVME_IMAGE,format=raw,if=none,id=nvme0"
    "-device" "nvme,drive=nvme0,serial=znvme-test-device"
    # Network
    "-netdev" "user,id=net0,hostfwd=tcp::2222-:22"
    "-device" "virtio-net-pci,netdev=net0"
    # Console and display
    "-vnc" "$QEMU_VNC"
    "-monitor" "stdio"
    # Enable IOMMU for VFIO testing (only with KVM)
    "-machine" "$MACHINE_OPT"
)

# Add IOMMU only if using KVM
if [ "$ACCEL_OPT" = "kvm" ]; then
    QEMU_ARGS+=("-device" "intel-iommu,intremap=on")
fi

# Add kernel and initrd if available
if [ -n "$QEMU_KERNEL" ] && [ -f "$QEMU_KERNEL" ]; then
    QEMU_ARGS+=("-kernel" "$QEMU_KERNEL")
fi

if [ -n "$QEMU_INITRD" ] && [ -f "$QEMU_INITRD" ]; then
    QEMU_ARGS+=("-initrd" "$QEMU_INITRD")
fi

# Only add kernel command line if kernel is used
if [ -n "$QEMU_KERNEL" ] && [ -f "$QEMU_KERNEL" ]; then
    # Kernel command line arguments
    KERNEL_CMDLINE="console=ttyS0 intel_iommu=on iommu=pt vfio_iommu_type1.allow_unsafe_interrupts=1"
    QEMU_ARGS+=("-append" "$KERNEL_CMDLINE")
fi

# Add serial console
QEMU_ARGS+=("-serial" "mon:telnet:127.0.0.1:4321,server,nowait")

# Enable debugging if requested
if [ "$QEMU_DEBUG" = "true" ]; then
    echo "Debug mode enabled - QEMU will wait for GDB connection on port 1234"
    QEMU_ARGS+=("-s" "-S")
fi

echo "Starting QEMU with virtual NVMe device..."
echo "Acceleration: $ACCEL_OPT"
echo "Command: $QEMU_CMD ${QEMU_ARGS[*]}"
echo ""
echo "Virtual NVMe device: $NVME_IMAGE ($QEMU_NVME_SIZE)"
echo "VNC display: localhost:590${QEMU_VNC#:}"
echo "Serial console: telnet localhost 4321"
echo "SSH port forwarding: localhost:2222 -> guest:22"
echo ""
echo "Monitor commands:"
echo "  info block - show block devices"
echo "  info pci - show PCI devices"
echo "  quit - shutdown QEMU"
echo ""

# Run QEMU
exec "$QEMU_CMD" "${QEMU_ARGS[@]}"