import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { requireCircleAccess, circleCol } from "./helpers";
import { makeCredential } from "./auth";

/** المسافة بالمتر بين نقطتين جغرافيتين — يقابل haversineDistanceMeters_ في Code.gs */
function haversineDistanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (v: number) => (v * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * يتأكد إن الموقع المُرسل داخل النطاق الجغرافي المسموح به للمجمع، لو الخاصية
 * مفعّلة في الإعدادات (geofenceEnabled). يقابل checkWorkLocation_ في Code.gs.
 */
function checkGeofence(
  settings: FirebaseFirestore.DocumentData,
  lat?: number,
  lng?: number
): { ok: boolean; message?: string } {
  if (!settings.geofenceEnabled) return { ok: true };
  const centerLat = Number(settings.circleLat);
  const centerLng = Number(settings.circleLng);
  const radius = Number(settings.geofenceRadiusMeters) || 0;
  if (!isFinite(centerLat) || !isFinite(centerLng) || radius <= 0) return { ok: true }; // إعدادات ناقصة — لا نمنع

  if (typeof lat !== "number" || typeof lng !== "number") {
    return { ok: false, message: "يجب تفعيل خدمة الموقع الجغرافي لتسجيل الحضور/الانصراف داخل موقع العمل فقط." };
  }
  const distance = haversineDistanceMeters(centerLat, centerLng, lat, lng);
  if (distance > radius) {
    return {
      ok: false,
      message: `أنت خارج نطاق موقع العمل المسموح به (المسافة الحالية: ${Math.round(distance)} متر، المسموح: ${radius} متر).`,
    };
  }
  return { ok: true };
}

/** يحسب دقائق التأخير وحالته مقارنة بوقت الحضور المستهدف (targetCheckInTime) */
function computeDelay(settings: FirebaseFirestore.DocumentData, now: Date): { delayMins: number; delayStatus: string } {
  const target = String(settings.targetCheckInTime || "").trim();
  const m = target.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return { delayMins: 0, delayStatus: "" };
  const targetMinutes = Number(m[1]) * 60 + Number(m[2]);
  const nowMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  const grace = Number(settings.graceMinutes) || 0;
  const diff = nowMinutes - targetMinutes;
  if (diff <= grace) return { delayMins: Math.max(0, diff), delayStatus: "في الوقت" };
  return { delayMins: diff, delayStatus: "متأخر" };
}

/** يحسب حالة الانصراف مقارنة بوقت الانصراف المستهدف (targetCheckOutTime) */
function computeEarlyStatus(settings: FirebaseFirestore.DocumentData, now: Date): string {
  const target = String(settings.targetCheckOutTime || "").trim();
  const m = target.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return "";
  const targetMinutes = Number(m[1]) * 60 + Number(m[2]);
  const nowMinutes = now.getUTCHours() * 60 + now.getUTCMinutes();
  return nowMinutes < targetMinutes ? "انصراف مبكر" : "في الوقت";
}

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

/** يقابل recordTeacherCheckIn في Code.gs — بما فيها الموقع الجغرافي والنطاق الجغرافي ودقائق التأخير */
export const recordTeacherCheckIn = functions.onCall(async (request) => {
  const { circleId, teacherId, teacherName, dateKey, dayName, lat, lng } = request.data as {
    circleId: string; teacherId: string; teacherName: string; dateKey: string; dayName: string;
    lat?: number; lng?: number;
  };
  requireCircleAccess(request, circleId);

  const circleSnap = await db.collection("circles").doc(circleId).get();
  const settings = circleSnap.data() || {};

  const geofence = checkGeofence(settings, lat, lng);
  if (!geofence.ok) {
    return { success: false, message: geofence.message };
  }

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();
  if (!existing.empty) {
    return { success: false, message: "تم تسجيل الحضور بالفعل اليوم." };
  }

  const now = new Date();
  const { delayMins, delayStatus } = computeDelay(settings, now);

  await col.add({
    dateKey,
    date: admin.firestore.FieldValue.serverTimestamp(),
    dayName,
    prayerTime: settings.prayerSlot || "",
    teacherName,
    isAbsent: false,
    checkIn: admin.firestore.FieldValue.serverTimestamp(),
    checkInLocation: typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null,
    checkOut: null,
    checkOutLocation: null,
    delayMins,
    delayStatus,
    earlyStatus: "",
    teacherId,
    username: request.auth?.token?.name || "",
  });

  return { success: true };
});

/** يقابل recordTeacherCheckOut في Code.gs — بما فيها الموقع الجغرافي والنطاق الجغرافي */
export const recordTeacherCheckOut = functions.onCall(async (request) => {
  const { circleId, teacherId, dateKey, lat, lng } = request.data as {
    circleId: string; teacherId: string; dateKey: string; lat?: number; lng?: number;
  };
  requireCircleAccess(request, circleId);

  const circleSnap = await db.collection("circles").doc(circleId).get();
  const settings = circleSnap.data() || {};

  const geofence = checkGeofence(settings, lat, lng);
  if (!geofence.ok) {
    return { success: false, message: geofence.message };
  }

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();
  if (existing.empty) {
    return { success: false, message: "لا يوجد تسجيل حضور لهذا اليوم بعد." };
  }

  const earlyStatus = computeEarlyStatus(settings, new Date());

  await existing.docs[0].ref.update({
    checkOut: admin.firestore.FieldValue.serverTimestamp(),
    checkOutLocation: typeof lat === "number" && typeof lng === "number" ? { lat, lng } : null,
    earlyStatus,
  });
  return { success: true };
});

/**
 * يقابل زر "الآن" في جدول تحضير المعلمين — يسمح لصاحب المجمع بتثبيت وقت
 * الحضور أو الانصراف الفعلي لأي معلم يدويًا (بدون تحقق من الموقع الجغرافي،
 * لأنها عملية إدارية من صاحب المجمع نفسه).
 */
export const adminStampTeacherAttendance = functions.onCall(async (request) => {
  const { circleId, teacherId, teacherName, dateKey, dayName, type } = request.data as {
    circleId: string; teacherId: string; teacherName: string; dateKey: string; dayName: string;
    type: "checkIn" | "checkOut";
  };
  requireCircleAccess(request, circleId);

  const circleSnap = await db.collection("circles").doc(circleId).get();
  const settings = circleSnap.data() || {};
  const now = new Date();

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();

  if (type === "checkIn") {
    const { delayMins, delayStatus } = computeDelay(settings, now);
    if (!existing.empty) {
      await existing.docs[0].ref.update({
        checkIn: admin.firestore.FieldValue.serverTimestamp(),
        isAbsent: false,
        delayMins,
        delayStatus,
      });
    } else {
      await col.add({
        dateKey,
        date: admin.firestore.FieldValue.serverTimestamp(),
        dayName,
        prayerTime: settings.prayerSlot || "",
        teacherName,
        isAbsent: false,
        checkIn: admin.firestore.FieldValue.serverTimestamp(),
        checkInLocation: null,
        checkOut: null,
        checkOutLocation: null,
        delayMins,
        delayStatus,
        earlyStatus: "",
        teacherId,
        username: "",
      });
    }
  } else {
    const earlyStatus = computeEarlyStatus(settings, now);
    if (!existing.empty) {
      await existing.docs[0].ref.update({
        checkOut: admin.firestore.FieldValue.serverTimestamp(),
        earlyStatus,
      });
    } else {
      return { success: false, message: "لا يوجد تسجيل حضور لهذا اليوم بعد — سجّل الحضور أولاً." };
    }
  }

  return { success: true };
});

/** زر "غياب" (مربع الاختيار) في جدول تحضير المعلمين — تسجيل/إلغاء غياب معلم يدويًا لليوم */
export const setTeacherAbsentToday = functions.onCall(async (request) => {
  const { circleId, teacherId, teacherName, dateKey, dayName, isAbsent } = request.data as {
    circleId: string; teacherId: string; teacherName: string; dateKey: string; dayName: string; isAbsent: boolean;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();

  if (!existing.empty) {
    await existing.docs[0].ref.update({ isAbsent });
  } else {
    await col.add({
      dateKey,
      date: admin.firestore.FieldValue.serverTimestamp(),
      dayName,
      prayerTime: "",
      teacherName,
      isAbsent,
      checkIn: null,
      checkInLocation: null,
      checkOut: null,
      checkOutLocation: null,
      delayMins: 0,
      delayStatus: "",
      earlyStatus: "",
      teacherId,
      username: "",
    });
  }
  return { success: true };
});

/** تقرير حضور المعلمين بفترة زمنية — أساس الإحصائيات، مسير الرواتب، وتصدير السجل الكامل */
export const getTeacherAttendanceReport = functions.onCall(async (request) => {
  const { circleId, fromDateKey, toDateKey } = request.data as {
    circleId: string; fromDateKey: string; toDateKey: string;
  };
  requireCircleAccess(request, circleId);

  let q: FirebaseFirestore.Query = circleCol(circleId, "teacherAttendance");
  if (fromDateKey) q = q.where("dateKey", ">=", fromDateKey);
  if (toDateKey) q = q.where("dateKey", "<=", toDateKey);

  const snap = await q.get();
  return { success: true, records: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/**
 * مسير الرواتب الشهري — يقابل بند "د. الإحصائيات ومسير الرواتب" في المواصفات.
 * لكل معلم: الحضور، التأخير، دقائق التأخير، خصم الغياب، خصم التأخير، المكافآت، الصافي.
 * قاعدة الحساب: خصم الغياب = (الراتب الأساسي / أيام العمل بالفترة) لكل يوم غياب.
 * خصم التأخير = (الراتب الأساسي / أيام العمل بالفترة / مدة الحلقة بالدقائق) × إجمالي دقائق التأخير.
 */
export const getMonthlyPayroll = functions.onCall(async (request) => {
  const { circleId, fromDateKey, toDateKey } = request.data as {
    circleId: string; fromDateKey: string; toDateKey: string;
  };
  requireCircleAccess(request, circleId);

  const [circleSnap, teachersSnap, attSnap] = await Promise.all([
    db.collection("circles").doc(circleId).get(),
    circleCol(circleId, "teachers").get(),
    (async () => {
      let q: FirebaseFirestore.Query = circleCol(circleId, "teacherAttendance");
      if (fromDateKey) q = q.where("dateKey", ">=", fromDateKey);
      if (toDateKey) q = q.where("dateKey", "<=", toDateKey);
      return q.get();
    })(),
  ]);

  const settings = circleSnap.data() || {};
  const workDays = Number(settings.workDays) || 26; // تقريبًا عدد أيام العمل بالشهر لو غير محدد
  const shiftMins = Number(settings.shiftDurationMins) || 60;

  const rows = teachersSnap.docs.map((tDoc) => {
    const t = tDoc.data();
    const salary = Number(t.salary) || 0;
    const bonus = Number(t.bonus) || 0;

    const records = attSnap.docs.map((d) => d.data()).filter((r) => r.teacherId === tDoc.id);
    const attendanceCount = records.filter((r) => !r.isAbsent && r.checkIn).length;
    const absentCount = records.filter((r) => r.isAbsent).length;
    const lateCount = records.filter((r) => r.delayStatus === "متأخر").length;
    const lateMinutesTotal = records.reduce((sum, r) => sum + (r.delayStatus === "متأخر" ? Number(r.delayMins) || 0 : 0), 0);

    const perDay = workDays > 0 ? salary / workDays : 0;
    const absenceDeduction = Math.round(perDay * absentCount);
    const lateDeduction = shiftMins > 0 ? Math.round((perDay / shiftMins) * lateMinutesTotal) : 0;
    const net = Math.max(0, salary - absenceDeduction - lateDeduction + bonus);

    return {
      teacherId: tDoc.id,
      teacherName: t.name || "",
      phone: t.phone || "",
      baseSalary: salary,
      attendanceCount,
      lateCount,
      lateMinutesTotal,
      absentCount,
      absenceDeduction,
      lateDeduction,
      bonus,
      net,
    };
  });

  return { success: true, rows, fromDateKey, toDateKey };
});

/**
 * زر "حفظ تسجيل اليوم في Google Sheets" — يكتب صف لكل معلم لليوم الحالي في
 * جدول بيانات Google Sheets يحدده صاحب المجمع في الإعدادات (googleSheetId).
 * يتطلب مشاركة الجدول (تحرير) مع حساب خدمة الدالة السحابية الافتراضي — انظر
 * docs/google-sheets-setup.md لخطوات التفعيل.
 */
export const saveTodayAttendanceToSheet = functions.onCall(async (request) => {
  const { circleId, dateKey } = request.data as { circleId: string; dateKey: string };
  requireCircleAccess(request, circleId);

  const circleSnap = await db.collection("circles").doc(circleId).get();
  const settings = circleSnap.data() || {};
  const sheetId = String(settings.googleSheetId || "").trim();
  if (!sheetId) {
    return { success: false, message: "لم يتم تحديد معرّف Google Sheet في إعدادات المجمع بعد." };
  }

  const attSnap = await circleCol(circleId, "teacherAttendance").where("dateKey", "==", dateKey).get();
  if (attSnap.empty) {
    return { success: false, message: "لا يوجد تسجيل حضور لهذا اليوم بعد." };
  }

  const rows = attSnap.docs.map((d) => {
    const r = d.data();
    const fmtTime = (ts: FirebaseFirestore.Timestamp | null) =>
      ts ? ts.toDate().toLocaleTimeString("ar-EG", { hour: "2-digit", minute: "2-digit" }) : "";
    return [
      dateKey,
      r.dayName || "",
      r.teacherName || "",
      r.isAbsent ? "غائب" : "حاضر",
      fmtTime(r.checkIn),
      r.delayStatus || "",
      String(r.delayMins ?? 0),
      fmtTime(r.checkOut),
      r.earlyStatus || "",
    ];
  });

  try {
    const { google } = await import("googleapis");
    const auth = new google.auth.GoogleAuth({ scopes: ["https://www.googleapis.com/auth/spreadsheets"] });
    const sheets = google.sheets({ version: "v4", auth });

    await sheets.spreadsheets.values.append({
      spreadsheetId: sheetId,
      range: "A1",
      valueInputOption: "USER_ENTERED",
      requestBody: { values: rows },
    });

    return { success: true, count: rows.length };
  } catch (e) {
    return {
      success: false,
      message:
        "تعذّرت الكتابة في Google Sheets. تأكد من مشاركة الجدول مع حساب الخدمة الخاص بالدالة السحابية بصلاحية تحرير، ومن تفعيل Google Sheets API للمشروع. تفاصيل: " +
        String(e),
    };
  }
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
