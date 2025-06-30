// src/main.zig
const std = @import("std");
const expect = std.testing.expect;
const page_size_min = std.heap.page_size_min;

const clap = @import("clap");

/// Device status enumeration
const DeviceStatus = enum {
    /// EN = 0, RDY = *, SHN = 0, SHST = 0, CFS = 0
    /// Device is not enabled
    Disabled,
    /// EN = 1, RDY = 0, SHN = 0, SHST = 0, CFS = 0
    /// Device is enabled but not ready
    Enabling,
    /// EN = 1, RDY = 1, SHN = 0, SHST = 0, CFS = 0
    /// Device is enabled and ready
    Enabled,
    /// EN = 1, RDY = 1, SHN != 0, SHST = 0, CFS = 0
    NotifyingShutdown,
    /// Device is enabled, ready, and in a shutdown state
    /// EN = 1, RDY = 1, SHN != 0,  SHST = 1, CFS = 0
    /// Device is enabled, ready, and in a shutdown state
    ShutdownInProgress,
    /// EN = 1, RDY = 1, SHN != 0,  SHST = 2, CFS = 0
    /// Device is enabled, ready, and has been shut down
    Shutdown,
    /// EN = *, RDY = *, SHST = *, CFS = 1
    /// Device is in a fatal error state
    FatalError,
    /// Other states not covered by the above
    Other,
};
const NvmDevice = struct {
    pci_addr: []const u8,
    bar0_fd: std.fs.File,
    ctrl_reg_map: []align(page_size_min) u8,
    ctrl_reg: *volatile ControllerRegister,

    /// Initialize the NVM device by mapping the controller registers from BAR0.
    pub fn open(pci_addr: []const u8) !NvmDevice {
        // BAR0 空間 (/sys/bus/pci/devices/[pci_address]/resource0) のパスを取得
        const bar0_path = try std.fs.path.join(std.heap.page_allocator, &.{ "/sys/bus/pci/devices/", pci_addr, "/resource0" });
        const bar0_fd = try std.fs.openFileAbsolute(bar0_path, .{ .mode = .read_write });
        errdefer bar0_fd.close();
        const bar0_size = try bar0_fd.getEndPos();

        // Map BAR0
        const ctrl_reg_map = try std.posix.mmap(
            null,
            bar0_size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{
                .TYPE = .SHARED,
            },
            bar0_fd.handle,
            0,
        );
        errdefer std.posix.munmap(ctrl_reg_map);
        const ctrl_reg: *volatile ControllerRegister = @ptrCast(ctrl_reg_map);
        if (!ctrl_reg.isValid()) {
            return error.InvalidControllerRegister;
        }
        return NvmDevice{
            .pci_addr = pci_addr,
            .bar0_fd = bar0_fd,
            .ctrl_reg_map = ctrl_reg_map,
            .ctrl_reg = ctrl_reg,
        };
    }

    /// Deinitialize the NVM device, unmapping the controller registers and closing the file descriptor.
    pub fn close(self: NvmDevice) void {
        std.posix.munmap(self.ctrl_reg_map);
        self.bar0_fd.close();
    }

    /// print hexdump of the controller registers.
    pub fn printRaw(self: *const NvmDevice, writer: anytype) !void {
        try printHexdump(writer, self.ctrl_reg_map, @sizeOf(ControllerRegister));
    }

    /// Get the status of the NVM device based on the controller registers.
    pub fn status(self: *const NvmDevice) DeviceStatus {
        const en = self.ctrl_reg.cc.en;
        const rdy = self.ctrl_reg.csts.rdy;
        const shn = self.ctrl_reg.cc.shn;
        const shst = self.ctrl_reg.csts.shst;
        const cfs = self.ctrl_reg.csts.cfs;

        const ret = switch (cfs) {
            0 => switch (shst) {
                ShutdownStatus.normal => switch (en) {
                    0 => DeviceStatus.Disabled,
                    1 => switch (rdy) {
                        0 => DeviceStatus.Enabling,
                        1 => switch (shn) {
                            ShutdownNotification.none => DeviceStatus.Enabled,
                            ShutdownNotification.normal => DeviceStatus.NotifyingShutdown,
                            ShutdownNotification.abrupt => DeviceStatus.NotifyingShutdown,
                            ShutdownNotification.reserved => unreachable,
                        },
                    },
                },
                ShutdownStatus.shutdownInProgress => DeviceStatus.ShutdownInProgress,
                ShutdownStatus.shutdown => DeviceStatus.Shutdown,
                else => unreachable,
            },
            1 => DeviceStatus.FatalError,
        };
        return ret;
    }
};

const ControllerRegister = packed struct {
    cap: ControllerCapabilities, // 0x00 Controller Capabilities
    vs: SpecificationVersion, // 0x08 Version
    intms: u32, // 0x0C Interrupt Mask Set
    intmc: u32, // 0x10 Interrupt Mask Clear
    cc: ControllerConfiguration, // 0x14 Controller Configuration
    _rsvd0: u32, // 0x18 Reserved
    csts: ControllerStatus, // 0x1C Controller Status
    nssr: u32, // 0x20 NVM Subsystem Reset (Optional)
    aqa: u32, // 0x24 Admin Queue Attributes
    asq: u64, // 0x28 Admin Submission Queue Base Address
    acq: u64, // 0x30 Admin Completion Queue Base Address

    /// is the controller register valid?
    pub fn isValid(self: *const volatile ControllerRegister) bool {
        if (self.cap.mqes == 0) {
            return false; // Maximum Queues Supported must be non-zero
        }
        if (self.cap.cssNvm != 1) {
            return false; // Command Set Supported must be NVM
        }
        if (self.vs.maj == 0 and self.vs.min == 0) {
            return false; // Version must be non-zero
        }
        return true;
    }

    pub fn nvmVersionStr(self: *const volatile ControllerRegister, allocator: std.mem.Allocator) ![]const u8 {
        // Format the version as "MAJOR.MINOR.TERSE"
        const version = try std.fmt.allocPrint(allocator, "{d}.{d}.{d}", .{
            self.vs.maj,
            self.vs.min,
            self.vs.ter,
        });
        return version;
    }
};
test "Controller Register Size" {
    const size = @sizeOf(ControllerRegister);
    try expect(size == 64);
}

test "NVMe Version String Format" {
    const allocator = std.testing.allocator;

    // Test case 1: Version 1.4.0 (the issue case)
    var ctrl_reg = ControllerRegister{
        .cap = undefined,
        .vs = SpecificationVersion{
            .ter = 0, // Terse version
            .min = 4, // Minor version
            .maj = 1, // Major version
        },
        .intms = 0,
        .intmc = 0,
        .cc = undefined,
        ._rsvd0 = 0,
        .csts = undefined,
        .nssr = 0,
        .aqa = 0,
        .asq = 0,
        .acq = 0,
    };

    const version_str = try ctrl_reg.nvmVersionStr(allocator);
    defer allocator.free(version_str);

    // Should format as MAJOR.MINOR.TERSE = 1.4.0
    try expect(std.mem.eql(u8, version_str, "1.4.0"));

    // Test case 2: Version 2.0.1 (different values)
    ctrl_reg.vs.maj = 2;
    ctrl_reg.vs.min = 0;
    ctrl_reg.vs.ter = 1;

    const version_str2 = try ctrl_reg.nvmVersionStr(allocator);
    defer allocator.free(version_str2);

    // Should format as MAJOR.MINOR.TERSE = 2.0.1
    try expect(std.mem.eql(u8, version_str2, "2.0.1"));
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
    min: u8, // [15:8] Minor Version
    maj: u16, // [31:16] Major Version
};
test "Specification Version Size" {
    const size = @sizeOf(SpecificationVersion);
    try expect(size == 4);
}

const ControllerConfiguration = packed struct {
    en: u1, // [0]  Enable Controller
    _rsv0: u3, // [3:1] Reserved
    css: u3, // [6:4] Command Set Selected
    mps: u4, // [10:7] Memory Page Size
    ams: u3, // [13:11] Arbitration Mechanism Selected
    shn: ShutdownNotification, // [15:14] Shutdown Notification
    iosqes: u4, // [19:16] I/O Submission Queue Entry Size
    iocqes: u4, // [23:20] I/O Completion Queue
    crimen: u1, // [24]  Controller Readiness Indicator
    _rsv1: u7, // [31:25] Reserved
};
test "Controller Configuration Size" {
    const size = @sizeOf(ControllerConfiguration);
    try expect(size == 4);
}

const ShutdownNotification = enum(u2) {
    none = 0b00, // No notification and no effect
    normal = 0b01, // Normal shutdown
    abrupt = 0b10, // Abrupt shutdown
    reserved = 0b11, // Reserved
};

const ShutdownStatus = enum(u2) {
    normal = 0b00, // Normal operation
    shutdownInProgress = 0b01, // Shutdown in progress
    shutdown = 0b10, // Shutdown completed
    reserved = 0b11, // Reserved
};
const ControllerStatus = packed struct {
    rdy: u1, // [0] Ready
    cfs: u1, // [1] Controller Fatal Status
    shst: ShutdownStatus, // [3:2] Shutdown Status
    nssro: u1, // [4] NVM Subsystem Reset Occurred
    pp: u1, // [5] Processing Paused
    st: u1, // [6] Shutdown Type 1 = NVM Subsystem Reset, 0 = Controller Level Resets
    _rsvd0: u25, // [31:07] Reserved
};

fn printHexdump(writer: anytype, data: []const u8, len: usize) !void {
    for (0..len) |i| {
        if (i % 16 == 0) {
            try writer.print("\n{x:08}: ", .{i});
        }
        try writer.print("{x:02} ", .{data[i]});
    }
    try writer.print("\n", .{});
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    // コマンドライン引数を取得
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-v, --verbose          Increase verbosity of output.
        \\<str>                  PCI address of the NVMe controller (e.g., 0000:00:1f.2).
    );
    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{ .diagnostic = &diag, .allocator = allocator }) catch |err| {
        diag.report(stderr, err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0)
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    const verbose = res.args.verbose != 0;

    const pci_addr: []const u8 = res.positionals[0] orelse {
        try stderr.print("PCI address is required.\n", .{});
        return error.InvalidArgument;
    };
    const device = try NvmDevice.open(pci_addr);
    defer device.close();
    const status = device.status();
    if (verbose) {
        const version = try device.ctrl_reg.nvmVersionStr(allocator);
        defer allocator.free(version);
        try stdout.print("Opened NVMe device at PCI address: {s}. NVMe Version: {s}. Status: {}\n", .{
            pci_addr,
            version,
            status,
        });
        try stdout.print("Controller Register Raw:", .{});
        try device.printRaw(stdout);

        try stdout.print("Parsed: {}\n", .{device.ctrl_reg});
    }
}
