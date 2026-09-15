# نظام إدارة الحلقات — تطبيق أندرويد وآيفون

تحويل نظام إدارة الحلقات من Google Apps Script (شيتات + صفحة ويب واحدة) إلى تطبيق حقيقي قابل للتوسع لأندرويد وآيفون، ببنية تحتية Firebase.

## هيكل المشروع

```
halaqat-app/
├── docs/data-model.md       ← مخطط بيانات Firestore الكامل (بديل شيتات Google)
├── firestore/                ← قواعد الأمان والفهرسة
├── functions/                ← الـ Backend (Cloud Functions بديل Code.gs) — TypeScript، بُني بنجاح ✅
├── migration/                ← سكريبت نقل بياناتك الحالية من الشيتات إلى Firestore
├── flutter_app/               ← كود تطبيق Flutter (أندرويد + آيفون) بلغة Dart واحدة
└── .github/workflows/build.yml ← بناء تلقائي مجاني لأندرويد وآيفون عبر GitHub Actions
```

## اللي خلص فعليًا

- **مخطط بيانات Firestore** كامل مطابق لبياناتك الحالية (مجمعات، معلمين، طلاب، حضور، نقاط تحفيزية، تقدّم أكاديمي).
- **كل Cloud Functions** بديلة لدوال Code.gs: المصادقة، السوبر أدمن (إنشاء/عرض/تعديل/حذف مجمع)، تحضير المعلمين، تحضير الطلاب + إشعار واتساب فوري للغياب، نقاط التحفيز ولوحة الشرف، التقدم الأكاديمي، والمهام المجدولة الأربعة (تذكير معلمين، نسخ احتياطي، ملخص أولياء أمور، تقرير شهري). **تم بناؤها بنجاح (npm run build) من غير أي أخطاء.**
- **سكريبت هجرة البيانات** من شيتاتك الحالية إلى Firestore (وضع تجريبي Dry-run افتراضيًا لأمانك).
- **تطبيق Flutter** بشاشات شغّالة: تسجيل دخول (سوبر أدمن/صاحب مجمع/معلم)، لوحة سوبر أدمن كاملة (نظرة عامة + إنشاء مجمع)، تحضير/انصراف المعلم، تحضير الطلاب، نقاط التحفيز ولوحة الشرف (مع تطبيق نقاط)، متابعة التقدم الأكاديمي.
- **GitHub Actions** يبني نسخة أندرويد (APK+AAB) وآيفون تلقائيًا مجانًا — يحل مشكلة إن بناء آيفون محتاج Mac.

## اللي محتاج منك أنت تحديدًا (حاجات قانونية/دفع مينفعش أعملها بدالك)

هذول الخطوات الوحيدة اللي **لازم** تتعمل من عندك:

1. **إنشاء مشروع Firebase**: روح [console.firebase.google.com](https://console.firebase.google.com) بحساب Gmail بتاعك، اعمل مشروع جديد، وفعّل: Authentication (Custom sign-in)، Firestore، Functions (يحتاج ترقية لخطة Blaze — بيها استخدام مجاني شهري كبير، مش هتدفع حاجة غالبًا لحجم نظامك الحالي).
2. **حساب Apple Developer** ($99/سنة) لو عايز تنشر على App Store — من [developer.apple.com](https://developer.apple.com). ده محتاج هويتك ودفع، مقدرش أعمله بدالك.
3. **حساب Google Play Console** ($25 مرة واحدة) لو عايز تنشر على Google Play — من [play.google.com/console](https://play.google.com/console).

## خطوات التشغيل بالترتيب

### 1) الـ Backend (Firebase)
```bash
cd halaqat-app
npm install -g firebase-tools
firebase login
firebase init   # اختار المشروع اللي عملته في الخطوة 1
firebase deploy --only firestore:rules,firestore:indexes,functions
```
بعد أول نشر، شغّل دالة `bootstrapSuperAdmin` مرة واحدة (من Firebase Console أو بـ curl) لإنشاء أول حساب سوبر أدمن — راجع التعليقات في `functions/src/auth.ts`.

### 2) هجرة بياناتك الحالية (اختياري، لو عايز تبدأ ببياناتك مش من الصفر)
```bash
cd migration
npm install
# حط ملف service-account.json (التعليمات في أول migrate.js)
node migrate.js          # وضع تجريبي أولاً
node migrate.js --write  # الكتابة الفعلية
```

### 3) تطبيق Flutter
```bash
cd flutter_app
./setup.sh                                    # يولّد android/ و ios/
dart pub global activate flutterfire_cli
flutterfire configure --project=<project-id>  # يربط التطبيق بمشروعك فعليًا
flutter run                                   # تجربة على جهازك
```

### 4) بناء تلقائي للمتجرين
اعمل commit وpush للمشروع كامل (بما فيه `flutter_app/android` و`flutter_app/ios` الناتجين من setup.sh) لمستودع GitHub، وGitHub Actions هيبني نسخة أندرويد وآيفون تلقائيًا (تقدر تنزّلها من تبويب Actions). للنشر الفعلي على المتجرين محتاج تضيف شهادات التوقيع كـ GitHub Secrets — تفاصيل أكتر لما توصل للمرحلة دي.

## الفرق الأمني الأهم عن النظام القديم

كلمات المرور كانت بتتخزن نص عادي في Google Sheets (بما فيها كلمة مرور السوبر أدمن نفسها مكتوبة في الكود). في النظام الجديد بتتخزن مُشفّرة (PBKDF2) ومفيش أي كلمة مرور نص عادي في أي مكان.

## اللي لسه محتاج شغل (مرحلة تانية)

- شاشات: إدارة الطلاب (إضافة/تعديل)، إدارة المعلمين، تعديل/حذف مجمع من لوحة السوبر أدمن، الرسوم البيانية (اتجاه الحضور)، التصدير PDF/Excel.
- ربط حساب Firebase Auth الفعلي لكل معلم بمستند teachers/{id} (حاليًا فيه placeholder في شاشة تسجيل حضور المعلم).
- إشعارات Push حقيقية (FCM) بدل الاعتماد الكامل على واتساب.
- نقل whatsappAccessToken لـ Secret Manager بدل حقل عادي.
- توقيع وتوزيع فعلي على App Store / Google Play بعد ما تجهّز الحسابات.
