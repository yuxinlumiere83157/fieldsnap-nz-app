# Per-session reset checklist

One copy per session. Fill it in **before** the participant touches the device, and keep it with that
participant's sheets in `docs/usability/results/` (git-ignored). Protocol reference:
`docs/usability_evaluation_protocol.md` §4.1.

| Field | Value |
| --- | --- |
| Participant id | |
| Session date | |
| Build / commit under test | |
| Facilitator (initials) | |

## Reset steps — tick each one, in order

| # | Step | Command | Done |
| --- | --- | --- | --- |
| 1 | Clear all app state (history, caches, selected image) | `adb shell pm clear nz.fieldsnap.app` | ☐ |
| 2 | Return the camera permission to its documented starting state | `adb shell pm revoke nz.fieldsnap.app android.permission.CAMERA` | ☐ |
| 3 | Remove the previous session's images from the device gallery | `adb shell rm -f /sdcard/Pictures/FieldSnap/*` | ☐ |
| 4 | Push only the two fixed task images | `adb push docs/usability/task_images/task1_subject.jpg /sdcard/Pictures/FieldSnap/` and `... task2_unsuitable.jpg ...` | ☐ |
| 5 | Make the picker see them | `adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///sdcard/Pictures/FieldSnap/task1_subject.jpg` (repeat for task 2) | ☐ |
| 6 | Launch and confirm a clean starting state | open **Identification history** → must be **empty**; back → capture screen shows **No image selected yet** | ☐ |

## Starting-state confirmation (record what you actually saw)

| Check | Observed |
| --- | --- |
| History screen empty | yes / no |
| Capture screen shows no image selected | yes / no |
| Task 1 image visible in the picker | yes / no |
| Task 2 image visible in the picker | yes / no |
| Airplane mode state for this session | on / off (state it; the app must work offline either way) |

## Deviations

| Step not completed, or anything unexpected | Effect on the session |
| --- | --- |
| | |

A session with an incomplete reset is still valid, but every deviation is reported in
`docs/usability_evaluation_report.md` — silently skipping this sheet is the one thing that would make
the data unusable.
