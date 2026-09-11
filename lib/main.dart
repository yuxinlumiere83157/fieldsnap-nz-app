import 'package:flutter/material.dart';

import 'services/confidence_policy.dart';
import 'services/file_system_image_input.dart';
import 'services/history_repository.dart';
import 'services/image_input.dart';
import 'services/model_labels.dart';
import 'services/on_device_species_classifier.dart';
import 'services/quality_gate.dart';
import 'services/sqflite_history_repository.dart';
import 'services/species_cards.dart';
import 'services/species_classifier.dart';
import 'viewmodels/classifier_view_model.dart';
import 'views/capture_screen.dart';

/// Everything the app needs, built once at startup and injected downwards.
class FieldSnapDependencies {
  const FieldSnapDependencies({
    required this.imageInput,
    required this.classifier,
    required this.cards,
    required this.history,
    required this.qualityGate,
    required this.confidencePolicy,
    required this.modelAsset,
    required this.modelLabel,
  });

  final ImageInput imageInput;
  final SpeciesClassifier classifier;
  final SpeciesCardRepository cards;
  final HistoryRepository history;
  final ImageQualityGate qualityGate;
  final ConfidencePolicy confidencePolicy;
  final String modelAsset;
  final String modelLabel;
}

void main() {
  runApp(const FieldSnapBootstrap());
}

/// Loads the bundled assets, then shows the app. Failures are surfaced instead of swallowed: if
/// the cards or the label list cannot be read, the user is told rather than shown an empty screen.
class FieldSnapBootstrap extends StatefulWidget {
  const FieldSnapBootstrap({super.key});

  @override
  State<FieldSnapBootstrap> createState() => _FieldSnapBootstrapState();
}

class _FieldSnapBootstrapState extends State<FieldSnapBootstrap> {
  late Future<FieldSnapDependencies> _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = _build();
  }

  Future<FieldSnapDependencies> _build() async {
    final SpeciesCardRepository cards = await SpeciesCardRepository.fromAsset();
    final ModelLabels labels = await ModelLabels.fromAsset();
    final FileSystemImageInput picker = FileSystemImageInput();
    // SQLite history on a real platform; the in-memory repository is only a fallback so a desktop
    // debug run without the sqflite plugin still starts.
    HistoryRepository history;
    try {
      history = await SqfliteHistoryRepository.open();
    } catch (error) {
      history = InMemoryHistoryRepository();
      debugPrint('FieldSnap: SQLite history unavailable ($error); using memory store');
    }
    return FieldSnapDependencies(
      imageInput: picker,
      classifier: await OnDeviceSpeciesClassifier.create(labels: labels),
      cards: cards,
      history: history,
      qualityGate: const ImageQualityGate(),
      confidencePolicy: const ConfidencePolicy(kDeployedConfidencePolicy),
      modelAsset: 'assets/models/fieldsnap_float.tflite',
      modelLabel: 'fieldsnap_float.tflite (FP32, data v2)',
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldSnap NZ',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: FutureBuilder<FieldSnapDependencies>(
        future: _dependencies,
        builder: (BuildContext context, AsyncSnapshot<FieldSnapDependencies> snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('FieldSnap could not start: ${snapshot.error}'),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final FieldSnapDependencies deps = snapshot.data!;
          return _appShell(deps);
        },
      ),
    );
  }
}

ThemeData get _theme => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
      useMaterial3: true,
    );

Widget _appShell(FieldSnapDependencies deps) => CaptureScreen(
      viewModel: ClassifierViewModel(
        imageInput: deps.imageInput,
        classifier: deps.classifier,
        qualityGate: deps.qualityGate,
        cards: deps.cards,
        history: deps.history,
        confidencePolicy: deps.confidencePolicy,
        modelAsset: deps.modelAsset,
        modelLabel: deps.modelLabel,
      ),
      cards: deps.cards,
      history: deps.history,
    );

/// Test-friendly entry point: the same shell with injected dependencies.
class FieldSnapApp extends StatelessWidget {
  const FieldSnapApp({
    super.key,
    required this.imageInput,
    required this.classifier,
    this.cards,
    this.history,
    this.qualityGate = const ImageQualityGate(),
    this.confidencePolicy = const ConfidencePolicy(kDeployedConfidencePolicy),
    this.modelAsset = 'test-model',
    this.modelLabel = 'test-model',
  });

  final ImageInput imageInput;
  final SpeciesClassifier classifier;
  final SpeciesCardRepository? cards;
  final HistoryRepository? history;
  final ImageQualityGate qualityGate;
  final ConfidencePolicy confidencePolicy;
  final String modelAsset;
  final String modelLabel;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldSnap NZ',
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: CaptureScreen(
        viewModel: ClassifierViewModel(
          imageInput: imageInput,
          classifier: classifier,
          qualityGate: qualityGate,
          cards: cards,
          history: history,
          confidencePolicy: confidencePolicy,
          modelAsset: modelAsset,
          modelLabel: modelLabel,
        ),
        cards: cards,
        history: history,
      ),
    );
  }
}
