# Usability testing kit

Everything needed to run the study in `docs/usability_evaluation_protocol.md` (**v1.2**). The
recruitment target is **five** participants (P01…) — sessions are run and accumulated one at a time,
so P01 can go ahead without waiting for the others. Nothing here contains participant data, and no
participant session has been run; the only run so far is the facilitator rehearsal (below), which
produced no data.

## Files, and what each is for

| File | Purpose | Print? |
| --- | --- | --- |
| `docs/usability_evaluation_protocol.md` | the pre-registered protocol; read it once before the first session | no |
| `consent_script.md` | read aloud before anything else | yes (one per participant) |
| `templates/participant_intake.md` | demographics flags, consent flags, clean-reset record | yes |
| `SUS_form.md` | the participant's own SUS sheet | yes |
| `templates/session_notes.md` | task-by-task record, SUS answers, qualitative answers | yes |
| `reset_checklist.md` | the per-session device reset and starting-state check | yes |
| `task_images/task1_subject.jpg` | the ordinary photo for Task 1 (provenance in `task_images/PROVENANCE.md`) | no |
| `task_images/task2_unsuitable.jpg` | the unsuitable photo for Task 2 | no |
| `tools/usability/make_task_images.py` | regenerates `task2_unsuitable.jpg` deterministically | no |
| `tools/usability/analyse_usability.py` | parses the sheets, scores SUS, evaluates C1–C3 (`--self-test` first) | no |
| `FREEZE_v1.2.md` | the v1.2 hash record for this kit | no |
| `tools/usability/verify_kit_freeze.py` | checks every kit file against that record | no |

## Confirm the build before the first session

A session is only interpretable if the build under test is pinned. Record both identifiers at install
time and write the commit on every participant's sheet (`Build tested`):

```sh
git rev-parse HEAD
shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

**The build must postdate the fixes in `docs/post_evaluation_changes.md`.** The artifact previously
left in `build/app/outputs/flutter-apk/` was built at Sep 11 19:06, *before* commit `3152302`
(20:24), which fixed the stale-result-after-replacing-an-image defect — and **Task 2 is precisely
"pick an unsuitable image, see the result, replace the image"**, so the pre-fix build would have shown
the participant a defect the repository had already fixed. It was rebuilt on 2026-10-02; the tested
build is recorded in `docs/post_evaluation_changes.md`. If the SHA changes after a session, that does
not retroactively change the sheet — it means later sessions used a different build and the report
must say so.

The study must not have moved the frozen configuration. Verify, and change nothing:

```sh
git status --short                     # expect clean apart from your own session sheets
shasum -a 256 assets/models/fieldsnap_float.tflite
git diff --stat lib/services/quality_gate.dart lib/services/confidence_policy.dart   # must be empty
```

## Before the first session

1. `python3 tools/usability/analyse_usability.py --self-test` — the parser, the interim/final boundary
   and the SUS arithmetic must pass before any real sheet is parsed.
2. `python3 tools/usability/verify_kit_freeze.py` — the kit must match `FREEZE_v1.2.md`, so a silent
   edit to a frozen instrument is caught rather than trusted.
3. Charge and prepare the device; confirm the build under test and write its commit on every sheet.
4. Print one copy per participant of: consent script, intake sheet, SUS form, session notes sheet,
   reset checklist. **Five sets are the target**; print more only if more participants are recruited.
5. Have the two task images ready to push (see `reset_checklist.md`), and confirm both hashes against
   `task_images/PROVENANCE.md`.

## Facilitator rehearsal (not a participant session)

Before the first real participant, run the whole procedure once alone: reset → pick the normal image →
read the result and learning card → pick the unsuitable image → recover by re-picking the normal image
→ open history and delete an entry → reset again. This is **not** a pilot participant: create no sheet
for it, record no result, and never count it in any denominator.

**This step is not optional, and it has already earned its place.** In the 2026-10-02 rehearsal it
found that the original fixed Task 1 image returned `Uncertain`, so no learning card was ever rendered
and **Task 1 was impossible for every participant** — a stimulus defect that would otherwise have been
misreported as a run of participant failures. The same rehearsal confirmed that the reset touches only
`nz.fieldsnap.app` and `/sdcard/Pictures/FieldSnap/` (all personal camera photos verified intact) and
that Task 2 takes the **quality gate** path. The full record is in
`docs/post_evaluation_changes.md` Change 6.5.

## Creating the per-participant sheets

`docs/usability/results/` is git-ignored so participant data never leaves the machine. Create one
sheet set per session:

```sh
mkdir -p docs/usability/results
cp docs/usability/templates/participant_intake.md docs/usability/results/P01_intake.md
cp docs/usability/templates/session_notes.md    docs/usability/results/P01_session.md
cp docs/usability/reset_checklist.md            docs/usability/results/P01_reset.md
```

Use `P02`, `P03`… for the next participants as they are tested. Only pseudonymous identifiers are used
(`P01`…`P99`), and no names, contact details or device serials go on any sheet. If a participant
withdraws, delete that participant's files.

## Running a session

Follow protocol §4.3: reset → consent → 30-second glance → three tasks in order → SUS → three
qualitative questions. Answers to the tasks are not hinted at; every facilitator intervention is
counted, because the primary criterion is completing Task 1 **without** intervention. Task 1's learning
card is rendered inside the result panel on the same screen — do not send the participant looking for
a separate "open page" control.

## After each session, and at the target

After **every** session, analyse what exists so far:

```sh
python3 tools/usability/analyse_usability.py
```

Below five valid sheets this prints an **INTERIM** report: that participant's individual task results
and SUS score, with C1–C3 marked *not yet evaluable*. That is the correct output for n = 1; it is not
a usability verdict, and NFR6 must not be reported as met or missed on it.

Once five participants have been tested, the same command reports `COMPLETE` with C1–C3 met or not met,
and the JSON can be written with:

```sh
python3 tools/usability/analyse_usability.py --json artifacts/usability_results.json
```

The script refuses to produce a summary (exit code 2) if no sheet validates, so an incomplete set
cannot be mistaken for a result. Then write `docs/usability_evaluation_report.md` with the criteria
met or not met, per-task numbers, SUS mean and median, qualitative themes with counts, and every
deviation — including any reset step that could not be completed.
