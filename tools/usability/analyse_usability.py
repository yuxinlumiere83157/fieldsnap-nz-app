#!/usr/bin/env python3
"""Usability-evaluation analysis (Iteration 4; incremental intake, protocol v1.2).

Reads the filled-in per-participant session sheets from docs/usability/results/ and produces the
aggregate figures required by docs/usability_evaluation_protocol.md: task success, completion times,
errors, interventions, critical errors, the standard SUS score, and the pre-registered criteria C1-C3.

Sessions are accumulated **one participant at a time** and the folder is read as-is, so a new sheet is
picked up simply by re-running the script. The recruitment target is five (protocol v1.2). Below that
target the output is an INTERIM, individual report: the participant's own results and SUS score are
shown, while C1-C3 are marked `not_evaluable` rather than met or not met, and the summary states that
the evaluation is not complete. At or above the target the criteria get real verdicts and the status
becomes COMPLETE. A single participant is therefore never reported as a usability verdict.

No results exist when this was written, and the script does not invent any: with an empty results
folder it reports "no sessions found" and exits without a report. `--self-test` validates the
arithmetic, the interim/final boundary and the criterion logic against hand-computed synthetic sheets
in a temporary directory; that is a code check, never published as study data (see
docs/usability/SELF_TEST.md).

Usage:
  python3 tools/usability/analyse_usability.py            # analyse the sheets present, print a summary
  python3 tools/usability/analyse_usability.py --json out.json
  python3 tools/usability/analyse_usability.py --self-test
"""
from __future__ import annotations

import argparse, json, math, pathlib, re, statistics, sys, tempfile

REPO = pathlib.Path(__file__).resolve().parents[2]
RESULTS = REPO / "docs" / "usability" / "results"

SUS_ITEMS = [
    "I think that I would like to use this system frequently.",
    "I found the system unnecessarily complex.",
    "I thought the system was easy to use.",
    "I think that I would need the support of a technical person to be able to use this system.",
    "I found the various functions in this system were well integrated.",
    "I thought there was too much inconsistency in this system.",
    "I would imagine that most people would learn to use this system very quickly.",
    "I found the system very cumbersome to use.",
    "I felt very confident using the system.",
    "I needed to learn a lot of things before I could get going with this system.",
]

# Recruitment target (protocol v1.2). The lecturer clarified that no fixed participant count applies
# and that at least five classmates are recommended, so five is the target and the point at which
# C1-C3 become evaluable. Pass marks are unchanged: >= 90 %, mean SUS >= 70, zero critical errors.
TARGET_PARTICIPANTS = 5
C1_MIN_RATE = 0.90      # >= 90 % of the recruited sample, applied as 5/5 at n = 5
C2_MIN_MEAN_SUS = 70.0
C3_MAX_CRITICAL = 0

# Criterion verdicts. NOT_EVALUABLE is deliberately distinct from NOT_MET: an incomplete sample must
# never be reported as a failed criterion (or, worse, an achieved one).
MET = "met"
NOT_MET = "not_met"
NOT_EVALUABLE = "not_evaluable"


def sus_score(answers: list[int]) -> float:
    """Standard SUS scoring: odd items contribute (x-1), even items (5-x), sum * 2.5."""
    if len(answers) != 10:
        raise ValueError(f"SUS requires exactly 10 answers, got {len(answers)}")
    if any(a < 1 or a > 5 for a in answers):
        raise ValueError("SUS answers must be 1..5")
    total = 0
    for index, answer in enumerate(answers, start=1):
        total += (answer - 1) if index % 2 == 1 else (5 - answer)
    return total * 2.5


def _table_value(text: str, field: str) -> str | None:
    """Reads `| field | value |` from a markdown table, tolerating blank values."""
    pattern = re.compile(r"^\|\s*" + re.escape(field) + r"\s*\|(.*)\|\s*$", re.IGNORECASE | re.MULTILINE)
    match = pattern.search(text)
    if not match:
        return None
    return match.group(1).strip()


YES = {"yes", "y", "true"}
NO = {"no", "n", "false"}


def _yes(value: str | None) -> bool | None:
    """Exact yes/no only.

    `startswith('y')` used to accept anything beginning with y - including the template's own
    "yes / no" placeholder, a blank cell that later got a stray character, or "yeah maybe". A sheet
    that has not actually been filled in must not be able to pass as a participant, so any value that
    is not exactly yes/no is now an error (see `validate_session`).
    """
    if value is None:
        return None
    token = value.strip().lower()
    if token in YES:
        return True
    if token in NO:
        return False
    return None


def _number(value: str | None) -> float | None:
    if value is None:
        return None
    match = re.search(r"-?\d+(?:\.\d+)?", value)
    return float(match.group()) if match else None


REQUIRED_TASK_FIELDS = ("completed", "success_without_intervention", "completion_time_s",
                        "intervention_count", "critical_error")


def validate_session(session: dict) -> list[str]:
    """Returns the reasons this sheet cannot be used. Empty list == valid."""
    errors: list[str] = []
    if session.get("participant_id") in (None, "", "?"):
        errors.append("missing participant id")
    for task in ("task1", "task2", "task3"):
        block = session["tasks"].get(task)
        if block is None:
            errors.append(f"{task}: missing section")
            continue
        for field in REQUIRED_TASK_FIELDS:
            if block.get(field) is None:
                errors.append(f"{task}: {field} is missing or not an exact yes/no or number")
        if block.get("completion_time_s") is not None and block["completion_time_s"] <= 0:
            errors.append(f"{task}: completion_time_s must be positive")

    answers = session.get("sus_answers") or []
    if len(answers) != 10 or any(a is None for a in answers):
        missing = [i + 1 for i, a in enumerate(answers) if a is None] if answers else list(range(1, 11))
        errors.append(
            "SUS: incomplete questionnaire "
            f"({len([a for a in answers if a is not None])}/10 answered; missing {missing}); "
            "the standard permits no partial scoring, so the questionnaire is invalid")
    elif any(not (1 <= a <= 5) for a in answers):
        errors.append("SUS: answers must be within 1..5")
    return errors


def parse_session(text: str) -> dict:
    """Extracts the protocol's fields from one filled-in session sheet."""
    out: dict = {}

    out["participant_id"] = _table_value(text, "Participant id") or "?"
    out["completed"] = _yes(_table_value(text, "completed"))
    out["success_without_intervention"] = _yes(_table_value(text, "success_without_intervention"))
    out["intervention_count"] = _number(_table_value(text, "intervention_count"))
    out["critical_error"] = _yes(_table_value(text, "critical_error"))
    out["completion_time_s"] = _number(_table_value(text, "completion_time_s"))
    out["learning_card_opened"] = _yes(_table_value(text, "learning_card_opened"))
    out["path_taken"] = _table_value(text, "path_taken")
    out["recovered_to_result"] = _yes(_table_value(text, "recovered_to_result"))
    out["found_history"] = _yes(_table_value(text, "found_history"))
    out["deleted_entry"] = _yes(_table_value(text, "deleted_entry"))

    # The sheet repeats some field names per task, so take them per task block.
    blocks = _split_task_blocks(text)
    per_task = {}
    for task, block in blocks.items():
        per_task[task] = {
            "completed": _yes(_table_value(block, "completed")),
            "success_without_intervention": _yes(_table_value(block, "success_without_intervention")),
            "completion_time_s": _number(_table_value(block, "completion_time_s")),
            "intervention_count": _number(_table_value(block, "intervention_count")) or 0,
            "critical_error": _yes(_table_value(block, "critical_error")) or False,
            "path_taken": _table_value(block, "path_taken"),
            "recovered_to_result": _yes(_table_value(block, "recovered_to_result")),
            "learning_card_opened": _yes(_table_value(block, "learning_card_opened")),
            "found_history": _yes(_table_value(block, "found_history")),
            "deleted_entry": _yes(_table_value(block, "deleted_entry")),
        }
    out["tasks"] = per_task

    # SUS: rows in the SUS table are `| n | item | answer |`
    sus_block = text.split("SUS answers", 1)[-1] if "SUS answers" in text else ""
    answers: list[int | None] = []
    for number in range(1, 11):
        match = re.search(r"^\|\s*" + str(number) + r"\s*\|[^|]*\|([^|]*)\|\s*$", sus_block, re.MULTILINE)
        answers.append(int(_number(match.group(1))) if match and _number(match.group(1)) else None)
    out["sus_answers"] = answers
    out["sus_valid"] = all(a is not None for a in answers) and all(1 <= int(a) <= 5 for a in answers if a)
    out["sus_score"] = (sus_score([int(a) for a in answers])
                        if out["sus_valid"] else None)
    out["validation_errors"] = validate_session(out)
    out["valid"] = not out["validation_errors"]
    return out


def _split_task_blocks(text: str) -> dict[str, str]:
    """Splits the sheet on the '## Task n' headings."""
    blocks: dict[str, str] = {}
    matches = list(re.finditer(r"^##\s*Task\s*(\d).*$", text, re.MULTILINE))
    for i, match in enumerate(matches):
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        blocks[f"task{match.group(1)}"] = text[start:end]
    return blocks


def required_successes(n: int) -> int:
    """The count of Task 1 successes that satisfies >= 90 % at this sample size.

    At the five-participant target 90 % of 5 = 4.5, so the requirement is 5/5: all five participants
    must complete Task 1 unaided. Deriving this from the target instead of hard-coding "5 of 5" keeps
    the requirement and the percentage from drifting apart if the sample size changes.
    """
    return math.ceil(C1_MIN_RATE * n)


def _criterion(state: str, requirement: str, measured, met: bool | None, note: str = "") -> dict:
    return {"requirement": requirement, "measured": measured, "state": state, "met": met, "note": note}


def evaluate(sessions: list[dict]) -> dict:
    """Aggregates sessions and applies the pre-registered criteria C1-C3.

    Only sheets that pass `validate_session` count as participants. Invalid sheets are reported with
    their reasons and are excluded from every denominator, so a blank or half-filled template can
    never contribute a success.

    Incremental behaviour (v1.2): sessions are accumulated one at a time. Below the recruitment
    target the result is an INTERIM, individual report - the criteria are `not_evaluable`, not "met"
    and not "not met" - so a single participant can never pass as a completed evaluation. At or above
    the target every criterion gets its verdict and `met` is populated.
    """
    total = len(sessions)
    invalid = [s for s in sessions if not s.get("valid", False)]
    sessions = [s for s in sessions if s.get("valid", False)]
    n = len(sessions)
    if n == 0:
        return {"status": "NO_SESSIONS", "sessions_submitted": total, "sessions_valid": 0,
                "recruitment": {"target": TARGET_PARTICIPANTS, "participants": 0,
                                "remaining": TARGET_PARTICIPANTS, "target_reached": False},
                "criteria": {},
                "invalid_sheets": [{"participant_id": s.get("participant_id"),
                                    "errors": s.get("validation_errors", [])} for s in invalid],
                "note": "no valid sessions found; invalid sheets are listed and contribute nothing"}

    task1 = [s["tasks"].get("task1", {}) for s in sessions]
    successes = sum(1 for t in task1 if t.get("success_without_intervention") is True)
    times = [t["completion_time_s"] for t in task1 if t.get("completion_time_s") is not None]
    critical = sum(1 for s in sessions for t in s["tasks"].values() if t.get("critical_error"))
    interventions = sum(t.get("intervention_count") or 0 for s in sessions for t in s["tasks"].values())
    sus_scores = [s["sus_score"] for s in sessions if s.get("sus_score") is not None]
    mean_sus = round(statistics.fmean(sus_scores), 2) if sus_scores else None

    complete = n >= TARGET_PARTICIPANTS
    need = required_successes(n)
    note_incomplete = (f"interim: {n} of {TARGET_PARTICIPANTS} participants recruited; "
                       f"criterion not yet evaluable")

    def verdict(passed: bool) -> str:
        """The state of one criterion: no verdict until the target sample size exists."""
        if not complete:
            return NOT_EVALUABLE
        return MET if passed else NOT_MET

    c1_met = successes >= need
    c2_met = mean_sus is not None and mean_sus >= C2_MIN_MEAN_SUS
    c3_met = critical == C3_MAX_CRITICAL

    criteria = {
        "C1_task1_success_without_intervention": _criterion(
            verdict(c1_met),
            f">= {int(C1_MIN_RATE * 100)}% of {TARGET_PARTICIPANTS} (i.e. {required_successes(TARGET_PARTICIPANTS)}/{TARGET_PARTICIPANTS})",
            f"{successes}/{n}",
            c1_met if complete else None,
            "" if complete else note_incomplete),
        "C2_mean_sus": _criterion(
            verdict(c2_met), f">= {C2_MIN_MEAN_SUS}", mean_sus,
            c2_met if complete else None,
            "" if complete else note_incomplete),
        "C3_critical_errors": _criterion(
            verdict(c3_met), f"== {C3_MAX_CRITICAL}", critical,
            c3_met if complete else None,
            "" if complete else note_incomplete),
    }

    report = {
        "status": "COMPLETE" if complete else "INTERIM",
        "recruitment": {
            "target": TARGET_PARTICIPANTS,
            "participants": n,
            "remaining": max(0, TARGET_PARTICIPANTS - n),
            "target_reached": complete,
            "note": ("recruitment target reached; this is the final evaluation"
                     if complete else
                     f"n = {n}, recruitment ongoing: this is an individual interim result, "
                     f"not a usability verdict. {TARGET_PARTICIPANTS - n} more participant(s) needed "
                     f"before C1-C3 can be evaluated."),
        },
        "individual_results": {s["participant_id"]: individual_report(s) for s in sessions},
        "sessions_submitted": total,
        "sessions_valid": n,
        "invalid_sheets": [{"participant_id": s.get("participant_id"),
                            "errors": s.get("validation_errors", [])} for s in invalid],
        "task1_success_without_intervention": successes,
        "task1_completion_time_s": {
            "median": statistics.median(times) if times else None,
            "min": min(times) if times else None,
            "max": max(times) if times else None,
            "n": len(times),
        },
        "interventions_total": interventions,
        "critical_errors_total": critical,
        "sus": {
            "mean": mean_sus,
            "median": statistics.median(sus_scores) if sus_scores else None,
            "per_participant": {s["participant_id"]: s["sus_score"] for s in sessions
                                if s.get("sus_score") is not None},
        },
        "criteria": criteria,
    }
    if not complete:
        report["interim"] = {
            "participants": n,
            "target": TARGET_PARTICIPANTS,
            "individual_results": report["individual_results"],
            "message": (f"INTERIM: n = {n} of {TARGET_PARTICIPANTS}. These are one participant's "
                        f"results, not a completed evaluation. No NFR6 criterion is claimed met."),
        }
    return report


def individual_report(session: dict) -> dict:
    """One participant's own results, for the interim report and the final per-participant table."""
    tasks = {}
    for name, block in session.get("tasks", {}).items():
        tasks[name] = {
            "completed": block.get("completed"),
            "success_without_intervention": block.get("success_without_intervention"),
            "completion_time_s": block.get("completion_time_s"),
            "intervention_count": block.get("intervention_count"),
            "critical_error": block.get("critical_error"),
        }
    return {
        "tasks": tasks,
        "sus_score": session.get("sus_score"),
        "sus_valid": session.get("sus_valid"),
        "critical_errors": sum(1 for t in session.get("tasks", {}).values() if t.get("critical_error")),
    }


def load_sessions(folder: pathlib.Path) -> list[dict]:
    sessions = []
    for path in sorted(folder.glob("*_session.md")):
        sessions.append(parse_session(path.read_text()))
    return sessions


# --------------------------------------------------------------------------------------------
# self-test: synthetic sheets, hand-computed expectations, temporary directory only
# --------------------------------------------------------------------------------------------

def _sheet(pid: str, task1_success: bool, sus: list[int], critical: bool = False,
           t1_time: int = 60) -> str:
    answers = "\n".join(f"| {i} | {SUS_ITEMS[i-1]} | {sus[i-1]} |" for i in range(1, 11))
    return f"""# Session notes sheet

| Participant id | {pid} |

## Task 1 — first identification and learning card

| Field | Value |
| --- | --- |
| completion_time_s | {t1_time} |
| completed | yes |
| success_without_intervention | {'yes' if task1_success else 'no'} |
| intervention_count | {0 if task1_success else 1} |
| critical_error | {'yes' if critical else 'no'} |

## Task 2 — unsuitable result and recovery

| Field | Value |
| --- | --- |
| completion_time_s | 45 |
| completed | yes |
| success_without_intervention | yes |
| intervention_count | 0 |
| critical_error | no |

## Task 3 — history entry

| Field | Value |
| --- | --- |
| completion_time_s | 30 |
| completed | yes |
| success_without_intervention | yes |
| intervention_count | 0 |
| critical_error | no |

## SUS answers (1 = strongly disagree … 5 = strongly agree)

| # | Item (verbatim from protocol §6) | Answer |
| --- | --- | --- |
{answers}
"""


def self_test() -> int:
    failures: list[str] = []

    def check(label: str, got, want) -> None:
        if got != want:
            failures.append(f"{label}: got {got!r}, want {want!r}")
        else:
            print(f"  ok  {label}")

    print("SUS arithmetic")
    # Note the standard scale's symmetry: answering 5 to every item scores 50, not 100, because the
    # even-numbered items are negatively worded. A perfect 100 requires 5 on the odd items and 1 on
    # the even ones. These expectations were corrected after the first self-test run caught the
    # mistake in the expectations (the scoring function was right).
    check("all 5s -> 50 (negatively worded items cancel)", sus_score([5] * 10), 50.0)
    check("best possible pattern -> 100", sus_score([5, 1] * 5), 100.0)
    check("worst possible pattern -> 0", sus_score([1, 5] * 5), 0.0)
    # Hand-computed: odd items (2,4,5,5,5) -> (1,3,4,4,4) = 16; even items (4,4,2,2,1) ->
    # (1,1,3,3,4) = 12; total 28; 28 * 2.5 = 70.0. Both this and the 82.5 expectation were wrong in
    # the first draft; the function was right and the test caught the arithmetic slip.
    check("hand-computed mixed -> 70.0", sus_score([2, 4, 4, 4, 5, 2, 5, 2, 5, 1]), 70.0)

    print("incremental intake: one participant is an interim result, not a verdict")
    with tempfile.TemporaryDirectory() as tmp:
        folder = pathlib.Path(tmp)
        # P01 alone, all three tasks successful, SUS 92.5 ([5,2,5,2,5,1,5,2,5,1] = 37 * 2.5). This is
        # the state the study is in after the first real session, and it must NOT be reported as
        # criteria met.
        (folder / "P01_session.md").write_text(_sheet("P01", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("one sheet -> valid session counted", result["sessions_valid"], 1)
        check("one sheet -> INTERIM status", result["status"], "INTERIM")
        check("one sheet -> target not reached", result["recruitment"]["target_reached"], False)
        check("one sheet -> remaining is 4", result["recruitment"]["remaining"], 4)
        check("one sheet -> C1 not evaluable",
              result["criteria"]["C1_task1_success_without_intervention"]["state"], NOT_EVALUABLE)
        check("one sheet -> C1 met is not claimed",
              result["criteria"]["C1_task1_success_without_intervention"]["met"], None)
        check("one sheet -> C2 not evaluable", result["criteria"]["C2_mean_sus"]["state"], NOT_EVALUABLE)
        check("one sheet -> C3 not evaluable",
              result["criteria"]["C3_critical_errors"]["state"], NOT_EVALUABLE)
        check("one sheet -> individual result reported for P01",
              result["individual_results"]["P01"]["sus_score"], 92.5)
        check("one sheet -> P01 task1 unaided",
              result["individual_results"]["P01"]["tasks"]["task1"]["success_without_intervention"], True)
        check("one sheet -> interim block present", "interim" in result, True)
        check("one sheet -> interim message names the shortfall",
              "1 of 5" in result["interim"]["message"], True)
        check("one sheet -> human summary says INTERIM",
              format_summary(result).startswith("*** INTERIM REPORT"), True)
        check("one sheet -> human summary never says criteria MET",
              "-> MET" in format_summary(result), False)

    print("interim accumulation and the 90% boundary at the five-participant target")
    with tempfile.TemporaryDirectory() as tmp:
        folder = pathlib.Path(tmp)
        for i in range(1, 5):   # four participants, all successful
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("four sheets -> still INTERIM (90% of 4 would be 4/4, but target is 5)",
              result["status"], "INTERIM")
        check("four sheets -> C1 still not evaluable",
              result["criteria"]["C1_task1_success_without_intervention"]["state"], NOT_EVALUABLE)

        # Five participants, four successful: that is 80%, below the >= 90% requirement.
        for i in range(1, 6):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", i <= 4, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("five sheets -> COMPLETE status", result["status"], "COMPLETE")
        check("five sheets -> target reached", result["recruitment"]["target_reached"], True)
        check("required successes at n=5 is 5", required_successes(5), 5)
        check("4/5 measures as 4/5",
              result["criteria"]["C1_task1_success_without_intervention"]["measured"], "4/5")
        check("4/5 is NOT MET (80% < 90%)",
              result["criteria"]["C1_task1_success_without_intervention"]["state"], NOT_MET)
        check("4/5 -> met is False",
              result["criteria"]["C1_task1_success_without_intervention"]["met"], False)
        check("no interim block once complete", "interim" in result, False)

        # Five successful participants: 5/5 = 100% >= 90%, so C1 is met.
        for i in range(1, 6):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("5/5 -> C1 MET", result["criteria"]["C1_task1_success_without_intervention"]["state"], MET)
        check("5/5 -> C1 met is True",
              result["criteria"]["C1_task1_success_without_intervention"]["met"], True)
        check("5/5 -> C2 MET (mean SUS 92.5)", result["criteria"]["C2_mean_sus"]["state"], MET)
        check("5/5 -> C3 MET (0 critical)", result["criteria"]["C3_critical_errors"]["state"], MET)
        check("all three met at target",
              all(c["state"] == MET for c in result["criteria"].values()), True)
        check("complete summary does not say INTERIM",
              "INTERIM" in format_summary(result), False)
        check("task1 median time", result["task1_completion_time_s"]["median"], 60)

        # Lower the SUS below the threshold -> only C2 flips.
        for i in range(1, 6):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", True, [4, 3, 4, 3, 4, 3, 4, 3, 4, 3]))
        result = evaluate(load_sessions(folder))
        check("C2 NOT MET when SUS < 70", result["criteria"]["C2_mean_sus"]["state"], NOT_MET)
        check("C1 still MET", result["criteria"]["C1_task1_success_without_intervention"]["state"], MET)

        # One critical error -> only C3 flips.
        for i in range(1, 6):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1], critical=(i == 3)))
        result = evaluate(load_sessions(folder))
        check("C3 NOT MET with one critical error",
              result["criteria"]["C3_critical_errors"]["state"], NOT_MET)
        check("critical error counted once", result["critical_errors_total"], 1)

        # empty folder -> no invented result
        empty = folder / "empty"
        empty.mkdir()
        result = evaluate(load_sessions(empty))
        check("empty folder reports no valid sessions", result["sessions_valid"], 0)
        check("empty folder has no criteria verdict", result["criteria"], {})
        check("empty folder is not COMPLETE", result["status"], "NO_SESSIONS")

    print("validation: a blank template is not a participant")
    template = REPO / "docs" / "usability" / "templates" / "session_notes.md"
    check("blank template exists", template.exists(), True)
    parsed = parse_session(template.read_text())
    check("blank template is invalid", parsed["valid"], False)
    check("blank template has no SUS score", parsed["sus_score"], None)
    check("blank template reports SUS as incomplete",
          any("SUS: incomplete" in e for e in parsed["validation_errors"]), True)
    check("blank template reports missing task fields",
          any("task1: completed is missing" in e for e in parsed["validation_errors"]), True)

    with tempfile.TemporaryDirectory() as tmp:
        folder = pathlib.Path(tmp)
        (folder / "P01_session.md").write_text(template.read_text())
        result = evaluate(load_sessions(folder))
        check("blank template counts as zero valid sessions", result["sessions_valid"], 0)
        check("blank template contributes no success",
              result.get("task1_success_without_intervention", 0), 0)
        check("blank template is listed as invalid", len(result["invalid_sheets"]), 1)
        check("blank template leaves C1 unmet",
              result["criteria"], {})

    print("validation: loose yes/no values are rejected")
    for label, value in (("template placeholder 'yes / no'", "yes / no"),
                         ("empty", ""),
                         ("chatty 'yep'", "yep"),
                         ("uncertain 'maybe'", "maybe")):
        sheet = _sheet("P01", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]).replace(
            "| completed | yes |", f"| completed | {value} |", 1)
        check(f"{label} invalidates the sheet", parse_session(sheet)["valid"], False)

    print("validation: a missing SUS answer invalidates that questionnaire only")
    incomplete = _sheet("P01", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]).replace(
        "| 7 |", "| 7 |", 1).replace(SUS_ITEMS[6] + " | 5 |", SUS_ITEMS[6] + " |  |")
    parsed = parse_session(incomplete)
    check("incomplete SUS has no score", parsed["sus_score"], None)
    check("incomplete SUS lists the missing item",
          any("missing [7]" in e for e in parsed["validation_errors"]), True)

    print("validation: valid sheets still aggregate")
    with tempfile.TemporaryDirectory() as tmp:
        folder = pathlib.Path(tmp)
        for i in range(1, 6):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("five valid sheets", result["sessions_valid"], 5)
        check("C1 MET with 5/5",
              result["criteria"]["C1_task1_success_without_intervention"]["state"], MET)

    print()
    if failures:
        print(f"SELF-TEST FAILURES ({len(failures)}):")
        for failure in failures:
            print("  -", failure)
        return 1
    print("self-test passed (arithmetic and criterion logic; no study data involved)")
    return 0


def format_summary(summary: dict) -> str:
    """Human-readable rendering of the report, interim or final.

    Deliberately refuses to phrase an incomplete sample as a result: below the target it prints
    INTERIM and says the criteria are not yet evaluable.
    """
    lines: list[str] = []
    status = summary.get("status")
    recruitment = summary.get("recruitment", {})
    n = summary.get("sessions_valid", 0)
    target = recruitment.get("target", TARGET_PARTICIPANTS)

    if status == "NO_SESSIONS":
        lines.append("NO SESSIONS YET")
        lines.append(f"  valid session sheets: 0 of {target} target")
        lines.append("  Nothing to report. This is the expected state before the first session; "
                     "no result is invented.")
        invalid = summary.get("invalid_sheets") or []
        if invalid:
            lines.append(f"  {len(invalid)} sheet(s) present but invalid:")
            for sheet in invalid:
                lines.append(f"    - {sheet['participant_id']}: {len(sheet['errors'])} problem(s)")
        return "\n".join(lines)

    if status == "INTERIM":
        lines.append(f"*** INTERIM REPORT - n = {n} of {target} ***")
        lines.append("    Individual participant result, NOT a usability verdict.")
        lines.append("    C1-C3 are not yet evaluable. Recruitment is ongoing.")
    else:
        lines.append(f"FINAL EVALUATION - n = {n} (target {target} reached)")

    if summary.get("sessions_valid") != summary.get("sessions_submitted"):
        lines.append(f"  invalid sheets excluded: "
                     f"{summary['sessions_submitted'] - summary['sessions_valid']}")

    lines.append("")
    lines.append("Per-participant results")
    for pid, result in (summary.get("individual_results") or {}).items():
        lines.append(f"  {pid}: SUS {result['sus_score']}"
                     f"{'' if result['sus_valid'] else ' (questionnaire invalid)'}"
                     f", critical errors {result['critical_errors']}")
        for name in ("task1", "task2", "task3"):
            block = result["tasks"].get(name)
            if not block:
                continue
            lines.append(f"    {name}: completed={_tick(block['completed'])} "
                         f"unaided={_tick(block['success_without_intervention'])} "
                         f"time={block['completion_time_s']}s "
                         f"interventions={block['intervention_count']} "
                         f"critical={_tick(block['critical_error'])}")

    lines.append("")
    lines.append("Criteria")
    for name, criterion in summary.get("criteria", {}).items():
        verdict = criterion["state"]
        if verdict == MET:
            verdict = "MET"
        elif verdict == NOT_MET:
            verdict = "NOT MET"
        else:
            verdict = "NOT YET EVALUABLE"
        lines.append(f"  {name}")
        lines.append(f"    requirement {criterion['requirement']}, "
                     f"measured {criterion['measured']} -> {verdict}")
        if criterion.get("note"):
            lines.append(f"    {criterion['note']}")

    if status == "INTERIM":
        lines.append("")
        lines.append(f"  {recruitment.get('note', '')}")
        lines.append("")
        lines.append("  Do NOT report NFR6 as met or as missed on this sample. Add the remaining "
                     "sessions and re-run; the criteria become evaluable at "
                     f"{target} valid sessions.")
    return "\n".join(lines)


def _tick(value) -> str:
    return {True: "yes", False: "no", None: "?"}.get(value, "?")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--results", default=str(RESULTS))
    parser.add_argument("--json", default=None)
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    folder = pathlib.Path(args.results)
    sessions = load_sessions(folder)
    if not sessions:
        print(f"no sessions found in {folder}")
        print("This is expected before the study runs. Fill in sheets from "
              "docs/usability/templates/ and re-run; nothing is fabricated here.")
        return 0

    summary = evaluate(sessions)
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(summary, indent=2))
    print(format_summary(summary))
    if summary.get("sessions_valid", 0) == 0:
        invalid = summary.get("invalid_sheets") or []
        print()
        print("No valid session sheets: every sheet failed validation. No report is produced.")
        for sheet in invalid:
            print(f"  {sheet['participant_id']}:")
            for problem in sheet["errors"]:
                print(f"    - {problem}")
        return 2
    if args.json:
        print(f"\nJSON written to {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
