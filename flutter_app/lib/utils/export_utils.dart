import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

/// أدوات تصدير موحّدة (PDF / Excel) تُستخدم في: كشف الحضور الأسبوعي، مسير
/// الرواتب الشهري، السجل الإجمالي الكامل، تصدير الطلاب، تصدير سجل التحفيز
/// ولوحة الشرف — تقابل كل أزرار "تصدير PDF" و"تصدير Excel" و"طباعة" بالمواصفات.

pw.Font? _arabicFontCache;
pw.Font? _arabicBoldFontCache;

Future<void> _ensureArabicFont() async {
  _arabicFontCache ??= await PdfGoogleFonts.notoNaskhArabicRegular();
  _arabicBoldFontCache ??= await PdfGoogleFonts.notoNaskhArabicBold();
}

/// يبني ويعرض/يشارك مستند PDF لجدول بعنوان ورؤوس أعمدة وصفوف بيانات —
/// نص عربي كامل من اليمين لليسار.
Future<void> exportTablePdf({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
  String fileName = 'export.pdf',
  String? subtitle,
}) async {
  await _ensureArabicFont();
  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: _arabicFontCache, bold: _arabicBoldFontCache),
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Center(
          child: pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        ),
        if (subtitle != null) ...[
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 12))),
        ],
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.center,
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}

/// يفتح معاينة/طباعة مباشرة (زر "طباعة") بدل المشاركة فقط.
Future<void> printTablePdf({
  required String title,
  required List<String> headers,
  required List<List<String>> rows,
  String? subtitle,
}) async {
  await _ensureArabicFont();
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: _arabicFontCache, bold: _arabicBoldFontCache),
      pageFormat: PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Center(child: pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold))),
        if (subtitle != null) ...[
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(subtitle, style: const pw.TextStyle(fontSize: 12))),
        ],
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: rows,
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellAlignment: pw.Alignment.centerRight,
          headerAlignment: pw.Alignment.center,
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green100),
        ),
      ],
    ),
  );
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}

/// يبني ملف Excel (xlsx) من رؤوس وصفوف ويشاركه.
Future<void> exportTableExcel({
  required String sheetTitle,
  required List<String> headers,
  required List<List<String>> rows,
  String fileName = 'export.xlsx',
}) async {
  final workbook = xls.Excel.createExcel();
  final xls.Sheet sheet = workbook[sheetTitle];
  workbook.setDefaultSheet(sheetTitle);

  sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());
  for (final row in rows) {
    sheet.appendRow(row.map((c) => xls.TextCellValue(c)).toList());
  }

  final bytes = workbook.save();
  if (bytes == null) return;

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(Uint8List.fromList(bytes), flush: true);
  await Share.shareXFiles([XFile(file.path)], text: sheetTitle);
}

/// يقرأ ملف Excel (xlsx) مُختار من الجهاز ويرجّع صفوفه كنص — يُستخدم في
/// "استيراد من إكسل" (بيانات الطلاب). الصف الأول يُعتبر رؤوس الأعمدة.
List<List<String>> readExcelRows(Uint8List bytes) {
  final workbook = xls.Excel.decodeBytes(bytes);
  if (workbook.tables.isEmpty) return [];
  final sheet = workbook.tables.values.first;
  return sheet.rows.map((row) {
    return row.map((cell) => cell?.value?.toString() ?? '').toList();
  }).toList();
}
