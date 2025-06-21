#!/bin/bash -eu
set -o pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <PCI_ADDRESS>"
  echo " - <PCI_ADDRESS> is the PCI address of the NVMe device to unbind (e.g., 0000:00:1f.2)"
  exit 1
fi

PCI_ADDR="$1"
UNBIND_PATH="/sys/bus/pci/drivers/uio_pci_generic/unbind"
BIND_PATH="/sys/bus/pci/drivers/nvme/bind"

# unbind uio_pci_generic driver
if [ ! -e "/sys/bus/pci/drivers/uio_pci_generic/$PCI_ADDR" ]; then
  echo "Device $PCI_ADDR is already unbound from the uio_pci_generic driver."
else
  echo "$PCI_ADDR" | sudo tee "$UNBIND_PATH"
  echo "Unbound $PCI_ADDR from uio_pci_generic driver."
fi

# bind the nvme driver to the device
if [ -e "/sys/bus/pci/drivers/nvme/$PCI_ADDR" ]; then
  echo "Device $PCI_ADDR is already bound to nvme driver."
else
  echo "$PCI_ADDR" | sudo tee "$BIND_PATH"
  echo "Bound $PCI_ADDR to nvme driver."
fi

# Check if the device is now bound to nvme
if [ -e "/sys/bus/pci/drivers/nvme/$PCI_ADDR" ]; then
  echo "Successfully bound $PCI_ADDR to nvme driver."
else
  echo "Failed to bind $PCI_ADDR to nvme driver."
  exit 1
fi
lspci -k -s "$PCI_ADDR"