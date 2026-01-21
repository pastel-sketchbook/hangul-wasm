const std = @import("std");
const hangul = @import("hangul.zig");

// Re-export core constants and functions needed by IME
const OHI_VOWEL_BASE = hangul.OHI_VOWEL_BASE;
const OHI_JAMO_OFFSET = hangul.OHI_JAMO_OFFSET;
const COMPAT_INITIAL = hangul.COMPAT_INITIAL;
const COMPAT_MEDIAL = hangul.COMPAT_MEDIAL;
const COMPAT_FINAL = hangul.COMPAT_FINAL;
const ohiIndexToInitialIdx = hangul.ohiIndexToInitialIdx;
const ohiIndexToMedialIdx = hangul.ohiIndexToMedialIdx;
const ohiIndexToFinalIdx = hangul.ohiIndexToFinalIdx;
const ohiIndexToSingleJamo = hangul.ohiIndexToSingleJamo;
const compose = hangul.compose;

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

        // Return single jamo (partial composition)
        if (self.initial > 0) return ohiIndexToSingleJamo(self.initial);
        if (self.medial > 0) return ohiIndexToSingleJamo(self.medial);
        if (self.final > 0) return ohiIndexToSingleJamo(self.final);

        return 0;
    }
};

/// Result from keystroke processing
pub const KeyResult = struct {
    action: Action,
    prev_codepoint: u32, // Emit this first (if action=emit_and_new)
    current_codepoint: u32, // Then emit/replace with this

    pub const Action = enum { no_change, replace, emit_and_new };
};

// ============================================================================
// 3-Bulsik (Sebeolsik) Keyboard Layout
// ============================================================================

/// 3-Bulsik lookup table from ohi.js lines 204-299
/// Maps ASCII codes 33-126 to token values:
/// - 93-122: Initial consonant (cho) → subtract 92 to get ohi index
/// - 66-86: Medial vowel (jung) → subtract 35 to get ohi index
/// - 1-30: Final consonant (jong) → use as-is for ohi index
/// - Other values: Literal characters (punctuation, etc.)
const LAYOUT_3BULSIK_LOOKUP = [94]u16{
    // Directly from ohi.js lines 204-299 (94 elements for ASCII 33-126)
    2, 183, 24, 15, 14, 8220, 120, 39, 126, 8221, // ! " # $ % & ' ( ) *
    43, 44, 41, 46, 74, 119, 30, 22, 18, 78, // + , - . / 0 1 2 3 4
    83, 68, 73, 85, 79, 52, 110, 44, 62, 46, // 5 6 7 8 9 : ; < = >
    33, 10, 7, 63, 27, 12, 5, 11, 69, 48, // ? @ A B C D E F G H
    55, 49, 50, 51, 34, 45, 56, 57, 29, 16, // I J K L M N O P Q R
    6, 13, 54, 3, 28, 20, 53, 26, 40, 58, // S T U V W X Y Z [ \
    60, 61, 59, 42, 23, 79, 71, 86, 72, 66, // ] ^ _ ` a b c d
    84, 96, 109, 115, 93, 116, 122, 113, 118, 121, // e f g h i j k l m n
    21, 67, 4, 70, 99, 74, 9, 1, 101, 17, // o p q r s t u v w x
    37, 92, 47, 8251, // y z { |
};

/// Token type returned by 3-Bulsik key mapping
pub const K3TokenTag = enum { cho, jung, jong, other };

pub const K3Token = union(K3TokenTag) {
    cho: u8, // Initial consonant (1-30)
    jung: u8, // Medial vowel (31-51)
    jong: u8, // Final consonant (1-30)
    other: u32, // Literal codepoint to insert
};

/// Map ASCII keycode to 3-Bulsik token
/// Based on ohi.js HAN3() which interprets lookup table values
pub fn mapKeycode3Bulsik(ascii: u8) ?K3Token {
    // ASCII 33 ('!') to 126 ('~') are mapped
    if (ascii < 33 or ascii > 126) return null;

    const idx = ascii - 33;
    const value = LAYOUT_3BULSIK_LOOKUP[idx];

    // Interpret value based on ranges (from ohi.js):
    // 93-122: cho (initial) → subtract 92 to get ohi index
    // 66-86: jung (medial) → subtract 35 to get ohi index (range 31-51)
    // 1-30: jong (final) → use as-is
    // Other: literal character to insert
    if (value >= 93 and value <= 122) {
        return .{ .cho = @intCast(value - 92) }; // ohi index 1-30
    } else if (value >= 66 and value <= 86) {
        return .{ .jung = @intCast(value - 35) }; // ohi index 31-51
    } else if (value >= 1 and value <= 30) {
        return .{ .jong = @intCast(value) }; // ohi index 1-30
    } else {
        return .{ .other = value }; // Literal codepoint
    }
}

// ============================================================================
// 2-Bulsik (Dubeolsik) Keyboard Layout
// ============================================================================

// Actual keyboard mapping following ohi.js (lines 119-146)
// This maps ASCII code points to jamo indices
pub fn mapKeycode2Bulsik(ascii: u8, shifted: bool) ?u8 {
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
pub const DoubleJamoType = enum { initial, medial, final };

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

// Double final consonants using ohi.js indices (lines 40-46)
// Note: ohi.js uses different indices for consonants as finals vs initials
// ㄱ=1, ㄴ=4, ㄹ=9, ㅁ=17, ㅂ=18, ㅅ=21, ㅈ=24, ㅌ=28, ㅍ=29, ㅎ=30
const DOUBLE_FINAL_MAPS = [_]DoubleFinalMap{
    .{ .base = 1, .targets = &[_]u8{21}, .results = &[_]u8{3} }, // ㄱ+ㅅ(21)=ㄳ (final[3])
    .{ .base = 4, .targets = &[_]u8{ 24, 30 }, .results = &[_]u8{ 5, 6 } }, // ㄴ+ㅈ(24)=ㄵ, ㄴ+ㅎ(30)=ㄶ
    .{ .base = 9, .targets = &[_]u8{ 1, 17, 18, 21, 28, 29, 30 }, .results = &[_]u8{ 10, 11, 12, 13, 14, 15, 16 } }, // ㄹ+ㄱ(1)=ㄺ, ㄹ+ㅁ(17)=ㄻ, ㄹ+ㅂ(18)=ㄼ, ㄹ+ㅅ(21)=ㄽ, ㄹ+ㅌ(28)=ㄾ, ㄹ+ㅍ(29)=ㄿ, ㄹ+ㅎ(30)=ㅀ
    .{ .base = 18, .targets = &[_]u8{21}, .results = &[_]u8{20} }, // ㅂ+ㅅ(21)=ㅄ (final[18])
};

/// Split a double final consonant back into its two components
/// Returns (base, target) ohi indices, or (0, 0) if not a double final
pub fn splitDoubleFinal(double_final: u8) struct { base: u8, second: u8 } {
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
pub fn detectDoubleJamo(jamo_type: DoubleJamoType, current: u8, incoming: u8) u8 {
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
pub fn processConsonant2Bulsik(state: *ImeState, jamo_index: i8) KeyResult {
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

    // If we already have a double final (final_flag == 1), we must emit current syllable
    // and start new. Cannot add more consonants to a double final.
    // This fixes: "않" + ㄴ → should emit "않" and start "ㄴ", not incorrectly split.
    if (state.medial > 0 and state.final > 0 and state.final_flag == 1) {
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
pub fn processVowel2Bulsik(state: *ImeState, jamo_index: i8) KeyResult {
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

// ============================================================================
// 3-Bulsik (Sebeolsik) State Machine
// Based on ohi.js Hangul3() lines 300-332
// Key difference from 2-Bulsik: No syllable splitting - cho/jung/jong are explicit
// ============================================================================

/// Process initial consonant (cho) in 3-Bulsik mode
/// Based on ohi.js Hangul3() lines 300-309
pub fn processCho3Bulsik(state: *ImeState, cho_index: u8) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };

    // If have existing initial without medial, try double initial
    // ohi.js: this.doubleJamo(0, this._q[0], c - 92)
    if (state.initial > 0 and state.medial == 0 and state.initial_flag == 0) {
        const double_idx = detectDoubleJamo(.initial, @intCast(state.initial), cho_index);
        if (double_idx != 0) {
            state.initial = @intCast(double_idx);
            state.initial_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
    }

    // ohi.js condition: _q[1] || _q[2] || !doubleJamo(...)
    // If have medial (_q[2]) or have initial-double flag (_q[1]), emit current and start new
    // Otherwise if doubleJamo succeeded, we already returned above
    // So if we get here: emit current (if any), start new with cho
    if (!state.isEmpty()) {
        result.action = .emit_and_new;
        result.prev_codepoint = state.toCodepoint();
    }

    // Start new syllable with cho
    state.reset();
    state.initial = @intCast(cho_index);
    state.initial_flag = 0;
    result.current_codepoint = state.toCodepoint();

    return result;
}

/// Process medial vowel (jung) in 3-Bulsik mode
/// Based on ohi.js Hangul3() lines 310-319
pub fn processJung3Bulsik(state: *ImeState, jung_index: u8) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };

    // If have medial but no final, try double medial
    if (state.medial > 0 and state.final == 0 and state.medial_flag == 0) {
        const double_idx = detectDoubleJamo(.medial, @intCast(state.medial), jung_index);
        if (double_idx != 0) {
            state.medial = @intCast(double_idx);
            state.medial_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
        // Cannot double, mark for new syllable
        state.medial = -1;
    }

    // ohi.js condition: ((!_q[0] || _q[2]) && (!_q[3] || _q[4])) || _q[2] < 0
    // Translation:
    // - (!_q[0] || _q[2]) = no cho OR already have jung
    // - (!_q[3] || _q[4]) = no jung-double OR have jong
    // If this condition is true, emit current and start new with just jung
    const should_emit = ((state.initial == 0 or state.medial != 0) and
        (state.medial_flag == 0 or state.final > 0)) or
        state.medial < 0;

    if (should_emit) {
        // Emit current composition (if any) and start new with just jung
        if (!state.isEmpty()) {
            result.action = .emit_and_new;
            result.prev_codepoint = state.toCodepoint();
        }
        state.reset();
        state.medial = @intCast(jung_index);
        state.medial_flag = 0;
        result.current_codepoint = state.toCodepoint();
    } else {
        // Add jung to existing cho
        state.medial = @intCast(jung_index);
        state.medial_flag = 0;
        result.action = .replace;
        result.current_codepoint = state.toCodepoint();
    }

    return result;
}

/// Process final consonant (jong) in 3-Bulsik mode
pub fn processJong3Bulsik(state: *ImeState, jong_index: u8) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };

    // If have final already, try double final
    if (state.final > 0 and state.final_flag == 0) {
        const double_idx = detectDoubleJamo(.final, @intCast(state.final), jong_index);
        if (double_idx != 0) {
            state.final = @intCast(double_idx);
            state.final_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
        // Cannot double, mark for new syllable
        state.final = -1;
    }

    // Need cho + jung to add jong
    if (state.initial > 0 and state.medial > 0 and state.final == 0) {
        state.final = @intCast(jong_index);
        state.final_flag = 0;
        result.action = .replace;
        result.current_codepoint = state.toCodepoint();
    } else {
        // Invalid state for jong, emit and start new with just jong
        if (!state.isEmpty()) {
            result.action = .emit_and_new;
            result.prev_codepoint = state.toCodepoint();
        }
        state.reset();
        state.final = @intCast(jong_index);
        result.current_codepoint = state.toCodepoint();
    }

    return result;
}

/// Process backspace - decomposes syllable step by step
/// Based on ohi.js keydownHandler() lines 418-427
pub fn processBackspace(state: *ImeState) ?u32 {
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
// Tests
// ============================================================================

test "ime state initialization" {
    const state = ImeState.init();
    try std.testing.expect(state.isEmpty());
    try std.testing.expectEqual(@as(u32, 0), state.toCodepoint());
}

test "ime state reset" {
    var state = ImeState.init();
    state.initial = 1;
    state.medial = 31;
    state.final = 4;
    try std.testing.expect(!state.isEmpty());
    state.reset();
    try std.testing.expect(state.isEmpty());
}

test "ime state single jamo" {
    var state = ImeState.init();

    // Initial only: should return single jamo
    state.initial = 1; // ㄱ = 0x3131
    try std.testing.expectEqual(@as(u32, 0x3131), state.toCodepoint());

    // Medial only
    state.reset();
    state.medial = 31; // ㅏ = 0x314F
    try std.testing.expectEqual(@as(u32, 0x314F), state.toCodepoint());
}

test "ime state compose syllable" {
    var state = ImeState.init();
    state.initial = 1; // ㄱ
    state.medial = 31; // ㅏ
    // Should compose 가 (U+AC00)
    try std.testing.expectEqual(@as(u32, 0xAC00), state.toCodepoint());
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
    try std.testing.expectEqual(@as(u8, 0), detectDoubleJamo(.medial, 31, 31)); // ㅏ+ㅏ
}

test "double jamo: final consonants" {
    // ㄱ+ㅅ=ㄳ (1+21=3)
    try std.testing.expectEqual(@as(u8, 3), detectDoubleJamo(.final, 1, 21));
    // ㄹ+ㄱ=ㄺ (9+1=10)
    try std.testing.expectEqual(@as(u8, 10), detectDoubleJamo(.final, 9, 1));
    // ㄹ+ㅂ=ㄼ (9+18=12)
    try std.testing.expectEqual(@as(u8, 12), detectDoubleJamo(.final, 9, 18));
    // ㄱ+ㄴ = not a valid double final
    try std.testing.expectEqual(@as(u8, 0), detectDoubleJamo(.final, 1, 4));
}

test "2-bulsik: type single consonant" {
    var state = ImeState.init();
    const result = processConsonant2Bulsik(&state, 1); // ㄱ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0x3131), result.current_codepoint); // ㄱ
    try std.testing.expectEqual(@as(i8, 1), state.initial);
}

test "2-bulsik: type 가 (g-a)" {
    var state = ImeState.init();

    // Type ㄱ
    _ = processConsonant2Bulsik(&state, 1);
    // Type ㅏ
    const result = processVowel2Bulsik(&state, 31);

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0xAC00), result.current_codepoint); // 가
}

test "2-bulsik: type 한 (han)" {
    var state = ImeState.init();

    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    const result = processConsonant2Bulsik(&state, 4); // ㄴ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0xD55C), result.current_codepoint); // 한
}

test "2-bulsik: double consonant ㄲ" {
    var state = ImeState.init();

    _ = processConsonant2Bulsik(&state, 1); // ㄱ
    const result = processConsonant2Bulsik(&state, 1); // ㄱ again

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0x3132), result.current_codepoint); // ㄲ
}

test "2-bulsik: double vowel ㅘ (ㅗ+ㅏ)" {
    var state = ImeState.init();

    _ = processConsonant2Bulsik(&state, 1); // ㄱ
    _ = processVowel2Bulsik(&state, 39); // ㅗ
    const result = processVowel2Bulsik(&state, 31); // ㅏ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    // 과 (U+ACFC) = ㄱ + ㅘ
    try std.testing.expectEqual(@as(u32, 0xACFC), result.current_codepoint);
}

test "2-bulsik: syllable split" {
    var state = ImeState.init();

    // Type 한 (ㅎ+ㅏ+ㄴ)
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ

    // Now type ㅏ - should split: 하 + ㄴㅏ = 하 + 나
    const result = processVowel2Bulsik(&state, 31);

    try std.testing.expectEqual(KeyResult.Action.emit_and_new, result.action);
    try std.testing.expectEqual(@as(u32, 0xD558), result.prev_codepoint); // 하
    try std.testing.expectEqual(@as(u32, 0xB098), result.current_codepoint); // 나
}

test "2-bulsik: emit on new consonant after complete syllable" {
    var state = ImeState.init();

    // Type 한 (ㅎ+ㅏ+ㄴ)
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ

    // Type another consonant ㄱ - can form double final?
    // ㄴ+ㄱ is NOT a valid double final, so:
    // - Should emit 한 and start new with ㄱ
    const result = processConsonant2Bulsik(&state, 1); // ㄱ

    try std.testing.expectEqual(KeyResult.Action.emit_and_new, result.action);
    try std.testing.expectEqual(@as(u32, 0xD55C), result.prev_codepoint); // 한
    try std.testing.expectEqual(@as(u32, 0x3131), result.current_codepoint); // ㄱ
}

test "double final consonant splitting" {
    var state = ImeState.init();

    // Type 닭 = ㄷ+ㅏ+ㄹ+ㄱ
    // ㄷ=7, ㅏ=31, ㄹ=9, ㄱ=1 (in ohi.js indices)
    _ = processConsonant2Bulsik(&state, 7); // ㄷ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 9); // ㄹ

    // Check we have 달 so far
    try std.testing.expectEqual(@as(u32, 0xB2EC), state.toCodepoint()); // 달

    // Add ㄱ to form ㄺ (double final)
    _ = processConsonant2Bulsik(&state, 1); // ㄱ

    // Should now have 닭
    try std.testing.expectEqual(@as(u32, 0xB2ED), state.toCodepoint()); // 닭
    try std.testing.expectEqual(@as(u8, 1), state.final_flag); // Double final flag set

    // Now type ㅏ - should split: 달 + 가
    const result = processVowel2Bulsik(&state, 31); // ㅏ

    try std.testing.expectEqual(KeyResult.Action.emit_and_new, result.action);
    try std.testing.expectEqual(@as(u32, 0xB2EC), result.prev_codepoint); // 달
    try std.testing.expectEqual(@as(u32, 0xAC00), result.current_codepoint); // 가
}

test "3-bulsik: mapping table size" {
    // Ensure table has correct size (94 elements for ASCII 33-126)
    try std.testing.expectEqual(@as(usize, 94), LAYOUT_3BULSIK_LOOKUP.len);
}

test "3-bulsik: mapping invalid ASCII" {
    // Below range
    try std.testing.expect(mapKeycode3Bulsik(32) == null);
    // Above range
    try std.testing.expect(mapKeycode3Bulsik(127) == null);
}

test "3-bulsik: mapping initial consonants (cho)" {
    // Test some initial consonant mappings from ohi.js
    // 'k' (ASCII 107) maps to 93 → cho index 1 (ㄱ)
    const k_token = mapKeycode3Bulsik('k');
    try std.testing.expect(k_token != null);
    switch (k_token.?) {
        .cho => |idx| try std.testing.expectEqual(@as(u8, 1), idx),
        else => return error.UnexpectedTokenType,
    }

    // 'j' (ASCII 106) maps to 115 → cho index 23 (ㅇ)
    const j_token = mapKeycode3Bulsik('j');
    try std.testing.expect(j_token != null);
    switch (j_token.?) {
        .cho => |idx| try std.testing.expectEqual(@as(u8, 23), idx),
        else => return error.UnexpectedTokenType,
    }
}

test "3-bulsik: mapping medial vowels (jung)" {
    // 'f' (ASCII 102) maps to 66 → jung index 31 (ㅏ)
    const f_token = mapKeycode3Bulsik('f');
    try std.testing.expect(f_token != null);
    switch (f_token.?) {
        .jung => |idx| try std.testing.expectEqual(@as(u8, 31), idx),
        else => return error.UnexpectedTokenType,
    }

    // 'd' (ASCII 100) maps to 86 → jung index 51 (ㅣ)
    const d_token = mapKeycode3Bulsik('d');
    try std.testing.expect(d_token != null);
    switch (d_token.?) {
        .jung => |idx| try std.testing.expectEqual(@as(u8, 51), idx),
        else => return error.UnexpectedTokenType,
    }
}

test "3-bulsik: mapping final consonants (jong)" {
    // '!' (ASCII 33) maps to 2 → jong index 2
    const exclaim_token = mapKeycode3Bulsik('!');
    try std.testing.expect(exclaim_token != null);
    switch (exclaim_token.?) {
        .jong => |idx| try std.testing.expectEqual(@as(u8, 2), idx),
        else => return error.UnexpectedTokenType,
    }

    // 'A' (ASCII 65) maps to 7 → jong index 7
    const a_upper_token = mapKeycode3Bulsik('A');
    try std.testing.expect(a_upper_token != null);
    switch (a_upper_token.?) {
        .jong => |idx| try std.testing.expectEqual(@as(u8, 7), idx),
        else => return error.UnexpectedTokenType,
    }
}

test "3-bulsik: mapping punctuation (other)" {
    // '"' (ASCII 34) → 183 → other (middle dot ·)
    const token_quote = mapKeycode3Bulsik('"');
    try std.testing.expect(token_quote != null);
    switch (token_quote.?) {
        .other => |cp| try std.testing.expectEqual(@as(u32, 183), cp),
        else => return error.UnexpectedTokenType,
    }

    // '&' (ASCII 38) → 8220 → left double quotation mark "
    const token_amp = mapKeycode3Bulsik('&');
    try std.testing.expect(token_amp != null);
    switch (token_amp.?) {
        .other => |cp| try std.testing.expectEqual(@as(u32, 8220), cp),
        else => return error.UnexpectedTokenType,
    }
}

test "3-bulsik: type single cho (initial)" {
    var state = ImeState.init();
    const result = processCho3Bulsik(&state, 1); // ㄱ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0x3131), result.current_codepoint); // ㄱ
}

test "3-bulsik: type 가 (cho + jung)" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 1); // ㄱ
    const result = processJung3Bulsik(&state, 31); // ㅏ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0xAC00), result.current_codepoint); // 가
}

test "3-bulsik: type 간 (cho + jung + jong)" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 1); // ㄱ
    _ = processJung3Bulsik(&state, 31); // ㅏ
    const result = processJong3Bulsik(&state, 4); // ㄴ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0xAC04), result.current_codepoint); // 간
}

test "3-bulsik: double cho ㄲ" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 1); // ㄱ
    const result = processCho3Bulsik(&state, 1); // ㄱ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    try std.testing.expectEqual(@as(u32, 0x3132), result.current_codepoint); // ㄲ
}

test "3-bulsik: double jung ㅘ" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 1); // ㄱ
    _ = processJung3Bulsik(&state, 39); // ㅗ
    const result = processJung3Bulsik(&state, 31); // ㅏ

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    // 과 (U+ACFC) = ㄱ + ㅘ
    try std.testing.expectEqual(@as(u32, 0xACFC), result.current_codepoint);
}

test "3-bulsik: double jong ㄳ" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 1); // ㄱ
    _ = processJung3Bulsik(&state, 31); // ㅏ
    _ = processJong3Bulsik(&state, 1); // ㄱ (jong)
    const result = processJong3Bulsik(&state, 21); // ㅅ (jong)

    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    // 갃 = ㄱ + ㅏ + ㄳ
    // U+AC03 = 0xAC00 + 3 (final index 3 = ㄳ)
    try std.testing.expectEqual(@as(u32, 0xAC03), result.current_codepoint);
}

test "3-bulsik: new cho commits previous syllable" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 1); // ㄱ
    _ = processJung3Bulsik(&state, 31); // ㅏ
    const result = processCho3Bulsik(&state, 4); // ㄴ (new cho)

    try std.testing.expectEqual(KeyResult.Action.emit_and_new, result.action);
    try std.testing.expectEqual(@as(u32, 0xAC00), result.prev_codepoint); // 가
    try std.testing.expectEqual(@as(u32, 0x3134), result.current_codepoint); // ㄴ
}

test "3-bulsik: no syllable splitting (unlike 2-bulsik)" {
    var state = ImeState.init();
    _ = processCho3Bulsik(&state, 30); // ㅎ
    _ = processJung3Bulsik(&state, 31); // ㅏ
    _ = processJong3Bulsik(&state, 4); // ㄴ
    // Now have 한

    // In 3-bulsik, typing a new jung should emit and start new (no split)
    const result = processJung3Bulsik(&state, 31); // ㅏ

    // Should emit 한 and start new with just ㅏ
    try std.testing.expectEqual(KeyResult.Action.emit_and_new, result.action);
    try std.testing.expectEqual(@as(u32, 0xD55C), result.prev_codepoint); // 한
    try std.testing.expectEqual(@as(u32, 0x314F), result.current_codepoint); // ㅏ (just vowel)
}

test "3-bulsik: jong without cho emits jong alone" {
    var state = ImeState.init();
    const result = processJong3Bulsik(&state, 4); // ㄴ as jong, no cho/jung first

    // In 3-bulsik, jong without complete syllable should just emit the jong alone
    try std.testing.expectEqual(KeyResult.Action.replace, result.action);
    // Single jamo should be returned
    // But wait - state has only final, so toCodepoint will return final jamo
    try std.testing.expectEqual(@as(u32, 0x3134), result.current_codepoint); // ㄴ

    // Verify state
    try std.testing.expectEqual(@as(i8, 0), state.initial);
    try std.testing.expectEqual(@as(i8, 0), state.medial);
    try std.testing.expectEqual(@as(i8, 4), state.final);
}

test "ime commit finalizes composition" {
    var state = ImeState.init();

    // Build up 한
    _ = processConsonant2Bulsik(&state, 30); // ㅎ
    _ = processVowel2Bulsik(&state, 31); // ㅏ
    _ = processConsonant2Bulsik(&state, 4); // ㄴ

    // Get codepoint before reset (simulating commit)
    const codepoint = state.toCodepoint();
    try std.testing.expectEqual(@as(u32, 0xD55C), codepoint); // 한

    // Reset (as commit would do)
    state.reset();
    try std.testing.expect(state.isEmpty());
    try std.testing.expectEqual(@as(u32, 0), state.toCodepoint());
}

test "ime commit on empty state returns zero" {
    var state = ImeState.init();

    // Empty state
    try std.testing.expect(state.isEmpty());
    const codepoint = state.toCodepoint();
    try std.testing.expectEqual(@as(u32, 0), codepoint);
}

test "ime commit on partial syllable returns jamo" {
    var state = ImeState.init();

    // Just initial consonant
    _ = processConsonant2Bulsik(&state, 1); // ㄱ

    const codepoint = state.toCodepoint();
    try std.testing.expectEqual(@as(u32, 0x3131), codepoint); // ㄱ

    state.reset();
    try std.testing.expect(state.isEmpty());
}

// ============================================================================
// Property-Based / Fuzz Tests
// ============================================================================

test "fuzz: random 2-bulsik keystroke sequences never panic" {
    // Property: Any sequence of valid jamo indices should not panic
    // and should produce valid state transitions
    var state = ImeState.init();

    // Valid consonant indices: 1-30
    const consonants = [_]i8{ 1, 2, 4, 7, 8, 9, 17, 18, 19, 21, 22, 24, 25, 26, 27, 28, 29, 30 };
    // Valid vowel indices: 31-51
    const vowels = [_]i8{ 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 43, 44, 45, 49, 51 };

    // Generate pseudo-random sequence using simple LCG
    var seed: u32 = 0xDEADBEEF;
    const iterations = 1000;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // LCG: seed = (a * seed + c) mod m
        seed = seed *% 1103515245 +% 12345;
        const rand = (seed >> 16) & 0x7FFF;

        // 50% chance consonant, 50% chance vowel
        if (rand % 2 == 0) {
            const idx = rand % consonants.len;
            const result = processConsonant2Bulsik(&state, consonants[idx]);
            // Result should always be valid
            try std.testing.expect(result.action == .no_change or
                result.action == .replace or
                result.action == .emit_and_new);
        } else {
            const idx = rand % vowels.len;
            const result = processVowel2Bulsik(&state, vowels[idx]);
            try std.testing.expect(result.action == .no_change or
                result.action == .replace or
                result.action == .emit_and_new);
        }

        // Verify state is always valid
        try std.testing.expect(state.initial >= -1 and state.initial <= 30);
        try std.testing.expect(state.medial >= -1 and state.medial <= 51);
        try std.testing.expect(state.final >= -1 and state.final <= 30);

        // Occasionally reset (10% chance)
        if (rand % 10 == 0) {
            state.reset();
        }
    }
}

test "fuzz: random 3-bulsik keystroke sequences never panic" {
    // Property: Any valid ASCII keystroke should not panic
    var state = ImeState.init();

    // Valid ASCII range for 3-Bulsik: 33-126
    var seed: u32 = 0xCAFEBABE;
    const iterations = 1000;

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        seed = seed *% 1103515245 +% 12345;
        const rand = (seed >> 16) & 0x7FFF;

        // Generate ASCII in valid range
        const ascii: u8 = @intCast(33 + (rand % 94));

        const token = mapKeycode3Bulsik(ascii);
        if (token) |t| {
            const result = switch (t) {
                .cho => |idx| processCho3Bulsik(&state, idx),
                .jung => |idx| processJung3Bulsik(&state, idx),
                .jong => |idx| processJong3Bulsik(&state, idx),
                .other => blk: {
                    // Other characters commit and emit
                    state.reset();
                    break :blk KeyResult{
                        .action = .emit_and_new,
                        .prev_codepoint = 0,
                        .current_codepoint = t.other,
                    };
                },
            };
            try std.testing.expect(result.action == .no_change or
                result.action == .replace or
                result.action == .emit_and_new);
        }

        // Occasionally reset
        if (rand % 10 == 0) {
            state.reset();
        }
    }
}

test "fuzz: backspace never corrupts state" {
    var state = ImeState.init();

    var seed: u32 = 0x12345678;
    const iterations = 500;
    const consonants = [_]i8{ 1, 4, 7, 17, 21, 30 };
    const vowels = [_]i8{ 31, 35, 39, 44, 51 };

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        seed = seed *% 1103515245 +% 12345;
        const rand = (seed >> 16) & 0x7FFF;

        // Random action: keystroke or backspace
        const action = rand % 3;
        if (action == 0) {
            // Consonant
            const idx = rand % consonants.len;
            _ = processConsonant2Bulsik(&state, consonants[idx]);
        } else if (action == 1) {
            // Vowel
            const idx = rand % vowels.len;
            _ = processVowel2Bulsik(&state, vowels[idx]);
        } else {
            // Backspace
            _ = processBackspace(&state);
        }

        // State should always be valid after any operation
        try std.testing.expect(state.initial >= 0 or state.initial == -1);
        try std.testing.expect(state.medial >= 0 or state.medial == -1);
        try std.testing.expect(state.final >= 0 or state.final == -1);
    }
}

test "property: decompose then compose roundtrips for valid syllables" {
    // Property: For any valid syllable, decompose → compose should return original
    const HANGUL_BASE: u32 = 0xAC00;
    const HANGUL_END: u32 = 0xD7A3;

    // Test a sample of syllables (every 100th to keep test fast)
    var syllable: u32 = HANGUL_BASE;
    while (syllable <= HANGUL_END) : (syllable += 100) {
        const decomp = hangul.decompose(syllable);
        try std.testing.expect(decomp != null);

        if (decomp) |d| {
            const recomposed = compose(d.initial, d.medial, d.final);
            try std.testing.expect(recomposed != null);
            try std.testing.expectEqual(syllable, recomposed.?);
        }
    }
}

test "property: all valid jamo combinations produce valid syllables" {
    // Property: Any valid (initial, medial, final) combination should compose
    // to a syllable in the valid Hangul range
    const HANGUL_BASE: u32 = 0xAC00;
    const HANGUL_END: u32 = 0xD7A3;

    // Test subset: first 5 initials, first 5 medials, first 5 finals
    for (COMPAT_INITIAL[0..5]) |initial| {
        for (COMPAT_MEDIAL[0..5]) |medial| {
            // Test with no final
            const no_final = compose(initial, medial, 0);
            try std.testing.expect(no_final != null);
            try std.testing.expect(no_final.? >= HANGUL_BASE and no_final.? <= HANGUL_END);

            // Test with finals
            for (COMPAT_FINAL[1..5]) |final| {
                const with_final = compose(initial, medial, final);
                try std.testing.expect(with_final != null);
                try std.testing.expect(with_final.? >= HANGUL_BASE and with_final.? <= HANGUL_END);
            }
        }
    }
}
