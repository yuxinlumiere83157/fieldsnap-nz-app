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

/// Maps a model label (`class_slug`, e.g. `kereru`) to display text.
///
/// Kept separate from the label order: FR5's learning-card content will replace this
/// lookup later, and the classifier must not depend on presentation strings.
class SpeciesDisplayNames {
  const SpeciesDisplayNames(this.bySlug);

  final Map<String, String> bySlug;

  static const Map<String, String> defaults = <String, String>{
    'tui': 'Tūī',
    'kereru': 'Kererū',
    'piwakawaka': 'Pīwakawaka',
    'tauhou': 'Tauhou (silvereye)',
    'korimako': 'Korimako',
    'house_sparrow': 'House sparrow',
    'blackbird': 'Common blackbird',
    'song_thrush': 'Song thrush',
    'starling': 'Common starling',
    'common_myna': 'Common myna',
    'pohutukawa': 'Pōhutukawa',
    'ti_kouka': 'Tī kōuka (cabbage tree)',
    'harakeke': 'Harakeke (NZ flax)',
    'silver_fern': 'Silver fern',
    'nikau': 'Nīkau',
    'kowhai': 'Kōwhai',
    'tradescantia': 'Tradescantia',
    'woolly_nightshade': 'Woolly nightshade',
    'wild_ginger': 'Wild ginger',
    'moth_plant': 'Moth plant',
  };

  String display(String slug) => bySlug[slug] ?? slug;
}
