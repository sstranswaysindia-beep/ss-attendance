import 'package:flutter/material.dart';

class SearchableDropdown<T> extends StatefulWidget {
  const SearchableDropdown({
    required this.items,
    required this.itemBuilder,
    required this.onChanged,
    this.value,
    this.hint,
    this.searchHint = 'Search...',
    this.isExpanded = true,
    this.decoration,
    super.key,
  });

  final List<T> items;
  final Widget Function(T item) itemBuilder;
  final ValueChanged<T?> onChanged;
  final T? value;
  final String? hint;
  final String searchHint;
  final bool isExpanded;
  final InputDecoration? decoration;

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  late TextEditingController _searchController;
  List<T> _filteredItems = [];
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _filteredItems = widget.items;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterItems(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        _filteredItems = widget.items.where((item) {
          final itemText = item.toString().toLowerCase();
          return itemText.contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search field
        if (_isOpen)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    setState(() {
                      _isOpen = false;
                      _searchController.clear();
                      _filteredItems = widget.items;
                    });
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: _filterItems,
              autofocus: true,
            ),
          ),
        
        // Dropdown button
        DropdownButtonFormField<T>(
          value: widget.value,
          decoration: widget.decoration,
          isExpanded: widget.isExpanded,
          hint: Text(widget.hint ?? 'Select'),
          items: _filteredItems.map((item) {
            return DropdownMenuItem<T>(
              value: item,
              child: widget.itemBuilder(item),
            );
          }).toList(),
          onChanged: (value) {
            widget.onChanged(value);
            setState(() {
              _isOpen = false;
              _searchController.clear();
              _filteredItems = widget.items;
            });
          },
          onTap: () {
            setState(() {
              _isOpen = !_isOpen;
              if (_isOpen) {
                _searchController.clear();
                _filteredItems = widget.items;
              }
            });
          },
        ),
      ],
    );
  }
}
