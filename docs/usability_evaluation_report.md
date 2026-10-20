# Usability evaluation report — P01 descriptive interim

**Status (21 October 2026): INTERIM — 1 valid real session of a planned target of 5.**
One consented adult novice participant completed the moderated study on 20 October 2026. All results below are descriptive for this session only. **NFR6 cohort-level criteria C1–C3 are NOT YET EVALUABLE.** No additional participants, general trends or population-level usability results are claimed.

This account follows the frozen [v1.2 protocol](usability_evaluation_protocol.md), with the actual session deviations recorded below. The participant's annotated paper forms and individual SUS item responses remain **private** and are not committed or included in the public source ZIP. The figures here were transcribed from those real records, and the SUS total was independently recomputed from the standard formula. This is not synthetic demonstration data.

## 1. Method, device and consent

- **Study:** moderated, task-based novice usability assessment; brief orientation, three assigned tasks, standard ten-item System Usability Scale (SUS), then three qualitative questions.
- **Date and length:** 20 October 2026; approximately **15 minutes total**, according to the facilitator, including orientation, tasks, questionnaire and interview. Task stopwatch readings add to only **44 seconds** and do not represent the entire session; the precise finishing clock time was not written down.
- **Participant:** one adult first-time FieldSnap user without formal bird/plant training, coded P01. Voluntary **verbal consent obtained**, no audio recording, no withdrawal. No personal name, photo, contact information or raw sheet is published.
- **Device/build:** Google Pixel 8, Android 17/API 37; fresh reset with fixed study photos prepared; **debug APK built from code commit `c510a54`**, SHA-256 prefix `6fc725cf`. The same code underwent the independently recorded 18 October S1–S6 physical smoke test; see [smoke evidence](smoke_test_running_state.md).
- **Primary scope:** user workflow and recovery, not classifier predictive accuracy. The frozen model, gate limits and confidence threshold were **not changed** or recalibrated for this study.

## 2. Actual task results

| Task | Outcome | Independent? | Measured task time | Moderator prompts | Recorded critical errors |
| --- | --- | --- | ---: | ---: | ---: |
| 1. Identify preselected photo and see learning card | **Completed**; Korimako output and inline card viewed | **Yes** | **20 s** | **0** | **0** |
| 2. React to uncertain classification and replace photo | **Completed**; FR4 Uncertain, then replaced image | **Yes** | **18 s** | **0** | **0** |
| 3. Find identification history and delete a record | **Completed**; history found and entry removed | **Yes** | **6 s** | **0** | **0** |
| **Observed P01 total** | **3/3 completed** | **3/3 unaided** | **44 s in task timers** | **0** | **0** |

These are the observations recorded on the form, not estimates. A failure, if one had occurred, would still have been reported rather than silently excluded.

**Task 1 stimulus limitation.** The supplied Korimako image was selected from the **validation** data before participation because it produced a stable visible learning card. Its task success supports this specific interaction path, **not** the deployed classifier's general accuracy; the sealed test data were not used to choose it.

**Task 2 protocol deviation.** The image actually used during this session was **not** the frozen `task2_unsuitable.jpg` blurred stimulus. The actual alternative photograph passed the quality gate, classification returned **“Uncertain – try another photo”** (the **FR4** abstention state), and P01 recovered through **“Replace from gallery.”** The originally planned blur stimulus was rejected by **FR2** in separate technical checks, but **that FR2 rejection was not observed in the P01 human task**. The reason for the stimulus substitution was not formally recorded; it should not be guessed. Thus the session provides evidence about FR4 comprehension/recovery, not novice comprehension of FR2 warnings.

## 3. SUS result

A complete **10/10-item standard SUS** questionnaire was returned, with one eligible response for each item. Odd statements were scored as `response − 1`, and even statements as `5 − response`; the contribution total was **33**, giving **33 × 2.5 = 82.5 / 100**.

This is **one individual's SUS score**, not a five-person average, representative satisfaction estimate, or proof of the original mean-SUS acceptance criterion. Individual item responses remain in the private session record.

## 4. Qualitative observations

The participant's main usability concern was the similar-sounding actions **“Replace from gallery”** and **“Clear selection.”** They interpreted the latter as potentially clearing several selected photos rather than the single currently displayed selection. When asked what **“Uncertain”** meant, the participant described the app as being unable to identify the object. These are de-identified paraphrases of one participant's answers, **not evidence of a population trend**. Future usability work should test clearer labels and explicit recovery explanations.

## 5. Pre-registered NFR6 criteria

The v1.2 recruitment target is five valid novice sessions. Matthew clarified that five was a recommendation rather than a hard minimum; the protocol nevertheless established that the cohort-level criteria are evaluated only at **n ≥ 5**.

| Criterion | Planned threshold | P01 descriptive observation | Verdict |
| --- | --- | --- | --- |
| C1 — first identification + card unaided | ≥90% of cohort | **1/1** independently completed | **NOT YET EVALUABLE (n=1)** |
| C2 — mean SUS | ≥70 across cohort | **P01 individual SUS 82.5** | **NOT YET EVALUABLE (n=1)** |
| C3 — critical errors | Zero across cohort tasks | **0 in P01** | **NOT YET EVALUABLE (n=1)** |

There are no claims that recruitment has been completed to its planned target. This is one real **applied** moderated mobile-usability process with an explicitly limited sample, distinct from the **completed** requirement-driven technical acceptance/benchmarking process in [traceability](traceability.md). The [KLM](klm_evaluation.md) is supplementary predictive modelling only and **was not fitted to P01 timings**.

## 6. Limitations and next steps

- **Sample and facilitator:** single convenience participant; one facilitator performed both moderation and note-taking. Individual task timers cannot be interpreted as representative task-speed distributions.
- **Stimulus control:** the Task 2 replacement differed from the planned blur stimulus; a later session should restrict the photo picker to the intended study stimuli or explicitly verify the photo chosen before recording the path.
- **Build/device:** only one Pixel 8 and a debug study build were used. Profile/release benchmarks in other reports are separate experiments and should not be represented as measurements collected during the human session.
- **Classifier:** frozen sealed-test top-1 accuracy was **0.5561**, so a successful interface interaction should not be construed as reliable autonomous bird/plant identification.
- **Design follow-up:** consider clearer single-photo wording for replacing versus clearing the selected image, and repeat moderated usability evaluation across a more varied adult sample.

The private P01 paper forms are the source evidence. They are **not** published under `docs/usability/results/` or elsewhere in the public Git repository.
