import 'package:ayman_target/app_colors.dart';
import 'package:ayman_target/constants.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class ProfileScreen extends StatefulWidget {
  final String userName;
  final bool isAdmin;
  final String userBranch;

  const ProfileScreen({
    super.key,
    required this.userName,
    required this.isAdmin,
    required this.userBranch,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DateTime _selectedDate = DateTime.now();
  Stream<QuerySnapshot>? _ordersStream;

  @override
  void initState() {
    super.initState();
    _refreshOrdersStream();
  }

  void _refreshOrdersStream() {
    _ordersStream = FirebaseFirestore.instance.collection('orders').where('branch', isEqualTo: widget.userBranch).snapshots();
  }

  bool _matchesBranch(Map<String, dynamic> data) {
    final branch = data['branch']?.toString().trim();
    if (branch == null || branch.isEmpty) {
      return widget.userBranch == AppConstants.defaultBranch;
    }
    return branch == widget.userBranch;
  }

  bool _isOnSelectedDay(Timestamp? timestamp) {
    if (timestamp == null) return false;
    final orderDate = timestamp.toDate();
    return orderDate.year == _selectedDate.year &&
        orderDate.month == _selectedDate.month &&
        orderDate.day == _selectedDate.day;
  }

  List<QueryDocumentSnapshot> _docsForDay(List<QueryDocumentSnapshot> docs) {
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      if (!_matchesBranch(data)) return false;
      return _isOnSelectedDay(data['timestamp'] as Timestamp?);
    }).toList();
  }

  // 📊 دالة لحساب وتلخيص أعداد الأوردرات فقط في كل قائمة (بدون فلوس)
  Widget _buildSummaryCard({required List<QueryDocumentSnapshot> docs, required String title, required Color color}) {
    int completedCount = 0;
    int totalCount = docs.length;

    for (var doc in docs) {
      var data = doc.data() as Map<String, dynamic>;
      if (data['status'] == 'مكتمل') {
        completedCount++;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          const SizedBox(height: 6),
          Text("إجمالي اليوم: $totalCount أوردر", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 2),
          Text("تم اكتماله: $completedCount", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // 📑 دالة بناء قائمة الأوردرات لكل قسم (بدون عرض مبالغ الإجمالي والمدفوع)
  Widget _buildOrdersList(List<QueryDocumentSnapshot> docs) {
    if (docs.isEmpty) {
      return const Center(child: Text("لا توجد أوردرات مسجلة لهذا اليوم"));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        var data = docs[index].data() as Map<String, dynamic>;
        String status = data['status'] ?? 'انتظار';
        String orderType = data['orderType'] ?? 'طباعة';
        String displayStatus = status;
        if (status == 'جاري الطباعة') {
          if (orderType == 'طباعة' || orderType == 'لوحات وبانرات' || orderType == 'ملازم ومذكرات' || orderType == 'كروت شخصية') {
            displayStatus = 'جاري الطباعة';
          } else {
            displayStatus = 'جاري التنفيذ';
          }
        }

        Color statusColor = status == 'مكتمل' ? Colors.green : (status == 'جاري الطباعة' ? AppColors.primary : Colors.orange);

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: statusColor.withValues(alpha: 0.2), width: 1),
          ),
          color: status == 'مكتمل' ? const Color(0xFFF4FBF7) : (status == 'جاري الطباعة' ? AppColors.primarySurface : const Color(0xFFFFFBF5)),
          child: ListTile(
            title: Text(data['clientName'] ?? "بدون اسم", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text("النوع: ${data['orderType'] ?? 'طباعة'}", style: TextStyle(color: Colors.purple[700], fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text("التفاصيل: ${data['details'] ?? ''}", maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.grey[700], fontSize: 12)),
              ],
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: statusColor)),
              child: Text(displayStatus, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // قائمتين (مسؤول ومستلم)
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        appBar: AppBar(
          title: const Text("الملف الشخصي والإنتاجية", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0.5,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.calendar_month, color: AppColors.primary),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2023),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) {
                  setState(() {
                    _selectedDate = picked;
                  });
                }
              },
            )
          ],
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primary,
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.assignment_turned_in_outlined), text: "المسؤول عنها"),
              Tab(icon: Icon(Icons.create_new_folder_outlined), text: "المستلمة (المنشأة)"),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: _ordersStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    "تعذر تحميل الإنتاجية.\nتأكد من نشر فهارس Firestore.",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ),
              );
            }

            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final dayDocs = _docsForDay(snapshot.data!.docs);

            var responsibleOrders = dayDocs.where((doc) {
              var d = doc.data() as Map<String, dynamic>;
              return d['employeeName'] == widget.userName;
            }).toList();

            var createdOrders = dayDocs.where((doc) {
              var d = doc.data() as Map<String, dynamic>;
              return d['creatorName'] == widget.userName;
            }).toList();

            return Column(
              children: [
                // 💳 كارت تعريفي فوق بالموظف وتلخيص سريع لليوم
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: widget.isAdmin ? Colors.red[50] : AppColors.primarySurface,
                            child: Icon(widget.isAdmin ? Icons.admin_panel_settings : Icons.person, color: widget.isAdmin ? Colors.red : AppColors.primary, size: 28),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.userName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                Text(widget.isAdmin ? "الرتبة: أدمن السيستم" : "الرتبة: موظف تنفيذ", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                              ],
                            ),
                          ),
                          Text(DateFormat('yyyy/MM/dd').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(child: _buildSummaryCard(docs: responsibleOrders, title: "إنتاجية المسؤولية", color: AppColors.primary)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildSummaryCard(docs: createdOrders, title: "إنتاجية الاستلام", color: Colors.purple)),
                        ],
                      ),
                    ],
                  ),
                ),

                // 📑 عرض القائمتين بالتبادل حسب الـ Tab المختار
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildOrdersList(responsibleOrders),
                      _buildOrdersList(createdOrders),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}