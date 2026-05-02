## Parent

#1

## What to build

Library view showing all saved entries in a grid or list, with the ability to open an entry detail view.

## UI elements

- Grid of entry thumbnails (illustration or working image as fallback)
- Failed entries marked with error badge
- Low-confidence entries marked with warning badge
- Tap/click entry opens detail view
- Entry count shown in window title

## Behavior

- Shows all entries sorted by created_at descending (newest first)
- Failed entries visible and distinguishable
- No search, no filter, no favorites in v0.1
- Empty state: "Import your first photo" prompt

## Acceptance criteria

- [ ] Library view shows all entries as a grid
- [ ] Failed entries have error badge
- [ ] Low-confidence entries have warning badge
- [ ] Tapping entry opens detail view
- [ ] Empty state shows when library is empty
- [ ] Entry count in window title updates as entries are added

## Blocked by

#5 (app shell with SQLite entries must exist first)