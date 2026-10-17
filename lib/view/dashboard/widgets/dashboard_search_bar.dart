import 'package:flutter/material.dart';

/// Search category dropdown + search field above the appointment queue.
/// State (category, controller) lives in the dashboard State; every change is
/// reported back through the callbacks, which call setState there.
class DashboardSearchBar extends StatelessWidget {
  final BoxConstraints constraints;
  final String searchCategory;
  final TextEditingController searchController;
  final ValueChanged<String> onCategoryChanged;

  /// Called on every keystroke (real-time update).
  final VoidCallback onQueryChanged;

  /// Clear (x) button.
  final VoidCallback onClear;

  const DashboardSearchBar({
    super.key,
    required this.constraints,
    required this.searchCategory,
    required this.searchController,
    required this.onCategoryChanged,
    required this.onQueryChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isSmallScreen = constraints.maxWidth < 600;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmallScreen ? 12 : 16,
        vertical: isSmallScreen ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          // Search Category Dropdown
          Container(
            padding: EdgeInsets.symmetric(horizontal: isSmallScreen ? 8 : 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: DropdownButton<String>(
              value: searchCategory,
              isDense: true,
              underline: const SizedBox(),
              icon: Icon(Icons.arrow_drop_down, color: Colors.grey[700]),
              style: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
                color: const Color(0xFF333333),
              ),
              items: ['Patient Name', 'Phone', 'Date'].map((String category) {
                return DropdownMenuItem<String>(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (String? newValue) {
                if (newValue != null) {
                  onCategoryChanged(newValue);
                }
              },
            ),
          ),
          SizedBox(width: isSmallScreen ? 8 : 12),
          // Search TextField
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: (_) => onQueryChanged(), // Real-time update
              decoration: InputDecoration(
                hintText: 'Search by $searchCategory...',
                hintStyle: TextStyle(
                  fontSize: isSmallScreen ? 13 : 14,
                  color: Colors.grey[500],
                ),
                prefixIcon: const Icon(Icons.search, color: Color(0xFF666666)),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFF666666)),
                        onPressed: onClear,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
                ),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isSmallScreen ? 12 : 16,
                  vertical: isSmallScreen ? 12 : 14,
                ),
              ),
              style: TextStyle(
                fontSize: isSmallScreen ? 13 : 14,
                color: const Color(0xFF333333),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
