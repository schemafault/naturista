# Gemma native port — Phase 1a design

Date: 2026-05-03
Branch: `mac-appy`
Strategic context: `performance_and_mas_audit.md` → "Next session — entry point" → step 1 ("Port Gemma identification first… Replace `GemmaActor`'s `PythonProcessTransport` with an in-process `MLXLMCommon` pipeline. Ship as a feature flag.")

## Goal

Lay foundation so the actual native MLX implementation (Phase 1b) can land without churning callers. **No behavior change in Phase 1a.**

## Non-goals (deferred)

- Implementing `NativeGemmaIdentifier` against `MLXVLM`. (1b)
- Validating model loading on all four registered models. (1c)
- Building UI for the toggle. (1d)
- Removing the Python backend. (1e)

## Architecture

Introduce an `Identifier` actor protocol that the pipeline can call without knowing what's behind it.

```swift
protocol Identifier: Actor {
    func identify(photoPath: String) async throws -> IdentificationResult
    func shutdown() async
}
```

Two concrete impls land behind this protocol:

| Impl | Status | Backed by |
|---|---|---|
| `PythonGemmaIdentifier` | ships in 1a (lifted from current `GemmaActor`) | `PythonProcessTransport` + `Python/gemma_service.py` |
| `NativeGemmaIdentifier`  | **placeholder only** in 1a, real in 1b | `MLXVLM` from `mlx-swift-lm` |

`GemmaActor.shared` becomes a thin facade that:
- holds an `any Identifier`
- consults a UserDefaults flag (`gemma.useNativeBackend`, default `false`)
- forwards `identify` and `shutdown`
- swaps the underlying identifier when the flag changes (rebuilt on next call)

`PipelineService` and `ModelLease` keep calling `GemmaActor.shared.identify(...)` — no caller change.

## File layout

| File | What |
|---|---|
| `Sources/AI/Identifier.swift` | `Identifier` protocol + `IdentificationResult`/`TopCandidate`/`Alternative` (lifted from `GemmaActor.swift`) |
| `Sources/AI/PythonGemmaIdentifier.swift` | Existing Python-backed actor (lifted) |
| `Sources/AI/NativeGemmaIdentifier.swift` | Placeholder actor — `identify` throws "not implemented" until 1b. Establishes the import surface for `MLXVLM` so 1a's build proves the SPM wiring works. |
| `Sources/AI/GemmaActor.swift` | Slimmed: facade only |
| `Sources/AI/IdentificationBackend.swift` | UserDefaults-backed feature-flag store |

## SPM wiring

- Package: `https://github.com/ml-explore/mlx-swift-lm`, pinned `from: "3.31.3"` (latest tag as of 2026-05-03).
- Products linked to Naturista target: `MLXVLM`, `MLXLMCommon`.
- Updated via `Naturista/project.yml` `packages:` and target `dependencies:`. `xcodegen` regenerates the `.xcodeproj`.

## Risks / known gaps

- **Llama 3.2 Vision 11B** is in our `GemmaModel` registry but **not** supported by `mlx-swift-lm`'s `MLXVLM`. Phase 1a doesn't break it (Python backend remains default). Phase 1b will need to either gate native-backend availability per-model or drop the Llama option from the picker. Decision deferred to 1b.
- mlx-swift-lm requires Swift tools 6.1 (Xcode 16.3+). Naturista's `SWIFT_VERSION` is set to 5.9 (a language mode, not toolchain) — should be compatible on a modern Xcode, but the first `xcodebuild` after wiring it up confirms.
- First build after adding the dep will compile mlx Metal shaders. Slow once, then cached. Per memory `mlx_swift_metal_xcodebuild.md`, must build via `xcodebuild` rather than `swift build` (the existing Naturista xcodeproj path is already xcodebuild-based, so this is fine).

## Verification

1. `xcodegen` regenerates `Naturista.xcodeproj` without errors.
2. `xcodebuild -scheme Naturista -configuration Debug build` succeeds (Metal shaders compile, no link errors against `MLXVLM`/`MLXLMCommon`).
3. App launches, identifies a photo end-to-end exactly as before (Python backend, since flag defaults `false`). Behavior should be identical to mac-appy@HEAD prior to this branch.
