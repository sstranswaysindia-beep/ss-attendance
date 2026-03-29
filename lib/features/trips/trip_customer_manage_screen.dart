import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_user.dart';
import '../../core/models/trip_customer.dart';
import '../../core/services/trip_repository.dart';
import '../../core/widgets/app_toast.dart';

const Color _customerHeroStart = Color(0xFF0A2A66);
const Color _customerHeroEnd = Color(0xFF1C5FD1);
const Color _customerAccent = Color(0xFF35D0BA);
const Color _customerPageBackground = Color(0xFFF2F6FB);
const Color _customerCardBackground = Color(0xFFFFFFFF);

enum _CustomerSortKey { name, id, code, status, created }

class TripCustomerManageScreen extends StatefulWidget {
  const TripCustomerManageScreen({required this.user, super.key});

  final AppUser user;

  @override
  State<TripCustomerManageScreen> createState() =>
      _TripCustomerManageScreenState();
}

class _TripCustomerManageScreenState extends State<TripCustomerManageScreen> {
  final TripRepository _repository = TripRepository();
  final TextEditingController _addController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _createdFormatter = DateFormat('dd-MM-yyyy');

  final Map<int, TextEditingController> _nameControllers =
      <int, TextEditingController>{};
  final Map<int, String> _statusSelections = <int, String>{};
  final Set<int> _savingIds = <int>{};
  final Set<int> _regenIds = <int>{};
  final Set<int> _deleteIds = <int>{};

  List<TripCustomer> _customers = const <TripCustomer>[];
  bool _isLoading = false;
  bool _isAdding = false;
  bool _didChange = false;
  String _searchQuery = '';
  _CustomerSortKey _sortKey = _CustomerSortKey.name;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadCustomers();
  }

  @override
  void dispose() {
    _addController.dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    for (final controller in _nameControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _handleSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final customers = await _repository.fetchCustomersForUser(widget.user);
      if (!mounted) return;
      _syncControllers(customers);
      setState(() {
        _customers = customers;
      });
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to load customers.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _syncControllers(List<TripCustomer> customers) {
    final ids = customers.map((customer) => customer.id).toSet();
    final obsoleteIds = _nameControllers.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);

    for (final id in obsoleteIds) {
      _nameControllers.remove(id)?.dispose();
      _statusSelections.remove(id);
      _savingIds.remove(id);
      _regenIds.remove(id);
      _deleteIds.remove(id);
    }

    for (final customer in customers) {
      final controller = _nameControllers.putIfAbsent(
        customer.id,
        () => TextEditingController(text: customer.customerName),
      );
      if (controller.text != customer.customerName) {
        controller.text = customer.customerName;
      }
      _statusSelections[customer.id] = customer.status;
    }
  }

  String _camelWord(String value) {
    if (value.isEmpty) {
      return value;
    }
    final lower = value.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  String _toCamelTitlePreserveSpaces(String value) {
    if (value.isEmpty) {
      return '';
    }
    final tokens = value.split(RegExp(r'(\s+)'));
    final buffer = StringBuffer();
    for (final token in tokens) {
      if (token.trim().isEmpty) {
        buffer.write(token);
      } else {
        buffer.write(_camelWord(token));
      }
    }
    return buffer.toString();
  }

  Future<void> _handleAddCustomers() async {
    final raw = _addController.text.trim();
    if (raw.isEmpty) {
      showAppToast(
        context,
        'Enter customer name(s). You can use commas.',
        isError: true,
      );
      return;
    }

    final transformed = raw
        .split(',')
        .map((name) => _toCamelTitlePreserveSpaces(name.trim()))
        .where((name) => name.isNotEmpty)
        .join(', ');

    setState(() {
      _isAdding = true;
      _addController.text = transformed;
      _addController.selection = TextSelection.fromPosition(
        TextPosition(offset: _addController.text.length),
      );
    });

    try {
      final message = await _repository.addCustomers(
        user: widget.user,
        customerNames: transformed,
      );
      if (!mounted) return;
      _didChange = true;
      _addController.clear();
      showAppToast(context, message);
      await _loadCustomers();
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to add customer.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isAdding = false;
        });
      }
    }
  }

  Future<void> _handleSaveCustomer(TripCustomer customer) async {
    final controller = _nameControllers[customer.id];
    final rawName = controller?.text.trim() ?? customer.customerName;
    final name = _toCamelTitlePreserveSpaces(rawName);
    final status = _statusSelections[customer.id] ?? customer.status;

    if (name.isEmpty) {
      showAppToast(context, 'Customer name required.', isError: true);
      return;
    }

    setState(() {
      _savingIds.add(customer.id);
      controller?.text = name;
      controller?.selection = TextSelection.fromPosition(
        TextPosition(offset: name.length),
      );
    });

    try {
      final message = await _repository.updateCustomer(
        user: widget.user,
        customerId: customer.id,
        customerName: name,
        status: status,
      );
      if (!mounted) return;
      _didChange = true;
      showAppToast(context, message);
      await _loadCustomers();
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to update customer.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _savingIds.remove(customer.id);
        });
      }
    }
  }

  Future<void> _handleRegenCustomer(TripCustomer customer) async {
    final controller = _nameControllers[customer.id];
    final rawName = controller?.text.trim() ?? customer.customerName;
    final name = _toCamelTitlePreserveSpaces(rawName);
    final status = _statusSelections[customer.id] ?? customer.status;

    if (name.isEmpty) {
      showAppToast(context, 'Customer name required.', isError: true);
      return;
    }

    setState(() {
      _regenIds.add(customer.id);
      controller?.text = name;
      controller?.selection = TextSelection.fromPosition(
        TextPosition(offset: name.length),
      );
    });

    try {
      final message = await _repository.updateCustomer(
        user: widget.user,
        customerId: customer.id,
        customerName: name,
        status: status,
        regenerateCode: true,
      );
      if (!mounted) return;
      _didChange = true;
      showAppToast(context, message);
      await _loadCustomers();
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to regenerate code.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _regenIds.remove(customer.id);
        });
      }
    }
  }

  Future<void> _handleDeleteCustomer(TripCustomer customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text(
          'Delete ${customer.customerName}? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _deleteIds.add(customer.id);
    });

    try {
      final message = await _repository.deleteCustomer(
        user: widget.user,
        customerId: customer.id,
      );
      if (!mounted) return;
      _didChange = true;
      showAppToast(context, message);
      await _loadCustomers();
    } on TripFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to delete customer.', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _deleteIds.remove(customer.id);
        });
      }
    }
  }

  int get _activeCount => _customers
      .where((customer) => customer.status.toLowerCase() == 'active')
      .length;

  int get _inactiveCount => _customers.length - _activeCount;

  List<TripCustomer> get _visibleCustomers {
    final filtered = _customers
        .where((customer) {
          if (_searchQuery.isEmpty) {
            return true;
          }
          final haystack = [
            customer.id.toString(),
            customer.customerName,
            customer.shortCode,
            customer.status,
            customer.createdAt?.toIso8601String() ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(_searchQuery);
        })
        .toList(growable: false);

    int compare(TripCustomer a, TripCustomer b) {
      switch (_sortKey) {
        case _CustomerSortKey.id:
          return a.id.compareTo(b.id);
        case _CustomerSortKey.code:
          return a.shortCode.toLowerCase().compareTo(b.shortCode.toLowerCase());
        case _CustomerSortKey.status:
          return a.status.toLowerCase().compareTo(b.status.toLowerCase());
        case _CustomerSortKey.created:
          return (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0));
        case _CustomerSortKey.name:
          return a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          );
      }
    }

    final sorted = [...filtered]..sort(compare);
    return _sortAscending ? sorted : sorted.reversed.toList(growable: false);
  }

  String _sortLabel(_CustomerSortKey key) {
    switch (key) {
      case _CustomerSortKey.id:
        return 'ID';
      case _CustomerSortKey.code:
        return 'Short Code';
      case _CustomerSortKey.status:
        return 'Status';
      case _CustomerSortKey.created:
        return 'Created';
      case _CustomerSortKey.name:
        return 'Customer Name';
    }
  }

  String _createdLabel(DateTime? value) {
    if (value == null) {
      return '—';
    }
    return _createdFormatter.format(value);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        Navigator.of(context).pop(_didChange);
      },
      child: Scaffold(
        backgroundColor: _customerPageBackground,
        appBar: AppBar(
          backgroundColor: _customerHeroStart,
          foregroundColor: Colors.white,
          title: const Text(
            'Customer Manager',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _isLoading ? null : _loadCustomers,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
          ],
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_customerHeroStart, _customerHeroEnd],
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => Navigator.of(context).pop(_didChange),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadCustomers,
          color: _customerAccent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildHeroCard(),
              const SizedBox(height: 14),
              _buildAddCard(),
              const SizedBox(height: 14),
              _buildSearchAndSortCard(),
              const SizedBox(height: 14),
              if (_isLoading && _customers.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_visibleCustomers.isEmpty)
                _buildEmptyState()
              else
                ..._visibleCustomers.map(_buildCustomerCard),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_customerHeroStart, _customerHeroEnd],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _customerHeroEnd.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.groups_2_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trip Customers',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Add, search, edit, regenerate and delete customer master entries.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatChip(
                  label: 'Total',
                  value: '${_customers.length}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatChip(label: 'Active', value: '$_activeCount'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatChip(
                  label: 'Inactive',
                  value: '$_inactiveCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCard() {
    return _sectionCard(
      backgroundColor: const Color(0xFFE9FFF8),
      borderColor: const Color(0xFFB7F1E3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add Customer',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF132238),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use commas to add multiple customer names at once.',
            style: TextStyle(
              color: Colors.blueGrey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'e.g. Apollo Hospital, Bharat Gas, Linde Bulk',
              hintStyle: const TextStyle(fontSize: 14),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              filled: true,
              fillColor: const Color(0xFFF6F8FC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.blueGrey.shade100),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.blueGrey.shade100),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: _customerAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isAdding ? null : _handleAddCustomers,
              style: FilledButton.styleFrom(
                backgroundColor: _customerAccent,
                foregroundColor: const Color(0xFF09243A),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: _isAdding
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: Text(
                _isAdding ? 'Adding...' : 'Add Customer',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchAndSortCard() {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search customer, code, status or ID',
              hintStyle: const TextStyle(fontSize: 14),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              filled: true,
              fillColor: const Color(0xFFF6F8FC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.blueGrey.shade100),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: Colors.blueGrey.shade100),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(16)),
                borderSide: BorderSide(color: _customerAccent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_CustomerSortKey>(
                  key: ValueKey<_CustomerSortKey>(_sortKey),
                  initialValue: _sortKey,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Sort By',
                    labelStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF6F8FC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.blueGrey.shade100),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.blueGrey.shade100),
                    ),
                  ),
                  items: _CustomerSortKey.values
                      .map(
                        (key) => DropdownMenuItem<_CustomerSortKey>(
                          value: key,
                          child: Text(_sortLabel(key)),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _sortKey = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () {
                  setState(() {
                    _sortAscending = !_sortAscending;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F8FC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blueGrey.shade100),
                  ),
                  child: Icon(
                    _sortAscending
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: _customerHeroStart,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return _sectionCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(
              Icons.group_off_rounded,
              size: 42,
              color: Colors.blueGrey.shade300,
            ),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isEmpty
                  ? 'No customers yet.'
                  : 'No customers match your search.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF132238),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(TripCustomer customer) {
    final controller = _nameControllers[customer.id]!;
    final isSaving = _savingIds.contains(customer.id);
    final isRegenerating = _regenIds.contains(customer.id);
    final isDeleting = _deleteIds.contains(customer.id);
    final isBusy = isSaving || isRegenerating || isDeleting;
    final isActive =
        (_statusSelections[customer.id] ?? customer.status).toLowerCase() ==
        'active';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _sectionCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _pill(
                        '#${customer.id}',
                        const Color(0xFFE9F2FF),
                        _customerHeroStart,
                      ),
                      _pill(
                        customer.shortCode.isEmpty
                            ? 'No code'
                            : customer.shortCode,
                        const Color(0xFFFBE8FF),
                        const Color(0xFF7B2CBF),
                      ),
                      _pill(
                        isActive ? 'Active' : 'Inactive',
                        isActive
                            ? const Color(0xFFE4FFF2)
                            : const Color(0xFFFFF1E6),
                        isActive
                            ? const Color(0xFF0B7A43)
                            : const Color(0xFFB65A00),
                      ),
                      _pill(
                        _createdLabel(customer.createdAt),
                        const Color(0xFFF4F6FA),
                        const Color(0xFF526174),
                      ),
                    ],
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              enabled: !isDeleting,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Customer Name',
                labelStyle: const TextStyle(fontSize: 12),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                filled: true,
                fillColor: const Color(0xFFF6F8FC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.blueGrey.shade100),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: Colors.blueGrey.shade100),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  borderSide: BorderSide(color: _customerAccent, width: 1.5),
                ),
              ),
              onEditingComplete: () {
                final value = _toCamelTitlePreserveSpaces(controller.text);
                controller
                  ..text = value
                  ..selection = TextSelection.fromPosition(
                    TextPosition(offset: value.length),
                  );
              },
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>(
                      'status-${customer.id}-${_statusSelections[customer.id] ?? customer.status}',
                    ),
                    initialValue:
                        _statusSelections[customer.id] ?? customer.status,
                    dropdownColor: Colors.white,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF132238),
                    ),
                    decoration: InputDecoration(
                      labelText: 'Status',
                      labelStyle: const TextStyle(fontSize: 12),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF6F8FC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.blueGrey.shade100),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.blueGrey.shade100),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Active',
                        child: Text('Active', style: TextStyle(fontSize: 13)),
                      ),
                      DropdownMenuItem(
                        value: 'Inactive',
                        child: Text('Inactive', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                    onChanged: isDeleting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() {
                              _statusSelections[customer.id] = value;
                            });
                          },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: FilledButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _handleSaveCustomer(customer),
                    style: FilledButton.styleFrom(
                      backgroundColor: _customerAccent,
                      foregroundColor: const Color(0xFF0A2033),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.save_rounded, size: 16),
                    label: const Text('Save', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () => _handleRegenCustomer(customer),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                    label: const Text('Regen', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required Widget child,
    Color? backgroundColor,
    Color? borderColor,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? _customerCardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor ?? Colors.white),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A2A66).withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _pill(String label, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
