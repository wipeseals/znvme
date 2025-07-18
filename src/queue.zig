const std = @import("std");
const expect = std.testing.expect;
const page_size_min = std.heap.page_size_min;
const vfio = @import("vfio.zig"); // 汎用化を目指すならvfio.DmaBufPool からvfioの依存性を切れるようにする
const util = @import("util.zig");

pub const QPair = struct {
    sq: SQManage,
    cq: CQManage,
    sq_body: vfio.DmaBufPoolEntry,
    cq_body: vfio.DmaBufPoolEntry,

    pub fn create(
        sq_depth: usize,
        cq_depth: usize,
        doorbell: *const Doorbell,
        dma_pool: *vfio.DmaBufPool,
    ) !QPair {
        const sq_size = util.alignUp(sq_depth * @sizeOf(SQEntry), page_size_min);
        const cq_size = util.alignUp(cq_depth * @sizeOf(CQEntry), page_size_min);
        // Allocate buffers for submission and completion queues
        const sq_body = try dma_pool.alloc(sq_size);
        const cq_body = try dma_pool.alloc(cq_size);

        return QPair{
            .sq = try SQManage.create(sq_depth, sq_body.buf, doorbell.sq),
            .cq = try CQManage.create(cq_depth, cq_body.buf, doorbell.cq),
            .sq_body = sq_body,
            .cq_body = cq_body,
        };
    }

    pub fn delete(self: *QPair, dma_pool: *vfio.DmaBufPool) !void {
        try dma_pool.free(&self.sq_body);
        try dma_pool.free(&self.cq_body);
    }

    pub fn push(self: *QPair, entry: *const SQEntry) !void {
        try self.sq.pushTail(entry);
    }
};

pub const Doorbell = struct {
    /// Submission Queue Doorbell Pointer
    sq: *volatile u32,
    /// Completion Queue Doorbell Pointer
    cq: *volatile u32,

    pub fn init(sq: *volatile u32, cq: *volatile u32) Doorbell {
        return Doorbell{
            .sq = sq,
            .cq = cq,
        };
    }
};

/// Queue control structure for managing submission and completion queues
pub const SQManage = struct {
    /// tail pointer
    tail: usize = 0,
    /// number of entries
    count: usize = 0,
    /// Maximum depth of the queue
    depth: usize = 0,
    /// body of the queue
    entries: []SQEntry = undefined,
    /// Doorbell pointer
    doorbell: *volatile u32 = undefined,
    /// head pointer (sync CQ.SQHD)
    head: usize = 0,

    pub fn create(
        d: usize,
        buf: []align(page_size_min) u8,
        doorbell: *volatile u32,
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
            .doorbell = doorbell,
        };
    }

    pub fn isFull(self: *const SQManage) bool {
        return self.count >= self.depth;
    }

    pub fn isEmpty(self: *const SQManage) bool {
        return self.count == 0;
    }

    pub fn tailPtr(self: *const SQManage, offset: usize) !*SQEntry {
        // Ensure the tail is within bounds
        if ((self.count + offset) >= self.depth) {
            return error.QueueFull;
        }
        // Calculate the tail pointer with wrap-around
        const tail_index = (self.tail + offset) % self.depth;
        return &self.entries[tail_index];
    }

    pub fn advanceTail(self: *SQManage, num: usize) !void {
        // Ensure the tail is within bounds
        if ((self.count + num) >= self.depth) {
            return error.QueueFull;
        }
        // Adjust the tail pointer with wrap-around
        self.tail = (self.tail + num) % self.depth;
        self.count += num;
    }

    pub fn pushTail(self: *SQManage, entry: *const SQEntry) !void {
        if (self.isFull()) {
            return error.QueueFull;
        }
        // Get the tail pointer and copy the entry
        const tail_ptr = try self.tailPtr(0);
        tail_ptr.* = entry.*;
        // Arrange the tail pointer
        try self.advanceTail(1);
    }

    pub fn updateDoorbell(self: *SQManage, sq_doorbell: *u64) !usize {
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

pub const CQManage = struct {
    /// head pointer
    head: usize = 0,
    /// number of entries
    count: usize = 0,
    /// Maximum depth of the queue
    depth: usize = 0,
    /// body of the queue
    entries: []CQEntry = undefined,
    /// Doorbell pointer
    doorbell: *volatile u32 = undefined,

    pub fn create(
        d: usize,
        buf: []align(page_size_min) u8,
        doorbell: *volatile u32,
    ) !CQManage {
        // check if the buffer size is sufficient
        if (buf.len < @sizeOf(CQEntry) * d) {
            return error.BufferTooSmall;
        }
        // create the queue structure
        return CQManage{
            .head = 0,
            .count = 0,
            .depth = d,
            .entries = @ptrCast(buf),
            .doorbell = doorbell,
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

/// Admin Opcodes
pub const AdminOpcode = enum(u8) {
    /// Identify Command
    identify = 0x06,
};

pub const ControllerNamespace = enum(u8) {
    namespace = 0x00,
    controller = 0x01,
    activeNameSpaceIdList = 0x02,
    namespaceIdentificationDescriptor = 0x03,
    nvmSetList = 0x04,
    ioCmdSetListSpecificIdentifyNamespace = 0x05,
    ioCmdSetSpecificIdentifyController = 0x06,
    // TODO: Other Figure 310: Identify - CNS Values
};
/// Command Dword 10 for Identify Command
pub const Cdw10Identify = packed struct {
    /// Controller or Namespace Structure
    cns: ControllerNamespace,
    /// reserved
    _rsvd: u8 = 0,
    /// Controller Identifier
    cntid: u16 = 0,
};

/// NVMe Submission Queue Entry structure
/// TODO: union support for Vendor Specific, ...
pub const SQEntry = packed struct {
    cdw0: SQDword0, // Submission Queue Dword 0
    nsid: u32 = 0xffffffff, // Namespace Identifier
    cdw2: u32 = 0x0, // Command Dword 2
    cdw3: u32 = 0x0, // Command Dword 3
    mptr: u32 = 0x0, // Metadata Pointer
    dptr: SQDataPointer, // Data Pointer
    cdw10: Cdw10Identify, // Command Dword 10
    cdw11: u32 = 0x0, // Command Dword 11
    cdw12: u32 = 0x0, // Command Dword 12
    cdw13: u32 = 0x0, // Command Dword 13
    cdw14: u32 = 0x0, // Command Dword 14
    cdw15: u32 = 0x0, // Command Dword 15
};

pub const FusedOperation = enum(u2) {
    /// No Fused Operation
    none = 0,
    /// First Command of Fused Operation
    firstCommandOfFused = 1,
    /// Second Command of Fused Operation
    secondCommandOfFused = 2,
    _reserved = 3,
};

/// Submission Queue Data Pointer Type
pub const SQDataPointerType = enum(u2) {
    /// PRP Entry
    prp = 0,
    /// SGL Entry
    sglUsedMptrAddr = 1,
    /// SGL Entry
    sglUsedMptrSqlSeg = 2,
    /// reserved
    _reserved = 3,
};
/// Submission Queue Dword 0 structure
pub const SQDword0 = packed struct {
    opc: AdminOpcode, // [7:0]  Opcode
    fuse: FusedOperation = FusedOperation.none, // [9:8]  Fused Operation
    _rsvd0: u4 = 0, // [13:10] Reserved
    psdt: SQDataPointerType = SQDataPointerType.prp, // [15:14] PRP or SGL Data Transfer
    cid: u16 = 0, // [31:16] Command Identifier
};
/// Completion Queue structure
/// TODO: SGL support
pub const SQDataPointer = packed struct {
    prp1: u64,
    prp2: u64,

    /// Create a SQDataPointer from an I/O Virtual Address (IOVA) and transfer size
    pub fn init(iova: u64, transfer_size: usize, dma_pool: ?*vfio.DmaBufPool) !struct { SQDataPointer, ?vfio.DmaBufPoolEntry } {
        const prp1 = iova;

        if (transfer_size <= page_size_min) {
            // Case.1: Single PRP Entry
            return .{ SQDataPointer{
                .prp1 = prp1,
                .prp2 = 0,
            }, null };
        } else {
            const offset = iova % page_size_min;
            const size_in_first_page = page_size_min - offset;
            const remain_size = transfer_size - size_in_first_page;

            if (remain_size <= page_size_min) {
                // Case.2: Two PRP Entries
                const prp2 = iova + size_in_first_page; // Next Page Head
                return .{ SQDataPointer{
                    .prp1 = prp1,
                    .prp2 = prp2,
                }, null };
            } else {
                // Case.3: Multiple PRP Entries (need PRP List)
                const pool = dma_pool orelse return error.NoDmaBufPool;
                // PRP1 = iova, PRP2 = PRP List Head IOVA, PRP List = {PRP2, PRP3, ...}
                const prp_entry_num = util.alignUp(remain_size, page_size_min) / page_size_min - 1;
                const prp_list_buf = try pool.alloc(remain_size);
                var prp_list_entries: []u64 = @ptrCast(prp_list_buf.buf);
                for (0..prp_entry_num) |i| {
                    const prp_offset = (1 + i) * page_size_min;
                    const prp_iova = prp_list_buf.iova + prp_offset;
                    prp_list_entries[i] = prp_iova;
                }
                const prp2 = prp_list_buf.iova;
                return .{ SQDataPointer{
                    .prp1 = prp1,
                    .prp2 = prp2,
                }, prp_list_buf };
            }
        }
    }
};

pub const CQEntry = packed struct {
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

test "SQManage Creation and Push" {
    const allocator = std.heap.page_allocator;
    const depth = 16;
    const buf_size = @sizeOf(SQEntry) * depth;
    const buf = try allocator.alloc(u8, buf_size);
    defer allocator.free(buf);

    const sq_manage = try SQManage.create(depth, buf[0..]);
    defer sq_manage.deinit();

    try expect(sq_manage.depth == depth);
    try expect(sq_manage.entries.len == depth);
    try expect(sq_manage.isEmpty());
    try expect(!sq_manage.isFull());

    // push entry
    const entry = SQEntry{
        .cdw0 = SQDword0{
            .opc = 0x01, // Example opcode
            .fuse = 0,
            ._rsvd0 = 0,
            .psdt = 0,
            .cid = 1, // Example command ID
        },
        .nsid = 1, // Example Namespace ID
        .cdw2 = 0,
        .cdw3 = 0,
        .mptr = 0,
        .dptr = SQDataPointer{
            .prp1 = 0,
            .prp2 = 0,
        },
        .cdw10 = 0,
        .cdw11 = 0,
        .cdw12 = 0,
        .cdw13 = 0,
        .cdw14 = 0,
        .cdw15 = 0,
    };
    try sq_manage.pushTail(&entry);
    try expect(!sq_manage.isEmpty());
    try expect(sq_manage.count == 1);

    // advance tail
    try sq_manage.advanceTail(3);
    try expect(sq_manage.tail == 4);
    try expect(sq_manage.count == 4);

    // sync to doorbell
    var sq_doorbell: u64 = 0;
    const pushed_count = try sq_manage.updateDoorbell(&sq_doorbell);
    try expect(pushed_count == 4);
    try expect(sq_manage.tail == 4);
    try expect(sq_manage.count == 0); // count should be reset after update
}

test "Submission Queue Size" {
    const size = @sizeOf(SQEntry);
    try expect(size == 64); // 16 * u32 = 64 bytes
}

test "Completion Queue Size" {
    const size = @sizeOf(CQEntry);
    try expect(size == 16);
}
