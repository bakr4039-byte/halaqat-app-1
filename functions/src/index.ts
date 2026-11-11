// ============================================================
// نقطة تجميع كل Cloud Functions — نظام إدارة الحلقات
// (البديل الكامل لملف Code.gs في مشروع Google Apps Script)
// ============================================================

import { setGlobalOptions } from "firebase-functions/v2";

// Keep the existing callable region, with small workloads and bounded scaling.
setGlobalOptions({ region: "us-central1", memory: "256MiB", cpu: "gcf_gen1", concurrency: 1, minInstances: 0, maxInstances: 2 });

export { login } from "./auth";

export {
  superAdminCreateCircle,
  superAdminGetOverview,
  superAdminUpdateCircle,
  superAdminDeleteCircle,
} from "./superAdmin";

export {
  getInitialData,
  recordTeacherCheckIn,
  recordTeacherCheckOut,
  adminStampTeacherAttendance,
  setTeacherAbsentToday,
  getTeacherAttendanceReport,
  getMonthlyPayroll,
  saveTodayAttendanceToSheet,
  saveTeachersAndSettings,
} from "./teacherAttendance";

export {
  getStudents,
  saveStudents,
  getStudentAttendanceForDate,
  saveStudentAttendanceDay,
  saveSingleStudentAttendance,
  getStudentAttendanceReport,
  getAttendanceTrend,
} from "./students";

export {
  getIncentiveItems,
  saveIncentiveItem,
  deleteIncentiveItem,
  applyIncentivePointsBulk,
  getIncentiveLedger,
  getLeaderboard,
  getIncentiveTransactions,
  updateIncentiveTransaction,
  deleteIncentiveTransaction,
} from "./incentives";

export { getAcademicProgressData, saveAcademicProgressValue } from "./academicProgress";

export {
  autoAbsentSweep,
  remindTeachersNotCheckedIn,
  weeklyBackupAllComplexes,
  sendWeeklyParentSummaries,
  sendMonthlyReportsToComplexOwners,
} from "./triggers";

