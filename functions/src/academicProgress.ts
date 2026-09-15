import * as functions from "firebase-functions/v2/https";
import { requireCircleAccess, circleCol } from "./helpers";

/** يقابل getAcademicProgressData في Code.gs */
export const getAcademicProgressData = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "academicProgress").get();
  return { success: true, records: snap.docs.map((d) => ({ studentId: d.id, ...d.data() })) };
});

/** يقابل saveAcademicProgressValue في Code.gs — تحديث قيمة واحدة (حفظ/مراجعة صغرى/مراجعة كبرى) لطالب */
export const saveAcademicProgressValue = functions.onCall(async (request) => {
  const { circleId, studentId, studentName, circleName, teacherId, field, value } = request.data as {
    circleId: string; studentId: string; studentName: string; circleName?: string; teacherId?: string;
    field: "hifz" | "minorReview" | "majorReview"; value: number;
  };
  requireCircleAccess(request, circleId);

  if (!["hifz", "minorReview", "majorReview"].includes(field)) {
    throw new functions.HttpsError("invalid-argument", "حقل غير صالح.");
  }

  const ref = circleCol(circleId, "academicProgress").doc(studentId);
  await ref.set(
    {
      studentName,
      circle: circleName || "",
      teacherId: teacherId || "",
      [field]: Number(value) || 0,
    },
    { merge: true }
  );
  return { success: true };
});
