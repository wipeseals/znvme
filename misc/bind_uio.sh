#!/bin/bash -eu
set -o pipefail

if [ $# -ne 3 ]; then
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
  echo "$PCI_ADDR" > "$UNBIND_PATH"
  echo "Unbound $PCI_ADDR from nvme driver."
fi

# add uio_pci_generic/new_id
if grep -q "$VID $PID" "/sys/bus/pci/drivers/uio_pci_generic/new_id"; then
  echo "Device with VID:PID $VID:$PID is already registered in uio_pci_generic."
else
  echo "Bound $PCI_ADDR to uio_pci_generic driver."
fi

# bind the uio_pci_generic driver to the device
if [ -e "/sys/bus/pci/drivers/uio_pci_generic/$PCI_ADDR" ]; then
  echo "Device $PCI_ADDR is already bound to uio_pci_generic driver."
else
  echo "$PCI_ADDR" > "$BIND_PATH"
  echo "Bound $PCI_ADDR to uio_pci_generic driver."
fi

# Check if the device is now bound to uio_pci_generic
if [ -e "/sys/bus/pci/drivers/uio_pci_generic/$PCI_ADDR" ]; then
  echo "Successfully bound $PCI_ADDR to uio_pci_generic driver."
else
  echo "Failed to bind $PCI_ADDR to uio_pci_generic driver."
  exit 1
fi
lspci -k -s "$PCI_ADDR"