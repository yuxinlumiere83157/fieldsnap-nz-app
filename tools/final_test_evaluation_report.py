#!/usr/bin/env python3
"""Builds docs/final_test_evaluation_report.md from the one-shot test predictions.

Reads artifacts/final_test_predictions.json (produced by the Dart harness with the production path)
and the frozen configuration, computes the pre-registered metrics, and writes the report with full
provenance. Does not run the model itself and does not modify any threshold.
"""
from __future__ import annotations

import datetime, hashlib, json, pathlib, subprocess, sys

REPO = pathlib.Path(__file__).resolve().parents[1]
ART = REPO / "artifacts"

TARGETS = {"top1": 0.80, "top3": 0.95, "macro_f1": 0.80, "accepted_accuracy": 0.90,
           "coverage_floor": 0.70}


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    preds = json.loads((ART / "final_test_predictions.json").read_text())
    rows = preds["rows"]
    labels = json.loads((REPO / "assets/models/class_indices.json").read_text())["classes"]
    conf = json.loads((ART / "confidence_threshold_calibration.json").read_text())
    threshold = conf["chosen_threshold"]
    qg = json.loads((ART / "quality_gate_verification.json").read_text())["chosen_thresholds"]
    model = REPO / "assets/models/fieldsnap_float.tflite"
    test_manifest = REPO / "data/manifest_test.csv"
    protocol = REPO / "docs/final_test_evaluation_protocol.md"
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=REPO,
                            capture_output=True, text=True).stdout.strip()

    n = len(rows)
    top1 = sum(1 for r in rows if r["correct_top1"]) / n
    top3 = sum(1 for r in rows if r["correct_top3"]) / n

    # per-class precision / recall / F1 + confusion matrix
    confusion = {t: {p: 0 for p in labels} for t in labels}
    for r in rows:
        confusion[r["truth"]][r["predicted"]] += 1
    per_class = {}
    f1s = []
    for cls in labels:
        tp = confusion[cls][cls]
        fn = sum(confusion[cls][p] for p in labels if p != cls)
        fp = sum(confusion[t][cls] for t in labels if t != cls)
        support = tp + fn
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / support if support else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        f1s.append(f1)
        per_class[cls] = {"support": support, "precision": precision, "recall": recall,
                          "f1": f1, "correct": tp}
    macro_f1 = sum(f1s) / len(f1s)

    # frozen confidence threshold applied to the same predictions
    accepted = [r for r in rows if r["top1_score"] >= threshold]
    rejected = [r for r in rows if r["top1_score"] < threshold]
    coverage = len(accepted) / n
    accepted_accuracy = (sum(1 for r in accepted if r["correct_top1"]) / len(accepted)
                         if accepted else 0.0)
    rejected_accuracy = (sum(1 for r in rejected if r["correct_top1"]) / len(rejected)
                         if rejected else 0.0)

    verdicts = {
        "top1 >= 0.80": (top1, top1 >= TARGETS["top1"]),
        "top3 >= 0.95": (top3, top3 >= TARGETS["top3"]),
        "macro_f1 >= 0.80": (macro_f1, macro_f1 >= TARGETS["macro_f1"]),
        "accepted accuracy >= 0.90 at coverage >= 0.70": (
            accepted_accuracy, accepted_accuracy >= TARGETS["accepted_accuracy"]
            and coverage >= TARGETS["coverage_floor"]),
    }

    run_id = datetime.datetime.now().strftime("%Y%m%dT%H%M%S") + "-" + sha(model)[:8]
    stamp = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
    raw = {
        "run_id": run_id, "timestamp": stamp, "commit": commit,
        "model": {"path": "assets/models/fieldsnap_float.tflite", "sha256": sha(model)},
        "test_manifest": {"path": "data/manifest_test.csv", "sha256": sha(test_manifest)},
        "protocol_sha256": sha(protocol),
        "labels_sha256": sha(REPO / "assets/models/class_indices.json"),
        "images": n,
        "metrics": {"top1": top1, "top3": top3, "macro_f1": macro_f1,
                    "coverage": coverage, "accepted": len(accepted), "rejected": len(rejected),
                    "accepted_accuracy": accepted_accuracy,
                    "rejected_accuracy": rejected_accuracy},
        "confidence_threshold": threshold,
        "fr2_thresholds": qg,
        "targets": {k: {"measured": v[0], "met": bool(v[1])} for k, v in verdicts.items()},
        "per_class": per_class,
        "confusion_matrix": confusion,
        "label_order": labels,
    }
    (ART / "final_test_evaluation.json").write_text(json.dumps(raw, indent=2))

    L = []
    A = L.append
    A("# Final test-set evaluation report")
    A("")
    A(f"**One-shot evaluation of the sealed test split**, run once on {stamp} at commit `{commit[:12]}`")
    A("under the pre-registered protocol `docs/final_test_evaluation_protocol.md` (SHA-256")
    A(f"`{raw['protocol_sha256'][:16]}…`). The split was sealed at the 1A freeze and opened only now.")
    A("")
    A("## Provenance")
    A("")
    A("| Item | Value |")
    A("| --- | --- |")
    A(f"| Run id | `{run_id}` |")
    A(f"| Timestamp | {stamp} |")
    A(f"| Commit | `{commit}` |")
    A(f"| Model | `assets/models/fieldsnap_float.tflite` |")
    A(f"| Model SHA-256 | `{raw['model']['sha256']}` |")
    A(f"| Test manifest | `data/manifest_test.csv` |")
    A(f"| Test-manifest SHA-256 | `{raw['test_manifest']['sha256']}` |")
    A(f"| Label file SHA-256 | `{raw['labels_sha256']}` |")
    A(f"| Images evaluated | {n} (all images in the split; none skipped) |")
    A(f"| Classes | {len(labels)} |")
    A(f"| Preprocessing | production `ImagePreprocessor` (decode, EXIF, RGB, 224x224 area resize, `(x-127.5)/127.5`) |")
    A(f"| Frozen FR2 thresholds | minBrightness {qg['min_brightness']}, maxBrightness {qg['max_brightness']}, minLaplacianVariance {qg['min_laplacian_variance']:.1f} |")
    A(f"| Frozen FR4 threshold | {threshold} (margin rule disabled) |")
    A(f"| Raw predictions | `artifacts/final_test_predictions.json` |")
    A(f"| Computed metrics | `artifacts/final_test_evaluation.json` |")
    A("")
    A("## Headline metrics (all test images, no quality-gate filtering)")
    A("")
    A("| Metric | Value | M1 target | Met? |")
    A("| --- | --- | --- | --- |")
    A(f"| Top-1 accuracy | **{top1:.4f}** ({sum(1 for r in rows if r['correct_top1'])}/{n}) | >= 0.80 | "
      f"{'**yes**' if verdicts['top1 >= 0.80'][1] else '**no**'} |")
    A(f"| Top-3 accuracy | **{top3:.4f}** ({sum(1 for r in rows if r['correct_top3'])}/{n}) | >= 0.95 | "
      f"{'**yes**' if verdicts['top3 >= 0.95'][1] else '**no**'} |")
    A(f"| Macro-F1 | **{macro_f1:.4f}** | >= 0.80 | "
      f"{'**yes**' if verdicts['macro_f1 >= 0.80'][1] else '**no**'} |")
    A("")
    A("## FR4 threshold applied (frozen at 0.37, not re-tuned on the test set)")
    A("")
    A("| Quantity | Value |")
    A("| --- | --- |")
    A(f"| Coverage | **{coverage:.4f}** ({len(accepted)}/{n} images answered) |")
    A(f"| Accepted images | {len(accepted)} |")
    A(f"| Rejected (Uncertain) images | {len(rejected)} |")
    A(f"| Accepted-prediction accuracy | **{accepted_accuracy:.4f}** |")
    A(f"| Rejected-subset accuracy (top-1, for transparency) | {rejected_accuracy:.4f} |")
    A("")
    A(f"M1 requires accepted accuracy >= {TARGETS['accepted_accuracy']:.2f} while coverage >= "
      f"{TARGETS['coverage_floor']:.2f}: **{'met' if verdicts['accepted accuracy >= 0.90 at coverage >= 0.70'][1] else 'NOT met'}** "
      f"(measured {accepted_accuracy:.4f} at coverage {coverage:.4f}).")
    A("")
    A("## Per-class precision / recall / F1")
    A("")
    A("| Class | Support | Correct | Precision | Recall | F1 |")
    A("| --- | --- | --- | --- | --- | --- |")
    for cls in sorted(labels, key=lambda c: per_class[c]["f1"]):
        m = per_class[cls]
        A(f"| {cls} | {m['support']} | {m['correct']} | {m['precision']:.3f} | {m['recall']:.3f} | {m['f1']:.3f} |")
    A("")
    A("## Confusion matrix (rows = truth, columns = prediction)")
    A("")
    A("| truth \\ pred | " + " | ".join(labels) + " |")
    A("| --- | " + " | ".join("---" for _ in labels) + " |")
    for t in labels:
        cells = " | ".join(str(confusion[t][p]) for p in labels)
        A(f"| **{t}** | {cells} |")
    A("")
    A("## Target evaluation as written (no target was adjusted)")
    A("")
    A("| M1 acceptance target | Measured | Verdict |")
    A("| --- | --- | --- |")
    A(f"| Held-out top-1 >= 0.80 | {top1:.4f} | {'MET' if verdicts['top1 >= 0.80'][1] else '**NOT MET**'} |")
    A(f"| Held-out top-3 >= 0.95 | {top3:.4f} | {'MET' if verdicts['top3 >= 0.95'][1] else '**NOT MET**'} |")
    A(f"| Macro-F1 >= 0.80 | {macro_f1:.4f} | {'MET' if verdicts['macro_f1 >= 0.80'][1] else '**NOT MET**'} |")
    A(f"| Accepted accuracy >= 0.90 at coverage >= 0.70 | {accepted_accuracy:.4f} at {coverage:.4f} | "
      f"{'MET' if verdicts['accepted accuracy >= 0.90 at coverage >= 0.70'][1] else '**NOT MET**'} |")
    A("")
    A("## Interpretation and limits")
    A("")
    A("* **All four M1 acceptance targets are not met.** Measured: top-1 "
      f"{top1:.4f} (target 0.80), top-3 {top3:.4f} (target 0.95), macro-F1 {macro_f1:.4f} "
      f"(target 0.80), and accepted accuracy {accepted_accuracy:.4f} at coverage {coverage:.4f} "
      "(target 0.90 at coverage >= 0.70). Top-3 is the closest of the four and still misses.")
    A("* The test split is small (187 images, 6-17 per class, 20 classes), so per-class numbers carry")
    A("  wide uncertainty; single-image changes move a class F1 by roughly 0.1. The headline numbers are")
    A("  reported because they are the pre-registered evaluation, not because they are precise.")
    A("* The threshold was fixed before this run and was **not** moved afterwards. Moving it now to")
    A("  improve the accepted-accuracy figure would invalidate the calibration and is explicitly")
    A("  forbidden by the protocol; the frozen operating point answers "
      f"{coverage:.1%} of images and is wrong on {(1 - accepted_accuracy):.1%} of the ones it answers.")
    A("* Test images were evaluated regardless of the FR2 quality gate, as the protocol requires, so")
    A("  these numbers describe the classifier, not the gate.")
    A("* The failure structure (background/colour shortcuts, similar species pairs) was analysed on the")
    A("  validation split in `docs/model_error_analysis.md` before this run. Several of the pairs it")
    A("  predicted dominate the matrix above (for example tauhou/blackbird and the tradescantia /")
    A("  wild-ginger / moth-plant cluster), which is consistent with that analysis - but it was written")
    A("  without sight of the test split and made no change to the model.")
    A("* Rejected-subset accuracy "
      f"({rejected_accuracy:.4f}) is reported for transparency: the threshold does concentrate errors")
    A("  into the rejected subset, as intended, but the accepted subset is still far from the target.")
    A("")
    A("## Post-evaluation freeze")
    A("")
    A("Per the protocol: **no model, class-set, preprocessing or threshold change is permitted on the")
    A("basis of these results.** The test split has now been read once and will not be used again as a")
    A("selection signal. Any further modelling work must use the validation split or a newly provisioned")
    A("test set, recorded as a new iteration with its own pre-registered protocol.")
    A("")
    A("## Not done in this evaluation")
    A("")
    A("* No retraining, no data expansion, no class changes, no QAT, no threshold adjustment.")
    A("* No usability testing (no participants, no SUS, no first-task success measurement).")
    A("")
    (REPO / "docs/final_test_evaluation_report.md").write_text("\n".join(L) + "\n")

    print(f"run {run_id}")
    print(f"top1={top1:.4f} top3={top3:.4f} macro_f1={macro_f1:.4f}")
    print(f"coverage={coverage:.4f} accepted_acc={accepted_accuracy:.4f} rejected_acc={rejected_accuracy:.4f}")
    for k, (v, met) in verdicts.items():
        print(f"  {k}: {'MET' if met else 'NOT MET'} ({v:.4f})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
