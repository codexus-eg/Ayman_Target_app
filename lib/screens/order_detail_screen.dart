import 'package:ayman_target/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class OrderDetailScreen extends StatelessWidget {
  final String orderId;
  final Map<String, dynamic> orderData;
  final bool isAdmin; // ✨ ضفنا المتغير دا هنا

  const OrderDetailScreen({
    super.key,
    required this.orderId,
    required this.orderData,
    required this.isAdmin, // ✨ وضفناه في الكونستركتور
  });

  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return "غير محدد";
    DateTime date = timestamp.toDate();
    return "${date.day}/${date.month}/${date.year} - ${DateFormat('hh:mm a').format(date)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("تفاصيل الأوردر بالكامل", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').doc(orderId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (!snapshot.data!.exists) return const Center(child: Text("هذا الأوردر لم يعد موجوداً"));

          var currentData = snapshot.data!.data() as Map<String, dynamic>;
          var lastEdit = currentData['lastEdit'] as Map<String, dynamic>?;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 📑 كارت البيانات الحالية للأوردر (يشوفه الكل عادي)
              Card(
                color: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey[200]!)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDetailRow("اسم العميل:", currentData['clientName'], Icons.person, AppColors.primary),
                      _buildDetailRow("رقم الموبايل:", currentData['phone'], Icons.phone, Colors.green),
                      _buildDetailRow("حالة الأوردر الحالية:", currentData['status'] ?? 'انتظار', Icons.info_outline, Colors.orange),
                      _buildDetailRow("نوع الأوردر:", currentData['orderType'] ?? 'طباعة', Icons.category, Colors.deepPurple),
                      const Divider(height: 30),
                      _buildDetailRow("المستلم (المنشئ):", currentData['creatorName'] ?? 'غير محدد', Icons.assignment_ind_outlined, Colors.purple),
                      _buildDetailRow("المسؤول الحالي:", currentData['employeeName'] ?? 'غير محدد', Icons.supervised_user_circle, AppColors.primaryLight),
                      _buildDetailRow("تاريخ الإنشاء:", _formatDateTime(currentData['timestamp'] as Timestamp?), Icons.calendar_today, Colors.grey),
                      const Divider(height: 30),
                      const Text("تفاصيل الطلب:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey[200]!)),
                        child: Text(currentData['details'] ?? "", style: const TextStyle(fontSize: 15, height: 1.4, color: Colors.black87)),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _priceBox("الإجمالي", "${currentData['total']} ج.م", Colors.black87),
                          _priceBox("المدفوع", "${currentData['paid']} ج.م", Colors.green[700]!),
                          _priceBox("المتبقي", "${(currentData['total'] ?? 0) - (currentData['paid'] ?? 0)} ج.م", Colors.red[700]!),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 🛑 قسم سجل التعديلات (تم تعديل الشرط ليظهر للأدمن فقط ومادام فيه تعديل)
              if (isAdmin && lastEdit != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text("⚠️ سجل آخر تعديل (للأدمن فقط)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                ),
                Card(
                  color: const Color(0xFFFFF9C4),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.amber, width: 0.5)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.edit_attributes, color: Colors.amber, size: 24),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "قام بالتعديل: ${lastEdit['editedBy']}",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("وقت التعديل: ${_formatDateTime(lastEdit['editTimestamp'] as Timestamp?)}", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                        const Divider(color: Colors.black12, height: 25),

                        const Text("مقارنة البيانات (القديم 🚫 مقابل الجديد ✅):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                        const SizedBox(height: 10),

                        if (lastEdit['old'] != null && lastEdit['new'] != null) ...[
                          _buildCompareItem("الاسم", (lastEdit['old'] as Map<String, dynamic>?)?['clientName'], (lastEdit['new'] as Map<String, dynamic>?)?['clientName']),
                          _buildCompareItem("الموبايل", (lastEdit['old'] as Map<String, dynamic>?)?['phone'], (lastEdit['new'] as Map<String, dynamic>?)?['phone']),
                          _buildCompareItem("التفاصيل", (lastEdit['old'] as Map<String, dynamic>?)?['details'], (lastEdit['new'] as Map<String, dynamic>?)?['details']),
                          _buildCompareItem("الإجمالي", "${(lastEdit['old'] as Map<String, dynamic>?)?['total'] ?? 0} ج.م", "${(lastEdit['new'] as Map<String, dynamic>?)?['total'] ?? 0} ج.م"),
                          _buildCompareItem("المدفوع", "${(lastEdit['old'] as Map<String, dynamic>?)?['paid'] ?? 0} ج.م", "${(lastEdit['new'] as Map<String, dynamic>?)?['paid'] ?? 0} ج.م"),
                          _buildCompareItem("نوع الأوردر", (lastEdit['old'] as Map<String, dynamic>?)?['orderType'] ?? 'طباعة', (lastEdit['new'] as Map<String, dynamic>?)?['orderType'] ?? 'طباعة'),
                        ] else
                          const Text("بيانات التعديل غير مكتملة", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ]
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String title, String value, IconData icon, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black87), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _priceBox(String label, String amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(amount, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildCompareItem(String label, dynamic oldVal, dynamic newVal) {
    if (oldVal == null && newVal == null) return const SizedBox.shrink();
    if (oldVal.toString() == newVal.toString()) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$label:", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.primaryDark)),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(child: Text("قبل: $oldVal", style: const TextStyle(color: Colors.red, fontSize: 13, decoration: TextDecoration.lineThrough))),
              const Icon(Icons.arrow_left, color: Colors.grey),
              Expanded(child: Text("بعد: $newVal", style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold))),
            ],
          ),
          const Divider(color: Colors.black12, thickness: 0.3),
        ],
      ),
    );
  }
}