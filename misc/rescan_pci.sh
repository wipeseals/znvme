#!/bin/bash -eux
set -o pipefail

# get the PCI address from the command line argument
if [ $# -lt 1 ]; then
  echo "Usage: $0 <PCI_ADDRESS>"
  echo " - <PCI_ADDRESS> is the PCI address of the device to rescan (e.g., 0000:00:1f.2)"
  exit 1
fi
PCI_ADDR="$1"


# remove the device from the PCI bus
if [ -e "/sys/bus/pci/devices/$PCI_ADDR/remove" ]; then
  echo 1 | sudo tee "/sys/bus/pci/devices/$PCI_ADDR/remove"
  echo "Removed $PCI_ADDR from PCI bus."
else
  echo "Device $PCI_ADDR not found on PCI bus."
fi

# rescan the PCI bus to re-add the device
if [ -e "/sys/bus/pci/rescan" ]; then
  echo 1 | sudo tee "/sys/bus/pci/rescan"
  echo "Rescanned PCI bus."
else
  echo "PCI bus rescan not supported on this system."
fi

# check if the device is back on the PCI bus
lspci -k -s "$PCI_ADDR" || echo "Device $PCI_ADDR not found after rescan."
