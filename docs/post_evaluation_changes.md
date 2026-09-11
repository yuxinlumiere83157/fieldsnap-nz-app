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

## What was *not* changed, and stays closed

* The sealed test split was not re-opened for scoring; the evaluation above stands as the one-shot
  result.
* No threshold, class, preprocessing-for-model or model change, therefore no metric can move.
* Usability testing has not started; no participant was recruited, and no result was fabricated.
