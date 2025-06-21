// src/main.zig
const std = @import("std");

// NVMe Specification 1.4 - Figure 9: Controller Registers
// BAR0/BAR1にマップされるレジスタの構造体を定義します。
// volatileアクセスを強制するため、packed structが適しています。
const NvmeRegisters = packed struct {
    cap: u64, // 0x00: Controller Capabilities
    vs: u32, // 0x08: Version
    intms: u32, // 0x0C: Interrupt Mask Set
    intmc: u32, // 0x10: Interrupt Mask Clear
    cc: CcFlags, // 0x14: Controller Configuration
    _rsvd1: u32,
    csts: u32, // 0x1C: Controller Status
    nssr: u32, // 0x20: NVM Subsystem Reset (Optional)
    aqa: u32, // 0x24: Admin Queue Attributes
    asq: u64, // 0x28: Admin Submission Queue Base Address
    acq: u64, // 0x30: Admin Completion Queue Base Address
    // ...以降もレジスタは続くが、今回はここまでで十分
};

// CC (Controller Configuration) レジスタのビットフィールド
const CcFlags = packed struct {
    EN: bool, // Bit 0: Enable
    _rsvd1: u3,
    CSS: u3, // Bit 4-6: Command Set Selected
    MPS: u4, // Bit 7-10: Memory Page Size
    AMS: u3, // Bit 11-13: Arbitration Mechanism Selected
    SHN: u2, // Bit 14-15: Shutdown Notification
    IOSQES: u4, // Bit 16-19: I/O Submission Queue Entry Size
    IOCQES: u4, // Bit 20-23: I/O Completion Queue Entry Size
    _rsvd2: u8,
};

// CSTS (Controller Status) レジスタのビットフィールド
const CstsFlags = packed struct {
    RDY: bool, // Bit 0: Ready
    CFS: bool, // Bit 1: Controller Fatal Status
    _rsvd: u30,
};

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
    const bar0_size = try bar0_fd.getEndPos();
    std.debug.print("BAR0 Mapped Size: {}\n", .{bar0_size});

    const bar0_mmap = try std.posix.mmap(
        null,
        bar0_size,
        std.posix.PROT.READ | std.posix.PROT.WRITE,
        .{
            .TYPE = .SHARED,
        },
        bar0_fd.handle,
        0,
    );
    defer std.posix.munmap(bar0_mmap);

    // test: print BAR0 data
    const bar0_data: []u8 = @ptrCast(bar0_mmap);
    for (0..256) |i| {
        if (i % 16 == 0) {
            std.debug.print("\n{x:08}: ", .{i});
        }
        std.debug.print("{x:2} ", .{bar0_data[i]});
    }
    std.debug.print("\n", .{});
}
