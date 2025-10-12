import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/models/advance_transaction.dart';
import '../../core/models/app_user.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';

class AdvanceSalaryScreen extends StatefulWidget {
  final AppUser user;

  const AdvanceSalaryScreen({super.key, required this.user});

  @override
  State<AdvanceSalaryScreen> createState() => _AdvanceSalaryScreenState();
}

class _AdvanceSalaryScreenState extends State<AdvanceSalaryScreen> {
  List<AdvanceTransaction> _transactions = [];
  double _currentBalance = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadBalance(), _loadTransactions()]);
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadBalance() async {
    try {
      final driverId = widget.user.driverId ?? widget.user.id;
      print('DEBUG: Loading balance for driverId: $driverId');

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_advance_balance.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId}),
      );

      print('DEBUG: Balance API response status: ${response.statusCode}');
      print('DEBUG: Balance API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['status'] == 'ok') {
            setState(() {
              _currentBalance = (data['balance'] ?? 0.0).toDouble();
            });
            print('DEBUG: Balance loaded: $_currentBalance');
          } else {
            print('DEBUG: API returned error: ${data['error']}');
          }
        } catch (jsonError) {
          print('DEBUG: Balance JSON decode error: $jsonError');
          print('DEBUG: Balance response body: ${response.body}');
        }
      }
    } catch (e) {
      print('Error loading balance: $e');
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final driverId = widget.user.driverId ?? widget.user.id;
      print('DEBUG: Loading transactions for driverId: $driverId');
      print('DEBUG: User driverId: ${widget.user.driverId}');
      print('DEBUG: User id: ${widget.user.id}');
      print(
        'DEBUG: Request body: ${jsonEncode({'driverId': driverId, 'limit': 50})}',
      );

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/get_advance_transactions.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'driverId': driverId, 'limit': 50}),
      );

      print('DEBUG: Transactions API response status: ${response.statusCode}');
      print('DEBUG: Transactions API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          print('DEBUG: Parsed JSON data: $data');
          if (data['status'] == 'ok') {
            final transactionsList = data['transactions'] as List?;
            print('DEBUG: Raw transactions list: $transactionsList');
            if (transactionsList != null) {
              final transactions = transactionsList
                  .map(
                    (json) => AdvanceTransaction.fromJson(
                      json as Map<String, dynamic>,
                    ),
                  )
                  .toList();
              setState(() {
                _transactions = transactions;
              });
              print(
                'DEBUG: Transactions loaded successfully: ${transactions.length}',
              );
              for (var transaction in transactions) {
                print(
                  'DEBUG: Transaction: ${transaction.id} - ${transaction.type} - ${transaction.amount} - ${transaction.description}',
                );
              }
            } else {
              print('DEBUG: Transactions list is null');
            }
          } else {
            print('DEBUG: Transactions API returned error: ${data['error']}');
          }
        } catch (jsonError) {
          print('DEBUG: Transactions JSON decode error: $jsonError');
          print('DEBUG: Transactions response body: ${response.body}');
        }
      }
    } catch (e) {
      print('Error loading transactions: $e');
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _formatTime(DateTime date) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _addTransactionWithDate(
    String type,
    double amount,
    String description,
    DateTime transactionDate,
  ) async {
    try {
      final driverId = widget.user.driverId ?? widget.user.id;
      final requestBody = {
        'driverId': driverId,
        'type': type,
        'amount': amount,
        'description': description,
        'timestamp': transactionDate.toIso8601String(),
      };

      print('DEBUG: Adding transaction with date for driverId: $driverId');
      print(
        'DEBUG: Transaction type: $type, amount: $amount, description: $description',
      );
      print('DEBUG: Transaction date: $transactionDate');
      print('DEBUG: Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/add_advance_transaction.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print(
        'DEBUG: Add transaction API response status: ${response.statusCode}',
      );
      print('DEBUG: Add transaction API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['status'] == 'ok') {
            showAppToast(context, 'Transaction added successfully');
            await _loadData(); // Refresh data
          } else {
            showAppToast(
              context,
              data['error'] ?? 'Failed to add transaction',
              isError: true,
            );
          }
        } catch (jsonError) {
          print('DEBUG: JSON decode error: $jsonError');
          print('DEBUG: Response body that failed to parse: ${response.body}');
          showAppToast(
            context,
            'Invalid response from server: ${response.body}',
            isError: true,
          );
        }
      } else {
        print('DEBUG: HTTP error status: ${response.statusCode}');
        showAppToast(
          context,
          'Server error (${response.statusCode}): ${response.body}',
          isError: true,
        );
      }
    } catch (e) {
      print('DEBUG: Error adding transaction: $e');
      showAppToast(context, 'Error adding transaction: $e', isError: true);
    }
  }

  Future<void> _addTransaction(
    String type,
    double amount,
    String description,
  ) async {
    try {
      final driverId = widget.user.driverId ?? widget.user.id;
      final requestBody = {
        'driverId': driverId,
        'type': type,
        'amount': amount,
        'description': description,
      };

      print('DEBUG: Adding transaction for driverId: $driverId');
      print(
        'DEBUG: Transaction type: $type, amount: $amount, description: $description',
      );
      print('DEBUG: Request body: ${jsonEncode(requestBody)}');

      final response = await http.post(
        Uri.parse(
          'https://sstranswaysindia.com/api/mobile/add_advance_transaction.php',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print(
        'DEBUG: Add transaction API response status: ${response.statusCode}',
      );
      print('DEBUG: Add transaction API response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if (data['status'] == 'ok') {
            showAppToast(context, 'Transaction added successfully');
            await _loadData(); // Refresh data
          } else {
            showAppToast(
              context,
              data['error'] ?? 'Failed to add transaction',
              isError: true,
            );
          }
        } catch (jsonError) {
          print('DEBUG: JSON decode error: $jsonError');
          print('DEBUG: Response body that failed to parse: ${response.body}');
          showAppToast(
            context,
            'Invalid response from server: ${response.body}',
            isError: true,
          );
        }
      } else {
        print('DEBUG: HTTP error status: ${response.statusCode}');
        showAppToast(
          context,
          'Server error (${response.statusCode}): ${response.body}',
          isError: true,
        );
      }
    } catch (e) {
      print('DEBUG: Error adding transaction: $e');
      showAppToast(context, 'Error adding transaction: $e', isError: true);
    }
  }

  void _showAddTransactionDialog(bool isAdvanceReceived) {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isAdvanceReceived ? 'You Got ₹' : 'You Gave ₹'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₹',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text('Date: ${_formatDate(selectedDate)}'),
                subtitle: Text(_formatTime(selectedDate)),
                trailing: const Icon(Icons.edit),
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 365),
                    ),
                    lastDate: DateTime.now(),
                  );
                  if (date != null) {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(selectedDate),
                    );
                    if (time != null) {
                      setState(() {
                        selectedDate = DateTime(
                          date.year,
                          date.month,
                          date.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    }
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountController.text);
                final description = descriptionController.text.trim();

                if (amount == null || amount <= 0) {
                  showAppToast(
                    context,
                    'Please enter a valid amount',
                    isError: true,
                  );
                  return;
                }

                if (description.isEmpty) {
                  showAppToast(
                    context,
                    'Please enter a description',
                    isError: true,
                  );
                  return;
                }

                Navigator.pop(context);

                final type = isAdvanceReceived ? 'advance_received' : 'expense';
                await _addTransactionWithDate(
                  type,
                  amount,
                  description,
                  selectedDate,
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Khata Book'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AppGradientBackground(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfileSection(),
                      const SizedBox(height: 16),
                      _buildBalanceCard(),
                      const SizedBox(height: 16),
                      _buildActionButtons(),
                      const SizedBox(height: 16),
                      _buildTransactionHistory(),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _buildBottomButtons(),
    );
  }

  Widget _buildProfileSection() {
    return Row(
      children: [
        CircleAvatar(
          radius: 30,
          backgroundImage: widget.user.profilePhoto != null
              ? NetworkImage(widget.user.profilePhoto!)
              : null,
          child: widget.user.profilePhoto == null
              ? const Icon(Icons.person, size: 30)
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.user.displayName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Driver',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'View settings',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            // TODO: Implement call functionality
          },
          icon: const Icon(Icons.phone),
        ),
      ],
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'You will get',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₹${_currentBalance.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  // TODO: Implement collection reminder
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade100,
                  foregroundColor: Colors.black,
                  elevation: 0,
                ),
                child: const Text('SET DATE'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: Colors.grey),
              SizedBox(width: 4),
              Text(
                'Set collection reminder',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(Icons.picture_as_pdf, 'Report', () {
          // TODO: Implement PDF report
        }),
        _buildActionButton(Icons.chat, 'Reminder', () {
          // TODO: Implement reminder
        }),
        _buildActionButton(Icons.sms, 'SMS', () {
          // TODO: Implement SMS
        }),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(onPressed: onTap, icon: Icon(icon)),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildTransactionHistory() {
    if (_transactions.isEmpty) {
      return const Center(child: Text('No transactions found'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ENTRIES',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 8),
        ..._transactions.map(
          (transaction) => _buildTransactionCard(transaction),
        ),
      ],
    );
  }

  Widget _buildTransactionCard(AdvanceTransaction transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                transaction.formattedDate,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (transaction.runningBalance != null)
                Text(
                  'Bal. ${transaction.formattedBalance}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  transaction.description,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Text(
                transaction.formattedAmount,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: transaction.isAdvanceReceived
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showAddTransactionDialog(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('YOU GAVE ₹'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _showAddTransactionDialog(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('YOU GOT ₹'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
