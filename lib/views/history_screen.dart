import 'package:flutter/material.dart';

import '../services/history_repository.dart';

/// Local identification history (FR6): view, delete one, clear all.
///
/// The list shows only records that really exist; there is no placeholder or sample data. No
/// photograph is displayed or stored — see docs/history.md.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, required this.repository});

  final HistoryRepository repository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late Future<List<HistoryRecord>> _records;

  @override
  void initState() {
    super.initState();
    _records = widget.repository.loadAll();
  }

  void _reload() {
    setState(() {
      _records = widget.repository.loadAll();
    });
  }

  Future<void> _delete(HistoryRecord record) async {
    final int? id = record.id;
    if (id == null) {
      return;
    }
    await widget.repository.delete(id);
    _reload();
  }

  Future<void> _clearAll() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text('Every saved identification will be deleted. This cannot be undone.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await widget.repository.deleteAll();
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Identification history'),
        actions: <Widget>[
          IconButton(
            onPressed: _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear all history',
          ),
        ],
      ),
      body: FutureBuilder<List<HistoryRecord>>(
        future: _records,
        builder: (BuildContext context, AsyncSnapshot<List<HistoryRecord>> snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('History could not be loaded: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<HistoryRecord> records = snapshot.data!;
          if (records.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No saved identifications yet.'),
              ),
            );
          }
          return ListView.separated(
            itemCount: records.length,
            separatorBuilder: (BuildContext context, int index) => const Divider(height: 1),
            itemBuilder: (BuildContext context, int index) {
              final HistoryRecord record = records[index];
              return ListTile(
                leading: Icon(
                  record.wasUncertain ? Icons.help_outline : Icons.eco_outlined,
                  color: record.wasUncertain ? theme.colorScheme.outline : null,
                ),
                title: Text(record.wasUncertain ? 'Uncertain' : record.topCommonName),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (!record.wasUncertain && record.topScientificName.isNotEmpty)
                      Text(record.topScientificName,
                          style: const TextStyle(fontStyle: FontStyle.italic)),
                    Text(
                      '${record.createdAt.toLocal().toString().substring(0, 16)}  |  '
                      '${(record.topConfidence * 100).toStringAsFixed(0)}%  |  '
                      'threshold ${(record.confidenceThreshold * 100).toStringAsFixed(0)}%'
                      '${record.confidencePolicyValidated ? '' : ' (unvalidated)'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      '${record.modelLabel}  |  brightness '
                      '${record.qualityBrightness.toStringAsFixed(2)}, sharpness '
                      '${record.qualityLaplacianVariance.toStringAsFixed(1)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete this record',
                  onPressed: () => _delete(record),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
