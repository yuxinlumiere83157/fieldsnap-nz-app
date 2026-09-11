# Engineering rules for this repository

Scope: the FieldSnap NZ Flutter/Android app (the course Milestone 2). This file records what the
app may contain, what must stay out, the architecture boundaries, and how a change is proved to
work. It is written for whoever picks the project up next, including the author returning after a
break.

## Product scope (do not exceed without an explicit request)

In scope for the delivered app: single-image import, basic image-quality gate,
on-device classification with top-3 + confidence, an uncertainty threshold, offline
learning cards, and local history.

Explicitly OUT of scope: user accounts, cloud inference, image uploads, online model
updates, social features, continuous real-time camera inference, audio recognition,
a full iOS delivery, payments, chat, and any analytics/telemetry. Do not add a
backend, Firebase or a network client "because it is convenient".

Iteration 0 adds nothing beyond: project skeleton, one-image import + preview +
replace/clear, error handling, tests, documentation.

## Architecture boundaries (Milestone 1 separation)

- `View` (`lib/views/`) renders state and calls ViewModel commands. No inference, no
  SQL, no direct file reads for decisions.
- `ViewModel` (`lib/viewmodels/`) owns UI state and orchestration. It may only talk to
  service interfaces.
- `Services` (`lib/services/`) contain the replaceable boundaries. The on-device model
  runtime is touched **only** by the inference implementation; persistence is touched
  **only** by a repository and its data-access implementation.
- `Models` (`lib/models/`) are plain immutable value types.
- Dependencies are injected by constructor from `lib/main.dart`. Do not add a DI or
  state-management framework without recording the reason in `docs/progress.md`.

## Honesty rules (non-negotiable)

- Never render an invented species, confidence value, latency, accuracy, screenshot,
  survey result or participant. If a model is absent, show that it is absent.
- Fakes used by tests must be clearly test-only and must not be reachable from
  production code paths.
- Do not mark a Milestone 1 target (NFR1-NFR6, top-1/top-3/macro-F1, coverage) as
  achieved without measured evidence from a defined procedure. Debug-build numbers
  never count as performance evidence.
- Record real events, including blockers, in `docs/progress.md` when they happen.

## Checks required before claiming a change works

```sh
export PATH="$HOME/development/flutter/bin:$PATH"
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="$(/usr/libexec/java_home -v 21)"

flutter pub get
flutter analyze          # must be clean for changed files
flutter test             # unit + widget tests must pass
flutter build apk --debug   # only when the Android toolchain is available
```

Report the exact commands run and their observed result. If a check could not run,
say so explicitly instead of implying success. Device-only behaviour (the real Photo
Picker, timing, memory) must be labelled as "not verified on device" until it has been
run on hardware.

## Repository hygiene

- `reference/`, build output, caches, credentials and participant data stay out of
  version control (see `.gitignore`).
- Do not commit model binaries or datasets whose licence is unverified.
- Keep commits small and describe what was actually verified.
- Do not rewrite existing history; local commits are fine, publishing is a human
  decision.

## Next iteration direction (not to be started in Iteration 0)

Validate model and data feasibility first: candidate label list (~20 Auckland
species), image sources and licences, train/validation/test split, a small real
sample proving train → convert to int8 → on-device call, and confirmation of input
shape, preprocessing and label order. An official generic demo model may be used for a
runtime smoke test only; that proves the integration path, not FieldSnap species
recognition.
