# Gemma 4 MTP: adoption watch

Date: 2026-05-05
Branch: `main`
Source announcement: https://blog.google/innovation-and-ai/technology/developers-tools/multi-token-prediction-gemma-4/

## Status

**Blocked on upstream.** Last checked: 2026-05-05.

Google released Multi-Token Prediction (MTP) drafters for Gemma 4 (E2B, E4B, 26B-MoE, 31B-Dense), claiming up to ~3x decode speedup via speculative decoding. The drafters share the target model's KV cache, which is a non-trivial extension beyond stock spec-decode. Naturista already runs `mlx-community/gemma-4-31b-it-4bit` and `mlx-community/gemma-4-e4b-it-4bit` as targets, so the existing weights remain valid. We just can't drive a drafter alongside them yet.

## Why we are not adopting now

Two upstream gaps, both must close before we can integrate cleanly:

1. **`mlx-swift-lm` 3.31.3 has spec-decode on the low-level API, not on `ChatSession`.**
   - PR #173 (https://github.com/ml-explore/mlx-swift-lm/pull/173) shipped in 3.31.3. It adds `generate()` and `generateTokens()` overloads taking `draftModel: any LanguageModel` and `draftCache: [KVCache]?`, plus a new `SpeculativeTokenIterator` and a `TokenIteratorProtocol`. Files touched: `Libraries/MLXLMCommon/Evaluate.swift`, `Libraries/MLXLMCommon/KVCache.swift`.
   - Constraint: drafter must support trimmable KV caches. `MambaCache` models throw. Gemma uses standard KV cache, so this is fine.
   - **`ChatSession` does not yet accept a draft model.** Tracked in issue #181 (https://github.com/ml-explore/mlx-swift-lm/issues/181). Naturista's `GemmaActor` (Sources/AI/GemmaActor.swift, lines 128:141) drives generation through `ChatSession`, so we either wait for #181 or refactor `GemmaActor` to use `generateTokens()` directly.

2. **No MLX-format MTP drafter weights are published.**
   - The `mlx-community` HF org currently lists only the standard `gemma-4-*` targets. No `*-mtp`, `*-drafter`, or `*-spec` variants as of 2026-05-05. This is the harder blocker: even with full `ChatSession` support, there is nothing to load.

## Trigger conditions to adopt

Hard blocker (both required):

- `mlx-community` publishes a 4-bit drafter that pairs with at least one of `gemma-4-31b-it-4bit` or `gemma-4-e4b-it-4bit`. (Or another mlx-community Gemma 4 target we already support.)
- One of:
  - mlx-swift-lm issue #181 closes (https://github.com/ml-explore/mlx-swift-lm/issues/181) AND `ChatSession.init` gains a draft-model parameter, **or**
  - We accept refactoring `GemmaActor` to call `generateTokens()` directly (already possible on 3.31.3, but it costs us the `ChatSession` instructions / images / tools convenience and means re-implementing the prompt assembly that `ChatSession` does for VLM inputs).

Informational signal (not blocking, but worth tracking): drafter weights showing up on the `google` HF org in any format, even before MLX conversion.

The watcher script `scripts/check_gemma4_mtp_status.sh` polls these and prints `READY TO ADOPT` when both blockers clear. Run it manually periodically, or wire it to a scheduled remote agent later via the `schedule` skill.

## Future integration sketch

Recorded so a future session does not re-derive the shape. File:line references reflect the current state of `main` as of 2026-05-05.

1. **`Sources/App/ModelConfig.swift`**
   - Add an optional `drafterRepoId: String?` to the `GemmaModel` enum cases (~lines 11:50). Populate only for Gemma 4 variants. Gemma 3 has no MTP path, so its cases stay `nil`.
   - Extend the download path used by `HuggingFaceDownloader` (~lines 377:498) to fetch both target and drafter directories under `~/Library/Application Support/Naturista/models/`. Drafter directory naming should mirror target (e.g. `gemma-4-e4b-it-4bit-drafter`).
   - Re-evaluate `GemmaModel.requirements` RAM thresholds to add the drafter footprint. Exact values depend on what `mlx-community` ships; revisit when weights publish.

2. **`Sources/AI/GemmaActor.swift`**
   - In `ensureContainer()` (~lines 121:163), load the drafter alongside the target via `VLMModelFactory.shared.loadContainer(...)` (or the LM equivalent if the drafter is text-only).
   - At the generation site (~lines 128:141), there are two paths depending on which trigger clears first:
     - **If `ChatSession` gains draft support (issue #181):** pass `draftModel:` (and any draft cache) into `ChatSession.init`. Smallest diff.
     - **If we move first by refactoring:** drop `ChatSession` and call `generateTokens()` directly with `draftModel:` and `draftCache:` from `MLXLMCommon.Evaluate`. We then own prompt assembly and image-processing that `ChatSession` was handling for us; bring across whatever VLM input shaping currently happens inside `ChatSession`.
   - Memory cleanup blocks (existing `MLX.Memory.clearCache()` at ~lines 46, 64, 85) need to also free the drafter container if the API hands one back separately.

3. **`Naturista/project.yml`** (~lines 10:33)
   - Already on `mlx-swift-lm` 3.31.3, which has the low-level spec-decode API. Bump only if `ChatSession` support lands in a later release we want.

4. **`Sources/App/SystemCapability` (or wherever RAM gating lives)**
   - Re-run capability checks against the new drafter-inclusive thresholds before letting users select a Gemma 4 variant.

5. **Validation**
   - Run end-to-end `identify()` on a known-good plant photo. Confirm the JSON output schema matches pre-MTP output (no regression in fidelity).
   - Measure tokens/sec before vs after. Expect ~2x to 3x on Apple Silicon per the Google blog.

## Out of scope for this watch

- Forking `mlx-swift-lm` to port spec-decode ourselves.
- Reviving a Python `mlx-lm` sidecar for Gemma (would regress mac-appy Phase 3 Python teardown).
- Switching the default model away from `gemma3_12b`. Gemma 3 has no MTP variant.
- Auto-conversion of Gemma 4 MTP drafter weights from PyTorch to MLX format. Wait for `mlx-community` to publish.
