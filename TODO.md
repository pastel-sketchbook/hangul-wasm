# hangul-wasm TODO

This document tracks planned enhancements, known issues, and future work for the hangul-wasm library.

**Current Version**: v0.3.0  
**Test Status**: 40 tests (39 passed, 1 skipped)  
**WASM Size**: 4.4KB (ReleaseSmall)

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
- [ ] **Add integration tests** - Browser-based tests using Playwright or similar
- [ ] **Add performance benchmarks** - Measure and document actual performance vs JavaScript implementations

### IME Improvements

- [x] **Fix double final consonant splitting** - Fixed: when a double final (e.g., ㄺ) splits on vowel input, first component stays as final, second becomes new initial (닭+ㅏ→달가)
- [x] **Add `wasm_ime_commit()`** - Added explicit function to finalize current composition and reset state
- [ ] **Improve composition overlay** - Currently disabled in `hangul-ime.js` (lines 65, 71, 93, etc.)

---

## Medium Priority

### Features

- [ ] **3-Bulsik (Sebeolsik) keyboard layout** - Add support for the three-set layout
  - Design analysis complete in `docs/rationale/0002_ohi_js_ime_port_strategy.md`
  - Requires separate processing logic from 2-Bulsik
  - Estimated effort: ~20 hours

- [x] **Jamo classification utilities** - Added helper functions with WASM exports:
  - `isJamo`, `isVowel`, `isConsonant`, `isDoubleConsonant`, `isDoubleVowel`

- [ ] **Bulk string composition** - Compose array of jamo back into syllables (inverse of `wasm_decomposeString`)

- [ ] **Unicode normalization** - Support NFC/NFD normalization for Hangul strings

### Memory Management

- [ ] **Implement proper allocator** - Current `wasm_free` is a no-op (hangul.zig:342-347)
  - Consider arena/bump allocator for reset strategy
  - Or simple free-list allocator for general use

- [ ] **Add `wasm_alloc_reset()`** - Reset allocator state for bounded workloads

### Build & Distribution

- [ ] **Add release tasks to Taskfile** - `release:patch`, `release:minor`, `release:major` (documented in AGENTS.md but not in Taskfile.yml)
- [ ] **GitHub Actions CI** - Automated testing and WASM build on push/PR
- [ ] **Pre-built WASM releases** - Publish `.wasm` files to GitHub releases
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
- [ ] **Optimize `compose()` lookup** - Consider hash map or binary search for jamo lookup (currently O(68) linear search)

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

3. **Focus change handling** - IME state persists across field blur/focus; should commit on blur

### WASM Memory

1. **Memory exhaustion** - 16KB static buffer can be exhausted in heavy use; no recovery mechanism
2. **No garbage collection** - Allocations never reclaimed during session

### Browser Compatibility

1. **Safari composition events** - Some Safari versions handle `keypress` differently
2. **Mobile keyboard support** - Virtual keyboards may not trigger expected events

---

## Code Quality Tasks

### Refactoring

- [ ] **Extract IME module** - Move IME code to separate `ime.zig` file for clarity
- [ ] **Consolidate index mapping** - `ohiIndexToInitialIdx`, `ohiIndexToMedialIdx`, `ohiIndexToFinalIdx` could use a unified approach
- [ ] **Add error enum** - Replace `?T` returns with proper error types for better debugging

### Documentation

- [ ] **Add inline doc comments** - Zig `///` doc comments for all public functions
- [ ] **Code examples in docs** - More comprehensive usage examples in README
- [ ] **Architecture diagram** - Visual representation of WASM/JS boundary

### Testing

- [ ] **Property-based tests for IME** - Exhaustive testing of keystroke sequences
- [ ] **Fuzz testing** - Random input testing for UTF-8 decoder and IME state machine
- [ ] **Visual regression tests** - Screenshot comparison for demo page

---

## Technical Debt

- [ ] **LAYOUT_2BULSIK duplication** - Layout defined in both Zig (hangul.zig:804-814) and JS (hangul-ime.js:12-23)
- [ ] **Magic numbers** - Some numeric constants lack named definitions (e.g., 31 for vowel threshold)
- [ ] **Unused code paths** - `LAYOUT_2BULSIK` constant in Zig appears unused after refactor
- [ ] **Composition overlay** - Feature disabled but code remains (hangul-ime.js:96-138)

---

## Ideas & Research

- [ ] **Investigate Hangul Jamo vs Compatibility Jamo** - Consider supporting both output formats
- [ ] **Korean romanization** - McCune-Reischauer or Revised Romanization conversion
- [ ] **Hanja (Chinese characters)** - Hangul to Hanja conversion lookup
- [ ] **Text-to-speech integration** - Phonetic analysis for Korean TTS

---

## Contributing

When working on these items:
1. Follow TDD approach (Red → Green → Refactor)
2. Use commit conventions from AGENTS.md (`feat:`, `fix:`, `struct:`, `refactor:`, `chore:`)
3. Add tests before implementing features
4. Update documentation alongside code changes

See [AGENTS.md](./AGENTS.md) for detailed development guidelines.
