#!/bin/bash -eu
set -o pipefail

lspci | grep "Non-Volatile memory controller" | while read -r line; do
    # Extract the PCI address from the line
    pci_address=$(echo "$line" | awk '{print $1}')
    
    # Get VID:PID using lspci -n
    vid_pid=$(lspci -n -s "$pci_address" | awk '{print $3}')
    vid=${vid_pid%%:*}
    pid=${vid_pid##*:}

    # Extract vendor and device name (manufacturer/model) from the original line
    info=$(echo "$line" | sed -E 's/^[^ ]+ [^:]+: //')

    # Print PCI address, VID, PID, and manufacturer/model info
    echo "PCI Address: $pci_address, VID: $vid, PID: $pid, Info: $info"
done