import 'dart:async';

import 'package:chronosync/data/portability/portability_file_service.dart';
import 'package:chronosync/data/portability/session_csv_exporter.dart';
import 'package:chronosync/domain/session/live_session.dart';
import 'package:chronosync/logic/live_session/live_session_view_mapper.dart';
import 'package:chronosync/presentation/formatters/time_format.dart';
import 'package:chronosync/presentation/screens/live/live.dart';
import 'package:flutter/material.dart';

class HistorySummaryScreen extends StatefulWidget {
  const HistorySummaryScreen({
    required this.session,
    required this.hostDisplayName,
    required this.fileService,
    super.key,
  });

  final LiveSession session;
  final String hostDisplayName;
  final PortabilityFileService fileService;

  @override
  State<HistorySummaryScreen> createState() => _HistorySummaryScreenState();
}

class _HistorySummaryScreenState extends State<HistorySummaryScreen> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    return SessionSummaryScreen(
      data: mapSessionSummaryView(
        session: widget.session,
        now: widget.session.endedAt ?? DateTime.now(),
        hostDisplayName: widget.hostDisplayName,
      ),
      isExporting: _exporting,
      onDone: () => Navigator.pop(context),
      onExportCsv: () => unawaited(_export()),
    );
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final String csv = const SessionCsvExporter().export(
        widget.session,
        hostDisplayName: widget.hostDisplayName,
      );
      await widget.fileService.shareCsv(
        csv: csv,
        fileName:
            '${safeFileStem(widget.session.planSnapshot.title)}-session.csv',
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not export the activity. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }
}
