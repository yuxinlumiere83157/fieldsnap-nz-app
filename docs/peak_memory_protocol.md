# Peak-memory measurement protocol (observational)

Milestone 1 makes **no pass/fail claim** about memory: peak process memory is an observational
metric, recorded on the designated device alongside the model and package sizes. This protocol makes
that number reproducible instead of anecdotal.

## Procedure

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
flutter build apk --debug              # or --profile for a closer-to-shipping figure
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n nz.fieldsnap.app/.MainActivity
# drive the flow: gallery pick -> quality gate -> Identify species
SAMPLES=10 INTERVAL=2 tools/measure_peak_memory.sh <device-id> artifacts/memory/peak_memory_flow.txt
```

The script samples `dumpsys meminfo nz.fieldsnap.app` every `INTERVAL` seconds for `SAMPLES`
samples and reports the **maximum** TOTAL PSS, Java heap and Native heap, with every raw sample kept
in the output file so a reader can see the variance rather than one number.

## Measured on the Pixel 8 (Android 17, API 37, 7.5 GB RAM)

| State | Peak TOTAL PSS | Peak Java heap |
| --- | --- | --- |
| App open, idle capture screen | 362.8 MB | 30.4 MB |
| After a gallery pick, quality gate and on-device classification | **421.0 MB** | 26.4 MB |

Interpretation, with the caveats that matter:

* These are **debug** builds; a profile or release build will differ, and the Flutter debug engine is
  substantially heavier than release. The number is therefore an upper-ish bound for this code, not
  a shipping figure.
* `dumpsys meminfo` does not expose the Flutter engine's native allocations as a "Native Heap" line
  for this process, so that column reads 0 and is reported as unavailable rather than as zero
  consumption.
* 421 MB peak on a 7.5 GB device is not a constraint for this prototype, but it is also not a claim
  that the app is memory-efficient: the model is 3.60 MiB FP32 and runs one image at a time.
* Sampling is coarse (2 s). A spike shorter than the interval can be missed; this is stated because
  the protocol is "observational", not a bound.

## What would make this stronger

* Repeat on a release build and report both figures side by side.
* Add `adb shell dumpsys meminfo --oom` or Perfetto traces if a finer view of the inference spike is
  needed.
* Record the figure per model variant (FP32 vs the experimental INT8) since the model is the part
  most likely to move it.
