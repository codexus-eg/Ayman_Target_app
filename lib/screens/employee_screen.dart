import 'dart:async';
import 'package:ayman_target/app_colors.dart';
import 'package:ayman_target/constants.dart';
import 'package:ayman_target/screens/notifications_screen.dart';
import 'package:ayman_target/screens/order_detail_screen.dart';
import 'package:ayman_target/screens/profile_screen.dart';
import 'package:ayman_target/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class EmployeeScreen extends StatefulWidget {
  const EmployeeScreen({super.key});

  @override
  State<EmployeeScreen> createState() => _EmployeeScreenState();
}

class _EmployeeScreenState extends State<EmployeeScreen> {
  String _searchQuery = "";
  String _statusFilter = "الكل";
  String _selectedEmployee = "الكل";
  String _userName = "جاري التحميل...";
  String _userBranch = AppConstants.defaultBranch;
  String _selectedBranchFilter = AppConstants.defaultBranch;
  bool _isAdmin = false;
  bool _isLoadingUser = true;
  List<String> _allEmployees = ["الكل"];

  String _selectedOrderTypeFilter = "الكل";
  StreamSubscription<QuerySnapshot>? _ordersSubscription;

  DateTime _selectedStatsDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _checkPermissionsAndLoadData();
  }

  void _checkPermissionsAndLoadData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          String role = (doc.data()?['role'] ?? "user").toString().trim().toLowerCase();
          String branch = doc.data()?['branch'] ?? AppConstants.defaultBranch;

          if (!mounted) return;
          setState(() {
            _userName = doc.data()?['name'] ?? "مستخدم";
            _userBranch = branch;
            _selectedBranchFilter = branch;
            _isAdmin = (role == 'admin');
            _isLoadingUser = false;
          });

          _loadEmployeesByBranch(_selectedBranchFilter);
        } else {
          if (mounted) setState(() => _isLoadingUser = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingUser = false);
    }
  }

  void _loadEmployeesByBranch(String branch) async {
    var collection = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: branch)
        .get();

    List<String> temp = ["الكل"];
    for (var doc in collection.docs) {
      if (doc.data().containsKey('name')) temp.add(doc.data()['name']);
    }
    if (!mounted) return;
    setState(() => _allEmployees = temp);
  }

  void _showAdminDashboard() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) {
        return StatefulBuilder(
            builder: (context, setModalState) {
              DateTime startOfDay = DateTime(_selectedStatsDate.year, _selectedStatsDate.month, _selectedStatsDate.day);
              DateTime endOfDay = startOfDay.add(const Duration(days: 1));

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('orders')
                    .where('branch', isEqualTo: _selectedBranchFilter)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Container(height: MediaQuery.of(context).size.height * 0.8, alignment: Alignment.center, child: const CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Container(height: MediaQuery.of(context).size.height * 0.8, alignment: Alignment.center, child: const Text("حدث خطأ في تحميل البيانات"));
                  }

                  double dayTotalPaid = 0;
                  double dayTotalOrders = 0;
                  int completedCount = 0;
                  int deliveredCount = 0;
                  int pendingCount = 0;
                  int canceledCount = 0;

                  Map<String, int> performance = {};
                  Map<String, double> employeeMoney = {};

                  if (snapshot.hasData && snapshot.data != null) {
                    for (var doc in snapshot.data!.docs) {
                      try {
                        var d = doc.data() as Map<String, dynamic>?;
                        if (d == null) continue;

                        Timestamp? orderTimestamp = d['timestamp'] as Timestamp?;
                        if (orderTimestamp == null) continue;
                        DateTime orderDate = orderTimestamp.toDate();
                        if (orderDate.isBefore(startOfDay) || orderDate.isAfter(endOfDay)) {
                          continue;
                        }
                        String status = (d['status'] ?? 'انتظار').toString();
                        double paidMoney = 0.0;
                        double totalMoney = 0.0;
                        if (d['paid'] != null) paidMoney = (d['paid'] is int) ? (d['paid'] as int).toDouble() : (d['paid'] as double);
                        if (d['total'] != null) totalMoney = (d['total'] is int) ? (d['total'] as int).toDouble() : (d['total'] as double);
                        if (status == 'مكتمل' || status == 'تم التسليم') {
                          dayTotalPaid += paidMoney;
                          dayTotalOrders += totalMoney;
                          if (status == 'تم التسليم') {
                            deliveredCount++;
                          } else {
                            completedCount++;
                          }
                          String emp = (d['employeeName'] ?? "غير محدد").toString().trim();
                          if(emp.isEmpty) emp = "غير محدد";
                          performance[emp] = (performance[emp] ?? 0) + 1;
                          employeeMoney[emp] = (employeeMoney[emp] ?? 0.0) + paidMoney;
                        } else if (status == 'ملغي' || status == 'مرتجع') {
                          canceledCount++;
                        } else {
                          pendingCount++;
                        }
                      } catch (e) {
                        continue;
                      }
                    }
                  }

                  List<MapEntry<String, int>> sortedList = performance.entries.toList();
                  sortedList.sort((a, b) => b.value.compareTo(a.value));

                  return Container(
                    padding: const EdgeInsets.all(24),
                    height: MediaQuery.of(context).size.height * 0.85,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                                child: Text(
                                    "تقرير فرع $_selectedBranchFilter المالي",
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis
                                )
                            ),
                            IconButton(
                              icon: const Icon(Icons.calendar_month, color: AppColors.primary, size: 28),
                              onPressed: () async {
                                final picked = await showDatePicker(context: context, initialDate: _selectedStatsDate, firstDate: DateTime(2023), lastDate: DateTime.now().add(const Duration(days: 365)));
                                if (picked != null) setModalState(() => _selectedStatsDate = picked);
                              },
                            ),
                          ],
                        ),
                        Text("تاريخ اليوم الفعلي: ${DateFormat('yyyy/MM/dd').format(_selectedStatsDate)}", style: const TextStyle(color: Colors.grey)),
                        const Divider(height: 20, thickness: 1),

                        _statCard("إجمالي الكاش (داخل الدرج حالياً)", "$dayTotalPaid ج.م", Colors.green),
                        const SizedBox(height: 8),
                        _statCard("إجمالي قيمة المطلوبات كاملة", "$dayTotalOrders ج.م", Colors.blue),
                        const SizedBox(height: 12),

                        Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _miniStatCard("تم التسليم", "$deliveredCount أوردر", Colors.teal)),
                                const SizedBox(width: 8),
                                Expanded(child: _miniStatCard("مكتمل ومقفل", "$completedCount أوردر", Colors.green)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: _miniStatCard("تحت التجهيز", "$pendingCount أوردر", Colors.orange)),
                                const SizedBox(width: 8),
                                Expanded(child: _miniStatCard("مرتجع / ملغي", "$canceledCount أوردر", Colors.red)),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),
                        const Text("ترتيب إنتاجية موظفي الفرع ماليّاً:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 10),

                        Expanded(
                          child: sortedList.isEmpty
                              ? const Center(child: Text("لا توجد أوردرات مكتملة أو مسلمة مسجلة باسم موظفين اليوم"))
                              : ListView.builder(
                            itemCount: sortedList.length,
                            itemBuilder: (context, index) {
                              var entry = sortedList[index];
                              String empName = entry.key;
                              int totalEmpOrders = entry.value;
                              double moneyCount = employeeMoney[empName] ?? 0.0;
                              int rank = index + 1;
                              Color rankColor = rank == 1 ? Colors.amber : (rank == 2 ? Colors.grey : (rank == 3 ? Colors.brown : Colors.blueGrey));

                              return Card(
                                elevation: 0,
                                color: Colors.grey[50],
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey[200]!)),
                                child: ListTile(
                                  leading: CircleAvatar(backgroundColor: rankColor, child: Text("$rank", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                  title: Text(empName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text("سلّم وتقفل له: $totalEmpOrders أوردر", style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  trailing: Text("$moneyCount ج.م كاش", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                                ),
                              );
                            },
                          ),
                        )
                      ],
                    ),
                  );
                },
              );
            }
        );
      },
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16), textAlign: TextAlign.end),
        ],
      ),
    );
  }

  Widget _miniStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // 📝 دالة تنسيق التاريخ والوقت بالساعة والدقيقة تلقائياً
  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return "جاري التسجيل...";
    DateTime date = timestamp.toDate();
    return DateFormat('yyyy/MM/dd - hh:mm a').format(date);
  }

  void _deleteOrder(String docId) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("تأكيد المسح"), content: const Text("حذف الأوردر نهائياً؟"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
        TextButton(onPressed: () async {
          final navigator = Navigator.of(context);
          final scaffoldMessenger = ScaffoldMessenger.of(context);
          try {
            await FirebaseFirestore.instance.collection('orders').doc(docId).delete();
            navigator.pop();
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('تم حذف الأوردر بنجاح', textAlign: TextAlign.center), backgroundColor: Colors.green),
            );
          } catch (e) {
            navigator.pop();
            scaffoldMessenger.showSnackBar(
              SnackBar(content: Text('فشل الحذف: ليس لديك صلاحية أو حدث خطأ: $e', textAlign: TextAlign.center), backgroundColor: Colors.redAccent),
            );
          }
        }, child: const Text("مسح", style: TextStyle(color: Colors.red))),
      ],
    ));
  }

  void _reassignOrder(
    String docId,
    String orderBranch, {
    required String clientName,
    required String currentEmployeeName,
  }) async {
    var collection = await FirebaseFirestore.instance
        .collection('users')
        .where('branch', isEqualTo: orderBranch)
        .get();

    final branchEmployees = <Map<String, String>>[];
    for (var doc in collection.docs) {
      final name = doc.data()['name']?.toString();
      if (name != null && name.isNotEmpty) {
        branchEmployees.add({'uid': doc.id, 'name': name});
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("تغيير المسؤول (فرع $orderBranch)"),
        content: SizedBox(
            width: double.maxFinite,
            child: branchEmployees.isEmpty
                ? const Padding(padding: EdgeInsets.all(8.0), child: Text("لا يوجد موظفين مسجلين في هذا الفرع", textAlign: TextAlign.center))
                : ListView(
                shrinkWrap: true,
                children: branchEmployees.map((employee) => ListTile(
                    title: Text(employee['name']!),
                    onTap: () async {
                      final name = employee['name']!;
                      final targetUid = employee['uid']!;
                      if (currentEmployeeName == name) {
                        if (context.mounted) Navigator.pop(context);
                        return;
                      }

                      await Future.wait([
                        FirebaseFirestore.instance
                            .collection('orders')
                            .doc(docId)
                            .update({'employeeName': name}),
                        NotificationService.instance
                            .sendOrderAssignedNotification(
                          targetUserId: targetUid,
                          orderId: docId,
                          clientName: clientName,
                          assignedBy: _userName,
                        ),
                      ]);

                      if (context.mounted) Navigator.pop(context);
                    }
                )).toList()
            )
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  Color _getCardBackgroundColor(String status) {
    switch (status) {
      case 'تم التسليم': return const Color(0xFFE0F2F1);
      case 'مكتمل': return const Color(0xFFE8F5E9);
      case 'جاري الطباعة': return AppColors.primarySurface;
      case 'ملغي': case 'مرتجع': return const Color(0xFFFFEBEE);
      case 'انتظار':
      default: return const Color(0xFFFFF3E0);
    }
  }

  Color _getCardBorderColor(String status) {
    switch (status) {
      case 'تم التسليم': return Colors.teal.withValues(alpha: 0.4);
      case 'مكتمل': return Colors.green.withValues(alpha: 0.3);
      case 'جاري الطباعة': return AppColors.primary.withValues(alpha: 0.3);
      case 'ملغي': case 'مرتجع': return Colors.red.withValues(alpha: 0.3);
      case 'انتظار':
      default: return Colors.orange.withValues(alpha: 0.3);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_isAdmin ? "لوحة الإدارة - فرع $_selectedBranchFilter" : "أهلاً $_userName (فرع $_userBranch)", style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white, elevation: 0.5,
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: NotificationService.instance.unreadCount,
            builder: (context, unread, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined,
                        color: AppColors.primary, size: 26),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => NotificationsScreen(
                            isAdmin: _isAdmin,
                          ),
                        ),
                      );
                    },
                  ),
                  if (unread > 0)
                    Positioned(
                      right: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          unread > 9 ? '9+' : '$unread',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.account_circle_outlined, color: AppColors.primary, size: 26),
            onPressed: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => ProfileScreen(
                        userName: _userName,
                        isAdmin: _isAdmin,
                        userBranch: _userBranch,
                      )
                  )
              );
            },
          ),
          if (_isAdmin) IconButton(icon: const Icon(Icons.dashboard_customize_rounded, color: AppColors.primary), onPressed: _showAdminDashboard),
          IconButton(icon: const Icon(Icons.logout, color: Colors.red), onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("تسجيل الخروج"),
                content: const Text("هل أنت متأكد من تسجيل الخروج؟"),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("إلغاء")),
                  TextButton(onPressed: () { Navigator.pop(context); FirebaseAuth.instance.signOut(); }, child: const Text("خروج", style: TextStyle(color: Colors.red))),
                ],
              ),
            );
          }),
        ],
      ),
      body: Column(
        children: [
          _buildTopFilters(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').where('branch', isEqualTo: _selectedBranchFilter).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

                var sortedDocs = snapshot.data!.docs.toList();
                sortedDocs.sort((a, b) {
                  var aTime = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                  var bTime = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                  if (aTime == null) return 1;
                  if (bTime == null) return -1;
                  return bTime.compareTo(aTime);
                });

                var docs = sortedDocs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  bool matchesSearch = (data['clientName'] ?? '').toString().contains(_searchQuery) || (data['phone'] ?? '').toString().contains(_searchQuery);
                  
                  String status = data['status'] ?? 'انتظار';
                  String orderType = data['orderType'] ?? 'طباعة';
                  bool isPrintType = orderType == 'طباعة' || orderType == 'لوحات وبانرات' || orderType == 'ملازم ومذكرات' || orderType == 'كروت شخصية';

                  bool matchesStatus;
                  if (_statusFilter == "الكل") {
                    matchesStatus = true;
                  } else if (_statusFilter == "جاري الطباعة") {
                    matchesStatus = (status == "جاري الطباعة") && isPrintType;
                  } else if (_statusFilter == "جاري التنفيذ") {
                    matchesStatus = (status == "جاري الطباعة") && !isPrintType;
                  } else {
                    matchesStatus = status == _statusFilter;
                  }

                  bool matchesEmployee = _selectedEmployee == "الكل" || data['employeeName'] == _selectedEmployee;
                  bool matchesOrderType = _selectedOrderTypeFilter == "الكل" || (data['orderType'] ?? 'طباعة') == _selectedOrderTypeFilter;
                  return matchesSearch && matchesStatus && matchesEmployee && matchesOrderType;
                }).toList();

                if(docs.isEmpty) return const Center(child: Text("لا توجد أوردرات تطابق الفلتر بالفرع الحالي"));

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    var data = docs[index].data() as Map<String, dynamic>;
                    String docId = docs[index].id;
                    String status = data['status'] ?? 'انتظار';
                    String orderType = data['orderType'] ?? 'طباعة';
                    String orderBranch = data['branch'] ?? _selectedBranchFilter;
                    bool canControl = _isAdmin || data['creatorName'] == _userName || data['employeeName'] == _userName;

                    return TweenAnimationBuilder<double>(
                      duration: Duration(milliseconds: 250 + (index * 40).clamp(0, 300)),
                      tween: Tween(begin: 0.0, end: 1.0),
                      builder: (context, value, child) {
                        return Transform.translate(offset: Offset(0, 20 * (1 - value)), child: Opacity(opacity: value, child: child));
                      },
                      child: InkWell(
                        onTap: _isAdmin ? () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => OrderDetailScreen(orderId: docId, orderData: data, isAdmin: _isAdmin)));
                        } : () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عفواً، تفاصيل وسجل الأوردر متاحة للإدارة فقط', textAlign: TextAlign.center), backgroundColor: Colors.redAccent, duration: Duration(seconds: 2)));
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: _getCardBackgroundColor(status), borderRadius: BorderRadius.circular(16), border: Border.all(color: _getCardBorderColor(status), width: 1),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 3))],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text("استلام: ${data['creatorName'] ?? 'موظف'}", style: TextStyle(color: Colors.grey[700], fontSize: 11)),
                                      const SizedBox(height: 2),
                                      InkWell(
                                          onTap: _isAdmin
                                              ? () => _reassignOrder(
                                                    docId,
                                                    orderBranch,
                                                    clientName: data['clientName']?.toString() ?? 'عميل',
                                                    currentEmployeeName: data['employeeName']?.toString() ?? '',
                                                  )
                                              : null,
                                          child: Text("المسؤول: ${data['employeeName']}", style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.bold, fontSize: 13))
                                      ),
                                    ]),
                                    if (canControl) Row(children: [
                                      IconButton(icon: const Icon(Icons.edit_note, color: Colors.orange, size: 24), onPressed: () => _showAddOrder(isEdit: true, docId: docId, existingData: data)),
                                      IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 24), onPressed: () => _deleteOrder(docId)),
                                    ]),
                                  ],
                                ),
                                const Divider(color: Colors.black12, thickness: 0.5, height: 20),
                                // ✨ عرض نوع الأوردر كـ badge
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text('📋 $orderType', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                                ),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(data['clientName'] ?? 'بدون اسم', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            const Icon(Icons.phone, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                                data['phone'] != null && data['phone'].toString().isNotEmpty ? data['phone'].toString() : "لا يوجد رقم مسجل",
                                                style: TextStyle(fontSize: 13, color: Colors.grey[700], fontWeight: FontWeight.w500)
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        // 🕒 هنا تم إضافة وعرض التاريخ والوقت بالساعة والدقيقة بشكل ثابت ومستمر
                                        Row(
                                          children: [
                                            const Icon(Icons.access_time_rounded, size: 14, color: Colors.grey),
                                            const SizedBox(width: 4),
                                            Text(
                                                _formatDateTime(data['timestamp'] as Timestamp?),
                                                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  _statusChip(docId, status, orderType, canControl),
                                ]),
                                const SizedBox(height: 12),
                                Container(
                                    width: double.infinity, padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.black.withValues(alpha: 0.05), width: 0.5)),
                                    child: Text(data['details'] ?? "", style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.3))
                                ),
                                const SizedBox(height: 15),
                                _priceSection(data, Colors.black87),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showAddOrder(), backgroundColor: AppColors.primary, child: const Icon(Icons.add, color: Colors.white)),
    );
  }

  Widget _buildTopFilters() {
    return Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          TextField(onChanged: (v) => setState(() => _searchQuery = v), decoration: InputDecoration(hintText: "بحث سريع بالاسم أو الموبايل...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.grey[100], border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
          const SizedBox(height: 8),

          if (_isAdmin) ...[
            DropdownButton<String>(
                value: _selectedBranchFilter,
                isExpanded: true,
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark),
                items: AppConstants.branches.map((b) => DropdownMenuItem(value: b, child: Text("عرض أوردرات فرع: $b"))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedBranchFilter = v;
                      _selectedEmployee = "الكل";
                    });
                    _loadEmployeesByBranch(v);
                  }
                }
            ),
            const SizedBox(height: 8),
          ],

          DropdownButton<String>(
              value: _selectedEmployee,
              isExpanded: true,
              items: _allEmployees.map((e) => DropdownMenuItem(value: e, child: Text("مسؤول: $e"))).toList(),
              onChanged: (v) => setState(() => _selectedEmployee = v!)
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ["الكل", "انتظار", "جاري الطباعة", "جاري التنفيذ", "مكتمل", "تم التسليم", "ملغي", "مرتجع"].map((s) {
            return Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(s), selected: _statusFilter == s, onSelected: (v) => setState(() => _statusFilter = s)));
          }).toList())),
          const SizedBox(height: 4),
          // ✨ فلتر نوع الأوردر
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ["الكل", ...AppConstants.orderTypes].map((t) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(t, style: const TextStyle(fontSize: 11)), selected: _selectedOrderTypeFilter == t, onSelected: (v) => setState(() => _selectedOrderTypeFilter = t)))).toList())),
        ])
    );
  }

  Widget _statusChip(String id, String s, String orderType, bool canEdit) {
    String displayStatus = s;
    if (s == 'جاري الطباعة') {
      if (orderType == 'طباعة' || orderType == 'لوحات وبانرات' || orderType == 'ملازم ومذكرات' || orderType == 'كروت شخصية') {
        displayStatus = 'جاري الطباعة';
      } else {
        displayStatus = 'جاري التنفيذ';
      }
    }

    Color color = s == 'تم التسليم' ? Colors.teal : (s == 'مكتمل' ? Colors.green : (s == 'جاري الطباعة' ? AppColors.primary : Colors.orange));
    Widget label = Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.5))), child: Text(displayStatus, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)));
    if (!canEdit) return label;
    return PopupMenuButton<String>(
      onSelected: (v) => FirebaseFirestore.instance.collection('orders').doc(id).update({'status': v}), 
      itemBuilder: (c) => ['انتظار', 'جاري الطباعة', 'مكتمل', 'تم التسليم', 'ملغي'].map((v) {
        String itemLabel = v;
        if (v == 'جاري الطباعة') {
          if (orderType == 'طباعة' || orderType == 'لوحات وبانرات' || orderType == 'ملازم ومذكرات' || orderType == 'كروت شخصية') {
            itemLabel = 'جاري الطباعة';
          } else {
            itemLabel = 'جاري التنفيذ';
          }
        }
        return PopupMenuItem(value: v, child: Text(itemLabel));
      }).toList(), 
      child: label
    );
  }

  Widget _priceSection(Map<String, dynamic> data, Color textColor) {
    double t = (data['total'] ?? 0).toDouble(); double p = (data['paid'] ?? 0).toDouble();
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(child: _priceItem("إجمالي", t, textColor)),
      Expanded(child: _priceItem("مدفوع", p, Colors.green[700]!)),
      Expanded(child: _priceItem("باقي", (t - p) < 0 ? 0 : t - p, Colors.red[700]!)),
    ]);
  }

  Widget _priceItem(String l, double v, Color c) => Column(children: [Text(l, style: const TextStyle(fontSize: 11, color: Colors.grey)), const SizedBox(height: 2), Text("$v ج.م", style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 14))]);

  void _showAddOrder({bool isEdit = false, String? docId, Map<String, dynamic>? existingData}) {
    final nameController = TextEditingController(text: isEdit ? existingData!['clientName'] : "");
    final phoneController = TextEditingController(text: isEdit ? existingData!['phone'] : "");
    final detailsController = TextEditingController(text: isEdit ? existingData!['details'] : "");
    final totalController = TextEditingController(text: isEdit ? existingData!['total'].toString() : "");
    final paidController = TextEditingController(text: isEdit ? existingData!['paid'].toString() : "");
    // ✨ نوع الأوردر (القيمة الافتراضية أو القيمة الحالية للتعديل)
    String selectedType = isEdit ? (existingData?['orderType'] ?? 'طباعة') : 'طباعة';
    bool isSaving = false;
    String? errorMessage;

    final nameFocusNode = FocusNode();
    final phoneFocusNode = FocusNode();
    final detailsFocusNode = FocusNode();
    final totalFocusNode = FocusNode();
    final paidFocusNode = FocusNode();

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) => StatefulBuilder(
          builder: (context, setModalState) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isEdit ? "تعديل الأوردر" : "أوردر جديد (فرع $_selectedBranchFilter)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Text(
                        errorMessage!,
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  const SizedBox(height: 15),
                  TextField(focusNode: nameFocusNode, controller: nameController, decoration: _inputDec("اسم العميل", Icons.person)), const SizedBox(height: 10),
                  TextField(focusNode: phoneFocusNode, controller: phoneController, keyboardType: TextInputType.phone, decoration: _inputDec("رقم الموبايل (11 رقم)", Icons.phone)), const SizedBox(height: 10),
                  // ✨ اختيار نوع الأوردر
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: _inputDec("نوع الأوردر", Icons.category),
                    items: AppConstants.orderTypes.map((String type) {
                      return DropdownMenuItem<String>(value: type, child: Text(type));
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setModalState(() => selectedType = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(focusNode: detailsFocusNode, controller: detailsController, decoration: _inputDec("تفاصيل الاوردر ؟", Icons.edit)), const SizedBox(height: 10),
                  Row(children: [Expanded(child: TextField(focusNode: totalFocusNode, controller: totalController, keyboardType: TextInputType.number, decoration: _inputDec("إجمالي", Icons.money))), const SizedBox(width: 10), Expanded(child: TextField(focusNode: paidFocusNode, controller: paidController, keyboardType: TextInputType.number, decoration: _inputDec("مدفوع", Icons.check)))]),
                  const SizedBox(height: 20),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: isEdit ? Colors.amber : AppColors.primary, minimumSize: const Size(double.infinity, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: isSaving ? null : () async {
                        String name = nameController.text.trim();
                        String phone = phoneController.text.trim();
                        String details = detailsController.text.trim();

                        if (name.isEmpty) {
                          setModalState(() {
                            errorMessage = "برجاء إدخال اسم العميل أولاً!";
                          });
                          nameFocusNode.requestFocus();
                          return;
                        }

                        if (phone.isEmpty) {
                          setModalState(() {
                            errorMessage = "برجاء إدخال رقم الموبايل أولاً!";
                          });
                          phoneFocusNode.requestFocus();
                          return;
                        }

                        if (phone.length != 11) {
                          setModalState(() {
                            errorMessage = "رقم الموبايل غير صحيح! يجب أن يتكون من 11 رقماً بالضبط.";
                          });
                          phoneFocusNode.requestFocus();
                          return;
                        }

                        RegExp phoneRegex = RegExp(r'^(010|011|012|015)[0-9]{8}$');
                        if (!phoneRegex.hasMatch(phone)) {
                          setModalState(() {
                            errorMessage = "رقم الموبايل غير صحيح! يجب أن يبدأ بـ 010 أو 011 أو 012 أو 015";
                          });
                          phoneFocusNode.requestFocus();
                          return;
                        }

                        if (details.isEmpty) {
                          setModalState(() {
                            errorMessage = "برجاء إدخال تفاصيل الأوردر أولاً!";
                          });
                          detailsFocusNode.requestFocus();
                          return;
                        }

                        String totalStr = totalController.text.trim();
                        if (totalStr.isEmpty) {
                          setModalState(() {
                            errorMessage = "برجاء إدخال إجمالي المبلغ أولاً!";
                          });
                          totalFocusNode.requestFocus();
                          return;
                        }
                        double? totalVal = double.tryParse(totalStr);
                        if (totalVal == null) {
                          setModalState(() {
                            errorMessage = "المبلغ الإجمالي يجب أن يكون رقماً صحيحاً.";
                          });
                          totalFocusNode.requestFocus();
                          return;
                        }

                        String paidStr = paidController.text.trim();
                        if (paidStr.isEmpty) {
                          setModalState(() {
                            errorMessage = "برجاء إدخال المبلغ المدفوع أولاً!";
                          });
                          paidFocusNode.requestFocus();
                          return;
                        }
                        double? paidVal = double.tryParse(paidStr);
                        if (paidVal == null) {
                          setModalState(() {
                            errorMessage = "المبلغ المدفوع يجب أن يكون رقماً صحيحاً.";
                          });
                          paidFocusNode.requestFocus();
                          return;
                        }

                        setModalState(() {
                          errorMessage = null;
                          isSaving = true;
                        });

                        final d = {
                          'clientName': name,
                          'phone': phone,
                          'details': details,
                          'total': double.tryParse(totalController.text) ?? 0,
                          'paid': double.tryParse(paidController.text) ?? 0,
                          'orderType': selectedType,
                        };

                        try {
                          if(isEdit && docId != null && existingData != null) {
                            Map<String, dynamic> oldData = {
                              'clientName': existingData['clientName'],
                              'phone': existingData['phone'],
                              'details': existingData['details'],
                              'total': existingData['total'],
                              'paid': existingData['paid'],
                              'orderType': existingData['orderType'] ?? 'طباعة',
                            };

                            await FirebaseFirestore.instance.collection('orders').doc(docId).update({
                              ...d,
                              'lastEdit': {
                                'editedBy': _userName,
                                'editTimestamp': FieldValue.serverTimestamp(),
                                'old': oldData,
                                'new': d
                              }
                            });
                          } else {
                            // ✨ إضافة أوردر جديد مع نوعه
                            await FirebaseFirestore.instance.collection('orders').add({
                              ...d,
                              'creatorName': _userName,
                              'employeeName': _userName,
                              'status': 'انتظار',
                              'branch': _selectedBranchFilter,
                              'timestamp': FieldValue.serverTimestamp(),
                            });

                            // ✨ الإشعار يتم إرساله الآن تلقائياً عن طريق الـ Cloud Function على السيرفر (onOrderCreated) لمنع التكرار ودعم الطلبات المرفوعة من العملاء.
                          }
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          setModalState(() {
                            isSaving = false;
                            errorMessage = "حدث خطأ أثناء الحفظ، حاول مرة أخرى";
                          });
                        }
                      },
                      child: isSaving
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(isEdit ? "تعديل وتحديث" : "حفظ الأوردر", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  ),
                  const SizedBox(height: 20)
                ],
              ),
            ),
          ),
        )
    ).then((_) {
      nameController.dispose();
      phoneController.dispose();
      detailsController.dispose();
      totalController.dispose();
      paidController.dispose();
      nameFocusNode.dispose();
      phoneFocusNode.dispose();
      detailsFocusNode.dispose();
      totalFocusNode.dispose();
      paidFocusNode.dispose();
    });
  }

  InputDecoration _inputDec(String l, IconData i) => InputDecoration(labelText: l, prefixIcon: Icon(i), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]);
}