const std = @import("std");
const fs = std.fs;
const util = @import("util.zig");

const c = @cImport({
    @cInclude("linux/vfio.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
});

// VFIO が Page alignedなメモリを要求するため、page_allocator固定
const page_size_min = std.heap.page_size_min;
const allocator = std.heap.page_allocator;

/// Represents a mapping between an I/O Virtual Address (IOVA) and a buffer.
pub const DmaMap = struct {
    iova: u64,
    buf: []const u8,
    flags: c_uint,
    active: bool,

    /// Initializes and maps a new Map instance with the specified IOVA, buffer, and flags.
    pub fn create(iova: u64, buf: []const u8, flags: c_uint, vfio: *Container) !DmaMap {
        var map = DmaMap{
            .iova = iova,
            .buf = buf,
            .flags = flags,
            .active = false,
        };
        try vfio.map_dma(&map);
        return map;
    }

    /// Unmaps the DMA region associated with this Map instance.
    pub fn delete(self: *DmaMap, vfio: *Container) !void {
        if (!self.active) {
            return; // Already unmapped
        }
        try vfio.unmap_dma(self);
    }
};
pub const DmaBuf = struct {
    buf: []align(page_size_min) u8,
    map: DmaMap,

    /// Initializes a new DmaBuf instance with the specified I/O Virtual Address (IOVA) and flags.
    pub fn alloc(iova: u64, size: usize, flags: c_uint, vfio: *Container) !DmaBuf {
        const buf = try allocator.alignedAlloc(u8, page_size_min, size);
        errdefer allocator.free(buf);
        const map = try DmaMap.create(iova, buf, flags, vfio);
        return DmaBuf{
            .buf = buf,
            .map = map,
        };
    }

    /// Opens the mapping for the specified I/O Virtual Address (IOVA) and flags.
    pub fn free(self: *DmaBuf, vfio: *Container) !void {
        try self.map.delete(vfio);
        allocator.free(self.buf);
    }
};

pub const DmaBufPoolEntry = struct {
    buf: []align(page_size_min) u8,
    iova: u64,
    page_index: usize,
    page_count: usize,
};

pub const DmaBufPool = struct {
    dma_buf: DmaBuf,
    free_bitset: std.StaticBitSet,

    /// Initializes a new DmaBufPool with the specified I/O Virtual Address (IOVA) and flags.
    pub fn init(iova: u64, size: usize, flags: c_uint, vfio: *Container) !DmaBufPool {
        const dma_buf = try DmaBuf.alloc(iova, size, flags, vfio);
        const free_bitset = std.StaticBitSet(size / page_size_min).initFull();
        return DmaBufPool{
            .dma_buf = dma_buf,
            .free_bitset = free_bitset,
        };
    }

    /// Allocates a new buffer from the pool.
    pub fn alloc(self: *DmaBufPool, size: usize) !DmaBufPoolEntry {
        // align size to page size
        const aligned_size = util.alignUp(size, page_size_min);
        const page_count = aligned_size / page_size_min;
        // find a free page in the bitmap
        const alloc_page_index = util.findNConsecutiveOnes(self.free_bitset, page_count) orelse {
            return error.NoFreePage; // No free page available
        };
        // mark the page as used
        self.free_bitset.setValue(alloc_page_index, false);
        // calculate the IOVA and buffer pointer
        const iova = alloc_page_index * page_size_min + self.dma_buf.map.iova;
        const buf_ptr = self.dma_buf.buf[alloc_page_index * page_size_min .. (alloc_page_index + 1) * page_size_min];
        return DmaBufPoolEntry{
            .buf = buf_ptr,
            .iova = iova,
            .page_index = alloc_page_index, // for freeing later
            .page_count = page_count, // number of pages allocated
        };
    }

    /// Frees a previously allocated buffer back to the pool.
    pub fn free(self: *DmaBufPool, entry: *const DmaBufPoolEntry) void {
        const free_page_index = entry.page_index;
        if (self.free_bitset.isSet(free_page_index)) {
            return error.PageAlreadyFree; // Page is already free
        }
        // mark the pages as free in the bitmap
        for (0..entry.page_count) |i| {
            self.free_bitset.setValue(free_page_index + i, true);
        }
    }

    /// Frees the resources associated with this DmaBufPool.
    pub fn deinit(self: *DmaBufPool, vfio: *Container) !void {
        try self.dma_buf.free(vfio);
        self.free_bitset.deinit(allocator);
    }
};

/// VFIO (Virtual Function I/O) interface for managing PCI devices in a virtualized environment.
pub const Container = struct {
    container_fd: std.posix.fd_t,
    group_fd: std.posix.fd_t,
    device_fd: std.posix.fd_t,
    bar0_map: []align(page_size_min) u8,

    pub fn create(pci_addr: []const u8) !Container {
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

        // PCIアドレスからグループ番号を取得
        // IOMMUグループへのシンボリックリンクのパスを構築し、指し先からiommu_groupsのグループ番号を取得
        // e.g. : ../../../../kernel/iommu_groups/14
        const symlink_path = try std.fmt.allocPrint(
            allocator,
            "/sys/bus/pci/devices/{s}/iommu_group",
            .{pci_addr},
        );
        defer allocator.free(symlink_path);
        var link_target_cstr: [fs.max_path_bytes]u8 = undefined;
        const link_target = try std.fs.readLinkAbsolute(symlink_path, &link_target_cstr);
        // パスから末尾のファイル名（グループ番号の文字列）を抽出
        const group_name_str = std.fs.path.basename(link_target);
        const group_num = try std.fmt.parseInt(u32, group_name_str, 10);

        // /dev/vfio/<group> をopen -> group FD
        const vfio_group_path = try std.fmt.allocPrint(allocator, "/dev/vfio/{d}", .{group_num});
        defer allocator.free(vfio_group_path);
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

    pub fn remove(self: *Container) void {
        // Unmap the controller registers
        std.posix.munmap(self.bar0_map);
        std.posix.close(self.device_fd);
        std.posix.close(self.group_fd);
        std.posix.close(self.container_fd);
    }

    /// Maps a DMA region for the specified I/O Virtual Address (IOVA) and data.
    pub fn map_dma(
        self: *Container,
        map: *DmaMap,
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
        map: *DmaMap,
    ) !void {
        const dma_unmap = c.vfio_iommu_type1_dma_unmap{
            .argsz = @sizeOf(c.vfio_iommu_type1_dma_unmap),
            .flags = 0,
            .iova = map.iova,
            .size = map.buf.len,
        };
        map.active = false;
        const ret = c.ioctl(self.container_fd, c.VFIO_IOMMU_UNMAP_DMA, &dma_unmap);
        if (ret < 0) {
            return error.VfioUnmapDmaFailed;
        }
    }
};
