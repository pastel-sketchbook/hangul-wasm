# hangul-wasm: Zig/WASM Port of hangul.js

A high-performance WebAssembly library for Korean text processing, implemented in Zig. Decomposes Hangul syllables into jamo components and composes them back with O(1) operations.

**Source Repository**: https://github.com/pastel-sketchbook/hangul-wasm

## About

This is a Zig-based implementation of Korean text processing functionality, compiled to WebAssembly for optimal performance. The original JavaScript library by kwseok provides utilities for decomposing and composing Korean syllables. This port brings those capabilities to WASM while maintaining API compatibility.

## Features

### Core Functions

**WASM-exported functions (use `wasm_` prefix in JavaScript):**

Core Functions:
- **`wasm_isHangulSyllable(c: u32) -> bool`**: Check if a character is a valid Hangul syllable (가-힣, U+AC00 to U+D7A3)
- **`wasm_decompose(syllable: u32, output_ptr: u32) -> bool`**: Decompose syllable into jamo; writes 3 u32 values (initial, medial, final) to WASM memory at offset. WARNING: Caller must allocate at least 12 bytes via wasm_alloc.
- **`wasm_decompose_safe(syllable: u32, output_ptr: u32, output_size: u32) -> bool`**: Safe variant with buffer size validation. Returns false if buffer too small (requires output_size >= 3).
- **`wasm_compose(initial: u32, medial: u32, final: u32) -> u32`**: Compose jamo into syllable code point (returns 0 if invalid)
- **`wasm_hasFinal(syllable: u32) -> bool`**: Check if a syllable has a final consonant (받침)
- **`wasm_getInitial(syllable: u32) -> u32`**: Extract initial consonant (초성) from a syllable
- **`wasm_getMedial(syllable: u32) -> u32`**: Extract medial vowel (중성) from a syllable
- **`wasm_getFinal(syllable: u32) -> u32`**: Extract final consonant (종성) from a syllable
- **`wasm_decomposeString(input_ptr: u32, input_len: u32, output_ptr: u32) -> u32`**: Decompose UTF-8 string into jamo code points; returns count of output code points

**Memory management:**
- **`wasm_alloc(size: u32) -> u32`**: Allocate WASM memory; returns byte offset (0 on failure)
- **`wasm_free(ptr: u32, size: u32) -> void`**: Deallocate WASM memory (no-op in current implementation)

### Technical Highlights

- **Full Unicode Hangul Support**: Handles all 11,172 valid Hangul syllables (U+AC00 to U+D7A3)
- **UTF-8 Encoding**: Proper UTF-8 decoding for multi-byte character sequences
- **Compatibility Jamo**: Uses Unicode Hangul Compatibility Jamo (U+3131–U+318E) for decomposed output
- **Zero Dependencies**: No external libraries required
- **WASM Optimized**: Compiled with Zig's release-small optimization for minimal binary size
- **Memory Safe**: All operations are bounds-checked and panic-free in production paths

## Architecture

### Data Structures

```
JamoDecomp:
  - initial: u32  (compatibility jamo character code)
  - medial: u32   (compatibility jamo character code)
  - final: u32    (compatibility jamo character code, 0 if no final)
```

### Unicode Constants

- **Hangul Syllable Range**: U+AC00 (가) to U+D7A3 (힣)
- **Initial Jamo (초성)**: 19 forms (U+1100 onwards)
- **Medial Jamo (중성)**: 21 forms (U+1161 onwards)
- **Final Jamo (종성)**: 28 forms including 0 (no final) (U+11A8 onwards)

### Composition Formula

A Hangul syllable is composed using:
```
syllable = HANGUL_SYLLABLE_BASE + (initial_idx × 21 × 28) + (medial_idx × 28) + final_idx
```

This formula allows O(1) decomposition and composition operations.

## Building

### Requirements

- **Zig**: 0.15 or later
- **Optional**: [uv](https://astral.sh/uv) for running the interactive demo

### Quick Build

Use the included Taskfile:

```bash
task build:wasm       # Build hangul.wasm (ReleaseSmall - optimized for size)
task build:wasm:fast  # Build with ReleaseFast (optimized for speed)
task build:wasm:debug # Build with Debug info
```

### Manual Compilation

```bash
# Optimized for size (recommended)
zig build-obj hangul.zig -target wasm32-freestanding -O ReleaseSmall

# Optimized for speed
zig build-obj hangul.zig -target wasm32-freestanding -O ReleaseFast

# With debug information
zig build-obj hangul.zig -target wasm32-freestanding -O Debug
```

### Build Profiles

- **ReleaseSmall** (9.5 KB): Optimized binary size, ideal for web distribution
- **ReleaseFast** (97 KB): Optimized runtime performance
- **Debug**: Full debug information for development

## Testing

Run tests using Taskfile or directly:

```bash
task test             # Run all tests
task test:verbose     # Run with verbose output
task check:all        # Format check + lint + test + build
```

Or run directly:

```bash
zig test hangul.zig
```

### Test Suite

The implementation includes 3 core tests covering:

- **`decompose hangul`**: Validates correct decomposition of boundary and mid-range syllables
  - Tests 가 (U+AC00, first syllable) with no final consonant
  - Tests 한 (U+D55C, mid-range) with final consonant
  - Verifies compatibility jamo output

- **`compose hangul`**: Validates assembly of jamo components into syllables
  - Tests composition without final (ㄱ + ㅏ → 가)
  - Tests composition with final (ㅎ + ㅏ + ㄴ → 한)

- **`has final`**: Ensures correct final consonant detection
  - Tests syllables with and without final consonants

### All Tests Passing

```
1/3 hangul.test.decompose hangul...OK
2/3 hangul.test.compose hangul...OK
3/3 hangul.test.has final...OK
All 3 tests passed.
```

## Usage

### JavaScript / Browser

```javascript
// Load the WASM module
async function initializeWasm() {
  try {
    const response = await fetch('hangul.wasm');
    const buffer = await response.arrayBuffer();
    const { instance } = await WebAssembly.instantiate(buffer);
    window.wasmModule = instance.exports;
  } catch (error) {
    console.error('WASM initialization error:', error);
    // Falls back to JavaScript implementation
  }
}

initializeWasm();

// Check if character is Hangul (uses WASM when available)
const code = 0xD55C; // '한'
if (window.wasmModule && window.wasmModule.wasm_isHangulSyllable(code)) {
  console.log('Character is Hangul');
}

// Decompose syllable into jamo (allocate memory via wasm_alloc)
const bufPtr = window.wasmModule.wasm_alloc(12); // 3 × u32 = 12 bytes
if (bufPtr !== 0 && window.wasmModule.wasm_decompose(0xD55C, bufPtr)) {
  // Read from WASM linear memory
  const memory = new Uint32Array(window.wasmModule.memory.buffer);
  const offset = bufPtr / 4; // Convert byte offset to u32 offset
  const initial = String.fromCharCode(memory[offset]);     // ㅎ (0x314E)
  const medial = String.fromCharCode(memory[offset + 1]);  // ㅏ (0x314F)
  const final = memory[offset + 2] !== 0 ? String.fromCharCode(memory[offset + 2]) : ""; // ㄴ (0x3134)
  console.log(`Jamo: ${initial}${medial}${final}`); // ㅎㅏㄴ
  window.wasmModule.wasm_free(bufPtr, 12);
}

// Compose jamo into syllable
const composed = window.wasmModule.wasm_compose(0x3131, 0x314F, 0); // ㄱ + ㅏ
console.log(String.fromCharCode(composed)); // '가'

// Check for final consonant (받침)
const hasFinal = window.wasmModule.wasm_hasFinal(0xD55C); // '한'
console.log(hasFinal); // true
```

### Node.js

```javascript
const fs = require('fs');

// Load WASM module
async function loadHangul() {
  const wasmBuffer = fs.readFileSync('hangul.wasm');
  const { instance } = await WebAssembly.instantiate(wasmBuffer);
  return instance.exports;
}

const hangul = await loadHangul();

// Use the same API as browser
const isHangul = hangul.wasm_isHangulSyllable(0xD55C);
const bufPtr = hangul.wasm_alloc(12);
if (bufPtr !== 0 && hangul.wasm_decompose(0xD55C, bufPtr)) {
  const memory = new Uint32Array(hangul.memory.buffer);
  const offset = bufPtr / 4;
  console.log('Initial:', String.fromCharCode(memory[offset]));
  console.log('Medial:', String.fromCharCode(memory[offset + 1]));
  console.log('Final:', String.fromCharCode(memory[offset + 2]));
  hangul.wasm_free(bufPtr, 12);
}
```

## Interactive Demo

An HTML demo (`index.html`) is included with:

- **Decomposition Viewer**: Real-time breakdown of Korean characters
- **Composition Tool**: Combine jamo to create syllables
- **Property Checker**: Inspect individual character properties
- **String Processor**: Decompose entire Korean text

<img src="screenshot.png" alt="hangul-wasm Demo" width="100%" />

Run the demo locally:
```bash
task run:demo         # Serve demo on localhost:8120
task run:demo:browse  # Open in browser automatically
```

**Demo Requirements**: [uv](https://astral.sh/uv) is required to serve the demo page (see Requirements above). Install with:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

The demo includes fallback JavaScript implementation for development. When `hangul.wasm` is available, all decomposition/composition operations automatically use the optimized Zig/WASM module via:
- `wasm_isHangulSyllable()` for character validation
- `wasm_decompose()` with typed array output buffers
- `wasm_compose()` for jamo composition
- `wasm_hasFinal()` for final consonant checks

JavaScript fallback is used if WASM fails to load.

## Implementation Details

### UTF-8 Decoding

The library includes a custom UTF-8 decoder (`decodeUtf8Char`) to handle:

- 1-byte sequences (ASCII: 0x00–0x7F)
- 2-byte sequences (0xC0–0xDF)
- 3-byte sequences (0xE0–0xEF) — Hangul is encoded here
- 4-byte sequences (0xF0–0xFF)

Each decoded character is checked against the Hangul syllable range and processed accordingly.

### Memory Management

#### Safe Allocation Patterns

**For simple decomposition (recommended):**
```javascript
// Allocate memory via wasm_alloc
const bufPtr = hangul.wasm_alloc(12); // 3 × u32 = 12 bytes
if (bufPtr !== 0 && hangul.wasm_decompose(0xD55C, bufPtr)) {
  // Read from WASM linear memory
  const memory = new Uint32Array(hangul.memory.buffer);
  const offset = bufPtr / 4; // Convert byte offset to u32 offset
  console.log('Initial:', String.fromCharCode(memory[offset]));
  console.log('Medial:', String.fromCharCode(memory[offset + 1]));
  console.log('Final:', String.fromCharCode(memory[offset + 2]));
  hangul.wasm_free(bufPtr, 12);
}
```

**For bulk string processing:**
```javascript
// Allocate buffer for large string decomposition
const input = '한글'.repeat(1000); // Large Korean text
const maxOutput = input.length * 3; // Worst case: each char → 3 jamo
const outputSize = maxOutput * 4; // Each u32 = 4 bytes
const outPtr = hangul.wasm_alloc(outputSize);

if (outPtr === 0) {
  console.error('WASM allocation failed');
  return;
}

const memory = new Uint32Array(hangul.memory.buffer);
const outArray = memory.subarray(outPtr / 4, (outPtr / 4) + maxOutput);

// ... use outArray for string processing ...

// Always deallocate
hangul.wasm_free(outPtr, outputSize);
```

#### Allocation Guarantees

- **wasm_alloc(size)**: Returns byte offset into WASM linear memory, or 0 on failure
  - Check return value: `if (ptr === 0) { handle error }`
  - Size in bytes (not elements)
  - Uses simple 16KB static buffer allocator (linear allocation)

- **wasm_free(ptr, size)**: No-op in current implementation
  - Simple linear allocator doesn't reclaim memory
  - Safe to call (for API compatibility)
  - For production use, consider reset strategy or proper allocator

- **Output Buffer Sizing**:
  - `wasm_decompose`: Allocate exactly 12 bytes (3 × u32)
  - `wasm_decomposeString`: Caller responsible for buffer size
    - Input: UTF-8 bytes (1-4 bytes per character)
    - Output: One code point per Hangul jamo + non-Hangul chars
    - Worst case: All Hangul with finals (3 jamo per char) = input.length * 3 code points * 4 bytes

The WASM module uses a simple 16KB static buffer allocator for memory management.

## Performance Characteristics

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| `isHangulSyllable` | O(1) | Simple range check |
| `decompose` | O(1) | Arithmetic decomposition |
| `compose` | O(19 + 21 + 28) | Linear jamo lookup (worst case) |
| `decomposeString` | O(n) | Linear scan with UTF-8 decoding |

Typical WASM execution is 10-100x faster than equivalent JavaScript for large text processing.

## Compatibility

### Browser Support

- All modern browsers with WebAssembly support (Chrome 57+, Firefox 52+, Safari 14.1+, Edge 15+)

### Node.js Support

- Node.js 22+ (native WebAssembly support)

## Differences from Original hangul.js

This port focuses on the core decomposition/composition functionality:

**Implemented:**
- [x] `isHangulSyllable` (similar to `isComplete`)
- [x] `decompose` (similar to `disassemble`)
- [x] `compose` (similar to `assemble`)
- [x] `hasFinal` / `getInitial` / `getMedial` / `getFinal`
- [x] String processing with UTF-8 support

**Not Implemented (Advanced Features):**
- [ ] `search` / `Searcher` (advanced pattern matching)
- [ ] `rangeSearch` (highlight/range detection)
- [ ] Vowel/consonant classification utilities
- [ ] Keyboard input method handling (Dubeol vs. Sebeol)

These can be added if needed; the core algorithmic foundation is in place.

## Security Considerations

- All operations are performed on Unicode code points, not strings
- No external input parsing (caller is responsible for UTF-8 decoding)
- Bounds checking on jamo lookup tables
- No panics in production code paths
- Deterministic behavior (no randomness or external state)

## Documentation

### Rationale & Design

- [**0001: Hangul Decomposition Algorithm**](./docs/rationale/0001_hangul_decomposition_algorithm.md) — Mathematical foundations of O(1) composition/decomposition, UTF-8 handling, boundary conditions, and algorithmic correctness guarantees.

### Development Guidelines

See [AGENTS.md](./AGENTS.md) for project principles, TDD workflow, commit conventions, and release procedures.

## Development

This project follows the principles outlined in [AGENTS.md](./AGENTS.md):

### TDD Workflow

1. Write failing tests first (Red)
2. Implement minimal code to pass tests (Green)
3. Refactor and tidy (Refactor)

Use `task pre:commit` before committing to ensure formatting and tests pass.

### Code Style

- Follows Zig conventions
- Const-first, explicit error handling with `?` operator
- Comprehensive Unicode comments with U+XXXX references
- Algorithm comments explain decomposition/composition mathematics

### Available Tasks

```bash
task fmt              # Format code
task fmt:check        # Check formatting (CI-friendly)
task test             # Run test suite
task test:verbose     # Verbose test output
task build:wasm       # Build optimized WASM
task check:all        # Full quality check
task pre:commit       # Pre-commit checks (fmt + test)
task run:demo         # Build and serve interactive demo
task run:demo:browse  # Build, serve, and open in browser
task clean            # Remove build artifacts
```

## Credits

This project is a Zig/WebAssembly port of [**hangul.js**](https://github.com/kwseok/hangul.js) by [kwseok](https://github.com/kwseok). The original library provided the algorithmic foundation and API design that informed this implementation.

## License

MIT

## References

- [Original hangul.js Repository](https://github.com/kwseok/hangul.js)
- [Unicode Hangul Block Specification](https://www.unicode.org/charts/PDF/UAC00.pdf)
- [Zig Language Documentation](https://ziglang.org/documentation/master/)
- [WebAssembly Specification](https://webassembly.org/)

## Related Projects

- [Hangul.js (E-)](https://github.com/e-/Hangul.js): Feature-rich JavaScript implementation
