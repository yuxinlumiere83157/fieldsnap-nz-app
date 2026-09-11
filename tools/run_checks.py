#!/usr/bin/env python3
"""Run the repository's checks and report pass / fail / skipped counts separately.

A skip is never counted as a pass: the Android-specific and research-only checks are allowed
to skip on a machine that cannot run them, and that has to be visible.

Usage: python3 tools/run_checks.py [--device <id>] [--json out.json]
"""
from __future__ import annotations

import argparse
import json
import pathlib
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]


def run(command: list[str], cwd: pathlib.Path) -> tuple[int, str]:
    process = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    return process.returncode, process.stdout + process.stderr


def parse_json_report(output: str) -> dict[str, int]:
    counts = {"success": 0, "failure": 0, "error": 0, "skipped": 0}
    names: dict[int, str] = {}
    hidden: dict[int, bool] = {}
    for line in output.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "testStart":
            test = event.get("test") or {}
            test_id = test.get("id")
            name = test.get("name") or "?"
            url = test.get("url") or ""
            names[test_id] = name
            # flutter also emits one synthetic "loading <file>" test per suite
            # flutter emits one synthetic "loading <file>" test per suite
            hidden[test_id] = url.endswith("loading_test.dart") or name.startswith("loading ")
        if event.get("type") == "testDone" and not hidden.get(event.get("testID")):
            result = event.get("result")
            if event.get("skipped"):
                counts["skipped"] += 1
            elif result in counts:
                counts[result] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--device", default=None,
                        help="device id for the on-device integration test (e.g. emulator-5554)")
    parser.add_argument("--json", default=None, help="write the summary here")
    args = parser.parse_args()

    suites: list[tuple[str, list[str], bool]] = [
        ("analyze", ["flutter", "analyze"], True),
        # deterministic suites only; the tagged integration tests run in their own suite
        ("unit+widget", ["flutter", "test", "--exclude-tags", "integration",
                         "--reporter", "json"], False),
        ("host integration", ["flutter", "test", "--tags", "integration", "--reporter", "json"], False),
    ]
    if args.device:
        suites.append((
            f"on-device integration ({args.device})",
            ["flutter", "test", "integration_test/on_device_inference_test.dart",
             "-d", args.device, "--reporter", "json"],
            False,
        ))

    summary: dict[str, dict] = {}
    exit_code = 0
    for label, command, is_analyze in suites:
        code, output = run(command, REPO)
        if is_analyze:
            clean = "No issues found!" in output
            summary[label] = {"exit": code, "clean": clean,
                              "detail": "No issues found!" if clean else output.strip()[-400:]}
            print(f"{label:32} exit={code} {'clean' if clean else 'ISSUES'}")
            if code != 0 or not clean:
                exit_code = 1
            continue
        counts = parse_json_report(output)
        summary[label] = {"exit": code, **counts}
        status = "ok" if (code == 0 and not counts["failure"] and not counts["error"]
                          and counts["success"] > 0) else "FAILED"
        print(f"{label:32} exit={code} {status} passed={counts['success']} "
              f"failed={counts['failure']} errors={counts['error']} skipped={counts['skipped']}")
        if status != "ok":
            exit_code = 1

    if args.json:
        pathlib.Path(args.json).write_text(json.dumps(summary, indent=2))
        print(f"summary written to {args.json}")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
