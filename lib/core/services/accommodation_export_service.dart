// lib/core/services/accommodation_export_service.dart

// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:app/core/services/file_saver.dart';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../api/admin_accommodation_api.dart';

// ─── Column definitions ───────────────────────────────────────────────────────

const _kHeaders = [
  'Business Name',
  'Trade Name',
  'Business Line',
  'Business Type',
  'Incharge First Name',
  'Incharge Middle Name',
  'Incharge Last Name',
  'Office Street',
  'Office Region',
  'Office Province',
  'Office Municipality',
  'Office Barangay',
  'Requestor Mobile No.',
];

const _kColWidths = <double>[
  22, 18, 20, 20,   // Name, Trade Name, Line, Type
  15, 15, 15,       // First, Middle, Last
  20, 18, 16, 20, 14, // Street, Region, Province, Mun, Brgy
  18,               // Phone
];

const _kPdfColWidths = <int, pw.TableColumnWidth>{
  0:  pw.FlexColumnWidth(2.2),  // Business Name
  1:  pw.FlexColumnWidth(1.8),  // Trade Name
  2:  pw.FlexColumnWidth(2.0),  // Business Line
  3:  pw.FlexColumnWidth(2.0),  // Business Type
  4:  pw.FlexColumnWidth(1.4),  // First
  5:  pw.FlexColumnWidth(1.4),  // Middle
  6:  pw.FlexColumnWidth(1.4),  // Last
  7:  pw.FlexColumnWidth(2.0),  // Street
  8:  pw.FlexColumnWidth(1.8),  // Region
  9:  pw.FlexColumnWidth(1.5),  // Province
  10: pw.FlexColumnWidth(2.0),  // Municipality
  11: pw.FlexColumnWidth(1.4),  // Barangay
  12: pw.FlexColumnWidth(1.8),  // Phone
};

// ─── Export service ───────────────────────────────────────────────────────────

class AccommodationExportService {
  const AccommodationExportService._();

  static List<String> _rowOf(AccommodationExportRow r) => [
        r.businessName,
        r.tradeName,
        r.businessLine,
        r.businessType,
        r.ownerFirstName,
        r.ownerMiddleName,
        r.ownerLastName,
        r.street,
        r.region,
        r.province,
        r.cityMunicipality,
        r.barangay,
        r.phone,
      ];

  // ── Excel ──────────────────────────────────────────────────────────────────

  static Future<void> exportToExcel(
    List<AccommodationExportRow> data,
    BuildContext context,
  ) async {
    try {
    final excel = Excel.createExcel();
      excel.rename('Sheet1', 'Accommodations'); // Rename the default sheet instead of deleting it
      final sheet = excel['Accommodations'];

      // ── Header row ──────────────────────────────────────────────────────
      final headerStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.fromHexString('#164E63'),
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

      for (var col = 0; col < _kHeaders.length; col++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0),
        );
        cell.value = TextCellValue(_kHeaders[col]);
        cell.cellStyle = headerStyle;
      }
      sheet.setRowHeight(0, 30);

      // ── Column widths ────────────────────────────────────────────────────
      for (var i = 0; i < _kColWidths.length; i++) {
        sheet.setColumnWidth(i, _kColWidths[i]);
      }

      // ── Data rows ────────────────────────────────────────────────────────
      for (var row = 0; row < data.length; row++) {
        final values = _rowOf(data[row]);
        final isStripe = row.isOdd;

        final rowStyle = isStripe
            ? CellStyle(
                fontSize: 9,
                backgroundColorHex: ExcelColor.fromHexString('#F0F9FF'),
                verticalAlign: VerticalAlign.Center,
              )
            : CellStyle(
                fontSize: 9,
                verticalAlign: VerticalAlign.Center,
              );

        for (var col = 0; col < values.length; col++) {
          final cell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1),
          );
          cell.value = TextCellValue(values[col]);
          cell.cellStyle = rowStyle;
        }
        sheet.setRowHeight(row + 1, 16);
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Failed to encode Excel file.');

      final fileName = _buildFileName('xlsx');
      final path = await _saveToDevice(fileName, bytes);
      if (path == null) throw Exception('Failed to save file to device.');

      if (!kIsWeb) {
        await OpenFile.open(path);
      }

      _showSnack(
        context,
        'Excel saved:\n$path',
      );
    } catch (e) {
      debugPrint('❌ Excel export error: $e');
      if (context.mounted) _showSnack(context, 'Export failed: $e', error: true);
    }
  }

  // ── PDF ────────────────────────────────────────────────────────────────────

  static Future<void> exportToPdf(
    List<AccommodationExportRow> data,
    BuildContext context,
  ) async {
    try {
      final doc  = pw.Document();
      final font     = pw.Font.helvetica();
      final fontBold = pw.Font.helveticaBold();
      final genDate  = _fmtDateTime(DateTime.now());

      final tableRows = data.map(_rowOf).toList();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Accommodations Report',
                style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 13,
                  color: PdfColor.fromHex('#164E63'),
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Generated: $genDate',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 7.5,
                  color: PdfColors.grey600,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(color: PdfColors.grey400, thickness: 0.5),
              pw.SizedBox(height: 4),
            ],
          ),
          footer: (ctx) => pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.Text(
                  'Page ${ctx.pageNumber} / ${ctx.pagesCount}',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 7,
                    color: PdfColors.grey500,
                  ),
                ),
              ],
            ),
          ),
          build: (_) => [
            pw.TableHelper.fromTextArray(
              headers: _kHeaders,
              data: tableRows,
              border: pw.TableBorder.all(
                color: PdfColors.grey300,
                width: 0.4,
              ),
              headerStyle: pw.TextStyle(
                font: fontBold,
                fontSize: 7,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#164E63'),
              ),
              oddRowDecoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F0F9FF'),
              ),
              cellStyle: pw.TextStyle(font: font, fontSize: 6.5),
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 3,
              ),
              columnWidths: _kPdfColWidths,
            ),
          ],
        ),
      );

      final pdfBytes = await doc.save();
      final fileName = _buildFileName('pdf');
      final path = await _saveToDevice(fileName, pdfBytes);
      if (path == null) throw Exception('Failed to save file to device.');

      if (!context.mounted) return;

      if (!kIsWeb) {
        await OpenFile.open(path);
      }

      _showSnack(
        context,
        'PDF saved:\n$path',
      );
    } catch (e) {
      debugPrint('❌ PDF export error: $e');
      if (context.mounted) {
        _showSnack(context, 'PDF export failed: $e', error: true);
      }
    }
  }

  // ── File saving ────────────────────────────────────────────────────────────

  static Future<String?> _saveToDevice(
    String fileName,
    List<int> bytes,
  ) async {
    if (kIsWeb) {
      try {
        return await saveFileToDownloads(fileName, bytes);
      } catch (e) {
        debugPrint('❌ web save failed: $e');
        return null;
      }
    }
    Future<String?> tryWrite(String dirPath) async {
      try {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) dir.createSync(recursive: true);
        final path = '$dirPath/$fileName';
        await File(path).writeAsBytes(bytes);
        return path;
      } catch (_) {
        return null;
      }
    }

    try {
      if (Platform.isAndroid) {
        // Try public Downloads first, fall back to app-scoped external storage
        return await tryWrite('/storage/emulated/0/Download') ??
            await tryWrite(
              (await getExternalStorageDirectory())?.path ??
                  (await getApplicationDocumentsDirectory()).path,
            );
      } else if (Platform.isIOS) {
        return await tryWrite((await getApplicationDocumentsDirectory()).path);
      } else {
        return await tryWrite(
          (await getDownloadsDirectory())?.path ??
              (await getApplicationDocumentsDirectory()).path,
        );
      }
    } catch (e) {
      debugPrint('❌ _saveToDevice error: $e');
      return null;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _buildFileName(String ext) {
    final n = DateTime.now();
    return 'accommodations_'
        '${n.year}${_p(n.month)}${_p(n.day)}'
        '_${_p(n.hour)}${_p(n.minute)}.$ext';
  }

  static String _p(int v) => v.toString().padLeft(2, '0');

  static String _fmtDateTime(DateTime dt) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[dt.month]} ${dt.day}, ${dt.year}  ${_p(dt.hour)}:${_p(dt.minute)}';
  }

  static void _showSnack(
    BuildContext context,
    String msg, {
    bool error = false,
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            error ? const Color(0xFFFF4D6A) : const Color(0xFF0E7490),
        action: action,
        duration: Duration(seconds: error ? 4 : 8),
      ),
    );
  }
}