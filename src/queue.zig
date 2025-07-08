const std = @import("std");
const expect = std.testing.expect;
const page_size_min = std.heap.page_size_min;

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

    pub fn tailPtr(self: *const SQManage, offset: usize) *SQEntry {
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
        const tail_ptr = self.tailPtr(0);
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

    pub fn create(
        d: usize,
        buf: []align(page_size_min) u8,
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

/// NVMe Submission Queue Entry structure
/// TODO: union support for Vendor Specific, ...
pub const SQEntry = packed struct {
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
pub const SQDword0 = packed struct {
    opc: u8, // [7:0]  Opcode
    fuse: u2, // [9:8]  Fused Operation
    _rsvd0: u4, // [13:10] Reserved
    psdt: u2, // [15:14] PRP or SGL Data Transfer
    cid: u16, // [31:16] Command Identifier
};
/// Completion Queue structure
/// TODO: SGL support
pub const SQDataPointer = packed struct {
    prp1: u32, // [31:0] PRP Entry 1
    prp2: u32, // [63:32] PRP Entry 2
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
test "Completion Queue Size" {
    const size = @sizeOf(CQEntry);
    try expect(size == 16);
}
