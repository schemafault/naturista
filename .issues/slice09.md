## Parent

#1

## What to build

Python CLI script that loads Gemma 4 31B Dense at 4-bit via mlx-vlm, accepts a photo path, and outputs structured identification JSON. No UI, no SQLite, no Swift. Tests whether the local VLM can produce useful botanical IDs.

## Identification JSON output

```json
{
  "model_confidence": "high | medium | low",
  "top_candidate": {
    "common_name": "string",
    "scientific_name": "string",
    "family": "string"
  },
  "alternatives": [
    {
      "common_name": "string",
      "scientific_name": "string",
      "reason": "string"
    }
  ],
  "visible_evidence": ["string"],
  "missing_evidence": ["string"],
  "safety_note": "Do not consume or handle based only on this identification."
}
```

model_confidence is coarse buckets only. No raw numbers. LLM self-reported confidence is not reliable.

## Acceptance criteria

- [ ] Script accepts photo path as CLI argument
- [ ] Loads Gemma 4 31B Dense 4-bit via mlx-vlm
- [ ] Returns structured JSON matching the spec above
- [ ] Runs against the common test set: 20 plants (dandelion, clover, nettle, rose, oak, ivy, bramble, daisy, thistle, plantain, silverweed, wood sorrel, primrose, bluebell, foxglove, hogweed, elder, hawthorn, birch, fern)
- [ ] Runs against the hard test set: 10 plants (cultivars, vegetative-stage, poor lighting, partial views, non-Western European, look-alike pairs)
- [ ] Common set exit criterion: 14/20 top-candidate correct, at least 4 of remaining 6 marked uncertain or low-confidence
- [ ] Hard set is informational only (used to calibrate safety messaging)

## Blocked by

None - can start immediately