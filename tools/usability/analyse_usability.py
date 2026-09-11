#!/usr/bin/env python3
"""Usability-evaluation analysis (Iteration 4).

Reads the filled-in per-participant session sheets from docs/usability/results/ and produces the
aggregate figures required by docs/usability_evaluation_protocol.md: task success, completion times,
errors, interventions, critical errors, the standard SUS score, and the pre-registered criteria C1-C3.

No results exist when this was written, and the script does not invent any: with an empty results
folder it reports "no sessions found" and exits without a report. `--self-test` validates the
arithmetic and criterion logic against hand-computed synthetic sheets in a temporary directory; that
is a code check, never published as study data (see docs/usability/SELF_TEST.md).

Usage:
  python3 tools/usability/analyse_usability.py            # analyse real sheets, print a summary
  python3 tools/usability/analyse_usability.py --json out.json
  python3 tools/usability/analyse_usability.py --self-test
"""
from __future__ import annotations

import argparse, json, pathlib, re, statistics, sys, tempfile

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

C1_MIN_SUCCESS = 9      # out of 10
C2_MIN_MEAN_SUS = 70.0
C3_MAX_CRITICAL = 0


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


def evaluate(sessions: list[dict]) -> dict:
    """Aggregates sessions and applies the pre-registered criteria C1-C3.

    Only sheets that pass `validate_session` count as participants. Invalid sheets are reported with
    their reasons and are excluded from every denominator, so a blank or half-filled template can
    never contribute a success.
    """
    total = len(sessions)
    invalid = [s for s in sessions if not s.get("valid", False)]
    sessions = [s for s in sessions if s.get("valid", False)]
    n = len(sessions)
    if n == 0:
        return {"sessions_submitted": total, "sessions_valid": 0, "criteria": {},
                "invalid_sheets": [{"participant_id": s.get("participant_id"),
                                    "errors": s.get("validation_errors", [])} for s in invalid],
                "note": "no valid sessions found; invalid sheets are listed and contribute nothing"}

    task1 = [s["tasks"].get("task1", {}) for s in sessions]
    successes = sum(1 for t in task1 if t.get("success_without_intervention") is True)
    times = [t["completion_time_s"] for t in task1 if t.get("completion_time_s") is not None]
    critical = sum(1 for s in sessions for t in s["tasks"].values() if t.get("critical_error"))
    interventions = sum(t.get("intervention_count") or 0 for s in sessions for t in s["tasks"].values())
    sus_scores = [s["sus_score"] for s in sessions if s.get("sus_score") is not None]

    criteria = {
        "C1_task1_success_without_intervention": {
            "requirement": f">= {C1_MIN_SUCCESS}/{n}",
            "measured": f"{successes}/{n}",
            "met": successes >= min(C1_MIN_SUCCESS, n) if n >= 10 else False,
            "note": "" if n >= 10 else "fewer than 10 participants recruited; criterion not yet evaluable",
        },
        "C2_mean_sus": {
            "requirement": f">= {C2_MIN_MEAN_SUS}",
            "measured": round(statistics.fmean(sus_scores), 2) if sus_scores else None,
            "met": bool(sus_scores) and statistics.fmean(sus_scores) >= C2_MIN_MEAN_SUS,
        },
        "C3_critical_errors": {
            "requirement": f"== {C3_MAX_CRITICAL}",
            "measured": critical,
            "met": critical == C3_MAX_CRITICAL,
        },
    }
    return {
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
            "mean": round(statistics.fmean(sus_scores), 2) if sus_scores else None,
            "median": statistics.median(sus_scores) if sus_scores else None,
            "per_participant": {s["participant_id"]: s["sus_score"] for s in sessions
                                if s.get("sus_score") is not None},
        },
        "criteria": criteria,
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

    print("criterion logic (synthetic sheets in a temp dir)")
    with tempfile.TemporaryDirectory() as tmp:
        folder = pathlib.Path(tmp)
        # 9 successes, mean SUS above 70, no critical errors -> all criteria met
        for i in range(1, 11):
            success = i <= 9
            sheet = _sheet(f"P{i:02d}", success, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1])
            (folder / f"P{i:02d}_session.md").write_text(sheet)
        result = evaluate(load_sessions(folder))
        check("C1 met with 9/10", result["criteria"]["C1_task1_success_without_intervention"]["met"], True)
        check("C2 met (SUS 80)", result["criteria"]["C2_mean_sus"]["met"], True)
        check("C3 met (0 critical)", result["criteria"]["C3_critical_errors"]["met"], True)
        check("task1 median time", result["task1_completion_time_s"]["median"], 60)

        # flip C1 only
        (folder / "P10_session.md").write_text(_sheet("P10", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("C1 met with 10/10", result["criteria"]["C1_task1_success_without_intervention"]["met"], True)

        (folder / "P10_session.md").write_text(_sheet("P10", False, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("C1 not met with 9/10 when one more fails", 
              result["criteria"]["C1_task1_success_without_intervention"]["measured"], "9/10")
        check("C1 met at exactly 9/10", result["criteria"]["C1_task1_success_without_intervention"]["met"], True)

        # lower the SUS below the threshold -> only C2 flips
        for i in range(1, 11):
            (folder / f"P{i:02d}_session.md").write_text(_sheet(f"P{i:02d}", True, [4, 3, 4, 3, 4, 3, 4, 3, 4, 3]))
        result = evaluate(load_sessions(folder))
        check("C2 not met when SUS < 70", result["criteria"]["C2_mean_sus"]["met"], False)
        check("C1 still met", result["criteria"]["C1_task1_success_without_intervention"]["met"], True)

        # one critical error -> only C3 flips
        for i in range(1, 11):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", True, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1], critical=(i == 3)))
        result = evaluate(load_sessions(folder))
        check("C3 not met with one critical error", result["criteria"]["C3_critical_errors"]["met"], False)
        check("critical error counted once", result["critical_errors_total"], 1)

        # empty folder -> no invented result
        empty = folder / "empty"
        empty.mkdir()
        result = evaluate(load_sessions(empty))
        check("empty folder reports no valid sessions", result["sessions_valid"], 0)
        check("empty folder has no criteria verdict", result["criteria"], {})

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
        for i in range(1, 11):
            (folder / f"P{i:02d}_session.md").write_text(
                _sheet(f"P{i:02d}", i <= 9, [5, 2, 5, 2, 5, 1, 5, 2, 5, 1]))
        result = evaluate(load_sessions(folder))
        check("ten valid sheets", result["sessions_valid"], 10)
        check("C1 met with 9/10", result["criteria"]["C1_task1_success_without_intervention"]["met"], True)

    print()
    if failures:
        print(f"SELF-TEST FAILURES ({len(failures)}):")
        for failure in failures:
            print("  -", failure)
        return 1
    print("self-test passed (arithmetic and criterion logic; no study data involved)")
    return 0


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
    if summary.get("sessions_valid", 0) == 0:
        print(json.dumps(summary, indent=2))
        print("No valid session sheets: every sheet failed validation. No report is produced.")
        return 2
    print(json.dumps(summary, indent=2))
    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(summary, indent=2))
        print(f"written to {args.json}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
