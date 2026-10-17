# KLM supplementary analysis

**Status:** predictive analysis, not a measurement of participants. No participant data exists; this
file contains none. Written 2026-10-17, **before** any P01 observation, and its parameters are not to be
fitted to P01 afterwards.

**What this is.** A keystroke-level-model (KLM) estimate of how long the three usability-task paths take
for a **skilled** user who already knows the method and makes no errors [R1]. The lecturer suggested
KLM (or structured interviews) as supplementary analysis when participant numbers are low; this is that
supplement, and it stands beside the usability session, not in place of it.

**What this is not.** KLM cannot predict whether a *novice* goes wrong, whether they understand
`Uncertain`, whether they are satisfied, or whether SUS/NFR6 are met. No claim in this file is a
usability result, and none may be quoted as one.

## 1. Evidence base and build

| Item | Value |
| --- | --- |
| Build the UI was read from | `3152302` in the archived mirror; APK SHA-256 `138f0211…` |
| Device for measured waits | Pixel 8, Android 17, release/profile builds |
| Frozen configuration | model `fieldsnap_float.tflite` `e6b10afd…`; accept threshold **0.37**; quality gate **0.26 / 0.89 / 100.0** |
| UI step evidence | source references below + committed screenshots |

The current public repository has never had the APK rebuilt, and five service files differ from `3152302`
by refactors (`background_runner`, `history_repository`, `image_preprocessor`, `model_labels`,
`quality_gate`: typed boundaries and dead-scaffolding removal). Those changes **do not alter** the three
paths, the thresholds or the delete behaviour modelled here; the measured waits below are reported for
the build they were measured on, as originally recorded, not re-measured.

Screenshots used (paths relative to the repository):

| Purpose | File | Build |
| --- | --- | --- |
| Path 1 start, image picked, quality accepted, `Identify species` enabled | `docs/logs/iter4_offline_01_result.png` | frozen build (threshold 37 %) |
| Path 3 history list, one record, per-row delete icon and `Clear all` icon | `docs/logs/iter4_offline_02_history_after_restart.png` | frozen build (threshold 37 %) |
| Path 1 result panel with learning card inline | `docs/logs/iteration2_device_03_result.png` | **earlier, pre-calibration build (threshold 45 %)** — layout only; the panel is unchanged in code, but this screenshot must not be cited as frozen-build evidence |

No committed screenshot shows the quality-rejection card on the frozen build; that state is verified by
code and by the 2026-10-02 device rehearsal recorded in `docs/post_evaluation_changes.md` (Change 6.5).

## 2. Operator parameters

Three kinds of time are kept separate: **literature** parameters, **modelling assumptions**, and
**measurements**. A number is only in the model if its kind is named.

| Op | Value used | Kind | Source / applicability | Caveat |
| --- | ---: | --- | --- | --- |
| `M` mental preparation | **1.35 s** | literature | Card, Moran & Newell 1980 [R1] | Expert; not a novice's comprehension of an `Uncertain` message |
| `P` finger point/tap | **80 ms** | literature | El Batran & Dunlop 2014 [R2]: movement time "for an icon pointing from a home position" (200×200 icon) | Movement only — tap press/dwell is **not** modelled, so this is a lower bound. App-bar icons are ≈48 dp, smaller than the 200 px target, so may be slower |
| `S` short swipe | **70 ms** | literature | [R2], short untargeted swipe | Not invoked: with two images in the picker no scroll is needed |
| `R_classify` (warm) | **314.42 ms** median | **measurement** | `docs/physical_device_run.md`: full CPU path (decode + resize + rescale + inference), profile build, 30 runs, warm-up excluded | One device, one session |
| `R_classify` (first, release) | **430–898 ms** observed | **measurement** | UI `last run` readings in the committed screenshots above | Two single-shot observations, not a distribution; includes isolate start-up/asset load |
| `R_picker` open / return | — | **not modelled** | System photo-picker transition + preview decode | Not measured; excluded rather than guessed. Every path that opens the picker is therefore a **lower bound** |
| Reading, comprehension, deciding what `Uncertain` means | — | **not modelled** | Outside KLM's scope | Deliberately excluded; this is the largest real-world term for a novice |

**Mental-operator placement rule used.** One `M` at each point where the user must choose between
alternatives or select a method — which button starts the task, which photo to pick, whether to run the
identification — and no `M` inside a continuous motor act. This is the standard KLM heuristic; applying
a different rule changes the `M` count and therefore the total, which is why the rule is stated.

**Model.** `T_predicted = Σ(n_i × t_i) + R_blocking`

## 3. Paths, from the real UI

### Path 1 — pick a normal photo → classify → learning card visible

Start state: app open on the capture screen, no image selected, camera permission revoked, the two fixed
task images in the gallery.

| # | Step | UI element (source) | Ops |
| --- | --- | --- | --- |
| 1 | Decide to import a photo, open the gallery | `Select from gallery` filled button (`lib/views/capture_screen.dart:231`) | `M P` |
| 2 | System photo picker opens; choose the photo | Android Photo Picker grid cell | `M P` + `R_picker` (excluded) |
| 3 | Preview + quality assessment on return | quality card, `lib/views/capture_screen.dart` `_QualityCard` | — |
| 4 | Decide to identify and tap | `Identify species` filled button (`lib/views/capture_screen.dart:334`) | `M P` |
| 5 | Wait for preprocess + inference; result and learning card render **inline** on the same screen | `Result` panel; card from `assets/data/species_cards.json` | `R_classify` |

`n_M = 3`, `n_P = 3`, `R = 0.314 s`
**T₁ = 3(1.35) + 3(0.08) + 0.314 = 4.60 s** (range 4.72–5.19 s if the first-classification release
wait is used instead). Excludes `R_picker`. There is no separate "open card" step — the card is rendered
inside the result panel, so Task 1's second half adds no operators.

### Path 2 — quality rejection shown → replace with a normal photo → usable result

Start state: an unsuitable photo has been picked; the quality card shows the red rejection
("Too little detail: sharpness … is below the 100 minimum") and `Identify species` is disabled.

| # | Step | UI element (source) | Ops |
| --- | --- | --- | --- |
| 1 | Decide to replace the photo | `Replace from gallery` (same button, label changes with state, `capture_screen.dart:231`) | `M P` |
| 2 | Picker opens; choose a usable photo | Photo Picker grid cell | `M P` + `R_picker` (excluded) |
| 3 | New preview + quality re-assessment (accepted) | `_QualityCard` | — |
| 4 | Decide to identify and tap | `Identify species` | `M P` |
| 5 | Classify and render card | `Result` panel | `R_classify` |

`n_M = 3`, `n_P = 3`, `R = 0.314 s`
**T₂ = 4.60 s** (4.72–5.19 s with the release wait), excluding `R_picker`.

Recovery therefore costs about the **same as the original attempt**: reaching a usable result after one
rejection is roughly `T_pick + T_recovery` ≈ 7.5 s of expert execution, excluding the unmodelled picker
transitions and the time spent reading the rejection itself.

### Path 3 — open history → delete one entry → see the completed state

Start state: capture screen; at least one saved identification exists.

| # | Step | UI element (source) | Ops |
| --- | --- | --- | --- |
| 1 | Decide to review history and tap the app-bar icon | history `IconButton` (`capture_screen.dart:38`) | `M P` |
| 2 | History screen loads records from SQLite | `lib/views/history_screen.dart` `FutureBuilder` | `R_history` (not measured) |
| 3 | Locate the target record and tap its trash icon | per-row `IconButton`, tooltip "Delete this record" (`history_screen.dart:131`) | `M P` |
| 4 | Record is deleted **immediately** (no confirmation dialog, no undo) and the list reloads | `_delete()` → `repository.delete(id)` → `_reload()` (`history_screen.dart:33`) | `R_reload` |

`n_M = 2`, `n_P = 2`
**T₃ = 2(1.35) + 2(0.08) = 2.86 s**, plus the unmeasured history/reload waits.

Code-verified detail worth recording: **single-record delete has no confirmation and no undo**, whereas
`Clear all history` opens an `AlertDialog` requiring `Delete all` (`history_screen.dart:43`). This is the
kind of inconsistency the protocol's third critical-error case ("data loss without warning") exists to
catch; it is a design observation from the code, not a participant finding.

## 4. Predicted times

| Path | M | P | R_blocking (measured) | T_predicted | Modelled as a lower bound because |
| --- | ---: | ---: | ---: | ---: | --- |
| 1 — pick → classify → card | 3 | 3 | 0.314 s | **4.60 s** | picker transition, reading |
| 2 — rejection → replace → result | 3 | 3 | 0.314 s | **4.60 s** | picker transition, reading the rejection |
| 3 — history → delete | 2 | 2 | not measured | **≥ 2.86 s** | history load, list reload |

## 5. Where the cost sits, and one low-risk improvement

The mental operators dominate: 4.05 s of Path 1's 4.60 s is `M` (≈ 88 %). Motor time is 0.24 s and the
measured system wait 0.31 s. Two consequences, both important for the report:

* **Optimising inference further would buy very little.** The whole measured classification wait is
  shorter than a single mental operator; the novice cost of this app is in *deciding and understanding*,
  which KLM does not model at all. That gap is exactly why the participant session is still needed.
* **One avoidable wait is identifiable from the measurements**: the first classification in a release
  session took 430–898 ms against a warm 314 ms. Pre-warming the interpreter and labels after an image is
  picked — no UI change, no model change — would remove a one-time few-hundred-millisecond stall on the
  first identification. Low risk, measurable, and it does not touch the frozen artefacts.

Second, unrelated to timing: giving single-record delete the same confirmation the `Clear all` control
already has (or a brief undo) would remove the only irreversible-without-warning action in the app. This
is a recommendation for future work; **no code was changed in this round**.

## 6. Limitations

* **Skilled user, no errors.** Every predicted time is a best-case execution time for someone who already
  knows what to do. A novice's first attempt will be slower and may not reach the endpoint at all.
* **Reading and comprehension are excluded.** Deciding that `Uncertain` is not a failure, and reading a
  learning card, are outside KLM. For the actual task those are plausibly the largest terms.
* **The system photo picker is excluded.** Opening it, waiting for thumbnails and returning are
  unmeasured; all picker paths are therefore lower bounds, and this is the biggest single gap.
* **`P` is movement-only** ([R2] reports movement time; press/dwell is not separately modelled), so motor
  time is conservative-low.
* **Fitts's law did not fit interactions beyond ~4 bits of index of difficulty** in [R2]; the picker grid
  and app-bar icons sit at different distances from a "home position", so a single `P` value cannot be
  exact for all of them.
* **One device, one measurement session** for the waits; the release single-shot readings are two
  observations, not a distribution.
* **Not validated against P01.** P01 is a novice; at most a descriptive comparison is possible, and it
  will not be used to tune these parameters.

## 7. What would settle the largest unknown

One measurement, if the device is available: time from tapping `Select from gallery` to the preview being
interactive, and from tapping the thumbnail to the app regaining focus. That single addition would turn
the picker term from "excluded" into measured, and is the only place where the model is currently more
than a few hundred milliseconds from a real novice's experience.

## References

* [R1] Card, S. K., Moran, T. P., & Newell, A. (1980). The keystroke-level model for user performance
  time with interactive systems. *Communications of the ACM, 23*(7), 396–410.
  <https://doi.org/10.1145/358886.358895>
* [R2] El Batran, K., & Dunlop, M. D. (2014). Enhancing KLM (keystroke-level model) to fit touch screen
  mobile devices. *Proceedings of MobileHCI '14*, 283–286.
  <https://doi.org/10.1145/2628363.2628385> — author manuscript:
  <https://strathprints.strath.ac.uk/49816/1/Karim_MHCI_Final_Camera_Ready.pdf>
