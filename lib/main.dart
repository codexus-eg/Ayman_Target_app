import 'package:ayman_target/app_colors.dart';
import 'package:ayman_target/screens/login_screen.dart';
import 'package:ayman_target/screens/employee_screen.dart';
import 'package:ayman_target/screens/order_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ayman_target/push_notification_handler.dart';
import 'package:ayman_target/services/notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';

/// مفتاح التنقل العام - يستخدم للانتقال لصفحة تفاصيل الأوردر عند الضغط على إشعار
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeDateFormatting('ar', null);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await NotificationService.instance.initialize(navigatorKey);
  } catch (e) {
    debugPrint('خطأ في تهيئة التطبيق: $e');
    runApp(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('حدث خطأ في تشغيل التطبيق.\nيرجى المحاولة مرة أخرى.\n\n$e',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.red)),
          ),
        ),
      ),
    ));
    return;
  }
  runApp(const AymanTargetApp());
}

class AymanTargetApp extends StatefulWidget {
  const AymanTargetApp({super.key});

  @override
  State<AymanTargetApp> createState() => _AymanTargetAppState();
}

class _AymanTargetAppState extends State<AymanTargetApp> {
  @override
  void initState() {
    super.initState();
    _setupFcmInteraction();
  }

  /// معالجة الضغط على إشعار FCM (التطبيق في الخلفية أو مقفول)
  void _setupFcmInteraction() {
    // 1. لما التطبيق كان مقفول تماماً والمستخدم دوس على الإشعار وفتح التطبيق
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        // ننتظر لحظة عشان الـ navigator يكون جاهز
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToOrderFromFcm(message.data);
        });
      }
    });

    // 2. لما التطبيق في الخلفية والمستخدم دوس على الإشعار
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _navigateToOrderFromFcm(message.data);
    });
  }

  /// الانتقال لصفحة تفاصيل الأوردر من بيانات الإشعار
  void _navigateToOrderFromFcm(Map<String, dynamic> data) async {
    final orderId = data['orderId']?.toString();
    if (orderId == null || orderId.isEmpty) return;

    try {
      final orderSnap = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();

      if (orderSnap.exists) {
        // تحديد هل المستخدم أدمن
        bool isAdmin = false;
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          isAdmin = (userDoc.data()?['role'] ?? '').toString().trim().toLowerCase() == 'admin';
        }

        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => OrderDetailScreen(
              orderId: orderId,
              orderData: orderSnap.data()!,
              isAdmin: isAdmin,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('خطأ في فتح الأوردر من الإشعار: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Ayman Target',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: AppColors.primary,
      ),
      // التعديل هنا في الـ home
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // 1. لو لسه بيبحث عن حالة المستخدم (لحظة التحميل)
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          // 2. لو حصل خطأ
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                    const SizedBox(height: 16),
                    const Text('حدث خطأ في الاتصال', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {}),
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasData) {
            return const EmployeeScreen();
          }

          // 3. لو مفيش مستخدم مسجل (أو عمل Logout)
          return const LoginScreen();
        },
      ),
    );
  }
}