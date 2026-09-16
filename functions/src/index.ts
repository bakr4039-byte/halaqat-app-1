// ============================================================
// نقطة تجميع كل Cloud Functions — نظام إدارة الحلقات
// (البديل الكامل لملف Code.gs في مشروع Google Apps Script)
// ============================================================

export { login, bootstrapSuperAdmin } from "./auth";

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
