#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

IMAGE_URL=${IMAGE_URL:-"https://releases.ubuntu.com/24.04/ubuntu-24.04.2-live-server-amd64.iso"}
IMAGE_FILE="$(basename "$IMAGE_URL")"
QEMU=${QEMU:-qemu-system-x86_64}
EXT_ARGS=${EXT_ARGS:-""}

# download Ubuntu Live Server ISO if it does not exist
if [ -f "$IMAGE_FILE" ]; then
    echo "Image file '$IMAGE_FILE' already exists. Skipping download."
else
    if command -v wget &> /dev/null; then
        wget -O "$IMAGE_FILE" "$IMAGE_URL"
    elif command -v curl &> /dev/null; then
        curl -L -o "$IMAGE_FILE" "$IMAGE_URL"
    else
        echo "Error: Neither wget nor curl is installed. Please install one of them to download the image."
        exit 1
    fi
    echo "Download complete: $IMAGE_FILE"
fi

# Create OS Drive image if it does not exist
OS_IMG=${OS_IMG:-os.img}
if [ ! -f "$OS_IMG" ]; then
    echo "Creating OS Drive image: $OS_IMG"
    qemu-img create -f qcow2 "$OS_IMG" 20G
fi

$QEMU \
    -enable-kvm \
    -m 2048 \
    -cpu host \
    -boot d \
    -D setup.log \
    -cdrom $IMAGE_FILE \
    -drive file=$OS_IMG,if=none,id=os_drive \
    -device virtio-blk-pci,drive=os_drive \
    $EXT_ARGS