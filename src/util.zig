/// Prints a hexdump of the given data to the specified writer.
pub fn printHexdump(writer: anytype, data: []const u8, len: usize) !void {
    for (0..len) |i| {
        if (i % 16 == 0) {
            try writer.print("\n{x:08}: ", .{i});
        }
        try writer.print("{x:02} ", .{data[i]});
    }
    try writer.print("\n", .{});
}

/// Aligns the given value up to the nearest multiple of the specified alignment.
pub fn alignUp(value: usize, alignment: usize) usize {
    if (alignment == 0) return value;
    return (value + alignment - 1) / alignment * alignment;
}

/// Aligns the given value down to the nearest multiple of the specified alignment.
pub fn alignDown(value: usize, alignment: usize) usize {
    if (alignment == 0) return value;
    return value / alignment * alignment;
}

test "alignUp and alignDown" {
    const std = @import("std");
    const expect = std.testing.expect;

    // alignUp tests
    try expect(alignUp(0, 4096) == 0);
    try expect(alignUp(1, 4096) == 4096);
    try expect(alignUp(4095, 4096) == 4096);
    try expect(alignUp(4096, 4096) == 4096);
    try expect(alignUp(4097, 4096) == 8192);

    // alignDown tests
    try expect(alignDown(0, 4096) == 0);
    try expect(alignDown(1, 4096) == 0);
    try expect(alignDown(4095, 4096) == 0);
    try expect(alignDown(4096, 4096) == 4096);
    try expect(alignDown(4097, 4096) == 4096);

    // alignment == 0
    try expect(alignUp(1234, 0) == 1234);
    try expect(alignDown(1234, 0) == 1234);
}

test "alignUp edge cases" {
    const std = @import("std");
    const expect = std.testing.expect;

    // Test with different alignment values
    try expect(alignUp(15, 8) == 16);
    try expect(alignUp(16, 8) == 16);
    try expect(alignUp(17, 8) == 24);
    
    // Test with alignment of 1 (should return same value)
    try expect(alignUp(42, 1) == 42);
    try expect(alignDown(42, 1) == 42);
    
    // Test with larger values
    try expect(alignUp(1000000, 512) == 1000448); // 1000000 + 448
    try expect(alignDown(1000000, 512) == 999936); // 1953 * 512
}
