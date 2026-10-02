#!/usr/bin/env python3
"""Builds a print-ready HTML pack of the usability kit forms.

The markdown forms in docs/usability/ are the source of truth and are frozen by
docs/usability/FREEZE_v1.2.md. This script only *renders* them: it never writes back, so the freeze
hashes are unaffected. The output is a single self-contained HTML file that prints to PDF from any
browser (Cmd-P), one form per page, with a facilitator briefing first.

Usage:
  python3 tools/usability/make_print_pack.py            # writes docs/usability/printable/print-pack.html
  python3 tools/usability/make_print_pack.py --open     # and opens it in the default browser
"""
from __future__ import annotations

import argparse, html, pathlib, re, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
KIT = REPO / "docs" / "usability"
OUT_DIR = KIT / "printable"

# (page title, source markdown relative to KIT, audience note)
SHEETS = [
    ("Reset checklist", "reset_checklist.md",
     "Facilitator · fill in before the participant arrives"),
    ("Consent script", "consent_script.md",
     "Facilitator · read aloud, one copy"),
    ("Intake sheet", "templates/participant_intake.md",
     "Facilitator · initials only, never a name"),
    ("Session notes", "templates/session_notes.md",
     "Facilitator · tasks, timings, interventions"),
    ("SUS form", "SUS_form.md",
     "PARTICIPANT · hand over, do not look at the answers"),
]

BRIEFING = """
<h1>P01 session briefing</h1>
<p class="lede">One page, read it once before you sit down with the participant. Everything below is
from the pre-registered protocol (v1.2); nothing here is new instruction.</p>

<h2>The run, in order — about 25 minutes</h2>
<table class="timeline">
<tr><th>Stage</th><th>~Time</th><th>What you do</th></tr>
<tr><td>Consent and intro</td><td>2–3 min</td><td>Read the consent script aloud. Key line: <strong>“We are testing the app, not you — if something is confusing, that is exactly what I need to find out.”</strong> Record verbal consent, then they are <code>P01</code>.</td></tr>
<tr><td>Short orientation</td><td>~30 s</td><td>“This app suggests a species from a photo you choose.” <strong>No buttons, no task answers, no demo.</strong></td></tr>
<tr><td>Task 1</td><td>10–15 min</td><td>Read the task text once. Start the timer as they begin.</td></tr>
<tr><td>Task 2</td><td></td><td>Read once. <strong>Do not warn them the photo is unsuitable.</strong></td></tr>
<tr><td>Task 3</td><td></td><td>Read once.</td></tr>
<tr><td>SUS</td><td>3–5 min</td><td>Read each of the ten items aloud once. They mark the sheet privately.</td></tr>
<tr><td>Three questions</td><td>3–5 min</td><td>Write their wording down close to verbatim. Thank them.</td></tr>
</table>

<h2>Two things that matter most</h2>
<ol class="big">
<li><strong>The learning card is inside the result panel on the same screen.</strong> Do not send them
looking for a separate “open page” control — there isn’t one.</li>
<li><strong>When they get stuck, help them and write it down.</strong> Default reply: “Try whatever you
would naturally do.” If they genuinely need help, give it and record it, e.g.
<em>“Task 3: did not find the history entry; after asking, the facilitator pointed it out; completed,
not independently.”</em> That is still a valid session — not a failed participant.</li>
</ol>

<h2>Record for every task</h2>
<p>completed · independently completed · time · what you had to prompt · any error. If the app crashes
or hangs, that is a <strong>task failure and a critical error</strong> — record it against the task it
interrupted and carry on. It is never a reason to drop the participant.</p>

<h2>SUS discipline</h2>
<p>Read the ten items <strong>once each, in order, verbatim</strong>. Do not paraphrase, re-order,
explain or interpret. If they ask what an item means, repeat the item and add nothing, and note that
they asked. Do not look at their answers until they hand the sheet back. Do not explain why a feature
exists while they are answering.</p>

<h2>Before they arrive — tick these</h2>
<ul class="checks">
<li>Reset run, history empty, capture screen shows “No image selected yet”</li>
<li>Both fixed task images visible in the picker</li>
<li>Personal photos in DCIM/Camera still present</li>
<li>Timer ready; these printed sheets on the table</li>
</ul>

<p class="foot">Participant id <code>P01</code> · build under test written on the intake sheet ·
no names, no contact details, no photos of the participant on any sheet.</p>
"""

CSS = """
:root { --ink:#1a1a1a; --muted:#5a5a5a; --line:#c9c9c9; --accent:#1f5d3a; }
* { box-sizing:border-box; }
body { font:11.5pt/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;
       color:var(--ink); margin:0; padding:0; }
.sheet { page-break-before:always; padding:14mm 14mm 10mm; }
.sheet:first-of-type { page-break-before:avoid; }
.sheet-title { font-size:16pt; margin:0 0 2mm; padding-bottom:1.5mm; border-bottom:2px solid var(--accent); }
.audience { font-size:9.5pt; text-transform:uppercase; letter-spacing:.06em; color:var(--accent);
            font-weight:700; margin:0 0 5mm; }
h1 { font-size:16pt; margin:0 0 4mm; }
h2 { font-size:12.5pt; margin:6mm 0 2mm; color:var(--accent); }
h3 { font-size:11.5pt; margin:4mm 0 1.5mm; }
p, li { margin:0 0 2mm; }
ul, ol { margin:0 0 3mm; padding-left:6mm; }
ol.big > li, ul.checks > li { margin-bottom:2.5mm; }
table { border-collapse:collapse; width:100%; margin:0 0 4mm; font-size:10.5pt; }
th, td { border:1px solid var(--line); padding:1.8mm 2.2mm; text-align:left; vertical-align:top; }
th { background:#f1f5f2; font-weight:700; }
code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:9.8pt;
       background:#f3f3f3; padding:.3mm 1mm; border-radius:2px; }
blockquote { margin:0 0 3mm; padding:2mm 3mm; border-left:3px solid var(--accent);
             background:#f7faf8; font-style:italic; }
.box { font-size:13pt; }
.lede { font-size:12pt; color:var(--muted); }
.timeline th:first-child, .timeline td:first-child { width:24%; }
.timeline th:nth-child(2), .timeline td:nth-child(2) { width:12%; white-space:nowrap; }
.foot { margin-top:6mm; padding-top:2mm; border-top:1px solid var(--line);
        font-size:9.5pt; color:var(--muted); }
@media print { body { margin:0; } .sheet { padding:12mm; } @page { margin:0; } }
"""


def inline(text: str) -> str:
    """Markdown emphasis -> HTML for one table cell or line.

    Collapses newlines first: a table cell in the source may wrap across lines, and `**bold**` or
    `*italic*` spanning that wrap would otherwise miss its closing marker (which is exactly how
    "**any unanswered item invalidates this questionnaire**" once printed as raw asterisks).
    """
    t = re.sub(r"\s*\n\s*", " ", text).strip()
    t = html.escape(t)
    t = re.sub(r"`([^`]+)`", r"<code>\1</code>", t)
    t = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", t)
    t = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", t)
    t = t.replace("☐", '<span class="box">&#9744;</span>')
    return t if t.strip() else "&nbsp;"


def render_table(block: list[str]) -> str:
    rows = [[c.strip() for c in ln.strip().strip("|").split("|")] for ln in block]
    head, body = rows[0], rows[2:]
    out = ["<table><thead><tr>"]
    out += [f"<th>{inline(c)}</th>" for c in head]
    out.append("</tr></thead><tbody>")
    for r in body:
        out.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>")
    return "".join(out) + "</tbody></table>"


def md_to_html(text: str) -> str:
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        s = lines[i].strip()
        if s.startswith("|"):
            block = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                block.append(lines[i]); i += 1
            out.append(render_table(block)); continue
        if re.fullmatch(r"-{3,}|\*{3,}|_{3,}", s):
            out.append("<hr>"); i += 1; continue
        if s.startswith("#"):
            lvl = min(len(s) - len(s.lstrip("#")), 4)
            out.append(f"<h{lvl}>{inline(s.lstrip('# ').strip())}</h{lvl}>")
        elif s.startswith(">"):
            # Join consecutive quoted lines: the consent script wraps mid-quote and its emphasis
            # spans the wrap, so formatting each source line separately printed raw asterisks.
            quoted = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                quoted.append(lines[i].strip().lstrip(">").strip()); i += 1
            out.append(f"<blockquote>{inline(' '.join(quoted))}</blockquote>")
            continue
        elif re.match(r"^[-*] ", s):
            items = []
            while i < len(lines) and re.match(r"^\s*[-*] ", lines[i]):
                items.append(inline(re.sub(r"^\s*[-*] ", "", lines[i]))); i += 1
            out.append("<ul>" + "".join(f"<li>{x}</li>" for x in items) + "</ul>"); continue
        elif re.match(r"^\d+\. ", s):
            items = []
            while i < len(lines) and re.match(r"^\s*\d+\. ", lines[i]):
                items.append(inline(re.sub(r"^\s*\d+\. ", "", lines[i]))); i += 1
            out.append("<ol>" + "".join(f"<li>{x}</li>" for x in items) + "</ol>"); continue
        elif s:
            # Join consecutive non-blank lines into one paragraph before formatting. In markdown a
            # single newline inside a paragraph is just a space, so emphasis may span it; emitting
            # one <p> per source line split "**any unanswered item invalidates this<br>questionnaire**"
            # and printed the asterisks raw.
            para = []
            while i < len(lines):
                cur = lines[i].strip()
                if not cur or cur.startswith(("#", "|", ">", "- ", "* ")) or re.match(r"^\d+\. ", cur):
                    break
                para.append(cur); i += 1
            out.append(f"<p>{inline(' '.join(para))}</p>")
            if not para:          # defensive: never loop without consuming a line
                i += 1
            continue
        i += 1
    return "\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--open", action="store_true", help="open the pack in the default browser")
    args = ap.parse_args()

    missing = [src for _, src, _ in SHEETS if not (KIT / src).exists()]
    if missing:
        print("kit files missing: " + ", ".join(missing)); return 1

    parts = [f'<section class="sheet briefing"><p class="audience">Facilitator · do not hand to the participant</p>{BRIEFING}</section>']
    for title, src, audience in SHEETS:
        parts.append(
            f'<section class="sheet"><h1 class="sheet-title">{html.escape(title)}</h1>'
            f'<p class="audience">{html.escape(audience)}</p>'
            f'{md_to_html((KIT / src).read_text())}</section>')

    doc = ("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">"
           "<title>FieldSnap usability — session pack (v1.2)</title>"
           f"<style>{CSS}</style></head><body>\n" + "\n".join(parts) + "\n</body></html>\n")
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    target = OUT_DIR / "print-pack.html"
    target.write_text(doc)
    print(f"wrote {target.relative_to(REPO)}  ({len(doc)} bytes, {len(SHEETS) + 1} sheets)")
    print("Print: open it and press Cmd-P, or 'Save as PDF', paper A4/Letter, margins Default.")
    if args.open:
        subprocess.run(["open", str(target)], check=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
