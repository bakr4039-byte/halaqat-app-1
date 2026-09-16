import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { requireCircleAccess, circleCol } from "./helpers";
import { notifyGuardiansOfAbsence } from "./whatsapp";

/** يقابل getStudents في Code.gs */
export const getStudents = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "students").get();
  return { success: true, students: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل saveStudents في Code.gs */
export const saveStudents = functions.onCall(async (request) => {
  const { circleId, students } = request.data as {
    circleId: string;
    students: Array<Record<string, unknown> & { id?: string }>;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "students");
  const existingSnap = await col.get();
  const incomingIds = new Set((students || []).filter((s) => s.id).map((s) => s.id));

  const batch = db.batch();
  existingSnap.forEach((doc) => {
    if (!incomingIds.has(doc.id)) batch.delete(doc.ref);
  });
  (students || []).forEach((s) => {
    const { id, ...rest } = s;
    const ref = id ? col.doc(id) : col.doc();
    batch.set(ref, rest, { merge: true });
  });
  await batch.commit();
  return { success: true };
});

/** يقابل getStudentAttendanceForDate في Code.gs */
export const getStudentAttendanceForDate = functions.onCall(async (request) => {
  const { circleId, dateKey } = request.data as { circleId: string; dateKey: string };
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "studentAttendance").where("dateKey", "==", dateKey).get();
  return { success: true, records: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل saveStudentAttendanceDay في Code.gs — بما فيها استدعاء إشعار أولياء الأمور بالغياب
 * الحالات المدعومة: حاضر present / غائب absent / متأخر late / مستأذن excused / إجازة leave
 * ("بدون تسجيل" حالة ضمنية لأي طالب من غير سجل — لا تُخزَّن). */
export const saveStudentAttendanceDay = functions.onCall(async (request) => {
  const { circleId, dateKey, records } = request.data as {
    circleId: string;
    dateKey: string;
    records: Array<{ studentId: string; studentName: string; teacherId: string; status: string; notes?: string }>;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "studentAttendance");
  // نفس منطق Code.gs: نحذف سجلات نفس اليوم القديمة (لو موجودة) قبل إضافة الجديدة، لمنع التكرار
  const existing = await col.where("dateKey", "==", dateKey).get();
  const batch = db.batch();
  existing.forEach((doc) => batch.delete(doc.ref));

  (records || []).forEach((r) => {
    const ref = col.doc();
    batch.set(ref, {
      dateKey,
      date: admin.firestore.Timestamp.fromDate(new Date(dateKey)),
      studentId: r.studentId,
      studentName: r.studentName,
      teacherId: r.teacherId || "",
      status: r.status,
      notes: r.notes || "",
    });
  });
  await batch.commit();

  await notifyGuardiansOfAbsence(circleId, records || []);

  return { success: true };
});

/** يقابل saveSingleStudentAttendance في Code.gs — تعديل حالة طالب واحد فقط */
export const saveSingleStudentAttendance = functions.onCall(async (request) => {
  const { circleId, dateKey, studentId, studentName, teacherId, status } = request.data as {
    circleId: string; dateKey: string; studentId: string; studentName: string; teacherId: string; status: string;
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "studentAttendance");
  const existing = await col.where("dateKey", "==", dateKey).where("studentId", "==", studentId).limit(1).get();

  if (!existing.empty) {
    await existing.docs[0].ref.update({ status, teacherId: teacherId || "" });
  } else {
    await col.add({
      dateKey,
      date: admin.firestore.Timestamp.fromDate(new Date(dateKey)),
      studentId, studentName, teacherId: teacherId || "", status, notes: "",
    });
  }
  return { success: true };
});

/** يقابل getStudentAttendanceReport في Code.gs */
export const getStudentAttendanceReport = functions.onCall(async (request) => {
  const { circleId, fromDateKey, toDateKey } = request.data as { circleId: string; fromDateKey: string; toDateKey: string };
  requireCircleAccess(request, circleId);

  let q: FirebaseFirestore.Query = circleCol(circleId, "studentAttendance");
  if (fromDateKey) q = q.where("dateKey", ">=", fromDateKey);
  if (toDateKey) q = q.where("dateKey", "<=", toDateKey);

  const snap = await q.get();
  return { success: true, records: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل getAttendanceTrend في Code.gs — اتجاه نسبة الحضور أسبوعيًا (آخر 12 أسبوع) */
export const getAttendanceTrend = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);

  const snap = await circleCol(circleId, "studentAttendance").get();
  const buckets: Record<string, { present: number; total: number }> = {};

  snap.forEach((doc) => {
    const r = doc.data();
    const d = new Date(r.dateKey);
    if (isNaN(d.getTime())) return;
    const weekStart = new Date(d);
    weekStart.setDate(d.getDate() - d.getDay());
    const key = weekStart.toISOString().slice(0, 10);
    if (!buckets[key]) buckets[key] = { present: 0, total: 0 };
    buckets[key].total++;
    if (r.status === "present") buckets[key].present++;
  });

  const weeks = Object.keys(buckets)
    .sort()
    .slice(-12)
    .map((k) => {
      const b = buckets[k];
      return {
        weekStart: k,
        attendanceRate: b.total > 0 ? Math.round((b.present / b.total) * 100) : 0,
        present: b.present,
        total: b.total,
      };
    });

  return { success: true, weeks };
});
