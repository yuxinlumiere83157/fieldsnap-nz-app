# FR4 confidence policy and the Uncertain state

## Design

`ConfidencePolicyConfig` (in `lib/services/confidence_policy.dart`) holds the numbers; `ConfidencePolicy`
applies them; the ViewModel turns the verdict into UI state. Two rules are supported:

1. **accept threshold** — the top score must reach this value;
2. **margin threshold** (optional) — the top score must lead the runner-up by at least this much.

Either rule can produce `ConfidenceVerdict.uncertain`, and the decision carries a human-readable
reason plus the configuration that produced it, so the result is explainable in the UI and in the
saved history row.

## Deployed configuration (calibrated, Iteration 3)

```dart
ConfidencePolicyConfig(
  acceptThreshold: 0.37,
  marginThreshold: null,
  isValidated: true,
  provenance: 'validation-split sweep, coverage >= 0.70 rule; see '
      'artifacts/confidence_threshold_calibration.json',
)
```

Derived by the pre-registered procedure in
`docs/confidence_threshold_calibration_protocol.md`, on the validation split only (163 images),
scored once with the shipped FP32 model. Selection rule: keep thresholds with coverage ≥ 0.70, then
take the highest accepted-prediction accuracy; ties prefer higher coverage, then the lower threshold.

**Chosen: 0.37** — coverage 0.712, accepted accuracy 0.595. The artefact records the model
SHA-256, validation-manifest SHA-256, run id, commit and protocol SHA-256.

**M1's accepted-accuracy target of ≥ 0.90 is NOT met at that coverage**, nor at any threshold that
keeps coverage ≥ 0.70 (it is only reached at 0.70, where coverage drops to 0.276). The target was not
adjusted, and the flattering operating point was not selected. Full sweep and target verdict:
`docs/iteration_3_calibration_report.md`.

The margin rule is **off** (`marginThreshold: null`). Calibrating a second, interacting rule on the
same split would weaken the calibration; adding it is future work.

## What remains true

* every history row still stores `confidence_policy_validated` **and** the threshold it used, so a
  record made under an older or uncalibrated policy can never be read later as a calibrated result;
* the UI states whether the threshold is calibrated, in words, from the configuration itself;
* tests inject explicit thresholds to exercise both branches (`acceptThreshold: 0.95` forces the
  Uncertain state; `0.30` forces an accept) rather than depending on the deployed value.

## Adding the margin rule properly (future work)

1. Sweep the margin on the validation split with the accept threshold held at 0.37.
2. Pre-register the rule (coverage floor plus an accepted-accuracy objective) before measuring.
3. Record the outcome, including a negative one, and change the deployed config only afterwards.
