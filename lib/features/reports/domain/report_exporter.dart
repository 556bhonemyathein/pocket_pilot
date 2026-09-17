import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/extensions/date_time_extensions.dart';
import '../../../core/utils/result.dart';
import '../../../shared/models/category.dart';
import '../../../shared/models/transaction.dart';

/// Turns a set of transactions into a shareable CSV or PDF file.
///
/// Lives in `domain/` and takes plain data because export is a pure
/// transformation: no providers, no context, no I/O beyond writing the file.
/// That makes it directly unit-testable, which matters — a broken CSV escape
/// is the kind of bug that silently corrupts someone's records.
class ReportExporter {
  const ReportExporter();

  /// RFC 4180 CSV. Fields containing a comma, quote or newline are quoted and
  /// internal quotes are doubled — the rule spreadsheets actually expect.
  Future<Result<File>> toCsv({required List<Transaction> transactions, required Map<String, Category> categories, required String fileName}) =>
      guard(() async {
        final StringBuffer buffer = StringBuffer()..writeln('Date,Type,Category,Amount,Currency,Note,Tags,Transfer To,Recurring');

        for (final Transaction t in transactions) {
          final Category category = categories[t.categoryId] ?? Category.unknown;
          buffer.writeln(
            <String>[
              t.date.isoDate,
              t.type.label,
              category.name,
              t.amount.toStringAsFixed(2),
              t.currencyCode,
              t.note,
              t.tags.join('; '),
              t.transferTo ?? '',
              t.recurrence.label,
            ].map(_escapeCsv).join(','),
          );
        }

        return _write('$fileName.csv', buffer.toString());
      });

  static String _escapeCsv(String value) {
    final bool needsQuoting = value.contains(',') || value.contains('"') || value.contains('\n');
    if (!needsQuoting) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  /// A printable summary: totals, category breakdown and the full ledger.
  Future<Result<File>> toPdf({
    required List<Transaction> transactions,
    required Map<String, Category> categories,
    required String title,
    required String subtitle,
    required String currencyCode,
    required String fileName,
    pw.Font? regularFont,
    pw.Font? boldFont,
  }) => guard(() async {
    final pw.ThemeData theme = regularFont != null && boldFont != null
        ? pw.ThemeData.withFont(base: regularFont, bold: boldFont)
        : regularFont != null
        ? pw.ThemeData.withFont(base: regularFont)
        : pw.ThemeData.base();

    final pw.Document document = pw.Document(theme: theme);

    final double income = transactions.where((Transaction t) => t.type.sign > 0).fold<double>(0, (double sum, Transaction t) => sum + t.amount);
    final double expense = transactions.where((Transaction t) => t.type.sign < 0).fold<double>(0, (double sum, Transaction t) => sum + t.amount);

    String money(double value) => '$currencyCode ${value.toStringAsFixed(2)}';

    final String safeTitle = title.replaceAll('·', '-');
    final String safeSubtitle = subtitle.replaceAll('→', '->').replaceAll('·', '-');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Text(safeTitle, style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text(safeSubtitle, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
            pw.Divider(),
          ],
        ),
        footer: (pw.Context context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount} - '
            'PocketPilot',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (pw.Context context) => <pw.Widget>[
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: <pw.Widget>[
              _summaryTile('Income', money(income), PdfColors.green700),
              _summaryTile('Expenses', money(expense), PdfColors.red700),
              _summaryTile('Net', money(income - expense), PdfColors.blue700),
            ],
          ),
          pw.SizedBox(height: 20),

          pw.Text('Transactions (${transactions.length})', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: <String>['Date', 'Category', 'Type', 'Note', 'Amount'],
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellAlignments: const <int, pw.Alignment>{4: pw.Alignment.centerRight},
            data: transactions
                .map(
                  (Transaction t) => <String>[
                    t.date.isoDate,
                    (categories[t.categoryId] ?? Category.unknown).name,
                    t.type.label,
                    t.note,
                    '${t.type.sign < 0 ? '-' : ''}${t.amount.toStringAsFixed(2)}',
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );

    return _write('$fileName.pdf', null, bytes: await document.save());
  });

  static pw.Widget _summaryTile(String label, String value, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  /// Writes to the temp directory: exports are transient artefacts handed
  /// straight to the share sheet, not something to accumulate in app storage.
  static Future<File> _write(String name, String? contents, {List<int>? bytes}) async {
    final Directory directory = await getTemporaryDirectory();
    final File file = File('${directory.path}/$name');
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(contents ?? '');
    }
    return file;
  }
}
