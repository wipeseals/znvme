#!/bin/bash -eux
set -o pipefail

if [ $# -lt 3 ]; then
  echo "Usage: $0 <PCI_ADDRESS> <VID> <PID>"
  echo " - <PCI_ADDRESS> is the PCI address of the NVMe device to bind (e.g., 0000:00:1f.2)"
  echo " - <VID> is the vendor ID of the NVMe device (e.g., 8086)"
  echo " - <PID> is the product ID of the NVMe device (e.g., 0953)"
  exit 1
fi

PCI_ADDR="$1"
VID="$2"
PID="$3"
UNBIND_PATH="/sys/bus/pci/drivers/nvme/unbind"
BIND_PATH="/sys/bus/pci/drivers/vfio-pci/bind"

# unbind the NVMe device from the nvme driver
if [ -e "/sys/bus/pci/drivers/nvme/$PCI_ADDR" ]; then
  echo "$PCI_ADDR" | sudo tee "$UNBIND_PATH"
  echo "Unbound $PCI_ADDR from nvme driver."
fi

# enable the vfio-pci driver
sudo modprobe vfio-pci

# set new_id for the vfio-pci driver (if not already set)
echo "$VID $PID" | sudo tee "/sys/bus/pci/drivers/vfio-pci/new_id" || true

# bind the vfio-pci driver to the device
if [ ! -e "/sys/bus/pci/drivers/vfio-pci/$PCI_ADDR" ]; then
  echo "$PCI_ADDR" | sudo tee "$BIND_PATH"
  echo "Bound $PCI_ADDR to vfio-pci driver."
else
  echo "Device $PCI_ADDR is already bound to vfio-pci driver."
fi

lspci -k -s "$PCI_ADDR"

# IOMMU group番号の表示と/dev/vfio/<group>のパーミッション設定
GROUP_PATH="/sys/bus/pci/devices/$PCI_ADDR/iommu_group"
if [ -L "$GROUP_PATH" ]; then
  GROUP_NUM=$(basename "$(readlink -f "$GROUP_PATH")")
  echo "IOMMU group: $GROUP_NUM"
  VFIO_DEV="/dev/vfio/$GROUP_NUM"
  sudo chmod 660 "$VFIO_DEV"
else
  echo "IOMMU group not found for $PCI_ADDR"
fi
