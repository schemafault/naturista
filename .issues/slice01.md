## Parent

#1

## What to build

SwiftUI macOS app shell with minimal structure: app window, file picker import, UUID-based file copy, SQLite schema, and basic save/read.

## Acceptance criteria

- [ ] App launches and shows a window
- [ ] "Import Photo" button opens NSOpenPanel (file picker)
- [ ] Selected photo is copied to `assets/originals/` with UUID filename
- [ ] Working copy (JPEG, 4MP max) saved to `assets/working/`
- [ ] SQLite database created at `naturista.sqlite`
- [ ] `entries` table with: id (UUID), created_at, captured_at (from EXIF or null), original_image_filename, working_image_filename, identification_json (empty), model_confidence (null), user_status (unreviewed), illustration_filename (null), plate_filename (null), notes (empty)
- [ ] Entry is saved to DB and read back on app relaunch
- [ ] Library folder portability verified: move folder to another location, reopen, data intact

## Blocked by

None - can start immediately