# Post-fix smoke test — running state and duplicate submissions

Hand-off checklist for a human tester. **This is a technical smoke test, not the usability study.**
It checks one behaviour that changed in `71f7bab`; it is not a participant session and must not be
reported as one.

> If the same person will also be the novice participant P01, **run their formal P01 session first**
> (see §5). Do not show them this checklist, do not demonstrate the fix, and do not let them read the
> expected results beforehand, or they no longer meet the protocol's "no prior use of this app" and
> "tasks not demonstrated" conditions.

Nothing in this file has been executed yet. The current status is **NOT RUN**: no Android SDK/adb was
available on the machine used for the fix, so the device behaviour is unverified. Do not mark a row
pass until the tester has actually observed it.

## 1. Build identification — fill this in before testing

Record these exactly; a result without them cannot be tied to a build.

| Field | Value |
| --- | --- |
| Git commit under test | `________________` (fix commit is `71f7bab`; use the commit actually built) |
| `git status --short` at build time | `________________` (expect empty) |
| Build command | `flutter build apk --debug` |
| APK SHA-256 (`shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk`) | `________________` |
| Device model / Android version | `________________` |
| Install time | `________________` |

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
| 1 | Pick the task image, wait for the quality verdict, tap **Identify species** once, and watch the result panel and the button immediately. | The result panel shows a running/progress state and the button shows its progress label (it is disabled). The state appears within the first moments, not only for one frame. | |
| 2 | While that first classification is still running, tap **Identify species** again 3–5 times quickly. | The extra taps do nothing: no second run starts, and the button stays disabled until the first finishes. | |
| 3 | Let the classification finish, then open **Identification history** (clock icon). | Exactly **one** new record for this classification. Count the rows before and after: the difference must be 1. | |
| 4 | With a result on screen, tap **Replace from gallery** and pick a *different* usable image. | The old result disappears immediately: no previous species name, confidence, candidates or latency is shown against the new photo. The panel then shows the quality verdict for the new image. | |
| 5 | With the new image, tap **Identify species** and let it finish. | A normal result renders: top-three candidates and, if the score is above 0.37, a named species with its learning card; below the threshold it shows "Uncertain" with the candidates marked as not asserted. No crash. | |
| 6 | Error/recovery path: pick an unsuitable image (for example the frozen `task2_unsuitable.jpg`), or deny the camera permission and try **Take photo**. | The app explains what is wrong in words, identification is unavailable, and the app recovers without a crash once a usable image is chosen or the permission is granted. | |

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
