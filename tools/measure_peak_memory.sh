#!/usr/bin/env bash
# Peak-memory measurement protocol (Iteration 3).
#
# Memory is an OBSERVATIONAL metric in this project: Milestone 1 sets no pass/fail threshold for it.
# The script samples the app's process memory repeatedly on a physical device and reports the
# maximum, so a figure in the report can be reproduced rather than quoted from one glance.
#
# Usage: tools/measure_peak_memory.sh [device-id] [output-file]
# Env:   SAMPLES (default 30), INTERVAL seconds (default 2)
set -euo pipefail

ADB="${ADB:-${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb}"
DEVICE="${1:-$("$ADB" devices | awk '/device$/{print $1; exit}')}"
OUT="${2:-artifacts/memory/peak_memory.txt}"
SAMPLES="${SAMPLES:-30}"
INTERVAL="${INTERVAL:-2}"
PKG="nz.fieldsnap.app"

[ -n "$DEVICE" ] || { echo "no device attached"; exit 1; }
[ -x "$ADB" ] || { echo "adb not found at $ADB"; exit 1; }
mkdir -p "$(dirname "$OUT")"

{
  echo "# peak-memory protocol"
  # The serial is redacted in the recorded output: see docs/data_privacy.md.
  echo "device=<device-serial-redacted> samples=$SAMPLES interval=${INTERVAL}s package=$PKG"
  echo "build_description=$("$ADB" -s "$DEVICE" shell dumpsys package "$PKG" | grep -m1 versionName || true)"
} | tee "$OUT"

sample() {
  "$ADB" -s "$DEVICE" shell dumpsys meminfo "$PKG" 2>/dev/null > /tmp/meminfo.txt || true
  awk '/TOTAL PSS:/{print $3; found=1} END{if(!found) print 0}' /tmp/meminfo.txt
}
heap() { awk -v key="$1" '$0 ~ key {print $(NF-1); exit}' /tmp/meminfo.txt; }

MAX_TOTAL=0; MAX_JAVA=0; MAX_NATIVE=0
for i in $(seq 1 "$SAMPLES"); do
  TOTAL=$(sample)
  JAVA=$(heap "Java Heap:"); NATIVE=$(heap "Native Heap:")
  TOTAL=${TOTAL:-0}; JAVA=${JAVA:-0}; NATIVE=${NATIVE:-0}
  echo "sample $i total_pss_kb=$TOTAL java_kb=$JAVA native_kb=$NATIVE" >> "$OUT"
  MAX_TOTAL=$(( TOTAL > MAX_TOTAL ? TOTAL : MAX_TOTAL ))
  MAX_JAVA=$(( JAVA > MAX_JAVA ? JAVA : MAX_JAVA ))
  MAX_NATIVE=$(( NATIVE > MAX_NATIVE ? NATIVE : MAX_NATIVE ))
  sleep "$INTERVAL"
done

{
  echo "# summary (observational only; no threshold)"
  echo "peak_total_pss_kb=$MAX_TOTAL"
  echo "peak_java_heap_kb=$MAX_JAVA"
  echo "peak_native_heap_kb=$MAX_NATIVE"
  awk -v t="$MAX_TOTAL" -v j="$MAX_JAVA" -v n="$MAX_NATIVE" \
    'BEGIN{printf "peak_total_pss_mb=%.1f\npeak_java_mb=%.1f\npeak_native_mb=%.1f\n", t/1024, j/1024, n/1024}'
} | tee -a "$OUT"
