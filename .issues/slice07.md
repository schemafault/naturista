## Parent

#1

## What to build

Editable notes field on entry detail view, plus "Retry" button that reruns the full pipeline from the original photo.

## Notes editing

- Single text field, multiline
- Saved on change (no explicit save button)
- Persists across app restarts
- Shown in entry detail and in composed plate's notes panel

## Retry behavior

- "Retry" button on failed or completed entries
- Reruns full pipeline: Gemma identification → FLUX illustration → compositor → save
- Notes are preserved across retry
- illustration_filename and plate_filename regenerated (UUID unchanged)
- user_status resets to "unreviewed"

## Acceptance criteria

- [ ] Notes field is editable on entry detail
- [ ] Notes persist across app restarts
- [ ] Notes shown in composed plate's notes panel
- [ ] "Retry" button visible on all entries (failed, completed, unreviewed)
- [ ] Retry preserves notes
- [ ] Retry regenerates illustration and plate (filenames same UUID, new files)
- [ ] Retry resets user_status to unreviewed
- [ ] Failed entries show error message; retry reruns from failed stage

## Blocked by

#7 (identification panel UI exists for notes display) and #9 (export works to confirm retry is useful)