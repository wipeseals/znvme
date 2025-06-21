// src/main.zig
const std = @import("std");

// Cのヘッダファイルをインポートして、定数や構造体、関数を使えるようにする
const c = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
    @cInclude("linux/vfio.h");
    @cInclude("stdlib.h"); // realpath, free
});

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

    // 1. VFIOコンテナを作成
    const container_fd = c.open("/dev/vfio/vfio", @as(c_int, c.O_RDWR), @as(c_uint, 0));
    if (container_fd < 0) {
        @panic("Failed to open /dev/vfio/vfio");
    }
    defer _ = c.close(container_fd);
}
