# Post-fix smoke test — running state and duplicate submissions

Hand-off checklist for a human tester. **This is a technical smoke test, not the usability study.**
It checks one behaviour that changed in `71f7bab`; it is not a participant session and must not be
reported as one.

> If the same person will also be the novice participant P01, **run their formal P01 session first**
> (see §5). Do not show them this checklist, do not demonstrate the fix, and do not let them read the
> expected results beforehand, or they no longer meet the protocol's "no prior use of this app" and
> "tasks not demonstrated" conditions.

**Executed 2026-10-18 on a Google Pixel 8 (Android 17) — all six checks PASS.** The build, observations
and evidence are recorded in the execution log at the end of this file. The checklist remains usable for
re-running against a later build; a future run should add its own row rather than editing this record.

## 1. Build identification — fill this in before testing

Record these exactly; a result without them cannot be tied to a build.

| Field | Value |
| --- | --- |
| Git commit under test | `c510a5449b5e102e2f39712c95ee584ad3badd10` (contains fix `71f7bab`) |
| `git status --short` at build time | empty (clean worktree) |
| Build command | `flutter build apk --debug` |
| APK SHA-256 (`shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk`) | `6fc725cff6822b272e51bf6ccf561cf4e30c603aa82a7c0a3ed5eb33d7f0c973` |
| Device model / Android version | Google Pixel 8, Android 17 / API 37, arm64-v8a |
| Install time | 2026-10-18 00:08:50 NZDT (`adb install -r`, app data preserved) |

`git rev-parse HEAD` and `git status --short` on the commit that contains the fix should show `71f7bab`
(or a descendant) and a clean tree.

## 2. Setup

```sh
export PATH="$HOME/development/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
flutter pub get
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n nz.fieldsnap.app/.MainActivity
```

The gallery needs one usable photo. Use the fixed task image from the frozen kit rather than a personal
photo, so this test matches the study material:

```sh
adb push docs/usability/task_images/task1_subject.jpg /sdcard/Pictures/FieldSnap/
adb shell content call --method scan_file --uri content://media \
  --arg /sdcard/Pictures/FieldSnap/task1_subject.jpg
```

## 3. Checklist — one row per behaviour

For each row: do the action, compare with "expected", then write **PASS**, **FAIL** or **BLOCKED**
(blocked = could not run the step) in the last column. If it fails, capture the exact steps and a
screenshot or screen recording; do not try to fix anything during the test.

| # | What to do | Expected behaviour | Result |
| --- | --- | --- | --- |
| 1 | Pick the task image, wait for the quality verdict, tap **Identify species** once, and watch the result panel and the button immediately. | The result panel shows a running/progress state and the button shows its progress label (it is disabled). The state appears within the first moments, not only for one frame. | **PASS** — button showed "Classifying on this device..." with spinner and disabled state, captured twice (00:10 and 00:14) |
| 2 | While that first classification is still running, tap **Identify species** again 3–5 times quickly. | The extra taps do nothing: no second run starts, and the button stays disabled until the first finishes. | **PASS** — 5 rapid taps during a 409 ms run produced exactly one new history row (1 → 2) |
| 3 | Let the classification finish, then open **Identification history** (clock icon). | Exactly **one** new record for this classification. Count the rows before and after: the difference must be 1. | **PASS** — baseline 0; after one classification 1 row |
| 4 | With a result on screen, tap **Replace from gallery** and pick a *different* image (frozen unsuitable image used). | The old result disappears immediately: no previous species name, confidence, candidates or latency is shown against the new photo. The panel then shows the quality verdict for the new image. | **PASS** — old Korimako result, confidence and latency gone; new image showed its own quality verdict |
| 5 | With a valid image, tap **Identify species** and let it finish. | A normal result renders: top-three candidates and, if the score is above 0.37, a named species with its learning card; below the threshold it shows "Uncertain" with the candidates marked as not asserted. No crash. | **PASS** — Korimako (bellbird) 98.6 %, top-3 list and learning card rendered; repeated after recovery |
| 6 | Error/recovery path: pick the frozen `task2_unsuitable.jpg`. | The app explains what is wrong in words, identification is unavailable, and the app recovers without a crash once a usable image is chosen or the permission is granted. | **PASS** — explained "Too little detail: sharpness 9.1 is below the 100 minimum"; tapping Identify added no history (3 → 3); re-picking the valid image recovered |

Rows 1–3 are the regression under test (the running state used to be cleared immediately, which hid the
progress state and allowed duplicate runs). Rows 4–6 guard against the fix having broken the older
behaviour.

## 4. Evidence to keep

Keep these outside the repository (they are not needed for it, and a recording may contain personal
content):

* the filled-in table above, with the build fields from §1;
* one screenshot of the running state (row 1) if it can be captured in time;
* a screen recording of rows 2–3 (the duplicate-tap test is easier to judge from video);
* the history list before and after row 3;
* for any failure: exact steps, what happened, what was expected, and whether it reproduces.

Optional log check:

```sh
adb logcat -d | grep -iE "flutter|fieldsnap|exception" | tail -40
```

## 5. If a defect reproduces

1. Stop the test; do not mix this with the usability session.
2. Record: build fields, steps, observed vs expected, frequency (e.g. 3/3 attempts).
3. Hand the record back. Any fix must be the smallest behaviour change, with a regression test that
   fails first, and a change-log entry — the same process used for the running-state fix (`Change 7` in
   `docs/post_evaluation_changes.md`).
4. Frozen artefacts (model weights, preprocessing, class list, FR2/FR4 thresholds, sealed-test results,
   usability success criteria) must not be touched to make a smoke test pass.

## 6. Formal novice session P01 — separate, and first if it is the same person

The smoke test is **not** a usability session. If the same person is going to be P01:

1. run the formal P01 session **first**, using the frozen v1.2 kit: consent script → 30-second
   orientation (no button demonstration) → the three fixed tasks → standard SUS → the short interview;
2. only afterwards, if at all, use that person for a technical smoke check — at that point they are no
   longer a novice and must not be recorded as a second participant.

Record the build used for P01 on the intake sheet. If the P01 build and the smoke-test build differ,
say so explicitly wherever the results are reported; a result is only interpretable against the build
that produced it.

The formal kit lives in `docs/usability/` (protocol v1.2, consent script, sheets, SUS form, reset
checklist); the print pack is generated by `tools/usability/make_print_pack.py`. Do not substitute zoo
photographs or personal photos for the two fixed task images.


## Execution log — 2026-10-18 (Google Pixel 8, Android 17)

| Field | Value |
| --- | --- |
| Build | commit `c510a54` (contains `71f7bab`), clean worktree |
| APK SHA-256 | `6fc725cff6822b272e51bf6ccf561cf4e30c603aa82a7c0a3ed5eb33d7f0c973` |
| Result | **S1–S6 all PASS**; no device-level defect found, no code changed after the test |
| Executed by | Robin, with adb automation driven by the Agent; physical interactions by Robin |
| Evidence location | `~/Documents/FieldSnap_M2_smoke_evidence_2026-10-18/` — screenshots and `BUILD_AND_RESULTS.txt`. Deliberately outside the repository; contains no participant data and no device identifier |

**One deviation, recorded rather than hidden.** After cancelling the photo picker once, the in-app result
had already been cleared — `pickImage()` clears the result as soon as a new selection starts — so the
classification was re-run. That re-run accounts for one extra history row. The behaviour is pre-existing
and outside this checklist; it is noted here so the history counts (1 → 2 → 3 → 4 across the session) are
not mistaken for duplicate classifications.

**Post-test reset for P01** (protocol v1.2 reset checklist): app data cleared, camera permission revoked,
only `/sdcard/Pictures/FieldSnap/` touched, both frozen task images re-pushed and media-scanned, history
empty, capture screen showing "No image selected yet", personal `DCIM/Camera` photos intact (5 files).
The device is handed over ready for the formal P01 session on the same build.
