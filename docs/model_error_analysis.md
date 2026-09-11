# Model error analysis — weakest validation classes

Scope: the shipped FP32 model trained on data version 2 (`artifacts/comparison_expanded.json`).
Source of the numbers: the **validation** split only (163 images, 20 classes). The sealed test split
has not been read, and nothing in this document changes the model: it records hypotheses to test,
not conclusions to act on by speculation.

The model is weak overall (validation top-1 0.503, macro-F1 0.499). This document asks *where* it
fails, because the answer shapes the next data and design decisions.

## Measurements

Per-class results, weakest first (validation; `n` is small, so treat single points loosely):

| Class | n | top-1 | precision | F1 |
| --- | --- | --- | --- | --- |
| tauhou (silvereye) | 7 | 0.143 | 0.167 | 0.154 |
| blackbird | 11 | 0.182 | 0.286 | 0.222 |
| moth plant | 7 | 0.429 | 0.188 | 0.261 |
| house sparrow | 4 | 0.250 | 0.333 | 0.286 |
| wild ginger | 6 | 0.333 | 0.250 | 0.286 |
| pōhutukawa | 7 | 0.429 | 0.300 | 0.353 |
| harakeke | 8 | 0.375 | 0.375 | 0.375 |
| tradescantia | 9 | 0.333 | 0.429 | 0.375 |

Strongest: silver fern (F1 0.833), korimako (0.783), tūī (0.737), common myna (0.727).

Most frequent confusions (truth → predicted, validation counts):

| Count | Truth | Predicted as | Plausible failure mode |
| --- | --- | --- | --- |
| 3 | woolly nightshade | moth plant | Both are large-leaved pest plants photographed against fences and scrub; the model may key on "big green leaf + disturbed ground" rather than leaf texture or flower. |
| 3 | tradescantia | wild ginger | Both are glossy-leaved ground-cover/understorey plants in shade; tradescantia mats and ginger stands share lighting and background. |
| 3 | tradescantia | moth plant | Vine/mat confusion in low, cluttered vegetation. |
| 3 | song thrush | tauhou | Both small brownish birds; at photo scale the speckled thrush breast is a few pixels wide. |
| 3 | piwakawaka | tūī | Fantail is small and dark against foliage; the model may be reading "small dark bird in green background". |
| 3 | piwakawaka | blackbird | Same issue: a small dark bird on a lawn/garden background. |
| 3 | blackbird | moth plant | The most damaging pair: an animal predicted as a plant. Suggests a background artefact (dark foliage texture) or an out-of-distribution photo rather than genuine shape confusion. |
| 2 | ti kōuka | harakeke | Both are clumps of long strap leaves; the flowering spike or trunk is needed to separate them and is often cropped out. |
| 2 | tauhou | korimako | Small olive-green birds in foliage. |
| 2 | wild ginger | tradescantia | Reciprocal of the pair above. |
| 2 | pōhutukawa | kōwhai | Both trees photographed as "flowers on a branch" against sky. |

## Likely failure modes, ranked by evidence strength

1. **Context/background shortcuts (strong).** Several confusions cross life form entirely
   (blackbird → moth plant, piwakawaka → tūī/blackbird). With ~150 training images per class drawn
   from iNaturalist, background and framing are highly correlated with the label, so a small model
   can score well on training data by recognising *where* the photo was taken. This is consistent
   with training accuracy 0.65 versus validation 0.30–0.50 across runs.
2. **Small subjects at low resolution (moderate).** The weak bird classes are the small ones
   (tauhou, piwakawaka, song thrush). The preprocessing shrinks the whole frame to 224x224, so a
   distant bird becomes a few dozen pixels; the field marks a learner would use are gone.
3. **Genuinely similar plant pairs (moderate).** ti kōuka/harakeke and tradescantia/wild ginger are
   hard even for people without a flower or trunk; the model has no way to ask for a better angle.
4. **Class imbalance in the *validation* sample (methodological, not model).** tauhou has n=7 and
   house sparrow n=4, so single-image swings move their F1 by ~0.14. These classes should not be
   used to justify a modelling change on their own.
5. **Quantisation is not the explanation for these errors.** The FP32 model is the one measured
   here; the INT8 penalty (docs/model_selection.md) is a separate, larger effect.

## What would test these hypotheses (not yet done)

* **Background control**: evaluate the same model on crops that remove the outer frame, or on
  images with the background masked. If accuracy rises sharply, the shortcut is confirmed and the
  next data step is augmentation/cropping rather than more images.
* **Subject-scale control**: resize so the subject occupies a fixed fraction of the frame, or train
  at a higher input resolution (for example 320 px) and re-measure. That turns "small subject" from
  a hypothesis into a measured effect.
* **Per-class dataset inspection**: count how many training images per class are close-ups versus
  whole-scene shots. If, say, tauhou is mostly whole-tree shots, the class is being asked to learn a
  silhouette.
* **Confusion-aware data collection**: add training images specifically for the pairs above, from
  independent observations, and re-measure the same validation split (the split must not change).
* **Abstention instead of accuracy**: the Uncertain path is already implemented. A validation-derived
  threshold would convert the worst errors into "try another photo", which is often the honest
  outcome for a beginner photo.

## What this document deliberately does not do

* It does not change the model, the classes, the preprocessing or the training set.
* It does not re-draw the split or touch the test set.
* It does not present the confusion counts as statistically robust: with 163 validation images the
  counts of 2–3 have wide uncertainty, and they are hypotheses to test.

## Relationship to Milestone 1

M1's accuracy targets (top-1 ≥ 80%, top-3 ≥ 95%, macro-F1 ≥ 0.80) are **not met** (0.503 / 0.749 /
0.499). M1 also fixed the measurement protocol — threshold chosen on validation data and frozen
before test evaluation — which is why the test split stays sealed while these failure modes are
investigated.
