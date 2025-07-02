#!/bin/bash -eux
set -o pipefail

# GDB debug script for QEMU znvme testing
# This script connects GDB to QEMU for debugging znvme

# Configuration
GDB_PORT=${GDB_PORT:-1234}
GDB_HOST=${GDB_HOST:-localhost}
ZNVME_BINARY=${ZNVME_BINARY:-../zig-out/bin/znvme}

# Directories
QEMU_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$QEMU_DIR")"

# Check if znvme binary exists
if [ ! -f "$ZNVME_BINARY" ]; then
    echo "Warning: znvme binary not found at $ZNVME_BINARY"
    echo "Run 'zig build' in the root directory to build it"
fi

# Create GDB init file
GDB_INIT_FILE="/tmp/gdb_init_znvme"
cat > "$GDB_INIT_FILE" << 'EOF'
# GDB initialization for znvme debugging

# Connect to QEMU
target remote localhost:1234

# Set up some useful commands
define qemu-info
  monitor info registers
  monitor info cpus
  monitor info block
  monitor info pci
end

define qemu-nvme-info
  monitor info block
  # Show NVMe device information
  monitor info pci | grep -i nvme
end

define qemu-continue
  continue
end

# Useful breakpoints for NVMe development
define setup-nvme-breakpoints
  # Add breakpoints for common NVMe operations
  # These are examples - adjust based on your debugging needs
  break main
  break NvmDevice.open
  break NvmDevice.close
end

# Display help
define help-znvme
  echo Available commands:\n
  echo   qemu-info         - Show QEMU system information\n
  echo   qemu-nvme-info    - Show NVMe device information\n
  echo   qemu-continue     - Continue execution\n
  echo   setup-nvme-breakpoints - Set up common NVMe breakpoints\n
  echo   help-znvme        - Show this help\n
end

echo \n
echo QEMU znvme debugging session started\n
echo Type 'help-znvme' for available commands\n
echo Type 'setup-nvme-breakpoints' to set common breakpoints\n
echo \n
EOF

echo "Connecting GDB to QEMU at $GDB_HOST:$GDB_PORT"
echo "QEMU should be started with debug mode enabled (QEMU_DEBUG=true)"
echo ""
echo "Available GDB commands:"
echo "  qemu-info - Show QEMU system information"
echo "  qemu-nvme-info - Show NVMe device information"
echo "  setup-nvme-breakpoints - Set up common NVMe breakpoints"
echo "  help-znvme - Show help"
echo ""

# Launch GDB
if [ -f "$ZNVME_BINARY" ]; then
    exec gdb -x "$GDB_INIT_FILE" "$ZNVME_BINARY"
else
    echo "Starting GDB without znvme binary (you can load it later with 'file' command)"
    exec gdb -x "$GDB_INIT_FILE"
fi