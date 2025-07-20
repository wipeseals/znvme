// src/main.zig
const std = @import("std");
const expect = std.testing.expect;

const clap = @import("clap");

const nvme = @import("nvme.zig");
const vfio = @import("vfio.zig");
const cmd = @import("cmd.zig");
const util = @import("util.zig");

const page_size_min = std.heap.page_size_min;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // コマンドライン引数を取得
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-v, --verbose          Increase verbosity of output.
        \\-t, --timeout <u32>    Set timeout for controller reset in seconds (default: 10).
        \\-f, --force            Force operation, skip controller register validation.
        \\<str>                  PCI address BDF (e.g., 0000:00:1f.2) of the NVMe controller.
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(stderr, clap.Help, &params, .{}); // 共通化

    const verbose = res.args.verbose != 0;

    const pci_addr: []const u8 = res.positionals[0] orelse {
        try stderr.print("PCI address is required.\n", .{});
        return clap.help(stderr, clap.Help, &params, .{}); // 共通化
    };

    var config = nvme.NvmDeviceConfig.default();
    if (res.args.timeout) |timeout| {
        if (timeout < 1) {
            try stderr.print("Timeout must be at least 1 second.\n", .{});
            return error.InvalidArgument;
        }
        config.timeout_sec = timeout;
        config.prefer_cap_to = false; // Use the provided timeout instead of CAP.TO
    }
    if (res.args.force != 0) {
        config.force = true;
    }
    var device = nvme.NvmDevice.open(pci_addr, &config) catch |err| {
        try stderr.print("Failed to open NVMe device at PCI address {s}: {}\n", .{ pci_addr, err });
        if (err == error.InvalidControllerRegister) {
            // print the controller registers for debugging
            var vfio_container = try vfio.Container.create(pci_addr);
            defer vfio_container.remove();
            try util.printHexdump(stderr, vfio_container.bar0_map, @sizeOf(nvme.ControllerRegister));
        }
        return err;
    };
    defer device.close() catch {};
    if (verbose) {
        try stdout.print("[Initial] Current status: {}\n", .{device.status()});
    }

    try device.resetAndEnable();
    if (verbose) {
        try stdout.print("[Post-Reset] Current status: {}\n", .{device.status()});
    }

    if (verbose) {
        const version = try device.ctrl_reg.nvmVersionStr(allocator);
        defer allocator.free(version);
        try stdout.print("Opened NVMe device at PCI address: {s}. NVMe Version: {s}. Status: {}\n", .{
            pci_addr,
            version,
            device.status(),
        });
        try stdout.print("Controller Register Raw:", .{});
        try device.printCtrlRegs(stdout);

        try stdout.print("Parsed: {}\n", .{device.ctrl_reg});
    }

    // TEST: Create Identify Command
    const identify_size = 4 * 1024; // 4 KiB for Identify Command
    const identify_buf = try device.buf_pool_data.alloc(identify_size);
    defer device.buf_pool_data.free(&identify_buf) catch {};
    const data_ptr, _ = try cmd.SQDataPointer.init(identify_buf.iova, identify_size, null);
    const identify = cmd.SQEntry{
        .cdw0 = cmd.SQDword0{
            .opc = cmd.AdminOpcode.identify,
            .fuse = cmd.FusedOperation.none,
            .psdt = cmd.SQDataPointerType.prp,
            .cid = 12345, // Command Identifier
        },
        .nsid = 0x0,
        .cdw2 = 0, // Command Dword 2
        .cdw3 = 0, // Command Dword 3
        .mptr = 0, // Metadata Pointer (not used for Identify Command)
        .dptr = data_ptr, // Data Pointer
        .cdw10 = cmd.Cdw10Identify{
            .cns = cmd.ControllerNamespace.controller,
            ._rsvd = 0,
            .cntid = 0x0,
        },
    };
    var aq = device.admin_queue orelse {
        return error.AdminQueueNotInitialized;
    };
    try aq.pushToSq(&identify, true);
    const cq_entry = aq.pullFromCq(config.timeout_sec * 1000) catch |err| {
        device.printAdminQueue(stderr) catch {};
        return err;
    };
    try stdout.print("CQ Entry: {any}\n", .{cq_entry});
    try util.printHexdump(stdout, identify_buf.buf, identify_buf.buf.len);
}
