// src/main.zig
const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.c_allocator;

    // コマンドライン引数を取得
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        std.debug.print("Usage: toynvme [pci_address]\n", .{});
        std.debug.print(" - [pci_address] 0000:01:00.0\n", .{});
        return;
    }
    const pci_addr = args[1];
    std.debug.print("PCI Address: {s}\n", .{pci_addr});

    // BAR0 空間 (/sys/bus/pci/devices/[pci_address]/resource0) のパスを取得
    const bar0_path = try std.fs.path.join(allocator, &.{ "/sys/bus/pci/devices/", pci_addr, "/resource0" });
    std.debug.print("BAR0 Path: {s}\n", .{bar0_path});
    // BAR0 空間をmmap
    const bar0_fd = try std.fs.openFileAbsolute(bar0_path, .{ .mode = .read_write });
    defer bar0_fd.close();
}
