import * as functions from "firebase-functions/v2/https";
import { admin } from "./admin";

export function requireManagerAccess(request: functions.CallableRequest, circleId: string) {
  requireCircleAccess(request, circleId);
  if (request.auth?.token.role === "teacher") {
    throw new functions.HttpsError("permission-denied", "هذا الإجراء لمدير المدرسة فقط.");
  }
}

export function requireTeacherSelf(request: functions.CallableRequest, teacherId: string) {
  if (request.auth?.token.role === "teacher" &&
      (!teacherId || request.auth.token.teacherId !== teacherId)) {
    throw new functions.HttpsError("permission-denied", "يمكنك تعديل حضورك فقط.");
  }
}

export async function accessibleStudents(request: functions.CallableRequest, circleId: string) {
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "students").get();
  const role = request.auth?.token.role;
  if (role !== "teacher") return snap.docs;
  const teacherId = String(request.auth?.token.teacherId || "");
  if (!teacherId) throw new functions.HttpsError("permission-denied", "حساب المعلم غير مربوط بحلقة.");
  const teacher = await circleCol(circleId, "teachers").doc(teacherId).get();
  const subCircle = teacher.data()?.subCircle;
  return snap.docs.filter((doc) => {
    const student = doc.data();
    return student.teacherId === teacherId ||
      (!student.teacherId && subCircle && student.subCircle === subCircle);
  });
}

export async function requireStudentAccess(request: functions.CallableRequest, circleId: string, studentId: string) {
  if (typeof studentId !== "string" || !studentId || studentId.includes("/")) {
    throw new functions.HttpsError("invalid-argument", "معرف الطالب غير صالح.");
  }
  const student = (await accessibleStudents(request, circleId)).find((doc) => doc.id === studentId);
  if (!student) throw new functions.HttpsError("permission-denied", "الطالب خارج حلقات هذا الحساب.");
  return student;
}

export function validDateKey(dateKey: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateKey || "") ||
      !Number.isFinite(Date.parse(dateKey)) || new Date(dateKey).toISOString().slice(0, 10) !== dateKey) {
    throw new functions.HttpsError("invalid-argument", "تاريخ غير صحيح.");
  }
}

/** يتأكد إن المستخدم المسجّل دخول مصرّح له بالتعامل مع مجمع معيّن */
export function requireCircleAccess(request: functions.CallableRequest, circleId: string) {
  const token = request.auth?.token;
  if (!token) throw new functions.HttpsError("unauthenticated", "الرجاء تسجيل الدخول.");
  const role = token.role as string;
  if (role === "superAdmin") return;
  if ((role === "owner" || role === "teacher") && token.circleId === circleId) return;
  throw new functions.HttpsError("permission-denied", "غير مصرح لك بالوصول لهذا المجمع.");
}

export function dateKeyOf(d: Date): string {
  return d.toISOString().slice(0, 10); // yyyy-MM-dd — يفترض التعامل بتوقيت الخادم UTC ثم التحويل عند العرض في العميل حسب Asia/Riyadh
}

export function circleCol(circleId: string, sub: string) {
  return admin.firestore().collection("circles").doc(circleId).collection(sub);
}

