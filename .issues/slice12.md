## Parent

#1

## What to build

Connect all AFK slices into a working end-to-end app and verify the full pipeline. This is a human-judgment gate: does the integrated app actually work, or are there integration bugs that weren't visible in individual slices?

## What to verify

Full flow:
1. Import photo (file picker)
2. Gemma identifies → identification panel populates
3. "Generate Plate" → FLUX generates → compositor renders → entry saved
4. Library view shows entry with correct thumbnail
5. Open entry → plate visible → export PNG works
6. Retry with notes editing preserves notes

Failure flows:
- Gemma returns malformed JSON → entry marked failed → retry works
- FLUX times out → entry marked failed → retry works
- Move library folder → reopen app → all data intact

## Acceptance criteria

- [ ] Full import → identify → generate → compose → save → export flow works end-to-end
- [ ] Library view shows entries with correct state
- [ ] Retry preserves notes
- [ ] Failed entries are retryable
- [ ] Folder portability works
- [ ] All slices connect without runtime crashes

## Blocked by

#5, #6, #7, #8, #9, #10, #11 (all AFK slices complete)