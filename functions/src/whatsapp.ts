import { db } from "./admin";

// ============================================================
// إرسال واتساب — يقابل sendWhatsAppMessage_ و notifyGuardiansOfAbsence_ في Code.gs
//
// ملاحظة أمنية: accessToken لازم يتخزن في Secret Manager (secret باسم
// مثلاً WHATSAPP_ACCESS_TOKEN_<circleId>) مش كحقل عادي في مستند
// Firestore يقدر أي حد عنده صلاحية owner يشوفه. الكود هنا مكتوب بافتراض
// إنك هتربطه بـ Secret Manager وقت الإعداد الفعلي على Firebase.
// ============================================================

interface WhatsAppSendResult {
  success: boolean;
  skipped?: boolean;
  code?: number;
  error?: string;
}

export async function sendWhatsAppMessage(
  circleId: string,
  toPhone: string,
  message: string
): Promise<WhatsAppSendResult> {
  try {
    if (!toPhone) return { success: false, skipped: true };

    const circleSnap = await db.collection("circles").doc(circleId).get();
    const settings = circleSnap.data() || {};
    const phoneNumberId = String(settings.whatsappPhoneNumberId || "").trim();
    // TODO: استبدال السطر التالي بقراءة فعلية من Secret Manager عند النشر
    const accessToken = String(process.env[`WHATSAPP_TOKEN_${circleId}`] || "").trim();

    if (!phoneNumberId || !accessToken) return { success: false, skipped: true };

    const cleanPhone = String(toPhone).replace(/[^0-9]/g, "");
    if (!cleanPhone) return { success: false, skipped: true };

    const resp = await fetch(`https://graph.facebook.com/v20.0/${encodeURIComponent(phoneNumberId)}/messages`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to: cleanPhone,
        type: "text",
        text: { body: message },
      }),
    });

    return { success: resp.ok, code: resp.status };
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

/** يقابل notifyGuardiansOfAbsence_ في Code.gs */
export async function notifyGuardiansOfAbsence(
  circleId: string,
  records: Array<{ studentId: string; studentName: string; status: string }>
) {
  try {
    const circleSnap = await db.collection("circles").doc(circleId).get();
    const settings = circleSnap.data() || {};
    if (String(settings.parentAbsenceNotifyEnabled).toLowerCase() !== "true" && settings.parentAbsenceNotifyEnabled !== true) {
      return;
    }

    const absentRecords = (records || []).filter((r) => r.status === "absent");
    if (!absentRecords.length) return;

    const studentsSnap = await db.collection("circles").doc(circleId).collection("students").get();
    const guardianMap: Record<string, string> = {};
    studentsSnap.forEach((doc) => {
      guardianMap[doc.id] = String(doc.data().guardianPhone || "");
    });

    await Promise.all(
      absentRecords.map(async (r) => {
        const phone = guardianMap[r.studentId];
        if (!phone) return;
        await sendWhatsAppMessage(
          circleId,
          phone,
          `نود إشعاركم بأن الطالب/ة ${r.studentName || ""} كان غائبًا اليوم عن حلقة تحفيظ القرآن.`
        );
      })
    );
  } catch {
    // تجاهل — نفس سلوك Code.gs الحالي (لا نفشل حفظ الحضور بسبب فشل إشعار واتساب)
  }
}
