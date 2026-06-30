abstract final class AppConstants {
  // Collection paths
  static const String usersCollection = 'users';
  static const String ordersCollection = 'orders';
  static const String notificationsSubcollection = 'notifications';

  // Notification configuration
  static const String notificationChannelId = 'high_importance_channel';
  static const String notificationChannelName = 'إشعارات الأوردرات';

  // Branches
  static const String defaultBranch = 'بنها';
  static const List<String> branches = ['بنها', 'شبين'];

  // Order statuses
  static const String statusWaiting = 'انتظار';
  static const String statusPrinting = 'جاري الطباعة';
  static const String statusCompleted = 'مكتمل';
  static const String statusDelivered = 'تم التسليم';
  static const String statusCancelled = 'ملغي';
  static const String statusReturned = 'مرتجع';

  static const List<String> orderStatuses = [
    statusWaiting,
    statusPrinting,
    statusCompleted,
    statusDelivered,
    statusCancelled,
  ];

  // User roles
  static const String roleAdmin = 'admin';
  static const String roleUser = 'user';

  // Order types
  static const List<String> orderTypes = [
    'طباعة',
    'بريزنتيشن',
    'تصميم جرافيك',
    'ملازم ومذكرات',
    'كروت شخصية',
    'لوحات وبانرات',
    'أخرى',
  ];
}
