import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Loads the label list that was written by `tools/train_and_export.py`.
///
/// The file is produced in the same run as the `.tflite` model, so the output order of
/// the model and this list cannot drift apart. Never hand-edit it.
class ModelLabels {
  const ModelLabels(this.classes);

  final List<String> classes;

  static const String assetPath = 'assets/models/class_indices.json';

  static Future<ModelLabels> fromAsset({String path = assetPath}) async {
    return fromJsonString(await rootBundle.loadString(path), source: path);
  }

  /// Parses the same file from memory, for tools and integration tests.
  static ModelLabels fromJsonString(String raw, {String source = assetPath}) {
    final Map<String, dynamic> parsed = json.decode(raw) as Map<String, dynamic>;
    final List<String> classes =
        (parsed['classes'] as List<dynamic>).cast<String>();
    if (classes.isEmpty) {
      throw StateError('label file $source contains no classes');
    }
    final Map<String, dynamic>? index = parsed['index'] as Map<String, dynamic>?;
    if (index != null) {
      for (final String name in classes) {
        if (index[name] != classes.indexOf(name)) {
          throw StateError('label file $source has an inconsistent index');
        }
      }
    }
    return ModelLabels(classes);
  }
}
