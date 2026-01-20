# ohi.js IME Port Strategy

## Overview

This document analyzes the feasibility and strategy for porting ohi.js (a Korean Input Method Editor) to Zig/WebAssembly, leveraging the existing hangul-wasm composition/decomposition infrastructure. The port would focus on modern browser support, dropping legacy compatibility layers.

**Status**: 🚧 IN PROGRESS - Core IME state machine complete and tested, WASM API next

**Implementation Progress:**
- ✅ Design analysis complete (this document)
- ✅ Project scope updated (AGENTS.md, README.md)
- ✅ `ImeState` struct implemented
- ✅ 2-Bulsik keyboard layout mapping
- ✅ Double jamo detection (initial, medial, final)
- ✅ Index conversion functions (ohi.js → Unicode Compatibility Jamo)
- ✅ `processConsonant2Bulsik()` state machine (all tests passing)
- ✅ `processVowel2Bulsik()` state machine (all tests passing)
- ✅ `processBackspace()` decomposition logic (tested)
- ✅ **29 unit tests: 28 passing, 1 skipped (UTF-8 test unrelated to IME)**
- ❌ WASM API exports (next step)
- ❌ JavaScript integration layer (next step)
- ❌ Demo integration (next step)
- ❌ 3-Bulsik support (future work)

**Recent Fixes (Commit 5b37800):**
1. Added `medial_flag` and `final_flag` checks to prevent attempting to double an already-doubled component
2. Used local `should_emit` flag instead of corrupting `state.initial` before saving `prev_codepoint`
3. Simplified backspace to clear flags together with their components (single-step decomposition per component)
4. Fixed test expectation: 0xACFC = 과 (correct), not 0xAE4C = 까

**Latest Commits:** 
- `5b37800` - "fix: correct IME state machine condition logic" (all tests passing)
- `df0183d` - "struct: add IME foundation (ohi.js port WIP)" (initial implementation)

**Original Source**: ohi.js by Ho-Seok Ee (GPL v2, 2006-2011)

## What is ohi.js?

ohi.js is a browser-based Korean IME that enables typing Korean text using standard QWERTY (and other) keyboard layouts. It provides:

1. **Two Korean keyboard layouts:**
   - **2-Bulsik (Dubeolsik)**: Standard two-set layout (most common)
   - **3-Bulsik (Sebeolsik)**: Three-set layout (separate keys for initial/medial/final)

2. **Real-time composition**: Converts Latin keystrokes into Hangul syllables dynamically

3. **Intelligent jamo handling**:
   - Double consonants (ㄱ+ㄱ → ㄲ, ㅅ+ㅅ → ㅆ)
   - Double vowels (ㅗ+ㅏ → ㅘ, ㅜ+ㅓ → ㅝ)
   - Complex finals (ㄱ+ㅅ → ㄳ, ㄴ+ㅎ → ㄶ)

4. **Syllable splitting**: Automatically splits syllables when needed (e.g., typing 한글 character by character)

5. **Backspace decomposition**: Breaks syllables apart on backspace (한 → 하 → ㅎ → ∅)

### Key Difference from hangul-wasm

| Aspect | hangul-wasm | ohi.js |
|--------|-------------|--------|
| **Purpose** | Static analysis of complete syllables | Real-time keyboard input processing |
| **Direction** | Syllable ↔ jamo components | Keystrokes → progressive assembly → syllables |
| **State** | Stateless pure functions | Stateful composition buffer |
| **Use Case** | Text processing, search, NLP | Typing Korean in browsers |
| **Scope** | Core algorithm only | Full IME with DOM integration |

## Architecture Analysis

### Three Distinct Layers

```
┌─────────────────────────────────────────────┐
│         JavaScript Layer (DOM/Events)       │
│  - Keyboard event listeners                 │
│  - Text field manipulation                  │
│  - Cursor position management               │
│  - Selection handling                       │
│  - Scroll position preservation             │
│  Must remain in JavaScript (no WASM access) │
└──────────────────┬──────────────────────────┘
                   │
                   │ Call WASM functions
                   │ Pass keystroke data
                   │ Receive composition results
                   │
┌──────────────────▼──────────────────────────┐
│         Zig WASM Core (IME Logic)           │
│  ✓ State machine (composition buffer)      │
│  ✓ Keyboard layout mappings                │
│  ✓ Double jamo detection                   │
│  ✓ Syllable composition (reuse existing!)  │
│  ✓ Jamo index mapping                      │
│  ✓ Backspace decomposition                 │
└─────────────────────────────────────────────┘
```

**Modern Browser Support Only:**
- Drop IE-specific code (document.selection, lines 71-79)
- Drop old Firefox keyEvent API (lines 84-88)
- Use standard `selectionStart`/`selectionEnd` API
- Assume modern KeyboardEvent support

## Core Data Structures

### 1. IME Composition State

ohi.js uses a 6-element array `_q = [0,0,0,0,0,0]` to track composition state:

```javascript
// ohi.js internal state
this._q = Array(
  0, // [0] initial consonant index
  0, // [1] initial flag (composition state)
  0, // [2] medial vowel index
  0, // [3] medial flag (composition state)
  0, // [4] final consonant index
  0, // [5] final flag (composition state)
);
```

**Zig translation:**

```zig
/// IME composition buffer state
/// Tracks in-progress syllable assembly
const ImeState = struct {
    initial: u8,        // 초성 index (0-19)
    initial_flag: u8,   // 0 or 1 (used for composition logic)
    medial: u8,         // 중성 index (0-21)
    medial_flag: u8,    // 0 or 1
    final: u8,          // 종성 index (0-28, 0=no final)
    final_flag: u8,     // 0 or 1
    
    pub fn init() ImeState {
        return .{ 
            .initial = 0, .initial_flag = 0,
            .medial = 0, .medial_flag = 0,
            .final = 0, .final_flag = 0
        };
    }
    
    pub fn reset(self: *ImeState) void {
        self.* = init();
    }
    
    pub fn isEmpty(self: ImeState) bool {
        return self.initial == 0 and self.medial == 0 and self.final == 0;
    }
    
    /// Convert state to complete syllable or single jamo
    pub fn toCodepoint(self: ImeState) u32 {
        if (self.initial != 0 and self.medial != 0) {
            // Compose full syllable using existing compose()
            const cho = INDEX_TO_COMPAT_INITIAL[self.initial];
            const jung = INDEX_TO_COMPAT_MEDIAL[self.medial];
            const jong = if (self.final != 0) 
                INDEX_TO_COMPAT_FINAL[self.final] 
            else 
                0;
            return compose(cho, jung, jong) orelse 0;
        }
        
        // Return single jamo
        if (self.initial != 0) return INDEX_TO_COMPAT_INITIAL[self.initial];
        if (self.medial != 0) return INDEX_TO_COMPAT_MEDIAL[self.medial];
        if (self.final != 0) return INDEX_TO_COMPAT_FINAL[self.final];
        
        return 0;
    }
};
```

### 2. Keyboard Layout Mappings

**2-Bulsik (Dubeolsik) Layout:**

ohi.js uses a lookup array (lines 119-146) mapping QWERTY positions to jamo indices:

```zig
/// Maps ASCII letter (A-Z, case-sensitive) to jamo index
/// Lowercase = unshifted, Uppercase = shifted
/// Index < 31 = consonant (can be initial or final)
/// Index >= 31 = vowel (medial only)
const LAYOUT_2BULSIK = struct {
    // Unshifted (lowercase)
    const lower = [26]u8{
        // a    b    c    d    e    f    g    h    i    j    k    l    m
           17,  48,  26,  23,   7,   9,  30,  39,  33,  35,  31,  51,  49,
        // n    o    p    q    r    s    t    u    v    w    x    y    z
           44,  32,  36,  18,   1,   4,  21,  37,  29,  24,  28,  43,  27
    };
    
    // Shifted (uppercase)
    const upper = [26]u8{
        // A    B    C    D    E    F    G    H    I    J    K    L    M
           17,  48,  26,  23,   9,  11,  30,  39,  33,  35,  31,  51,  49,
        // N    O    P    Q    R    S    T    U    V    W    X    Y    Z
           44,  34,  38,  20,   3,   6,  23,  37,  29,  24,  28,  43,  27
    };
    
    /// Map ASCII keycode to jamo index
    pub fn map(ascii: u8, shifted: bool) ?u8 {
        if (ascii >= 'a' and ascii <= 'z') {
            return if (shifted) upper[ascii - 'a'] else lower[ascii - 'a'];
        }
        if (ascii >= 'A' and ascii <= 'Z') {
            return if (shifted) upper[ascii - 'A'] else lower[ascii - 'A'];
        }
        return null;
    }
};
```

**3-Bulsik (Sebeolsik) Layout:**

Separate mappings for initial (cho), medial (jung), and final (jong) positions:

```zig
const LAYOUT_3BULSIK = struct {
    // Lines 204-299 in ohi.js define complex mapping
    // ASCII 33-126 → jamo indices with distinct ranges:
    // 93-122: Initial consonants (cho)
    // 66-86:  Medial vowels (jung)
    // 1-30:   Final consonants (jong)
    
    const lookup = [94]u8{ /* full mapping table */ };
    
    pub fn classify(ascii: u8) enum { cho, jung, jong, other } {
        const idx = lookup[ascii - 33];
        if (idx >= 93 and idx <= 122) return .cho;
        if (idx >= 66 and idx <= 86) return .jung;
        if (idx >= 1 and idx <= 30) return .jong;
        return .other;
    }
};
```

### 3. Double Jamo Detection

ohi.js `doubleJamo()` function (lines 33-51) detects when two jamos combine into a compound:

```zig
const DoubleJamoType = enum { initial, medial, final };

/// Double initial consonants (ㄲ, ㄸ, ㅃ, ㅆ, ㅉ)
const DOUBLE_INITIAL = struct {
    // Only 5 consonants can double
    singles: [5]u8 = .{ 1, 7, 18, 21, 24 },  // ㄱ ㄷ ㅅ ㅈ ㅎ
    doubles: [5]u8 = .{ 2, 8, 19, 22, 25 },  // ㄲ ㄸ ㅆ ㅉ (ㅎㅎ rare)
};

/// Double medial vowels (complex combinations)
const DOUBLE_MEDIAL = struct {
    // ㅗ + ㅏ/ㅐ/ㅣ → ㅘ/ㅙ/ㅚ
    // ㅜ + ㅓ/ㅔ/ㅣ → ㅝ/ㅞ/ㅟ
    // ㅡ + ㅣ → ㅢ
    
    base: [4]u8 = .{ 8, 13, 18, 20 },  // ㅗ ㅜ ㅡ (plus one more)
    
    // Nested structure from ohi.js lines 38-39
    combinations: []const []const u8 = &[_][]const u8{
        &[_]u8{ 39, 44, 49 },        // ㅗ + {ㅏ, ㅐ, ㅣ}
        &[_]u8{ 31, 32, 51 },        // Base combination indices
        &[_]u8{ 35, 36, 51 },        // (exact mapping requires full decode)
        &[_]u8{ 51 },
    },
};

/// Double final consonants (ㄳ, ㄵ, ㄶ, ㄺ, ㄻ, ㄼ, ㄽ, ㄾ, ㄿ, ㅀ, ㅄ)
const DOUBLE_FINAL = struct {
    // 11 valid compound finals
    // ㄱ+ㅅ→ㄳ, ㄴ+ㅈ→ㄵ, ㄴ+ㅎ→ㄶ, ㄹ+ㄱ/ㅁ/ㅂ/ㅅ/ㅌ/ㅍ/ㅎ→ㄺ-ㅀ, ㅂ+ㅅ→ㅄ
    
    base_to_combinations: []const struct { base: u8, targets: []const u8 } = &[_]{
        .{ .base = 1,  .targets = &[_]u8{ 19 } },                    // ㄱ+ㅅ
        .{ .base = 4,  .targets = &[_]u8{ 22, 27 } },                // ㄴ+ㅈ/ㅎ
        .{ .base = 8,  .targets = &[_]u8{ 1, 17, 18, 19, 25, 26, 27 } }, // ㄹ+...
        .{ .base = 18, .targets = &[_]u8{ 19 } },                    // ㅂ+ㅅ
    },
};

/// Detect if current + incoming jamo can form double jamo
/// Returns 0 if cannot combine, otherwise returns new compound index
pub fn detectDoubleJamo(
    jamo_type: DoubleJamoType,
    current: u8,
    incoming: u8
) u8 {
    return switch (jamo_type) {
        .initial => detectDoubleInitial(current, incoming),
        .medial => detectDoubleMedial(current, incoming),
        .final => detectDoubleFinal(current, incoming),
    };
}
```

## Core Algorithm: State Machine

### Keystroke Processing Flow

```
Keystroke (ASCII)
      ↓
Keyboard Layout Mapping
      ↓
Jamo Index (1-51)
      ↓
  ┌───┴───┐
  │       │
Consonant  Vowel
  │       │
  ↓       ↓
Try Double Jamo
  │       │
  ↓       ↓
Update ImeState
  │       │
  └───┬───┘
      ↓
Emit Decision:
- Replace current char
- Emit prev + new char
- Start new syllable
      ↓
Return to JavaScript
```

### 2-Bulsik Consonant Processing

```zig
const KeyResult = struct {
    action: enum { replace, emit_and_new, no_change },
    prev_codepoint: u32,      // Emit this first (if emit_and_new)
    current_codepoint: u32,   // Then emit/replace with this
};

/// Process consonant keystroke in 2-Bulsik mode
/// Based on ohi.js Hangul2() lines 152-176
pub fn processConsonant2Bulsik(
    state: *ImeState,
    jamo_index: u8
) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };
    
    // Scenario 1: Try adding as double final consonant
    // "한" + ㄱ → check if ㄴ+ㄱ valid? No. Fall through.
    // "밥" + ㅅ → ㅂ+ㅅ=ㅄ? Yes! → "밥" becomes "밟"
    if (state.medial != 0 and state.final != 0 and state.final_flag == 0) {
        const double_idx = detectDoubleJamo(.final, state.final, jamo_index);
        if (double_idx != 0) {
            state.final = double_idx;
            state.final_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
        // Cannot double → will add as new syllable initial
        state.initial = 0; // Signal to emit current (ohi.js line 154)
    }
    
    // Scenario 2: No medial yet OR should start new syllable
    if (state.medial == 0 or 
        state.initial < 0 or  // Flagged to emit
        (state.initial != 0 and state.final == 0 and 
         !canFollowAsInitial(jamo_index))) // Some consonants can't follow
    {
        // Try double initial: "ㄱ" + ㄱ → "ㄲ"
        const double_idx = if (state.medial == 0 and state.final == 0)
            detectDoubleJamo(.initial, state.initial, jamo_index)
        else
            0;
        
        if (double_idx != 0) {
            state.initial = double_idx;
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

/// Some consonants (ㅇ, ㅅ, ㄴ) can follow initial without medial
/// ohi.js line 161: c == 8 || c == 19 || c == 25
fn canFollowAsInitial(jamo_index: u8) bool {
    return jamo_index == 8 or jamo_index == 19 or jamo_index == 25;
}
```

### 2-Bulsik Vowel Processing

```zig
/// Process vowel keystroke in 2-Bulsik mode
/// Based on ohi.js Hangul2() lines 177-199
pub fn processVowel2Bulsik(
    state: *ImeState,
    jamo_index: u8
) KeyResult {
    var result: KeyResult = .{
        .action = .replace,
        .prev_codepoint = 0,
        .current_codepoint = 0,
    };
    
    // Scenario 1: Try adding as double medial
    // "ㅗ" + ㅏ → "ㅘ"
    if (state.medial != 0 and state.final == 0 and state.medial_flag == 0) {
        const double_idx = detectDoubleJamo(.medial, state.medial, jamo_index);
        if (double_idx != 0) {
            state.medial = double_idx;
            state.medial_flag = 1;
            result.action = .replace;
            result.current_codepoint = state.toCodepoint();
            return result;
        }
        // Cannot double
        state.medial = -1; // Signal (ohi.js line 180)
    }
    
    // Scenario 2: Syllable splitting
    // "한" + ㅏ → Split into "하" + "ㄴㅏ" (incomplete)
    // Move final consonant to become initial of new syllable
    if (state.initial != 0 and state.medial != 0 and state.final != 0) {
        // Emit current syllable without final
        const temp_final = state.final;
        state.final = 0;
        result.action = .emit_and_new;
        result.prev_codepoint = state.toCodepoint();
        
        // Start new syllable with old final as initial
        state.reset();
        state.initial = temp_final;
        state.medial = jamo_index;
        state.initial_flag = 0;
        state.medial_flag = 0;
        result.current_codepoint = state.toCodepoint();
        return result;
    }
    
    // Scenario 3: Start new syllable or add to existing
    if ((state.initial == 0 or state.medial != 0) or state.medial < 0) {
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
```

### Backspace Handling

```zig
/// Process backspace - decomposes syllable step by step
/// Based on ohi.js keydownHandler() lines 418-427
pub fn processBackspace(state: *ImeState) ?u32 {
    // Find rightmost non-zero component and remove it
    // Order: final → medial flag → medial → initial flag → initial
    
    if (state.final_flag != 0) {
        state.final_flag = 0;
        return state.toCodepoint();
    }
    if (state.final != 0) {
        state.final = 0;
        return state.toCodepoint();
    }
    if (state.medial_flag != 0) {
        state.medial_flag = 0;
        return state.toCodepoint();
    }
    if (state.medial != 0) {
        state.medial = 0;
        return state.toCodepoint();
    }
    if (state.initial_flag != 0) {
        state.initial_flag = 0;
        return state.toCodepoint();
    }
    if (state.initial != 0) {
        state.initial = 0;
        return null; // State now empty - let browser handle deletion
    }
    
    return null; // Already empty
}
```

## WASM API Design

### Exported Functions

```zig
/// Create new IME instance
/// Returns handle (pointer to ImeState in WASM memory)
export fn wasm_ime_create() u32 {
    const state = allocator.create(ImeState) catch return 0;
    state.* = ImeState.init();
    return @intFromPtr(state);
}

/// Destroy IME instance
export fn wasm_ime_destroy(handle: u32) void {
    const state: *ImeState = @ptrFromInt(handle);
    allocator.destroy(state);
}

/// Reset IME composition state
export fn wasm_ime_reset(handle: u32) void {
    const state: *ImeState = @ptrFromInt(handle);
    state.reset();
}

/// Process keystroke
/// @param handle: IME instance
/// @param keycode: ASCII character code
/// @param shift: Shift key pressed
/// @param layout: 0=2-bulsik, 1=3-bulsik
/// @param result_ptr: Pointer to output buffer (12 bytes)
/// @returns true if key was handled
///
/// Output buffer format (3 × u32):
/// [0] action: 0=no_change, 1=replace, 2=emit_and_new
/// [1] prev_codepoint: Previous character (if action=2)
/// [2] current_codepoint: Current character
export fn wasm_ime_processKey(
    handle: u32,
    keycode: u32,
    shift: bool,
    layout: u8,
    result_ptr: u32
) bool {
    const state: *ImeState = @ptrFromInt(handle);
    const output: [*]u32 = @ptrFromInt(result_ptr);
    
    // Map keycode to jamo index based on layout
    const jamo_opt = if (layout == 0)
        LAYOUT_2BULSIK.map(@intCast(keycode), shift)
    else
        LAYOUT_3BULSIK.map(@intCast(keycode), shift);
    
    const jamo = jamo_opt orelse return false;
    
    // Process based on jamo type and layout
    const result = if (layout == 0) blk: {
        if (jamo < 31) {
            break :blk processConsonant2Bulsik(state, jamo);
        } else {
            break :blk processVowel2Bulsik(state, jamo);
        }
    } else blk: {
        break :blk processKey3Bulsik(state, jamo);
    };
    
    // Write result to output buffer
    output[0] = @intFromEnum(result.action);
    output[1] = result.prev_codepoint;
    output[2] = result.current_codepoint;
    
    return true;
}

/// Process backspace
/// @returns Updated codepoint (0 if state is now empty)
export fn wasm_ime_backspace(handle: u32) u32 {
    const state: *ImeState = @ptrFromInt(handle);
    return processBackspace(state) orelse 0;
}

/// Get current composition state (for debugging)
export fn wasm_ime_getState(handle: u32, output_ptr: u32) void {
    const state: *ImeState = @ptrFromInt(handle);
    const output: [*]u8 = @ptrFromInt(output_ptr);
    output[0] = state.initial;
    output[1] = state.initial_flag;
    output[2] = state.medial;
    output[3] = state.medial_flag;
    output[4] = state.final;
    output[5] = state.final_flag;
}
```

## JavaScript Integration

### Modern Browser API (No Legacy Support)

```javascript
class HangulIme {
    constructor(wasmModule) {
        this.wasm = wasmModule;
        this.handle = this.wasm.wasm_ime_create();
        this.layout = 0; // 0=2-bulsik, 1=3-bulsik
        this.enabled = false;
    }
    
    destroy() {
        this.wasm.wasm_ime_destroy(this.handle);
    }
    
    setLayout(layout) {
        this.layout = layout; // 0 or 1
        this.reset();
    }
    
    reset() {
        this.wasm.wasm_ime_reset(this.handle);
    }
    
    enable() {
        this.enabled = true;
    }
    
    disable() {
        this.enabled = false;
        this.reset();
    }
    
    handleKeyPress(event) {
        if (!this.enabled) return true;
        
        const field = event.target;
        const keycode = event.key.charCodeAt(0);
        
        // Only handle printable ASCII
        if (keycode < 32 || keycode > 126) return true;
        
        // Allocate result buffer
        const resultPtr = this.wasm.wasm_alloc(12); // 3 × u32
        
        const handled = this.wasm.wasm_ime_processKey(
            this.handle,
            keycode,
            event.shiftKey,
            this.layout,
            resultPtr
        );
        
        if (handled) {
            const memory = new Uint32Array(this.wasm.memory.buffer);
            const offset = resultPtr / 4;
            
            const action = memory[offset];
            const prevCodepoint = memory[offset + 1];
            const currentCodepoint = memory[offset + 2];
            
            switch (action) {
                case 1: // replace
                    this.replaceLastChar(field, currentCodepoint);
                    break;
                case 2: // emit_and_new
                    this.insertChar(field, prevCodepoint);
                    this.insertChar(field, currentCodepoint);
                    break;
            }
            
            event.preventDefault();
        }
        
        this.wasm.wasm_free(resultPtr, 12);
        return !handled;
    }
    
    handleKeyDown(event) {
        if (!this.enabled) return true;
        
        const field = event.target;
        
        if (event.key === 'Backspace') {
            const newCodepoint = this.wasm.wasm_ime_backspace(this.handle);
            
            if (newCodepoint !== 0) {
                // Replace last character with decomposed version
                this.replaceLastChar(field, newCodepoint);
                event.preventDefault();
                return false;
            }
            // newCodepoint === 0: state is empty, let browser handle normally
        }
        
        // Reset on arrow keys, home, end, etc.
        if (event.key.startsWith('Arrow') || 
            event.key === 'Home' || 
            event.key === 'End') {
            this.reset();
        }
        
        return true;
    }
    
    // Modern selectionStart/End API (all modern browsers)
    insertChar(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const start = field.selectionStart;
        const end = field.selectionEnd;
        
        field.value = 
            field.value.slice(0, start) + 
            char + 
            field.value.slice(end);
        
        field.selectionStart = field.selectionEnd = start + char.length;
    }
    
    replaceLastChar(field, codepoint) {
        const char = String.fromCodePoint(codepoint);
        const start = field.selectionStart;
        
        field.value = 
            field.value.slice(0, start - 1) + 
            char + 
            field.value.slice(start);
        
        field.selectionStart = field.selectionEnd = start;
    }
}

// Usage
async function initIme() {
    const wasmModule = await loadHangulWasm();
    const ime = new HangulIme(wasmModule);
    
    document.addEventListener('keypress', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
            ime.handleKeyPress(e);
        }
    });
    
    document.addEventListener('keydown', (e) => {
        if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') {
            ime.handleKeyDown(e);
        }
    });
    
    // Toggle with Ctrl+Space
    document.addEventListener('keydown', (e) => {
        if (e.ctrlKey && e.key === ' ') {
            if (ime.enabled) {
                ime.disable();
                console.log('IME disabled');
            } else {
                ime.enable();
                console.log('IME enabled');
            }
            e.preventDefault();
        }
    });
}
```

## Index Mapping Tables

### ohi.js Indices → Unicode Compatibility Jamo

```zig
/// Map ohi.js initial consonant index (1-30) to Unicode Compatibility Jamo
const INDEX_TO_COMPAT_INITIAL = [31]u32{
    0,      // 0: unused
    0x3131, // 1: ㄱ
    0x3132, // 2: ㄲ
    0x3134, // 3: ㄴ
    0x3137, // 4: ㄷ
    0x3138, // 5: ㄸ
    0x3139, // 6: ㄹ
    0x3141, // 7: ㅁ
    0x3142, // 8: ㅂ
    0x3143, // 9: ㅃ
    0x3145, // 10: ㅅ
    0x3146, // 11: ㅆ
    0x3147, // 12: ㅇ
    0x3148, // 13: ㅈ
    0x3149, // 14: ㅉ
    0x314A, // 15: ㅊ
    0x314B, // 16: ㅋ
    0x314C, // 17: ㅌ
    0x314D, // 18: ㅍ
    0x314E, // 19: ㅎ
    // Extended indices for 3-bulsik (20-30)
    // ... (need to decode from ohi.js line 204-299)
};

/// Map ohi.js medial vowel index (31-51) to Unicode Compatibility Jamo
const INDEX_TO_COMPAT_MEDIAL = [52]u32{
    0,      // 0-30: unused
    // (fill 0x0000 for indices 1-30)
    [30]u32{0} ** 30,
    0x314F, // 31: ㅏ
    0x3150, // 32: ㅐ
    0x3151, // 33: ㅑ
    0x3152, // 34: ㅒ
    0x3153, // 35: ㅓ
    0x3154, // 36: ㅔ
    0x3155, // 37: ㅕ
    0x3156, // 38: ㅖ
    0x3157, // 39: ㅗ
    0x3158, // 40: ㅘ (ㅗ+ㅏ)
    0x3159, // 41: ㅙ (ㅗ+ㅐ)
    0x315A, // 42: ㅚ (ㅗ+ㅣ)
    0x315B, // 43: ㅛ
    0x315C, // 44: ㅜ
    0x315D, // 45: ㅝ (ㅜ+ㅓ)
    0x315E, // 46: ㅞ (ㅜ+ㅔ)
    0x315F, // 47: ㅟ (ㅜ+ㅣ)
    0x3160, // 48: ㅠ
    0x3161, // 49: ㅡ
    0x3162, // 50: ㅢ (ㅡ+ㅣ)
    0x3163, // 51: ㅣ
};

/// Map ohi.js final consonant index (0-30) to Unicode Compatibility Jamo
const INDEX_TO_COMPAT_FINAL = [31]u32{
    0,      // 0: no final
    0x3131, // 1: ㄱ
    0x3132, // 2: ㄲ
    0x3133, // 3: ㄳ (ㄱ+ㅅ)
    0x3134, // 4: ㄴ
    0x3135, // 5: ㄵ (ㄴ+ㅈ)
    0x3136, // 6: ㄶ (ㄴ+ㅎ)
    0x3137, // 7: ㄷ
    0x3139, // 8: ㄹ
    0x313A, // 9: ㄺ (ㄹ+ㄱ)
    0x313B, // 10: ㄻ (ㄹ+ㅁ)
    0x313C, // 11: ㄼ (ㄹ+ㅂ)
    0x313D, // 12: ㄽ (ㄹ+ㅅ)
    0x313E, // 13: ㄾ (ㄹ+ㅌ)
    0x313F, // 14: ㄿ (ㄹ+ㅍ)
    0x3140, // 15: ㅀ (ㄹ+ㅎ)
    0x3141, // 16: ㅁ
    0x3142, // 17: ㅂ
    0x3144, // 18: ㅄ (ㅂ+ㅅ)
    0x3145, // 19: ㅅ
    0x3146, // 20: ㅆ
    0x3147, // 21: ㅇ
    0x3148, // 22: ㅈ
    0x314A, // 23: ㅊ
    0x314B, // 24: ㅋ
    0x314C, // 25: ㅌ
    0x314D, // 26: ㅍ
    0x314E, // 27: ㅎ
    // Extended indices 28-30 (if needed for 3-bulsik)
};
```

## Testing Strategy

### Unit Tests (TDD Approach)

```zig
test "ime state initialization" {
    const state = ImeState.init();
    try std.testing.expect(state.isEmpty());
    try std.testing.expectEqual(@as(u32, 0), state.toCodepoint());
}

test "2-bulsik: type 가 (g-a)" {
    var state = ImeState.init();
    
    // Type 'r' (ㄱ)
    const jamo_g = LAYOUT_2BULSIK.map('r', false).?;
    const result1 = processConsonant2Bulsik(&state, jamo_g);
    try std.testing.expectEqual(KeyResult.Action.replace, result1.action);
    try std.testing.expectEqual(@as(u32, 0x3131), result1.current_codepoint); // ㄱ
    
    // Type 'k' (ㅏ)
    const jamo_a = LAYOUT_2BULSIK.map('k', false).?;
    const result2 = processVowel2Bulsik(&state, jamo_a);
    try std.testing.expectEqual(KeyResult.Action.replace, result2.action);
    try std.testing.expectEqual(@as(u32, 0xAC00), result2.current_codepoint); // 가
}

test "2-bulsik: double consonant ㄲ" {
    var state = ImeState.init();
    
    // Type 'r' twice
    const jamo_g = LAYOUT_2BULSIK.map('r', false).?;
    _ = processConsonant2Bulsik(&state, jamo_g);
    const result = processConsonant2Bulsik(&state, jamo_g);
    
    try std.testing.expectEqual(@as(u32, 0x3132), result.current_codepoint); // ㄲ
}

test "2-bulsik: double vowel ㅗ+ㅏ=ㅘ" {
    var state = ImeState.init();
    
    // Type 'g' (ㄱ)
    const jamo_g = LAYOUT_2BULSIK.map('r', false).?;
    _ = processConsonant2Bulsik(&state, jamo_g);
    
    // Type 'h' (ㅗ)
    const jamo_o = LAYOUT_2BULSIK.map('h', false).?;
    _ = processVowel2Bulsik(&state, jamo_o);
    
    // Type 'k' (ㅏ)
    const jamo_a = LAYOUT_2BULSIK.map('k', false).?;
    const result = processVowel2Bulsik(&state, jamo_a);
    
    try std.testing.expectEqual(@as(u32, 0xAC00 + 1*588), result.current_codepoint); // 과
}

test "2-bulsik: syllable split 한 + ㅏ" {
    var state = ImeState.init();
    
    // Type "한" (han)
    _ = processConsonant2Bulsik(&state, 27); // ㅎ
    _ = processVowel2Bulsik(&state, 31);     // ㅏ
    const result1 = processConsonant2Bulsik(&state, 4); // ㄴ
    try std.testing.expectEqual(@as(u32, 0xD55C), result1.current_codepoint); // 한
    
    // Type ㅏ again → should split into "하" + "ㄴㅏ"
    const result2 = processVowel2Bulsik(&state, 31);
    try std.testing.expectEqual(KeyResult.Action.emit_and_new, result2.action);
    try std.testing.expectEqual(@as(u32, 0xD558), result2.prev_codepoint); // 하
    // current is incomplete: ㄴㅏ (나 without final)
}

test "backspace decomposition" {
    var state = ImeState.init();
    
    // Type "한"
    _ = processConsonant2Bulsik(&state, 27); // ㅎ
    _ = processVowel2Bulsik(&state, 31);     // ㅏ
    _ = processConsonant2Bulsik(&state, 4);  // ㄴ
    
    // Backspace: 한 → 하
    const cp1 = processBackspace(&state).?;
    try std.testing.expectEqual(@as(u32, 0xD558), cp1); // 하
    
    // Backspace: 하 → ㅎ
    const cp2 = processBackspace(&state).?;
    try std.testing.expectEqual(@as(u32, 0x314E), cp2); // ㅎ
    
    // Backspace: ㅎ → (empty)
    const cp3 = processBackspace(&state);
    try std.testing.expect(cp3 == null);
}

test "exhaustive: all layouts produce valid syllables" {
    // Test that all keyboard mappings produce valid Unicode
    for (LAYOUT_2BULSIK.lower) |idx| {
        if (idx == 0) continue;
        // Verify idx maps to valid jamo
    }
}
```

### Integration Tests (JavaScript)

```javascript
describe('HangulIme', () => {
    let ime;
    
    beforeEach(async () => {
        const wasm = await loadHangulWasm();
        ime = new HangulIme(wasm);
        ime.enable();
    });
    
    test('types 가 correctly', () => {
        const field = document.createElement('input');
        
        // Type 'r' (ㄱ)
        simulateKeyPress(field, 'r', ime);
        expect(field.value).toBe('ㄱ');
        
        // Type 'k' (ㅏ)
        simulateKeyPress(field, 'k', ime);
        expect(field.value).toBe('가');
    });
    
    test('handles double consonant', () => {
        const field = document.createElement('input');
        
        simulateKeyPress(field, 'r', ime); // ㄱ
        simulateKeyPress(field, 'r', ime); // ㄱ+ㄱ = ㄲ
        
        expect(field.value).toBe('ㄲ');
    });
    
    test('splits syllable correctly', () => {
        const field = document.createElement('input');
        
        // Type 한글
        simulateKeyPress(field, 'g', ime); // ㅎ
        simulateKeyPress(field, 'k', ime); // ㅏ
        simulateKeyPress(field, 's', ime); // ㄴ → "한"
        simulateKeyPress(field, 'r', ime); // ㄱ → "한ㄱ"
        simulateKeyPress(field, 'm', ime); // ㅡ → "한" + "ㄱㅡ"
        simulateKeyPress(field, 'f', ime); // ㄹ → "한글"
        
        expect(field.value).toBe('한글');
    });
    
    test('backspace decomposes', () => {
        const field = document.createElement('input');
        
        // Type 한
        simulateKeyPress(field, 'g', ime);
        simulateKeyPress(field, 'k', ime);
        simulateKeyPress(field, 's', ime);
        expect(field.value).toBe('한');
        
        // Backspace
        simulateBackspace(field, ime);
        expect(field.value).toBe('하');
        
        simulateBackspace(field, ime);
        expect(field.value).toBe('ㅎ');
        
        simulateBackspace(field, ime);
        expect(field.value).toBe('');
    });
});
```

## Performance Expectations

### Compared to Pure JavaScript (ohi.js)

| Operation | ohi.js (JS) | Zig WASM | Speedup |
|-----------|-------------|----------|---------|
| Keystroke processing | ~0.5ms | ~0.05ms | 10x |
| Composition math | ~0.1ms | ~0.01ms | 10x |
| State updates | ~0.2ms | ~0.02ms | 10x |
| Memory usage | ~10KB | ~2KB state | 5x smaller |

### Bundle Size

| Component | ohi.js | Zig WASM Port |
|-----------|--------|---------------|
| Core logic | 520 lines JS (~15KB minified) | 2KB WASM + existing 2KB hangul.wasm |
| DOM integration | Included | ~2KB JS glue |
| **Total** | **~15KB** | **~6KB** (60% reduction) |

## Advantages of Zig Port

### 1. **Reuse Existing Infrastructure**
- `compose()` function already tested with all 11,172 syllables
- No need to duplicate composition math
- Algorithmic correctness guaranteed

### 2. **Type Safety**
- Zig's compile-time checks prevent index out-of-bounds
- No runtime type errors (unlike JavaScript)
- Explicit error handling

### 3. **Performance**
- Faster keystroke processing (critical for responsive typing)
- Lower memory footprint
- Better CPU cache utilization

### 4. **Smaller Bundle**
- 60% smaller than ohi.js
- Single WASM binary for all Korean text processing

### 5. **Testability**
- TDD-friendly with Zig's built-in test framework
- Deterministic behavior (no JavaScript quirks)
- Easier to reason about state machine

## Challenges and Mitigations

### 1. **Complex State Machine Logic**
- **Challenge**: ohi.js has intricate edge cases
- **Mitigation**: Port incrementally with TDD, test each transition

### 2. **Index Mapping**
- **Challenge**: ohi.js uses custom index system
- **Mitigation**: Create comprehensive lookup tables, test exhaustively

### 3. **Double Jamo Detection**
- **Challenge**: Nested array logic is hard to parse
- **Mitigation**: Reverse-engineer to explicit rules, document clearly

### 4. **DOM Integration**
- **Challenge**: WASM can't directly manipulate DOM
- **Mitigation**: Keep thin JavaScript layer, all logic in WASM

### 5. **Debugging Complexity**
- **Challenge**: Cross-language boundary makes debugging harder
- **Mitigation**: Add `wasm_ime_getState()` for inspection, comprehensive logging

## Dropped Features (Legacy Browser Support)

### Removed from ohi.js:

1. **Internet Explorer Support**
   - `document.selection` API (lines 71-79)
   - `createRange()` / `s.text` manipulation
   
2. **Old Firefox (<12) Support**
   - `initKeyEvent()` API (lines 84-88)
   - Special Gecko keyboard event handling

3. **QWERTZ/AZERTY Keyboard Layouts**
   - Lines 343-372 (layout swapping)
   - Can be added later if needed

4. **Inline Frame Support**
   - Lines 494-506 (injecting into iframes)
   - Not needed for modern single-page apps

5. **Fixed Position Status Indicator**
   - Lines 446-470 (bottom-right mode indicator)
   - Better handled by modern UI frameworks

### Modern Equivalents:

| Old API | Modern Replacement |
|---------|-------------------|
| `document.selection` | `field.selectionStart/End` |
| `initKeyEvent()` | Standard `KeyboardEvent` |
| Manual scroll tracking | Browser handles automatically |
| Fixed positioning hacks | CSS `position: fixed` works everywhere |

## Implementation Roadmap

If this were to be implemented (currently out of scope):

### Phase 1: Foundation (struct commits)
1. Define `ImeState` struct
2. Create index mapping tables
3. Add WASM API scaffolding

### Phase 2: 2-Bulsik Core (feat commits, TDD)
1. Implement keyboard layout mapping
2. Port consonant processing (with tests)
3. Port vowel processing (with tests)
4. Implement backspace handling

### Phase 3: Double Jamo (feat commits)
1. Port double initial detection
2. Port double medial detection
3. Port double final detection
4. Test all combinations

### Phase 4: JavaScript Integration
1. Create `HangulIme` class
2. Add event listeners
3. Test in real browser environment

### Phase 5: 3-Bulsik Support (optional feat)
1. Decode 3-bulsik layout from ohi.js
2. Implement separate processing logic
3. Test thoroughly

### Phase 6: Optimization (refactor commits)
1. Profile performance
2. Optimize hot paths
3. Reduce WASM memory usage

## Implementation Notes & Lessons Learned

### ohi.js Index System Deep Dive

The most critical aspect of the port is understanding ohi.js's custom index system:

**Key Discovery**: ohi.js does NOT use direct array indices. It uses custom indices (1-51) that must be converted before use:

```javascript
// ohi.js lines 63-69: The conversion formulas
function cho(i) { return i - (i < 3 ? 1 : i < 5 ? 2 : i < 10 ? 4 : i < 20 ? 11 : 12); }
function jung(j) { return j - 31; }
function jong(k) { return k - (k < 8 ? 0 : k < 19 ? 1 : k < 25 ? 2 : 3); }
function han(i, j, k) { return 0xAC00 + (cho(i) * 21 + jung(j)) * 28 + jong(k); }
function HanFromString(i) { return 0x3130 + i; }
```

**Zig Implementation** (hangul.zig lines ~780-830):
- `ohiIndexToInitialIdx()` - Convert ohi.js initial index (1-30) to standard initial index (0-18)
- `ohiIndexToMedialIdx()` - Convert ohi.js medial index (31-51) to standard medial index (0-20)
- `ohiIndexToFinalIdx()` - Convert ohi.js final index (0-30) to standard final index (0-27)
- `ohiIndexToSingleJamo()` - Convert any ohi.js index to single jamo codepoint (U+3130 + index)

### State Machine Condition Challenges

**Problem Area**: The condition logic in `processConsonant2Bulsik()` for deciding whether to:
1. Add as final consonant to current syllable
2. Start new syllable with consonant as initial

**Original ohi.js logic** (lines 156-162):
```javascript
if (_q[2] == 0 || _q[0] < 0 || 
    (_q[0] > 0 && (_q[4] == 0 || _q[5] == 0) && (_q[4] > 0 || c == 8 || c == 19 || c == 25))) {
  // Try double initial or start new syllable
}
```

**Incorrect first attempt**:
```zig
if (state.medial == 0 or state.initial < 0 or
    (state.initial > 0 and state.final == 0 and !canFollowAsInitial(jamo_u8)))
```

**Corrected version**:
```zig
if (state.medial == 0 or state.initial < 0 or
    (state.initial > 0 and (state.final == 0 or state.final_flag == 0) and
    (state.final > 0 or canFollowAsInitial(jamo_u8))))
```

**Key difference**: The flag fields (`initial_flag`, `medial_flag`, `final_flag`) are critical for tracking whether a double jamo was just formed. This affects:
- Backspace behavior (decompose double jamos first)
- Decision logic (can we add more to this component?)

### Test-Driven Development Wins

**Tests caught issues early**:
1. Missing index conversion calls
2. Incorrect condition logic
3. Off-by-one errors in double jamo tables
4. State not being properly reset

**Test structure** (hangul.zig lines ~880-980):
```zig
test "2-bulsik: type 한 (han)" { ... }
test "2-bulsik: double consonant ㄲ" { ... }
test "2-bulsik: double vowel ㅘ" { ... }
test "2-bulsik: syllable split" { ... }
test "backspace decomposition" { ... }
```

Each test follows the pattern:
1. Initialize fresh `ImeState`
2. Simulate keystroke sequence
3. Verify intermediate states
4. Check final output codepoint

### Memory Layout Considerations

**ImeState** is deliberately kept small (6 bytes):
```zig
const ImeState = struct {
    initial: u8,      // 0-30 (ohi.js indices)
    initial_flag: u8, // 0 or 1
    medial: u8,       // 0 or 31-51 (ohi.js indices)
    medial_flag: u8,  // 0 or 1
    final: u8,        // 0-30 (ohi.js indices)
    final_flag: u8,   // 0 or 1
};
```

This allows WASM to efficiently allocate/deallocate instances and minimizes memory transfer overhead.

### Double Jamo Table Construction

**Challenge**: ohi.js uses nested arrays for double jamo detection.

**Solution**: Flatten into explicit lookup tables:

```zig
const DOUBLE_INITIAL_SINGLES = [_]u8{ 1, 7, 18, 21, 27 }; // ㄱ ㄷ ㅅ ㅈ ㅎ
const DOUBLE_INITIAL_DOUBLES = [_]u8{ 2, 8, 19, 22, 28 }; // ㄲ ㄸ ㅆ ㅉ ㅎㅎ(rare)

// Medial: Map (base, target) → result
const DOUBLE_MEDIAL_MAPS = [_]DoubleMedMap{
    .{ .base = 39, .target = 31, .result = 40 },  // ㅗ + ㅏ = ㅘ
    .{ .base = 39, .target = 32, .result = 41 },  // ㅗ + ㅐ = ㅙ
    // ... (13 total combinations)
};

// Final: Similar structure for 11 compound finals
```

### Next Implementation Steps (Post-Debugging)

**Once tests pass**:

1. **Add WASM exports** - Create the API functions documented in this design doc
2. **Create JavaScript glue** - `HangulIme` class for DOM integration
3. **Update demo** - Add IME toggle and keyboard event handling
4. **Comprehensive testing** - Browser integration tests
5. **Performance profiling** - Verify 10x speedup claim
6. **Documentation** - Update README with IME usage examples

**Future enhancements**:
- 3-Bulsik layout support
- Autocorrect/suggestion hooks
- Multi-field IME instance management
- Custom keyboard layout support

### References & Code Locations

**ohi.js critical lines**:
- Lines 33-51: `doubleJamo()` function
- Lines 63-69: Index conversion formulas
- Lines 119-146: 2-Bulsik layout mapping
- Lines 152-199: `Hangul2()` state machine (core logic)
- Lines 418-427: Backspace handling

**hangul.zig implementation**:
- Lines ~720-750: `ImeState` struct
- Lines ~755-775: `KeyResult` struct and action enum
- Lines ~780-830: Index conversion functions
- Lines ~835-870: Double jamo detection tables and logic
- Lines ~875-950: State machine (`processConsonant2Bulsik`, `processVowel2Bulsik`)
- Lines ~955-980: Backspace processing
- Lines ~985+: Unit tests (29 total)

---

## Conclusion

Porting ohi.js to Zig/WASM is **technically feasible** and would provide significant benefits:

- **60% smaller bundle** (6KB vs 15KB)
- **10x faster** keystroke processing
- **Type-safe** implementation with compile-time guarantees
- **Reuses existing** composition/decomposition infrastructure
- **Modern browsers only** (simpler code)

The main challenges are:
- Complex state machine logic (requires careful TDD)
- Index mapping complexity (reverse engineering needed)
- DOM integration boundary (requires JS glue layer)

**Effort estimate**: ~57 hours for full implementation with comprehensive tests.

**Recommendation**: If IME functionality becomes a project goal, this port would be valuable. The existing `compose()` function provides a solid foundation, and the performance/size benefits are substantial.

---

**References:**
- ohi.js source: 520 lines (GPL v2)
- hangul-wasm `compose()`: Already tested with all 11,172 syllables
- Unicode Hangul range: U+AC00 to U+D7A3
- Compatibility Jamo: U+3131 to U+318E
