import 'dart:io';

import 'package:flutter/material.dart';

import '../models/pick_errors.dart';
import '../models/picked_image.dart';
import '../services/history_repository.dart';
import '../services/quality_gate.dart';
import '../services/species_cards.dart';
import '../viewmodels/classifier_view_model.dart';
import 'history_screen.dart';
import 'result_panel.dart';

/// Capture screen: pick or shoot ONE photo, see the quality verdict, classify on-device, and read
/// the result as a species card, an Uncertain message, or an explained failure.
///
/// Scope guard: the widget only renders [ClassifierState] and calls ViewModel commands. It never
/// runs inference, never touches SQL, and never displays a species or confidence that a real model
/// did not produce.
class CaptureScreen extends StatelessWidget {
  const CaptureScreen({
    super.key,
    required this.viewModel,
    this.cards,
    this.history,
  });

  final ClassifierViewModel viewModel;
  final SpeciesCardRepository? cards;
  final HistoryRepository? history;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FieldSnap NZ'),
        actions: <Widget>[
          IconButton(
            onPressed: history == null
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) =>
                            HistoryScreen(repository: history!),
                      ),
                    ),
            icon: const Icon(Icons.history),
            tooltip: 'Identification history',
          ),
          IconButton(
            onPressed: viewModel.state.hasImage ? viewModel.clearImage : null,
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear selected image',
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: viewModel,
        builder: (BuildContext context, Widget? _) => _CaptureBody(
          viewModel: viewModel,
          cards: cards,
        ),
      ),
    );
  }
}

class _CaptureBody extends StatelessWidget {
  const _CaptureBody({required this.viewModel, this.cards});

  final ClassifierViewModel viewModel;
  final SpeciesCardRepository? cards;

  @override
  Widget build(BuildContext context) {
    final ClassifierState state = viewModel.state;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _StatusCard(state: state, viewModel: viewModel),
          if (state.error != null) ...<Widget>[
            const SizedBox(height: 12),
            _ErrorPanel(error: state.error!, onRetry: viewModel.pickImage),
          ],
          const SizedBox(height: 12),
          _PreviewCard(state: state),
          const SizedBox(height: 12),
          _CaptureActions(state: state, viewModel: viewModel),
          if (state.quality != null) ...<Widget>[
            const SizedBox(height: 12),
            _QualityCard(quality: state.quality!),
          ],
          const SizedBox(height: 12),
          _ClassifySection(state: state, viewModel: viewModel, cards: cards),
          if (state.resultKind != ResultKind.none) ...<Widget>[
            const SizedBox(height: 12),
            ResultPanel(state: state, cards: cards),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state, required this.viewModel});

  final ClassifierState state;
  final ClassifierViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Step 1 - Choose one photo', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_message(), style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }

  String _message() {
    if (state.error != null) {
      return 'The last image could not be used. See the message below.';
    }
    switch (state.status) {
      case SelectionStatus.idle:
        return viewModel.classificationUnavailableMessage;
      case SelectionStatus.picking:
        return 'Waiting for the camera or the photo picker...';
      case SelectionStatus.ready:
        return state.hasQualityPass
            ? 'Image accepted. It passed the brightness and sharpness checks.'
            : 'Image selected, but it did not pass the quality check.';
    }
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.state});

  final ClassifierState state;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PickedImage? image = state.image;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Preview', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (image == null)
              Container(
                height: 160,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('No image selected yet'),
              )
            else ...<Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: Image.file(
                  File(image.path),
                  fit: BoxFit.contain,
                  errorBuilder: (BuildContext context, Object error, StackTrace? _) {
                    return Container(
                      height: 160,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'This file could not be displayed. It may have been moved or may not be '
                        'a supported image format.\nChoose another image to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text('File: ${_fileName(image.path)}', style: theme.textTheme.bodySmall),
              Text('Size: ${image.readableSize}', style: theme.textTheme.bodySmall),
              Text('Pixels: ${image.readableDimensions}', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }

  String _fileName(String path) {
    final int index = path.lastIndexOf(Platform.pathSeparator);
    return index == -1 ? path : path.substring(index + 1);
  }
}

class _CaptureActions extends StatelessWidget {
  const _CaptureActions({required this.state, required this.viewModel});

  final ClassifierState state;
  final ClassifierViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: <Widget>[
        FilledButton.icon(
          onPressed: state.isPicking
              ? null
              : () => viewModel.pickImage(channel: CaptureChannel.gallery),
          icon: const Icon(Icons.photo_library_outlined),
          label: Text(state.hasImage ? 'Replace from gallery' : 'Select from gallery'),
        ),
        FilledButton.tonalIcon(
          onPressed: state.isPicking
              ? null
              : () => viewModel.pickImage(channel: CaptureChannel.camera),
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Take photo'),
        ),
        OutlinedButton.icon(
          onPressed: state.hasImage ? viewModel.clearImage : null,
          icon: const Icon(Icons.close),
          label: const Text('Clear selection'),
        ),
      ],
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({required this.quality});

  final QualityDecision quality;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool ok = quality.isAcceptable;
    return Card(
      color: ok ? null : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
                  color: ok
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  'Step 2 - Image quality',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: ok ? null : theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              quality.explanation,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: ok ? null : theme.colorScheme.onErrorContainer,
              ),
            ),
            if (quality.metrics != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                'Brightness ${quality.metrics!.brightness.toStringAsFixed(2)}  |  '
                'Sharpness ${quality.metrics!.laplacianVariance.toStringAsFixed(1)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ok ? null : theme.colorScheme.onErrorContainer,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ClassifySection extends StatelessWidget {
  const _ClassifySection({required this.state, required this.viewModel, this.cards});

  final ClassifierState state;
  final ClassifierViewModel viewModel;
  final SpeciesCardRepository? cards;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool hasCards = cards != null && cards!.length > 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Step 3 - Identification', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(viewModel.classificationUnavailableMessage,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: state.canClassify
                  ? () {
                      viewModel.prepare();
                      viewModel.classify();
                    }
                  : null,
              icon: state.isClassifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(state.isClassifying
                  ? 'Classifying on this device...'
                  : 'Identify species'),
            ),
            const SizedBox(height: 8),
            Text(
              hasCards
                  ? 'Runs the bundled model on this device. No network request, no upload.'
                  : 'The model runs on this device. Learning cards are not bundled in this build.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(viewModel.confidencePolicyNote, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              'Model: ${state.modelAsset.isEmpty ? "not configured" : state.modelAsset}'
              '${state.latencyMs > 0 ? "  |  last run ${state.latencyMs} ms" : ""}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final PickError error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String title, String detail) = _copyFor(error);

    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () => onRetry(),
              child: const Text('Choose another image'),
            ),
          ],
        ),
      ),
    );
  }

  (String, String) _copyFor(PickError error) {
    switch (error.reason) {
      case PickErrorReason.unsupportedImage:
        return (
          'Unsupported image',
          'FieldSnap could not read this image format. Pick a JPEG or PNG photo.',
        );
      case PickErrorReason.readFailed:
        return (
          'Could not read the image',
          'The selected file could not be opened. It may have been moved or deleted. '
              'Choose another image.',
        );
      case PickErrorReason.platformFailure:
        return (
          'Image selection failed',
          'The system picker reported a problem. You can try again.',
        );
      case PickErrorReason.cancelled:
        return (
          'No image selected',
          'Selection was cancelled. Nothing changed.',
        );
      case PickErrorReason.permissionDenied:
        return (
          'Camera unavailable',
          'FieldSnap could not use the camera: permission was refused or no camera app is '
              'available. You can still choose an existing photo from the gallery.',
        );
    }
  }
}
