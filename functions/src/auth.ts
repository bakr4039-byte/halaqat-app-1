import * as functions from "firebase-functions/v2/https";
import { db, auth } from "./admin";
import * as crypto from "crypto";

// ============================================================
// نظام مصادقة بديل لمقارنة username/password النصية في Code.gs
//
// نستخدم Firebase Custom Tokens: العميل (تطبيق Flutter) يبعت
// username + password لـ Cloud Function، والفنكشن يتحقق من الهاش
// المخزّن في مجموعة "credentials"، ولو صح بيرجّع Custom Token
// يستخدمه العميل مع signInWithCustomToken(). بعد كده كل تعامل
// العميل مع Firestore بيمر عبر Firebase Auth الحقيقي (uid + claims).
//
// حفظ كلمة المرور: PBKDF2 (متوفرة أصلاً في Node crypto، بدون أي
// حزمة خارجية إضافية) — أفضل بكتير من التخزين النصي الحالي في
// SUPER_ADMIN_PASSWORD / شيت Users.
// ============================================================

const PBKDF2_ITERATIONS = 100_000;

function hashPassword(password: string, salt: string): string {
  return crypto.pbkdf2Sync(password, salt, PBKDF2_ITERATIONS, 64, "sha512").toString("hex");
}

export function makeCredential(password: string): { salt: string; hash: string } {
  const salt = crypto.randomBytes(16).toString("hex");
  return { salt, hash: hashPassword(password, salt) };
}

function verifyPassword(password: string, salt: string, expectedHash: string): boolean {
  const hash = hashPassword(password, salt);
  // مقارنة بزمن ثابت لمنع timing attacks
  const a = Buffer.from(hash, "hex");
  const b = Buffer.from(expectedHash, "hex");
  if (a.length !== b.length) return false;
  return crypto.timingSafeEqual(a, b);
}

interface CredentialDoc {
  username: string;
  salt: string;
  hash: string;
  role: "superAdmin" | "owner" | "teacher";
  circleId?: string;
  teacherId?: string;
  disabled?: boolean;
}

async function loginWithUsernamePassword(username: string, password: string) {
  const uname = String(username || "").trim().toLowerCase();
  if (!uname || !password) {
    throw new functions.HttpsError("invalid-argument", "الرجاء إدخال اسم المستخدم وكلمة المرور.");
  }

  const credSnap = await db.collection("credentials").doc(uname).get();
  if (!credSnap.exists) {
    throw new functions.HttpsError("not-found", "بيانات الدخول غير صحيحة.");
  }
  const cred = credSnap.data() as CredentialDoc;
  if (cred.disabled) {
    throw new functions.HttpsError("permission-denied", "هذا الحساب معطّل.");
  }
  if (!verifyPassword(password, cred.salt, cred.hash)) {
    throw new functions.HttpsError("not-found", "بيانات الدخول غير صحيحة.");
  }

  // uid الحساب في Firebase Auth = نفس اسم المستخدم (منظّف) لضمان الثبات
  const uid = `u_${uname}`;
  try {
    await auth.getUser(uid);
  } catch {
    await auth.createUser({ uid, displayName: uname });
  }

  const claims: Record<string, unknown> = { role: cred.role };
  if (cred.circleId) claims.circleId = cred.circleId;
  if (cred.teacherId) claims.teacherId = cred.teacherId;
  await auth.setCustomUserClaims(uid, claims);

  const customToken = await auth.createCustomToken(uid, claims);
  return { success: true, token: customToken, role: cred.role, circleId: cred.circleId || null };
}

/** يقابل superAdminLogin / loginUser (لصاحب المجمع) / loginTeacherView في Code.gs */
export const login = functions.onCall(async (request) => {
  const { username, password } = request.data as { username: string; password: string };
  return loginWithUsernamePassword(username, password);
});
