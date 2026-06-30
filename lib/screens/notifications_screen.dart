import 'package:ayman_target/app_colors.dart';
import 'package:ayman_target/screens/order_detail_screen.dart';
import 'package:ayman_target/services/notification_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatelessWidget {
  final bool isAdmin;

  const NotificationsScreen({super.key, required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('يجب تسجيل الدخول أولاً')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: () => NotificationService.instance.markAllAsRead(uid),
            child: const Text('قراءة الكل'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('حدث خطأ ما أثناء تحميل الإشعارات'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'لا توجد إشعارات',
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final isRead = data['read'] == true;
              final createdAt = data['createdAt'] as Timestamp?;

              // معالجة آمنة للتاريخ في حال عدم اكتمال الكتابة على السيرفر بعد (Server Timestamp)
              String timeStr = '';
              if (createdAt != null) {
                try {
                  timeStr = DateFormat('dd/MM hh:mm a', 'ar').format(createdAt.toDate());
                } catch (_) {
                  timeStr = ''; // تفادي أي كراش مفاجئ في الـ formatting
                }
              }

              return Material(
                color: isRead ? Colors.white : AppColors.primarySurface,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    // تحديث الحالة فوراً
                    NotificationService.instance.markAsRead(uid, doc.id);

                    final orderId = data['orderId']?.toString();
                    if (orderId != null) {
                      try {
                        final orderSnap = await FirebaseFirestore.instance
                            .collection('orders')
                            .doc(orderId)
                            .get();

                        if (orderSnap.exists && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => OrderDetailScreen(
                                orderId: orderId,
                                orderData: orderSnap.data()!,
                                isAdmin: isAdmin,
                              ),
                            ),
                          );
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('عذراً، هذا الأوردر تم حذفه من قبل المسؤول.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } catch (e) {
                        debugPrint("خطأ في جلب تفاصيل الطلب: $e");
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.assignment_ind,
                          color: isRead ? Colors.grey : AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['title']?.toString() ?? 'إشعار',
                                style: TextStyle(
                                  fontWeight: isRead ? FontWeight.w500 : FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                data['body']?.toString() ?? '',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[800],
                                ),
                              ),
                              if (timeStr.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}