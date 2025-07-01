#!/bin/bash -eux
set -o pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <PCI_ADDRESS>"
  echo " - <PCI_ADDRESS> is the PCI address of the NVMe device to unbind (e.g., 0000:00:1f.2)"
  exit 1
fi

PCI_ADDR="$1"
UNBIND_PATH="/sys/bus/pci/drivers/vfio-pci/unbind"
BIND_PATH="/sys/bus/pci/drivers/nvme/bind"

# unbind vfio-pci driver
if [ -e "/sys/bus/pci/drivers/vfio-pci/$PCI_ADDR" ]; then
  echo "$PCI_ADDR" | sudo tee "$UNBIND_PATH"
  echo "Unbound $PCI_ADDR from vfio-pci driver."
fi

# bind the nvme driver to the device
if [ ! -e "/sys/bus/pci/drivers/nvme/$PCI_ADDR" ]; then
  echo "$PCI_ADDR" | sudo tee "$BIND_PATH"
  echo "Bound $PCI_ADDR to nvme driver."
else
  echo "Device $PCI_ADDR is already bound to nvme driver."
fi

lspci -k -s "$PCI_ADDR"
