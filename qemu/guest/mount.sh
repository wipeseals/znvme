#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

# create mount point if it does not exist
MOUNT_POINT=${MOUNT_POINT:-/mnt/znvme}
if [ ! -d "$MOUNT_POINT" ]; then
    echo "Creating mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
fi

# mount the project root directory to the mount point
sudo mount -t 9p -o trans=virtio,version=9p2000.L znvme_root "$MOUNT_POINT"