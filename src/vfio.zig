const std = @import("std");
const c = @import("c.zig");
const page_size_min = std.heap.page_size_min;
const util = @import("util.zig");

/// Represents a mapping between an I/O Virtual Address (IOVA) and a buffer.
/// TODO: bufferの確保も内在させ、Freeの責務をはっきりさせておく
pub const Map = struct {
    pub iova: u64;
    pub buf: []const u8;
    pub flags: c_uint;
    active: bool = false;

    pub fn init(iova: u64, buf: []const u8, flags: c_uint) Map {
        return Map{
            .iova = iova,
            .buf = buf,
            .flags = flags,
            .active = false,
        };
    }

    /// Creates a new Map instance with the specified I/O Virtual Address (IOVA), buffer, and flags.
    pub fn open(self: *Map, vfio: *Container) !Map {
        try vfio.map_dma(self);
        return self;
    }

    /// Unmaps the DMA region associated with this Map instance.
    pub fn close(self: *Map, vfio: *Container) !void {
        if (!self.active) {
            return; // Already unmapped
        }
        try vfio.unmap_dma(self);
        // free buffer

    }
};

/// VFIO (Virtual Function I/O) interface for managing PCI devices in a virtualized environment.
pub const Container = struct {
    pub container_fd: std.posix.fd_t;
    pub group_fd: std.posix.fd_t;
    pub device_fd: std.posix.fd_t;
    pub bar0_map: []align(page_size_min) u8;

    pub fn open(pci_addr: []const u8, group_num: u32) !Container {
        var container_fd: std.posix.fd_t = -1;
        var group_fd: std.posix.fd_t = -1;
        var device_fd: std.posix.fd_t = -1;
        var bar0_map: []align(page_size_min) u8 = &[_]u8{};

        errdefer {
            if (bar0_map.len > 0) std.posix.munmap(bar0_map);
            if (device_fd != -1) std.posix.close(device_fd);
            if (group_fd != -1) std.posix.close(group_fd);
            if (container_fd != -1) std.posix.close(container_fd);
        }

        // /dev/vfio/<group> をopen -> group FD
        const vfio_group_path = try std.fmt.allocPrint(std.heap.page_allocator, "/dev/vfio/{d}", .{group_num});
        defer std.heap.page_allocator.free(vfio_group_path);
        group_fd = try std.posix.open(vfio_group_path, .{ .ACCMODE = .RDWR }, 0);

        // グループの状態を確認する
        var group_status: c.struct_vfio_group_status = undefined;
        group_status.argsz = @sizeOf(@TypeOf(group_status));
        if (c.ioctl(group_fd, c.VFIO_GROUP_GET_STATUS, &group_status) < 0) {
            return error.VfioGetGroupStatusFailed;
        }
        // グループがViableでない（例えば一部デバイスがホストドライバを使用中など）
        if (group_status.flags & c.VFIO_GROUP_FLAGS_VIABLE == 0) {
            return error.VfioGroupNotViable;
        }
        // /dev/vfio/vfio をopen -> container FD
        container_fd = try std.posix.open("/dev/vfio/vfio", .{ .ACCMODE = .RDWR }, 0);
        // VFIO_GROUP_SET_CONTAINER でコンテナにグループを登録
        if (c.ioctl(group_fd, c.VFIO_GROUP_SET_CONTAINER, &container_fd) < 0) {
            return error.VfioSetContainerFailed;
        }
        // VFIO_SET_IOMMU でIOMMUタイプを設定
        if (c.ioctl(container_fd, c.VFIO_SET_IOMMU, c.VFIO_TYPE1_IOMMU) < 0) {
            return error.VfioSetIommuFailed;
        }

        // デバイスのFDを取得
        var pci_addr_cstr: [32]u8 = undefined;
        @memcpy(pci_addr_cstr[0..pci_addr.len], pci_addr);
        pci_addr_cstr[pci_addr.len] = 0;
        const fd_result = c.ioctl(group_fd, c.VFIO_GROUP_GET_DEVICE_FD, &pci_addr_cstr);
        if (fd_result < 0) {
            return error.VfioGetDeviceFdFailed;
        }
        device_fd = @intCast(fd_result);
        // VFIO_PCI_BAR0_REGION_INDEX でBAR0空間の情報を取得
        var region_info: c.struct_vfio_region_info = .{ .argsz = @sizeOf(c.struct_vfio_region_info) };
        region_info.index = c.VFIO_PCI_BAR0_REGION_INDEX;
        if (c.ioctl(device_fd, c.VFIO_DEVICE_GET_REGION_INFO, &region_info) != 0) {
            return error.VfioGetRegionInfoFailed;
        }
        // vfio_device_fd と region_info を使ってBAR0空間にアクセス
        bar0_map = try std.posix.mmap(
            null,
            region_info.size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            device_fd,
            region_info.offset,
        );

        if (bar0_map.len == 0) {
            return error.VfioMmapFailed;
        }

        return Container{
            .container_fd = container_fd,
            .group_fd = group_fd,
            .device_fd = device_fd,
            .bar0_map = bar0_map,
        };
    }

    pub fn close(self: *Container) void {
        // Unmap the controller registers
        std.posix.munmap(self.bar0_map);
        std.posix.close(self.device_fd);
        std.posix.close(self.group_fd);
        std.posix.close(self.container_fd);
    }

    /// Maps a DMA region for the specified I/O Virtual Address (IOVA) and data.
    pub fn map_dma(
        self: *Container,
        map: *Map,
    ) !void {
        const dma_map = c.vfio_iommu_type1_dma_map{
            .argsz = @sizeOf(c.vfio_iommu_type1_dma_map),
            .flags = map.flags,
            .iova = map.iova,
            .size = map.buf.len,
            .vaddr = @intFromPtr(map.buf.ptr),
        };
        const ret = c.ioctl(self.container_fd, c.VFIO_IOMMU_MAP_DMA, &dma_map);
        if (ret < 0) {
            return error.VfioMapDmaFailed;
        }
        map.active = true; // Mark the map as active
    }

    /// Unmaps a DMA region for the specified I/O Virtual Address (IOVA).
    pub fn unmap_dma(
        self: *Container,
        map: *Map,
    ) !void {
        const dma_unmap = c.vfio_iommu_type1_dma_unmap{
            .argsz = @sizeOf(c.vfio_iommu_type1_dma_unmap),
            .flags = 0,
            .iova = map.iova,
            .size = map.buf.len,
            .vaddr = @intFromPtr(map.buf.ptr),
        };
        map.active = false;
        const ret = c.ioctl(self.container_fd, c.VFIO_IOMMU_UNMAP_DMA, &dma_unmap);
        if (ret < 0) {
            return error.VfioUnmapDmaFailed;
        }
    }
};
