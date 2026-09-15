# مخطط بيانات Firestore — نظام إدارة الحلقات

هذا المستند يوثّق التحويل من هيكل Google Sheets الحالي إلى مجموعات Firestore، حفاظًا على نفس العلاقات المنطقية مع إضافة القابلية للتوسع (فهرسة، استعلامات مباشرة، أمان على مستوى المستند).

## الفكرة العامة

- كل "مجمع" (Circle) كان له ملف Google Sheets منفصل (SpreadsheetID). في Firestore بيصبح مستند واحد داخل مجموعة `circles`، وكل البيانات التابعة له (معلمين، طلاب، حضور...) تبقى في مجموعات فرعية (subcollections) تحت مستند المجمع، بدل ملفات منفصلة.
- ملف `Users_Database` (المستخدمين) كان فيه صف واحد لكل مجمع (Username/Password/SpreadsheetID). في Firestore، تسجيل الدخول بيتحول لـ **Firebase Authentication** (بريد إلكتروني/كلمة مرور أو رقم هاتف)، مع custom claims تحدد الدور (superAdmin / circleOwner / teacher) والمجمع التابع له.
- التوقيت المحلي (Asia/Riyadh) بيتحول من نص "dd/MM/yyyy" إلى `Timestamp` حقيقي في Firestore (تسهيل الفرز والاستعلام بالتاريخ، مع الاحتفاظ بحقل نصي "dateKey" بصيغة yyyy-MM-dd للمطابقة السريعة).

## المجموعات (Collections)

### `circles/{circleId}`
يقابل صف في Users + شيت Settings.
```
{
  circleName: string,
  ownerUsername: string,       // كان Username في Users
  logoUrl: string,
  createdAt: Timestamp,
  themeColor: string,
  workDays: number,
  prayerSlot: string,
  shiftDurationMins: number,
  prayerCity: string,
  circlePhone: string,
  graceMinutes: number,
  autoWhatsapp: boolean,
  prayerReminderEnabled: boolean,
  reminderMinutesBefore: number,
  // إعدادات الميزات الجديدة (واتساب + تذكيرات + تقارير)
  whatsappPhoneNumberId: string,
  whatsappAccessToken: string,   // يُفضّل نقلها لـ Secret Manager بدل تخزينها كنص عادي
  teacherReminderEnabled: boolean,
  teacherReminderTime: string,   // "HH:MM"
  parentWeeklySummaryEnabled: boolean,
  parentAbsenceNotifyEnabled: boolean,
  reportEmail: string
}
```

### `circles/{circleId}/teachers/{teacherId}`
يقابل شيت Teachers (ID, Name, Salary, Phone, Bonus, SubCircle, Username).
```
{
  name: string,
  salary: number,
  phone: string,
  bonus: number,
  subCircle: string,
  username: string,
  authUid: string   // ربط بحساب Firebase Auth الخاص بالمعلم
}
```

### `circles/{circleId}/teacherAttendance/{recordId}`
يقابل شيت Attendance (تحضير/انصراف المعلمين).
```
{
  dateKey: string,        // yyyy-MM-dd
  date: Timestamp,
  dayName: string,
  prayerTime: string,
  teacherName: string,
  isAbsent: boolean,
  checkIn: Timestamp | null,
  checkOut: Timestamp | null,
  delayMins: number,
  delayStatus: string,
  earlyStatus: string,
  teacherId: string,
  username: string
}
```

### `circles/{circleId}/students/{studentId}`
يقابل شيت Students.
```
{
  name: string,
  guardianName: string,
  guardianPhone: string,
  stage: string,
  memorizationSurah: string,
  teacherId: string,
  subCircle: string,
  address: string,
  joinDate: Timestamp,
  notes: string,
  status: string   // active / inactive
}
```

### `circles/{circleId}/studentAttendance/{recordId}`
يقابل شيت StudentAttendance.
```
{
  dateKey: string,
  date: Timestamp,
  studentId: string,
  studentName: string,
  teacherId: string,
  status: string,   // present / absent
  notes: string
}
```

### `circles/{circleId}/incentiveItems/{itemId}`
يقابل شيت IncentiveItems.
```
{ name: string, type: string, points: number }
```

### `circles/{circleId}/incentiveLedger/{entryId}`
يقابل شيت IncentivePoints.
```
{
  studentId: string,
  studentName: string,
  subCircle: string,
  itemId: string,
  itemName: string,
  type: string,
  points: number,
  date: Timestamp,
  appliedBy: string
}
```

### `circles/{circleId}/academicProgress/{studentId}`
يقابل شيت AcademicProgress.
```
{
  studentName: string,
  circle: string,
  teacherId: string,
  hifz: number,
  minorReview: number,
  majorReview: number
}
```

## المصادقة والصلاحيات (يستبدل السوبر أدمن/يوزر/باسورد النصي)

- **Firebase Authentication** بدل المقارنة النصية لكلمة المرور.
- **Custom Claims** على حساب كل مستخدم: `{ role: 'superAdmin' | 'owner' | 'teacher', circleId: '...' }`.
- **Firestore Security Rules** تمنع أي مستخدم من قراءة/تعديل بيانات مجمع غير بتاعه، وتمنع أي عميل (حتى لو مصادق) من تعديل نقاط التحفيز أو الحضور مباشرة — كل التعديلات تمر عبر Cloud Functions (نفس فلسفة "الباك إند بيتحكم" الموجودة حاليًا في Code.gs) عشان نمنع الغش (مثلاً طالب يغيّر نقاطه بنفسه).

## ملاحظة أمنية مهمة

`whatsappAccessToken` حاليًا مخزّن كنص عادي في شيت Settings (بيانات حساسة). في Firestore/Firebase الأفضل نقله لـ **Secret Manager** وتقرأه الـ Cloud Function وقت التنفيذ فقط، مش تسيبه في مستند يقدر أي أدمن مجمع يشوفه.
