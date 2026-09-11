import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Configuration for the FR2 image-quality gate.
///
/// Thresholds live here (injected, not hard-coded) so they can be tuned from evidence and so
/// tests can supply explicit values. See docs/quality_gate.md for how the defaults were chosen
/// and how development samples were used.
class QualityGateConfig {
  /// Frozen by the calibration run of 2026-09-11 (Iteration 3).
  ///
  /// Provenance: `docs/quality_gate_calibration_protocol.md` (pre-registered, with one recorded
  /// amendment), `artifacts/quality_gate_calibration.json`, and the one-shot verification in
  /// `artifacts/quality_gate_verification.json` (run id recorded there). On the independent
  /// verification subset the gate measured:
  ///
  ///  * reject recall: dark 1.000, blurred 0.988,
  ///    overexposed 0.171;
  ///  * false rejection of acceptable photos: 0.012.
  ///
  /// The overexposure figure is reported, not optimised: the clipped condition overlaps valid
  /// bright photos, so `maxBrightness` is a safety ceiling rather than an overexposure detector.
  const QualityGateConfig({
    this.minBrightness = 0.26,
    this.maxBrightness = 0.89,
    this.minLaplacianVariance = 100.0,
    this.analysisSize = 224,
  });

  /// Minimum mean luma in `[0, 1]`; below this the photo is too dark to classify.
  final double minBrightness;

  /// Maximum mean luma in `[0, 1]`; above this the photo is blown out.
  final double maxBrightness;

  /// Minimum variance of the Laplacian; below this the photo has too little high-frequency
  /// detail to be trusted (blur, motion smear, or a featureless background).
  final double minLaplacianVariance;

  /// Images are analysed after downscaling to this square size, which keeps the metric cheap
  /// and scale-stable.
  final int analysisSize;

  Map<String, Object> toJson() => <String, Object>{
        'min_brightness': minBrightness,
        'max_brightness': maxBrightness,
        'min_laplacian_variance': minLaplacianVariance,
        'analysis_size': analysisSize,
      };
}

/// Why an image failed the quality gate. Each reason carries the measured value so the UI can
/// explain the decision instead of just refusing.
enum QualityFailureKind { tooDark, tooBright, tooBlurry, undecodable }

class QualityMetrics {
  const QualityMetrics({required this.brightness, required this.laplacianVariance});

  /// Mean luma in `[0, 1]`.
  final double brightness;

  /// Variance of the Laplacian of the grayscale analysis image (arbitrary but comparable units).
  final double laplacianVariance;

  Map<String, Object> toJson() => <String, Object>{
        'brightness': double.parse(brightness.toStringAsFixed(4)),
        'laplacian_variance': double.parse(laplacianVariance.toStringAsFixed(4)),
      };
}

class QualityDecision {
  const QualityDecision.passed(this.metrics)
      : kind = null,
        measured = null,
        threshold = null;

  const QualityDecision.failed({
    required QualityFailureKind this.kind,
    required QualityMetrics this.metrics,
    required double this.measured,
    required double this.threshold,
  });

  final QualityMetrics? metrics;
  final QualityFailureKind? kind;
  final double? measured;
  final double? threshold;

  bool get isAcceptable => kind == null;

  /// One-line, user-facing explanation with the measured value and the threshold.
  String get explanation {
    final QualityMetrics m = metrics!;
    switch (kind) {
      case null:
        return 'Image quality accepted (brightness ${m.brightness.toStringAsFixed(2)}, '
            'detail ${m.laplacianVariance.toStringAsFixed(1)}).';
      case QualityFailureKind.tooDark:
        return 'Too dark: brightness ${m.brightness.toStringAsFixed(2)} is below the '
            '${threshold!.toStringAsFixed(2)} minimum. Try again with more light.';
      case QualityFailureKind.tooBright:
        return 'Overexposed: brightness ${m.brightness.toStringAsFixed(2)} is above the '
            '${threshold!.toStringAsFixed(2)} maximum. Avoid direct glare.';
      case QualityFailureKind.tooBlurry:
        return 'Too little detail: sharpness ${m.laplacianVariance.toStringAsFixed(1)} is '
            'below the ${threshold!.toStringAsFixed(0)} minimum. Hold still and refocus.';
      case QualityFailureKind.undecodable:
        return 'The image could not be decoded for a quality check.';
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'acceptable': isAcceptable,
        'kind': kind?.name,
        'explanation': explanation,
        if (metrics != null) 'metrics': metrics!.toJson(),
        if (measured != null) 'measured': double.parse(measured!.toStringAsFixed(4)),
        if (threshold != null) 'threshold': threshold,
      };
}

/// Explainable brightness/blur gate (FR2). Deliberately not a model: two published, simple
/// metrics with configurable thresholds.
///
/// * **brightness** = mean luma of the decoded image, `0.0`-`1.0`.
/// * **blur** = variance of the Laplacian over the grayscale image, computed on the **0-255**
///   pixel scale. High variance means sharp edges; a flat or smeared image gives a low value.
///   This is the classic "blur detection with the Laplacian" approach, chosen because it is
///   cheap, deterministic and easy to explain. The scale matters: computing it on normalised
///   `[0, 1]` values divides the metric by 255 squared, so the first version of this gate
///   rejected every image as blurry. The thresholds in [QualityGateConfig] are in 0-255 units
///   and were checked against real photos (see docs/quality_gate.md).
class ImageQualityGate {
  const ImageQualityGate([this.config = const QualityGateConfig()]);

  final QualityGateConfig config;

  /// Evaluates an accepted image file. Never throws: an undecodable image is a reported failure.
  QualityDecision evaluateFile(dynamic pickedImage) {
    final String path = pickedImage.path as String;
    return evaluate(File(path).readAsBytesSync());
  }

  /// Evaluates [encodedImage]. Never throws.
  ///
  /// The decode is wrapped because the `image` package can throw a `RangeError` from a format
  /// probe (a short file starts the PSD decoder, which then reads past the end) rather than
  /// returning null. A quality gate that crashes on a junk file would be worse than useless: the
  /// user would lose the recovery path.
  QualityDecision evaluate(Uint8List encodedImage) {
    img.Image? decoded;
    try {
      decoded = img.decodeImage(encodedImage);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      return const QualityDecision.failed(
        kind: QualityFailureKind.undecodable,
        metrics: QualityMetrics(brightness: 0, laplacianVariance: 0),
        measured: 0,
        threshold: 0,
      );
    }
    return evaluateDecoded(decoded);
  }

  QualityDecision evaluateDecoded(img.Image decoded) {
    final int size = config.analysisSize;
    final img.Image small = img.copyResize(
      decoded,
      width: size,
      height: size,
      interpolation: img.Interpolation.average,
    );
    final img.Image gray = img.grayscale(small);

    double totalLuma = 0;
    // Raw 0-255 luma: brightness is normalised for the threshold, the Laplacian is not.
    final Float64List luma = Float64List(size * size);
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final double value = gray.getPixel(x, y).r.toDouble();
        luma[y * size + x] = value;
        totalLuma += value;
      }
    }
    final double brightness = (totalLuma / (size * size)) / 255.0;
    final double variance = _laplacianVariance(luma, size);
    final QualityMetrics metrics =
        QualityMetrics(brightness: brightness, laplacianVariance: variance);

    if (brightness < config.minBrightness) {
      return QualityDecision.failed(
        kind: QualityFailureKind.tooDark,
        metrics: metrics,
        measured: brightness,
        threshold: config.minBrightness,
      );
    }
    if (brightness > config.maxBrightness) {
      return QualityDecision.failed(
        kind: QualityFailureKind.tooBright,
        metrics: metrics,
        measured: brightness,
        threshold: config.maxBrightness,
      );
    }
    if (variance < config.minLaplacianVariance) {
      return QualityDecision.failed(
        kind: QualityFailureKind.tooBlurry,
        metrics: metrics,
        measured: variance,
        threshold: config.minLaplacianVariance,
      );
    }
    return QualityDecision.passed(metrics);
  }

  /// Variance of the 4-neighbour Laplacian, excluding the border.
  double _laplacianVariance(Float64List luma, int size) {
    final List<double> responses = <double>[];
    double sum = 0;
    for (int y = 1; y < size - 1; y++) {
      for (int x = 1; x < size - 1; x++) {
        final int i = y * size + x;
        final double response = 4 * luma[i] -
            luma[i - 1] -
            luma[i + 1] -
            luma[i - size] -
            luma[i + size];
        responses.add(response);
        sum += response;
      }
    }
    if (responses.isEmpty) {
      return 0;
    }
    final double mean = sum / responses.length;
    double squared = 0;
    for (final double value in responses) {
      squared += math.pow(value - mean, 2).toDouble();
    }
    return squared / responses.length;
  }
}
