import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { requireCircleAccess, circleCol } from "./helpers";

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

/** يقابل recordTeacherCheckIn في Code.gs */
export const recordTeacherCheckIn = functions.onCall(async (request) => {
  const { circleId, teacherId, teacherName, dateKey, dayName } = request.data as {
    circleId: string; teacherId: string; teacherName: string; dateKey: string; dayName: string;
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
    checkOut: null,
    delayMins: 0,
    delayStatus: "",
    earlyStatus: "",
    teacherId,
    username: request.auth?.token?.name || "",
  });

  return { success: true };
});

/** يقابل recordTeacherCheckOut في Code.gs */
export const recordTeacherCheckOut = functions.onCall(async (request) => {
  const { circleId, teacherId, dateKey } = request.data as {
    circleId: string; teacherId: string; dateKey: string;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "teacherAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("teacherId", "==", teacherId).limit(1).get();
  if (existing.empty) {
    return { success: false, message: "لا يوجد تسجيل حضور لهذا اليوم بعد." };
  }

  await existing.docs[0].ref.update({ checkOut: admin.firestore.FieldValue.serverTimestamp() });
  return { success: true };
});

/** يقابل saveTeachersAndSettings في Code.gs */
export const saveTeachersAndSettings = functions.onCall(async (request) => {
  const { circleId, teachers, settings } = request.data as {
    circleId: string;
    teachers: Array<{ id?: string; name: string; salary: number; phone: string; bonus: number; subCircle: string; username: string }>;
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

  (teachers || []).forEach((t) => {
    const ref = t.id ? teachersCol.doc(t.id) : teachersCol.doc();
    batch.set(ref, {
      name: t.name, salary: t.salary || 0, phone: t.phone || "",
      bonus: t.bonus || 0, subCircle: t.subCircle || "", username: t.username || "",
    }, { merge: true });
  });

  if (settings) {
    batch.set(db.collection("circles").doc(circleId), settings, { merge: true });
  }

  await batch.commit();
  return { success: true };
});
