import 'dart:convert';
import 'package:ayman_target/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:ayman_target/constants.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // إذا كان الإشعار يحتوي على جسم notification، فإن FCM SDK يعرضه تلقائياً في الخلفية.
  // نقوم بعرض إشعار محلي فقط إذا كان الإشعار عبارة عن data-only message (لا يحتوي على notification).
  if (message.notification != null) {
    return;
  }

  final title = message.data['title']?.toString() ?? 'إشعار جديد';
  final body = message.data['body']?.toString() ?? '';
  final orderId = message.data['orderId']?.toString();

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  await plugin.initialize(settings: const InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  ));

  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      AppConstants.notificationChannelId,
      AppConstants.notificationChannelName,
      channelDescription: 'تنبيهات تعيين المسؤول عن الأوردرات',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  final payloadJson = orderId != null ? jsonEncode({'orderId': orderId}) : null;

  await plugin.show(
    id: (message.messageId?.hashCode.abs() ?? DateTime.now().millisecondsSinceEpoch) % 2147483647,
    title: title,
    body: body,
    notificationDetails: details,
    payload: payloadJson,
  );
}
