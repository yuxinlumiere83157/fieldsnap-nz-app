# Usability testing kit

Everything needed to run sessions P01–P10 for the study in
`docs/usability_evaluation_protocol.md` (v1.1). Nothing here contains participant data, and no
session has been run.

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

## Before the first session

1. `python3 tools/usability/analyse_usability.py --self-test` — the parser and SUS arithmetic must
   pass before any real sheet is parsed.
2. Charge and prepare the device; confirm the build under test and write its commit on every sheet.
3. Print one copy per participant of: consent script, intake sheet, SUS form, session notes sheet,
   reset checklist. Ten sets for P01–P10.
4. Have the two task images ready to push (see `reset_checklist.md`).

## Creating the per-participant sheets

`docs/usability/results/` is git-ignored so participant data never leaves the machine. Create one
sheet set per session:

```sh
mkdir -p docs/usability/results
cp docs/usability/templates/participant_intake.md docs/usability/results/P01_intake.md
cp docs/usability/templates/session_notes.md    docs/usability/results/P01_session.md
cp docs/usability/reset_checklist.md            docs/usability/results/P01_reset.md
```

Only `P01`…`P10` identifiers are used, and no names, contact details or device serials go on any
sheet. If a participant withdraws, delete that participant's files.

## Running a session

Follow protocol §4.2: reset → consent → 30-second glance → three tasks in order → SUS → three
qualitative questions. Answers to the tasks are not hinted at; every facilitator intervention is
counted, because the primary criterion is completing Task 1 **without** intervention.

## After all ten sessions

```sh
python3 tools/usability/analyse_usability.py --json artifacts/usability_results.json
```

The script refuses to produce a summary (exit code 2) if no sheet validates, so an incomplete set
cannot be mistaken for a result. Then write `docs/usability_evaluation_report.md` with the criteria
met or not met, per-task numbers, SUS mean and median, qualitative themes with counts, and every
deviation — including any reset step that could not be completed.
