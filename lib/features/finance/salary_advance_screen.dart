import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/models/advance_request.dart';
import '../../core/models/app_user.dart';
import '../../core/models/salary_credit.dart';
import '../../core/services/finance_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class SalaryAdvanceScreen extends StatefulWidget {
  const SalaryAdvanceScreen({
    required this.user,
    super.key,
  });

  final AppUser user;

  @override
  State<SalaryAdvanceScreen> createState() => _SalaryAdvanceScreenState();
}

class _SalaryAdvanceScreenState extends State<SalaryAdvanceScreen> {
  final FinanceRepository _financeRepository = FinanceRepository();

  bool _isLoading = false;
  String? _errorMessage;
  List<SalaryCredit> _salaryCredits = const [];
  List<AdvanceRequest> _advanceRequests = const [];
  String _advanceStatusFilter = 'All';
  bool _isSubmittingAdvance = false;
  final Set<String> _salaryDeleting = <String>{};
  final Set<String> _advanceDeleting = <String>{};

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _purposeController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _purposeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadFinanceData();
  }

  Future<void> _loadFinanceData() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      setState(() {
        _errorMessage = 'Driver mapping missing. Contact admin.';
        _salaryCredits = const [];
        _advanceRequests = const [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _financeRepository.fetchSalaryCredits(driverId),
        _financeRepository.fetchAdvanceRequests(
          driverId,
          status: _advanceStatusFilter == 'All' ? null : _advanceStatusFilter,
        ),
      ]);

      if (!mounted) return;

      setState(() {
        _salaryCredits = results[0] as List<SalaryCredit>;
        _advanceRequests = results[1] as List<AdvanceRequest>;
      });
    } on FinanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      const fallback = 'Unable to load salary and advance details.';
      setState(() => _errorMessage = fallback);
      showAppToast(context, fallback, isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onAdvanceStatusChanged(String? status) async {
    if (status == null) return;
    setState(() => _advanceStatusFilter = status);
    await _loadFinanceData();
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) {
      return '-';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    return DateFormat('dd MMM yyyy').format(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseSalary = widget.user.salary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Salary & Advances'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadFinanceData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
          ),
        ],
      ),
      body: AppGradientBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (baseSalary != null && baseSalary.isNotEmpty) ...[
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.account_balance),
                              title: const Text('Monthly Salary'),
                              subtitle: const Text('As per HR records'),
                              trailing: Text('₹$baseSalary', style: theme.textTheme.titleMedium),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text('Salary Credits', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 12),
                        if (_salaryCredits.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'No salary credits recorded yet.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        else
                          ..._salaryCredits.map(
                            (credit) {
                              final isDeleting = _salaryDeleting.contains(credit.salaryCreditId);
                              return Card(
                                child: Dismissible(
                                  key: ValueKey('salary-${credit.salaryCreditId}'),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (_) async {
                                    await _confirmDeleteSalary(credit);
                                    return false;
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.delete, color: Colors.red),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(Icons.account_balance_wallet),
                                    title: Text('₹${credit.amount.toStringAsFixed(2)}'),
                                    subtitle: Text('Credited on ${_formatDate(credit.creditedOn)}'),
                                    trailing: isDeleting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Advance Requests',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            SizedBox(
                              width: 170,
                              child: DropdownButtonFormField<String>(
                                value: _advanceStatusFilter,
                                items: const [
                                  DropdownMenuItem(value: 'All', child: Text('All')),
                                  DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                                  DropdownMenuItem(value: 'Approved', child: Text('Approved')),
                                  DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                                  DropdownMenuItem(value: 'Disbursed', child: Text('Disbursed')),
                                ],
                                onChanged: _onAdvanceStatusChanged,
                                decoration: const InputDecoration(labelText: 'Status'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_advanceRequests.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'No advance requests for the selected filter.',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          )
                        else
                          ..._advanceRequests.map(
                            (request) {
                              final statusColor = switch (request.status) {
                                'Approved' => Colors.green,
                                'Disbursed' => Colors.blue,
                                'Rejected' => Colors.red,
                                'Pending' => Colors.orange,
                                _ => Colors.grey,
                              };
                              final isDeleting =
                                  _advanceDeleting.contains(request.advanceRequestId);
                              return Card(
                                child: Dismissible(
                                  key: ValueKey('advance-${request.advanceRequestId}'),
                                  direction: request.status == 'Pending'
                                      ? DismissDirection.endToStart
                                      : DismissDirection.none,
                                  confirmDismiss: (_) async {
                                    await _confirmDeleteAdvance(request);
                                    return false;
                                  },
                                  background: Container(
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(horizontal: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.delete, color: Colors.red),
                                  ),
                                  child: ListTile(
                                    leading: const Icon(Icons.request_page),
                                    title: Text('₹${request.amount.toStringAsFixed(2)}'),
                                    subtitle: Text(
                                      '${request.purpose}\nRequested: ${_formatDate(request.requestedAt)}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Chip(
                                          label: Text(request.status),
                                          backgroundColor: statusColor.withOpacity(0.15),
                                          labelStyle: TextStyle(color: statusColor),
                                        ),
                                        if (request.disbursedAt != null)
                                          Text('Disbursed: ${_formatDate(request.disbursedAt)}',
                                              style: theme.textTheme.bodySmall),
                                        if (isDeleting)
                                          const Padding(
                                            padding: EdgeInsets.only(top: 4),
                                            child: SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            _openAdvanceRequestSheet();
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Request Advance'),
                        ),
                      ],
                    ),
                  ),
      ),
    );
}

  Future<void> _openAdvanceRequestSheet() async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(context, 'Driver mapping missing. Contact admin.', isError: true);
      return;
    }

    _amountController.clear();
    _purposeController.clear();
    _notesController.clear();
    final formKey = GlobalKey<FormState>();

    final shouldReload = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                top: 16,
              ),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Request Advance', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Amount (₹)'),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter amount';
                        }
                        final parsed = double.tryParse(value.trim());
                        if (parsed == null || parsed <= 0) {
                          return 'Amount must be greater than zero';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _purposeController,
                      decoration: const InputDecoration(labelText: 'Purpose'),
                      maxLength: 120,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter purpose';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesController,
                      decoration: const InputDecoration(labelText: 'Notes (optional)'),
                      maxLines: 3,
                      maxLength: 255,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _isSubmittingAdvance
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate()) {
                                      return;
                                    }
                                    final amount = double.parse(_amountController.text.trim());
                                    final purpose = _purposeController.text.trim();
                                    final notes = _notesController.text.trim();

                                    modalSetState(() => _isSubmittingAdvance = true);
                                    setState(() => _isSubmittingAdvance = true);

                                    try {
                                      await _financeRepository.submitAdvanceRequest(
                                        driverId: driverId,
                                        amount: amount,
                                        purpose: purpose,
                                        notes: notes.isEmpty ? null : notes,
                                      );
                                      if (!mounted) return;
                                      modalSetState(() => _isSubmittingAdvance = false);
                                      setState(() => _isSubmittingAdvance = false);
                                      showAppToast(context, 'Advance requested successfully.');
                                      Navigator.of(context).pop(true);
                                    } on FinanceFailure catch (error) {
                                      modalSetState(() => _isSubmittingAdvance = false);
                                      setState(() => _isSubmittingAdvance = false);
                                      showAppToast(context, error.message, isError: true);
                                    } catch (_) {
                                      modalSetState(() => _isSubmittingAdvance = false);
                                      setState(() => _isSubmittingAdvance = false);
                                      showAppToast(context, 'Unable to submit request.', isError: true);
                                    }
                                  },
                            child: _isSubmittingAdvance
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Submit'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldReload == true) {
      await _loadFinanceData();
    }
  }

  Future<void> _confirmDeleteSalary(SalaryCredit credit) async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(context, 'Driver mapping missing. Contact admin.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Salary Credit'),
        content: const Text('Remove this salary credit entry?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _salaryDeleting.add(credit.salaryCreditId));
    try {
      await _financeRepository.deleteSalaryCredit(
        driverId: driverId,
        salaryCreditId: credit.salaryCreditId,
      );
      if (!mounted) return;
      setState(() {
        _salaryCredits = List.of(_salaryCredits)
          ..removeWhere((item) => item.salaryCreditId == credit.salaryCreditId);
        _salaryDeleting.remove(credit.salaryCreditId);
      });
      showAppToast(context, 'Salary credit removed.');
    } on FinanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _salaryDeleting.remove(credit.salaryCreditId));
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _salaryDeleting.remove(credit.salaryCreditId));
      showAppToast(context, 'Unable to delete salary credit.', isError: true);
    }
  }

  Future<void> _confirmDeleteAdvance(AdvanceRequest request) async {
    final driverId = widget.user.driverId;
    if (driverId == null || driverId.isEmpty) {
      showAppToast(context, 'Driver mapping missing. Contact admin.', isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Advance Request'),
        content: const Text('Cancel this advance request?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    setState(() => _advanceDeleting.add(request.advanceRequestId));
    try {
      await _financeRepository.deleteAdvanceRequest(
        driverId: driverId,
        advanceRequestId: request.advanceRequestId,
      );
      if (!mounted) return;
      setState(() {
        _advanceRequests = List.of(_advanceRequests)
          ..removeWhere((item) => item.advanceRequestId == request.advanceRequestId);
        _advanceDeleting.remove(request.advanceRequestId);
      });
      showAppToast(context, 'Advance request removed.');
    } on FinanceFailure catch (error) {
      if (!mounted) return;
      setState(() => _advanceDeleting.remove(request.advanceRequestId));
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _advanceDeleting.remove(request.advanceRequestId));
      showAppToast(context, 'Unable to delete advance request.', isError: true);
    }
  }
}
