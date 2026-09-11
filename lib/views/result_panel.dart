import 'package:flutter/material.dart';

import '../services/classification_result.dart';
import '../services/confidence_policy.dart';
import '../services/species_cards.dart';
import '../viewmodels/classifier_view_model.dart';

/// Renders the classification outcome: an identified species card, the Uncertain state, or an
/// explained failure. It shows only values the model produced, and it never invents a species.
class ResultPanel extends StatelessWidget {
  const ResultPanel({super.key, required this.state, this.cards});

  final ClassifierState state;
  final SpeciesCardRepository? cards;

  @override
  Widget build(BuildContext context) {
    switch (state.resultKind) {
      case ResultKind.none:
      case ResultKind.running:
        return const SizedBox.shrink();
      case ResultKind.identified:
        return _identified(context);
      case ResultKind.uncertain:
        return _uncertain(context);
      case ResultKind.failed:
        return _failed(context);
    }
  }

  Widget _cardShell(BuildContext context, String title, IconData icon, List<Widget> children,
      {Color? background}) {
    final ThemeData theme = Theme.of(context);
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, color: background == null ? null : theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: background == null ? null : theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _identified(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SpeciesCandidate? top = state.topCandidate;
    if (top == null) {
      return const SizedBox.shrink();
    }
    final SpeciesCard? card = state.card;
    final ConfidenceDecision? confidence = state.confidence;

    return _cardShell(
      context,
      'Result',
      Icons.eco_outlined,
      <Widget>[
        Text(card?.commonName ?? top.commonName, style: theme.textTheme.headlineSmall),
        if ((card?.scientificName ?? top.scientificName).isNotEmpty)
          Text(
            card?.scientificName ?? top.scientificName,
            style: theme.textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
          ),
        const SizedBox(height: 6),
        Text(
          'Confidence ${(top.confidence * 100).toStringAsFixed(1)}%'
          '${confidence == null ? '' : '  (threshold '
              '${(confidence.config.acceptThreshold * 100).toStringAsFixed(0)}%'
              '${confidence.config.isValidated ? '' : ', unvalidated'})'}',
          style: theme.textTheme.bodyMedium,
        ),
        if (state.latencyMs > 0)
          Text('On-device inference: ${state.latencyMs} ms (isolate)', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        _candidateList(context),
        if (card != null) ...<Widget>[
          const Divider(height: 24),
          Text('Learning card', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(card.identification, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text('Where to look: ${card.habitat}', style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          Text(
            'Status: ${card.status}${card.maoriName.isEmpty ? '' : '  |  Māori name: ${card.maoriName}'}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  Widget _uncertain(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ConfidenceDecision? confidence = state.confidence;
    return _cardShell(
      context,
      'Uncertain - try another photo',
      Icons.help_outline,
      <Widget>[
        Text(
          'The model was not confident enough to name a species, so FieldSnap is not asserting '
          'one. This is the FR4 abstention path, not a failure.',
          style: theme.textTheme.bodyMedium,
        ),
        if (confidence != null) ...<Widget>[
          const SizedBox(height: 6),
          Text(confidence.reason, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Text('Closest candidates (not asserted):', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        _candidateList(context),
      ],
    );
  }

  Widget _failed(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return _cardShell(
      context,
      'No result',
      Icons.error_outline,
      <Widget>[
        Text(state.errorMessage ?? 'The image could not be classified.',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          'Try a clearer photo, or choose a different image from the gallery.',
          style: theme.textTheme.bodySmall,
        ),
      ],
      background: theme.colorScheme.errorContainer,
    );
  }

  Widget _candidateList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: state.candidates
          .map((SpeciesCandidate candidate) {
            final SpeciesCard? card = cards?.bySlug(candidate.commonName);
            final String label = card?.commonName ?? candidate.commonName;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: <Widget>[
                  Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                  Text('${(candidate.confidence * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.bodyMedium),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}
