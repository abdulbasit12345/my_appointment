import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../services/dashboard_metrics_service.dart';

/// Activity Log Section with real-time entries
///
/// Filter / page-size state lives in the dashboard State and is reported
/// back through [onFilterSelected] and [onLoadMore].
class ActivityLogPanel extends StatelessWidget {
  final BoxConstraints constraints;

  /// Activity log stream (DashboardRepository.watchActivityLog) for the
  /// current [activityLogLimit] / [selectedLogType].
  final Stream<QuerySnapshot> stream;

  /// null = all types
  final String? selectedLogType;
  final int activityLogLimit;

  /// A filter chip was (de)selected: (chip type, selected).
  final void Function(String? type, bool selected) onFilterSelected;

  /// "Load More" button.
  final VoidCallback onLoadMore;

  const ActivityLogPanel({
    super.key,
    required this.constraints,
    required this.stream,
    required this.selectedLogType,
    required this.activityLogLimit,
    required this.onFilterSelected,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isMediumScreen = constraints.maxWidth < 900;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title and Filter Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Reallocation Activity Log',
              style: TextStyle(
                fontSize: isSmallScreen
                    ? 14
                    : isMediumScreen
                        ? 16
                        : 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
          ],
        ),
        SizedBox(height: isSmallScreen ? 8 : 10),
        // Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildLogFilterChip('All', null, constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Claims', 'slot_claim', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Cancellations', 'cancellation', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Cascades', 'cascade_trigger', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Errors', 'error', constraints),
              SizedBox(width: isSmallScreen ? 6 : 8),
              _buildLogFilterChip('Maintenance', 'maintenance', constraints),
            ],
          ),
        ),
        SizedBox(height: isSmallScreen ? 10 : 12),
        Container(
          height: constraints.maxWidth < 1000 ? 400 : 500,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0), width: 1.5),
            borderRadius: BorderRadius.circular(10),
            color: const Color(0xFFFAFAFA),
          ),
          child: StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'Error loading activity log: ${snapshot.error}',
                      style: TextStyle(
                        color: Colors.red,
                        fontSize: isSmallScreen ? 11 : 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                // Show proper empty state when no activity log entries exist
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(isSmallScreen ? 16.0 : 24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.history,
                          size: isSmallScreen ? 48 : 64,
                          color: Colors.grey[400],
                        ),
                        SizedBox(height: isSmallScreen ? 12 : 16),
                        Text(
                          'No activity yet',
                          style: TextStyle(
                            fontSize: isSmallScreen ? 14 : 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        SizedBox(height: isSmallScreen ? 8 : 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 16 : 24,
                          ),
                          child: Text(
                            'Activity log will appear here once\npatients start interacting with the system.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: isSmallScreen ? 12 : 14,
                              color: Colors.grey[500],
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Parse and display real activity log entries
              final entries = snapshot.data!.docs
                  .map((doc) => ActivityLogEntry.fromFirestore(doc))
                  .toList();

              return Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      children: entries.map((entry) {
                        return _buildActivityLogItem(
                          entry.message,
                          entry.formattedTimestamp,
                          entry.type,
                          constraints,
                        );
                      }).toList(),
                    ),
                  ),
                  // Load More Button
                  if (entries.length >= activityLogLimit)
                    Padding(
                      padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: onLoadMore,
                          icon: const Icon(Icons.expand_more, size: 18),
                          label: const Text('Load More'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(
                              vertical: isSmallScreen ? 10 : 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Build filter chip for activity log types
  Widget _buildLogFilterChip(
      String label, String? type, BoxConstraints constraints) {
    final isSmallScreen = constraints.maxWidth < 600;
    final isSelected = selectedLogType == type;

    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: isSmallScreen ? 11 : 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (selected) => onFilterSelected(type, selected),
      selectedColor: _getLogTypeColor(type).withOpacity(0.2),
      checkmarkColor: _getLogTypeColor(type),
      labelStyle: TextStyle(
        color: isSelected ? _getLogTypeColor(type) : Colors.grey[700],
      ),
      side: BorderSide(
        color: isSelected ? _getLogTypeColor(type) : Colors.grey[300]!,
        width: isSelected ? 1.5 : 1,
      ),
    );
  }

  /// Individual Activity Log Item
  Widget _buildActivityLogItem(
    String activity,
    String timestamp,
    String? type,
    BoxConstraints constraints,
  ) {
    final isSmallScreen = constraints.maxWidth < 600;
    final typeColor = _getLogTypeColor(type);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: isSmallScreen ? 6.0 : 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isSmallScreen ? 8 : 10,
            height: isSmallScreen ? 8 : 10,
            margin: EdgeInsets.only(
              top: isSmallScreen ? 4 : 6,
              right: isSmallScreen ? 10 : 14,
            ),
            decoration: BoxDecoration(
              color: typeColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: typeColor.withOpacity(0.3),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activity,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 12 : 14,
                    color: const Color(0xFF1A1A1A),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: isSmallScreen ? 4 : 6),
                Text(
                  timestamp,
                  style: TextStyle(
                    fontSize: isSmallScreen ? 10 : 12,
                    color: const Color(0xFF888888),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Get color for log type
Color _getLogTypeColor(String? type) {
  switch (type) {
    case 'slot_claim':
      return Colors.green;
    case 'cancellation':
    case 'rearrangement':
      return Colors.orange;
    case 'cascade_trigger':
    case 'slot_offer':
      return Colors.blue;
    case 'error':
      return Colors.red;
    case 'maintenance':
      return Colors.purple;
    case 'dismissal':
      return Colors.grey;
    default:
      return const Color(0xFF1976D2);
  }
}
