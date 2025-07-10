const std = @import("std");

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

pub fn findNConsecutiveOnes(
    bitset: std.DynamicBitSet,
    n: usize, // 探したい連続ビット数
) ?u32 {
    var cons_free: u32 = 0;
    var cons_start: u32 = undefined;
    var bit_idx: u32 = 0;
    // search for n consecutive free(1) in the bitset
    while (bit_idx < bitset.capacity()) : (bit_idx += 1) {
        if (bitset.isSet(bit_idx)) {
            if (cons_free == 0) {
                // 連続が始まった位置を記録
                cons_start = bit_idx;
            }
            cons_free += 1;
        } else {
            cons_free = 0;
        }

        // カウンターがnに達したかチェック
        if (cons_free >= n) {
            // 連続がnに達したので開始位置を返す
            return cons_start;
        }
    }
    return null;
}

test "alignUp and alignDown" {
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

test "findNConsecutiveOnes" {
    const expect = std.testing.expect;

    var bitset = std.StaticBitSet(32).initFull();
    try expect(findNConsecutiveOnes(32, bitset, 1) == 0);
    try expect(findNConsecutiveOnes(32, bitset, 2) == 0);
    try expect(findNConsecutiveOnes(32, bitset, 3) == 0);
    try expect(findNConsecutiveOnes(32, bitset, 4) == 0);

    // Clear some bits
    bitset.setValue(0, false);
    bitset.setValue(1, false);
    try expect(findNConsecutiveOnes(32, bitset, 1) == 2);
    try expect(findNConsecutiveOnes(32, bitset, 2) == 2);
    try expect(findNConsecutiveOnes(32, bitset, 3) == null);
}
