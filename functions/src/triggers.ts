import { onSchedule } from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import { db, admin } from "./admin";
import { sendWhatsAppMessage } from "./whatsapp";

// ============================================================
// المهام المجدولة — تقابل المشغّلات الزمنية (Triggers) في Code.gs:
// autoAbsentSweep, remindTeachersNotCheckedIn, weeklyBackupAllComplexes,
// sendWeeklyParentSummaries, sendMonthlyReportsToComplexOwners.
//
// في Apps Script كانت لازم تتفعّل يدويًا بتشغيل setupXXX_ONETIME() مرة
// واحدة. هنا الجدولة بتتحدد في الكود نفسه (onSchedule) ولما تعمل
// `firebase deploy --only functions` بتتسجل تلقائيًا في Cloud Scheduler
// — مفيش خطوة يدوية منفصلة، بس تقدر توقفها لاحقًا من Cloud Scheduler
// أو Firebase Console بدل حذف الكود.
// ============================================================

function todayKey(): string {
  return new Date().toISOString().slice(0, 10);
}

/** يقابل autoAbsentSweep في Code.gs — تسجيل غياب تلقائي للمعلمين بعد نهاية الوردية */
export const autoAbsentSweep = onSchedule("every 10 minutes", async () => {
  const circlesSnap = await db.collection("circles").get();
  for (const circleDoc of circlesSnap.docs) {
    try {
      const settings = circleDoc.data();
      const shiftEndCheck = true; // TODO: نفس منطق حساب نهاية الوردية بتاريخ shiftDurationMins + prayerSlot من Code.gs
      if (!shiftEndCheck) continue;

      const teachersSnap = await circleDoc.ref.collection("teachers").get();
      const attCol = circleDoc.ref.collection("teacherAttendance");
      const dk = todayKey();
      const existingSnap = await attCol.where("dateKey", "==", dk).get();
      const presentIds = new Set(existingSnap.docs.map((d) => d.data().teacherId));

      const batch = db.batch();
      let inserted = false;
      teachersSnap.forEach((tDoc) => {
        if (presentIds.has(tDoc.id)) return;
        const ref = attCol.doc();
        batch.set(ref, {
          dateKey: dk,
          date: admin.firestore.FieldValue.serverTimestamp(),
          dayName: new Date().toLocaleDateString("ar-EG", { weekday: "long" }),
          prayerTime: settings.prayerSlot || "",
          teacherName: tDoc.data().name,
          isAbsent: true,
          checkIn: null,
          checkOut: null,
          delayMins: 0,
          delayStatus: "",
          earlyStatus: "",
          teacherId: tDoc.id,
          username: tDoc.data().username || "",
        });
        inserted = true;
      });
      if (inserted) await batch.commit();
    } catch (e) {
      logger.error(`autoAbsentSweep failed for circle ${circleDoc.id}`, e);
    }
  }
});

/** يقابل remindTeachersNotCheckedIn في Code.gs */
export const remindTeachersNotCheckedIn = onSchedule("every 10 minutes", async () => {
  const circlesSnap = await db.collection("circles").get();
  const nowMinutes = new Date().getUTCHours() * 60 + new Date().getUTCMinutes(); // TODO: تحويل لتوقيت Asia/Riyadh

  for (const circleDoc of circlesSnap.docs) {
    try {
      const settings = circleDoc.data();
      if (!settings.teacherReminderEnabled) continue;
      const cutoff = String(settings.teacherReminderTime || "");
      const m = cutoff.match(/^(\d{1,2}):(\d{2})$/);
      if (!m) continue;
      const cutoffMinutes = Number(m[1]) * 60 + Number(m[2]);
      if (nowMinutes < cutoffMinutes || nowMinutes > cutoffMinutes + 15) continue;

      const dk = todayKey();
      const teachersSnap = await circleDoc.ref.collection("teachers").get();
      const attSnap = await circleDoc.ref.collection("teacherAttendance").where("dateKey", "==", dk).get();
      const checkedInIds = new Set(attSnap.docs.map((d) => d.data().teacherId));

      for (const tDoc of teachersSnap.docs) {
        if (checkedInIds.has(tDoc.id)) continue;
        const phone = tDoc.data().phone;
        if (!phone) continue;
        await sendWhatsAppMessage(
          circleDoc.id, phone,
          "تذكير: لم يتم تسجيل حضورك اليوم بعد. يُرجى تسجيل الدخول في أقرب وقت ممكن."
        );
      }
    } catch (e) {
      logger.error(`remindTeachersNotCheckedIn failed for circle ${circleDoc.id}`, e);
    }
  }
});

/**
 * يقابل weeklyBackupAllComplexes في Code.gs.
 * بدل نسخ ملف شيت لكل مجمع، بنستخدم تصدير Firestore المُدار (Managed Export)
 * لكل قاعدة البيانات دفعة واحدة إلى Cloud Storage — أقوى وأسهل صيانة.
 * يتطلب: تفعيل الـ API، وصلاحية Cloud Datastore Import Export Admin على
 * حساب الخدمة، وباكت Cloud Storage مخصص (مثلاً gs://<project-id>-backups).
 */
export const weeklyBackupAllComplexes = onSchedule(
  { schedule: "every friday 03:00", timeZone: "Asia/Riyadh" },
  async () => {
    const projectId = process.env.GCLOUD_PROJECT;
    const bucket = `gs://${projectId}-backups/firestore/${todayKey()}`;
    try {
      const { GoogleAuth } = await import("google-auth-library");
      const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/datastore"] });
      const client = await auth.getClient();
      await client.request({
        url: `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default):exportDocuments`,
        method: "POST",
        data: { outputUriPrefix: bucket },
      });
      logger.info(`Firestore backup started -> ${bucket}`);
    } catch (e) {
      logger.error("weeklyBackupAllComplexes failed", e);
    }
  }
);

/** يقابل sendWeeklyParentSummaries في Code.gs */
export const sendWeeklyParentSummaries = onSchedule(
  { schedule: "every friday 18:00", timeZone: "Asia/Riyadh" },
  async () => {
    const circlesSnap = await db.collection("circles").get();
    const weekAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 7 * 24 * 60 * 60 * 1000);

    for (const circleDoc of circlesSnap.docs) {
      try {
        const settings = circleDoc.data();
        if (!settings.parentWeeklySummaryEnabled) continue;

        const studentsSnap = await circleDoc.ref.collection("students").get();
        const attSnap = await circleDoc.ref.collection("studentAttendance").where("date", ">=", weekAgo).get();
        const ledgerSnap = await circleDoc.ref.collection("incentiveLedger").where("date", ">=", weekAgo).get();

        for (const sDoc of studentsSnap.docs) {
          const student = sDoc.data();
          if (!student.guardianPhone) continue;

          let present = 0, absent = 0;
          attSnap.forEach((d) => {
            const r = d.data();
            if (r.studentId !== sDoc.id) return;
            if (r.status === "present") present++; else if (r.status === "absent") absent++;
          });

          let points = 0;
          ledgerSnap.forEach((d) => {
            const r = d.data();
            if (r.studentId !== sDoc.id) return;
            points += r.type === "deduct" ? -Number(r.points) : Number(r.points);
          });

          await sendWhatsAppMessage(
            circleDoc.id, student.guardianPhone,
            `ملخص أسبوعي للطالب/ة ${student.name}:\nالحضور: ${present} يوم، الغياب: ${absent} يوم\nمجموع النقاط هذا الأسبوع: ${points}`
          );
        }
      } catch (e) {
        logger.error(`sendWeeklyParentSummaries failed for circle ${circleDoc.id}`, e);
      }
    }
  }
);

/** يقابل sendMonthlyReportsToComplexOwners في Code.gs */
export const sendMonthlyReportsToComplexOwners = onSchedule(
  { schedule: "1 of month 04:00", timeZone: "Asia/Riyadh" },
  async () => {
    const circlesSnap = await db.collection("circles").get();
    const monthAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 24 * 60 * 60 * 1000);

    for (const circleDoc of circlesSnap.docs) {
      try {
        const settings = circleDoc.data();
        const reportEmail = String(settings.reportEmail || "").trim();
        if (!reportEmail) continue;

        const [teachersSnap, studentsSnap, attSnap, ledgerSnap] = await Promise.all([
          circleDoc.ref.collection("teachers").count().get(),
          circleDoc.ref.collection("students").count().get(),
          circleDoc.ref.collection("studentAttendance").where("date", ">=", monthAgo).get(),
          circleDoc.ref.collection("incentiveLedger").where("date", ">=", monthAgo).get(),
        ]);

        let present = 0, absent = 0, totalPoints = 0;
        attSnap.forEach((d) => {
          const r = d.data();
          if (r.status === "present") present++; else if (r.status === "absent") absent++;
        });
        ledgerSnap.forEach((d) => {
          const r = d.data();
          totalPoints += r.type === "deduct" ? -Number(r.points) : Number(r.points);
        });

        // إرسال الإيميل: يتطلب ربط خدمة بريد (مثلاً SendGrid أو Gmail API عبر
        // service account مفوّض) — MailApp كانت متاحة تلقائيًا في Apps Script،
        // وده أحد الفروقات اللي لازم تتغطى بخدمة خارجية هنا.
        logger.info(`Monthly report ready for ${circleDoc.id} -> ${reportEmail}`, {
          teachersCount: teachersSnap.data().count,
          studentsCount: studentsSnap.data().count,
          present, absent, totalPoints,
        });
      } catch (e) {
        logger.error(`sendMonthlyReportsToComplexOwners failed for circle ${circleDoc.id}`, e);
      }
    }
  }
);
