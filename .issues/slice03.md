## Parent

#1

## What to build

SwiftUI panel that displays Gemma 4 identification results. Shown after a photo is imported and Gemma has processed it.

## UI elements

- Top candidate: common name, scientific name (italic), family
- Model certainty badge: high (green) / medium (yellow) / low (red) with label "Model certainty — not a measure of accuracy"
- Alternatives list (if any): name + reason
- Visible evidence list
- Missing evidence list
- Safety note: "Do not consume or handle based only on this identification."
- Entry status badge: unreviewed (gray) / failed (red)
- "Generate Plate" button (disabled until Gemma returns)

## Behavior

- If Gemma returns before user has dismissed the panel, panel auto-populates
- If Gemma fails, panel shows error state and "Generate Plate" stays disabled
- No re-identify button; identification is re-run only via pipeline retry

## Acceptance criteria

- [ ] Panel appears after Gemma completes
- [ ] All fields populated from Gemma JSON output
- [ ] Model certainty shown as colored badge (not raw number)
- [ ] Safety note always visible
- [ ] "Generate Plate" button disabled while Gemma is running
- [ ] Entry record updated with identification_json, model_confidence, user_status

## Blocked by

#6 (Gemma subprocess must be running)