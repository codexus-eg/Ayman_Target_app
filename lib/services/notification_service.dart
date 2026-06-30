import 'dart:async';
import 'dart:convert';

import 'package:ayman_target/constants.dart';
import 'package:ayman_target/screens/order_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  final Set<String> _shownNotificationIds = {};
  String? _listeningUserId;
  bool _initialized = false;
  bool _firstSnapshot = true;
  DateTime? _listenStartedAt;
  GlobalKey<NavigatorState>? _navigatorKey;
  StreamSubscription<RemoteMessage>? _onMessageSub;
  StreamSubscription<String>? _onTokenRefreshSub;
  StreamSubscription<User?>? _authStateSub;

  Future<void> initialize(GlobalKey<NavigatorState> navigatorKey) async {
    if (_initialized) return;
    _navigatorKey = navigatorKey;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _localNotifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    const channel = AndroidNotificationChannel(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      description: 'تنبيهات تعيين المسؤول عن الأوردرات',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _onMessageSub = FirebaseMessaging.onMessage.listen(_onForegroundFcmMessage);

    await _saveFcmTokenIfLoggedIn();
    _onTokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      await _persistFcmToken(user.uid, token);
    });

    _authStateSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      if (user == null) {
        stopListening();
      } else {
        await _saveFcmTokenForUser(user.uid);
        await startListening(user.uid);
      }
    });

    _initialized = true;
  }

  void _onForegroundFcmMessage(RemoteMessage message) {
    // لو الـ Firestore listener شغال، هو اللي يعرض الإشعار بدل الـ FCM (لتفادي التكرار)
    if (_listeningUserId != null &&
        (message.data['type'] == 'order_assigned' || message.data['type'] == 'new_order')) {
      return;
    }
    final notificationId =
        message.data['notificationId']?.toString() ??
            message.messageId ??
            DateTime.now().toIso8601String();
    if (_shownNotificationIds.contains(notificationId)) return;
    if (_shownNotificationIds.length > 500) _shownNotificationIds.clear();
    _shownNotificationIds.add(notificationId);

    _showLocalNotification(
      title: message.notification?.title ??
          message.data['title']?.toString() ??
          'إشعار جديد',
      body: message.notification?.body ??
          message.data['body']?.toString() ??
          '',
      notificationId: notificationId.hashCode.abs() % 2147483647,
      orderId: message.data['orderId']?.toString(),
    );
  }

  /// معالجة الضغط على الإشعار المحلي (من جوا التطبيق)
  void _onNotificationTapped(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final orderId = data['orderId']?.toString();
      if (orderId == null || orderId.isEmpty) return;

      final orderSnap = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();

      if (!orderSnap.exists) return;

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

      _navigatorKey?.currentState?.push(
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(
            orderId: orderId,
            orderData: orderSnap.data()!,
            isAdmin: isAdmin,
          ),
        ),
      );
    } catch (e) {
      debugPrint('خطأ في فتح الأوردر من الإشعار: $e');
    }
  }

  Future<void> _saveFcmTokenIfLoggedIn() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await _saveFcmTokenForUser(user.uid);
  }

  Future<void> _saveFcmTokenForUser(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _persistFcmToken(uid, token);
    } catch (e) {
      debugPrint('خطأ في حفظ FCM token: $e');
    }
  }

  Future<void> _persistFcmToken(String uid, String token) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'fcmToken': token, 'fcmTokenUpdatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
  }

  Future<void> startListening(String userId) async {
    if (_listeningUserId == userId &&
        _notificationsSubscription != null) {
      return;
    }
    stopListening();
    _listeningUserId = userId;
    _shownNotificationIds.clear();
    _firstSnapshot = true;
    _listenStartedAt = DateTime.now();

    _notificationsSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .listen(_onNotificationsSnapshot);
  }

  void stopListening() {
    _notificationsSubscription?.cancel();
    _notificationsSubscription = null;
    _listeningUserId = null;
    _shownNotificationIds.clear();
    _listenStartedAt = null;
    unreadCount.value = 0;
  }

  void dispose() {
    stopListening();
    _onMessageSub?.cancel();
    _onTokenRefreshSub?.cancel();
    _authStateSub?.cancel();
    unreadCount.dispose();
  }

  void _onNotificationsSnapshot(QuerySnapshot snapshot) {
    unreadCount.value = snapshot.docs
        .where((d) => (d.data() as Map<String, dynamic>)['read'] != true)
        .length;

    if (_firstSnapshot) {
      _firstSnapshot = false;
      final recentCutoff =
          (_listenStartedAt ?? DateTime.now()).subtract(const Duration(minutes: 5));
      for (final doc in snapshot.docs) {
        _shownNotificationIds.add(doc.id);
        final data = doc.data() as Map<String, dynamic>;
        if (data['read'] == true) continue;
        if (!_isRecentNotification(data, recentCutoff)) continue;

        _showLocalNotification(
          title: data['title']?.toString() ?? 'إشعار جديد',
          body: data['body']?.toString() ?? '',
          notificationId: doc.id.hashCode.abs() % 2147483647,
          orderId: data['orderId']?.toString(),
        );
      }
      return;
    }

    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null || data['read'] == true) continue;
      if (_shownNotificationIds.contains(change.doc.id)) continue;

      _shownNotificationIds.add(change.doc.id);
      _showLocalNotification(
        title: data['title']?.toString() ?? 'إشعار جديد',
        body: data['body']?.toString() ?? '',
        notificationId: change.doc.id.hashCode.abs() % 2147483647,
        orderId: data['orderId']?.toString(),
      );
    }
  }

  bool _isRecentNotification(
    Map<String, dynamic> data,
    DateTime cutoff,
  ) {
    final createdAt = data['createdAt'];
    if (createdAt is Timestamp) {
      return createdAt.toDate().isAfter(cutoff);
    }
    return false;
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    required int notificationId,
    String? orderId,
  }) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        AppConstants.notificationChannelId,
        AppConstants.notificationChannelName,
        channelDescription: 'تنبيهات تعيين المسؤول عن الأوردرات',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
    // إرسال orderId كـ payload عشان لما المستخدم يدوس على الإشعار نعرف نفتح الأوردر
    final payloadJson = orderId != null ? jsonEncode({'orderId': orderId}) : null;
    await _localNotifications.show(
      id: notificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payloadJson,
    );
  }

  /// إشعار جماعي لكل المستخدمين عند إضافة أوردر جديد.
  /// بيكتب إشعار في subcollection كل مستخدم ← Cloud Function بتبعت FCM push لكل واحد.
  Future<void> sendNewOrderNotificationToAll({
    required String orderId,
    required String clientName,
    required String creatorName,
    required String orderType,
    required String branch,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // جلب المستخدمين في نفس الفرع فقط
    final usersSnapshot =
        await FirebaseFirestore.instance.collection('users').where('branch', isEqualTo: branch).get();

    final title = '📦 أوردر جديد';
    final body =
        '$creatorName أضاف أوردر جديد ($orderType) للعميل "$clientName" - فرع $branch';

    WriteBatch batch = FirebaseFirestore.instance.batch();
    int batchCount = 0;
    for (final userDoc in usersSnapshot.docs) {
      // لا تبعت إشعار للشخص اللي أنشأ الأوردر
      if (userDoc.id == currentUid) continue;

      if (batchCount >= 499) {
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        batchCount = 0;
      }

      final notifRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .collection('notifications')
          .doc();

      batch.set(notifRef, {
        'type': 'new_order',
        'title': title,
        'body': body,
        'orderId': orderId,
        'clientName': clientName,
        'creatorName': creatorName,
        'orderType': orderType,
        'branch': branch,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batchCount++;
    }
    if (batchCount > 0) await batch.commit();
  }

  /// إشعار فوري للموظف المعيَّن فقط عند تغيير المسؤول من الأدمن.
  Future<void> sendOrderAssignedNotification({
    required String targetUserId,
    required String orderId,
    required String clientName,
    required String assignedBy,
  }) async {
    if (targetUserId.isEmpty) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && currentUid == targetUserId) return;

    const title = 'أوردر جديد مسؤول عنه';
    final body =
        'تم تعيينك مسؤولاً عن أوردر العميل "$clientName" بواسطة $assignedBy';

    await FirebaseFirestore.instance
        .collection('users')
        .doc(targetUserId)
        .collection('notifications')
        .add({
      'type': 'order_assigned',
      'title': title,
      'body': body,
      'orderId': orderId,
      'clientName': clientName,
      'assignedBy': assignedBy,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> markAsRead(String userId, String notificationId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  Future<void> markAllAsRead(String userId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('notifications')
          .where('read', isEqualTo: false)
          .limit(499)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (e) {
      debugPrint('خطأ في تحديث الإشعارات: $e');
    }
  }
}
