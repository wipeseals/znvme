#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

QEMU=${QEMU:-qemu-system-x86_64}
EXT_ARGS=${EXT_ARGS:-""}

# if os image does not exist, run setup.sh
OS_IMG=${OS_IMG:-os.img}
if [ ! -f "$OS_IMG" ]; then
    ./setup.sh
fi

# test nvme image
TEST_NVME_IMG=${TEST_NVME_IMG:-nvme.img}
if [ ! -f "$TEST_NVME_IMG" ]; then
    echo "Creating Test NVMe image: $TEST_NVME_IMG"
    qemu-img create -f qcow2 "$TEST_NVME_IMG" 10G
    # Fill the NVMe image with some data for testing
    dd if=/dev/zero of="$TEST_NVME_IMG" bs=1M count=10 status=progress
fi

# get project root directory for mount virtfs
ZNVME_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$ZNVME_ROOT" ]; then
    echo "Error: ZNVME_ROOT is not set. Please set it to the root directory of your project."
    exit 1
fi

$QEMU \
    -enable-kvm \
    -m 2048 \
    -cpu host \
    -boot d \
    -D boot.log \
    -drive file=$OS_IMG,if=none,id=os_drive \
    -device virtio-blk-pci,drive=os_drive \
    # test nvme drive
    -drive file=$TEST_NVME_IMG,if=none,id=nvme0 \
    -device nvme,drive=nvme0,serial=deadbeef \
    # mount project root directory
    -virtfs local,path="$ZNVME_ROOT",mount_tag=znvme_root,security_model=passthrough \
    -fsdev local,id=fsdev0,path="$ZNVME_ROOT" \
    $EXT_ARGS