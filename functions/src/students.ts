import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { requireCircleAccess, requireManagerAccess, circleCol, accessibleStudents, requireStudentAccess, validDateKey } from "./helpers";
import { notifyGuardiansOfAbsence } from "./whatsapp";

/** يقابل getStudents في Code.gs */
export const getStudents = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);
  const students = await accessibleStudents(request, circleId);
  return { success: true, students: students.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل saveStudents في Code.gs */
export const saveStudents = functions.onCall(async (request) => {
  const { circleId, students } = request.data as {
    circleId: string;
    students: Array<Record<string, unknown> & { id?: string }>;
  };
  requireManagerAccess(request, circleId);

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
  const allowed = new Set((await accessibleStudents(request, circleId)).map((d) => d.id));
  return { success: true, records: snap.docs.filter((d) => allowed.has(d.data().studentId)).map((d) => ({ id: d.id, ...d.data() })) };
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

  validDateKey(dateKey);
  if (!Array.isArray(records) || records.length > 400) throw new functions.HttpsError("invalid-argument", "قائمة رصد غير صالحة أو كبيرة.");
  const allowed = new Map((await accessibleStudents(request, circleId)).map((d) => [d.id, d.data()]));
  const seen = new Set<string>();
  const prepared = records.map((r) => {
    const student = allowed.get(r.studentId);
    if (!student || seen.has(r.studentId) || !["present","absent","late","excused","leave"].includes(r.status)) {
      throw new functions.HttpsError("permission-denied", "طالب مكرر أو خارج حلقاتك أو حالة حضور غير صحيحة.");
    }
    seen.add(r.studentId);
    return {...r, studentName: String(student.name || ""), teacherId: String(student.teacherId || request.auth?.token.teacherId || "")};
  });
  const col = circleCol(circleId, "studentAttendance");
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(col.where("dateKey", "==", dateKey));
    const docId = (sid: string) => dateKey + "_" + encodeURIComponent(sid);
    const legacy = existing.docs.filter((d) => seen.has(d.data().studentId) && d.id !== docId(d.data().studentId));
    if (legacy.length + prepared.length > 450) throw new functions.HttpsError("invalid-argument", "قسّم الرصد إلى دفعات أصغر.");
    legacy.forEach((d) => tx.delete(d.ref));
    prepared.forEach((r) => tx.set(col.doc(docId(r.studentId)), {
      dateKey, date: admin.firestore.Timestamp.fromDate(new Date(dateKey)),
      studentId: r.studentId, studentName: r.studentName, teacherId: r.teacherId,
      status: r.status, notes: r.notes || "", updatedBy: request.auth!.uid,
    }, {merge:true}));
  });
  // Attendance is already committed; a notification-provider outage must not
  // encourage the client to repeat a successful write.
  try { await notifyGuardiansOfAbsence(circleId, prepared); } catch { /* retry notifications separately */ }

  return { success: true };
});

/** يقابل saveSingleStudentAttendance في Code.gs — تعديل حالة طالب واحد فقط */
export const saveSingleStudentAttendance = functions.onCall(async (request) => {
  const { circleId, dateKey, studentId, studentName, teacherId, status } = request.data as {
    circleId: string; dateKey: string; studentId: string; studentName: string; teacherId: string; status: string;
  };
  requireCircleAccess(request, circleId);

  validDateKey(dateKey);
  const student = await requireStudentAccess(request, circleId, studentId);
  if (!["present","absent","late","excused","leave"].includes(status)) throw new functions.HttpsError("invalid-argument", "حالة غير صحيحة.");
  const col = circleCol(circleId, "studentAttendance");
  const id = dateKey + "_" + encodeURIComponent(studentId);
  await db.runTransaction(async (tx) => {
    const existing = await tx.get(col.where("dateKey", "==", dateKey).where("studentId", "==", studentId));
    existing.docs.filter((d) => d.id !== id).forEach((d) => tx.delete(d.ref));
    tx.set(col.doc(id), {dateKey, date:admin.firestore.Timestamp.fromDate(new Date(dateKey)), studentId,
      studentName:String(student.data().name || studentName), teacherId:String(student.data().teacherId || request.auth?.token.teacherId || teacherId || ""),status}, {merge:true});
  });
  return {success:true};
});

/** يقابل getStudentAttendanceReport في Code.gs */
export const getStudentAttendanceReport = functions.onCall(async (request) => {
  const { circleId, fromDateKey, toDateKey } = request.data as { circleId: string; fromDateKey: string; toDateKey: string };
  requireCircleAccess(request, circleId);

  let q: FirebaseFirestore.Query = circleCol(circleId, "studentAttendance");
  if (fromDateKey) q = q.where("dateKey", ">=", fromDateKey);
  if (toDateKey) q = q.where("dateKey", "<=", toDateKey);

  const snap = await q.get();
  const allowed = new Set((await accessibleStudents(request, circleId)).map((d) => d.id));
  return { success: true, records: snap.docs.filter((d) => allowed.has(d.data().studentId)).map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل getAttendanceTrend في Code.gs — اتجاه نسبة الحضور أسبوعيًا (آخر 12 أسبوع) */
export const getAttendanceTrend = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);

  const snap = await circleCol(circleId, "studentAttendance").get();
  const allowed = new Set((await accessibleStudents(request, circleId)).map((d) => d.id));
  const buckets: Record<string, { present: number; total: number }> = {};

  snap.forEach((doc) => {
    const r = doc.data();
    if (!allowed.has(r.studentId)) return;
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

