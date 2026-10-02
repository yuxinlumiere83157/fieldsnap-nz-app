# Usability evaluation report

**Status: `n = 0` — no participant data exists. Recruitment not started. No criterion is claimed met
or missed.**

This report is the published output of `docs/usability_evaluation_protocol.md` (**v1.2**). It is filled
in incrementally as sessions are run. Until the recruitment target of **five** valid sessions is
reached it stays **INTERIM** and reports only individual results; the criteria C1–C3 are
**not yet evaluable** and must not be described as met or missed.

**Fill-in convention:** every value to be supplied is written `_<...>_`. Nothing in this file is a
measurement until it has been copied from a real session sheet and cross-checked against
`tools/usability/analyse_usability.py`. No number here may be estimated, extrapolated or invented.

---

## 1. How each update is produced

```sh
python3 tools/usability/analyse_usability.py                 # human-readable summary
python3 tools/usability/analyse_usability.py --json artifacts/usability_results.json
```

The script reads whatever sheets exist in `docs/usability/results/` (git-ignored) and prints
`status: INTERIM` below five valid sessions, `status: COMPLETE` at five or more. Section 3 is copied
from `recruitment`, sections 4–6 from `sessions_valid` and `individual_results`, section 7 from
`criteria`, and section 8 from `sus`.

Two failure modes matter when reading the output:

* a **partially filled** sheet is reported as an invalid sheet and produces **no report at all**
  (exit code 2). That is by design — an incomplete sheet is not a participant. Fix the sheet, do not
  work around it;
* a **blank template** left in `docs/usability/results/` also counts as an invalid *submission*. Before
  each analysis run, make sure every file in that folder is a sheet you actually intend to count.

## 2. Scope

This study evaluates the **interface and workflow only**. The model is frozen and was not retrained,
retuned or re-evaluated for it; its measured top-1 is 0.5561, so participants will often see
`Uncertain` or a wrong species. This report says nothing about whether identifications are correct,
and no metric in it is about model accuracy.

Model/threshold state at the time of writing: model SHA-256 `e6b10afdfc97d73d…`, accept threshold
`0.37`, quality-gate thresholds `0.26 / 0.89 / 100.0` — unchanged.

## 3. Recruitment status

| | |
| --- | --- |
| Status | **INTERIM** |
| Recruited (valid sessions) | `_0_` of **5** target |
| Remaining | `_5_` |
| Target reached | **no** |
| Sessions submitted / valid | `_0_` / `_0_` |
| Invalid sheets | `_none_` |

P01 has not been run. Per protocol §10.1 this report states individual results only, and no claim is
made about NFR6 or general usability.

## 4. Per-participant task results

_Populate one row per valid session, in the order tested. Copy from `individual_results` in the script
output; do not transcribe from memory. Task times are seconds._

| Id | Task 1 done | **T1 unaided (C1)** | T1 time (s) | T2 done | T2 unaided | T2 path | T3 done | T3 unaided | Prompts (all tasks) | Critical errors |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P01 | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` |

**Task 1 completion time (n = _0_):** median `_ _` s, range `_ _`–`_ _` s.

## 5. Per-task summary

_Across all valid sessions so far. "Unaided" is the C1 measure; a task completed only after a
facilitator prompt is completed but **not** unaided._

| Task | Sessions | Completed | Completed unaided | Median time (s) | Errors |
| --- | --- | --- | --- | --- | --- |
| 1 — identify + learning card | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` |
| 2 — unsuitable photo + recovery | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` |
| 3 — history + delete | `_ _` | `_ _` | `_ _` | `_ _` | `_ _` |

Task 2 recovery paths observed: `_quality_gate: _, uncertain_then_replace: _, other: _`.

## 6. Interventions and critical errors

Facilitator interventions, total: `_0_`. For each, the task, what was done and why — in the form
*"Task 3: participant did not find the history entry; after asking, the facilitator pointed it out;
completed, not independently."* An intervention is never a reason to discard a session.

| Task | What the facilitator did | Why |
| --- | --- | --- |
| `_ _` | `_ _` | `_ _` |

Critical interaction errors (pre-registered definition, protocol §5): **`_0_`**. `yes` only for a stuck
state with no working recovery, a state lie, or unannounced data loss. A crash or unrecoverable hang
counts as a critical error and a task failure, and the session is still **not** excluded.

| Task | Definition triggered (§5) | What happened |
| --- | --- | --- |
| `_ _` | `_ _` | `_ _` |

## 7. Pre-registered criteria

No criterion is evaluable before five valid sessions exist. Each is reported as **met**, **not met**, or
**not yet evaluable** — never silently omitted.

| # | Requirement | Evaluable from | Measured | Verdict |
| --- | --- | --- | --- | --- |
| C1 | ≥ 90 % complete Task 1 **without** facilitator intervention | n ≥ 5 | `_ _` | **not yet evaluable** |
| C2 | Mean SUS ≥ 70 | n ≥ 5 | `_ _` | **not yet evaluable** |
| C3 | Zero critical interaction errors | n ≥ 5 | `_ _` | **not yet evaluable** |

At the five-participant target, 90 % of 5 is 4.5, so C1 requires **5/5**; four of five is 80 % and
does not meet it. Required counts are derived by the script, not restated here.

**Overall:** the five-participant evaluation is **not complete**. This section will carry the criterion
verdicts only when `status` becomes `COMPLETE`.

## 8. System Usability Scale

_Standard 10-item SUS, facilitator reads each item aloud once verbatim, participant marks their own
sheet. Any missing or out-of-range answer invalidates that participant's questionnaire, which is
reported rather than silently dropped._

| Id | SUS score | Valid questionnaire |
| --- | --- | --- |
| P01 | `_ _` | `_ _` |

Mean SUS `_ _` · median `_ _` · n = `_0_` · invalid questionnaires: `_0_`.

## 9. Qualitative findings

_Asked after the SUS, recorded as close to verbatim as possible. Reported as themes with the number of
participants behind each, and at least one representative quote per theme. No quotes yet._

**Q1. What was the most confusing part about using the app?**

_none yet_

**Q2. What do you understand "Uncertain" to mean?** _(probes whether abstention is understood or read
as a fault)_

_none yet_

**Q3. If you could change one thing, what first?**

_none yet_

## 10. Deviations from the protocol

Every departure, with its reason and when it was decided. Pre-dating this report: the v1.1 → v1.2
amendment (five-participant target, Task 1 stimulus replaced, interim reporting) and the session-notes
restructuring — all decided before any participant, recorded in `docs/usability/FREEZE_v1.2.md` and
`docs/post_evaluation_changes.md`.

| When | Deviation | Reason |
| --- | --- | --- |
| `_ _` | `_ _` | `_ _` |

Reset steps that could not be completed in a session go here too; such a session is still valid.

## 11. Limitations

* Convenience sample of classmates: not representative, and the small target means effectively no
  statistical power. Five participants can surface problems; they cannot establish general usability.
* The classifier abstains or errs often (top-1 0.5561). Task 2 measures how participants cope with
  that, not accuracy.
* Facilitation and note-taking are done by the same person, so timing and records are approximate.
* Whether these limitations change the conclusion is stated when the criteria are finally reported.
