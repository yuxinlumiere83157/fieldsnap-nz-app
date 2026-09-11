# Usability evaluation protocol — v1.1, PRE-REGISTERED

Status: **v1.1**, committed before any participant was recruited, contacted or tested. No participant
data exists at the time of writing and nothing in this folder contains results.

**Why this is v1.1 and not v1.0**: v1.0 named a single commit as its freeze point. That reference went
stale the moment a later commit landed, so a reader could not tell which revision was in force. The
freeze point is therefore recorded as a version plus the git history itself: recruitment may begin
only from a commit whose message carries `usability protocol v1.1`, and any later edit is v1.2 or
higher with its own note. The substantive changes from v1.0 are listed in
`docs/post_evaluation_changes.md`.

This study evaluates the **interface and workflow**, not the model's accuracy. The classifier is
frozen (`docs/final_test_evaluation_report.md`): its measured top-1 is 0.5561, so participants will
often see `Uncertain` or a wrong species, and the instrument below is designed to capture how they
cope with that rather than to hide it.

## 1. Objective and scope

Milestone 1's usability requirement (NFR6) is: **first-identification task success ≥ 90 % without
facilitator intervention, SUS ≥ 70, and zero critical interaction errors**, measured with ten
representative novice users. This protocol operationalises exactly that.

Out of scope: model accuracy, latency, memory, and any change to the frozen artefacts. This study
produces no evidence about whether the identifications are correct.

## 2. Pre-registered success criteria (do not adjust after data collection)

| # | Criterion | Measurement |
| --- | --- | --- |
| C1 | **At least 9 of 10 (≥ 90 %)** participants complete **Task 1** (first identification plus opening the learning card) **without facilitator intervention** | per-participant `task1.success_without_intervention` |
| C2 | **Mean SUS ≥ 70** | standard 10-item SUS, see §6 |
| C3 | **Zero critical interaction errors** across all participants and tasks | `critical_error` count, definition in §5 |

Each criterion is reported as met or not met with its measured value. If a criterion is missed, it is
reported as missed. Success criteria are not reworded, thresholds are not moved, and data from a
participant who fails is not excluded unless the exclusion rule in §4 applies (and then the
exclusion and its reason are reported).

## 3. Participants

* **Target: 10 adult (18+) novice nature learners.** "Novice" = no formal botanical or
  ornithological training and no prior use of this app. Self-declared; recorded as a yes/no flag.
* Recruitment is convenience-based (the people the researcher can reach), which is a documented
  limitation, not a claim of representativeness.
* **Informed consent before anything else**: purpose, what is recorded, that participation is
  voluntary, that they may stop at any time without giving a reason, that no name is recorded, and
  how the data is stored and deleted. The consent script is in
  `docs/usability/consent_script.md`.
* **Pseudonymous identifiers only**: `P01` … `P10`. No names, no contact details, no device serials,
  no photographs of participants. See §8.

## 4. Setting and procedure

### 4.1 Clean reset before every session (do all five steps, in order)

The app keeps state between sessions — selected image, quality verdict, result, and the SQLite history
written by the previous participant. A session that starts with someone else's history is not a clean
measurement, so the reset is a protocol step rather than a good intention:

1. `adb shell pm clear nz.fieldsnap.app` (clears the app's private storage, including the SQLite
   history and any cached copy the picker handed over);
2. `adb shell pm revoke nz.fieldsnap.app android.permission.CAMERA` so the camera-permission path is
   in its documented starting state (the study's tasks use the gallery, and a leftover grant would
   change what a curious participant finds);
3. remove the previous session's images from the device gallery
   (`adb shell rm -f /sdcard/Pictures/FieldSnap/*`) and re-push only
   `task1_subject.jpg` and `task2_unsuitable.jpg` from `docs/usability/task_images/`;
4. re-scan the pushed files so the platform picker lists them
   (`adb shell am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file:///…`);
5. launch the app and confirm the capture screen shows **no image selected** and the history screen is
   **empty**, then hand the device to the participant with the app already open on the capture screen.

Record on the intake sheet that the reset was performed, and note any step that could not be completed
(the session is still valid, but the deviation is reported).

### 4.2 Session sequence

Roughly 20–30 minutes per participant, in one session, away from the facilitator's prompting:

0. perform the reset above **before** the participant touches the device;
1. consent and demographics sheet (`templates/participant_intake.md`);
2. brief app orientation **without touching the tasks**: "this app identifies plants and birds from a
   photo you choose; open it and have a look" (30 seconds, no task hints);
3. three tasks in order (§5), each read aloud verbatim from the task script;
4. standard 10-item SUS (§6), read aloud verbatim;
5. three short qualitative questions (§7), audio-recorded only with separate consent, otherwise
   written down by the facilitator as close to verbatim as possible.

Facilitator discipline: answer only with "please try whatever you would naturally do"; do not point
at controls, name screens, or explain the model. Any departure from this is recorded as an
intervention with its reason, which is what C1 measures.

***Failure and exclusion rules (pre-registered, v1.1)***:

* **An app crash or a hang is a task failure and a critical interaction error**, not an exclusion. The
  participant's session continues if they are willing, and the crash is recorded against the task it
  interrupted (which task, what they were doing, whether the app recovered). A crash therefore counts
  against **C1** and **C3** exactly as a stuck state would — a system that crashes when a novice uses
  it is not usable, and excusing it would flatter the result.
* **A device-level failure outside the app** (the phone dies, the OS photo picker itself is broken) is
  recorded as a technical failure; if it prevents the task, the session is excluded and the exclusion
  with its reason is reported.
* **Withdrawal of consent** ends the session and deletes the sheet; it is reported as a withdrawal
  with no data.
* A participant who simply fails a task is **never** excluded.

## 5. Tasks, and what is recorded

**Fixed prepared task images.** Every session uses the same two committed images, so results are
comparable across participants and the study is reproducible:

| Purpose | File | Notes |
| --- | --- | --- |
| Task 1 (ordinary photo) | `docs/usability/task_images/task1_subject.jpg` | a real photo of a plant or bird from the project's own CC-licensed data set; its provenance is recorded in `docs/usability/task_images/PROVENANCE.md` |
| Task 2 (unsuitable photo) | `docs/usability/task_images/task2_unsuitable.jpg` | deliberately unusable: a photo of a screen, blurry and glare-affected, so the FR2 gate or the classifier is expected to refuse it |

The facilitator copies these two files into the device gallery before each session (the reset
procedure below does this as a step). **Do not substitute personal photos**: it would change the
stimulus between participants and, if the photo is a participant's own, would put their data on the
device under test.

### Task 1 — first identification and learning card (the primary task)

> "Please use the app to identify the plant or bird in this photo, and then open the information card
> about whatever it tells you it is."

| Field | Values |
| --- | --- |
| `started_at`, `ended_at` | wall clock, to the second |
| `completion_time_s` | derived |
| `completed` | yes / no |
| `success_without_intervention` | yes / no — **this is C1** |
| `intervention_count`, `intervention_notes` | how many times the facilitator had to step in, and why |
| `prediction_shown` | the species/`Uncertain` the app displayed (recorded verbatim) |
| `learning_card_opened` | yes / no |
| `errors` | any mistaken action, with what happened |
| `critical_error` | yes / no (see definition below) |

### Task 2 — unsuitable result and recovery

> "Please identify the plant or bird in this photo."

The prepared photo is `task2_unsuitable.jpg` (see §5's image table). The task wording no longer
announces that the photo is unsuitable: telling the participant what to expect would remove exactly
the behaviour being measured. Either of two outcomes counts as success: the quality gate asks for
another image, **or** the result is `Uncertain` and the participant replaces the image. Recording the
recovery path is what the task is for.

| Field | Values |
| --- | --- |
| `completion_time_s`, `completed` | as above |
| `success_without_intervention` | yes / no |
| `path_taken` | `quality_gate` / `uncertain_then_replace` / `other` (describe) |
| `recovered_to_result` | yes / no — did they end with a non-Uncertain result or an explained rejection |
| `errors`, `critical_error`, `intervention_*` | as above |

### Task 3 — history entry

> "Find the list of identifications the app has saved, and delete one of them."

| Field | Values |
| --- | --- |
| `completion_time_s`, `completed` | as above |
| `success_without_intervention` | yes / no |
| `found_history` | yes / no |
| `deleted_entry` | yes / no |
| `errors`, `critical_error`, `intervention_*` | as above |

### Critical interaction error (definition, pre-registered)

An error is **critical** if it leaves the participant unable to continue without the facilitator, or
if it makes them believe something false about the system's state. The three cases counted in this
study:

1. **Stuck state**: the participant cannot proceed and no affordance gets them out (for example a
   blocking error with no working recovery route).
2. **State lie**: the interface tells them something untrue — for example it shows a species for an
   image they never selected, or reports an action succeeded when it did not.
3. **Data loss without warning**: an action destroys something the participant wanted to keep (for
   example deleting a history entry they were still reading, or losing a selected image with no
   warning and no way back).

A slow, confused or inefficient path is **not** critical; it is recorded as an error and a time cost.
The definition is fixed here so it cannot be loosened after seeing the sessions.

## 6. System Usability Scale (standard wording, unchanged)

**Administration (fixed in v1.1 so every participant gets the same treatment):** the participant
receives a printed copy of the ten items and the response scale, the facilitator reads **each item
aloud once, verbatim and in order**, and the participant marks their own answers privately. The
facilitator does not paraphrase, re-order, explain or interpret any item, and does not see the answers
until the sheet is handed back. The instruction given is: *"answer honestly; there are no right
answers"*. If a participant asks what an item means, the facilitator repeats the item and adds
*nothing* else; the fact that the question was asked is noted on the sheet.

Rationale: reading aloud removes a reading-comprehension difference between participants, while the
private marking keeps the answers unobserved. Mixing modes between participants (some overheard, some
written silently) would make the scores incomparable, which is why this is now spelled out.

The standard Likert response set is used, unchanged: **1 = Strongly disagree, 2 = Disagree,
3 = Neutral, 4 = Agree, 5 = Strongly agree.** Items alternate positive/negative:

1. I think that I would like to use this system frequently.
2. I found the system unnecessarily complex.
3. I thought the system was easy to use.
4. I think that I would need the support of a technical person to be able to use this system.
5. I found the various functions in this system were well integrated.
6. I thought there was too much inconsistency in this system.
7. I would imagine that most people would learn to use this system very quickly.
8. I found the system very cumbersome to use.
9. I felt very confident using the system.
10. I needed to learn a lot of things before I could get going with this system.

**Scoring (standard, unmodified):** for odd-numbered items contribute `score − 1`; for even-numbered
items contribute `5 − score`. Sum the ten contributions and multiply by **2.5** → 0–100.
`tools/usability/analyse_usability.py` implements exactly this and is covered by an arithmetic
self-test (see §9).

**Any missing or out-of-range answer invalidates that participant's questionnaire** (the SUS score is
only defined on all ten items; the standard permits no partial scoring). An invalid questionnaire is
**not** silently dropped from the mean: the report states how many questionnaires were invalid, why,
and reports the mean over the valid ones with that count, so a participant who skipped items cannot
quietly disappear from the headline number.

## 7. Qualitative questions (asked after the SUS)

1. "What was the most confusing part about using the app?"
2. "The app sometimes says 'Uncertain' instead of naming a species. In your own words, what do you
   think that means?" (probes whether the abstention concept is understood, or read as a fault)
3. "If you could change one thing about the app, what would you change first?"

Recorded verbatim where possible. Reported as themes with the participant count behind each theme and
at least one representative quote per theme.

## 8. Data handling and privacy

* Identifiers are `P01`…`P10`. **No names, contact details, signatures, device serials or images of
  participants are recorded in this repository.**
* The consent form may be signed on paper; the paper stays with the researcher and is **not** scanned
  into the repository.
* Per-participant result sheets live in `docs/usability/results/` which is **git-ignored**. Only
  aggregate results (counts, means, themes) are published, in
  `docs/usability_evaluation_report.md`.
* Audio recordings, if any, stay outside the repository and are deleted after transcription; the
  transcript contains no names.
* Participants may withdraw at any time; on withdrawal their sheet is deleted and not summarised.

## 9. Instrument files (created in this iteration, no data)

| File | Purpose |
| --- | --- |
| `docs/usability_evaluation_protocol.md` | this protocol |
| `docs/usability/consent_script.md` | what the facilitator reads before starting |
| `docs/usability/templates/participant_intake.md` | blank per-participant sheet (demographics, consent flags) |
| `docs/usability/templates/session_notes.md` | blank task-by-task sheet, SUS answers and qualitative answers |
| `tools/usability/analyse_usability.py` | parser + SUS scoring + criterion evaluation for up to 10 sheets |
| `tools/usability/SELF_TEST.md` | documents the arithmetic self-test and how to run it |

The analysis script contains a `--self-test` mode that validates the SUS arithmetic and the
criterion logic against **hand-computed examples and clearly-labelled synthetic sheets that are never
published as results**. That is a code check, not a study: no participant, no session and no result
is fabricated anywhere in this repository.

## 10. Reporting

`docs/usability_evaluation_report.md` will report, whatever the outcome:

* the pre-registered criteria C1–C3, each met or not met with its measured value;
* per-task success, completion time (median and range), error counts, intervention counts and
  critical errors;
* mean and median SUS with the per-participant scores;
* the qualitative themes with counts, including the answers about `Uncertain`;
* every deviation from this protocol, with its reason and when it was decided.
