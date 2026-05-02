## Parent

#1

## What to build

"Export PNG" button in the entry detail view that saves the composed plate to a user-selected location.

## Behavior

- User clicks "Export PNG"
- NSSavePanel opens with suggested filename: `{common_name}-plate.png`
- User selects destination
- Plate PNG written to chosen location
- No further action required; file is standalone

## Acceptance criteria

- [ ] "Export PNG" button visible in entry detail view
- [ ] Save panel opens with filename pre-filled from common name
- [ ] Correct plate PNG written to selected location
- [ ] Exported PNG is the composed botanical plate at full resolution

## Blocked by

#9 (plate compositor must produce output first)