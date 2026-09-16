// ============================================================
// أنواع البيانات المشتركة — مطابقة لـ docs/data-model.md
// ============================================================

export type UserRole = "superAdmin" | "owner" | "teacher";

export interface AuthClaims {
  role: UserRole;
  circleId?: string;
  teacherId?: string;
}

export interface Circle {
  circleName: string;
  ownerUsername: string;
  logoUrl: string;
  createdAt: FirebaseFirestore.Timestamp;
  themeColor: string;
  workDays: number;
  prayerSlot: string;
  shiftDurationMins: number;
  prayerCity: string;
  circlePhone: string;
  graceMinutes: number;
  autoWhatsapp: boolean;
  prayerReminderEnabled: boolean;
  reminderMinutesBefore: number;
  whatsappPhoneNumberId?: string;
  teacherReminderEnabled?: boolean;
  teacherReminderTime?: string;
  parentWeeklySummaryEnabled?: boolean;
  parentAbsenceNotifyEnabled?: boolean;
  reportEmail?: string;
}

export interface Teacher {
  name: string;
  salary: number;
  phone: string;
  bonus: number;
  subCircle: string;
  username: string;
  authUid?: string;
}

export interface GeoPoint {
  lat: number;
  lng: number;
}

export interface TeacherAttendanceRecord {
  dateKey: string;
  date: FirebaseFirestore.Timestamp;
  dayName: string;
  prayerTime: string;
  teacherName: string;
  isAbsent: boolean;
  checkIn: FirebaseFirestore.Timestamp | null;
  checkInLocation?: GeoPoint | null;
  checkOut: FirebaseFirestore.Timestamp | null;
  checkOutLocation?: GeoPoint | null;
  delayMins: number;
  delayStatus: string;
  earlyStatus: string;
  teacherId: string;
  username: string;
}

export interface Student {
  name: string;
  guardianName: string;
  guardianPhone: string;
  stage: string;
  memorizationSurah: string;
  teacherId: string;
  subCircle: string;
  address: string;
  joinDate: FirebaseFirestore.Timestamp | null;
  notes: string;
  status: "active" | "inactive";
}

export interface StudentAttendanceRecord {
  dateKey: string;
  date: FirebaseFirestore.Timestamp;
  studentId: string;
  studentName: string;
  teacherId: string;
  status: "present" | "absent";
  notes: string;
}

export interface IncentiveItem {
  name: string;
  type: "grant" | "deduct";
  points: number;
}

export interface IncentiveLedgerEntry {
  studentId: string;
  studentName: string;
  subCircle: string;
  itemId: string;
  itemName: string;
  type: "grant" | "deduct";
  points: number;
  date: FirebaseFirestore.Timestamp;
  appliedBy: string;
}

export interface AcademicProgress {
  studentName: string;
  circle: string;
  teacherId: string;
  hifz: number;
  minorReview: number;
  majorReview: number;
}
