import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { requireCircleAccess, circleCol } from "./helpers";
import { makeCredential } from "./auth";

/** يقابل getInitialData في Code.gs — بيانات المعلمين + تحضير اليوم + الإعدادات */
export const getInitialData = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);

  const [circleSnap, teachersSnap] = await Promise.all([
    db.collection("circles").doc(circleId).get(),
    circleCol(circleId, "teachers").get(),
  ]);

  if (!circleSnap.exists) throw new functions.HttpsError("not-found", "المجمع غير موجود.");

  const teachers = teachersSnap.docs.map((d) => ({ id: d.id, ...d.data() }));

  return {
    success: true,
    settings: circleSnap.data(),
    teachers,
  };
});

/** يقابل recordTeacherCheckIn في Code.gs — بما فيها الموقع الجغرافي وقت التحضير */
export const recordTeacherCheckIn = functions.onCall(async (request) => {
  const { circleId, teacherId, teacherName, dateKey, dayName, lat, lng } = request.data as {
    circleId: string; teacherId: string; teacherName: string; dateKey: string; dayName: string;
    lat?: number; lng?: number;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();
  if (!existing.empty) {
    return { success: false, message: "تم تسجيل الحضور بالفعل اليوم." };
  }

  await col.add({
    dateKey,
    date: admin.firestore.FieldValue.serverTimestamp(),
    dayName,
    prayerTime: "",
    teacherName,
    isAbsent: false,
    checkIn: admin.firestore.FieldValue.serverTimestamp(),
    checkInLocation: typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null,
    checkOut: null,
    checkOutLocation: null,
    delayMins: 0,
    delayStatus: "",
    earlyStatus: "",
    teacherId,
    username: request.auth?.token?.name || "",
  });

  return { success: true };
});

/** يقابل recordTeacherCheckOut في Code.gs — بما فيها الموقع الجغرافي وقت الانصراف */
export const recordTeacherCheckOut = functions.onCall(async (request) => {
  const { circleId, teacherId, dateKey, lat, lng } = request.data as {
    circleId: string; teacherId: string; dateKey: string; lat?: number; lng?: number;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();
  if (existing.empty) {
    return { success: false, message: "لا يوجد تسجيل حضور لهذا اليوم بعد." };
  }

  await existing.docs[0].ref.update({
    checkOut: admin.firestore.FieldValue.serverTimestamp(),
    checkOutLocation: typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null,
  });
  return { success: true };
});

/**
 * يقابل saveTeachersAndSettings في Code.gs — وبيتكفّل كمان بإنشاء/تحديث
 * بيانات دخول المعلم في مجموعة "credentials" (كانت ناقصة تمامًا قبل كده،
 * فأي معلم يتضاف من شاشة الإدارة كان يتسجّل في teachers/ لكن من غير أي
 * حساب دخول فعلي — يعني ميقدرش يسجّل دخول أبدًا).
 */
export const saveTeachersAndSettings = functions.onCall(async (request) => {
  const { circleId, teachers, settings } = request.data as {
    circleId: string;
    teachers: Array<{
      id?: string; name: string; salary: number; phone: string; bonus: number;
      subCircle: string; username: string; password?: string;
    }>;
    settings: Record<string, unknown>;
  };
  requireCircleAccess(request, circleId);

  const batch = db.batch();
  const teachersCol = circleCol(circleId, "teachers");

  const existingSnap = await teachersCol.get();
  const incomingIds = new Set((teachers || []).filter((t) => t.id).map((t) => t.id));
  existingSnap.forEach((doc) => {
    if (!incomingIds.has(doc.id)) batch.delete(doc.ref);
  });

  const credentialWrites: Array<{ uname: string; data: Record<string, unknown> }> = [];

  (teachers || []).forEach((t) => {
    const ref = t.id ? teachersCol.doc(t.id) : teachersCol.doc();
    batch.set(ref, {
      name: t.name, salary: t.salary || 0, phone: t.phone || "",
      bonus: t.bonus || 0, subCircle: t.subCircle || "", username: t.username || "",
    }, { merge: true });

    // لو صاحب المجمع كتب اسم مستخدم + كلمة مرور للمعلم، ننشئ/نحدّث حساب
    // دخوله. لو سايب كلمة المرور فاضية (تعديل معلم موجود بدون تغيير كلمة
    // مروره)، نسيبها زي ما هي من غير أي تغيير.
    const uname = String(t.username || "").trim().toLowerCase();
    if (uname && t.password) {
      const { salt, hash } = makeCredential(t.password);
      credentialWrites.push({
        uname,
        data: { username: uname, salt, hash, role: "teacher", circleId, teacherId: ref.id },
      });
    }
  });

  if (settings) {
    batch.set(db.collection("circles").doc(circleId), settings, { merge: true });
  }

  await batch.commit();

  // نكتب بيانات الدخول بعد الـ batch (بعد ما نتأكد إن أي اسم مستخدم
  // موجود مسبقًا يخص نفس المجمع، عشان محدش ياخد حساب معلم في مجمع تاني)
  const skippedUsernames: string[] = [];
  for (const cw of credentialWrites) {
    const credRef = db.collection("credentials").doc(cw.uname);
    const existing = await credRef.get();
    const existingCircleId = existing.exists ? (existing.data()?.circleId as string | undefined) : undefined;
    if (existing.exists && existingCircleId && existingCircleId !== circleId) {
      skippedUsernames.push(cw.uname);
      continue;
    }
    await credRef.set(cw.data, { merge: true });
  }

  return { success: true, skippedUsernames };
});
