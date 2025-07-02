#!/bin/bash -eux
set -o pipefail

# Enhanced NVMe device listing script that works well with QEMU virtual devices
# This extends the functionality of the existing list.sh to provide more detailed information

echo "# Enhanced NVMe device listing for QEMU environment"
echo "# Date: $(date)"
echo ""

# Check if running in QEMU
if dmidecode -s system-manufacturer 2>/dev/null | grep -qi qemu; then
    echo "# Detected QEMU virtual environment"
elif grep -q QEMU /proc/cpuinfo 2>/dev/null; then
    echo "# Detected QEMU virtual environment"
else
    echo "# Physical hardware or other virtualization"
fi
echo ""

# Original NVMe list functionality (if nvme-cli is available)
if command -v nvme >/dev/null 2>&1; then
    echo "# NVMe devices (nvme-cli)"
    nvme list 2>/dev/null || echo "No NVMe devices found by nvme-cli"
    echo ""
fi

echo "# PCI NVMe controllers"
if lspci | grep -i "Non-Volatile memory controller" >/dev/null; then
    lspci | grep -i "Non-Volatile memory controller" | while read -r line; do
        # Extract the PCI address from the line
        pci_address=$(echo "$line" | awk '{print $1}')
        
        # Get VID:PID using lspci -n
        vid_pid=$(lspci -n -s "$pci_address" | awk '{print $3}')
        vid=${vid_pid%%:*}
        pid=${vid_pid##*:}

        echo "PCI Address: $pci_address, VID: $vid, PID: $pid, Info: ${line#* }"
        
        # Show detailed device information
        echo "  Detailed information:"
        lspci -s "$pci_address" -vvv | sed 's/^/    /'
        
        # Check driver binding
        if [ -e "/sys/bus/pci/devices/$pci_address/driver" ]; then
            driver=$(basename "$(readlink "/sys/bus/pci/devices/$pci_address/driver")")
            echo "  Current driver: $driver"
        else
            echo "  Current driver: none"
        fi
        
        # Check IOMMU group
        if [ -L "/sys/bus/pci/devices/$pci_address/iommu_group" ]; then
            group_num=$(basename "$(readlink -f "/sys/bus/pci/devices/$pci_address/iommu_group")")
            echo "  IOMMU group: $group_num"
            
            # Check VFIO device
            if [ -e "/dev/vfio/$group_num" ]; then
                vfio_perms=$(ls -l "/dev/vfio/$group_num" | awk '{print $1, $3, $4}')
                echo "  VFIO device: /dev/vfio/$group_num ($vfio_perms)"
            else
                echo "  VFIO device: not available"
            fi
        else
            echo "  IOMMU group: not available"
        fi
        
        echo ""
    done
else
    echo "No NVMe controllers found"
fi

# Show IOMMU status
echo "# IOMMU status"
if dmesg | grep -i "dmar\|iommu" | tail -3 >/dev/null; then
    echo "IOMMU messages from dmesg:"
    dmesg | grep -i "dmar\|iommu" | tail -3 | sed 's/^/  /'
else
    echo "No IOMMU messages found in dmesg"
fi
echo ""

# Show VFIO status
echo "# VFIO status"
if [ -d /dev/vfio ]; then
    echo "VFIO devices:"
    ls -la /dev/vfio/ | sed 's/^/  /'
else
    echo "VFIO not available (/dev/vfio not found)"
fi
echo ""

# Show loaded modules relevant to NVMe and VFIO
echo "# Relevant kernel modules"
echo "Loaded modules:"
lsmod | grep -E "(nvme|vfio)" | sed 's/^/  /' || echo "  No relevant modules loaded"
echo ""

# Check kernel command line for IOMMU settings
echo "# Kernel command line"
if grep -q "intel_iommu=on\|amd_iommu=on\|iommu=pt" /proc/cmdline; then
    echo "IOMMU appears to be enabled:"
    cat /proc/cmdline | sed 's/^/  /'
else
    echo "IOMMU may not be enabled in kernel command line:"
    cat /proc/cmdline | sed 's/^/  /'
    echo ""
    echo "Consider adding: intel_iommu=on iommu=pt (for Intel) or amd_iommu=on (for AMD)"
fi
echo ""

# For znvme usage instructions
echo "# Usage instructions for znvme"
echo "To bind an NVMe device to VFIO for znvme usage:"
echo "  1. Find the PCI address, VID, and PID from the listing above"
echo "  2. Run: sudo ./bind_vfio.sh <PCI_ADDRESS> <VID> <PID>"
echo "  3. Use the IOMMU group number with znvme"
echo ""
echo "To unbind and return to normal NVMe driver:"
echo "  1. Run: sudo ./unbind_vfio.sh <PCI_ADDRESS>"
echo ""
echo "Example for QEMU virtual NVMe device:"
echo "  Usually appears as PCI address similar to 00:04.0 or 00:05.0"
echo "  With VID/PID depending on QEMU configuration"