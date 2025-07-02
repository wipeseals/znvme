#!/bin/bash

# IOMMU有効化のキーワード
IOMMU_KEYWORDS=("intel_iommu=on" "amd_iommu=on" "iommu=on")

echo "Checking IOMMU status..."

FOUND=0

# カーネルコマンドラインの確認
CMDLINE=$(cat /proc/cmdline)
for key in "${IOMMU_KEYWORDS[@]}"; do
    if [[ "$CMDLINE" == *"$key"* ]]; then
        echo "IOMMU is enabled in kernel cmdline: $key"
        FOUND=1
        break
    fi
done

# dmesgでIOMMUの有効化メッセージを確認
if dmesg | grep -qi 'IOMMU.*enabled'; then
    echo "IOMMU is enabled (dmesg check)."
    FOUND=1
fi

if [[ $FOUND -eq 0 ]]; then
    echo "IOMMU does NOT appear to be enabled."
    exit 1
else
    exit 0
fi
