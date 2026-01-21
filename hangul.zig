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

// Index mapping tables for ohi.js compatibility
// ohi.js uses custom indices (1-30 for consonants, 31-51 for vowels)
// These need conversion to array indices for COMPAT_INITIAL/MEDIAL/FINAL

/// Convert ohi.js initial consonant index to COMPAT_INITIAL array index
/// Based on ohi.js line 65: i - (i < 3 ? 1 : i < 5 ? 2 : i < 10 ? 4 : i < 20 ? 11 : 12)
fn ohiIndexToInitialIdx(i: i8) u8 {
    if (i <= 0) return 0;
    const val: u8 = @intCast(i);
    if (val < 3) return val - 1;
    if (val < 5) return val - 2;
    if (val < 10) return val - 4;
    if (val < 20) return val - 11;
    return val - 12;
}

/// Convert ohi.js medial vowel index to COMPAT_MEDIAL array index
/// Based on ohi.js line 66: j - 31
fn ohiIndexToMedialIdx(j: i8) u8 {
    if (j < 31) return 0;
    return @intCast(j - 31);
}

/// Convert ohi.js final consonant index to COMPAT_FINAL array index
/// Based on ohi.js line 67-68: k - (k < 8 ? 0 : k < 19 ? 1 : k < 25 ? 2 : 3)
fn ohiIndexToFinalIdx(k: i8) u8 {
    if (k <= 0) return 0;
    const val: u8 = @intCast(k);
    if (val < 8) return val - 0;
    if (val < 19) return val - 1;
    if (val < 25) return val - 2;
    return val - 3;
}

/// Convert ohi.js index to single jamo Unicode code point
/// Based on ohi.js line 69: 0x3130 + (i || j || k)
fn ohiIndexToSingleJamo(idx: i8) u32 {
    if (idx <= 0) return 0;
    return 0x3130 + @as(u32, @intCast(idx));
}

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

// Jamo classification constants
// Compatibility Jamo range: U+3131 to U+3163
const COMPAT_JAMO_START: u32 = 0x3131;
const COMPAT_JAMO_END: u32 = 0x3163;
const COMPAT_VOWEL_START: u32 = 0x314F; // ㅏ

// Double consonants (initial): ㄲ, ㄸ, ㅃ, ㅆ, ㅉ
const DOUBLE_CONSONANTS = [_]u32{ 0x3132, 0x3138, 0x3143, 0x3146, 0x3149 };

// Double vowels: ㅘ, ㅙ, ㅚ, ㅝ, ㅞ, ㅟ, ㅢ
const DOUBLE_VOWELS = [_]u32{ 0x3158, 0x3159, 0x315A, 0x315D, 0x315E, 0x315F, 0x3162 };

/// Check if codepoint is a compatibility jamo (consonant or vowel)
pub fn isJamo(c: u32) bool {
    return c >= COMPAT_JAMO_START and c <= COMPAT_JAMO_END;
}

/// Check if codepoint is a consonant (초성/종성)
pub fn isConsonant(c: u32) bool {
    return c >= COMPAT_JAMO_START and c < COMPAT_VOWEL_START;
}

/// Check if codepoint is a vowel (중성)
pub fn isVowel(c: u32) bool {
    return c >= COMPAT_VOWEL_START and c <= COMPAT_JAMO_END;
}

/// Check if codepoint is a double consonant (ㄲ, ㄸ, ㅃ, ㅆ, ㅉ)
pub fn isDoubleConsonant(c: u32) bool {
    for (DOUBLE_CONSONANTS) |dc| {
        if (c == dc) return true;
    }
    return false;
}

/// Check if codepoint is a double vowel (ㅘ, ㅙ, ㅚ, ㅝ, ㅞ, ㅟ, ㅢ)
pub fn isDoubleVowel(c: u32) bool {
    for (DOUBLE_VOWELS) |dv| {
        if (c == dv) return true;
    }
    return false;
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

// Jamo classification exports
export fn wasm_isJamo(c: u32) bool {
    return isJamo(c);
}

export fn wasm_isConsonant(c: u32) bool {
    return isConsonant(c);
}

export fn wasm_isVowel(c: u32) bool {
    return isVowel(c);
}

export fn wasm_isDoubleConsonant(c: u32) bool {
    return isDoubleConsonant(c);
}

export fn wasm_isDoubleVowel(c: u32) bool {
    return isDoubleVowel(c);
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
var wasm_buffer: [WASM_BUFFER_SIZE]u8 align(8) = undefined;
var wasm_alloc_ptr: u32 = 0;

export fn wasm_alloc(size: u32) u32 {
    // Align to 4 bytes for safe u32 access (required by JavaScript TypedArrays)
    const alignment: u32 = 4;
    const mask: u32 = alignment - 1;
    const inverted_mask: u32 = ~mask;
    const aligned_ptr = (wasm_alloc_ptr + mask) & inverted_mask;

    if (aligned_ptr + size > WASM_BUFFER_SIZE) {
        return 0; // Allocation failed
    }
    const ptr = @intFromPtr(&wasm_buffer[aligned_ptr]);
    wasm_alloc_ptr = aligned_ptr + size;
    return @intCast(ptr);
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

test "jamo classification: isJamo" {
    // Valid jamo
    try std.testing.expect(isJamo(0x3131)); // ㄱ (first)
    try std.testing.expect(isJamo(0x3163)); // ㅣ (last)
    try std.testing.expect(isJamo(0x314F)); // ㅏ (first vowel)
    try std.testing.expect(isJamo(0x3145)); // ㅅ

    // Not jamo
    try std.testing.expect(!isJamo(0x3130)); // before range
    try std.testing.expect(!isJamo(0x3164)); // after range
    try std.testing.expect(!isJamo(0xAC00)); // 가 (syllable, not jamo)
    try std.testing.expect(!isJamo('A'));
}

test "jamo classification: isConsonant" {
    // Consonants (ㄱ to ㅎ): U+3131 to U+314E
    try std.testing.expect(isConsonant(0x3131)); // ㄱ
    try std.testing.expect(isConsonant(0x314E)); // ㅎ
    try std.testing.expect(isConsonant(0x3134)); // ㄴ
    try std.testing.expect(isConsonant(0x3139)); // ㄹ

    // Not consonants
    try std.testing.expect(!isConsonant(0x314F)); // ㅏ (vowel)
    try std.testing.expect(!isConsonant(0x3163)); // ㅣ (vowel)
    try std.testing.expect(!isConsonant('A'));
}

test "jamo classification: isVowel" {
    // Vowels (ㅏ to ㅣ): U+314F to U+3163
    try std.testing.expect(isVowel(0x314F)); // ㅏ
    try std.testing.expect(isVowel(0x3163)); // ㅣ
    try std.testing.expect(isVowel(0x3153)); // ㅓ
    try std.testing.expect(isVowel(0x3157)); // ㅗ

    // Not vowels
    try std.testing.expect(!isVowel(0x3131)); // ㄱ (consonant)
    try std.testing.expect(!isVowel(0x314E)); // ㅎ (consonant)
    try std.testing.expect(!isVowel('A'));
}

test "jamo classification: isDoubleConsonant" {
    // Double consonants: ㄲ, ㄸ, ㅃ, ㅆ, ㅉ
    try std.testing.expect(isDoubleConsonant(0x3132)); // ㄲ
    try std.testing.expect(isDoubleConsonant(0x3138)); // ㄸ
    try std.testing.expect(isDoubleConsonant(0x3143)); // ㅃ
    try std.testing.expect(isDoubleConsonant(0x3146)); // ㅆ
    try std.testing.expect(isDoubleConsonant(0x3149)); // ㅉ

    // Not double consonants
    try std.testing.expect(!isDoubleConsonant(0x3131)); // ㄱ
    try std.testing.expect(!isDoubleConsonant(0x3134)); // ㄴ
    try std.testing.expect(!isDoubleConsonant(0x314F)); // ㅏ (vowel)
}

test "jamo classification: isDoubleVowel" {
    // Double vowels: ㅘ, ㅙ, ㅚ, ㅝ, ㅞ, ㅟ, ㅢ
    try std.testing.expect(isDoubleVowel(0x3158)); // ㅘ
    try std.testing.expect(isDoubleVowel(0x3159)); // ㅙ
    try std.testing.expect(isDoubleVowel(0x315A)); // ㅚ
    try std.testing.expect(isDoubleVowel(0x315D)); // ㅝ
    try std.testing.expect(isDoubleVowel(0x315E)); // ㅞ
    try std.testing.expect(isDoubleVowel(0x315F)); // ㅟ
    try std.testing.expect(isDoubleVowel(0x3162)); // ㅢ

    // Not double vowels
    try std.testing.expect(!isDoubleVowel(0x314F)); // ㅏ
    try std.testing.expect(!isDoubleVowel(0x3153)); // ㅓ
    try std.testing.expect(!isDoubleVowel(0x3131)); // ㄱ (consonant)
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

test "wasm_decompose_safe buffer validation (wasm only)" {
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

test "decompose_safe logic validation (host)" {
    // Test the underlying decompose function that wasm_decompose_safe wraps
    // This validates the same logic without WASM-specific pointer handling

    // Test valid syllable 한 (U+D55C)
    const han = decompose(0xD55C);
    try std.testing.expect(han != null);
    if (han) |j| {
        try std.testing.expectEqual(COMPAT_INITIAL[18], j.initial); // ㅎ
        try std.testing.expectEqual(COMPAT_MEDIAL[0], j.medial); // ㅏ
        try std.testing.expectEqual(COMPAT_FINAL[4], j.final); // ㄴ
    }

    // Test valid syllable 가 (U+AC00) - no final
    const ga = decompose(0xAC00);
    try std.testing.expect(ga != null);
    if (ga) |j| {
        try std.testing.expectEqual(COMPAT_INITIAL[0], j.initial); // ㄱ
        try std.testing.expectEqual(COMPAT_MEDIAL[0], j.medial); // ㅏ
        try std.testing.expectEqual(@as(u32, 0), j.final); // no final
    }

    // Test invalid character (not a Hangul syllable)
    const invalid = decompose(0x1234);
    try std.testing.expect(invalid == null);

    // Test character below Hangul range
    const below = decompose(0xABFF);
    try std.testing.expect(below == null);

    // Test character above Hangul range
    const above = decompose(0xD7A4);
    try std.testing.expect(above == null);
}

// ============================================================================
// IME Tests
// ============================================================================

test "ime state initialization" {
    const state = ImeState.init();
    try std.testing.expect(state.isEmpty());
    try std.testing.expectEqual(@as(u32, 0), state.toCodepoint());
}

test "ime state reset" {
    var state = ImeState.init();
    state.initial = 1;
    state.medial = 1;
    state.final = 1;
    try std.testing.expect(!state.isEmpty());

    state.reset();
    try std.testing.expect(state.isEmpty());
}

test "ime state single jamo" {
    var state = ImeState.init();
    state.initial = 1; // ㄱ (index 0 in COMPAT_INITIAL)
    try std.testing.expectEqual(@as(u32, 0x3131), state.toCodepoint()); // ㄱ

    state.reset();
    state.medial = 31; // ㅏ (index 31 in ohi.js = index 0 in COMPAT_MEDIAL)
    try std.testing.expectEqual(@as(u32, 0x314F), state.toCodepoint()); // ㅏ

    state.reset();
    state.final = 1; // ㄱ (index 1 in COMPAT_FINAL)
    try std.testing.expectEqual(@as(u32, 0x3131), state.toCodepoint()); // ㄱ
}

test "ime state compose syllable" {
    var state = ImeState.init();
    state.initial = 1; // ㄱ
    state.medial = 31; // ㅏ
    try std.testing.expectEqual(@as(u32, 0xAC00), state.toCodepoint()); // 가

    state.final = 4; // ㄴ (index 4 in COMPAT_FINAL)
    try std.testing.expectEqual(@as(u32, 0xAC04), state.toCodepoint()); // 간
}

test "keyboard layout 2-bulsik basic mapping" {
    // Test consonants
    try std.testing.expectEqual(@as(u8, 1), mapKeycode2Bulsik('r', false).?); // ㄱ
    try std.testing.expectEqual(@as(u8, 4), mapKeycode2Bulsik('s', false).?); // ㄴ
    try std.testing.expectEqual(@as(u8, 21), mapKeycode2Bulsik('t', false).?); // ㅅ

    // Test vowels
    try std.testing.expectEqual(@as(u8, 31), mapKeycode2Bulsik('k', false).?); // ㅏ
    try std.testing.expectEqual(@as(u8, 32), mapKeycode2Bulsik('o', false).?); // ㅐ
    try std.testing.expectEqual(@as(u8, 51), mapKeycode2Bulsik('l', false).?); // ㅣ
}

test "double jamo: initial consonants" {
    // ㄱ+ㄱ=ㄲ
    try std.testing.expectEqual(@as(u8, 2), detectDoubleJamo(.initial, 1, 1));
    // ㄷ+ㄷ=ㄸ
    try std.testing.expectEqual(@as(u8, 8), detectDoubleJamo(.initial, 7, 7));
    // ㅅ+ㅅ=ㅆ
    try std.testing.expectEqual(@as(u8, 19), detectDoubleJamo(.initial, 18, 18));

    // Cannot double
    try std.testing.expectEqual(@as(u8, 0), detectDoubleJamo(.initial, 1, 4)); // ㄱ+ㄴ
}

test "double jamo: medial vowels" {
    // ㅗ+ㅏ=ㅘ
    try std.testing.expectEqual(@as(u8, 40), detectDoubleJamo(.medial, 39, 31));
    // ㅜ+ㅓ=ㅝ
    try std.testing.expectEqual(@as(u8, 45), detectDoubleJamo(.medial, 44, 35));
    // ㅡ+ㅣ=ㅢ
    try std.testing.expectEqual(@as(u8, 50), detectDoubleJamo(.medial, 49, 51));

    // Cannot double
    try std.testing.expectEqual(@as(u8, 0), detectDoubleJamo(.medial, 31, 32)); // ㅏ+ㅐ
}

test "double jamo: final consonants" {
    // ㄱ+ㅅ=ㄳ
    try std.testing.expectEqual(@as(u8, 3), detectDoubleJamo(.final, 1, 19));
    // ㄴ+ㅈ=ㄵ
    try std.testing.expectEqual(@as(u8, 5), detectDoubleJamo(.final, 4, 22));
    // ㄴ+ㅎ=ㄶ
    try std.testing.expectEqual(@as(u8, 6), detectDoubleJamo(.final, 4, 27));
    // ㅂ+ㅅ=ㅄ
    try std.testing.expectEqual(@as(u8, 20), detectDoubleJamo(.final, 18, 19));
    // ㄹ+ㄱ=ㄺ (ohi index: ㄹ=9, ㄱ=1) → result ohi 10 → final[9]
    try std.testing.expectEqual(@as(u8, 10), detectDoubleJamo(.final, 9, 1));
    // ㄹ+ㅁ=ㄻ (ohi index: ㄹ=9, ㅁ=17) → result ohi 11 → final[10]
    try std.testing.expectEqual(@as(u8, 11), detectDoubleJamo(.final, 9, 17));

    // Cannot double
    try std.testing.expectEqual(@as(u8, 0), detectDoubleJamo(.final, 1, 4)); // ㄱ+ㄴ
}

test "2-bulsik: type single consonant" {
    var state = ImeState.init();

    // Type 'r' (ㄱ, index 1)
    const result = processConsonant2Bulsik(&state, 1);
    try std.testing.expectEqual(@as(@TypeOf(result.action), .replace), result.action);
    try std.testing.expectEqual(@as(u32, 0x3131), result.current_codepoint); // ㄱ
    try std.testing.expectEqual(@as(i8, 1), state.initial);
}

test "2-bulsik: type 가 (g-a)" {
    var state = ImeState.init();

    // Type ㄱ
    _ = processConsonant2Bulsik(&state, 1);

    // Type ㅏ
    const result = processVowel2Bulsik(&state, 31);
    try std.testing.expectEqual(@as(@TypeOf(result.action), .replace), result.action);
    try std.testing.expectEqual(@as(u32, 0xAC00), result.current_codepoint); // 가
}

test "2-bulsik: type 한 (han)" {
    var state = ImeState.init();

    // Type ㅎ + ㅏ + ㄴ -> 한 using correct ohi.js indices
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    const result = processConsonant2Bulsik(&state, 4); // ㄴ

    try std.testing.expectEqual(@as(u32, 0xD55C), result.current_codepoint); // 한
}

test "2-bulsik: double consonant ㄲ" {
    var state = ImeState.init();

    // Type ㄱ twice
    _ = processConsonant2Bulsik(&state, 1);
    const result = processConsonant2Bulsik(&state, 1);

    try std.testing.expectEqual(@as(@TypeOf(result.action), .replace), result.action);
    try std.testing.expectEqual(@as(u32, 0x3132), result.current_codepoint); // ㄲ
}

test "2-bulsik: double vowel ㅘ (ㅗ+ㅏ)" {
    var state = ImeState.init();

    // Type ㄱ + ㅗ + ㅏ -> 과
    _ = processConsonant2Bulsik(&state, 1); // ㄱ
    _ = processVowel2Bulsik(&state, 39); // ㅗ
    const result = processVowel2Bulsik(&state, 31); // ㅏ

    // ㅗ+ㅏ=ㅘ, so should get 과 (ㄱ + ㅘ)
    // 과 = U+ACFC (verified with Python unicodedata)
    try std.testing.expectEqual(@as(u32, 0xACFC), result.current_codepoint); // 과
}

test "2-bulsik: syllable split" {
    var state = ImeState.init();

    // Type 한 (ㅎ+ㅏ+ㄴ) using correct ohi.js indices
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ -> 한

    // Type ㅏ again -> should split into "하" + "ㄴㅏ"
    const result = processVowel2Bulsik(&state, 31); // ㅏ

    try std.testing.expectEqual(@as(@TypeOf(result.action), .emit_and_new), result.action);
    try std.testing.expectEqual(@as(u32, 0xD558), result.prev_codepoint); // 하
    // Current should be ㄴㅏ (나 without final)
    try std.testing.expect(result.current_codepoint != 0);
}

test "2-bulsik: emit on new consonant after complete syllable" {
    var state = ImeState.init();

    // Type 한 using correct ohi.js indices
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ -> 한

    // Type another consonant -> should emit 한, start new
    const result = processConsonant2Bulsik(&state, 1); // ㄱ

    try std.testing.expectEqual(@as(@TypeOf(result.action), .emit_and_new), result.action);
    try std.testing.expectEqual(@as(u32, 0xD55C), result.prev_codepoint); // 한
    try std.testing.expectEqual(@as(u32, 0x3131), result.current_codepoint); // ㄱ
}

test "backspace decomposition" {
    var state = ImeState.init();

    // Type 한 using correct ohi.js indices
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ

    // Backspace: 한 → 하
    const cp1 = processBackspace(&state).?;
    try std.testing.expectEqual(@as(u32, 0xD558), cp1); // 하

    // Backspace: 하 → ㅎ
    const cp2 = processBackspace(&state).?;
    try std.testing.expectEqual(@as(u32, 0x314E), cp2); // ㅎ

    // Backspace: ㅎ → empty
    const cp3 = processBackspace(&state);
    try std.testing.expect(cp3 == null);
    try std.testing.expect(state.isEmpty());
}

test "double final consonant splitting" {
    // When typing 닭 (ㄷ+ㅏ+ㄹ+ㄱ) then a vowel, the ㄹㄱ should split:
    // 닭 + ㅏ → 달가 (not 닭ㄱㅏ)
    // The ㄹ stays as final of first syllable, ㄱ becomes initial of new syllable
    var state = ImeState.init();

    // Type 닭: e(ㄷ=7) + k(ㅏ=31) + f(ㄹ=9) + r(ㄱ=1) - forms double final ㄺ
    _ = processConsonant2Bulsik(&state, 7); // ㄷ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 9); // ㄹ
    const r1 = processConsonant2Bulsik(&state, 1); // ㄱ - should form double final ㄺ
    try std.testing.expectEqual(.replace, r1.action);
    try std.testing.expectEqual(@as(u32, 0xB2ED), r1.current_codepoint); // 닭 (U+B2ED)

    // Now type a vowel - should split the double final
    // 닭 → 달 + 가
    const r2 = processVowel2Bulsik(&state, 31); // ㅏ
    try std.testing.expectEqual(.emit_and_new, r2.action);
    try std.testing.expectEqual(@as(u32, 0xB2EC), r2.prev_codepoint); // 달 (U+B2EC) - final ㄹ only
    try std.testing.expectEqual(@as(u32, 0xAC00), r2.current_codepoint); // 가 (U+AC00) - ㄱ+ㅏ
}

test "ime commit finalizes composition" {
    // Test that commit returns the current syllable and resets state
    var state = ImeState.init();

    // Type 한: ㅎ(30) + ㅏ(31) + ㄴ(4)
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ

    try std.testing.expectEqual(@as(u32, 0xD55C), state.toCodepoint()); // 한
    try std.testing.expect(!state.isEmpty());

    // Simulate commit by getting codepoint and resetting
    const committed = state.toCodepoint();
    state.reset();

    try std.testing.expectEqual(@as(u32, 0xD55C), committed); // 한
    try std.testing.expect(state.isEmpty());
    try std.testing.expectEqual(@as(u32, 0), state.toCodepoint());
}

test "ime commit on empty state returns zero" {
    var state = ImeState.init();
    try std.testing.expect(state.isEmpty());

    const committed = state.toCodepoint();
    state.reset();

    try std.testing.expectEqual(@as(u32, 0), committed);
    try std.testing.expect(state.isEmpty());
}

test "ime commit on partial syllable returns jamo" {
    var state = ImeState.init();

    // Type just ㅎ (initial only)
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    try std.testing.expectEqual(@as(u32, 0x314E), state.toCodepoint()); // ㅎ

    const committed = state.toCodepoint();
    state.reset();

    try std.testing.expectEqual(@as(u32, 0x314E), committed); // ㅎ (single jamo)
    try std.testing.expect(state.isEmpty());
}

test "typing 입력할 then backspace should decompose 할" {
    // This test simulates the exact user scenario:
    // Type "입력할" (dlq + fur + gkf in 2-bulsik layout)
    // Then press backspace - should decompose 할 → 하
    var state = ImeState.init();

    // Type 입: d(ㅇ=23) + l(ㅣ=51) + q(ㅂ=18)
    const r1 = processConsonant2Bulsik(&state, 23); // ㅇ
    try std.testing.expectEqual(.replace, r1.action);

    const r2 = processVowel2Bulsik(&state, 51); // ㅣ
    try std.testing.expectEqual(.replace, r2.action);
    try std.testing.expectEqual(@as(u32, 0xC774), r2.current_codepoint); // 이

    const r3 = processConsonant2Bulsik(&state, 18); // ㅂ
    try std.testing.expectEqual(.replace, r3.action);
    try std.testing.expectEqual(@as(u32, 0xC785), r3.current_codepoint); // 입

    // Type 력: f(ㄹ=9) + u(ㅕ=37) + r(ㄱ=1)
    const r4 = processConsonant2Bulsik(&state, 9); // ㄹ - should emit 입 and start new
    try std.testing.expectEqual(.emit_and_new, r4.action);
    try std.testing.expectEqual(@as(u32, 0xC785), r4.prev_codepoint); // 입
    try std.testing.expectEqual(@as(u32, 0x3139), r4.current_codepoint); // ㄹ (single jamo)

    const r5 = processVowel2Bulsik(&state, 37); // ㅕ
    try std.testing.expectEqual(.replace, r5.action);
    try std.testing.expectEqual(@as(u32, 0xB824), r5.current_codepoint); // 려

    const r6 = processConsonant2Bulsik(&state, 1); // ㄱ
    try std.testing.expectEqual(.replace, r6.action);
    try std.testing.expectEqual(@as(u32, 0xB825), r6.current_codepoint); // 력

    // Type 할: g(ㅎ=30) + k(ㅏ=31) + f(ㄹ=9)
    const r7 = processConsonant2Bulsik(&state, 30); // ㅎ - should emit 력 and start new
    try std.testing.expectEqual(.emit_and_new, r7.action);
    try std.testing.expectEqual(@as(u32, 0xB825), r7.prev_codepoint); // 력
    try std.testing.expectEqual(@as(u32, 0x314E), r7.current_codepoint); // ㅎ (single jamo)

    const r8 = processVowel2Bulsik(&state, 31); // ㅏ
    try std.testing.expectEqual(.replace, r8.action);
    try std.testing.expectEqual(@as(u32, 0xD558), r8.current_codepoint); // 하

    const r9 = processConsonant2Bulsik(&state, 9); // ㄹ
    try std.testing.expectEqual(.replace, r9.action);
    try std.testing.expectEqual(@as(u32, 0xD560), r9.current_codepoint); // 할

    // Now verify state before backspace
    try std.testing.expectEqual(@as(i8, 30), state.initial); // ㅎ
    try std.testing.expectEqual(@as(i8, 31), state.medial); // ㅏ
    try std.testing.expectEqual(@as(i8, 9), state.final); // ㄹ

    // Backspace: 할 → 하
    const bs1 = processBackspace(&state);
    try std.testing.expect(bs1 != null);
    try std.testing.expectEqual(@as(u32, 0xD558), bs1.?); // 하

    // Verify state after first backspace
    try std.testing.expectEqual(@as(i8, 30), state.initial); // ㅎ
    try std.testing.expectEqual(@as(i8, 31), state.medial); // ㅏ
    try std.testing.expectEqual(@as(i8, 0), state.final); // no final
}

// ============================================================================
// IME (Input Method Editor) Implementation
// Based on ohi.js by Ho-Seok Ee
// ============================================================================

/// IME composition state - tracks in-progress syllable assembly
/// Maps to ohi.js _q array: [initial, initial_flag, medial, medial_flag, final, final_flag]
pub const ImeState = struct {
    initial: i8, // 초성 index (0-19), -1 for special states
    initial_flag: u8, // 0 or 1 (composition state)
    medial: i8, // 중성 index (0-21), -1 for special states
    medial_flag: u8, // 0 or 1
    final: i8, // 종성 index (0-28, 0=no final), -1 for special states
    final_flag: u8, // 0 or 1

    pub fn init() ImeState {
        return .{
            .initial = 0,
            .initial_flag = 0,
            .medial = 0,
            .medial_flag = 0,
            .final = 0,
            .final_flag = 0,
        };
    }

    pub fn reset(self: *ImeState) void {
        self.* = init();
    }

    pub fn isEmpty(self: ImeState) bool {
        return self.initial <= 0 and self.medial <= 0 and self.final <= 0;
    }

    /// Convert state to complete syllable or single jamo
    pub fn toCodepoint(self: ImeState) u32 {
        // If have initial + medial, compose full syllable
        if (self.initial > 0 and self.medial > 0) {
            const cho_idx = ohiIndexToInitialIdx(self.initial);
            const jung_idx = ohiIndexToMedialIdx(self.medial);
            const jong_idx = ohiIndexToFinalIdx(self.final);

            const cho = COMPAT_INITIAL[cho_idx];
            const jung = COMPAT_MEDIAL[jung_idx];
            const jong = if (jong_idx > 0) COMPAT_FINAL[jong_idx] else 0;

            return compose(cho, jung, jong) orelse 0;
        }

        // Return single jamo using ohi.js formula: 0x3130 + index
        if (self.initial > 0) return ohiIndexToSingleJamo(self.initial);
        if (self.medial > 0) return ohiIndexToSingleJamo(self.medial);
        if (self.final > 0) return ohiIndexToSingleJamo(self.final);

        return 0;
    }
};

/// Result from keystroke processing
pub const KeyResult = struct {
    action: enum { no_change, replace, emit_and_new },
    prev_codepoint: u32, // Emit this first (if action=emit_and_new)
    current_codepoint: u32, // Then emit/replace with this
};

/// 2-Bulsik (Dubeolsik) keyboard layout mapping
/// Maps ASCII characters to jamo indices (1-based for compatibility with ohi.js logic)
/// Index < 31 = consonant (can be initial or final)
/// Index >= 31 = vowel (medial only)
const LAYOUT_2BULSIK = [_]u8{
    // Mapping from ohi.js lines 119-146
    // r    R    t    T    s    e    E    f    a    q    Q    t    d    w    W    c    z
    17, 1,  21, 2, 4, 7, 8, 9, 17, 18, 19, 21, 23, 24, 25, 26,
    // x    v    g
    27, 28, 29,
    30,
    // Shifted keys (uppercase)
    // Vowels: k=ㅏ, o=ㅐ, i=ㅑ, O=ㅒ, j=ㅓ, p=ㅔ, u=ㅕ, P=ㅖ, h=ㅗ, hk=ㅘ, ho=ㅙ, hl=ㅚ
    // y=ㅛ, n=ㅜ, nj=ㅝ, np=ㅞ, nl=ㅟ, b=ㅠ, m=ㅡ, ml=ㅢ, l=ㅣ
};

// Actual keyboard mapping following ohi.js (lines 119-146)
// This maps ASCII code points to jamo indices
fn mapKeycode2Bulsik(ascii: u8, shifted: bool) ?u8 {
    // Based on ohi.js Array at lines 119-146
    const lower_map = [26]u8{
        // a    b    c    d    e    f    g    h    i    j    k    l    m
        17, 48, 26, 23, 7, 9, 30, 39, 33, 35, 31, 51, 49,
        // n    o    p    q    r    s    t    u    v    w    x    y    z
        44, 32, 36, 18, 1, 4, 21, 37, 29, 24, 28, 43, 27,
    };

    const upper_map = [26]u8{
        // A    B    C    D    E    F    G    H    I    J    K    L    M
        17, 48, 26, 23, 8, 9, 30, 39, 33, 35, 31, 51, 49,
        // N    O    P    Q    R    S    T    U    V    W    X    Y    Z
        44, 34, 38, 18, 1, 6, 21, 37, 29, 24, 28, 43, 27,
    };

    if (ascii >= 'a' and ascii <= 'z') {
        const idx = ascii - 'a';
        return if (shifted) upper_map[idx] else lower_map[idx];
    }
    if (ascii >= 'A' and ascii <= 'Z') {
        const idx = ascii - 'A';
        return upper_map[idx];
    }

    return null;
}

/// Double jamo detection tables
/// Based on ohi.js doubleJamo() lines 33-51
const DoubleJamoType = enum { initial, medial, final };

// Double initial: ㄱ+ㄱ=ㄲ, ㄷ+ㄷ=ㄸ, ㅂ+ㅂ=ㅃ, ㅅ+ㅅ=ㅆ, ㅈ+ㅈ=ㅉ
const DOUBLE_INITIAL_SINGLES = [_]u8{ 1, 7, 18, 21, 24 }; // Indices in layout
const DOUBLE_INITIAL_RESULT = [_]u8{ 2, 8, 19, 22, 25 }; // Resulting double

// Double medial vowels - more complex (ohi.js lines 38-39)
// ㅗ(8)+ㅏ(1)=ㅘ(9), ㅗ+ㅐ(2)=ㅙ(10), ㅗ+ㅣ(20)=ㅚ(11)
// ㅜ(13)+ㅓ(5)=ㅝ(14), ㅜ+ㅔ(6)=ㅞ(15), ㅜ+ㅣ=ㅟ(16)
// ㅡ(18)+ㅣ=ㅢ(19)
const DoubleMedialMap = struct {
    base: u8,
    targets: []const u8,
    results: []const u8,
};

const DOUBLE_MEDIAL_MAPS = [_]DoubleMedialMap{
    .{ .base = 39, .targets = &[_]u8{ 31, 32, 51 }, .results = &[_]u8{ 40, 41, 42 } }, // ㅗ
    .{ .base = 44, .targets = &[_]u8{ 35, 36, 51 }, .results = &[_]u8{ 45, 46, 47 } }, // ㅜ
    .{ .base = 49, .targets = &[_]u8{51}, .results = &[_]u8{50} }, // ㅡ
};

// Double final consonants - ㄱ+ㅅ=ㄳ, ㄴ+ㅈ=ㄵ, ㄴ+ㅎ=ㄶ, etc. (ohi.js lines 40-46)
const DoubleFinalMap = struct {
    base: u8,
    targets: []const u8,
    results: []const u8,
};

const DOUBLE_FINAL_MAPS = [_]DoubleFinalMap{
    .{ .base = 1, .targets = &[_]u8{19}, .results = &[_]u8{3} }, // ㄱ+ㅅ=ㄳ (final[3])
    .{ .base = 4, .targets = &[_]u8{ 22, 27 }, .results = &[_]u8{ 5, 6 } }, // ㄴ+ㅈ=ㄵ, ㄴ+ㅎ=ㄶ
    .{ .base = 9, .targets = &[_]u8{ 1, 17, 18, 19, 25, 26, 27 }, .results = &[_]u8{ 10, 11, 12, 13, 14, 15, 16 } }, // ㄹ+ㄱ=ㄺ(10), ㄹ+ㅁ=ㄻ(11), ㄹ+ㅂ=ㄼ(12), ㄹ+ㅅ=ㄽ(13), ㄹ+ㅌ=ㄾ(14), ㄹ+ㅍ=ㄿ(15), ㄹ+ㅎ=ㅀ(16)
    .{ .base = 18, .targets = &[_]u8{19}, .results = &[_]u8{20} }, // ㅂ+ㅅ=ㅄ (final[18])
};

/// Split a double final consonant back into its two components
/// Returns (base, target) ohi indices, or (0, 0) if not a double final
fn splitDoubleFinal(double_final: u8) struct { base: u8, second: u8 } {
    for (DOUBLE_FINAL_MAPS) |map| {
        for (map.targets, 0..) |target, i| {
            if (double_final == map.results[i]) {
                return .{ .base = map.base, .second = target };
            }
        }
    }
    return .{ .base = 0, .second = 0 };
}

/// Detect if current + incoming jamo can form double jamo
/// Returns new compound index or 0 if cannot combine
fn detectDoubleJamo(jamo_type: DoubleJamoType, current: u8, incoming: u8) u8 {
    return switch (jamo_type) {
        .initial => blk: {
            for (DOUBLE_INITIAL_SINGLES, 0..) |single, i| {
                if (current == single and incoming == single) {
                    break :blk DOUBLE_INITIAL_RESULT[i];
                }
            }
            break :blk 0;
        },
        .medial => blk: {
            for (DOUBLE_MEDIAL_MAPS) |map| {
                if (current == map.base) {
                    for (map.targets, 0..) |target, i| {
                        if (incoming == target) {
                            break :blk map.results[i];
                        }
                    }
                }
            }
            break :blk 0;
        },
        .final => blk: {
            for (DOUBLE_FINAL_MAPS) |map| {
                if (current == map.base) {
                    for (map.targets, 0..) |target, i| {
                        if (incoming == target) {
                            break :blk map.results[i];
                        }
                    }
                }
            }
            break :blk 0;
        },
    };
}

/// Process consonant keystroke in 2-Bulsik mode
/// Based on ohi.js Hangul2() lines 152-176
fn processConsonant2Bulsik(state: *ImeState, jamo_index: i8) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };

    const jamo_u8: u8 = @intCast(jamo_index);
    var should_emit = false; // Track if we need to emit

    // Scenario 1: Try adding as double final consonant
    // Only try if final_flag == 0 (not already a double jamo)
    if (state.medial > 0 and state.final > 0 and state.final_flag == 0) {
        const double_idx = detectDoubleJamo(.final, @intCast(state.final), jamo_u8);
        if (double_idx != 0) {
            state.final = @intCast(double_idx);
            state.final_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
        // Cannot double - will need to emit current syllable
        should_emit = true;
    }

    // Scenario 2: Try double initial or start new syllable
    // ohi.js lines 156-162
    if (state.medial == 0 or
        should_emit or
        (state.initial > 0 and (state.final == 0 or state.final_flag == 0) and
            (state.final > 0 or canFollowAsInitial(jamo_u8))))
    {
        // Try double initial
        const double_idx = if (state.medial == 0 and state.final == 0 and state.initial > 0)
            detectDoubleJamo(.initial, @intCast(state.initial), jamo_u8)
        else
            0;

        if (double_idx != 0) {
            state.initial = @intCast(double_idx);
            state.initial_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
        } else {
            // Emit previous syllable, start new
            if (!state.isEmpty()) {
                result.action = .emit_and_new;
                result.prev_codepoint = state.toCodepoint();
            }
            state.reset();
            state.initial = jamo_index;
            state.initial_flag = 1;
            result.current_codepoint = state.toCodepoint();
        }
    }
    // Scenario 3: Add as initial (if empty) or final (if have medial)
    else {
        if (state.initial == 0) {
            state.initial = jamo_index;
            state.initial_flag = 1;
        } else if (state.final == 0) {
            state.final = jamo_index;
            state.final_flag = 0;
        }
        result.action = .replace;
        result.current_codepoint = state.toCodepoint();
    }

    return result;
}

/// Some consonants can follow initial without medial
/// ohi.js line 161: c == 8 || c == 19 || c == 25
fn canFollowAsInitial(jamo_index: u8) bool {
    return jamo_index == 8 or jamo_index == 19 or jamo_index == 25;
}

/// Process vowel keystroke in 2-Bulsik mode
/// Based on ohi.js Hangul2() lines 177-199
fn processVowel2Bulsik(state: *ImeState, jamo_index: i8) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };

    const jamo_u8: u8 = @intCast(jamo_index);

    // Scenario 1: Try adding as double medial
    // Only try if medial_flag == 0 (not already a double jamo)
    if (state.medial > 0 and state.final == 0 and state.medial_flag == 0) {
        const double_idx = detectDoubleJamo(.medial, @intCast(state.medial), jamo_u8);
        if (double_idx != 0) {
            state.medial = @intCast(double_idx);
            state.medial_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
        // Cannot double
        state.medial = -1;
    }

    // Scenario 2: Syllable splitting
    if (state.initial > 0 and state.medial > 0 and state.final > 0) {
        const temp_final: u8 = @intCast(state.final);
        var new_initial: i8 = undefined;

        // Check if this is a double final that needs splitting
        if (state.final_flag == 1) {
            // Double final: split it - first component stays, second becomes new initial
            const split = splitDoubleFinal(temp_final);
            if (split.base != 0) {
                state.final = @intCast(split.base);
                new_initial = @intCast(split.second);
            } else {
                state.final = 0;
                new_initial = @intCast(temp_final);
            }
        } else {
            // Single final: move it entirely to new syllable
            state.final = 0;
            new_initial = @intCast(temp_final);
        }
        state.final_flag = 0;

        result.action = .emit_and_new;
        result.prev_codepoint = state.toCodepoint();

        // Start new syllable with the appropriate initial
        state.reset();
        state.initial = new_initial;
        state.medial = jamo_index;
        state.initial_flag = 0;
        state.medial_flag = 0;
        result.current_codepoint = state.toCodepoint();
        return result;
    }

    // Scenario 3: Start new syllable or add to existing
    if ((state.initial == 0 or state.medial > 0) or state.medial < 0) {
        // Start new syllable with just vowel
        if (!state.isEmpty()) {
            result.action = .emit_and_new;
            result.prev_codepoint = state.toCodepoint();
        }
        state.reset();
        state.medial = jamo_index;
        result.current_codepoint = state.toCodepoint();
    } else {
        // Add medial to existing initial
        state.medial = jamo_index;
        state.medial_flag = 0;
        result.action = .replace;
        result.current_codepoint = state.toCodepoint();
    }

    return result;
}

/// Process backspace - decomposes syllable step by step
/// Based on ohi.js keydownHandler() lines 418-427
fn processBackspace(state: *ImeState) ?u32 {
    // Find rightmost non-zero component and remove it
    // Order: final → medial → initial (flags are cleared with their components)
    if (state.final > 0) {
        state.final = 0;
        state.final_flag = 0;
        return state.toCodepoint();
    }
    if (state.medial > 0) {
        state.medial = 0;
        state.medial_flag = 0;
        return state.toCodepoint();
    }
    if (state.initial > 0) {
        state.initial = 0;
        state.initial_flag = 0;
        return null; // State now empty - let browser handle deletion
    }

    return null; // Already empty
}

// ============================================================================
// WASM API Exports for IME
// ============================================================================

/// Create new IME instance
/// Returns handle (pointer to ImeState in WASM memory)
/// Returns 0 if allocation fails
export fn wasm_ime_create() u32 {
    const state_ptr = wasm_alloc(@sizeOf(ImeState));
    if (state_ptr == 0) return 0;

    const state: *ImeState = @ptrFromInt(state_ptr);
    state.* = ImeState.init();
    return state_ptr;
}

/// Destroy IME instance
/// @param handle: Pointer returned from wasm_ime_create
export fn wasm_ime_destroy(handle: u32) void {
    if (handle == 0) return;
    wasm_free(handle, @sizeOf(ImeState));
}

/// Reset IME composition state
/// @param handle: IME instance pointer
export fn wasm_ime_reset(handle: u32) void {
    if (handle == 0) return;
    const state: *ImeState = @ptrFromInt(handle);
    state.reset();
}

/// Process keystroke (2-Bulsik layout only for now)
/// @param handle: IME instance pointer
/// @param jamo_index: ohi.js jamo index (1-51)
/// @param result_ptr: Pointer to output buffer (12 bytes = 3 × u32)
/// @returns true if key was handled
///
/// Output buffer format (3 × u32):
/// [0] action: 0=no_change, 1=replace, 2=emit_and_new
/// [1] prev_codepoint: Previous character (if action=emit_and_new)
/// [2] current_codepoint: Current character
export fn wasm_ime_processKey(
    handle: u32,
    jamo_index: i8,
    result_ptr: u32,
) bool {
    if (handle == 0 or result_ptr == 0) return false;

    const state: *ImeState = @ptrFromInt(handle);
    const output: [*]u32 = @ptrFromInt(result_ptr);

    // Determine if consonant or vowel based on ohi.js index range
    const result = if (jamo_index < 31)
        processConsonant2Bulsik(state, jamo_index)
    else
        processVowel2Bulsik(state, jamo_index);

    // Write result to output buffer
    output[0] = @intFromEnum(result.action);
    output[1] = result.prev_codepoint;
    output[2] = result.current_codepoint;

    return true;
}

/// Process backspace
/// @param handle: IME instance pointer
/// @returns Updated codepoint (0 if state is now empty)
export fn wasm_ime_backspace(handle: u32) u32 {
    if (handle == 0) return 0;
    const state: *ImeState = @ptrFromInt(handle);
    return processBackspace(state) orelse 0;
}

/// Get current composition state (for debugging)
/// @param handle: IME instance pointer
/// @param output_ptr: Pointer to output buffer (6 bytes)
export fn wasm_ime_getState(handle: u32, output_ptr: u32) void {
    if (handle == 0 or output_ptr == 0) return;

    const state: *ImeState = @ptrFromInt(handle);
    const output: [*]u8 = @ptrFromInt(output_ptr);

    output[0] = @intCast(state.initial);
    output[1] = state.initial_flag;
    output[2] = @intCast(state.medial);
    output[3] = state.medial_flag;
    output[4] = @intCast(state.final);
    output[5] = state.final_flag;
}

/// Commit current composition
/// Finalizes the current syllable and resets the IME state
/// @param handle: IME instance pointer
/// @returns The codepoint of the finalized syllable (0 if empty)
export fn wasm_ime_commit(handle: u32) u32 {
    if (handle == 0) return 0;
    const state: *ImeState = @ptrFromInt(handle);

    // Get current codepoint before reset
    const codepoint = state.toCodepoint();

    // Reset state for next composition
    state.reset();

    return codepoint;
}

// Build configuration comment:
// Build with: zig build-lib hangul.zig -target wasm32-freestanding -dynamic -rdynamic -O ReleaseSmall
// This creates hangul.wasm that can be used from JavaScript
