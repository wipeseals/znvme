// src/main.zig
const std = @import("std");
const log = std.log;
const expect = std.testing.expect;

const vfio = @import("vfio.zig");
const cmd = @import("cmd.zig");
const util = @import("util.zig");

// VFIO用Cヘッダのインクルード
const c = @cImport({
    @cInclude("linux/vfio.h");
    @cInclude("sys/ioctl.h");
});

const page_size_min = std.heap.page_size_min;

/// Device status enumeration
pub const DeviceStatus = enum {
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
pub const NvmDeviceConfig = struct {
    pci_addr: []const u8,
    timeout_sec: u32,
    prefer_cap_to: bool,
    admin_queue_depth: u12,
    force: bool,
    // VFIO Buffer Pool for Queues
    buf_pool_queue_iova: u64,
    buf_pool_queue_size: usize,
    // VFIO Buffer Pool for Data (Large Data Transfers)
    iova_data_base: u64,
    iova_data_size: usize,

    pub fn default() NvmDeviceConfig {
        return NvmDeviceConfig{
            .pci_addr = "0000:00:00.0",
            .timeout_sec = 30,
            .prefer_cap_to = true,
            .admin_queue_depth = 32,
            .force = false,
            .buf_pool_queue_iova = 0x10000000,
            .buf_pool_queue_size = 256 * (@sizeOf(cmd.SQEntry) + @sizeOf(cmd.CQEntry)),
            .iova_data_base = 0x20000000,
            .iova_data_size = 512 * 1024 * 1024,
        };
    }
};
// TODO: IOVA Allocation Logic for Queue/Datas

/// NVMe device structure
pub const NvmDevice = struct {
    /// PCI address of the NVMe controller, e.g., "0000:00:1f.2"
    pci_addr: []const u8,
    /// Configuration for the NVM device
    config: NvmDeviceConfig,
    /// Pointer to the controller registers
    ctrl_reg: *volatile ControllerRegister,
    /// VFIO Container
    vfio_container: vfio.Container,
    /// DMA Buffer Pool for Queues
    buf_pool_queues: vfio.DmaBufPool,
    /// DMA Buffer Pool for Data
    buf_pool_data: vfio.DmaBufPool,
    /// Admin Queue
    admin_queue: ?cmd.QPair,

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

    /// Initialize the NVM device by mapping the controller registers from BAR0.
    pub fn open(config: *const NvmDeviceConfig) !NvmDevice {
        // Create a VFIO container for the specified PCI address
        var vfio_container = try vfio.Container.create(config.pci_addr);
        errdefer vfio_container.remove();

        // Map the controller registers from BAR0
        const ctrl_reg: *volatile ControllerRegister = @ptrCast(vfio_container.bar0_map);
        if (!ctrl_reg.isValid()) {
            // If the force option is enabled, we proceed anyway
            if (!config.force) {
                return error.InvalidControllerRegister;
            }
        }
        // Allocate DMA buffer pools for queues and data
        var buf_pool_queues = try vfio.DmaBufPool.init(
            config.buf_pool_queue_iova,
            config.buf_pool_queue_size,
            c.VFIO_DMA_MAP_FLAG_READ | c.VFIO_DMA_MAP_FLAG_WRITE,
            &vfio_container,
        );
        errdefer buf_pool_queues.deinit(&vfio_container) catch {};
        const buf_pool_data = try vfio.DmaBufPool.init(
            config.iova_data_base,
            config.iova_data_size,
            c.VFIO_DMA_MAP_FLAG_READ | c.VFIO_DMA_MAP_FLAG_WRITE,
            &vfio_container,
        );
        // 成功したのでリソースの所有権をムーブ
        const dev = NvmDevice{
            .pci_addr = config.pci_addr,
            .config = config.*,
            .vfio_container = vfio_container,
            .ctrl_reg = ctrl_reg,
            .buf_pool_queues = buf_pool_queues,
            .buf_pool_data = buf_pool_data,
            .admin_queue = null, // Initially no admin queue
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
        if (self.admin_queue) |_| {
            try self.admin_queue.?.delete(&self.buf_pool_queues);
            self.admin_queue = null;
        }
        // Unmap the controller registers
        self.vfio_container.remove();
    }

    /// print hexdump of the controller registers.
    pub fn printCtrlRegs(self: *const NvmDevice, writer: anytype) !void {
        try util.printHexdump(writer, self.vfio_container.bar0_map, @sizeOf(ControllerRegister));
    }

    pub fn printAdminQueue(self: *const NvmDevice, writer: anytype) !void {
        if (self.admin_queue) |q| {
            try writer.print("Admin Submission Queue", .{});
            try util.printHexdump(writer, q.sq_body.buf, q.sq_body.buf.len);
            try writer.print("Admin Completion Queue", .{});
            try util.printHexdump(writer, q.cq_body.buf, q.cq_body.buf.len);
            try self.printDoorbell(writer, 0);
        } else {
            try writer.print("Admin Queue is not initialized.\n", .{});
        }
    }

    pub fn printDoorbell(self: *const NvmDevice, writer: anytype, queue_id: u32) !void {
        const doorbell = try self.doorbellPtr(queue_id);
        try writer.print("Doorbell for Queue {d}:\n", .{queue_id});
        try writer.print("  SQ: {}(@0x{x})\n", .{ doorbell.sq.*, @intFromPtr(doorbell.sq) });
        try writer.print("  CQ: {}(@0x{x})\n", .{ doorbell.cq.*, @intFromPtr(doorbell.cq) });
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
            std.time.sleep(1);
        }
    }

    pub fn enable(self: *NvmDevice) !void {
        // Check if the Admin Queue already exists
        if (self.admin_queue) |_| {
            try self.admin_queue.?.delete(&self.buf_pool_queues);
            self.admin_queue = null; // Clear the existing queue
        }

        // allocate ASQ and ACQ
        const doorbell = try self.doorbellPtr(0);
        // clear Admin CQ/SQ Doorbell
        @atomicStore(u32, doorbell.sq, 0x0, std.builtin.AtomicOrder.release);
        @atomicStore(u32, doorbell.cq, 0x0, std.builtin.AtomicOrder.release);

        self.admin_queue = try cmd.QPair.create(
            self.config.admin_queue_depth,
            self.config.admin_queue_depth,
            &doorbell,
            &self.buf_pool_queues,
        );
        errdefer {
            self.admin_queue.?.delete(&self.buf_pool_queues) catch {};
            self.admin_queue = null;
        }

        // set ASQ, ACQ, AQA
        self.ctrl_reg.aqa = AdminQueueAttributes{
            .asqs = self.config.admin_queue_depth,
            ._rsvd0 = 0,
            .acqs = self.config.admin_queue_depth,
            ._rsvd1 = 0,
        };
        self.ctrl_reg.asq = @intCast(self.admin_queue.?.sq_body.iova);
        self.ctrl_reg.acq = @intCast(self.admin_queue.?.cq_body.iova);

        // set en = 1 to enable the controller
        var cc_enable = self.ctrl_reg.cc;
        cc_enable.en = 1;
        @atomicStore(ControllerConfiguration, &self.ctrl_reg.cc, cc_enable, std.builtin.AtomicOrder.release);
        const start_enable = std.time.milliTimestamp();
        while (self.ctrl_reg.csts.rdy != 1) {
            if (self.isTimeoutExceeded(start_enable)) {
                return error.Timeout;
            }
            std.time.sleep(1);
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
            std.time.sleep(1);
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
            std.time.sleep(1);
        }
    }

    /// Get the doorbell address
    fn doorbellPtr(self: *const NvmDevice, queue_id: u32) !cmd.Doorbell {
        const base = 0x1000;
        const dstrd = self.ctrl_reg.cap.dstrd;

        // Start: 0x00 + (idx * (4 << dstrd))
        //   id: sq0, cq0, iosq1, iocq1, ...
        const sq_idx = queue_id * 2;
        const cq_idx = sq_idx + 1;
        const sq_doorbell_offset = base + (sq_idx * (@as(usize, 4) << dstrd));
        const cq_doorbell_offset = base + (cq_idx * (@as(usize, 4) << dstrd));
        // Ensure the offsets are within the bounds of BAR0
        const sq_doorbell_ptr: []align(4) u8 = @alignCast(self.vfio_container.bar0_map[sq_doorbell_offset..][0..4]);
        const cq_doorbell_ptr: []align(4) u8 = @alignCast(self.vfio_container.bar0_map[cq_doorbell_offset..][0..4]);
        return cmd.Doorbell{
            .sq = @ptrCast(sq_doorbell_ptr),
            .cq = @ptrCast(cq_doorbell_ptr),
        };
    }
};

pub const ControllerRegister = packed struct {
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
pub const ControllerCapabilities = packed struct {
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
pub const SpecificationVersion = packed struct {
    ter: u8, // [7:0]  Terse Version
    min: u8, // [15:8] Minor Version
    maj: u16, // [31:16] Major Version
};

pub const ControllerConfiguration = packed struct {
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

pub const ShutdownNotification = enum(u2) {
    none = 0b00, // No notification and no effect
    normal = 0b01, // Normal shutdown
    abrupt = 0b10, // Abrupt shutdown
    reserved = 0b11, // Reserved
};

pub const ShutdownStatus = enum(u2) {
    normal = 0b00, // Normal operation
    shutdownInProgress = 0b01, // Shutdown in progress
    shutdown = 0b10, // Shutdown completed
    reserved = 0b11, // Reserved
};
pub const ControllerStatus = packed struct {
    rdy: u1, // [0] Ready
    cfs: u1, // [1] Controller Fatal Status
    shst: ShutdownStatus, // [3:2] Shutdown Status
    nssro: u1, // [4] NVM Subsystem Reset Occurred
    pp: u1, // [5] Processing Paused
    st: u1, // [6] Shutdown Type 1 = NVM Subsystem Reset, 0 = Controller Level Resets
    _rsvd0: u25, // [31:07] Reserved
};
pub const AdminQueueAttributes = packed struct {
    asqs: u12, // [11:0] Admin Submission Queue Size
    _rsvd0: u4, // [15:12] Reserved
    acqs: u12, // [27:16] Admin Completion Queue Size
    _rsvd1: u4, // [31:28] Reserved
};

test "Controller Capabilities Size" {
    const size = @sizeOf(ControllerCapabilities);
    try expect(size == 8);
}
test "Specification Version Size" {
    const size = @sizeOf(SpecificationVersion);
    try expect(size == 4);
}
test "Controller Configuration Size" {
    const size = @sizeOf(ControllerConfiguration);
    try expect(size == 4);
}

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
