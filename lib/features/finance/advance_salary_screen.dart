import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/models/advance_transaction.dart';
import '../../core/models/app_user.dart';
import '../../core/services/finance_repository.dart';
import '../../core/services/profile_repository.dart';
import '../../core/widgets/app_gradient_background.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/widgets/profile_photo_widget.dart';

class AdvanceSalaryScreen extends StatefulWidget {
  final AppUser user;

  const AdvanceSalaryScreen({super.key, required this.user});

  @override
  State<AdvanceSalaryScreen> createState() => _AdvanceSalaryScreenState();
}

class _AdvanceSalaryScreenState extends State<AdvanceSalaryScreen> {
  List<AdvanceTransaction> _transactions = [];
  List<AdvanceTransaction> _filteredTransactions = [];
  double _currentBalance = 0.0;
  bool _isLoading = true;
  bool _isUploadingPhoto = false;
  String _selectedMonth = 'All Months';
  final ProfileRepository _profileRepository = ProfileRepository();

  // Fund transfer modal state
  String? _selectedDriverId;
  String _selectedDriverName = '';
  final TextEditingController _transferAmountController =
      TextEditingController();
  final TextEditingController _transferDescriptionController =
      TextEditingController();
  final TextEditingController _driverSearchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<Map<String, dynamic>> _driversList = [];
  List<Map<String, dynamic>> _filteredDriversList = [];
  bool _showDriverList = false;

  @override
  void initState() {
    super.initState();
    _loadData();

    // Add listener to search controller for debugging
    _driverSearchController.addListener(() {
      print(
        'DEBUG: Controller listener - text: "${_driverSearchController.text}"',
      );
    });
  }

  @override
  void dispose() {
    _transferAmountController.dispose();
    _transferDescriptionController.dispose();
    _driverSearchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadBalance(),
      _loadTransactions(),
      _loadDriversList(),
    ]);
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
                _filterTransactions();
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

  void _onMonthSelected(String month) {
    setState(() {
      _selectedMonth = month;
      _filterTransactions();
    });
  }

  void _filterTransactions() {
    if (_selectedMonth == 'All Months') {
      _filteredTransactions = _transactions;
    } else {
      final monthIndex = _getMonthIndex(_selectedMonth);
      _filteredTransactions = _transactions.where((transaction) {
        try {
          final date = DateTime.parse(transaction.createdAt);
          return date.month == monthIndex;
        } catch (e) {
          return false;
        }
      }).toList();
    }
  }

  int _getMonthIndex(String month) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return months.indexOf(month) + 1;
  }

  Future<void> _handlePhotoSelected(File file) async {
    setState(() => _isUploadingPhoto = true);
    try {
      String url;
      final driverId = widget.user.driverId;

      if (driverId != null && driverId.isNotEmpty) {
        // Driver with driverId - use driver-specific upload
        url = await _profileRepository.uploadProfilePhoto(
          driverId: driverId,
          file: file,
        );
      } else {
        // Supervisor or user without driverId - use user-specific upload
        url = await _profileRepository.uploadUserProfilePhoto(
          userId: widget.user.id,
          file: file,
        );
      }

      if (!mounted) return;

      setState(() {
        widget.user.profilePhoto = url;
      });
      showAppToast(context, 'Profile photo updated.');
    } on ProfileFailure catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message, isError: true);
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, 'Unable to upload profile photo.', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
      }
    }
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
        actions: [
          PopupMenuButton<String>(
            onSelected: _onMonthSelected,
            itemBuilder: (BuildContext context) {
              final months = [
                'All Months',
                'January',
                'February',
                'March',
                'April',
                'May',
                'June',
                'July',
                'August',
                'September',
                'October',
                'November',
                'December',
              ];
              return months.map((String month) {
                return PopupMenuItem<String>(value: month, child: Text(month));
              }).toList();
            },
            child: const Icon(Icons.filter_list),
            tooltip: 'Filter by Month',
          ),
        ],
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
        ProfilePhotoWithUpload(
          user: widget.user,
          radius: 30,
          onPhotoSelected: _handlePhotoSelected,
          isUploading: _isUploadingPhoto,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'You will get',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              GestureDetector(
                onTap: () => _showFundTransferDialog(),
                child: const Text(
                  'Fund Transfer',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
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
        ],
      ),
    );
  }

  Widget _buildTransactionHistory() {
    if (_filteredTransactions.isEmpty) {
      return Center(
        child: Text(
          _transactions.isEmpty
              ? 'No transactions found'
              : 'No transactions found for $_selectedMonth',
        ),
      );
    }

    // Group transactions by date
    final groupedTransactions = <String, List<AdvanceTransaction>>{};
    for (final transaction in _filteredTransactions) {
      final dateKey = _getDateKey(transaction.createdAt);
      groupedTransactions.putIfAbsent(dateKey, () => []).add(transaction);
    }

    // Sort dates in descending order (newest first)
    final sortedDates = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ENTRIES',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const Row(
              children: [
                Text(
                  'YOU GAVE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.red,
                  ),
                ),
                SizedBox(width: 20),
                Text(
                  'YOU GOT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            if (_selectedMonth != 'All Months')
              Text(
                _selectedMonth,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Display transactions grouped by date
        ...sortedDates.map((dateKey) {
          final transactions = groupedTransactions[dateKey]!;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDateHeaderWithTodayYesterday(dateKey),
              const SizedBox(height: 8),
              // Display each transaction individually
              ...transactions.map((transaction) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ENTRIES Column (Left) - Date, Time, Balance, Description
                      Expanded(flex: 3, child: _buildEntryCard(transaction)),
                      const SizedBox(width: 8),
                      // YOU GAVE Column (Middle) - Red amounts
                      Expanded(
                        flex: 1,
                        child: transaction.type == 'expense'
                            ? _buildAmountCard(transaction, isYouGot: false)
                            : const SizedBox(height: 60),
                      ),
                      const SizedBox(width: 8),
                      // YOU GOT Column (Right) - Green amounts
                      Expanded(
                        flex: 1,
                        child: transaction.type == 'advance_received'
                            ? _buildAmountCard(transaction, isYouGot: true)
                            : const SizedBox(height: 60),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
            ],
          );
        }),
      ],
    );
  }

  String _getDateKey(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day} ${_getMonthName(date.month)} ${date.year}';
    } catch (e) {
      return 'Unknown Date';
    }
  }

  String _getMonthName(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }

  Widget _buildDateHeaderWithTodayYesterday(String dateKey) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    String displayText = dateKey;
    try {
      final parts = dateKey.split(' ');
      if (parts.length >= 3) {
        final day = int.parse(parts[0]);
        final monthName = parts[1];
        final year = int.parse(parts[2]);

        // Find month index (add 1 since month index is 0-based)
        final monthIndex = _getMonthIndexFromName(monthName) + 1;
        if (monthIndex > 0) {
          final transactionDate = DateTime(year, monthIndex, day);
          final nowDate = DateTime(now.year, now.month, now.day);
          final yesterdayDate = DateTime(
            yesterday.year,
            yesterday.month,
            yesterday.day,
          );

          // Compare dates
          if (transactionDate.isAtSameMomentAs(nowDate)) {
            displayText = '$dateKey - Today';
          } else if (transactionDate.isAtSameMomentAs(yesterdayDate)) {
            displayText = '$dateKey - Yesterday';
          }
        }
      }
    } catch (e) {
      // If parsing fails, use original dateKey
      print('Date parsing error: $e');
    }

    return Text(
      displayText,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.black87,
      ),
    );
  }

  int _getMonthIndexFromName(String monthName) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months.indexOf(monthName);
  }

  // ENTRIES Column Card (Left) - Date, Time, Balance, Description
  Widget _buildEntryCard(AdvanceTransaction transaction) {
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
          // Date - Time
          Text(
            _formatDateTime(transaction.createdAt),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          // Balance
          if (transaction.runningBalance != null)
            Text(
              'Bal. ${transaction.formattedBalance}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.w500,
              ),
            ),
          const SizedBox(height: 4),
          // Description (full text with smaller font)
          Text(
            transaction.description,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  // Amount Card for YOU GAVE/YOU GOT columns
  Widget _buildAmountCard(
    AdvanceTransaction transaction, {
    bool isYouGot = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
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
      child: Center(
        child: Text(
          transaction.formattedAmount,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isYouGot ? Colors.green : Colors.red,
          ),
        ),
      ),
    );
  }

  String _formatDateTime(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final day = date.day.toString().padLeft(2, '0');
      final month = _getMonthName(date.month);
      final year = date.year.toString().substring(2); // Last 2 digits
      final minute = date.minute.toString().padLeft(2, '0');
      final ampm = date.hour >= 12 ? 'PM' : 'AM';
      final displayHour = date.hour > 12
          ? date.hour - 12
          : (date.hour == 0 ? 12 : date.hour);

      return '$day $month $year • ${displayHour.toString().padLeft(2, '0')}:$minute $ampm';
    } catch (e) {
      return 'Invalid Date';
    }
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

  void _showFundTransferDialog() async {
    print('DEBUG: Opening fund transfer dialog');
    print('DEBUG: Drivers already loaded, total: ${_driversList.length}');

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'YOU GOT - Fund Transfer',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Driver Search Field
                    const Text(
                      'Search Driver',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Driver Search TextField
                    TextField(
                      controller: _driverSearchController,
                      focusNode: _searchFocusNode,
                      enabled: _driversList.isNotEmpty,
                      decoration: InputDecoration(
                        hintText: _driversList.isEmpty
                            ? 'Loading drivers...'
                            : 'Type driver name to search...',
                        border: const OutlineInputBorder(),
                        prefixIcon: _driversList.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : const Icon(Icons.search),
                        suffixIcon: _selectedDriverId != null
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _selectedDriverId = null;
                                  _selectedDriverName = '';
                                  _driverSearchController.clear();
                                  _showDriverList = false;
                                  _filteredDriversList = List.from(
                                    _driversList,
                                  );
                                  setDialogState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        _filterDrivers(value);
                        setDialogState(() {}); // Trigger dialog rebuild
                      },
                      onTap: () {
                        if (_driverSearchController.text.isNotEmpty) {
                          _showDriverList = true;
                          setDialogState(() {});
                        }
                      },
                      textInputAction: TextInputAction.none,
                      keyboardType: TextInputType.text,
                    ),

                    // Search Results List
                    if (_showDriverList && _filteredDriversList.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredDriversList.length,
                          itemBuilder: (context, index) {
                            final driver = _filteredDriversList[index];
                            final isSelected =
                                _selectedDriverId == driver['id'].toString();

                            return ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.person,
                                color: isSelected ? Colors.green : Colors.grey,
                                size: 20,
                              ),
                              title: Text(
                                driver['name'],
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.green.shade700
                                      : Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                'ID: ${driver['id']}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: isSelected
                                  ? Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade600,
                                      size: 20,
                                    )
                                  : null,
                              onTap: () => _selectDriver(driver),
                            );
                          },
                        ),
                      ),

                    // No Results Message
                    if (_showDriverList &&
                        _filteredDriversList.isEmpty &&
                        _driverSearchController.text.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey.shade50,
                        ),
                        child: Text(
                          'No drivers found for "${_driverSearchController.text}"',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Transfer Amount
                    const Text(
                      'Transfer Amount',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _transferAmountController,
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setDialogState(
                          () {},
                        ); // Trigger rebuild for button state
                      },
                      decoration: InputDecoration(
                        prefixText: '₹ ',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'Enter amount',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Transfer Description
                    const Text(
                      'Transfer Description',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _transferDescriptionController,
                      onChanged: (value) {
                        setDialogState(
                          () {},
                        ); // Trigger rebuild for button state
                      },
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        hintText: 'e.g., Advance payment, Salary advance',
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Transfer Summary
                    if (_selectedDriverId != null &&
                        _transferAmountController.text.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Transfer Summary',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text('Driver: $_selectedDriverName'),
                            Text(
                              'Transfer Amount: ₹ ${_transferAmountController.text}',
                            ),
                            Text(
                              'Description: ${_transferDescriptionController.text}',
                            ),
                            Text(
                              'Date: ${DateTime.now().toString().split(' ')[0]}',
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _clearTransferForm();
                  },
                  child: const Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed:
                      _selectedDriverId != null &&
                          _transferAmountController.text.isNotEmpty &&
                          _transferDescriptionController.text.isNotEmpty
                      ? () async {
                          await _processFundTransfer();
                          if (mounted) {
                            Navigator.of(context).pop();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    'TRANSFER FUND',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _clearTransferForm() {
    _selectedDriverId = null;
    _selectedDriverName = '';
    _transferAmountController.clear();
    _transferDescriptionController.clear();
    _driverSearchController.clear();
    _showDriverList = false;
    _filteredDriversList = List.from(_driversList);
  }

  Future<void> _processFundTransfer() async {
    if (_selectedDriverId == null ||
        _transferAmountController.text.isEmpty ||
        _transferDescriptionController.text.isEmpty) {
      print(
        'DEBUG: Fund transfer validation failed - driverId: $_selectedDriverId, amount: ${_transferAmountController.text}, description: ${_transferDescriptionController.text}',
      );
      return;
    }

    try {
      // Show loading indicator
      setState(() {
        _isLoading = true;
      });

      final amount = double.tryParse(_transferAmountController.text) ?? 0.0;
      final description = _transferDescriptionController
          .text; // Just use the user's description
      final senderId = widget.user.driverId ?? widget.user.id;

      print(
        'DEBUG: Starting fund transfer - driverId: $_selectedDriverId, senderId: $senderId, amount: $amount, description: $description',
      );

      // Call API to save fund transfer
      final financeRepository = FinanceRepository();
      await financeRepository.submitFundTransfer(
        driverId: _selectedDriverId!,
        senderId: senderId,
        amount: amount,
        description: description,
      );

      // Clear form
      _clearTransferForm();

      // Reload data to get updated transactions and balance
      await _loadData();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fund transfer of ₹${amount.toStringAsFixed(0)} to $_selectedDriverName completed successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('DEBUG: Fund transfer error: $e');
      print('DEBUG: Error type: ${e.runtimeType}');
      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to process fund transfer: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Hide loading indicator
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDriversList() async {
    try {
      print('Loading drivers from API...');
      final response = await http.get(
        Uri.parse('https://sstranswaysindia.com/api/mobile/get_drivers.php'),
        headers: {'Content-Type': 'application/json'},
      );

      print('Driver API response status: ${response.statusCode}');
      print('Driver API response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['status'] == 'ok') {
          final driversData = data['drivers'] as List<dynamic>;
          print('DEBUG: Found ${driversData.length} drivers from API');
          for (var driver in driversData) {
            print('DEBUG: - ${driver['name']} (ID: ${driver['id']})');
          }
          setState(() {
            _driversList = driversData.cast<Map<String, dynamic>>();
          });
        } else {
          print('DEBUG: API returned error: ${data['error']}');
          _setFallbackDrivers();
        }
      } else {
        print('API request failed with status: ${response.statusCode}');
        _setFallbackDrivers();
      }
    } catch (e) {
      print('Error loading drivers: $e');
      _setFallbackDrivers();
    }

    // Initialize filtered list
    _filteredDriversList = List.from(_driversList);
    print('DEBUG: Drivers loaded at page start, total: ${_driversList.length}');
  }

  void _filterDrivers(String searchText) {
    // Real-time filtering
    if (searchText.isEmpty) {
      _filteredDriversList = List.from(_driversList);
      _showDriverList = false;
    } else {
      // Instant filtering
      final searchLower = searchText.toLowerCase();
      _filteredDriversList = _driversList
          .where(
            (driver) =>
                driver['name'].toString().toLowerCase().contains(searchLower),
          )
          .toList();
      _showDriverList = true;
    }

    // Immediate setState for real-time results
    setState(() {});
  }

  void _selectDriver(Map<String, dynamic> driver) {
    print('DEBUG: Driver selected: ${driver['name']}');
    _selectedDriverId = driver['id'].toString();
    _selectedDriverName = driver['name'];
    _driverSearchController.text = driver['name'];
    _showDriverList = false;
    setState(() {});
  }

  void _setFallbackDrivers() {
    print('DEBUG: Using fallback drivers');
    setState(() {
      _driversList = [
        {'id': 1, 'name': 'Test Driver 1'},
        {'id': 2, 'name': 'Test Driver 2'},
        {'id': 3, 'name': 'Test Driver 3'},
      ];
    });
    for (var driver in _driversList) {
      print('DEBUG: - ${driver['name']} (ID: ${driver['id']})');
    }
  }
}
