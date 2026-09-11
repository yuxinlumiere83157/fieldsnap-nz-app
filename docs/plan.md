# FieldSnap NZ — Iteration 0 execution plan

Status: proposed and executed on 2026-09-11. Keep this file as the record of the
plan that was actually followed; deviations are noted in `progress.md`.

## Sequence

1. **Read the task material and the design baseline.** Distinguish M1 design intent
   from implemented fact. Note that `reference/M1_report.pdf` is absent, so only the
   summary in the task file is available.
2. **Environment check (evidence-based).** Detect OS/CPU/RAM/disk, Git, Flutter/Dart,
   Android SDK components, JDK(s), ADB, devices. Record actual versions and pick
   versions from official sources instead of "latest". Ask the human before any
   system-level installation.
3. **Create the project root.** New folder, no nested duplicate project, keep the task
   file and a `reference/` folder (git-ignored).
4. **Minimal Flutter Android project** with `CaptureScreen`, `ClassifierViewModel`, a
   replaceable `ImageInput` adapter, explicit data types for pick results and UI state,
   and a `SpeciesClassifier` boundary that reports `modelUnavailable`.
5. **Import/preview slice:** launch → pick one local image → preview → replace → clear,
   with cancellation, read-failure, unsupported-image and plugin-failure recovery.
6. **Tests:** unit tests for the ViewModel and the adapter, widget tests for the flow;
   test-only fakes with no production reachability.
7. **Verification commands:** `flutter doctor -v`, `flutter analyze`, `flutter test`,
   `flutter build apk --debug` (Android chain only), then device run if one exists.
8. **Documentation and version control:** README, ENGINEERING_RULES.md, traceability, progress,
   iteration report, `.gitignore`, `git init` on `main`, local commit. Publishing stays
   a human action.

## Explicit stop point

Stop at the end of Iteration 0. Do not train models, download large datasets, buy
compute, or continue into the full application. The next iteration starts with model
and data feasibility.

## Risks identified up front

| Risk | Handling |
| --- | --- |
| Flutter not installed | ask for installation approval, install stable into `~/development`, record the version |
| No physical Android device attached | static analysis + tests + debug build; device behaviour explicitly "not verified" |
| Real Photo Picker unavailable to automated tests | deterministic fakes for logic; a documented on-device manual verification step |
| `reference/M1_report.pdf` missing | proceed from the design summary; mark everything that depends on the real report as unverified |
| M1 design said API 26+ while Flutter defaults to minSdk 24 | keep Flutter's default, record the difference as a decision item rather than silently changing it |
