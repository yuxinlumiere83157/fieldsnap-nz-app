# Data privacy rules for this repository

This repository is **public** (Milestone 2 requires marker access), so the publication rules are
deliberate rather than incidental. This file records what is kept, what is removed, and why.

## Belongs in the repository

* Our own source code, tests, configuration and technical documentation.
* Licence and provenance metadata: photo id, observation id, class, group, licence code,
  attribution string, observation date, taxon id/name, CDN URL, image md5 and byte size.
* The frozen split protocol and `data_version_2.json`, plus small model assets (the FP8/INT8
  `.tflite` files and the label list) so a reviewer can run the app without retraining.

## Does not belong in the repository

| Item | Why | Where it lives instead |
| --- | --- | --- |
| **Precise and near-precise observation locations** (`latitude`, `longitude`, `place_guess`) | Never used for training or evaluation, so they add no reproducibility value — but they do carry publication risk, and iNaturalist itself obscures coordinates for sensitive taxa. | Removed from the published manifests; the local-only download manifest may still contain what the API returned, and is git-ignored |
| **The original photographs** | Their licences allow use but the repository should not become a redistribution mirror; they are reproducible from the manifest. | Local `data/raw/` only (git-ignored) |
| **The Milestone 1 report and course material** | Personal submission and teaching material. | Local `reference/` (git-ignored) |
| **Device identifiers** (serial numbers, ADB ids) | Not needed to reproduce anything, and they identify a physical device. | Redacted from `docs/physical_device_run.md`; recorded privately if needed |
| **User photographs at runtime** | The app must not copy the user's media. | Never stored: see `docs/history.md` |
| **Credentials, keystores, `.env` files** | Obvious, but listed so the rule is explicit. | git-ignored |

## Guards in the code

* `tools/fetch_dataset.py` no longer even records `latitude`, `longitude` or `place_guess`.
* `tools/build_train_manifest.py` strips those columns if an older local manifest still has them,
  so they cannot leak back in through regeneration.
* `data/provenance_shareable.csv` is generated without location or local-path columns.
* `.gitignore` excludes `reference/`, `data/raw/`, `data/cache/` and the full local manifests.

## Audit performed before Iteration 2 was pushed

* no device serial, phone number, account detail or coordinate value appears in any tracked file;
* the only people-related content in the repository is the **photo attributions**, which the CC
  licences require;
* during the physical-device run the platform picker displayed the device's own photo library and
  an early automated tap selected a private screenshot. It was never classified, never written to
  the history database, never committed, and the single captured frame was deleted immediately;
  the app was then uninstalled and the pushed sample photo removed from the device.
