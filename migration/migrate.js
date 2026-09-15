/**
 * سكريبت هجرة بيانات نظام إدارة الحلقات
 * من: Google Sheets (MASTER_SS_ID + ملف شيت لكل مجمع)
 * إلى: Firestore (حسب docs/data-model.md)
 *
 * طريقة التشغيل (من جهازك، مرة واحدة وقت الانتقال):
 *   1) cd migration && npm install
 *   2) جهّز حساب خدمة (Service Account) من Google Cloud Console بصلاحية:
 *        - Editor أو Firestore + Sheets API معًا (أو حسابين منفصلين، الكود يدعم الاثنين)
 *      وشارك MASTER_SS_ID وكل ملفات شيتات المجمعات مع بريد الحساب (كـ Viewer).
 *   3) حمّل ملف مفتاح JSON للحساب واحفظه هنا باسم service-account.json
 *      (الملف ده لازم يفضل خاص، متضافش لأي Git repo عام).
 *   4) شغّل: node migrate.js
 *
 * السكريبت بينفّذ Dry-run افتراضيًا (بيطبع بس، من غير ما يكتب) —
 * لازم تمرر --write عشان فعليًا يكتب في Firestore.
 */

const fs = require("fs");
const path = require("path");
const { google } = require("googleapis");
const admin = require("firebase-admin");
const crypto = require("crypto");

const MASTER_SS_ID = process.env.MASTER_SS_ID || "1X2PpM6HX8NH0WIXULRc13cshx_lmCB2uZI1RwhPH7kQ";
const SERVICE_ACCOUNT_PATH = path.join(__dirname, "service-account.json");
const DRY_RUN = !process.argv.includes("--write");

if (!fs.existsSync(SERVICE_ACCOUNT_PATH)) {
  console.error("خطأ: مفقود ملف service-account.json في مجلد migration/. راجع التعليمات أعلى الملف.");
  process.exit(1);
}
const serviceAccount = JSON.parse(fs.readFileSync(SERVICE_ACCOUNT_PATH, "utf8"));

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const auth = new google.auth.GoogleAuth({
  credentials: serviceAccount,
  scopes: ["https://www.googleapis.com/auth/spreadsheets.readonly"],
});
const sheets = google.sheets({ version: "v4", auth });

// ============================================================
// أدوات مساعدة
// ============================================================

const PBKDF2_ITERATIONS = 100_000;
function makeCredential(password) {
  const salt = crypto.randomBytes(16).toString("hex");
  const hash = crypto.pbkdf2Sync(password, salt, PBKDF2_ITERATIONS, 64, "sha512").toString("hex");
  return { salt, hash };
}

function parseDdMmYyyy(str) {
  const s = String(str || "").trim();
  const m = s.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})$/);
  if (!m) return null;
  return new Date(Number(m[3]), Number(m[2]) - 1, Number(m[1]));
}

function toTimestampOrNull(d) {
  return d ? admin.firestore.Timestamp.fromDate(d) : null;
}

async function readSheet(spreadsheetId, sheetName, numCols) {
  try {
    const res = await sheets.spreadsheets.values.get({
      spreadsheetId,
      range: `${sheetName}!A2:${String.fromCharCode(64 + numCols)}`,
    });
    return res.data.values || [];
  } catch (e) {
    console.warn(`  تعذّرت قراءة شيت "${sheetName}" من ${spreadsheetId}: ${e.message}`);
    return [];
  }
}

/** يكتب مجموعة صفوف في مجموعة فرعية على دفعات (حد Firestore 500 لكل batch) */
async function writeDocs(colRef, docs) {
  if (DRY_RUN) {
    console.log(`  [DRY-RUN] كان هيتكتب ${docs.length} مستند في ${colRef.path}`);
    return;
  }
  for (let i = 0; i < docs.length; i += 450) {
    const batch = db.batch();
    docs.slice(i, i + 450).forEach(({ id, data }) => {
      const ref = id ? colRef.doc(id) : colRef.doc();
      batch.set(ref, data, { merge: true });
    });
    await batch.commit();
  }
  console.log(`  ✓ اتكتب ${docs.length} مستند في ${colRef.path}`);
}

// ============================================================
// الهجرة الفعلية
// ============================================================

async function migrateCircle(row) {
  const [username, password, circleName, spreadsheetId, logoUrl, createdAt] = row;
  if (!username || !spreadsheetId) return;

  console.log(`\n== مجمع: ${circleName} (${username}) ==`);
  const uname = String(username).trim().toLowerCase();

  // 1) مستند المجمع + الإعدادات
  const settingsRows = await readSheet(spreadsheetId, "Settings", 2);
  const settings = {};
  settingsRows.forEach(([k, v]) => { if (k) settings[k] = v; });

  const circleRef = db.collection("circles").doc(); // معرّف جديد؛ لو عايز تحافظ على نفس الـ SpreadsheetID كمعرّف استخدم .doc(spreadsheetId)
  const circleData = {
    circleName: circleName || settings.circleName || "",
    ownerUsername: uname,
    logoUrl: logoUrl || settings.circleLogo || "",
    createdAt: parseDdMmYyyy(createdAt) ? toTimestampOrNull(parseDdMmYyyy(createdAt)) : admin.firestore.FieldValue.serverTimestamp(),
    themeColor: settings.themeColor || "green",
    workDays: Number(settings.workDays) || 5,
    prayerSlot: settings.prayerSlot || "Asr",
    shiftDurationMins: Number(settings.shiftDurationMins) || 120,
    prayerCity: settings.prayerCity || "Riyadh",
    circlePhone: settings.circlePhone || "",
    graceMinutes: Number(settings.graceMinutes) || 0,
    autoWhatsapp: String(settings.autoWhatsapp).toLowerCase() === "true",
    prayerReminderEnabled: String(settings.prayerReminderEnabled).toLowerCase() !== "false",
    reminderMinutesBefore: Number(settings.reminderMinutesBefore) || 15,
    whatsappPhoneNumberId: settings.whatsappPhoneNumberId || "",
    teacherReminderEnabled: String(settings.teacherReminderEnabled).toLowerCase() === "true",
    teacherReminderTime: settings.teacherReminderTime || "",
    parentWeeklySummaryEnabled: String(settings.parentWeeklySummaryEnabled).toLowerCase() === "true",
    parentAbsenceNotifyEnabled: String(settings.parentAbsenceNotifyEnabled).toLowerCase() === "true",
    reportEmail: settings.reportEmail || "",
  };

  if (!DRY_RUN) await circleRef.set(circleData);
  else console.log(`  [DRY-RUN] هيتعمل مجمع جديد بالبيانات:`, circleData.circleName);

  // 2) بيانات اعتماد صاحب المجمع (كلمة المرور القديمة بتتهاش من جديد)
  const { salt, hash } = makeCredential(String(password || Math.random().toString(36)));
  if (!DRY_RUN) {
    await db.collection("credentials").doc(uname).set({
      username: uname, salt, hash, role: "owner", circleId: circleRef.id,
    });
  } else {
    console.log(`  [DRY-RUN] هيتعمل credential لـ ${uname} بدور owner`);
  }

  // 3) المعلمون
  const teacherRows = await readSheet(spreadsheetId, "Teachers", 7);
  const teacherDocs = teacherRows.map((r) => ({
    id: null,
    legacyId: r[0],
    data: { name: r[1] || "", salary: Number(r[2]) || 0, phone: r[3] || "", bonus: Number(r[4]) || 0, subCircle: r[5] || "", username: r[6] || "" },
  }));
  const teacherIdMap = {}; // legacyId (شيت) -> Firestore doc id جديد
  const teachersColRef = circleRef.collection("teachers");
  if (!DRY_RUN) {
    for (const t of teacherDocs) {
      const ref = teachersColRef.doc();
      await ref.set(t.data);
      teacherIdMap[t.legacyId] = ref.id;
    }
  }
  console.log(`  معلمون: ${teacherDocs.length}`);

  // 4) حضور المعلمين
  const attRows = await readSheet(spreadsheetId, "Attendance", 12);
  const attDocs = attRows.map((r) => {
    const d = parseDdMmYyyy(r[0]);
    return {
      id: null,
      data: {
        dateKey: d ? d.toISOString().slice(0, 10) : "",
        date: toTimestampOrNull(d) || admin.firestore.Timestamp.now(),
        dayName: r[1] || "", prayerTime: r[2] || "", teacherName: r[3] || "",
        isAbsent: String(r[4]).toUpperCase() === "TRUE",
        checkIn: r[5] || "", checkOut: r[6] || "",
        delayMins: Number(r[7]) || 0, delayStatus: r[8] || "", earlyStatus: r[9] || "",
        teacherId: teacherIdMap[r[10]] || r[10] || "", username: r[11] || "",
      },
    };
  });
  await writeDocs(circleRef.collection("teacherAttendance"), attDocs);

  // 5) الطلاب
  const studentRows = await readSheet(spreadsheetId, "Students", 12);
  const studentDocs = studentRows.map((r) => ({
    id: null,
    legacyId: r[0],
    data: {
      name: r[1] || "", guardianName: r[2] || "", guardianPhone: r[3] || "",
      stage: r[4] || "", memorizationSurah: r[5] || "",
      teacherId: teacherIdMap[r[6]] || r[6] || "", subCircle: r[7] || "",
      address: r[8] || "", joinDate: toTimestampOrNull(parseDdMmYyyy(r[9])),
      notes: r[10] || "", status: r[11] || "active",
    },
  }));
  const studentIdMap = {};
  const studentsColRef = circleRef.collection("students");
  if (!DRY_RUN) {
    for (const s of studentDocs) {
      const ref = studentsColRef.doc();
      await ref.set(s.data);
      studentIdMap[s.legacyId] = ref.id;
    }
  }
  console.log(`  طلاب: ${studentDocs.length}`);

  // 6) حضور الطلاب
  const sAttRows = await readSheet(spreadsheetId, "StudentAttendance", 6);
  const sAttDocs = sAttRows.map((r) => {
    const d = parseDdMmYyyy(r[0]);
    return {
      id: null,
      data: {
        dateKey: d ? d.toISOString().slice(0, 10) : "",
        date: toTimestampOrNull(d) || admin.firestore.Timestamp.now(),
        studentId: studentIdMap[r[1]] || r[1] || "", studentName: r[2] || "",
        teacherId: teacherIdMap[r[3]] || r[3] || "", status: r[4] || "", notes: r[5] || "",
      },
    };
  });
  await writeDocs(circleRef.collection("studentAttendance"), sAttDocs);

  // 7) بنود التحفيز
  const itemRows = await readSheet(spreadsheetId, "IncentiveItems", 4);
  const itemDocs = itemRows.map((r) => ({ id: null, legacyId: r[0], data: { name: r[1] || "", type: r[2] || "grant", points: Number(r[3]) || 0 } }));
  const itemIdMap = {};
  const itemsColRef = circleRef.collection("incentiveItems");
  if (!DRY_RUN) {
    for (const it of itemDocs) {
      const ref = itemsColRef.doc();
      await ref.set(it.data);
      itemIdMap[it.legacyId] = ref.id;
    }
  }
  console.log(`  بنود تحفيزية: ${itemDocs.length}`);

  // 8) سجل نقاط التحفيز
  const ledgerRows = await readSheet(spreadsheetId, "IncentivePoints", 10);
  const ledgerDocs = ledgerRows.map((r) => {
    const d = parseDdMmYyyy(r[8]);
    return {
      id: null,
      data: {
        studentId: studentIdMap[r[1]] || r[1] || "", studentName: r[2] || "", subCircle: r[3] || "",
        itemId: itemIdMap[r[4]] || r[4] || "", itemName: r[5] || "", type: r[6] || "grant",
        points: Number(r[7]) || 0, date: toTimestampOrNull(d) || admin.firestore.Timestamp.now(),
        appliedBy: r[9] || "",
      },
    };
  });
  await writeDocs(circleRef.collection("incentiveLedger"), ledgerDocs);

  // 9) التقدم الأكاديمي
  const progRows = await readSheet(spreadsheetId, "AcademicProgress", 7);
  const progDocs = progRows.map((r) => ({
    id: studentIdMap[r[0]] || null,
    data: {
      studentName: r[1] || "", circle: r[2] || "", teacherId: teacherIdMap[r[3]] || r[3] || "",
      hifz: Number(r[4]) || 0, minorReview: Number(r[5]) || 0, majorReview: Number(r[6]) || 0,
    },
  }));
  await writeDocs(circleRef.collection("academicProgress"), progDocs);
}

async function main() {
  console.log(DRY_RUN ? "*** وضع تجريبي (Dry-run) — مفيش أي كتابة فعلية. مرر --write للكتابة الحقيقية. ***" : "*** وضع الكتابة الفعلية ***");

  const usersRows = await readSheet(MASTER_SS_ID, "Users", 6);
  console.log(`عدد المجمعات في Users: ${usersRows.length}`);

  for (const row of usersRows) {
    await migrateCircle(row);
  }

  console.log("\nتمت الهجرة." + (DRY_RUN ? " (Dry-run فقط — شغّل بـ --write للتنفيذ الفعلي)" : ""));
}

main().catch((e) => {
  console.error("فشلت الهجرة:", e);
  process.exit(1);
});
