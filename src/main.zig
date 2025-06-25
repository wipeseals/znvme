// src/main.zig
const std = @import("std");
const expect = std.testing.expect;

const ControllerRegister = packed struct {
    cap: ControllerCapabilities, // 0x00 Controller Capabilities
    vs: SpecificationVersion, // 0x08 Version
    intms: u32, // 0x0C Interrupt Mask Set
    intmc: u32, // 0x10 Interrupt Mask Clear
    cc: u32, // 0x14 Controller Configuration
    _rsvd0: u32, // 0x18 Reserved
    csts: u32, // 0x1C Controller Status
    nssr: u32, // 0x20 NVM Subsystem Reset (Optional)
    aqa: u32, // 0x24 Admin Queue Attributes
    asq: u64, // 0x28 Admin Submission Queue Base Address
    acq: u64, // 0x30 Admin Completion Queue Base Address
};
test "Controller Register Size" {
    const size = @sizeOf(ControllerRegister);
    try expect(size == 64);
}
const ControllerCapabilities = packed struct {
    mqes: u16, // [15:0]  Maximum Queues Supported
    cqr: u1, // [16]    Contiguous Queues Required
    amsWrr: u1, // [17]   Arbitration Mechanism Supported (Weighted Round Robin)
    amsVs: u1, // [18]    Arbitration Mechanism Supported (Vendor Specific)
    _rsvd0: u5, // [23:19] Reserved
    to: u8, // [31:24] Timeout (in seconds)
    dstrd: u4, // [35:32] Doorbell Stride
    nssrs: u1, // [36]    NVM Subsystem Reset Supported
    cssNvm: u1, // [37]   Command Set Supported (NVM)
    _rsvd1: u7, // [44:38] Reserved
    bps: u1, // [45]    Boot Partition Supported
    _rsvd2: u2, // [47:46] Reserved
    mpsMin: u4, // [51:48] Minimum Page Size
    mpsMax: u4, // [55:52] Maximum Page Size
    _rsvd3: u8, // [63:56] Reserved
};
test "Controller Capabilities Size" {
    const size = @sizeOf(ControllerCapabilities);
    try expect(size == 8);
}
const SpecificationVersion = packed struct {
    ter: u8, // [7:0]  Terse Version
    maj: u8, // [15:8] Major Version
    min: u16, // [31:16] Minor Version
};
test "Specification Version Size" {
    const size = @sizeOf(SpecificationVersion);
    try expect(size == 4);
}

fn printHexdump(data: []const u8, len: usize) void {
    for (0..len) |i| {
        if (i % 16 == 0) {
            std.debug.print("\n{x:08}: ", .{i});
        }
        std.debug.print("{x:02} ", .{data[i]});
    }
    std.debug.print("\n", .{});
}

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
    printHexdump(bar0_data, 256);
    // test: cast to ControllerRegister
    const ctrl_reg: *ControllerRegister = @ptrCast(bar0_mmap);
    std.debug.print("{}\n", .{ctrl_reg});
}
