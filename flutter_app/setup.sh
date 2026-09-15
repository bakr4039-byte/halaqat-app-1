#!/usr/bin/env bash
# ============================================================
# سكريبت تجهيز مشروع Flutter — يُشغَّل مرة واحدة على جهازك (أو داخل CI)
# بعد تثبيت Flutter SDK بشكل طبيعي (https://docs.flutter.dev/get-started/install)
#
# ليه محتاجين السكريبت ده؟
# ملفات android/ و ios/ (مشروع Xcode/Gradle الكامل) بتتولّد تلقائيًا
# بأداة `flutter create` ومفيهاش قيمة تُكتب يدويًا سطر بسطر — فبدل كده
# السكريبت بيولّدها لك، وبعدين يحط كود Dart (lib/ + pubspec.yaml)
# اللي جاهز فوق المشروع المُولَّد.
# ============================================================
set -euo pipefail

if ! command -v flutter &> /dev/null; then
  echo "لازم تثبت Flutter SDK الأول: https://docs.flutter.dev/get-started/install"
  exit 1
fi

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"

echo "==> توليد هيكل المشروع الأصلي (android/ios) في مجلد مؤقت..."
flutter create --org com.halaqat --project-name halaqat_app "$TMP_DIR/scaffold"

echo "==> نقل android/ و ios/ للمشروع الحالي..."
cp -R "$TMP_DIR/scaffold/android" "$APP_DIR/"
cp -R "$TMP_DIR/scaffold/ios" "$APP_DIR/"
rm -rf "$TMP_DIR"

echo "==> تثبيت الحزم..."
cd "$APP_DIR"
flutter pub get

cat <<'EOF'

==> تم! الخطوات الجاية:
  1) ثبّت flutterfire CLI:
       dart pub global activate flutterfire_cli
  2) اربط المشروع بحساب Firebase بتاعك (لازم يكون عامل firebase init الأول
     في مجلد halaqat-app/ الرئيسي):
       flutterfire configure --project=<your-firebase-project-id>
     الأمر ده هيستبدل lib/firebase_options.dart تلقائيًا بالقيم الصحيحة.
  3) جرّب التطبيق:
       flutter run
  4) لبناء نسخة أندرويد:
       flutter build apk --release
     (بناء آيفون محتاج Mac أو GitHub Actions — راجع ../.github/workflows/build.yml)
EOF
