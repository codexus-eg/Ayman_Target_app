const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

const CHANNEL_ID = "high_importance_channel";

// 1. إرسال Push Notification عندما يتلقى أي مستخدم وثيقة إشعار جديدة
exports.sendNotificationPush = onDocumentCreated(
  "users/{userId}/notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const supportedTypes = ["order_assigned", "new_order"];
    if (!supportedTypes.includes(data.type)) return;

    const userId = event.params.userId;
    const userDoc = await getFirestore().collection("users").doc(userId).get();
    const token = userDoc.data()?.fcmToken;
    if (!token) return;

    const title = data.title || "إشعار جديد";
    const body = data.body || "";

    try {
      await getMessaging().send({
        token,
        notification: { title, body },
        data: {
          type: data.type || "new_order",
          orderId: data.orderId || "",
          notificationId: event.params.notificationId,
          title,
          body,
        },
        android: {
          priority: "high",
          notification: {
            channelId: CHANNEL_ID,
            priority: "high",
          },
        },
        apns: {
          headers: { "apns-priority": "10" },
          payload: { aps: { sound: "default" } },
        },
      });
    } catch (error) {
      if (
        error.code === "messaging/invalid-registration-token" ||
        error.code === "messaging/registration-token-not-registered"
      ) {
        await getFirestore()
          .collection("users")
          .doc(userId)
          .update({ fcmToken: null });
      }
    }
  }
);

// 2. إنشاء إشعارات تلقائية لجميع الموظفين بالفرع عند تسجيل أوردر جديد (سواء من العميل أو الموظف)
exports.onOrderCreated = onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const branch = data.branch;
    if (!branch) return;

    const clientName = data.clientName || "عميل";
    const creatorName = data.creatorName || "العميل";
    const orderType = data.orderType || "غير محدد";

    const title = "📦 أوردر جديد";
    const body = `${creatorName} أضاف أوردر جديد (${orderType}) للعميل "${clientName}" - فرع ${branch}`;

    const db = getFirestore();

    // جلب كل الموظفين في نفس الفرع
    const usersSnapshot = await db
      .collection("users")
      .where("branch", "==", branch)
      .get();

    const createdByUid = data.createdBy || ""; // إذا كان هناك معرف لمنشئ الأوردر من حسابات العملاء

    const promises = [];
    usersSnapshot.forEach((userDoc) => {
      // عدم إرسال إشعار للموظف الذي أنشأ الأوردر بنفسه
      if (userDoc.id === createdByUid || userDoc.data()?.name === creatorName) {
        return;
      }

      const notifRef = db
        .collection("users")
        .doc(userDoc.id)
        .collection("notifications")
        .doc();

      promises.push(
        notifRef.set({
          type: "new_order",
          title: title,
          body: body,
          orderId: event.params.orderId,
          clientName: clientName,
          creatorName: creatorName,
          orderType: orderType,
          branch: branch,
          read: false,
          createdAt: new Date(), // طابع زمني للسيرفر
        })
      );
    });

    if (promises.length > 0) {
      await Promise.all(promises);
    }
  }
);
