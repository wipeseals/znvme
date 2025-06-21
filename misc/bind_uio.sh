#!/bin/bash -eu
set -o pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <PCI_ADDRESS> <VID> <PID>"
  echo " - <PCI_ADDRESS> is the PCI address of the NVMe device to unbind (e.g., 0000:00:1f.2)"
  echo " - <VID> is the vendor ID of the NVMe device (e.g., 8086)"
  echo " - <PID> is the product ID of the NVMe device (e.g., 0953)"
  exit 1
fi

PCI_ADDR="$1"
VID="$2"
PID="$3"
UNBIND_PATH="/sys/bus/pci/drivers/nvme/unbind"
BIND_PATH="/sys/bus/pci/drivers/uio_pci_generic/bind"

# unbind the NVMe device from the nvme driver
if [ ! -e "/sys/bus/pci/drivers/nvme/$PCI_ADDR" ]; then
  echo "Device $PCI_ADDR is already unbound from the nvme driver."
else
  echo "$PCI_ADDR" | sudo tee "$UNBIND_PATH"
  echo "Unbound $PCI_ADDR from nvme driver."
fi

# enable the uio_pci_generic driver
sudo modprobe uio_pci_generic

# bind the uio_pci_generic driver to the device
if [ ! -e "/sys/bus/pci/drivers/uio_pci_generic/$PCI_ADDR" ]; then
  echo "$PCI_ADDR" | sudo tee "$BIND_PATH"
  echo "Bound $PCI_ADDR to uio_pci_generic driver."
else
  echo "Device $PCI_ADDR is already bound to uio_pci_generic driver."
fi

# Check if the device is now bound to uio_pci_generic
if [ ! -e "/sys/bus/pci/drivers/uio_pci_generic/$PCI_ADDR" ]; then
  echo "Failed to bind $PCI_ADDR to uio_pci_generic driver."
  exit 1
fi

# allow read write access to the bar0 (for testing)
chmod 666 "/sys/bus/pci/devices/$PCI_ADDR/resource0"

echo "Successfully bound $PCI_ADDR to uio_pci_generic driver."
lspci -k -s "$PCI_ADDR"