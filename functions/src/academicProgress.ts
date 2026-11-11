import * as functions from "firebase-functions/v2/https";
import { requireCircleAccess, circleCol, accessibleStudents, requireStudentAccess } from "./helpers";

/** يقابل getAcademicProgressData في Code.gs */
export const getAcademicProgressData = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "academicProgress").get();
  const allowed = new Set((await accessibleStudents(request, circleId)).map((d) => d.id));
  return { success: true, records: snap.docs.filter((d) => allowed.has(d.id)).map((d) => ({ studentId: d.id, ...d.data() })) };
});

/** يقابل saveAcademicProgressValue في Code.gs — تحديث قيمة واحدة (حفظ/مراجعة صغرى/مراجعة كبرى) لطالب */
export const saveAcademicProgressValue = functions.onCall(async (request) => {
  const { circleId, studentId, studentName, circleName, teacherId, field, value } = request.data as {
    circleId: string; studentId: string; studentName: string; circleName?: string; teacherId?: string;
    field: "hifz" | "minorReview" | "majorReview"; value: number;
  };
  requireCircleAccess(request, circleId);

  const student = await requireStudentAccess(request, circleId, studentId);
  const amount = Number(value);
  if (!Number.isFinite(amount) || amount < 0) {
    throw new functions.HttpsError("invalid-argument", "القيمة يجب أن تكون رقمًا غير سالب.");
  }

  if (!["hifz", "minorReview", "majorReview"].includes(field)) {
    throw new functions.HttpsError("invalid-argument", "حقل غير صالح.");
  }

  const ref = circleCol(circleId, "academicProgress").doc(studentId);
  await ref.set(
    {
      studentName: student.data().name || studentName,
      circle: student.data().subCircle || circleName || "",
      teacherId: student.data().teacherId || request.auth?.token.teacherId || teacherId || "",
      [field]: amount,
    },
    { merge: true }
  );
  return { success: true };
});

