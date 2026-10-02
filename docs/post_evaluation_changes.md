# Changes made after the one-shot final test evaluation

The sealed test split was evaluated **once** on 2026-09-11 (run id `20260911T191603-e6b10afd`,
report `docs/final_test_evaluation_report.md`). This file records every code change made after that
evaluation, why it was necessary, and whether it can affect the frozen metrics. It exists because
"we fixed something afterwards" is exactly the kind of statement that needs to be checkable.

**Bottom line: the frozen test results are unchanged and remain valid.** No change below touches the
model, the 20 classes, the training data, the FR2/FR4 thresholds, or the evaluation procedure.

## Frozen artefacts (verified untouched)

| Artefact | State |
| --- | --- |
| `assets/models/fieldsnap_float.tflite` | unchanged, SHA-256 `e6b10afdfc97d73d…` |
| `lib/services/confidence_policy.dart` | threshold still 0.37, margin still `null` |
| `lib/services/quality_gate.dart` | thresholds still 0.26 / 0.89 / 100.0 |
| `artifacts/final_test_predictions.json` | byte-identical to the evaluated run |
| `artifacts/final_test_evaluation.json` | byte-identical; top-1 0.5561, top-3 0.7968, macro-F1 0.5343 |
| `docs/final_test_evaluation_report.md` | unchanged |

No retraining, no data expansion, no class-set change, no preprocessing change made for model
optimisation, no threshold change, and the sealed test split was **not** re-opened for scoring.

## Change 1 — stale result after replacing an image (`ClassifierViewModel`)

**What was wrong.** `ClassifierState.copyWith(clearResult: true)` cleared only `card` and
`errorMessage`. `resultKind`, `candidates`, `confidence` and `latencyMs` survived, so after picking a
different image the result panel kept rendering the previous photo's species and latency above the
new preview.

**Reproduced before fixing.** Three regression tests in `test/classifier_view_model_test.dart`
(`stale-result regression (audit Phase A)`) failed on the pre-fix code with
`Expected: ResultKind.none / Actual: ResultKind.identified`:

1. replacing the image clears candidates, confidence, card, latency and result kind;
2. an in-flight classification cannot attach its result to a different image;
3. an in-flight classification cannot attach its result after the image is cleared.

**Fix.** `clearResult` (and `clearImage`) now reset every derived field, and the view model keeps a
`_selectionGeneration` counter that is bumped on each new pick and on clear. `classify()` captures the
generation and returns without rendering if it changed while the model was running. All three tests
pass afterwards; 104 deterministic tests pass overall.

**Effect on the frozen metrics: none.** Presentation-layer state only.

## Change 2 — JPEG EXIF orientation applied twice (`ImagePreprocessor`)

**What was wrong.** The `image` package is inconsistent across formats: its **JPEG** decoder applies
the EXIF orientation itself, while its **PNG** decoder does not. `ImagePreprocessor` applied the
transform unconditionally, so any JPEG carrying an orientation tag was rotated a second time.

**Reproduced before fixing, with JPEG fixtures (not only PNG).** Newly generated JPEG fixtures that
store the same pixels and the same tags as the PNG ones showed the PNG path upright for all eight
orientations and the JPEG path wrong for 2-8 (`v6` produced a sideways layout). Two regression tests
were added to `test/integration/preprocessing_conformance_test.dart`: "JPEG orientation fixtures land
upright too" and "JPEG and PNG agree for every orientation" (a wrong transform shows up as a large
per-element delta). The old PNG-only coverage could not see this defect, which is why the audit's
insistence on JPEG fixtures was correct.

**Fix.** `applyExifOrientationSafely` skips the transform when the decoder already applied it. The
JPEG path is detected structurally (SOI/SOF markers, plus the stored frame dimensions in
`readJpegStoredDimensions`) and the reasoning, including the pinned package version's measured
behaviour, is recorded in the function's doc comment. The PNG path is unchanged and still applies the
transform, so the PNG fixtures and the Python conformance measurement keep their meaning.

**Could this have affected the frozen evaluation? No — measured, not assumed.** A metadata-only scan
of all 187 evaluated test images (`artifacts/exif_orientation_audit.json`) found:

* 186 JPEG files and 1 non-JPEG;
* **0 APP1 segments and 0 EXIF APP1 segments in total**;
* EXIF orientation histogram: `{'1': 187}` (PIL `getexif()`, metadata read only — no pixel decode into
  arrays, no classification, no metric recomputation).

With no EXIF segment anywhere in the split, `readExifOrientation` returned `null` for every image and
the transform never ran, so the pre-fix and post-fix preprocessing produce identical tensors for all
187 images. `test/fixtures/reference_input.f32` (PNG-derived) is unaffected for the same reason and
the runtime-conformance tests still pass.

**Why the timestamps differ:** this scan reads the committed test manifest only. The manifest was not
modified, and the scan does not open the split for scoring — no prediction was produced or inspected.

## Change 3 — usability protocol v1.0 → v1.1 (no study had run)

See `docs/usability_evaluation_protocol.md`. Changes: the stale commit reference was replaced with a
version-based freeze ("recruitment begins from a commit whose message carries `usability protocol
v1.1`"); the two task images are now fixed committed files with provenance
(`docs/usability/task_images/`); Task 2's wording no longer announces that its photo is unsuitable;
an app crash is now a task failure **and** a critical error instead of an exclusion; a five-step clean
reset is mandatory before every session; and SUS administration is fixed as "facilitator reads each
item aloud verbatim, participant marks answers privately". No participant data exists.

## Change 4 — usability analysis script (no study had run)

`tools/usability/analyse_usability.py` accepted any value starting with `y`/`n`, which meant the blank
template's own `yes / no` placeholder could parse as a success. It now:

* accepts only exact `yes`/`no` (and validates every required task field, the completion time, and the
  participant id);
* treats **any** missing or out-of-range SUS answer as an invalid questionnaire for that participant
  rather than silently omitting it, and reports how many questionnaires were invalid and why;
* refuses to produce a summary at all (exit code 2) when no sheet is valid.

Self-tests prove a blank template cannot count as a participant: it is parsed, found invalid, yields
no SUS score, contributes zero successes, and leaves the criteria empty. Loose values (`yep`, `maybe`,
empty, the template's `yes / no`) are each rejected. Running the script against a real copy of the
blank template produced `sessions_valid: 0` and exit code 2.

## Change 5 — consent wording

`docs/usability/consent_script.md` now states that anonymous aggregate findings and de-identified
short quotations may appear in the assessed university report and in the public project documentation,
that the individual sheets are not published, that audio is **not** recorded by default (explicit
separate consent required), and that a participant can withdraw a quotation even after the session.
The intake sheet's consent rows were updated to match.

## Change 6 — usability protocol amended to a five-participant target (v1.1 → v1.2), before any session

The protocol pre-registered ten participants. The lecturer then clarified that the study has **no
fixed participant count** and that **at least five classmates are recommended**. The target was
therefore amended to **five** — and the amendment was written **before the first session**, when no
participant data existed, so it cannot be a post-hoc adjustment made to suit a result.

**No measurement threshold moved.** ≥ 90 % of recruited participants must still complete Task 1
without intervention, mean SUS must still be ≥ 70, and there must still be zero critical interaction
errors. What changed is the recruitment plan and the point at which a criterion becomes evaluable —
a change with a real statistical consequence, which is why it is recorded here and not as a wording
tweak.

*Applied as*: 90 % of five is 4.5, so the Task 1 requirement at that sample size is **5/5** (all five
unaided). Four of five is 80 % and does not meet the criterion. This is stricter in absolute count
than v1.1's 9/10 and identical in the percentage the requirement states; NFR6 was always a
percentage. The script derives the count from the target rather than hard-coding it.

### Change 6.1 — `analyse_usability.py` no longer mis-reports a partial sample

The previous version had two defects that this amendment exposes:

* `C1_MIN_SUCCESS = 9` with a denominator of 10, and
  `"met": successes >= min(C1_MIN_SUCCESS, n) if n >= 10 else False`. At **n = 1** a fully successful
  participant was therefore reported with **`C1 met: false`** — a *failed* criterion verdict computed
  from a sample that had not yet been recruited. That is the opposite error from flattering the
  result, and it is still wrong: a criterion that cannot yet be evaluated must not be reported as
  met or not met.
* The script had no notion of an interim versus final evaluation, so nothing stopped a single
  participant's output from reading as a finished usability result.

The script now:

* takes `TARGET_PARTICIPANTS = 5` and `C1_MIN_RATE = 0.90`, deriving the required success count
  (`required_successes`) instead of hard-coding it;
* gives every criterion one of three states — `met`, `not_met`, **`not_evaluable`** — where
  `not_evaluable` is used below the target and `met` is `None`;
* emits `"status": "INTERIM"` with an `interim` block and a per-participant `individual_results`
  section below the target, and `"status": "COMPLETE"` with real verdicts at or above it;
* prints a human-readable summary that says `*** INTERIM REPORT - n = 1 of 5 ***`, warns
  *"Do NOT report NFR6 as met or as missed on this sample"*, and never prints a criterion as `MET`
  when the sample is incomplete;
* accepts sessions incrementally — the folder is read as-is, so each new participant is picked up by
  re-running one command, and no schema change is needed to add P02 … P05.

### Change 6.2 — self-test coverage for the interim boundary, and a bug it caught

The self-test previously proved "9/10 meets C1", which no longer describes the study. It now covers
the incremental path: one sheet → `INTERIM` with `not_evaluable` criteria and a reported individual
result; four sheets → still `INTERIM`; five sheets → `COMPLETE`; **4/5 → `not_met`**; 5/5 → `met`;
empty folder → `NO_SESSIONS` and no invented verdict.

Writing that coverage caught a real defect introduced during the rewrite: the three criteria shared a
single `state` variable initialised to `MET` once the target was reached, so C2 and C3 both reported
**`met` even when their own measured value failed** (mean SUS below 70, or one critical error). The
per-criterion verdict is now computed from that criterion's own result, and the test asserts each
criterion flips independently. This is precisely why the check runs before any session rather than
after scoring a participant.

### Change 6.3 — facilitator operating procedure

The facilitator procedure was folded into the existing kit rather than added as a second document:
`docs/usability/TESTING_KIT.md` now carries the build verification and the recording of the build SHA
and APK hash, the rehearsal step and what counts as a non-session; `docs/usability/reset_checklist.md`
carries the scoped reset commands and the hand-over starting-state checks; and
`docs/usability/FREEZE_v1.2.md` records the amended freeze (see Change 6.6). The reset is explicitly bounded to `nz.fieldsnap.app` and
`/sdcard/Pictures/FieldSnap/` so it cannot remove personal gallery content from the facilitator's own
phone. `consent_script.md` now states the ~25-minute duration; `participant_intake.md` and
`results/README.md` were updated for the fixed task images, the open-ended `P01…P99` id range and the
incremental intake.

### Change 6.4 — the test build had to be rebuilt

The APK present in `build/app/outputs/flutter-apk/` was built at **Sep 11 19:06**, *before* commit
`3152302` (20:24), which fixed the **stale-result-after-replacing-an-image** defect and the JPEG EXIF
orientation defect. Task 2 is exactly "pick an unsuitable image, see the result, replace the image",
so the pre-fix build would have shown the participant a defect the repository had already fixed, and
the session would have measured the wrong binary. The build was therefore rebuilt from the commit
carrying protocol v1.2, and its SHA is recorded on the intake sheet of every session.

### Change 6.5 — the Task 1 stimulus was replaced (found in the facilitator rehearsal)

The facilitator rehearsal (protocol §4.2), run on the real device before any participant, found that
the fixed Task 1 image made **Task 1 impossible to complete**. The frozen classifier returns
`Uncertain` for `kowhai` photo `412560479`:

* `artifacts/conf/val_scores.json` records `predicted: tradescantia`, `top1_score: 0.2199`,
  `correct: false`;
* the device agreed — top confidence **0.193**, below the deployed accept threshold of 0.37, so the
  result panel showed *"Uncertain - try another photo"* with the nearest candidates unasserted.

Task 1 asks the participant to identify the photo **and open the learning card**, but the card is only
rendered for an asserted species. With no species asserted there is no card, so
`learning_card_opened` would have been `no` and `success_without_intervention` `no` for every
participant regardless of ability: **C1 would have failed 0/5 by construction**, and the report would
have attributed a stimulus defect to the participants and the app.

The cause was the image choice, not the model (kowhai recall is 0.364 on the frozen test split; only
2 of 7 kowhai validation images clear the threshold). The replacement was selected on the frozen
validation scores as the **most reliable** available stimulus, not merely a working one:

| Candidate class | val images | accepted (≥0.37) | accepted **and** correct | best score |
| --- | ---: | ---: | ---: | ---: |
| **korimako (chosen)** | 9 | 9 | **9 / 9** | **0.9856** |
| silver_fern | 5 | 5 | 5 / 5 | 0.9783 |
| tui | 8 | 8 | 7 | 0.9554 |
| kowhai (the original) | 7 | 3 | 2 | 0.8384 |

`task1_subject.jpg` is now korimako photo `37780000` (validation split, © Jon Sullivan, CC BY,
observation `24431147`). Verified on the device after the swap: **Korimako (bellbird), confidence
98.6%**, learning card rendered. Because the stimulus is pushed to the gallery and is **not** bundled
as an app asset, no rebuild was needed and the APK is unchanged. Full provenance and the reasoning
are in `docs/usability/task_images/PROVENANCE.md`; the runbook now pins the image hash so a swapped or
re-encoded file is caught before a session.

This was decided **before any participant existed** and is recorded here rather than presented as a
silent tweak. It changes the stimulus, not the measurement: the tasks, the SUS, the criteria, the
thresholds and the model are all as pre-registered.

**Rehearsal outcome (no participant data).** With the corrected stimulus the facilitator completed the
whole procedure on the device: Task 1 produced a korimako card; Task 2's unsuitable image was refused
by the **FR2 quality gate** ("too little detail: sharpness 9.1 is below the 100 minimum"), which is
the `quality_gate` path, and recovery by re-picking the normal image restored a clean accepted state;
Task 3 deleted exactly the intended history entry; the reset returned the app to "No image selected
yet" and "No saved identifications yet." No sheet was created for the rehearsal and nothing was
counted in any denominator. The rehearsal also confirmed the reset touches only `nz.fieldsnap.app`
and `/sdcard/Pictures/FieldSnap/`: all five personal camera photos were verified present afterwards.

## What was *not* changed, and stays closed

* The sealed test split was not re-opened for scoring; the evaluation above stands as the one-shot
  result.
* No threshold, class, preprocessing-for-model or model change, therefore no metric can move.
* The model, the 20 classes, the training data, the FR2/FR4 thresholds and every frozen metric were
  untouched by the v1.2 amendment.
* The three usability thresholds themselves (≥ 90 %, SUS ≥ 70, zero critical errors) were not moved.
* Usability testing has not started; no participant was recruited, contacted or tested in this change,
  and **no participant data was created** — `docs/usability/results/` still contains only its README.
