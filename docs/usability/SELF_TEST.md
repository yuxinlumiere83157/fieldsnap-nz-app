# Analysis-script self-test (code check, not a study)

`tools/usability/analyse_usability.py --self-test` verifies the script's arithmetic and criterion
logic against **hand-computed examples**. It exists so that a scoring bug is caught before any real
session, not after.

It is explicitly **not** a pilot study and produces no participant data. The synthetic sheets it uses
live in memory (or in a temporary directory) and are never written into `docs/usability/results/` or
into any report. No participant, session, SUS response or task outcome is fabricated anywhere in this
repository.

What it checks:

1. **SUS arithmetic** — the best-possible pattern (`5,1,5,1,…`) must score 100, the worst (`1,5,1,5,…`)
   must score 0, answering 5 to everything must score **50** (the negatively worded items cancel it
   out, which is a common misunderstanding the test pins down), and a mixed pattern must equal its
   hand-computed value: `2,4,4,4,5,2,5,2,5,1` → odd items contribute 1+3+4+4+4 = 16, even items
   1+1+3+3+4 = 12, total 28, ×2.5 = **70.0**.

   The first run of this self-test failed on all three of those expectations while the scoring
   function was correct — the expectations had been written from memory. They are now derived in the
   comment beside them, which is the point of having the check before any session runs.
2. **Criterion logic** — with 9 of 10 task-1 successes, mean SUS ≥ 70 and no critical errors, all three
   criteria report met; flipping any one input flips exactly that criterion to not met.
3. **Aggregation** — medians and ranges over task times, intervention and error totals.

Run it with:

```sh
python3 tools/usability/analyse_usability.py --self-test
```
