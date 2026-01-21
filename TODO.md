# hangul-wasm TODO

This document tracks planned enhancements, known issues, and future work for the hangul-wasm library.

**Current Version**: v0.6.2  
**Test Status**: 58 unit tests + 13 e2e tests  
**WASM Size**: ~6.9KB (ReleaseSmall)

---

## Completed Features

- [x] Core decomposition/composition (O(1) operations)
- [x] All 11,172 Hangul syllables exhaustively tested
- [x] UTF-8 string processing
- [x] WASM memory management (16KB static allocator)
- [x] 2-Bulsik IME with full state machine
- [x] Double jamo detection (initial, medial, final)
- [x] Syllable splitting logic
- [x] Backspace decomposition
- [x] JavaScript integration layer (`hangul-ime.js`)
- [x] Interactive demo (`index.html`)
- [x] WASM API exports for IME functionality

---

## High Priority

### Documentation & Usability

- [x] **Update README.md test count** - ~~Currently shows "3 core tests" but there are 29 tests total~~ Updated to show 32 tests
- [x] **Add npm package setup** - Created `package.json` with Bun support for npm/yarn/bun installation
- [x] **TypeScript type definitions** - Added `hangul-ime.d.ts` with full API types
- [ ] **API reference documentation** - Generate docs from code comments

### Testing & Quality

- [x] **Fix skipped test** - Added `decompose_safe logic validation (host)` test that validates the same logic without WASM-specific pointer handling
- [x] **Add integration tests** - Browser-based tests using Playwright (13 tests covering 2-Bulsik, 3-Bulsik, blur handling, and tools)
- [x] **Add performance benchmarks** - Benchmarks show WASM is 1.5-2x faster for single operations (IME use case), while JS can be faster for bulk due to call overhead
- [ ] **Benchmark in CI** - Add benchmark step to GitHub Actions to track performance regressions
- [ ] **Property-based IME fuzz tests** - Random keystroke sequences to catch state machine edge cases

### IME Improvements

- [x] **Fix double final consonant splitting** - Fixed: when a double final (e.g., ㄺ) splits on vowel input, first component stays as final, second becomes new initial (닭+ㅏ→달가)
- [x] **Add `wasm_ime_commit()`** - Added explicit function to finalize current composition and reset state
- [x] **Fix blur handling** - IME now commits composition when input field loses focus
- [ ] **Improve composition overlay** - Currently disabled in `hangul-ime.js` (lines 65, 71, 93, etc.)

---

## Medium Priority

### Features

- [x] **3-Bulsik (Sebeolsik) keyboard layout** - Added support for the three-set layout
  - Design analysis in `docs/rationale/0002_ohi_js_ime_port_strategy.md`
  - Separate state machine (`processCho3Bulsik`, `processJung3Bulsik`, `processJong3Bulsik`)
  - No syllable splitting (unlike 2-Bulsik)
  - WASM export: `wasm_ime_processKey3()`
  - JavaScript integration: `HangulIme.setLayoutMode('3bulsik')`

- [x] **Jamo classification utilities** - Added helper functions with WASM exports:
  - `isJamo`, `isVowel`, `isConsonant`, `isDoubleConsonant`, `isDoubleVowel`

- [x] **Bulk string composition** - Added `composeString` / `wasm_composeString` (inverse of decompose)

- ~~**Unicode normalization**~~ - Out of scope; browser APIs (`String.normalize()`) handle this

### Memory Management

- [ ] **Implement proper allocator** - Current `wasm_free` is a no-op (hangul.zig:342-347)
  - Consider arena/bump allocator for reset strategy
  - Or simple free-list allocator for general use

- [ ] **Add `wasm_alloc_reset()`** - Reset allocator state for bounded workloads

### Build & Distribution

- [x] **Add release tasks to Taskfile** - Added `release:patch`, `release:minor`, `release:major` with VERSION file
- [x] **GitHub Actions CI** - Added `.github/workflows/ci.yml` for automated testing and WASM build
- [x] **Pre-built WASM releases** - Added `.github/workflows/release.yml` to publish WASM on version tags
- [x] **Native Zig dev server** - Replaced Python/uv server with http.zig static file server (see `docs/rationale/0003_http_zig_static_server.md`)
- [ ] **CDN distribution** - Publish to unpkg or jsdelivr for direct browser usage

---

## Low Priority / Future Work

### Advanced Features (Currently Out of Scope per AGENTS.md)

- [ ] **Pattern matching / search** - `search()` / `Searcher` class for partial Hangul matching
  - Useful for autocomplete and search-as-you-type
  - Would enable searching "ㅎㄱ" to match "한글"

- [ ] **Range search for highlighting** - `rangeSearch()` for finding match positions in text

### Performance Optimizations

- [ ] **SIMD for bulk operations** - Use WASM SIMD for batch decomposition (if browser support allows)
- [ ] **Streaming composition API** - Progressive character-by-character composition for large texts
- [x] **Optimize `compose()` lookup** - Replaced O(68) linear search with O(1) comptime reverse lookup tables

### Platform Support

- [ ] **Deno support** - Test and document Deno usage
- [ ] **Cloudflare Workers** - Test WASM execution in edge runtime
- [ ] **React/Vue/Svelte components** - Framework-specific IME components

### Alternative Input Methods

- [ ] **QWERTZ keyboard layout** - German keyboard support
- [ ] **AZERTY keyboard layout** - French keyboard support
- [ ] **Mobile soft keyboard** - Touch-optimized IME interface

---

## Known Issues

### IME State Machine

1. **Double vowel edge case** - When typing ㅗ+ㅏ after a syllable with double final, behavior may differ from native Korean IME

2. **Shift key timing** - Rapid shift+key combinations may not always register the shifted jamo

### WASM Memory

1. **Memory exhaustion** - 16KB static buffer can be exhausted in heavy use; no recovery mechanism
2. **No garbage collection** - Allocations never reclaimed during session

### Browser Compatibility

1. **Safari composition events** - Some Safari versions handle `keypress` differently
2. **Mobile keyboard support** - Virtual keyboards may not trigger expected events

---

## Code Quality Tasks

### Refactoring

- [x] **Extract IME module** - Moved IME code to separate `ime.zig` file (v0.6.0)
- [x] **Optimize compose() lookup** - Replaced O(68) linear search with O(1) comptime reverse lookup tables (v0.6.2)
- [ ] **Consolidate index mapping** - `ohiIndexToInitialIdx`, `ohiIndexToMedialIdx`, `ohiIndexToFinalIdx` could use a unified approach
- [ ] **Add error enum** - Replace `?T` returns with proper error types for better debugging

### Documentation

- [x] **Add inline doc comments** - Zig `///` doc comments for all public functions
- [ ] **Code examples in docs** - More comprehensive usage examples in README
- [ ] **Architecture diagram** - Mermaid diagram showing WASM/JS boundary and IME state flow
- [ ] **Update README benchmarks** - Include latest compose() performance (1.85x faster after O(1) optimization)

### Testing

- [ ] **Property-based tests for IME** - Exhaustive testing of keystroke sequences
- [ ] **Fuzz testing** - Random input testing for UTF-8 decoder and IME state machine
- [ ] **Visual regression tests** - Screenshot comparison for demo page

---

## Technical Debt

- [x] **LAYOUT_2BULSIK duplication** - Removed unused Zig constant; layout now only in JS (v0.5.5)
- [x] **Magic numbers** - Added OHI_VOWEL_BASE and OHI_JAMO_OFFSET constants (v0.5.5)
- [x] **Unused code paths** - Removed unused LAYOUT_2BULSIK constant from Zig (v0.5.5)
- [x] **Composition overlay** - Removed disabled overlay code (v0.5.6)

---

## Ideas & Research

- [ ] **Investigate Hangul Jamo vs Compatibility Jamo** - Consider supporting both output formats
- [ ] **Korean romanization** - McCune-Reischauer or Revised Romanization conversion
- ~~**Hanja (Chinese characters)**~~ - Out of scope; requires large dictionary data, different domain
- [ ] **Text-to-speech integration** - Phonetic analysis for Korean TTS

---

## Contributing

When working on these items:
1. Follow TDD approach (Red → Green → Refactor)
2. Use commit conventions from AGENTS.md (`feat:`, `fix:`, `struct:`, `refactor:`, `chore:`)
3. Add tests before implementing features
4. Update documentation alongside code changes

See [AGENTS.md](./AGENTS.md) for detailed development guidelines.
