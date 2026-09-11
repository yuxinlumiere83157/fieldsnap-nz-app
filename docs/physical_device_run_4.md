# Physical-device run 4 — offline (no network) end-to-end and SQLite persistence

Pixel 8, Android 17 (API 37), arm64. Debug APK built from the current commit. Purpose: the one
submission-critical device run that was still outstanding — the core flow with **no network at all**,
plus a real SQLite history record surviving a force-close and relaunch.

| Item | Value |
| --- | --- |
| Device | Google Pixel 8 (`shiba`), USB (serial redacted; see `docs/data_privacy.md`) |
| OS | Android 17, API 37, build `CP2A.260805.005` |
| Build under test | `flutter build apk --debug` from this commit; uninstalled and reinstalled clean first |
| Task image | `docs/usability/task_images/task1_subject.jpg` (the usability study's fixed Task 1 stimulus) |
| Offline state | `wifi_on = 0`, `Active default network: none`, `ping 8.8.8.8` → **Network is unreachable** |

## Offline proof

`cmd connectivity airplane-mode enable` alone was **not** enough: it reported
`airplane_mode_on = 1` while `wifi_on` stayed `2` and `ping` still succeeded — the automation hook
does not switch the radios on this device. Real offline was therefore established with
`svc wifi disable` + `svc data disable`, and verified three ways before the run:

```
settings get global wifi_on        -> 0
dumpsys connectivity               -> Active default network: none
ping -c 1 -W 3 8.8.8.8             -> connect: Network is unreachable
```

This is recorded because "airplane mode was on" would have been a false claim of offline operation.

## Result

| Step | Observed |
| --- | --- |
| Gallery pick (offline) | platform picker opened, `task1_subject.jpg` selected, preview shown (675x900) |
| Quality gate (FR2) | accepted: brightness 0.47, sharpness 12003.6 |
| On-device inference (FR3) | ran offline and produced top-1 **Nīkau palm 19.33 %**, runner-up tradescantia 18.15 % |
| Abstention (FR4, frozen 0.37) | below threshold → **Uncertain**, not a species claim |
| History (FR6) | one record written; survives force-close and relaunch |
| Crashes | 0 `FATAL EXCEPTION` / `E/AndroidRuntime` lines |

Screenshots: `docs/logs/iter4_offline_01_result.png` (result screen, offline),
`docs/logs/iter4_offline_02_history_after_restart.png` (history after relaunch).

## SQLite persistence, verified at the file level

The app's database was exported with `run-as` and read with sqlite3 rather than inferred from the UI:

```
tables: android_metadata, history, sqlite_sequence
history columns: id, created_at, top_slug, top_common_name, top_scientific_name, top_confidence,
                 runner_up_slug, runner_up_confidence, was_uncertain, confidence_threshold,
                 confidence_policy_validated, quality_brightness, quality_laplacian_variance,
                 quality_accepted, model_label, model_asset
```

Record written by the offline run:

```
id 1 | 2026-09-11T21:08:18.272298 | Nīkau palm (Rhopalostylis sapida) top1=0.1933
     | runner-up tradescantia 0.1815 | uncertain 1 | threshold 0.37 | validated 1
     | quality 0.47 / 12003.6 accepted | fieldsnap_float.tflite (FP32, data v2)
```

After `am force-stop` (process confirmed gone), relaunch and reopening the history screen, the
database re-exported with the **same SHA-256** and the same row; the history screen rendered
`Uncertain | 2026-09-11 21:08 | 19% | threshold 37% | fieldsnap_float.tflite (FP32, data v2) |
brightness 0.47, sharpness 12003.6`.

Two things this proves beyond "it works":

* **No photograph is stored.** The schema has no image, thumbnail or file-path column, so the
  user's photo genuinely cannot be recovered from the database (`docs/history.md`).
* **The policy provenance is stored per row** (`confidence_threshold` 0.37 and
  `confidence_policy_validated` 1), so a record made under a different or uncalibrated threshold
  can never be read later as if it came from this one.

## A false alarm worth recording

Earlier in this session the **Identify species** button appeared unresponsive: four taps over
several minutes looked like no-ops because the UI hierarchy I kept reading still said
"Ready to classify". The button was in fact working — a history record appeared with a timestamp
matching those taps. The stale data came from re-reading a cached `uiautomator` dump; treating the
**database** as the source of truth resolved it immediately. There is no application defect here,
and no code was changed because of it. Both `input tap` and `input touchscreen tap` were fine; the
diagnostic was wrong, not the app.

## Device state afterwards

Wi-Fi and mobile data restored (`Wi-Fi is enabled`, `ping` succeeds), airplane-mode automation flag
cleared, app history left with the single record above. The device is ready for the usability study's
reset checklist, which was itself exercised during this run.
