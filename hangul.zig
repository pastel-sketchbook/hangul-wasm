const std = @import("std");
const ime = @import("ime.zig");

// Hangul Unicode constants
const HANGUL_SYLLABLE_BASE: u32 = 0xAC00;
const HANGUL_SYLLABLE_END: u32 = 0xD7A3;
const JAMO_INITIAL_BASE: u32 = 0x1100;
const JAMO_MEDIAL_BASE: u32 = 0x1161;
const JAMO_FINAL_BASE: u32 = 0x11A8;

const INITIAL_COUNT: u32 = 19;
const MEDIAL_COUNT: u32 = 21;
const FINAL_COUNT: u32 = 28;

// ohi.js index boundaries
// ohi.js uses 1-30 for consonants, 31-51 for vowels
pub const OHI_VOWEL_BASE: i8 = 31; // First vowel index in ohi.js system
pub const OHI_JAMO_OFFSET: u32 = 0x3130; // ohi.js uses 0x3130 + index for single jamo

// Compatibility jamo (used for decomposition display)
pub const COMPAT_INITIAL = [_]u32{
    0x3131, 0x3132, 0x3134, 0x3137, 0x3138, 0x3139, 0x3141, 0x3142,
    0x3143, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149, 0x314A, 0x314B,
    0x314C, 0x314D, 0x314E,
};

pub const COMPAT_MEDIAL = [_]u32{
    0x314F, 0x3150, 0x3151, 0x3152, 0x3153, 0x3154, 0x3155, 0x3156,
    0x3157, 0x3158, 0x3159, 0x315A, 0x315B, 0x315C, 0x315D, 0x315E,
    0x315F, 0x3160, 0x3161, 0x3162, 0x3163,
};

pub const COMPAT_FINAL = [_]u32{
    0x0000, 0x3131, 0x3132, 0x3133, 0x3134, 0x3135, 0x3136, 0x3137,
    0x3139, 0x313A, 0x313B, 0x313C, 0x313D, 0x313E, 0x313F, 0x3140,
    0x3141, 0x3142, 0x3144, 0x3145, 0x3146, 0x3147, 0x3148, 0x3149,
    0x314A, 0x314B, 0x314C, 0x314D, 0x314E,
};

// Reverse lookup tables for O(1) compose() - generated at comptime
// Maps Unicode codepoint to array index (0xFF = invalid)
const JAMO_LOOKUP_SIZE = 0x3164 - 0x3131 + 1; // U+3131 to U+3163 inclusive (51 entries)

const INITIAL_REVERSE = blk: {
    var table: [JAMO_LOOKUP_SIZE]u8 = [_]u8{0xFF} ** JAMO_LOOKUP_SIZE;
    for (COMPAT_INITIAL, 0..) |cp, i| {
        table[cp - 0x3131] = @intCast(i);
    }
    break :blk table;
};

const MEDIAL_REVERSE = blk: {
    var table: [JAMO_LOOKUP_SIZE]u8 = [_]u8{0xFF} ** JAMO_LOOKUP_SIZE;
    for (COMPAT_MEDIAL, 0..) |cp, i| {
        table[cp - 0x3131] = @intCast(i);
    }
    break :blk table;
};

const FINAL_REVERSE = blk: {
    var table: [JAMO_LOOKUP_SIZE]u8 = [_]u8{0xFF} ** JAMO_LOOKUP_SIZE;
    for (COMPAT_FINAL, 0..) |cp, i| {
        if (cp != 0) { // Skip the null entry
            table[cp - 0x3131] = @intCast(i);
        }
    }
    break :blk table;
};

// Index mapping tables for ohi.js compatibility
// ohi.js uses custom indices (1-30 for consonants, 31-51 for vowels)
// These need conversion to array indices for COMPAT_INITIAL/MEDIAL/FINAL

// Comptime lookup table for initial consonant index conversion
// Based on ohi.js line 65: i - (i < 3 ? 1 : i < 5 ? 2 : i < 10 ? 4 : i < 20 ? 11 : 12)
// Note: Not all indices 1-30 are valid ohi indices; invalid entries return 0
const OHI_INITIAL_TO_IDX = blk: {
    var table: [31]u8 = [_]u8{0} ** 31;
    for (1..31) |i| {
        // Use signed arithmetic to avoid overflow, then saturate to 0 if negative
        const val: i32 = @intCast(i);
        const result: i32 = if (val < 3) val - 1 else if (val < 5) val - 2 else if (val < 10) val - 4 else if (val < 20) val - 11 else val - 12;
        table[i] = if (result >= 0) @intCast(result) else 0;
    }
    break :blk table;
};

// Comptime lookup table for final consonant index conversion
// Based on ohi.js line 67-68: k - (k < 8 ? 0 : k < 19 ? 1 : k < 25 ? 2 : 3)
const OHI_FINAL_TO_IDX = blk: {
    var table: [31]u8 = [_]u8{0} ** 31;
    for (1..31) |k| {
        const val: i32 = @intCast(k);
        const result: i32 = if (val < 8) val else if (val < 19) val - 1 else if (val < 25) val - 2 else val - 3;
        table[k] = if (result >= 0) @intCast(result) else 0;
    }
    break :blk table;
};

/// Convert ohi.js initial consonant index to COMPAT_INITIAL array index
/// O(1) lookup using comptime-generated table
pub fn ohiIndexToInitialIdx(i: i8) u8 {
    if (i <= 0 or i > 30) return 0;
    return OHI_INITIAL_TO_IDX[@intCast(i)];
}

/// Convert ohi.js medial vowel index to COMPAT_MEDIAL array index
/// Based on ohi.js line 66: j - 31
pub fn ohiIndexToMedialIdx(j: i8) u8 {
    if (j < OHI_VOWEL_BASE) return 0;
    return @intCast(j - OHI_VOWEL_BASE);
}

/// Convert ohi.js final consonant index to COMPAT_FINAL array index
/// O(1) lookup using comptime-generated table
pub fn ohiIndexToFinalIdx(k: i8) u8 {
    if (k <= 0 or k > 30) return 0;
    return OHI_FINAL_TO_IDX[@intCast(k)];
}

/// Convert ohi.js index to single jamo Unicode code point
/// Based on ohi.js line 69: 0x3130 + (i || j || k)
pub fn ohiIndexToSingleJamo(idx: i8) u32 {
    if (idx <= 0) return 0;
    return OHI_JAMO_OFFSET + @as(u32, @intCast(idx));
}

/// Result of decomposing a Hangul syllable into jamo components.
/// All values are Unicode compatibility jamo code points (U+3131-U+3163).
pub const JamoDecomp = struct {
    /// Initial consonant (초성): U+3131-U+314E (ㄱ-ㅎ)
    initial: u32,
    /// Medial vowel (중성): U+314F-U+3163 (ㅏ-ㅣ)
    medial: u32,
    /// Final consonant (종성): U+3131-U+314E or 0 if none (받침)
    final: u32,
};

/// Check if a Unicode code point is a Hangul syllable (가-힣).
/// Valid range: U+AC00 to U+D7A3 (11,172 syllables).
///
/// Example:
/// ```zig
/// isHangulSyllable(0xD55C) // '한' → true
/// isHangulSyllable(0x0041) // 'A' → false
/// ```
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

/// Decompose a Hangul syllable into its constituent jamo components.
///
/// Takes a precomposed Hangul syllable (U+AC00–U+D7A3) and returns its
/// initial consonant (초성), medial vowel (중성), and final consonant (종성).
///
/// Returns `null` if the input is not a valid Hangul syllable.
///
/// Example:
/// ```zig
/// const jamo = decompose(0xD55C); // '한' (U+D55C)
/// // jamo.initial = 0x314E (ㅎ)
/// // jamo.medial  = 0x314F (ㅏ)
/// // jamo.final   = 0x3134 (ㄴ)
/// ```
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

/// Compose jamo components into a precomposed Hangul syllable.
///
/// Takes compatibility jamo code points for initial (초성), medial (중성),
/// and final (종성) consonants and returns the composed syllable.
/// Pass 0 for `final` if the syllable has no final consonant.
///
/// Returns `null` if any jamo is invalid or cannot form a valid syllable.
///
/// Example:
/// ```zig
/// const syllable = compose(0x314E, 0x314F, 0x3134); // ㅎ + ㅏ + ㄴ
/// // syllable = 0xD55C ('한')
///
/// const ga = compose(0x3131, 0x314F, 0); // ㄱ + ㅏ + (none)
/// // ga = 0xAC00 ('가')
/// ```
pub fn compose(initial: u32, medial: u32, final: u32) ?u32 {
    // O(1) lookup using comptime-generated reverse tables
    const base: u32 = 0x3131;

    // Bounds check for jamo range
    if (initial < base or initial >= base + JAMO_LOOKUP_SIZE) return null;
    if (medial < base or medial >= base + JAMO_LOOKUP_SIZE) return null;

    const initial_idx = INITIAL_REVERSE[initial - base];
    const medial_idx = MEDIAL_REVERSE[medial - base];

    if (initial_idx == 0xFF or medial_idx == 0xFF) return null;

    // Handle final: 0 means no final consonant
    var final_idx: u8 = 0;
    if (final != 0) {
        if (final < base or final >= base + JAMO_LOOKUP_SIZE) return null;
        final_idx = FINAL_REVERSE[final - base];
        if (final_idx == 0xFF) return null;
    }

    const syllable = HANGUL_SYLLABLE_BASE +
        (@as(u32, initial_idx) * MEDIAL_COUNT * FINAL_COUNT) +
        (@as(u32, medial_idx) * FINAL_COUNT) +
        @as(u32, final_idx);

    return syllable;
}

/// Check if a Hangul syllable has a final consonant (받침).
///
/// Returns `true` if the syllable has a final jamo, `false` otherwise.
/// Returns `false` for non-Hangul characters.
///
/// Example:
/// ```zig
/// hasFinal(0xD55C) // '한' → true (has ㄴ)
/// hasFinal(0xAC00) // '가' → false (no final)
/// ```
pub fn hasFinal(syllable: u32) bool {
    if (!isHangulSyllable(syllable)) return false;
    const syllable_index = syllable - HANGUL_SYLLABLE_BASE;
    return (syllable_index % FINAL_COUNT) != 0;
}

/// Get the initial consonant (초성) of a Hangul syllable.
///
/// Returns the compatibility jamo code point for the initial consonant,
/// or `null` if the input is not a valid Hangul syllable.
///
/// Example:
/// ```zig
/// getInitial(0xD55C) // '한' → 0x314E (ㅎ)
/// ```
pub fn getInitial(syllable: u32) ?u32 {
    const jamo = decompose(syllable);
    return if (jamo) |j| j.initial else null;
}

/// Get the medial vowel (중성) of a Hangul syllable.
///
/// Returns the compatibility jamo code point for the medial vowel,
/// or `null` if the input is not a valid Hangul syllable.
///
/// Example:
/// ```zig
/// getMedial(0xD55C) // '한' → 0x314F (ㅏ)
/// ```
pub fn getMedial(syllable: u32) ?u32 {
    const jamo = decompose(syllable);
    return if (jamo) |j| j.medial else null;
}

/// Get the final consonant (종성) of a Hangul syllable.
///
/// Returns the compatibility jamo code point for the final consonant,
/// or 0 if the syllable has no final, or `null` if not a valid syllable.
///
/// Example:
/// ```zig
/// getFinal(0xD55C) // '한' → 0x3134 (ㄴ)
/// getFinal(0xAC00) // '가' → 0 (no final)
/// ```
pub fn getFinal(syllable: u32) ?u32 {
    const jamo = decompose(syllable);
    return if (jamo) |j| j.final else null;
}

// ============================================================================
// WASM Exports - Core Functions
// ============================================================================

/// WASM export: Check if code point is a Hangul syllable.
/// Returns 1 (true) or 0 (false).
export fn wasm_isHangulSyllable(c: u32) bool {
    return isHangulSyllable(c);
}

/// WASM export: Check if syllable has a final consonant (받침).
/// Returns 1 (true) or 0 (false).
export fn wasm_hasFinal(c: u32) bool {
    return hasFinal(c);
}

/// WASM export: Get initial consonant (초성) of a syllable.
/// Returns the jamo code point, or 0 if invalid input.
export fn wasm_getInitial(c: u32) u32 {
    return getInitial(c) orelse 0;
}

/// WASM export: Get medial vowel (중성) of a syllable.
/// Returns the jamo code point, or 0 if invalid input.
export fn wasm_getMedial(c: u32) u32 {
    return getMedial(c) orelse 0;
}

/// WASM export: Get final consonant (종성) of a syllable.
/// Returns the jamo code point, 0 if no final, or 0 if invalid.
export fn wasm_getFinal(c: u32) u32 {
    return getFinal(c) orelse 0;
}

/// WASM export: Compose jamo into a Hangul syllable.
/// Returns the syllable code point, or 0 if invalid jamo.
export fn wasm_compose(initial: u32, medial: u32, final: u32) u32 {
    return compose(initial, medial, final) orelse 0;
}

/// WASM export: Decompose syllable into jamo array.
///
/// Writes initial, medial, final to output buffer (3 × u32 = 12 bytes).
/// Caller MUST allocate at least 12 bytes at output_ptr.
/// Returns true on success, false if not a valid Hangul syllable.
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

// ============================================================================
// WASM Exports - Jamo Classification
// ============================================================================

/// WASM export: Check if code point is a compatibility jamo.
export fn wasm_isJamo(c: u32) bool {
    return isJamo(c);
}

/// WASM export: Check if code point is a consonant.
export fn wasm_isConsonant(c: u32) bool {
    return isConsonant(c);
}

/// WASM export: Check if code point is a vowel.
export fn wasm_isVowel(c: u32) bool {
    return isVowel(c);
}

/// WASM export: Check if code point is a double consonant.
export fn wasm_isDoubleConsonant(c: u32) bool {
    return isDoubleConsonant(c);
}

/// WASM export: Check if code point is a double vowel.
export fn wasm_isDoubleVowel(c: u32) bool {
    return isDoubleVowel(c);
}

/// WASM export: Safe decompose with buffer size validation.
///
/// Like wasm_decompose, but validates output_size >= 3.
/// Returns false if syllable invalid OR buffer too small.
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

/// Compose array of jamo codepoints back into Hangul syllables
/// This is the inverse of decompose - takes jamo and produces syllables
/// Non-jamo codepoints pass through unchanged
/// Returns the number of output codepoints written
fn composeString(input: [*]const u32, input_len: usize, output: [*]u32) u32 {
    var out_idx: u32 = 0;
    var i: usize = 0;

    while (i < input_len) {
        const c = input[i];

        // Check if this is a consonant that could start a syllable
        if (isConsonant(c)) {
            // Look ahead for vowel
            if (i + 1 < input_len and isVowel(input[i + 1])) {
                const initial = c;
                const medial = input[i + 1];

                // Check for final consonant
                var final: u32 = 0;
                var consumed: usize = 2;

                if (i + 2 < input_len and isConsonant(input[i + 2])) {
                    // Check if next char after potential final is a vowel
                    // If so, the consonant belongs to the next syllable
                    if (i + 3 < input_len and isVowel(input[i + 3])) {
                        // Consonant starts next syllable, no final for current
                        final = 0;
                        consumed = 2;
                    } else {
                        // Consonant is final of current syllable
                        final = input[i + 2];
                        consumed = 3;
                    }
                }

                // Compose the syllable
                if (compose(initial, medial, final)) |syllable| {
                    output[out_idx] = syllable;
                    out_idx += 1;
                    i += consumed;
                    continue;
                }
            }
        }

        // Pass through non-composable characters
        output[out_idx] = c;
        out_idx += 1;
        i += 1;
    }

    return out_idx;
}

/// WASM export: Compose jamo array back into Hangul syllables.
///
/// Takes an array of jamo code points and combines them into syllables.
/// Non-jamo characters pass through unchanged.
/// Returns the number of output code points written.
export fn wasm_composeString(input_ptr: u32, input_len: u32, output_ptr: u32) u32 {
    const input: [*]const u32 = @ptrFromInt(input_ptr);
    const output: [*]u32 = @ptrFromInt(output_ptr);
    return composeString(input, input_len, output);
}

/// WASM export: Decompose UTF-8 string into jamo code points.
///
/// Reads UTF-8 bytes and decomposes Hangul syllables into jamo.
/// Non-Hangul characters pass through unchanged.
/// Returns the number of output code points written.
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

// ============================================================================
// UTF-8 Decoding Helpers
// ============================================================================

/// Result of decoding a single UTF-8 character.
const Utf8Char = struct {
    /// Decoded Unicode code point (0 if invalid/incomplete).
    char: u32,
    /// Number of bytes consumed (0 if invalid/incomplete).
    len: u32,
};

/// Decode a single UTF-8 character from a byte sequence.
///
/// Handles 1-4 byte sequences per UTF-8 spec.
/// Returns {char=0, len=0} for invalid or incomplete sequences.
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

// ============================================================================
// WASM Memory Allocation
// ============================================================================

// Simple bump allocator for WASM with reset capability
// Designed for bounded sessions (e.g., per-page-load or per-session)
const WASM_BUFFER_SIZE = 16 * 1024; // 16KB buffer
var wasm_buffer: [WASM_BUFFER_SIZE]u8 align(8) = undefined;
var wasm_alloc_ptr: u32 = 0;
var wasm_alloc_count: u32 = 0; // Track number of active allocations

/// WASM export: Allocate memory from the static buffer.
///
/// Returns a pointer (byte offset) into WASM linear memory,
/// or 0 if allocation fails. Memory is 4-byte aligned.
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
    wasm_alloc_count += 1;
    return @intCast(ptr);
}

/// WASM export: Free allocated memory.
///
/// For bump allocator, individual frees are no-ops, but when all allocations
/// are freed (alloc_count reaches 0), the allocator resets automatically.
/// This enables bounded session usage where memory is reclaimed after cleanup.
export fn wasm_free(ptr: u32, size: u32) void {
    _ = ptr;
    _ = size;

    // Decrement allocation count; reset when all freed
    if (wasm_alloc_count > 0) {
        wasm_alloc_count -= 1;
        if (wasm_alloc_count == 0) {
            // All allocations freed - reset the bump allocator
            wasm_alloc_ptr = 0;
        }
    }
}

/// WASM export: Reset the allocator completely.
///
/// Use this to reclaim all memory at once (e.g., on page unload or session end).
/// WARNING: All previously allocated pointers become invalid after this call.
export fn wasm_alloc_reset() void {
    wasm_alloc_ptr = 0;
    wasm_alloc_count = 0;
}

/// WASM export: Get allocator statistics for debugging.
///
/// Returns bytes used in the allocator buffer.
export fn wasm_alloc_used() u32 {
    return wasm_alloc_ptr;
}

/// WASM export: Get number of active allocations.
export fn wasm_alloc_count_active() u32 {
    return wasm_alloc_count;
}

// ============================================================================
// WASM API Exports for IME
// ============================================================================

/// Create new IME instance
/// Returns handle (pointer to ImeState in WASM memory)
/// Returns 0 if allocation fails
export fn wasm_ime_create() u32 {
    const state_ptr = wasm_alloc(@sizeOf(ime.ImeState));
    if (state_ptr == 0) return 0;

    const state: *ime.ImeState = @ptrFromInt(state_ptr);
    state.* = ime.ImeState.init();
    return state_ptr;
}

/// Destroy IME instance
/// @param handle: Pointer returned from wasm_ime_create
export fn wasm_ime_destroy(handle: u32) void {
    if (handle == 0) return;
    wasm_free(handle, @sizeOf(ime.ImeState));
}

/// Reset IME composition state
/// @param handle: IME instance pointer
export fn wasm_ime_reset(handle: u32) void {
    if (handle == 0) return;
    const state: *ime.ImeState = @ptrFromInt(handle);
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

    const state: *ime.ImeState = @ptrFromInt(handle);
    const output: [*]u32 = @ptrFromInt(result_ptr);

    // Determine if consonant or vowel based on ohi.js index range
    const result = if (jamo_index < 31)
        ime.processConsonant2Bulsik(state, jamo_index)
    else
        ime.processVowel2Bulsik(state, jamo_index);

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
    const state: *ime.ImeState = @ptrFromInt(handle);
    return ime.processBackspace(state) orelse 0;
}

/// Get current composition state (for debugging)
/// @param handle: IME instance pointer
/// @param output_ptr: Pointer to output buffer (6 bytes)
export fn wasm_ime_getState(handle: u32, output_ptr: u32) void {
    if (handle == 0 or output_ptr == 0) return;

    const state: *ime.ImeState = @ptrFromInt(handle);
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
    const state: *ime.ImeState = @ptrFromInt(handle);

    // Get current codepoint before reset
    const codepoint = state.toCodepoint();

    // Reset state for next composition
    state.reset();

    return codepoint;
}

/// Process keystroke in 3-Bulsik layout
/// @param handle: IME instance pointer
/// @param ascii: ASCII keycode (33-126)
/// @param result_ptr: Pointer to output buffer (16 bytes = 4 × u32)
/// @returns true if key was handled as Hangul
///
/// Output buffer format (4 × u32):
/// [0] action: 0=no_change, 1=replace, 2=emit_and_new, 3=literal
/// [1] prev_codepoint: Previous character (if action=emit_and_new)
/// [2] current_codepoint: Current character
/// [3] literal_codepoint: Literal character to insert (if action=literal)
export fn wasm_ime_processKey3(
    handle: u32,
    ascii: u8,
    result_ptr: u32,
) bool {
    if (handle == 0 or result_ptr == 0) return false;

    const state: *ime.ImeState = @ptrFromInt(handle);
    const output: [*]u32 = @ptrFromInt(result_ptr);

    // Map ASCII to 3-Bulsik token
    const token = ime.mapKeycode3Bulsik(ascii);
    if (token == null) {
        // Invalid ASCII range
        output[0] = 0; // no_change
        output[1] = 0;
        output[2] = 0;
        output[3] = 0;
        return false;
    }

    switch (token.?) {
        .cho => |idx| {
            const result = ime.processCho3Bulsik(state, idx);
            output[0] = @intFromEnum(result.action);
            output[1] = result.prev_codepoint;
            output[2] = result.current_codepoint;
            output[3] = 0;
        },
        .jung => |idx| {
            const result = ime.processJung3Bulsik(state, idx);
            output[0] = @intFromEnum(result.action);
            output[1] = result.prev_codepoint;
            output[2] = result.current_codepoint;
            output[3] = 0;
        },
        .jong => |idx| {
            const result = ime.processJong3Bulsik(state, idx);
            output[0] = @intFromEnum(result.action);
            output[1] = result.prev_codepoint;
            output[2] = result.current_codepoint;
            output[3] = 0;
        },
        .other => |cp| {
            // Literal character - commit current composition if any
            if (!state.isEmpty()) {
                output[0] = 2; // emit_and_new
                output[1] = state.toCodepoint();
                state.reset();
            } else {
                output[0] = 3; // literal (custom action)
                output[1] = 0;
            }
            output[2] = 0;
            output[3] = cp; // The literal character to insert
        },
    }

    return true;
}

// ============================================================================
// Tests - Core Hangul Functions
// ============================================================================

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

test "composeString: jamo array to syllables" {
    // Test composing jamo back into syllables
    // 한글 decomposed: ㅎ ㅏ ㄴ ㄱ ㅡ ㄹ
    const jamo = [_]u32{
        0x314E, 0x314F, 0x3134, // ㅎ ㅏ ㄴ → 한
        0x3131, 0x3161, 0x3139, // ㄱ ㅡ ㄹ → 글
    };
    var output: [10]u32 = undefined;

    const count = composeString(&jamo, jamo.len, &output);

    try std.testing.expectEqual(@as(u32, 2), count);
    try std.testing.expectEqual(@as(u32, 0xD55C), output[0]); // 한
    try std.testing.expectEqual(@as(u32, 0xAE00), output[1]); // 글
}

test "composeString: syllable without final" {
    // 가 = ㄱ + ㅏ (no final)
    const jamo = [_]u32{ 0x3131, 0x314F }; // ㄱ ㅏ
    var output: [5]u32 = undefined;

    const count = composeString(&jamo, jamo.len, &output);

    try std.testing.expectEqual(@as(u32, 1), count);
    try std.testing.expectEqual(@as(u32, 0xAC00), output[0]); // 가
}

test "composeString: mixed jamo and non-jamo" {
    // "A한B" decomposed: A ㅎ ㅏ ㄴ B
    const input = [_]u32{ 'A', 0x314E, 0x314F, 0x3134, 'B' };
    var output: [10]u32 = undefined;

    const count = composeString(&input, input.len, &output);

    try std.testing.expectEqual(@as(u32, 3), count);
    try std.testing.expectEqual(@as(u32, 'A'), output[0]);
    try std.testing.expectEqual(@as(u32, 0xD55C), output[1]); // 한
    try std.testing.expectEqual(@as(u32, 'B'), output[2]);
}

test "composeString: lone consonant passes through" {
    // Single consonant with no vowel following
    const jamo = [_]u32{0x3131}; // ㄱ alone
    var output: [5]u32 = undefined;

    const count = composeString(&jamo, jamo.len, &output);

    try std.testing.expectEqual(@as(u32, 1), count);
    try std.testing.expectEqual(@as(u32, 0x3131), output[0]); // ㄱ (unchanged)
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

test "bump allocator: allocation count tracking (host)" {
    // Test the allocation counting logic without WASM pointer conversion
    // Reset to known state
    wasm_alloc_ptr = 0;
    wasm_alloc_count = 0;

    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_used());
    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_count_active());

    // Simulate allocations by directly manipulating state
    wasm_alloc_ptr = 100;
    wasm_alloc_count = 2;

    try std.testing.expectEqual(@as(u32, 100), wasm_alloc_used());
    try std.testing.expectEqual(@as(u32, 2), wasm_alloc_count_active());

    // Free one - count decreases but ptr stays
    wasm_free(0, 0);
    try std.testing.expectEqual(@as(u32, 1), wasm_alloc_count_active());
    try std.testing.expectEqual(@as(u32, 100), wasm_alloc_used()); // Not reset yet

    // Free last - should auto-reset
    wasm_free(0, 0);
    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_count_active());
    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_used()); // Auto-reset!
}

test "bump allocator: manual reset (host)" {
    wasm_alloc_ptr = 500;
    wasm_alloc_count = 5;

    wasm_alloc_reset();

    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_count_active());
    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_used());
}

test "bump allocator: wasm-only tests" {
    // Skip on non-WASM targets since pointer sizes differ
    if (@import("builtin").target.cpu.arch != .wasm32) return error.SkipZigTest;

    // Reset allocator to known state
    wasm_alloc_reset();

    // Allocate some memory
    const ptr1 = wasm_alloc(100);
    try std.testing.expect(ptr1 != 0);
    try std.testing.expectEqual(@as(u32, 1), wasm_alloc_count_active());

    const ptr2 = wasm_alloc(200);
    try std.testing.expect(ptr2 != 0);
    try std.testing.expectEqual(@as(u32, 2), wasm_alloc_count_active());

    // Free all
    wasm_free(ptr1, 100);
    wasm_free(ptr2, 200);
    try std.testing.expectEqual(@as(u32, 0), wasm_alloc_used());

    // Test allocation failure
    const huge = wasm_alloc(WASM_BUFFER_SIZE + 1);
    try std.testing.expectEqual(@as(u32, 0), huge);

    wasm_alloc_reset();
}

// Build configuration comment:
// Build with: zig build-lib hangul.zig -target wasm32-freestanding -dynamic -rdynamic -O ReleaseSmall
// This creates hangul.wasm that can be used from JavaScript
