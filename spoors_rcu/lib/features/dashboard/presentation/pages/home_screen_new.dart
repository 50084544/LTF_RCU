import 'package:BMS/core/common_widgets/bottomnavbar.dart';
//import 'package:BMS/core/common_widgets/toast.dart';
import 'package:BMS/core/network/api_service.dart';
import 'package:BMS/features/workid_list/presentation/pages/workid.dart';
import 'package:flutter/material.dart';
//import 'dart:math' as math;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lottie/lottie.dart';
import '../../../auth/data/datasources/api_service.dart';
// import '../../../auth/presentation/bloc/session/session_bloc.dart';
// import '../../../auth/presentation/bloc/session/session_event.dart';
//import '../../../workid_list/presentation/pages/audit_list_screen.dart  ';
import '../../../../core/constants/constants.dart';
import 'package:hive/hive.dart';
import '../../../../core/common_widgets/hamburger.dart';
//import 'dart:math' show sin, pi, min;
import 'dart:async'; // Added for Timer

class HomeScreenNew extends StatefulWidget {
  const HomeScreenNew({Key? key}) : super(key: key);

  @override
  State<HomeScreenNew> createState() => _HomeScreenNewState();
}

class _HomeScreenNewState extends State<HomeScreenNew>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _errorMessage;
  bool _noTasks = false;
  late AnimationController _animationController;
  late List<Animation<double>> _bubbleAnimations;
  late List<Animation<double>> _fadeAnimations;
  late List<Animation<double>> _floatAnimations;
  String username = ''; // Default value
  int selectedTab = 0;

  // Modified cooldown variables
  bool _isReloadButtonDisabled = false;
  Timer? _cooldownTimer;
  int _remainingMinutes = 5;

  final List<Map<String, dynamic>> _auditCategories = [
    {
      'id': 'live_disbursement',
      'title': 'Live Disbursement',
      'icon': Icons.money,
      'color': AppColors.primary,
      'route': 'live_disbursement',
      'isNew': true,
    },
    {
      'id': 'collection_audit',
      'title': 'Collection Audit',
      'icon': Icons.account_balance_wallet,
      'color': AppColors.primary,
      'route': 'collection_audit',
      'isNew': true,
    },
    {
      'id': 'post_disbursement_audit',
      'title': 'Post Disbursement Audit',
      'icon': Icons.assignment_turned_in,
      'color': AppColors.primary,
      'route': 'post_disbursement_audit',
      'isNew': true,
    },
    {
      'id': 'special_audit',
      'title': 'Special Audit',
      'icon': Icons.star,
      'color': AppColors.primary,
      'route': 'special_audit',
      'isNew': true,
    },
    {
      'id': 'crm_audit',
      'title': 'CRM Audit',
      'icon': Icons.people,
      'color': AppColors.primary,
      'route': 'crm_audit',
      'isNew': false,
    },
    {
      'id': 'branch_compliance_audit',
      'title': 'Branch Compliance Audit',
      'icon': Icons.business,
      'color': AppColors.primary,
      'route': 'branch_compliance_audit',
      'isNew': false,
    },
    {
      'id': 'cross_audit',
      'title': 'Cross Audit',
      'icon': Icons.swap_horiz,
      'color': AppColors.primary,
      'route': 'cross_audit',
      'isNew': false,
    },
    {
      'id': 'fmr_theft_robbery',
      'title': 'FMR 4 theft & robbery',
      'icon': Icons.security,
      'color': AppColors.primary,
      'route': 'fmr_theft_robbery',
      'isNew': false,
    },
    {
      'id': 'bpm_appraisal',
      'title': 'BPM Appraisal',
      'icon': Icons.assessment,
      'color': AppColors.primary,
      'route': 'bpm_appraisal',
      'isNew': false,
    },
    {
      'id': 'pdav',
      'title': 'PDAV',
      'icon': Icons.verified_user,
      'color': AppColors.primary,
      'route': 'pdav',
      'isNew': false,
    },
  ];

  // Dynamic audit categories that will be populated from API
  List<Map<String, dynamic>> _dynamicAuditCategories = [];

  @override
  void initState() {
    super.initState();

    // Delay to access context and arguments
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map &&
          args['name'] != null &&
          args['name'].toString().isNotEmpty) {
        setState(() {
          username = args['name'].toString();
        });
      }
      // Now fetch data with the username from argument
      _fetchtoken();
      // Optionally, update username from Hive after
      _loadUsername();
    });

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _initBubbleAnimations(_auditCategories.length);
    Future.delayed(const Duration(milliseconds: 100), () {
      _animationController.forward();
    });
  }

  void _initBubbleAnimations(int count) {
    // Each bubble pops in sequence, with a delay for each
    // Bubble pop has a 'scale' animation starting at 0.0 and ending at 1.0
    // We'll use Intervals to stagger the pop-in
    const bubblePopDuration = 0.38; // fraction of total duration for each pop
    const popDelay = 0.18; // delay (fraction) between each pop
    _bubbleAnimations = [];
    _fadeAnimations = [];
    _floatAnimations = [];
    for (int i = 0; i < count; i++) {
      final start = (i * popDelay).clamp(0.0, 1.0 - bubblePopDuration);
      final end = (start + bubblePopDuration).clamp(0.0, 1.0);
      _bubbleAnimations.add(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(start, end, curve: Curves.elasticOut),
        ),
      );
      _fadeAnimations.add(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
      _floatAnimations.add(
        CurvedAnimation(
          parent: _animationController,
          curve: Interval(start, end, curve: Curves.easeInOut),
        ),
      );
    }
  }

  @override
  void didUpdateWidget(covariant HomeScreenNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    // In case widget updated and categories changed, re-init
    _initBubbleAnimations(_getCategories().length);
  }

  @override
  void dispose() {
    _animationController.dispose();
    _cooldownTimer?.cancel(); // Cancel cooldown timer when widget is disposed
    super.dispose();
  }

  // Fixed method to start cooldown timer - using minutes for production
  void _startCooldownTimer() {
    // If no tasks were found, don't apply cooldown
    if (_noTasks) {
      setState(() {
        _isReloadButtonDisabled = false;
      });
      return;
    }

    setState(() {
      _remainingMinutes = 5; // Set to 5 minutes for production
      _isReloadButtonDisabled = true;
    });

    // Using a more reliable timer approach
    _cooldownTimer?.cancel(); // Cancel any existing timer
    _cooldownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _remainingMinutes--;

          if (_remainingMinutes <= 0) {
            _isReloadButtonDisabled = false;
            timer.cancel();
          }
        });
      } else {
        timer.cancel(); // Ensure timer is canceled if widget is unmounted
      }
    });

    // For immediate UI feedback - only show if we have tasks
    if (!_noTasks) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Reload will be available again in 5 minutes'),
        backgroundColor: Colors.blue,
        duration: Duration(seconds: 3),
      ));
    }
  }

  // Method to show remaining time snackbar - fixed with proper error handling
  void _showRemainingTimeSnackbar() {
    if (!mounted) return;

    String timeText =
        _remainingMinutes == 1 ? "1 minute" : "$_remainingMinutes minutes";

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Kindly wait for $timeText and try again'),
      backgroundColor: Colors.blue,
      duration: const Duration(seconds: 3),
    ));
  }

  // Fixed _fetchtoken method to properly handle disabled state
  Future<void> _fetchtoken() async {
    // If button is disabled and we have tasks, show snackbar and return
    if (_isReloadButtonDisabled && !_noTasks) {
      _showRemainingTimeSnackbar();
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    // Start cooldown timer after setting loading state
    _startCooldownTimer();

    try {
      final ApiCall apiCall = ApiCall();
      final result =
          await apiCall.callApi(endpoint: 'listview', username: username);

      // Ensure widget is still mounted before updating state
      if (!mounted) return;

      if (result['success']) {
        _dynamicAuditCategories = [];
        final Set<String> uniqueRecordTypes = {};
        final Map<String, String> recordIdByType = {};
        final Map<String, String> uidByType = {};

        // Check for empty records array
        bool hasRecords = false;

        // Case 1: Check records directly in data
        if (result['data'] != null &&
            result['data']['records'] is List &&
            (result['data']['records'] as List).isNotEmpty) {
          hasRecords = true;
        }

        // Case 2: Check records in all_records
        else if (result['data'] != null &&
            result['data']['all_records'] != null &&
            result['data']['all_records']['records'] is List &&
            (result['data']['all_records']['records'] as List).isNotEmpty) {
          hasRecords = true;
        }

        // Case 3: Check records_by_type
        else if (result['data'] != null &&
            result['data']['records_by_type'] != null &&
            (result['data']['records_by_type'] as Map).isNotEmpty) {
          // Check if any record type has at least one record
          bool anyRecordsFound = false;
          (result['data']['records_by_type'] as Map).forEach((key, value) {
            if (value is List && value.isNotEmpty) {
              anyRecordsFound = true;
            }
          });
          hasRecords = anyRecordsFound;
        }

        // If no records found in any format, show "no tasks" view
        if (!hasRecords) {
          setState(() {
            _isLoading = false;
            _noTasks = true; // Set no tasks flag
            _dynamicAuditCategories = []; // Clear any categories
          });
          return;
        }

        // Continue with existing logic for processing records...
        if (result['data'] != null &&
            result['data']['record_types'] != null &&
            result['data']['record_types'] is List) {
          final List<dynamic> recordTypes = result['data']['record_types'];

          for (var recordType in recordTypes) {
            if (recordType is String) {
              uniqueRecordTypes.add(recordType);
              final records = result['data']['records_by_type']?[recordType];
              if (records != null && records.isNotEmpty && records[0] is Map) {
                recordIdByType[recordType] = records[0]['Work_Id__c'] ?? '';
                uidByType[recordType] = records[0]['Id'] ?? '';
              }
            }
          }
        } else if (result['data'] != null &&
            result['data']['all_records'] != null &&
            result['data']['all_records']['records'] is List) {
          final List<dynamic> records =
              result['data']['all_records']['records'];

          for (var record in records) {
            if (record is Map && record['RecordTypeName'] != null) {
              final recordType = record['RecordTypeName'];
              uniqueRecordTypes.add(recordType);
              if (!recordIdByType.containsKey(recordType)) {
                recordIdByType[recordType] = record['Work_Id__c'] ?? '';
                uidByType[recordType] = records[0]['Id'] ?? '';
              }
            }
          }
        } else if (result['data'] != null &&
            result['data']['records'] is List) {
          final List<dynamic> records = result['data']['records'];

          for (var record in records) {
            if (record is Map && record['RecordTypeName'] != null) {
              final recordType = record['RecordTypeName'];
              uniqueRecordTypes.add(recordType);
              if (!recordIdByType.containsKey(recordType)) {
                recordIdByType[recordType] = record['Work_Id__c'] ?? '';
                uidByType[recordType] = records[0]['Id'] ?? '';
              }
            }
          }
        }
        for (var recordType in uniqueRecordTypes) {
          recordType.replaceAll('_', ' ');
          IconData icon = _getIconForRecordType(recordType);
          Color color = AppColors.primary;
          bool isNew = _isNewRecordType(recordType);

          // Count records for this type
          int recordCount = 0;
          if (result['data'] != null &&
              result['data']['records_by_type'] != null) {
            final records = result['data']['records_by_type'][recordType];
            if (records is List) {
              recordCount = records.length;
            }
          } else if (result['data'] != null &&
              result['data']['records'] is List) {
            // Fallback for flat list
            recordCount = (result['data']['records'] as List)
                .where((rec) => rec['RecordTypeName'] == recordType)
                .length;
          }

          _dynamicAuditCategories.add({
            'id': _getIdFromRecordTypeName(recordType),
            //'title': recordType.replaceAll('_', ' '),
            'title': recordType,
            'icon': icon,
            'color': color,
            'route': _getIdFromRecordTypeName(recordType),
            'isNew': isNew,
            'recordId': recordIdByType[recordType],
            'uid': uidByType[recordType],
            'count': recordCount,
          });
        }
        setState(() {
          _isLoading = false;
          _noTasks = false; // Explicitly set to false since we found records
        });

        // Re-init bubble animation so the correct number of cards animate
        _initBubbleAnimations(_getCategories().length);

        _animationController.reset();
        Future.delayed(const Duration(milliseconds: 100), () {
          _animationController.forward();
        });
      } else {
        // API returned success: false
        setState(() {
          _errorMessage = result['message'] ?? 'No tasks available';
          _isLoading = false;
          _noTasks =
              true; // Set to true for any error case that indicates no tasks
        });
      }
    } catch (e) {
      // Ensure widget is still mounted before updating state
      if (!mounted) return;

      setState(() {
        _errorMessage = 'An error occurred: ${e.toString()}';
        _isLoading = false;
        _noTasks = false;
      });
    }
  }

  // Helper method to generate ID from record type name
  String _getIdFromRecordTypeName(String recordTypeName) {
    return recordTypeName.toLowerCase().replaceAll(' ', '_');
  }

  // Helper method to determine icon for record type
  IconData _getIconForRecordType(String recordTypeName) {
    switch (recordTypeName) {
      case 'Live_Disbursement':
        return Icons.money;
      case 'Collection_Audit':
        return Icons.account_balance_wallet;
      case 'Post_Disbursement_Audit':
        return Icons.assignment_turned_in;
      case 'Special_Audit':
        return Icons.star;
      case 'CRM_Audit':
        return Icons.people;
      case 'Branch_Compliance_Audit':
        return Icons.business;
      case 'Cross_Audit':
        return Icons.swap_horiz;
      case 'FMR 4 theft & robbery':
        return Icons.security;
      case 'Fmr_Theft_Robbery':
        return Icons.security;
      case 'BPM_Appraisal':
        return Icons.assessment;
      case 'PDAV':
        return Icons.verified_user;
      default:
        return Icons.work;
    }
  }

  bool _isNewRecordType(String recordTypeName) {
    return true;
  }

  List<Map<String, dynamic>> _getCategories() {
    return _dynamicAuditCategories.isNotEmpty
        ? _dynamicAuditCategories
        : _auditCategories;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: CustomDrawer(isOnDashboard: true, username: username),
      appBar: AppBar(
        toolbarHeight: 60,
        title: Text(
          'Activities',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            // Only disable the button if tasks exist and cooldown is active
            // Keep it enabled if there are no tasks (even during cooldown)
            onPressed: (_isReloadButtonDisabled && !_noTasks)
                ? () => _showRemainingTimeSnackbar() // Show cooldown message
                : _fetchtoken, // Fetch data immediately
            // Only show as disabled if tasks exist and cooldown is active
            color: (_isReloadButtonDisabled && !_noTasks) ? Colors.grey : null,
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 250,
                    height: 250,
                    child: Lottie.asset(
                      'assets/animations/downloadAnimation.json',
                      repeat: true,
                      animate: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Fetching data...',
                    style: TextStyle(
                      fontSize: 18,
                      fontStyle: FontStyle.italic,
                      color: Color(0xFF0F2B5B),
                    ),
                  ),
                ],
              ),
            )
          : _noTasks || _dynamicAuditCategories.isEmpty
              ? _buildNoTasksView()
              : _errorMessage != null
                  ? _buildErrorView()
                  : _buildHomeContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 60,
              color: Color(0xff0F68A0),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: AppSpacing.medium),
          ],
        ),
      ),
    );
  }

  Widget _buildNoTasksView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 250,
            height: 250,
            child: Lottie.asset(
              'assets/animations/NoTasks.json', // <-- Use your Notasks lottie file
              repeat: true,
              animate: true,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'You have no pending tasks!',
            style: TextStyle(
              fontSize: 18,
              fontStyle: FontStyle.italic,
              color: Color(0xFF0F2B5B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeContent() {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
              child: _buildAuditGrid(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditGrid() {
    final categories = _getCategories();

    // Re-init animations if length doesn't match (hot reload/dev-time only)
    if (_bubbleAnimations.length != categories.length) {
      _initBubbleAnimations(categories.length);
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            // Bubble pop: scale from 0 to 1 with elastic, fade-in, float up and down
            final scale = _bubbleAnimations[index].value;
            final opacity = _fadeAnimations[index].value;
            //final floatY = sin(_floatAnimations[index].value * 2 * pi) * 3;
            final floatY = _generateFloatOffset(_floatAnimations[index].value);
            return Transform.translate(
              offset: Offset(0, floatY),
              child: Transform.scale(
                scale: scale,
                child: Opacity(
                  opacity: opacity,
                  child: child,
                ),
              ),
            );
          },
          child: _buildAuditCard(categories[index], index),
        );
      },
    );
  }

  Widget _buildAuditCard(Map<String, dynamic> category, int index) {
    final bool isCompleted = category['isCompleted'] == true;
    return InkWell(
      onTap: () => _navigateToAuditList(category),
      child: Container(
        decoration: BoxDecoration(
          color: isCompleted ? Colors.green[100] : Colors.white,
          border: Border.all(
            color: isCompleted ? Colors.green : const Color(0xFF0F2B5B),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: (isCompleted ? Colors.green : const Color(0xFF0F2B5B))
                  .withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isCompleted)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'COMPLETED',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            if (category['isNew'] == true)
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(255, 210, 221, 241),
                      borderRadius: BorderRadius.circular(5),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0xFF0F2B5B).withOpacity(0.2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Text(
                      'NEW',
                      style: TextStyle(
                        color: Color(0xFF0F2B5B),
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: category['color'].withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                category['icon'],
                color: category['color'],
                size: 36,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                // Show title and count
                category['count'] != null && category['count'] > 0
                    ? '${category['title']} (${category['count']})'
                    : category['title'],
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: category['color'],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToAuditList(Map<String, dynamic> category) async {
    print('Sending username to workid as $username');
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Workid(
          title: category['title'],
          recordType: category['title'],
          recordId: category['recordId'],
          uid: category['uid'], // Pass the uid to Workid
          username: username,
        ),
      ),
    );

    if (result != null) {
      if (result['completedRecordType'] != null) {
        setState(() {
          _markCategoryAsCompleted(result['completedRecordType']);
        });
      } else if (result['updatedRecordType'] != null) {
        setState(() {
          _updateCategoryPendingCount(
            result['updatedRecordType'],
            result['pendingCount'] ?? 0,
          );
        });
      }
    }
  }

  void _markCategoryAsCompleted(String recordType) {
    int idx =
        _dynamicAuditCategories.indexWhere((cat) => cat['title'] == recordType);
    if (idx != -1) {
      var cat = _dynamicAuditCategories.removeAt(idx);
      cat['isCompleted'] = true;
      cat['isNew'] = false;
      cat['count'] = 0;
      _dynamicAuditCategories.add(cat); // Move to bottom
    }
  }

  void _updateCategoryPendingCount(String recordType, int pendingCount) {
    int idx =
        _dynamicAuditCategories.indexWhere((cat) => cat['title'] == recordType);
    if (idx != -1) {
      _dynamicAuditCategories[idx]['count'] = pendingCount;
    }
  }

  // Add a method to load username from Hive - it was referenced but missing
  void _loadUsername() {
    try {
      final box = Hive.box('auth');
      final storedUsername = box.get('username');
      if (storedUsername != null && storedUsername.toString().isNotEmpty) {
        setState(() {
          username = storedUsername.toString();
        });
      }
    } catch (e) {}
  }

  double _generateFloatOffset(double animationValue) {
    // Use a deterministic approach without relying on math.sin
    // This creates a smooth up-and-down motion using only basic arithmetic

    // Scale the animation value to a full cycle (0 to 1)
    double cycle = animationValue % 1.0;

    // Create a parabolic curve: y = 4 * (x - 0.5)²
    // This gives 0 at x=0.5 and approaches 1 at x=0 and x=1
    double parabolicValue = 4.0 * (cycle - 0.5) * (cycle - 0.5);

    // Invert and scale the value to get the float effect (-3 to 3 pixels)
    return (1.0 - parabolicValue) * 6.0 - 3.0;
  }
}
