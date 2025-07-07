// src/main.zig
const std = @import("std");
const expect = std.testing.expect;

const clap = @import("clap");

const vfio = @import("vfio.zig");
const util = @import("util.zig");

// VFIO用Cヘッダのインクルード
const c = @cImport({
    @cInclude("linux/vfio.h");
    @cInclude("sys/ioctl.h");
});

const page_size_min = std.heap.page_size_min;
const sleep_ns = 10; // 10ns

/// NVMe Submission Queue Entry structure
/// TODO: union support for Vendor Specific, ...
const SQEntry = packed struct {
    cdw0: SQDword0, // Submission Queue Dword 0
    nsid: u32, // Namespace Identifier
    cdw2: u32, // Command Dword 2
    cdw3: u32, // Command Dword 3
    mptr: u32, // Metadata Pointer
    dptr: SQDataPointer, // Data Pointer
    cdw10: u32, // Command Dword 10
    cdw11: u32, // Command Dword 11
    cdw12: u32, // Command Dword 12
    cdw13: u32, // Command Dword 13
    cdw14: u32, // Command Dword 14
    cdw15: u32, // Command Dword 15
};
test "Submission Queue Size" {
    const size = @sizeOf(SQEntry);
    try expect(size == 64); // 16 * u32 = 64 bytes
}
/// Submission Queue Dword 0 structure
const SQDword0 = packed struct {
    opc: u8, // [7:0]  Opcode
    fuse: u2, // [9:8]  Fused Operation
    _rsvd0: u4, // [13:10] Reserved
    psdt: u2, // [15:14] PRP or SGL Data Transfer
    cid: u16, // [31:16] Command Identifier
};
/// Completion Queue structure
/// TODO: SGL support
const SQDataPointer = packed struct {
    prp1: u32, // [31:0] PRP Entry 1
    prp2: u32, // [63:32] PRP Entry 2
};

const CompletionQueueEntry = packed struct {
    dw0: u32, // Command Specific Dword 0
    dw1: u32, // Command Specific Dword 1
    sqhd: u16, // Submission Queue Head Pointer
    sqid: u16, // Submission Queue Identifier
    cid: u16, // Command Identifier
    p: u1, // Phase Tag
    sc: u8, // Status Code
    sct: u3, // Status Code Type
    crd: u2, // Command Retry Delay
    more: u1, // More
    dnr: u1, // Do Not Retry
};
test "Completion Queue Size" {
    const size = @sizeOf(CompletionQueueEntry);
    try expect(size == 16);
}

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
/// Configuration for the NVM device
const NvmDeviceConfig = struct {
    /// Timeout for controller reset in seconds
    timeout_sec: u32 = 10,
    /// Prefer the CAP.TO setting
    prefer_cap_to: bool = true,
    /// Admin queue depth, minimum is 1 (規格上+1が必要だが、0'base registerなのでそのままセット)
    admin_queue_depth: u12 = 1,
    /// Base address for I/O Virtual Address (IOVA) for admin submission queue
    iova_asq_base: u64 = 0x10000000,
    /// Base address for I/O Virtual Address (IOVA) for admin completion queue
    iova_acq_base: u64 = 0x20000000,
    /// Base address for I/O Virtual Address (IOVA) for I/O queues
    iova_sq_base: u64 = 0x30000000,
    /// Base address for I/O Virtual Address (IOVA) for I/O submission queue
    iova_cq_base: u64 = 0x40000000,
    /// Base address for I/O Virtual Address (IOVA) for data
    iova_data_base: u64 = 0xa0000000,

    pub fn default() NvmDeviceConfig {
        return NvmDeviceConfig{
            .timeout_sec = 10,
            .prefer_cap_to = true,
            .admin_queue_depth = 1,
            .iova_asq_base = 0x10000000,
            .iova_acq_base = 0x20000000,
            .iova_sq_base = 0x30000000,
            .iova_cq_base = 0x40000000,
            .iova_data_base = 0xa0000000,
        };
    }
};
/// Queue control structure for managing submission and completion queues
const SQManage = struct {
    /// tail pointer
    tail: usize = 0,
    /// number of entries
    count: usize = 0,
    /// Maximum depth of the queue
    depth: usize = 0,
    /// body of the queue
    entries: []SQEntry = undefined,

    pub fn create(
        d: usize,
        buf: []align(page_size_min) u8,
    ) !SQManage {
        // check if the buffer size is sufficient
        if (buf.len < @sizeOf(SQEntry) * d) {
            return error.BufferTooSmall;
        }
        // create the queue structure
        return SQManage{
            .tail = 0,
            .count = 0,
            .depth = d,
            .entries = @ptrCast(buf),
        };
    }

    pub fn isFull(self: *const SQManage) bool {
        return self.count >= self.depth;
    }

    pub fn isEmpty(self: *const SQManage) bool {
        return self.count == 0;
    }

    pub fn pushTail(self: *SQManage, entry: *const SQEntry) !void {
        if (self.isFull()) {
            return error.QueueFull;
        }
        self.entries[self.tail] = entry;
        self.tail = (self.tail + 1) % self.depth;
        self.count += 1;
    }

    pub fn send(self: *SQManage, sq_doorbell: *u64) !usize {
        // Ensure the queue is not empty before updating the doorbell
        if (self.isEmpty()) {
            return error.QueueEmpty;
        }
        // Update the tail pointer in the doorbell
        @atomicStore(u32, &sq_doorbell, @intCast(self.tail), std.builtin.AtomicOrder.release);
        // clear the count
        const old_count = self.count;
        self.count = 0;
        return old_count; // Return the number of entries that were pushed
    }
};

const CQManage = struct {
    /// head pointer
    head: usize = 0,
    /// number of entries
    count: usize = 0,
    /// Maximum depth of the queue
    depth: usize = 0,
    /// body of the queue
    entries: []CompletionQueueEntry = undefined,

    pub fn create(
        d: usize,
        buf: []align(page_size_min) u8,
    ) !CQManage {
        // check if the buffer size is sufficient
        if (buf.len < @sizeOf(CompletionQueueEntry) * d) {
            return error.BufferTooSmall;
        }
        // create the queue structure
        return CQManage{
            .head = 0,
            .count = 0,
            .depth = d,
            .entries = @ptrCast(buf),
        };
    }

    pub fn isFull(self: *const CQManage) bool {
        return self.count >= self.depth;
    }

    pub fn isEmpty(self: *const CQManage) bool {
        return self.count == 0;
    }

    // TODO: sync cqhdbl
};

/// NVMe device structure
const NvmDevice = struct {
    /// PCI address of the NVMe controller, e.g., "0000:00:1f.2"
    pci_addr: []const u8,
    /// Configuration for the NVM device
    config: NvmDeviceConfig,
    /// Pointer to the controller registers
    ctrl_reg: *volatile ControllerRegister,
    /// VFIO Container
    vfio_container: vfio.Container,
    /// Admin Submission Queue DataBody
    asq_body: ?vfio.MappedBuf = null,
    /// Admin Completion Queue DataBody
    acq_body: ?vfio.MappedBuf = null,
    // Admin Submission Queue Management
    asq: SQManage = undefined,
    // Admin Completion Queue Management
    acq: CQManage = undefined,

    fn timeoutSec(self: *const NvmDevice) u32 {
        if (self.config.prefer_cap_to and self.ctrl_reg.cap.to != 0) {
            return self.ctrl_reg.cap.to;
        } else {
            return self.config.timeout_sec;
        }
    }
    fn isTimeoutExceeded(self: *const NvmDevice, start: i64) bool {
        const timeout_ms = self.timeoutSec() * 1000;
        return (std.time.milliTimestamp() - start) > timeout_ms;
    }

    fn freeAdminQueues(self: *NvmDevice) !void {
        if (self.asq_body) |_| {
            try self.asq_body.?.free(&self.vfio_container);
        }
        if (self.acq_body) |_| {
            try self.acq_body.?.free(&self.vfio_container);
        }
        self.asq_body = null;
        self.acq_body = null;
    }

    /// Initialize the NVM device by mapping the controller registers from BAR0.
    pub fn open(pci_addr: []const u8, config: *const NvmDeviceConfig) !NvmDevice {
        const vfio_container = try vfio.Container.create(pci_addr);
        const ctrl_reg: *volatile ControllerRegister = @ptrCast(vfio_container.bar0_map);
        if (!ctrl_reg.isValid()) {
            return error.InvalidControllerRegister;
        }
        // 成功したのでリソースの所有権をムーブ
        const dev = NvmDevice{
            .pci_addr = pci_addr,
            .config = config.*,
            .vfio_container = vfio_container,
            .ctrl_reg = ctrl_reg,
        };
        return dev;
    }

    /// Deinitialize the NVM device, unmapping the controller registers and closing the file descriptor.
    pub fn close(self: *NvmDevice) !void {
        // If the device is enabled, attempt to shut it down gracefully
        if (self.status() != DeviceStatus.Disabled) {
            self.shutdown(ShutdownNotification.normal) catch |err| {
                if (err != error.Timeout) {
                    return err; // Only propagate non-timeout errors
                }
                // controller disable if shutdown failed
                self.reset() catch |reset_err| {
                    if (reset_err != error.Timeout) {
                        return reset_err; // Only propagate non-timeout errors
                    }
                };
            };
        }
        // Release the ASQ/ACQ buffers if they were allocated
        try self.freeAdminQueues();
        // Unmap the controller registers
        self.vfio_container.remove();
    }

    /// print hexdump of the controller registers.
    pub fn printRaw(self: *const NvmDevice, writer: anytype) !void {
        try util.printHexdump(writer, self.vfio_container.bar0_map, @sizeOf(ControllerRegister));
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
    /// Controller Reset
    pub fn reset(self: *NvmDevice) !void {
        // set en = 0 to disable the controller
        var cc_disable = self.ctrl_reg.cc;
        cc_disable.en = 0;
        @atomicStore(ControllerConfiguration, &self.ctrl_reg.cc, cc_disable, std.builtin.AtomicOrder.release);
        const start_reset = std.time.milliTimestamp();
        while (self.ctrl_reg.csts.rdy != 0) {
            if (self.isTimeoutExceeded(start_reset)) {
                return error.Timeout;
            }
            std.time.sleep(sleep_ns);
        }
    }

    pub fn enable(self: *NvmDevice) !void {
        // Check if the Admin Queue already exists
        try self.freeAdminQueues();

        // allocate ASQ and ACQ
        const admin_queue_depth = self.config.admin_queue_depth;
        const asq_size = util.alignUp(admin_queue_depth * @sizeOf(SQEntry), page_size_min);
        const acq_size = util.alignUp(admin_queue_depth * @sizeOf(CompletionQueueEntry), page_size_min);
        const flags = c.VFIO_DMA_MAP_FLAG_READ | c.VFIO_DMA_MAP_FLAG_WRITE;
        self.asq_body = try vfio.MappedBuf.alloc(self.config.iova_asq_base, asq_size, flags, &self.vfio_container);
        self.acq_body = try vfio.MappedBuf.alloc(self.config.iova_acq_base, acq_size, flags, &self.vfio_container);
        self.asq = try SQManage.create(admin_queue_depth, self.asq_body.?.buf);
        self.acq = try CQManage.create(admin_queue_depth, self.acq_body.?.buf);
        errdefer {
            self.asq = undefined;
            self.acq = undefined;
            self.asq_body.?.free(&self.vfio_container) catch {};
            self.acq_body.?.free(&self.vfio_container) catch {};
            self.asq_body = null;
            self.acq_body = null;
        }
        // set ASQ, ACQ, AQA
        self.ctrl_reg.aqa = AdminQueueAttributes{
            .asqs = admin_queue_depth,
            ._rsvd0 = 0,
            .acqs = admin_queue_depth,
            ._rsvd1 = 0,
        };
        self.ctrl_reg.asq = @intCast(self.config.iova_asq_base);
        self.ctrl_reg.acq = @intCast(self.config.iova_acq_base);

        // set en = 1 to enable the controller
        var cc_enable = self.ctrl_reg.cc;
        cc_enable.en = 1;
        @atomicStore(ControllerConfiguration, &self.ctrl_reg.cc, cc_enable, std.builtin.AtomicOrder.release);
        const start_enable = std.time.milliTimestamp();
        while (self.ctrl_reg.csts.rdy != 1) {
            if (self.isTimeoutExceeded(start_enable)) {
                return error.Timeout;
            }
            std.time.sleep(sleep_ns);
        }
    }

    pub fn resetAndEnable(self: *NvmDevice) !void {
        try self.reset(); // Reset the controller first
        try self.enable(); // Then enable the controller
    }

    pub fn resetSubsystem(self: *NvmDevice) !void {
        // CAP.NSSRS must be 1 to support NVM Subsystem Reset
        if (self.ctrl_reg.cap.nssrs == 0) {
            return error.NssrNotSupported;
        }
        // NVM Subsystem Reset
        @atomicStore(u32, &self.ctrl_reg.nssr, 0x4e564d65, std.builtin.AtomicOrder.release); // "NVM" in ASCII
        const start_reset = std.time.milliTimestamp();
        while (self.ctrl_reg.csts.nssro == 0) {
            if (self.isTimeoutExceeded(start_reset)) {
                return error.Timeout;
            }
            std.time.sleep(sleep_ns);
        }
    }

    pub fn shutdown(self: *NvmDevice, shn: ShutdownNotification) !void {
        // already shutdown?
        if (self.status() == DeviceStatus.Shutdown) {
            return;
        }

        // set SHN in Controller Configuration
        if (self.status() != DeviceStatus.ShutdownInProgress) {
            var cc_shutdown = self.ctrl_reg.cc;
            cc_shutdown.shn = shn;
            @atomicStore(ControllerConfiguration, &self.ctrl_reg.cc, cc_shutdown, std.builtin.AtomicOrder.release);
        }

        // wait for shutdown to complete
        const start_shutdown = std.time.milliTimestamp();
        while (self.ctrl_reg.csts.shst != ShutdownStatus.shutdown) {
            if (self.isTimeoutExceeded(start_shutdown)) {
                return error.Timeout;
            }
            std.time.sleep(sleep_ns);
        }
    }

    pub fn pushAdminCmd(self: *NvmDevice, cmd: *const SQEntry) !void {
        // Check if the Controller is enabled and ready
        if (self.status() != DeviceStatus.Enabled) {
            try self.resetAndEnable();
        }
        // Push the command to the ASQ
        try self.asq.pushTail(&cmd);
    }

    pub fn updateAsqDoorbell(self: *NvmDevice) !usize {
        // Check if the Controller is enabled and ready
        if (self.status() != DeviceStatus.Enabled) {
            return error.ControllerNotReady;
        }
        const pushed_count = try self.asq.send(&self.ctrl_reg.asq);
        return pushed_count;
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
    aqa: AdminQueueAttributes, // 0x24 Admin Queue Attributes
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
        .aqa = AdminQueueAttributes{
            .asqs = 2, // Admin Submission Queue Size
            ._rsvd0 = 0,
            .acqs = 2, // Admin Completion Queue Size
            ._rsvd1 = 0,
        },
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
const AdminQueueAttributes = packed struct {
    asqs: u12, // [11:0] Admin Submission Queue Size
    _rsvd0: u4, // [15:12] Reserved
    acqs: u12, // [27:16] Admin Completion Queue Size
    _rsvd1: u4, // [31:28] Reserved
};

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
        \\-t, --timeout <u32>    Set timeout for controller reset in seconds (default: 10).
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

    var config = NvmDeviceConfig.default();
    if (res.args.timeout) |timeout| {
        if (timeout < 1) {
            try stderr.print("Timeout must be at least 1 second.\n", .{});
            return error.InvalidArgument;
        }
        config.timeout_sec = timeout;
        config.prefer_cap_to = false; // Use the provided timeout instead of CAP.TO
    }
    var device = try NvmDevice.open(pci_addr, &config);
    defer device.close() catch {};
    if (verbose) {
        try stdout.print("[Initial] Current status: {}\n", .{device.status()});
    }

    try device.resetAndEnable();
    if (verbose) {
        try stdout.print("[Post-Reset] Current status: {}\n", .{device.status()});
    }

    try device.shutdown(ShutdownNotification.normal);
    if (verbose) {
        try stdout.print("[Post-Shutdown] Current status: {}\n", .{device.status()});
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
        try device.printRaw(stdout);

        try stdout.print("Parsed: {}\n", .{device.ctrl_reg});
    }
}
