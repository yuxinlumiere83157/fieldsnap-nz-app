import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'tflite_species_classifier.dart';

/// Real on-device inference through `tflite_flutter` (the LiteRT/TFLite binding M1
/// selected). Only this adapter touches the interpreter; nothing above it imports
/// `tflite_flutter`.
///
/// The constructor validates the model's actual tensor contract instead of assuming it:
/// a float32 image input **preprocessed externally to [-1, 1]** and a float32 probability
/// output whose width matches the label list. If the exported model disagrees, construction
/// fails loudly rather than producing quiet nonsense.
///
/// The `[0, 255]` wording that used to live here was stale: none of the deployed models do
/// internal rescaling. `assertInputInRange` below is the regression guard for that contract.
class TfliteInferenceEngine implements InferenceEngine {
  TfliteInferenceEngine._(this._interpreter, this.labels, this.outputShape, this._inputShape);

  /// Deployment baseline (Iteration 2).
  ///
  /// The prototype now ships the FP32 model. Evidence for the change (measured on the same
  /// validation split, listed in docs/model_selection.md): FP32 validation top-1 0.497 /
  /// top-3 0.724 versus INT8 0.307 / 0.613, while the 3.60 MiB FP32 asset stays far below the
  /// M1 ceiling of 15 MB for the quantized model. INT8 is kept as an experimental artefact.
  static const String defaultAsset = 'assets/models/fieldsnap_float.tflite';

  /// Experimental INT8 artefact, kept for comparison and future work.
  static const String experimentalInt8Asset = 'assets/models/fieldsnap_int8.tflite';
  static const String defaultLabels = 'assets/models/class_indices.json';

  final Interpreter _interpreter;
  final List<int> _inputShape;

  @override
  final List<String> labels;

  @override
  final List<int> outputShape;

  /// Loads the model from the app's asset bundle.
  static Future<TfliteInferenceEngine> load({
    String assetPath = defaultAsset,
    required List<String> expectedLabels,
    int threads = 2,
  }) async {
    final Interpreter interpreter = await Interpreter.fromAsset(
      assetPath,
      options: InterpreterOptions()..threads = threads,
    );
    return _fromInterpreter(interpreter, expectedLabels);
  }

  /// Loads the model from bytes, for tools and host-side tests that have the file on
  /// disk but no Flutter asset bundle.
  static Future<TfliteInferenceEngine> loadFromBytes({
    required Uint8List bytes,
    required List<String> expectedLabels,
    int threads = 2,
  }) async {
    final Interpreter interpreter = Interpreter.fromBuffer(
      bytes,
      options: InterpreterOptions()..threads = threads,
    );
    return _fromInterpreter(interpreter, expectedLabels);
  }

  /// Shared contract validation: fail loudly rather than run a mismatched model.
  static TfliteInferenceEngine _fromInterpreter(
    Interpreter interpreter,
    List<String> expectedLabels,
  ) {
    final Tensor input = interpreter.getInputTensor(0);
    final Tensor output = interpreter.getOutputTensor(0);
    final List<int> inputShape = List<int>.unmodifiable(input.shape);
    final List<int> outputShape = List<int>.unmodifiable(output.shape);

    if (input.type != TensorType.float32) {
      throw StateError('expected a float32 input tensor, got ${input.type}');
    }
    if (input.shape.length != 4 || input.shape[3] != 3) {
      throw StateError('expected an NHWC RGB input, got ${input.shape}');
    }
    if (outputShape.last != expectedLabels.length) {
      throw StateError('output width ${outputShape.last} does not match '
          '${expectedLabels.length} labels');
    }
    return TfliteInferenceEngine._(
      interpreter,
      List<String>.unmodifiable(expectedLabels),
      outputShape,
      inputShape,
    );
  }

  /// The model's own view of its input, for reports and the cross-language check.
  Map<String, Object> get contract => <String, Object>{
        'input_shape': _inputShape,
        'input_type': 'float32',
        'output_shape': outputShape,
        'output_type': 'float32',
        'labels': labels.length,
        'note': 'input values are float32 RGB in [-1, 1]; preprocessing is external and '
            'applied exactly once by ImagePreprocessor',
      };

  /// Regression guard for the input contract.
  ///
  /// The deployed models were exported with `include_preprocessing=False`, so they expect
  /// `[-1, 1]`. A `[0, 255]` tensor is the exact mistake this project made before and it does
  /// not raise on its own — it just returns wrong predictions. Allowing a small margin keeps
  /// rounding from producing false alarms.
  static void assertInputInRange(Float32List tensor) {
    double minimum = double.infinity;
    double maximum = -double.infinity;
    for (final double value in tensor) {
      minimum = value < minimum ? value : minimum;
      maximum = value > maximum ? value : maximum;
    }
    if (minimum < -1.05 || maximum > 1.05) {
      throw ArgumentError(
        'model input must be float32 RGB in [-1, 1] (external preprocessing, '
        'include_preprocessing=False); got range [$minimum, $maximum]. A [0, 255] tensor '
        'means the rescaling step was skipped — see docs/preprocessing_spec.md',
      );
    }
  }

  @override
  Future<List<double>> run(ModelInput input) async {
    assertInputInRange(input.tensor);
    final int expected = _inputShape[1] * _inputShape[2] * _inputShape[3];
    if (input.tensor.length != expected) {
      throw ArgumentError('tensor has ${input.tensor.length} values, '
          'model expects $expected');
    }
    final List<List<List<double>>> shaped = _reshape(input.tensor);
    // Both sides must be nested to match the model's batch dimension: input [1,H,W,3]
    // and output [1,N]. tflite_flutter throws "Output object shape mismatch" otherwise,
    // and `run` takes `Object`, so the compiler cannot catch it — hence the explicit
    // shapes here and the contract assertion at load time.
    final List<List<double>> output = <List<double>>[
      List<double>.filled(labels.length, 0),
    ];
    _interpreter.run(
      <List<List<List<double>>>>[shaped],
      output,
    );
    return output.first;
  }

  /// NHWC nesting: [height][width][channels], one flat list per image.
  List<List<List<double>>> _reshape(Float32List flat) {
    final int height = _inputShape[1];
    final int width = _inputShape[2];
    final int channels = _inputShape[3];
    int index = 0;
    final List<List<List<double>>> out = <List<List<double>>>[];
    for (int y = 0; y < height; y++) {
      final List<List<double>> row = <List<double>>[];
      for (int x = 0; x < width; x++) {
        final List<double> pixel = <double>[];
        for (int c = 0; c < channels; c++) {
          pixel.add(flat[index++]);
        }
        row.add(pixel);
      }
      out.add(row);
    }
    return out;
  }

  @override
  void dispose() => _interpreter.close();
}
