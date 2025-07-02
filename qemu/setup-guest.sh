#!/bin/bash -eux
set -o pipefail

# Setup script to run inside QEMU guest
# This script prepares the guest environment for znvme testing

echo "Setting up QEMU guest environment for znvme testing..."

# Update system
echo "Updating system packages..."
apt-get update

# Install required packages
echo "Installing required packages..."
apt-get install -y \
    build-essential \
    linux-headers-$(uname -r) \
    pciutils \
    nvme-cli \
    gdb \
    strace \
    ltrace \
    dmesg \
    lsof

# Enable IOMMU and VFIO
echo "Configuring IOMMU and VFIO..."

# Check if IOMMU is enabled
if dmesg | grep -q "DMAR\|IOMMU"; then
    echo "IOMMU appears to be enabled"
else
    echo "Warning: IOMMU may not be enabled properly"
    echo "Kernel command line should include: intel_iommu=on iommu=pt"
fi

# Load VFIO modules
modprobe vfio
modprobe vfio-pci
modprobe vfio_iommu_type1

# Check for NVMe devices
echo "Checking for NVMe devices..."
lspci | grep -i nvme || echo "No NVMe devices found yet"
nvme list || echo "nvme-cli not finding devices yet"

# Create znvme user and group
echo "Creating znvme user for testing..."
useradd -m -s /bin/bash znvme || echo "User already exists"
usermod -a -G sudo znvme

# Set up SSH for remote access
echo "Setting up SSH..."
systemctl enable ssh
systemctl start ssh

# Create directory for znvme
echo "Setting up znvme directory..."
mkdir -p /home/znvme/znvme
chown znvme:znvme /home/znvme/znvme

# Set up VFIO permissions
echo "Setting up VFIO permissions..."
cat > /etc/udev/rules.d/99-vfio.rules << 'EOF'
# VFIO rules for znvme testing
SUBSYSTEM=="vfio", GROUP="znvme", MODE="0660"
EOF

udevadm control --reload-rules

# Create helper script for znvme testing
cat > /home/znvme/test-znvme.sh << 'EOF'
#!/bin/bash
# Helper script for znvme testing

echo "=== znvme Test Environment ==="
echo "Kernel version: $(uname -r)"
echo "IOMMU status:"
dmesg | grep -i "dmar\|iommu" | tail -5
echo ""
echo "PCI devices:"
lspci | grep -i nvme
echo ""
echo "NVMe devices:"
nvme list
echo ""
echo "VFIO status:"
ls -la /dev/vfio/
echo ""
echo "Available for testing!"
EOF

chmod +x /home/znvme/test-znvme.sh
chown znvme:znvme /home/znvme/test-znvme.sh

echo "Guest setup complete!"
echo "You can now:"
echo "1. Copy znvme binary to /home/znvme/znvme/"
echo "2. Use the existing misc/ scripts for device binding"
echo "3. Run /home/znvme/test-znvme.sh to check environment status"