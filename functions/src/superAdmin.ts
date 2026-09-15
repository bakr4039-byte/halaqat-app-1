import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { makeCredential } from "./auth";

function requireSuperAdmin(request: functions.CallableRequest) {
  const role = request.auth?.token?.role;
  if (role !== "superAdmin") {
    throw new functions.HttpsError("permission-denied", "غير مصرح لك بهذا الإجراء.");
  }
}

/** يقابل superAdminCreateCircle في Code.gs */
export const superAdminCreateCircle = functions.onCall(async (request) => {
  requireSuperAdmin(request);
  const { circleName, ownerUsername, password, logoUrl, themeColor } = request.data as {
    circleName: string;
    ownerUsername: string;
    password: string;
    logoUrl?: string;
    themeColor?: string;
  };

  const uname = String(ownerUsername || "").trim().toLowerCase();
  if (!circleName || !uname || !password) {
    throw new functions.HttpsError("invalid-argument", "الرجاء إدخال اسم المجمع واسم المستخدم وكلمة المرور.");
  }

  const existing = await db.collection("credentials").doc(uname).get();
  if (existing.exists) {
    throw new functions.HttpsError("already-exists", "اسم المستخدم مستخدم بالفعل.");
  }

  const circleRef = db.collection("circles").doc();
  await circleRef.set({
    circleName,
    ownerUsername: uname,
    logoUrl: logoUrl || "",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    themeColor: themeColor || "green",
    workDays: 5,
    prayerSlot: "Asr",
    shiftDurationMins: 120,
    prayerCity: "Riyadh",
    circlePhone: "",
    graceMinutes: 0,
    autoWhatsapp: false,
    prayerReminderEnabled: true,
    reminderMinutesBefore: 15,
  });

  const { salt, hash } = makeCredential(password);
  await db.collection("credentials").doc(uname).set({
    username: uname,
    salt,
    hash,
    role: "owner",
    circleId: circleRef.id,
  });

  return { success: true, circleId: circleRef.id };
});

/** يقابل superAdminGetOverview + computeCircleActivityStats_ في Code.gs */
export const superAdminGetOverview = functions.onCall(async (request) => {
  requireSuperAdmin(request);

  const circlesSnap = await db.collection("circles").get();
  let totalTeachers = 0;
  let totalStudents = 0;

  const circles = await Promise.all(
    circlesSnap.docs.map(async (doc) => {
      const data = doc.data();
      const [teachersSnap, studentsSnap, stats] = await Promise.all([
        db.collection("circles").doc(doc.id).collection("teachers").count().get(),
        db.collection("circles").doc(doc.id).collection("students").count().get(),
        computeCircleActivityStats(doc.id),
      ]);
      const teachersCount = teachersSnap.data().count;
      const studentsCount = studentsSnap.data().count;
      totalTeachers += teachersCount;
      totalStudents += studentsCount;
      return {
        circleId: doc.id,
        username: data.ownerUsername,
        circleName: data.circleName,
        createdAt: data.createdAt,
        teachersCount,
        studentsCount,
        lastActivity: stats.lastActivity,
        attendanceRate: stats.attendanceRate,
      };
    })
  );

  return {
    success: true,
    circlesCount: circles.length,
    teachersCount: totalTeachers,
    studentsCount: totalStudents,
    circles,
  };
});

/** يقابل computeCircleActivityStats_ في Code.gs — آخر نشاط ونسبة حضور آخر 30 يوم */
async function computeCircleActivityStats(circleId: string) {
  let lastActivity: string | null = null;
  let attendanceRate: number | null = null;
  try {
    const monthAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);
    const recentSnap = await db
      .collection("circles")
      .doc(circleId)
      .collection("studentAttendance")
      .where("date", ">=", monthAgo)
      .get();

    let present = 0;
    let total = 0;
    let lastDate: FirebaseFirestore.Timestamp | null = null;
    recentSnap.forEach((doc) => {
      const r = doc.data();
      total++;
      if (r.status === "present") present++;
      if (!lastDate || r.date.toMillis() > lastDate.toMillis()) lastDate = r.date;
    });
    if (lastDate) lastActivity = (lastDate as FirebaseFirestore.Timestamp).toDate().toISOString().slice(0, 10);
    if (total > 0) attendanceRate = Math.round((present / total) * 100);
  } catch {
    // تجاهل خطأ مجمع واحد فقط
  }
  return { lastActivity, attendanceRate };
}

/** يقابل superAdminUpdateCircle في Code.gs */
export const superAdminUpdateCircle = functions.onCall(async (request) => {
  requireSuperAdmin(request);
  const { circleId, updates } = request.data as { circleId: string; updates: Record<string, unknown> };
  if (!circleId) throw new functions.HttpsError("invalid-argument", "circleId مطلوب.");

  // اسم المستخدم لا يُعدَّل من هنا مباشرة لأنه مفتاح مجموعة credentials —
  // من يحتاج تغيير اسم المستخدم يحتاج Cloud Function منفصلة تنقل المستند.
  const allowed = [
    "circleName", "logoUrl", "themeColor", "workDays", "prayerSlot",
    "shiftDurationMins", "prayerCity", "circlePhone", "graceMinutes",
    "autoWhatsapp", "prayerReminderEnabled", "reminderMinutesBefore",
    "whatsappPhoneNumberId", "teacherReminderEnabled", "teacherReminderTime",
    "parentWeeklySummaryEnabled", "parentAbsenceNotifyEnabled", "reportEmail",
  ];
  const safeUpdates: Record<string, unknown> = {};
  for (const key of allowed) {
    if (updates && key in updates) safeUpdates[key] = updates[key];
  }

  await db.collection("circles").doc(circleId).update(safeUpdates);
  return { success: true };
});

/** يقابل superAdminDeleteCircle في Code.gs */
export const superAdminDeleteCircle = functions.onCall(async (request) => {
  requireSuperAdmin(request);
  const { circleId } = request.data as { circleId: string };
  if (!circleId) throw new functions.HttpsError("invalid-argument", "circleId مطلوب.");

  const circleRef = db.collection("circles").doc(circleId);
  const circleSnap = await circleRef.get();
  if (!circleSnap.exists) throw new functions.HttpsError("not-found", "المجمع غير موجود.");

  // حذف بيانات الاعتماد المرتبطة بصاحب المجمع
  const credsSnap = await db.collection("credentials").where("circleId", "==", circleId).get();
  const batch = db.batch();
  credsSnap.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();

  // ملاحظة: حذف كل المجموعات الفرعية (طلاب/حضور/...) يحتاج دالة recursive delete
  // (متوفرة كـ firebase-tools API) — تُضاف هنا وقت التنفيذ الفعلي لتفادي حذف جزئي صامت.
  await circleRef.delete();
  return { success: true };
});
