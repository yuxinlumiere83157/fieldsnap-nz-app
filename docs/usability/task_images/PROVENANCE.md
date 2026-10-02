# Task image provenance

These two files are the fixed stimuli for the usability study. Every session uses them, so the task is
identical across participants.

## task1_subject.jpg — the ordinary photo (Task 1)

* source: our own **validation-split** image `data/raw/korimako/37780000.jpg` (never in the sealed test split)
* class: `korimako` (Korimako / bellbird, *Anthornis melanura*)
* licence: `cc-by` — © Jon Sullivan, some rights reserved (CC BY)
* observation id `24431147`, photo id `37780000`, original 2048x1357, observed 2019-04-29 at
  Christchurch including Banks Peninsula, Canterbury, New Zealand
* downscaled to at most 900 px on the long edge (900x597) and re-encoded at quality 92 for the repository
* shipped SHA-256: `9fbf50b85d8447e4b2bdb8e1cba49f91c3be872edfe92fb7a2801cb15d3f1aee`

### Why this image and not the original kowhai photo

The first fixed Task 1 image was `kowhai` photo `412560479`. On the frozen classifier that image
returns **`Uncertain`**: its top-1 is **0.2199**, below the deployed accept threshold of 0.37 (the
frozen validation scoring in `artifacts/conf/val_scores.json` records `predicted: tradescantia`,
`top1_score: 0.2199`, `correct: false`; confirmed on the device, which showed top confidence 0.193).

That made **Task 1 impossible by construction**. Task 1 asks the participant to identify the photo
*and open the learning card*, but the card is only rendered for an asserted species. With no species
asserted there is no card to open, so `learning_card_opened` would have been `no` and
`success_without_intervention` `no` for **every** participant regardless of ability — the primary
criterion C1 would have failed 0/5 because of a stimulus defect, and the report would have blamed the
app for it. The root cause is the image choice, not the model: kowhai recall is 0.364 on the frozen
test set and only 2 of the 7 kowhai validation images clear the threshold.

The replacement was chosen on the frozen validation scores as the **most reliable** stimulus
available, not merely a working one:

| Candidate class | val images | accepted (≥0.37) | accepted **and** correct | best score |
| --- | ---: | ---: | ---: | ---: |
| **korimako (chosen)** | 9 | 9 | **9 / 9** | **0.9856** |
| silver_fern | 5 | 5 | 5 / 5 | 0.9783 |
| tui | 8 | 8 | 7 | 0.9554 |
| kowhai (the original) | 7 | 3 | 2 | 0.8384 |

korimako is one of only two classes in which **every** validation image is both accepted and
correctly classified, and photo `37780000` has the highest score in it. Verified on the device after
the swap: **Korimako (bellbird), confidence 98.6%**, `ANTHORNIS MELANURA`, learning card rendered
(898 ms on-device inference).

Because the stimulus is only ever pushed to the device gallery and is **not** bundled as an app asset,
this change requires no rebuild; the APK is untouched.

## task2_unsuitable.jpg — the unsuitable photo (Task 2)

Generated, not collected, so its provenance is trivial and it is trivially reproducible: a synthetic
low-contrast, heavily blurred frame with a bright glare band and a visible pixel grid, i.e. the shape
of the photo-of-a-screen a novice might take. It contains no personal content and no identifiable
subject, and it ships with this repository under the same terms as the project's own code.

Regenerate it with `python3 tools/usability/make_task_images.py`.

## Fit with the frozen evaluation

Neither image is used to compute any metric. `task1_subject.jpg` comes from the validation split,
which the classifier is not trained on; using it as a study stimulus says nothing about accuracy and
does not touch the sealed test split or any frozen result. Its top-1 confidence was known before the
first session and is recorded here, so no participant's result can be used to choose or justify the
stimulus after the fact.
