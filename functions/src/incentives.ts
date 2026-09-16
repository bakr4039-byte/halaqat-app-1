import * as functions from "firebase-functions/v2/https";
import { db, admin } from "./admin";
import { requireCircleAccess, circleCol } from "./helpers";

/** يقابل getIncentiveItems في Code.gs */
export const getIncentiveItems = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "incentiveItems").get();
  return { success: true, items: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل saveIncentiveItem في Code.gs (إنشاء أو تعديل بند تحفيزي) */
export const saveIncentiveItem = functions.onCall(async (request) => {
  const { circleId, item } = request.data as {
    circleId: string;
    item: { id?: string; name: string; type: "grant" | "deduct"; points: number };
  };
  requireCircleAccess(request, circleId);

  const col = circleCol(circleId, "incentiveItems");
  const ref = item.id ? col.doc(item.id) : col.doc();
  await ref.set({ name: item.name, type: item.type, points: Number(item.points) || 0 }, { merge: true });
  return { success: true, id: ref.id };
});

/** يقابل deleteIncentiveItem في Code.gs */
export const deleteIncentiveItem = functions.onCall(async (request) => {
  const { circleId, itemId } = request.data as { circleId: string; itemId: string };
  requireCircleAccess(request, circleId);
  await circleCol(circleId, "incentiveItems").doc(itemId).delete();
  return { success: true };
});

/** يقابل applyIncentivePointsBulk في Code.gs — تطبيق بند تحفيزي على عدة طلاب دفعة واحدة */
export const applyIncentivePointsBulk = functions.onCall(async (request) => {
  const { circleId, itemId, studentIds, appliedBy } = request.data as {
    circleId: string; itemId: string; studentIds: string[]; appliedBy: string;
  };
  requireCircleAccess(request, circleId);

  const itemSnap = await circleCol(circleId, "incentiveItems").doc(itemId).get();
  if (!itemSnap.exists) throw new functions.HttpsError("not-found", "البند التحفيزي غير موجود.");
  const item = itemSnap.data()!;

  const studentsSnap = await circleCol(circleId, "students").get();
  const studentMap: Record<string, FirebaseFirestore.DocumentData> = {};
  studentsSnap.forEach((d) => (studentMap[d.id] = d.data()));

  const ledgerCol = circleCol(circleId, "incentiveLedger");
  const batch = db.batch();
  (studentIds || []).forEach((sid) => {
    const student = studentMap[sid];
    if (!student) return;
    const ref = ledgerCol.doc();
    batch.set(ref, {
      studentId: sid,
      studentName: student.name || "",
      subCircle: student.subCircle || "",
      itemId,
      itemName: item.name,
      type: item.type,
      points: item.points,
      date: admin.firestore.FieldValue.serverTimestamp(),
      appliedBy: appliedBy || "",
    });
  });
  await batch.commit();
  return { success: true, count: (studentIds || []).length };
});

/** يقابل getIncentiveLedger في Code.gs */
export const getIncentiveLedger = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);
  const snap = await circleCol(circleId, "incentiveLedger").orderBy("date", "desc").get();
  return { success: true, ledger: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل getLeaderboard في Code.gs — إجمالي نقاط كل طالب مرتّبة تنازليًا، مع عمود الحلقة */
export const getLeaderboard = functions.onCall(async (request) => {
  const { circleId } = request.data as { circleId: string };
  requireCircleAccess(request, circleId);

  const snap = await circleCol(circleId, "incentiveLedger").get();
  const totals: Record<string, { studentName: string; subCircle: string; points: number }> = {};
  snap.forEach((doc) => {
    const r = doc.data();
    if (!totals[r.studentId]) totals[r.studentId] = { studentName: r.studentName, subCircle: r.subCircle || "", points: 0 };
    totals[r.studentId].points += r.type === "deduct" ? -Number(r.points) : Number(r.points);
  });

  const leaderboard = Object.entries(totals)
    .map(([studentId, v]) => ({ studentId, studentName: v.studentName, subCircle: v.subCircle, points: v.points }))
    .sort((a, b) => b.points - a.points);

  return { success: true, leaderboard };
});

/** يقابل getIncentiveTransactions في Code.gs — بحسب تاريخ */
export const getIncentiveTransactions = functions.onCall(async (request) => {
  const { circleId, fromDateKey, toDateKey } = request.data as {
    circleId: string; fromDateKey?: string; toDateKey?: string;
  };
  requireCircleAccess(request, circleId);

  let q: FirebaseFirestore.Query = circleCol(circleId, "incentiveLedger");
  if (fromDateKey) q = q.where("date", ">=", admin.firestore.Timestamp.fromDate(new Date(fromDateKey)));
  if (toDateKey) q = q.where("date", "<=", admin.firestore.Timestamp.fromDate(new Date(toDateKey)));

  const snap = await q.orderBy("date", "desc").get();
  return { success: true, transactions: snap.docs.map((d) => ({ id: d.id, ...d.data() })) };
});

/** يقابل updateIncentiveTransaction في Code.gs — لتصحيح عملية مسجّلة بالخطأ */
export const updateIncentiveTransaction = functions.onCall(async (request) => {
  const { circleId, transactionId, updates } = request.data as {
    circleId: string; transactionId: string; updates: { points?: number; type?: "grant" | "deduct" };
  };
  requireCircleAccess(request, circleId);
  await circleCol(circleId, "incentiveLedger").doc(transactionId).update(updates);
  return { success: true };
});

/** يقابل deleteIncentiveTransaction في Code.gs */
export const deleteIncentiveTransaction = functions.onCall(async (request) => {
  const { circleId, transactionId } = request.data as { circleId: string; transactionId: string };
  requireCircleAccess(request, circleId);
  await circleCol(circleId, "incentiveLedger").doc(transactionId).delete();
  return { success: true };
});
