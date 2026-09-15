import * as functions from "firebase-functions/v2/https";
import { admin } from "./admin";

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
