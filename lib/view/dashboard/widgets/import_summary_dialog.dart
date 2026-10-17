import 'package:flutter/material.dart';

/// Show import summary dialog
Future<void> showImportSummaryDialog(
  BuildContext context,
  int totalRows,
  int successCount,
  List<String> errorLogs,
) async {
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) {
      return ImportSummaryDialog(
        totalRows: totalRows,
        successCount: successCount,
        errorLogs: errorLogs,
      );
    },
  );
}

/// Summary shown after a CSV import (processed / added / skipped rows).
class ImportSummaryDialog extends StatelessWidget {
  final int totalRows;
  final int successCount;
  final List<String> errorLogs;

  const ImportSummaryDialog({
    super.key,
    required this.totalRows,
    required this.successCount,
    required this.errorLogs,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxHeight: 600,
            maxWidth: 500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            // Title with icon
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Import Summary',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Summary content - scrollable if there are many errors
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Processed $totalRows records.',
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Successfully added $successCount appointments.',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (errorLogs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.orange[200]!,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Skipped ${errorLogs.length} records:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.orange[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ...errorLogs.take(10).map((error) => Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(
                                '• $error',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.orange[900],
                                ),
                              ),
                            )),
                            if (errorLogs.length > 10)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  '... and ${errorLogs.length - 10} more',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.orange[700],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Done button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }
}
