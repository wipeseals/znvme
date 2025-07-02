#!/bin/bash
# Demo script showing the complete QEMU workflow for znvme

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== znvme QEMU Environment Demo ===${NC}"
echo ""
echo "This script demonstrates the complete workflow for using znvme"
echo "with QEMU virtual NVMe devices."
echo ""
echo "Prerequisites:"
echo "- QEMU and dependencies installed (run './qemu-manager.sh setup')"
echo "- znvme built (run './qemu-manager.sh build')"
echo ""

read -p "Press Enter to continue or Ctrl+C to exit..."

echo ""
echo -e "${GREEN}Step 1: Check environment status${NC}"
./qemu-manager.sh status

echo ""
echo -e "${GREEN}Step 2: Start QEMU with virtual NVMe device${NC}"
echo "This will start QEMU in the background with:"
echo "- Virtual NVMe device (1GB)"
echo "- Intel IOMMU enabled"
echo "- VNC display on port 5901"
echo "- SSH forwarding on port 2222"
echo "- Serial console on port 4321"
echo ""

read -p "Start QEMU? [y/N]: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting QEMU... (This may take a moment)"
    ./qemu-manager.sh start &
    QEMU_PID=$!
    
    echo ""
    echo -e "${YELLOW}QEMU is starting...${NC}"
    echo "You can connect to it via:"
    echo "- VNC: vncviewer localhost:5901"
    echo "- Serial console: telnet localhost 4321"
    echo "- SSH (once guest is configured): ssh -p 2222 user@localhost"
    echo ""
    
    sleep 5
    
    echo -e "${GREEN}Step 3: Check QEMU status${NC}"
    ./qemu-manager.sh status
    
    echo ""
    echo -e "${GREEN}Step 4: Guest Setup Instructions${NC}"
    echo "Once the guest OS is booted, you can:"
    echo ""
    echo "1. Setup the guest environment:"
    echo "   # Copy setup-guest.sh to the guest and run:"
    echo "   sudo ./setup-guest.sh"
    echo ""
    echo "2. Copy znvme binary and scripts to the guest"
    echo ""
    echo "3. List NVMe devices in the guest:"
    echo "   ./list-enhanced.sh"
    echo ""
    echo "4. Bind virtual NVMe device to VFIO:"
    echo "   ./bind-qemu-nvme.sh"
    echo ""
    echo "5. Test znvme with the virtual device:"
    echo "   ./znvme <pci_address> <iommu_group>"
    echo ""
    
    echo -e "${GREEN}Step 5: Debugging${NC}"
    echo "To debug znvme with GDB:"
    echo "1. Stop the current QEMU instance"
    echo "2. Start QEMU with debugging enabled:"
    echo "   QEMU_DEBUG=true ./qemu-manager.sh start"
    echo "3. In another terminal, connect GDB:"
    echo "   ./qemu-manager.sh debug"
    echo ""
    
    read -p "Stop QEMU now? [y/N]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping QEMU..."
        ./qemu-manager.sh stop
    else
        echo "QEMU left running. Use './qemu-manager.sh stop' to stop it."
    fi
else
    echo "Skipping QEMU startup."
fi

echo ""
echo -e "${GREEN}Step 6: Running Tests${NC}"
echo "To run the automated test environment validation:"
echo ""
read -p "Run environment tests? [y/N]: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./qemu-manager.sh test
fi

echo ""
echo -e "${GREEN}Step 7: Cleanup${NC}"
echo "To clean up generated files:"
echo ""
read -p "Clean up generated files? [y/N]: " -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    ./qemu-manager.sh clean
fi

echo ""
echo -e "${BLUE}=== Demo Complete ===${NC}"
echo ""
echo "Summary of what you can do:"
echo "- Use './qemu-manager.sh help' for all available commands"
echo "- Read 'docs/QEMU.md' for detailed documentation"
echo "- Use individual scripts in qemu/ directory for specific tasks"
echo ""
echo "The QEMU environment provides:"
echo "✓ Virtual NVMe devices for testing without physical hardware"
echo "✓ GDB debugging integration"
echo "✓ Automated CI/CD testing capabilities"
echo "✓ Complete isolation from host system"
echo ""
echo "Happy testing!"