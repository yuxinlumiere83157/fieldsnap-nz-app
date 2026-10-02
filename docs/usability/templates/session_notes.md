# P01 — session notes

Copy to `docs/usability/results/P01_session.md` (git-ignored) and fill in as you go.

**Don't be put off by the length.** Per task you only have to fill **five fields** — time, done,
unaided, prompts, critical. They sit right under the task's script. Everything below those is optional
and can be a few words, or left blank if nothing stood out.

**In one line:** 3 tasks × 5 fields + 10 SUS marks + 3 quotes.

> **Do not add summary or roll-up tables to this sheet.** The analysis script reads the *first*
> matching `| field | value |` row in each task section, so a summary table above the tasks can shadow
> the real answers and silently invalidate the sheet.

| Field | Value |
| --- | --- |
| Participant id | P01 |
| Build / commit | |
| Facilitator | (initials) |
| Session date | |

**What the five fields mean**

* **completion_time_s** — seconds, start of task to stop. A range is fine (`70`, or `60-80`).
* **completed** — did they finish it at all, help or no help?
* **success_without_intervention** — did they finish **with no help from you**? *This is the headline
  result of the whole study, so be strict with yourself here.*
* **intervention_count** — how many times you stepped in. `0` if you never did.
* **critical_error** — `yes` only if they were stuck with no way forward, the screen told them
  something untrue, or something was lost without warning. **Slow or confused is not critical.**

---

## Task 1 — identify the photo and read its learning card

**Say this (verbatim):**

> “Please use the app to identify the plant or bird in this photo, and then open the information card
> about whatever it tells you it is.”

Answer any question with: *“Try whatever you would naturally do.”* Nothing else.

The learning card appears **inside the result panel on the same screen** — don't send them looking for
a separate button.

**Fill these five:**

| Field | Value |
| --- | --- |
| completion_time_s | |
| completed | yes / no |
| success_without_intervention | yes / no |
| intervention_count | |
| critical_error | yes / no |

**If anything stood out** (optional, a few words each):

| Field | Value |
| --- | --- |
| intervention_notes | only if the count isn't 0 — what did you have to do? |
| prediction_shown | the app's own words, e.g. `Korimako (bellbird) 98.6%` or `Uncertain` |
| learning_card_opened | yes / no |
| errors | any wrong turn |

## Task 2 — the unsuitable photo, then recovery

**Say this (verbatim) — do not warn them the photo is unsuitable:**

> “Please identify the plant or bird in this photo.”

Two outcomes both count as success: the app asks for another image, **or** it says `Uncertain` and
they swap the photo themselves.

**Fill these five:**

| Field | Value |
| --- | --- |
| completion_time_s | |
| completed | yes / no |
| success_without_intervention | yes / no |
| intervention_count | |
| critical_error | yes / no |

**If anything stood out** (optional):

| Field | Value |
| --- | --- |
| intervention_notes | only if the count isn't 0 |
| path_taken | quality_gate / uncertain_then_replace / other: |
| recovered_to_result | yes / no |
| errors | |

## Task 3 — find history and delete one entry

**Say this (verbatim):**

> “Find the list of identifications the app has saved, and delete one of them.”

**Fill these five:**

| Field | Value |
| --- | --- |
| completion_time_s | |
| completed | yes / no |
| success_without_intervention | yes / no |
| intervention_count | |
| critical_error | yes / no |

**If anything stood out** (optional):

| Field | Value |
| --- | --- |
| intervention_notes | only if the count isn't 0 |
| found_history | yes / no |
| deleted_entry | yes / no |
| errors | |

---

## SUS answers — copy the participant's ten marks here

They mark their own sheet privately; this is only the transcription. **All ten are needed** — one
blank and that questionnaire can't be scored.

| # | Item (verbatim from protocol §6) | Answer |
| --- | --- | --- |
| 1 | I think that I would like to use this system frequently. | |
| 2 | I found the system unnecessarily complex. | |
| 3 | I thought the system was easy to use. | |
| 4 | I think that I would need the support of a technical person to be able to use this system. | |
| 5 | I found the various functions in this system were well integrated. | |
| 6 | I thought there was too much inconsistency in this system. | |
| 7 | I would imagine that most people would learn to use this system very quickly. | |
| 8 | I found the system very cumbersome to use. | |
| 9 | I felt very confident using the system. | |
| 10 | I needed to learn a lot of things before I could get going with this system. | |

*(The script works the score out — no arithmetic needed here.)*

## Their words — three questions, close to verbatim

**Q1. What was the most confusing part about using the app?**

>

**Q2. The app sometimes says "Uncertain" instead of naming a species. In your own words, what do you
think that means?**

>

**Q3. If you could change one thing about the app, what would you change first?**

>

## Anything else — facts only, no interpretation

* Deviations from the protocol, and when they were decided:
* Anything the app did that the protocol doesn't cover (crash, hang, stuck state):
