#!/bin/bash -eux
set -o pipefail

# Auto-bind QEMU virtual NVMe devices to VFIO
# This script automatically detects QEMU virtual NVMe devices and binds them to VFIO

echo "=== QEMU NVMe Device Auto-Binder ==="

# Check if we're in a QEMU environment
in_qemu() {
    if dmidecode -s system-manufacturer 2>/dev/null | grep -qi qemu; then
        return 0
    elif grep -q QEMU /proc/cpuinfo 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

if in_qemu; then
    echo "Detected QEMU virtual environment"
else
    echo "Note: Not detected as QEMU environment, but proceeding anyway"
fi

# Find NVMe devices
echo "Searching for NVMe devices..."
nvme_devices=()
while IFS= read -r line; do
    pci_addr=$(echo "$line" | awk '{print $1}')
    nvme_devices+=("$pci_addr")
    echo "Found NVMe device: $pci_addr"
done < <(lspci | grep -i "Non-Volatile memory controller")

if [ ${#nvme_devices[@]} -eq 0 ]; then
    echo "No NVMe devices found!"
    exit 1
fi

echo "Found ${#nvme_devices[@]} NVMe device(s)"

# Process each device
for pci_addr in "${nvme_devices[@]}"; do
    echo ""
    echo "Processing device: $pci_addr"
    
    # Get VID:PID
    vid_pid=$(lspci -n -s "$pci_addr" | awk '{print $3}')
    vid=${vid_pid%%:*}
    pid=${vid_pid##*:}
    
    echo "  PCI Address: $pci_addr"
    echo "  VID: $vid"
    echo "  PID: $pid"
    
    # Check current driver
    if [ -e "/sys/bus/pci/devices/$pci_addr/driver" ]; then
        current_driver=$(basename "$(readlink "/sys/bus/pci/devices/$pci_addr/driver")")
        echo "  Current driver: $current_driver"
        
        if [ "$current_driver" = "vfio-pci" ]; then
            echo "  Already bound to vfio-pci, skipping"
            continue
        fi
    else
        echo "  Current driver: none"
    fi
    
    # Ask for confirmation
    if [ "${AUTO_BIND:-}" != "true" ]; then
        echo -n "Bind this device to vfio-pci? [y/N]: "
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "  Skipping device $pci_addr"
            continue
        fi
    fi
    
    # Bind to vfio-pci
    echo "  Binding to vfio-pci..."
    if ../misc/bind_vfio.sh "$pci_addr" "$vid" "$pid"; then
        echo "  Successfully bound $pci_addr to vfio-pci"
        
        # Show IOMMU group info
        if [ -L "/sys/bus/pci/devices/$pci_addr/iommu_group" ]; then
            group_num=$(basename "$(readlink -f "/sys/bus/pci/devices/$pci_addr/iommu_group")")
            echo "  IOMMU group: $group_num"
            echo "  VFIO device: /dev/vfio/$group_num"
            echo ""
            echo "  You can now use znvme with:"
            echo "    ./znvme $pci_addr $group_num"
        fi
    else
        echo "  Failed to bind $pci_addr to vfio-pci"
    fi
done

echo ""
echo "=== Summary ==="
echo "VFIO-bound NVMe devices:"
lspci -k | grep -A3 -B1 "Non-Volatile memory controller" | grep -A3 -B1 "vfio-pci" || echo "None"

echo ""
echo "Available VFIO devices:"
ls -la /dev/vfio/ 2>/dev/null || echo "None"

echo ""
echo "To unbind devices, use:"
for pci_addr in "${nvme_devices[@]}"; do
    if [ -e "/sys/bus/pci/drivers/vfio-pci/$pci_addr" ]; then
        echo "  ../misc/unbind_vfio.sh $pci_addr"
    fi
done