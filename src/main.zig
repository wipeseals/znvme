// src/main.zig
const std = @import("std");
const log = std.log;
const expect = std.testing.expect;

const clap = @import("clap");

const nvme = @import("nvme.zig");
const vfio = @import("vfio.zig");
const cmd = @import("cmd.zig");
const util = @import("util.zig");

const page_size_min = std.heap.page_size_min;

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

fn setupConfigFromArgs(allocator: std.mem.Allocator) !nvme.NvmDeviceConfig {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-t, --timeout <u32>    Set timeout for controller reset in seconds (default: 10).
        \\-f, --force            Force operation, skip controller register validation.
        \\--admin_queue_depth <u32> Set the depth of the admin queue (default: 1).
        \\<str>                  PCI address BDF (e.g., 0000:00:1f.2) of the NVMe controller.
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(stderr, clap.Help, &params, .{}); // 共通化
        return error.InvalidArgument;
    }

    var config = nvme.NvmDeviceConfig.default();
    config.pci_addr = res.positionals[0] orelse {
        log.err("PCI address is required.\n", .{});
        try clap.help(stderr, clap.Help, &params, .{}); // 共通化
        return error.InvalidArgument;
    };
    if (res.args.timeout) |timeout| {
        if (timeout < 1) {
            log.err("Timeout must be at least 1 second.\n", .{});
            return error.InvalidArgument;
        }
        config.timeout_sec = timeout;
        config.prefer_cap_to = false; // Use the provided timeout instead of CAP.TO
    }
    if (res.args.force != 0) {
        config.force = true;
    }
    if (res.args.admin_queue_depth) |depth| {
        // Check if the depth is within valid range
        if (depth < 1 or depth > 4095) {
            log.err("Admin queue depth must be between 1 and 4095.\n", .{});
            return error.InvalidArgument;
        }
        config.admin_queue_depth = @intCast(depth);
    }
    return config;
}
pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // コマンドライン引数を解析
    const config = setupConfigFromArgs(allocator) catch |err| {
        if (err == error.InvalidArgument) {
            // no exception, just print usage
            return;
        } else {
            return err;
        }
    };

    // Open NVMe device
    var device = nvme.NvmDevice.open(&config) catch |err| {
        log.err("Failed to open NVMe device at PCI address {s}: {}\n", .{ config.pci_addr, err });
        if (err == error.InvalidControllerRegister) {
            // print the controller registers for debugging
            var vfio_container = try vfio.Container.create(config.pci_addr);
            defer vfio_container.remove();
            try util.printHexdump(stderr, vfio_container.bar0_map, @sizeOf(nvme.ControllerRegister));
        }
        return err;
    };
    defer device.close() catch |err| {
        log.err("Failed to close NVMe device: {}\n", .{err});
    };

    log.debug("[Initial] Current status: {}", .{device.status()});
    device.resetAndEnable() catch |err| {
        log.err("Failed to reset and enable NVMe device: {}\n", .{err});
        device.printCtrlRegs(stderr) catch {};
        return err;
    };
    log.debug("[Post Controller Enable] Current status: {}", .{device.status()});

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
    log.info("SQ Entry: {any}", .{identify});
    var aq = device.admin_queue orelse {
        return error.AdminQueueNotInitialized;
    };
    try aq.push(&identify, true);
    const cq_entry = aq.pull(config.timeout_sec * 1000) catch |err| {
        device.printAdminQueue(stderr) catch {};
        return err;
    };
    log.info("CQ Entry: {any}", .{cq_entry});
    try util.printHexdump(stdout, identify_buf.buf, identify_buf.buf.len);
}
