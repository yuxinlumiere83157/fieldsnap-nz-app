# Final test-set evaluation report

**One-shot evaluation of the sealed test split**, run once on 2026-09-11T19:16:03+12:00 at commit `996a320b7132`
under the pre-registered protocol `docs/final_test_evaluation_protocol.md` (SHA-256
`3ee52a0b062e360b…`). The split was sealed at the 1A freeze and opened only now.

## Provenance

| Item | Value |
| --- | --- |
| Run id | `20260911T191603-e6b10afd` |
| Timestamp | 2026-09-11T19:16:03+12:00 |
| Commit | `996a320b7132746a0c2e2a152e0848595b254054` |
| Model | `assets/models/fieldsnap_float.tflite` |
| Model SHA-256 | `e6b10afdfc97d73da0a37be1f3b6a30209f3830576328e7318d0e1fa1e1ead25` |
| Test manifest | `data/manifest_test.csv` |
| Test-manifest SHA-256 | `e1573b32cb2115aa5acc2747958dfd0f893ae1a3c4bfbd32f35724cc4bc21d07` |
| Label file SHA-256 | `c89919599b0e48381e03f0dfb8483621fdafb5bb7a0809204ba8ed8d313c3155` |
| Images evaluated | 187 (all images in the split; none skipped) |
| Classes | 20 |
| Preprocessing | production `ImagePreprocessor` (decode, EXIF, RGB, 224x224 area resize, `(x-127.5)/127.5`) |
| Frozen FR2 thresholds | minBrightness 0.26, maxBrightness 0.89, minLaplacianVariance 100.0 |
| Frozen FR4 threshold | 0.37 (margin rule disabled) |
| Raw predictions | `artifacts/final_test_predictions.json` |
| Computed metrics | `artifacts/final_test_evaluation.json` |

## Headline metrics (all test images, no quality-gate filtering)

| Metric | Value | M1 target | Met? |
| --- | --- | --- | --- |
| Top-1 accuracy | **0.5561** (104/187) | >= 0.80 | **no** |
| Top-3 accuracy | **0.7968** (149/187) | >= 0.95 | **no** |
| Macro-F1 | **0.5343** | >= 0.80 | **no** |

## FR4 threshold applied (frozen at 0.37, not re-tuned on the test set)

| Quantity | Value |
| --- | --- |
| Coverage | **0.7326** (137/187 images answered) |
| Accepted images | 137 |
| Rejected (Uncertain) images | 50 |
| Accepted-prediction accuracy | **0.6496** |
| Rejected-subset accuracy (top-1, for transparency) | 0.3000 |

M1 requires accepted accuracy >= 0.90 while coverage >= 0.70: **NOT met** (measured 0.6496 at coverage 0.7326).

## Per-class precision / recall / F1

| Class | Support | Correct | Precision | Recall | F1 |
| --- | --- | --- | --- | --- | --- |
| korimako | 13 | 2 | 0.286 | 0.154 | 0.200 |
| wild_ginger | 9 | 2 | 0.222 | 0.222 | 0.222 |
| moth_plant | 10 | 3 | 0.250 | 0.300 | 0.273 |
| blackbird | 4 | 1 | 0.500 | 0.250 | 0.333 |
| tradescantia | 9 | 2 | 0.667 | 0.222 | 0.333 |
| house_sparrow | 12 | 3 | 0.600 | 0.250 | 0.353 |
| kowhai | 8 | 4 | 0.364 | 0.500 | 0.421 |
| common_myna | 7 | 2 | 1.000 | 0.286 | 0.444 |
| woolly_nightshade | 13 | 5 | 0.714 | 0.385 | 0.500 |
| pohutukawa | 8 | 5 | 0.455 | 0.625 | 0.526 |
| song_thrush | 5 | 4 | 0.444 | 0.800 | 0.571 |
| nikau | 10 | 7 | 0.538 | 0.700 | 0.609 |
| kereru | 7 | 5 | 0.556 | 0.714 | 0.625 |
| tauhou | 17 | 14 | 0.609 | 0.824 | 0.700 |
| harakeke | 9 | 7 | 0.636 | 0.778 | 0.700 |
| piwakawaka | 9 | 9 | 0.562 | 1.000 | 0.720 |
| silver_fern | 14 | 11 | 0.733 | 0.786 | 0.759 |
| ti_kouka | 9 | 7 | 0.778 | 0.778 | 0.778 |
| tui | 3 | 2 | 1.000 | 0.667 | 0.800 |
| starling | 11 | 9 | 0.818 | 0.818 | 0.818 |

## Confusion matrix (rows = truth, columns = prediction)

| truth \ pred | blackbird | common_myna | harakeke | house_sparrow | kereru | korimako | kowhai | moth_plant | nikau | piwakawaka | pohutukawa | silver_fern | song_thrush | starling | tauhou | ti_kouka | tradescantia | tui | wild_ginger | woolly_nightshade |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **blackbird** | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 1 | 0 |
| **common_myna** | 0 | 2 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **harakeke** | 0 | 0 | 7 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| **house_sparrow** | 1 | 0 | 1 | 3 | 0 | 0 | 0 | 0 | 0 | 4 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |
| **kereru** | 0 | 0 | 0 | 1 | 5 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 |
| **korimako** | 0 | 0 | 0 | 0 | 1 | 2 | 0 | 1 | 1 | 1 | 0 | 0 | 0 | 0 | 6 | 0 | 0 | 0 | 0 | 1 |
| **kowhai** | 0 | 0 | 0 | 0 | 1 | 0 | 4 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 1 |
| **moth_plant** | 0 | 0 | 0 | 0 | 0 | 1 | 3 | 3 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 |
| **nikau** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 7 | 0 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| **piwakawaka** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 9 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **pohutukawa** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 5 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 |
| **silver_fern** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 | 11 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| **song_thrush** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 4 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| **starling** | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 9 | 0 | 0 | 0 | 0 | 0 | 0 |
| **tauhou** | 0 | 0 | 0 | 0 | 1 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 14 | 0 | 0 | 0 | 0 | 0 |
| **ti_kouka** | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 1 | 7 | 0 | 0 | 0 | 0 |
| **tradescantia** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 2 | 0 | 2 | 0 |
| **tui** | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 | 0 |
| **wild_ginger** | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 3 | 3 | 0 | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 2 | 0 |
| **woolly_nightshade** | 0 | 0 | 2 | 0 | 0 | 0 | 4 | 0 | 0 | 0 | 2 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 5 |

## Target evaluation as written (no target was adjusted)

| M1 acceptance target | Measured | Verdict |
| --- | --- | --- |
| Held-out top-1 >= 0.80 | 0.5561 | **NOT MET** |
| Held-out top-3 >= 0.95 | 0.7968 | **NOT MET** |
| Macro-F1 >= 0.80 | 0.5343 | **NOT MET** |
| Accepted accuracy >= 0.90 at coverage >= 0.70 | 0.6496 at 0.7326 | **NOT MET** |

## Interpretation and limits

* **All four M1 acceptance targets are not met.** Measured: top-1 0.5561 (target 0.80), top-3 0.7968 (target 0.95), macro-F1 0.5343 (target 0.80), and accepted accuracy 0.6496 at coverage 0.7326 (target 0.90 at coverage >= 0.70). Top-3 is the closest of the four and still misses.
* The test split is small (187 images, 6-17 per class, 20 classes), so per-class numbers carry
  wide uncertainty; single-image changes move a class F1 by roughly 0.1. The headline numbers are
  reported because they are the pre-registered evaluation, not because they are precise.
* The threshold was fixed before this run and was **not** moved afterwards. Moving it now to
  improve the accepted-accuracy figure would invalidate the calibration and is explicitly
  forbidden by the protocol; the frozen operating point answers 73.3% of images and is wrong on 35.0% of the ones it answers.
* Test images were evaluated regardless of the FR2 quality gate, as the protocol requires, so
  these numbers describe the classifier, not the gate.
* The failure structure (background/colour shortcuts, similar species pairs) was analysed on the
  validation split in `docs/model_error_analysis.md` before this run. Several of the pairs it
  predicted dominate the matrix above (for example tauhou/blackbird and the tradescantia /
  wild-ginger / moth-plant cluster), which is consistent with that analysis - but it was written
  without sight of the test split and made no change to the model.
* Rejected-subset accuracy (0.3000) is reported for transparency: the threshold does concentrate errors
  into the rejected subset, as intended, but the accepted subset is still far from the target.

## Post-evaluation freeze

Per the protocol: **no model, class-set, preprocessing or threshold change is permitted on the
basis of these results.** The test split has now been read once and will not be used again as a
selection signal. Any further modelling work must use the validation split or a newly provisioned
test set, recorded as a new iteration with its own pre-registered protocol.

## Not done in this evaluation

* No retraining, no data expansion, no class changes, no QAT, no threshold adjustment.
* No usability testing (no participants, no SUS, no first-task success measurement).

