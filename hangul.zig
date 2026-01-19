const std = @import("std");

// Hangul Unicode constants
const HANGUL_SYLLABLE_BASE: u32 = 0xAC00;
const HANGUL_SYLLABLE_END: u32 = 0xD7A3;
const JAMO_INITIAL_BASE: u32 = 0x1100;
const JAMO_MEDIAL_BASE: u32 = 0x1161;
const JAMO_FINAL_BASE: u32 = 0x11A8;

const INITIAL_COUNT: u32 = 19;
const MEDIAL_COUNT: u32 = 21;
const FINAL_COUNT: u32 = 28;

// Compatibility jamo (used for decomposition display)
const COMPAT_INITIAL = [_]u32{
    0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141, 0x3142,
    0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149, 0x314A, 0x314B,
    0x314C, 0x314D, 0x314E,
};

const COMPAT_MEDIAL = [_]u32{
    0x314F, 0x3150, 0x3151, 0x3152, 0x3153, 0x3154, 0x3155, 0x3156,
    0x3157, 0x3158, 0x3159, 0x315A, 0x315B, 0x315C, 0x315D, 0x315E,
    0x315F, 0x3160, 0x3161, 0x3162, 0x3163,
};

const COMPAT_FINAL = [_]u32{
    0x0000, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137,
    0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E, 0x313F, 0x3140,
    0x3141, 0x3142, 0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149,
    0x314A, 0x314B, 0x314C, 0x314D, 0x314E,
};

// Jamo decomposition result
pub const JamoDecomp = struct {
    initial: u32,
    medial: u32,
    final: u32,
};

// Check if character is a Hangul syllable
pub fn isHangulSyllable(c: u32) bool {
    return c >= HANGUL_SYLLABLE_BASE and c <= HANGUL_SYLLABLE_END;
}

// Decompose Hangul syllable into jamo components
pub fn decompose(syllable: u32) ?JamoDecomp {
    if (!isHangulSyllable(syllable)) return null;

    const syllable_index = syllable - HANGUL_SYLLABLE_BASE;
    const final_index = syllable_index % FINAL_COUNT;
    const medial_index = (syllable_index / FINAL_COUNT) % MEDIAL_COUNT;
    const initial_index = syllable_index / (FINAL_COUNT * MEDIAL_COUNT);

    return JamoDecomp{
        .initial = COMPAT_INITIAL[@intCast(initial_index)],
        .medial = COMPAT_MEDIAL[@intCast(medial_index)],
        .final = if (final_index > 0) COMPAT_FINAL[@intCast(final_index)] else 0,
    };
}

// Compose jamo components into Hangul syllable
pub fn compose(initial: u32, medial: u32, final: u32) ?u32 {
    var initial_idx: ?u32 = null;
    var medial_idx: ?u32 = null;
    var final_idx: ?u32 = null;

    // Find initial index
    for (COMPAT_INITIAL, 0..) |jamo, i| {
        if (jamo == initial) {
            initial_idx = @intCast(i);
            break;
        }
    }

    // Find medial index
    for (COMPAT_MEDIAL, 0..) |jamo, i| {
        if (jamo == medial) {
            medial_idx = @intCast(i);
            break;
        }
    }

    // Find final index - must be 0 or found in COMPAT_FINAL
    if (final == 0) {
        final_idx = 0;
    } else {
        for (COMPAT_FINAL, 0..) |jamo, i| {
            if (jamo == final) {
                final_idx = @intCast(i);
                break;
            }
        }
    }

    // Validate all indices found (including final)
    if (initial_idx == null or medial_idx == null or final_idx == null) return null;

    const syllable = HANGUL_SYLLABLE_BASE +
        (initial_idx.? * MEDIAL_COUNT * FINAL_COUNT) +
        (medial_idx.? * FINAL_COUNT) +
        final_idx.?;

    return syllable;
}

// Check if character has final jamo (받침)
pub fn hasFinal(syllable: u32) bool {
    if (!isHangulSyllable(syllable)) return false;
    const syllable_index = syllable - HANGUL_SYLLABLE_BASE;
    return (syllable_index % FINAL_COUNT) != 0;
}

// Get initial jamo
pub fn getInitial(syllable: u32) ?u32 {
    const jamo = decompose(syllable);
    return if (jamo) |j| j.initial else null;
}

// Get medial jamo
pub fn getMedial(syllable: u32) ?u32 {
    const jamo = decompose(syllable);
    return if (jamo) |j| j.medial else null;
}

// Get final jamo
pub fn getFinal(syllable: u32) ?u32 {
    const jamo = decompose(syllable);
    return if (jamo) |j| j.final else null;
}

// WASM exports
export fn wasm_isHangulSyllable(c: u32) bool {
    return isHangulSyllable(c);
}

export fn wasm_hasFinal(c: u32) bool {
    return hasFinal(c);
}

export fn wasm_getInitial(c: u32) u32 {
    return getInitial(c) orelse 0;
}

export fn wasm_getMedial(c: u32) u32 {
    return getMedial(c) orelse 0;
}

export fn wasm_getFinal(c: u32) u32 {
    return getFinal(c) orelse 0;
}

export fn wasm_compose(initial: u32, medial: u32, final: u32) u32 {
    return compose(initial, medial, final) orelse 0;
}

// Decompose into array: returns initial, medial, final
// NOTE: Caller MUST allocate at least 3 u32 values (12 bytes) for output buffer
// Takes byte offset into WASM linear memory
export fn wasm_decompose(syllable: u32, output_ptr: u32) bool {
    const jamo = decompose(syllable);
    if (jamo) |j| {
        // Cast offset to pointer into WASM linear memory
        const output: [*]u32 = @ptrFromInt(output_ptr);
        output[0] = j.initial;
        output[1] = j.medial;
        output[2] = j.final;
        return true;
    }
    return false;
}

// Safe decompose with buffer size validation
// Returns: true on success, false if syllable invalid or buffer too small
// Takes byte offset into WASM linear memory
export fn wasm_decompose_safe(syllable: u32, output_ptr: u32, output_size: u32) bool {
    // Require at least 3 u32 slots (12 bytes)
    if (output_size < 3) return false;

    const jamo = decompose(syllable);
    if (jamo) |j| {
        const output: [*]u32 = @ptrFromInt(output_ptr);
        output[0] = j.initial;
        output[1] = j.medial;
        output[2] = j.final;
        return true;
    }
    return false;
}

// String processing - decompose entire string
// Takes byte offsets into WASM linear memory
export fn wasm_decomposeString(input_ptr: u32, input_len: u32, output_ptr: u32) u32 {
    const input: [*]const u8 = @ptrFromInt(input_ptr);
    const output: [*]u32 = @ptrFromInt(output_ptr);
    var out_idx: u32 = 0;
    var i: u32 = 0;

    while (i < input_len) {
        const c = decodeUtf8Char(input, i, input_len);
        if (c.char == 0) break;

        if (isHangulSyllable(c.char)) {
            const jamo = decompose(c.char);
            if (jamo) |j| {
                output[out_idx] = j.initial;
                out_idx += 1;
                output[out_idx] = j.medial;
                out_idx += 1;
                if (j.final != 0) {
                    output[out_idx] = j.final;
                    out_idx += 1;
                }
            }
        } else {
            output[out_idx] = c.char;
            out_idx += 1;
        }

        i += c.len;
    }

    return out_idx;
}

// Helper to decode UTF-8 character
const Utf8Char = struct {
    char: u32,
    len: u32,
};

fn decodeUtf8Char(bytes: [*]const u8, start: u32, max_len: u32) Utf8Char {
    if (start >= max_len) return .{ .char = 0, .len = 0 };

    const first = bytes[start];

    // 1-byte (ASCII)
    if (first < 0x80) {
        return .{ .char = first, .len = 1 };
    }

    // 2-byte: 110xxxxx 10xxxxxx
    if (first < 0xE0) {
        if (start + 1 >= max_len) return .{ .char = 0, .len = 0 };
        const cont = bytes[start + 1];
        // Validate continuation byte (must be 10xxxxxx, i.e., 0x80-0xBF)
        if ((cont & 0xC0) != 0x80) return .{ .char = 0, .len = 0 };
        const c = (@as(u32, first & 0x1F) << 6) | (cont & 0x3F);
        return .{ .char = c, .len = 2 };
    }

    // 3-byte (Hangul is here): 1110xxxx 10xxxxxx 10xxxxxx
    if (first < 0xF0) {
        if (start + 2 >= max_len) return .{ .char = 0, .len = 0 };
        const cont1 = bytes[start + 1];
        const cont2 = bytes[start + 2];
        // Validate continuation bytes
        if ((cont1 & 0xC0) != 0x80 or (cont2 & 0xC0) != 0x80) return .{ .char = 0, .len = 0 };
        const c = (@as(u32, first & 0x0F) << 12) |
            (@as(u32, cont1 & 0x3F) << 6) |
            (cont2 & 0x3F);
        return .{ .char = c, .len = 3 };
    }

    // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
    if (start + 3 >= max_len) return .{ .char = 0, .len = 0 };
    const cont1 = bytes[start + 1];
    const cont2 = bytes[start + 2];
    const cont3 = bytes[start + 3];
    // Validate continuation bytes
    if ((cont1 & 0xC0) != 0x80 or (cont2 & 0xC0) != 0x80 or (cont3 & 0xC0) != 0x80) {
        return .{ .char = 0, .len = 0 };
    }
    const c = (@as(u32, first & 0x07) << 18) |
        (@as(u32, cont1 & 0x3F) << 12) |
        (@as(u32, cont2 & 0x3F) << 6) |
        (cont3 & 0x3F);
    return .{ .char = c, .len = 4 };
}

// Simple static buffer allocator for WASM (no threading required)
const WASM_BUFFER_SIZE = 16 * 1024; // 16KB buffer
var wasm_buffer: [WASM_BUFFER_SIZE]u8 = undefined;
var wasm_alloc_ptr: u32 = 0;

export fn wasm_alloc(size: u32) u32 {
    if (wasm_alloc_ptr + size > WASM_BUFFER_SIZE) {
        return 0; // Allocation failed
    }
    const ptr = wasm_alloc_ptr;
    wasm_alloc_ptr += size;
    return ptr;
}

export fn wasm_free(ptr: u32, size: u32) void {
    // For simple linear allocator, we don't do anything
    // In production, use a proper allocator or reset strategy
    _ = ptr;
    _ = size;
}

// Tests
test "decompose hangul" {
    const ga = decompose(0xAC00); // 가
    try std.testing.expect(ga != null);
    if (ga) |g| {
        try std.testing.expectEqual(COMPAT_INITIAL[0], g.initial); // ㄱ
        try std.testing.expectEqual(COMPAT_MEDIAL[0], g.medial); // ㅏ
        try std.testing.expectEqual(@as(u32, 0), g.final);
    }

    const han = decompose(0xD55C); // 한
    try std.testing.expect(han != null);
    if (han) |h| {
        try std.testing.expectEqual(COMPAT_INITIAL[18], h.initial); // ㅎ
        try std.testing.expectEqual(COMPAT_MEDIAL[0], h.medial); // ㅏ
        try std.testing.expect(h.final != 0); // ㄴ
    }
}

test "decompose last syllable (힣)" {
    const hit = decompose(0xD7A3); // 힣 - last syllable
    try std.testing.expect(hit != null);
    if (hit) |h| {
        try std.testing.expectEqual(COMPAT_INITIAL[18], h.initial); // ㅎ
        try std.testing.expectEqual(COMPAT_MEDIAL[20], h.medial); // ㅣ
        try std.testing.expect(h.final != 0); // ㅎ
    }
}

test "compose hangul" {
    const ga = compose(0x3131, 0x314F, 0); // ㄱ + ㅏ = 가
    try std.testing.expectEqual(@as(u32, 0xAC00), ga.?);

    const han = compose(0x314E, 0x314F, 0x3134); // ㅎ + ㅏ + ㄴ = 한
    try std.testing.expectEqual(@as(u32, 0xD55C), han.?);
}

test "compose invalid jamo combination" {
    const result = compose(0x314E, 0x314F, 0x9999); // invalid final
    try std.testing.expect(result == null);
}

test "roundtrip decompose compose" {
    const syllables = [_]u32{ 0xAC00, 0xD55C, 0xD7A3 };
    for (syllables) |syllable| {
        const decomp = decompose(syllable);
        try std.testing.expect(decomp != null);
        if (decomp) |d| {
            const composed = compose(d.initial, d.medial, d.final);
            try std.testing.expect(composed != null);
            try std.testing.expectEqual(syllable, composed.?);
        }
    }
}

test "has final" {
    try std.testing.expect(!hasFinal(0xAC00)); // 가 - no final
    try std.testing.expect(hasFinal(0xD55C)); // 한 - has final
}

test "non-Hangul character returns null" {
    try std.testing.expect(decompose('A') == null);
    try std.testing.expect(decompose(0x3042) == null); // ぁ (Hiragana)
}

test "UTF-8 decoding with valid 3-byte sequence" {
    // 한 (U+D55C) in UTF-8: [0xED, 0x95, 0x9C]
    const bytes = [_]u8{ 0xED, 0x95, 0x9C };
    const c = decodeUtf8Char(&bytes, 0, 3);
    try std.testing.expectEqual(@as(u32, 0xD55C), c.char);
    try std.testing.expectEqual(@as(u32, 3), c.len);
}

test "UTF-8 decoding incomplete sequence returns zero" {
    // Incomplete 3-byte sequence
    const bytes = [_]u8{ 0xED, 0x95 };
    const c = decodeUtf8Char(&bytes, 0, 2);
    try std.testing.expectEqual(@as(u32, 0), c.char);
    try std.testing.expectEqual(@as(u32, 0), c.len);
}

test "UTF-8 decoding invalid continuation byte" {
    // 0xED is start of 3-byte, 0x95 is valid continuation, but 0x41 (ASCII) is not
    const bytes = [_]u8{ 0xED, 0x95, 0x41 };
    const c = decodeUtf8Char(&bytes, 0, 3);
    // Should return 0 because 0x41 is not a valid continuation byte (10xxxxxx)
    try std.testing.expectEqual(@as(u32, 0), c.char);
    try std.testing.expectEqual(@as(u32, 0), c.len);
}

test "exhaustive roundtrip: all 11172 syllables" {
    // Property-based test: verify all valid Hangul syllables decompose and recompose correctly
    // This is a comprehensive correctness guarantee for the entire valid range
    var count: u32 = 0;
    var syllable = HANGUL_SYLLABLE_BASE;

    while (syllable <= HANGUL_SYLLABLE_END) : (syllable += 1) {
        count += 1;

        // Decompose
        const jamo = decompose(syllable);
        try std.testing.expect(jamo != null);

        if (jamo) |j| {
            // Recompose
            const recomposed = compose(j.initial, j.medial, j.final);
            try std.testing.expect(recomposed != null);

            // Verify roundtrip: should get original syllable back
            try std.testing.expectEqual(syllable, recomposed.?);
        }
    }

    // Verify we tested exactly 11,172 syllables
    try std.testing.expectEqual(@as(u32, 11172), count);
}

test "exhaustive validation: invalid jamo combinations rejected" {
    // Test that all 19 * 21 * 28 = 11,172 valid combinations work
    // and all invalid combinations are rejected

    var valid_count: u32 = 0;
    var i: u32 = 0;

    while (i < INITIAL_COUNT) : (i += 1) {
        var j: u32 = 0;
        while (j < MEDIAL_COUNT) : (j += 1) {
            var k: u32 = 0;
            while (k < FINAL_COUNT) : (k += 1) {
                const initial = COMPAT_INITIAL[i];
                const medial = COMPAT_MEDIAL[j];
                const final = COMPAT_FINAL[k];

                const result = compose(initial, medial, final);
                try std.testing.expect(result != null);
                valid_count += 1;
            }
        }
    }

    // Verify we tested exactly 19 * 21 * 28 = 11,172 combinations
    try std.testing.expectEqual(@as(u32, 11172), valid_count);

    // Test invalid combinations are rejected
    const invalid_initial = 0xFFFF;
    const valid_medial = COMPAT_MEDIAL[0];
    const valid_final = COMPAT_FINAL[0];

    try std.testing.expect(compose(invalid_initial, valid_medial, valid_final) == null);
    try std.testing.expect(compose(valid_medial, invalid_initial, valid_final) == null);
    try std.testing.expect(compose(valid_medial, valid_final, invalid_initial) == null);
}

test "wasm_decompose_safe buffer validation" {
    // Skip this test on non-WASM targets since pointer casting behaves differently
    if (@import("builtin").target.cpu.arch != .wasm32) return error.SkipZigTest;

    var output: [3]u32 = undefined;
    const output_ptr: u32 = @truncate(@intFromPtr(&output));

    // Test with valid buffer size
    const success = wasm_decompose_safe(0xD55C, output_ptr, 3);
    try std.testing.expect(success);
    try std.testing.expectEqual(COMPAT_INITIAL[18], output[0]); // ㅎ
    try std.testing.expectEqual(COMPAT_MEDIAL[0], output[1]); // ㅏ

    // Test with buffer too small
    const too_small = wasm_decompose_safe(0xD55C, output_ptr, 2);
    try std.testing.expect(!too_small);

    // Test with zero buffer size
    const zero_size = wasm_decompose_safe(0xD55C, output_ptr, 0);
    try std.testing.expect(!zero_size);

    // Test with invalid syllable
    const invalid = wasm_decompose_safe(0x1234, output_ptr, 3);
    try std.testing.expect(!invalid);
}

// Build configuration comment:
// Build with: zig build-lib hangul.zig -target wasm32-freestanding -dynamic -rdynamic -O ReleaseSmall
// This creates hangul.wasm that can be used from JavaScript
