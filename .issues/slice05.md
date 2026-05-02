## Parent

#1

## What to build

SwiftUI Canvas compositor that takes a FLUX illustration PNG and renders the final botanical plate with native typography and texture.

## What to render

- Aged paper texture background (bundled asset)
- FLUX illustration, centered
- Title: common name (large, serif font)
- Scientific name: italic, below title
- Family: smaller, below scientific name
- Plate number: auto-incremented integer, bottom corner
- Notes panel: user notes from entry, bottom portion
- Border: thin decorative border around entire plate

All text rendered natively by SwiftUI. FLUX never generates text.

## Technical notes

- Canvas renders at 2480 x 3508 px (300dpi portrait A4)
- Export to PNG via UIGraphicsImageRenderer or similar
- Plate number auto-increments per the entry's index in the library (not user-editable in v0.1)

## Acceptance criteria

- [ ] Illustration composited onto paper texture
- [ ] Title, scientific name (italic), family rendered in correct positions
- [ ] Notes panel populated from entry.notes
- [ ] Plate number rendered
- [ ] Border rendered
- [ ] Output saved to generated/plates/ with UUID filename
- [ ] Entry updated: plate_filename populated
- [ ] Export size is print-quality (2480 x 3508 at 300dpi or equivalent)

## Blocked by

#8 (FLUX illustration must exist first)