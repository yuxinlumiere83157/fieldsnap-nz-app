# Final test evaluation protocol — PRE-REGISTERED, committed before the test split is opened

Status: frozen at commit `0b9aa7c09cff` **before** `data/manifest_test.csv` was read. Everything in this
document was fixed in advance; the test split is opened exactly once for the evaluation below.

## 1. Frozen evaluation candidate

| Item | Value |
| --- | --- |
| Model | `assets/models/fieldsnap_float.tflite` |
| Model SHA-256 | `e6b10afdfc97d73da0a37be1f3b6a30209f3830576328e7318d0e1fa1e1ead25` |
| Labels | `assets/models/class_indices.json` SHA-256 `c89919599b0e48381e03f0dfb8483621…` |
| Classes | 20 (order exactly as in the label file) |
| Data version | 2 — training manifest `data/manifest_train_expanded_v2.csv`, mapping hash `76a3d3b42690d8b9…` |
| Test split | `data/manifest_test.csv`, 187 images, sealed since the 1A freeze (protocol `data/split_protocol.json`, manifest SHA-256 `feb9cdaf06fe1081…`) |
| Test-manifest SHA-256 (at evaluation) | recorded in the report and in the raw predictions file |

## 2. Frozen production preprocessing

The **production** path, unchanged (`lib/services/image_preprocessor.dart`):

1. decode the encoded image;
2. apply EXIF orientation (spec-correct table, Pillow-verified);
3. convert to RGB;
4. resize to 224x224 with area averaging;
5. rescale `(pixel - 127.5) / 127.5` to `[-1, 1]` **exactly once**;
6. emit float32 HWC `[1, 224, 224, 3]`.

The exported models use `include_preprocessing=False`, so no rescaling happens inside the graph;
`TfliteInferenceEngine.assertInputInRange` enforces the `[-1, 1]` contract at runtime.

## 3. Frozen thresholds

| Gate | Frozen value | Provenance |
| --- | --- | --- |
| FR2 `minBrightness` | **0.26** | validation-split calibration, one-shot verification |
| FR2 `maxBrightness` | **0.89** | ditto |
| FR2 `minLaplacianVariance` | **100.0** | ditto |
| FR4 accept threshold | **0.37** | validation-split sweep, coverage >= 0.70 rule |
| FR4 margin rule | **disabled** (`marginThreshold: null`) | deliberate; see `docs/confidence_policy.md` |

## 4. Evaluation procedure (fixed in advance)

* **Primary path**: the shipped FP32 `.tflite` through the production preprocessing above. No
  alternative model is used for the headline numbers.
* **All test images are evaluated**, regardless of any quality-gate outcome. The FR2 gate has its
  own evaluation (`docs/iteration_3_calibration_report.md`) and must not silently shrink the test set.
* One pass. No iteration on the model, classes, preprocessing or thresholds afterwards.
* Reported: top-1, top-3, macro-F1, per-class precision/recall/F1, the full confusion matrix, and
  the image/class counts.
* The frozen 0.37 threshold is then applied to the same predictions to report coverage, accepted
  and rejected counts, accepted-prediction accuracy and rejected-subset accuracy.

## 5. M1 acceptance targets (evaluated as written, not adjusted)

| Target | Requirement |
| --- | --- |
| Held-out top-1 accuracy | **>= 0.80** |
| Held-out top-3 accuracy | **>= 0.95** |
| Macro-F1 | **>= 0.80** |
| Accepted-prediction accuracy | **>= 0.90 while coverage >= 0.70** |

Every target is reported as met or not met with its measured value. A target is never
reinterpreted after seeing the result, and no threshold is moved to reach one.

## 6. Artefacts produced

| Artefact | Contents |
| --- | --- |
| `artifacts/final_test_predictions.json` | every test image: photo id, observation id, true class, predicted class, top-3 with scores, correctness |
| `docs/final_test_evaluation_report.md` | the report: metrics, targets, provenance (model SHA, test-manifest hash, run id, commit SHA, timestamp) |

## 7. Post-evaluation freeze

After this evaluation, **no model, class-set, preprocessing or threshold change is permitted** on
the basis of the test results. The test split is read once; any later work must use the validation
split or a new, separately-provisioned test set, and any such change must be recorded as a new
iteration with its own protocol.

## 8. Out of scope for this evaluation

* Usability testing (no participants yet; SUS and first-task success remain unmeasured).
* Memory and latency: measured separately on the Pixel 8 (`docs/peak_memory_protocol.md`,
  `docs/physical_device_run.md`).
* The experimental INT8 artefact: its accuracy gap is already recorded in `docs/model_selection.md`
  and it is not the deployed model.
