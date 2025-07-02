// src/main.zig
const std = @import("std");
const expect = std.testing.expect;
const page_size_min = std.heap.page_size_min;

const clap = @import("clap");

// VFIO用Cヘッダのインクルード
const c = @cImport({
    @cInclude("linux/vfio.h");
    @cInclude("sys/ioctl.h");
    @cInclude("fcntl.h");
    @cInclude("sys/mman.h");
    @cInclude("unistd.h");
    @cInclude("stdint.h");
});

/// NVMe Submission Queue Entry structure
/// TODO: union support for Vendor Specific, ...
const SubmissionQueueEntry = packed struct {
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
    const size = @sizeOf(SubmissionQueueEntry);
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

    pub fn default() NvmDeviceConfig {
        return NvmDeviceConfig{
            .timeout_sec = 10,
            .prefer_cap_to = true,
        };
    }
};
const NvmDevice = struct {
    pci_addr: []const u8,
    config: NvmDeviceConfig,
    vfio_container_fd: std.posix.fd_t,
    vfio_group_fd: std.posix.fd_t,
    vfio_device_fd: std.posix.fd_t,
    ctrl_reg_map: []align(page_size_min) u8,
    ctrl_reg: *volatile ControllerRegister,

    /// Initialize the NVM device by mapping the controller registers from BAR0.
    pub fn open(pci_addr: []const u8, group_num: u32, config: *const NvmDeviceConfig) !NvmDevice {
        const stderr = std.io.getStdErr().writer();

        // --- VFIO経由でデバイスをopen・BAR0マップ ---
        var vfio_container_fd: std.posix.fd_t = -1;
        var vfio_group_fd: std.posix.fd_t = -1;
        var vfio_device_fd: std.posix.fd_t = -1;
        var bar0_map: []align(page_size_min) u8 = &[_]u8{};

        // errdeferを使ったクリーンアップ
        errdefer {
            if (bar0_map.len > 0) std.posix.munmap(bar0_map);
            if (vfio_device_fd != -1) std.posix.close(vfio_device_fd);
            if (vfio_group_fd != -1) std.posix.close(vfio_group_fd);
            if (vfio_container_fd != -1) std.posix.close(vfio_container_fd);
        }

        // /dev/vfio/<group> をopen -> group FD
        const vfio_group_path = try std.fmt.allocPrint(std.heap.page_allocator, "/dev/vfio/{d}", .{group_num});
        defer std.heap.page_allocator.free(vfio_group_path);
        vfio_group_fd = try std.posix.open(vfio_group_path, .{ .ACCMODE = .RDWR }, 0);

        // グループの状態を確認する（この呼び出し自体が重要）
        var group_status: c.struct_vfio_group_status = undefined;
        group_status.argsz = @sizeOf(@TypeOf(group_status));

        if (c.ioctl(vfio_group_fd, c.VFIO_GROUP_GET_STATUS, &group_status) < 0) {
            // エラー処理（本来はここも丁寧に行う）
            try stderr.print("VFIO_GROUP_GET_STATUS failed\n", .{});
            return error.VfioGetGroupStatusFailed;
        }

        if (group_status.flags & c.VFIO_GROUP_FLAGS_VIABLE == 0) {
            // グループがViableでない（例えば一部デバイスがホストドライバを使用中など）
            try stderr.print("VFIO group is not viable\n", .{});
            return error.VfioGroupNotViable;
        }
        // /dev/vfio/vfio をopen -> container FD
        vfio_container_fd = try std.posix.open("/dev/vfio/vfio", .{ .ACCMODE = .RDWR }, 0);

        // APIバージョンを確認
        if (c.ioctl(vfio_container_fd, c.VFIO_GET_API_VERSION) != c.VFIO_API_VERSION) {
            try stderr.print("Unknown VFIO API version\n", .{});
            return error.VfioUnknownApiVersion;
        }

        // IOMMU Type 1 が利用可能か確認する (利用可能時に1)
        if (c.ioctl(vfio_container_fd, c.VFIO_CHECK_EXTENSION, c.VFIO_TYPE1_IOMMU) != 1) {
            try stderr.print("VFIO_TYPE1_IOMMU is not available\n", .{});
            return error.VfioIommuTypeNotSupported;
        }

        // VFIO_GROUP_SET_CONTAINER でコンテナにグループを登録
        const ret3 = c.ioctl(vfio_group_fd, c.VFIO_GROUP_SET_CONTAINER, &vfio_container_fd);
        if (ret3 < 0) {
            const errno = std.posix.errno(-1);
            try stderr.print("VFIO_GROUP_SET_CONTAINER failed: ret:{} errno: {}\n", .{ ret3, errno });
            return error.VfioSetContainerFailed;
        }
        // VFIO_SET_IOMMU でIOMMUタイプを設定
        const ret4 = c.ioctl(vfio_container_fd, c.VFIO_SET_IOMMU, c.VFIO_TYPE1_IOMMU);
        if (ret4 < 0) {
            const errno = std.posix.errno(-1);
            try stderr.print("VFIO_SET_IOMMU failed: ret:{} errno: {}\n", .{ ret4, errno });
            return error.VfioSetIommuFailed;
        }

        // デバイスのFDを取得
        var pci_addr_cstr: [32]u8 = undefined;
        @memcpy(pci_addr_cstr[0..pci_addr.len], pci_addr);
        pci_addr_cstr[pci_addr.len] = 0;
        const fd_result = c.ioctl(vfio_group_fd, c.VFIO_GROUP_GET_DEVICE_FD, &pci_addr_cstr);
        if (fd_result < 0) return error.VfioGetDeviceFdFailed;
        vfio_device_fd = @intCast(fd_result);

        // BAR0情報取得
        var region_info: c.struct_vfio_region_info = .{ .argsz = @sizeOf(c.struct_vfio_region_info) };
        region_info.index = c.VFIO_PCI_BAR0_REGION_INDEX;
        if (c.ioctl(vfio_device_fd, c.VFIO_DEVICE_GET_REGION_INFO, &region_info) != 0) {
            return error.VfioGetRegionInfoFailed;
        }

        // BAR0をmmap
        bar0_map = try std.posix.mmap(
            null,
            region_info.size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            vfio_device_fd,
            region_info.offset,
        );

        const ctrl_reg: *volatile ControllerRegister = @ptrCast(bar0_map.ptr);
        if (!ctrl_reg.isValid()) {
            return error.InvalidControllerRegister;
        }

        // 成功したのでリソースの所有権をムーブ
        const dev = NvmDevice{
            .pci_addr = pci_addr,
            .config = config.*,
            .vfio_container_fd = vfio_container_fd,
            .vfio_group_fd = vfio_group_fd,
            .vfio_device_fd = vfio_device_fd,
            .ctrl_reg_map = bar0_map,
            .ctrl_reg = ctrl_reg,
        };

        // errdeferが発動しないように-1をセット
        vfio_container_fd = -1;
        vfio_group_fd = -1;
        vfio_device_fd = -1;
        bar0_map = &[_]u8{};

        return dev;
    }

    /// Deinitialize the NVM device, unmapping the controller registers and closing the file descriptor.
    pub fn close(self: NvmDevice) void {
        std.posix.munmap(self.ctrl_reg_map);
        std.posix.close(self.vfio_device_fd);
        std.posix.close(self.vfio_group_fd);
        std.posix.close(self.vfio_container_fd);
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
    pub fn timeoutSec(self: *const NvmDevice) u32 {
        if (self.config.prefer_cap_to & self.ctrl_reg.cap.to != 0) {
            return self.ctrl_reg.cap.to;
        } else {
            return self.config.timeout_sec;
        }
    }
    fn isTimeoutExceeded(self: *const NvmDevice, start: u64) bool {
        const timeout_ms = self.timeoutSec() * 1000;
        return (std.time.milliTimestamp() - start) > timeout_ms;
    }
    /// Controller Reset
    pub fn resetController(self: *NvmDevice) !void {
        // set en = 0 to disable the controller
        {
            self.ctrl_reg.cc.en = 0;
            const start = std.time.milliTimestamp();
            while (self.ctrl_reg.csts.rdy != 0) {
                if (self.isTimeoutExceeded(start)) {
                    return error.Timeout;
                }
            }
        }
        // TODO: vfio physical address space
        // allocate ASQ and ACQ
        // const size = @sizeOf(u32) * self.ctrl_reg.cap.mqes;
        // const asq = try std.heap.page_allocator.alignedAlloc(u32, page_size_min, size);
        // const acq = try std.heap.page_allocator.alignedAlloc(u32, page_size_min, size);

        // set ASQ, ACQ, AQA
        self.ctrl_reg.aqa = 0; // depth = 1

        // set en = 1 to enable the controller
        {
            self.ctrl_reg.cc.en = 1;
            const start = std.time.milliTimestamp();
            while (self.ctrl_reg.csts.rdy != 1) {
                if (self.isTimeoutExceeded(start)) {
                    return error.Timeout;
                }
            }
        }
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
        \\-t, --timeout <u32>    Set timeout for controller reset in seconds (default: 10).
        \\<str>                  PCI address of the NVMe controller (e.g., 0000:00:1f.2).
        \\<u32>                  IOMMU group number (required).
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

    // TODO: readlink -f /sys/bus/pci/devices/<pci_addr>/iommu_group  相当を行ってgroup_numを取得できるはず
    const group_num = res.positionals[1] orelse {
        try stderr.print("IOMMU group number is required.\n", .{});
        return error.InvalidArgument;
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
    const device = try NvmDevice.open(pci_addr, group_num, &config);
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
