import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// One offline learning card (FR5). Plain data: no networking, no images.
class SpeciesCard {
  const SpeciesCard({
    required this.slug,
    required this.commonName,
    required this.scientificName,
    required this.group,
    required this.maoriName,
    required this.identification,
    required this.habitat,
    required this.status,
  });

  /// The model label this card belongs to.
  final String slug;
  final String commonName;
  final String scientificName;

  /// `bird` or `plant`.
  final String group;
  final String maoriName;

  /// Short, beginner-facing field marks (FR5's "identification guidance").
  final String identification;

  /// Where a beginner will actually meet the species.
  final String habitat;

  /// `native`, `introduced` or `pest`.
  final String status;

  String get displayName => maoriName.isEmpty ? commonName : maoriName;

  static SpeciesCard fromJson(Map<String, dynamic> json) => SpeciesCard(
        slug: json['slug'] as String,
        commonName: json['common_name'] as String,
        scientificName: json['scientific_name'] as String,
        group: json['group'] as String,
        maoriName: (json['maori_name'] as String?) ?? '',
        identification: json['identification'] as String,
        habitat: json['habitat'] as String,
        status: json['status'] as String,
      );
}

/// Loads the bundled cards. The content ships with the app, so cards work in airplane mode.
class SpeciesCardRepository {
  SpeciesCardRepository._(this._bySlug);

  final Map<String, SpeciesCard> _bySlug;

  static const String assetPath = 'assets/data/species_cards.json';

  static Future<SpeciesCardRepository> fromAsset({String path = assetPath}) async {
    return fromJsonString(await rootBundle.loadString(path), source: path);
  }

  /// Synchronous construction from JSON text, for tests and tools.
  static SpeciesCardRepository fromJsonString(String raw, {String source = assetPath}) {
    final Map<String, dynamic> payload = json.decode(raw) as Map<String, dynamic>;
    final List<dynamic> entries = payload['species'] as List<dynamic>;
    final Map<String, SpeciesCard> bySlug = <String, SpeciesCard>{};
    for (final dynamic entry in entries) {
      final SpeciesCard card = SpeciesCard.fromJson(entry as Map<String, dynamic>);
      if (bySlug.containsKey(card.slug)) {
        throw StateError('duplicate species slug ${card.slug} in $source');
      }
      bySlug[card.slug] = card;
    }
    if (bySlug.isEmpty) {
      throw StateError('no species cards found in $source');
    }
    return SpeciesCardRepository._(bySlug);
  }

  int get length => _bySlug.length;

  List<String> get slugs => _bySlug.keys.toList(growable: false);

  /// Looks up a card; unknown labels return null rather than a made-up species.
  SpeciesCard? bySlug(String slug) => _bySlug[slug];

  /// Verifies that every model label has a card, so the UI can never show a bare slug.
  List<String> missingFor(Iterable<String> modelLabels) =>
      modelLabels.where((String label) => !_bySlug.containsKey(label)).toList(growable: false);
}
