import 'package:chronosync/data/models/series_statistics.dart';
import 'package:flutter/material.dart';

/// Displays aggregate series statistics at completion
/// Shows event count, expected time, actual time, and over/under time
class SeriesStatisticsPanel extends StatelessWidget {
  final SeriesStatistics statistics;

  const SeriesStatisticsPanel({
    super.key,
    required this.statistics,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Series Statistics',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildStatRow(
              context,
              'Events Completed',
              '${statistics.eventCount}',
              null,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              context,
              'Expected Time',
              statistics.expectedTimeFormatted,
              null,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              context,
              'Actual Time',
              statistics.actualTimeFormatted,
              null,
            ),
            const SizedBox(height: 8),
            _buildStatRow(
              context,
              statistics.isOvertime ? 'Overtime' : statistics.isUndertime ? 'Undertime' : 'On Time',
              statistics.overUnderTimeFormatted,
              _getOverUnderColor(statistics),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a single statistic row with label and value
  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    Color? valueColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
        ),
      ],
    );
  }

  /// Returns color for over/under time display
  /// Red for overtime, green for undertime, neutral for on-time
  Color _getOverUnderColor(SeriesStatistics stats) {
    if (stats.isOvertime) {
      return Colors.red;
    } else if (stats.isUndertime) {
      return Colors.green;
    } else {
      return Colors.grey;
    }
  }
}
