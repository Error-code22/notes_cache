import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'office_pptx.dart';

/// Converts a PPTX file to a PDF blob (bytes).
///
/// Faithful port of the web pptx-to-pdf.ts converter:
/// - Landscape 16:9 pages (280×157.5mm)
/// - Header with title + page number
/// - Images stacked/side-by-side
/// - Text body with first line larger as title stand-in
class PptxToPdf {
  /// Convert a .pptx/.ppsx file to PDF bytes.
  ///
  /// [file] is the source PPTX file on disk.
  /// [title] is used as the document title and header label.
  /// Returns raw PDF bytes suitable for writing to disk or uploading.
  static Future<Uint8List> convert(File file, {String? title}) async {
    final slides = await PptxService.readSlidesWithImages(file);
    if (slides.isEmpty) throw Exception('No slides found in PPTX');

    final doc = pw.Document();
    final slideTitle = title ?? file.uri.pathSegments.last.replaceAll(RegExp(r'\.pptx?$'), '');

    // Landscape 16:9 in points (1pt = 1/72 inch)
    const pageW = 840.0; // 280mm in pt
    const pageH = 472.5; // 157.5mm in pt
    const margin = 34.0; // ~12mm
    final pageFormat = PdfPageFormat(pageW, pageH);

    for (var i = 0; i < slides.length; i++) {
      final s = slides[i];

      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          margin: pw.EdgeInsets.all(margin),
          build: (context) => _buildSlide(s, i, slides.length, slideTitle, pageW, pageH, margin),
        ),
      );
    }

    return doc.save();
  }

  static pw.Widget _buildSlide(
    PptxSlide slide,
    int index,
    int total,
    String title,
    double pageW,
    double pageH,
    double margin,
  ) {
    final usableW = pageW - margin * 2;
    final children = <pw.Widget>[];

    // Header: "Title  ·  1/N"
    children.add(
      pw.Text(
        '$title  ·  ${index + 1}/$total',
        style: pw.TextStyle(
          fontSize: 9,
          color: PdfColors.grey,
        ),
      ),
    );
    children.add(pw.SizedBox(height: 12));

    // Images (up to 3, stacked vertically)
    for (final imgBytes in slide.images.take(3)) {
      try {
        final image = _decodeImage(imgBytes);
        if (image != null) {
          // Scale to fit within usable width, max 165pt tall (55mm)
          final maxW = usableW;
          final maxH = 165.0;
          final imgW = image.width?.toDouble() ?? 100.0;
          final imgH = image.height?.toDouble() ?? 100.0;
          final scale = min(min(maxW / imgW, maxH / imgH), 1.0);
          final w = imgW * scale;
          final h = imgH * scale;
          children.add(pw.SizedBox(
            width: w,
            height: h,
            child: pw.Image(image),
          ));
          children.add(pw.SizedBox(height: 6));
        }
      } catch (_) {
        // Skip undecodable images
      }
    }

    // Text body
    if (slide.texts.isEmpty) {
      children.add(pw.Text(
        '(no text on this slide)',
        style: pw.TextStyle(fontSize: 11, color: PdfColors.grey400),
      ));
    } else {
      // First line larger as title stand-in
      children.add(pw.Text(
        slide.texts.first,
        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
      ));
      children.add(pw.SizedBox(height: 6));

      // Remaining text
      for (final line in slide.texts.skip(1)) {
        children.add(pw.Text(
          line,
          style: const pw.TextStyle(fontSize: 11),
        ));
      }
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: children,
    );
  }

  /// Decode raw image bytes into a pw.ImageProvider.
  static pw.ImageProvider? _decodeImage(Uint8List bytes) {
    // Try to detect format by magic bytes
    if (bytes.length < 4) return null;

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
      return pw.MemoryImage(bytes);
    }

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
      return pw.MemoryImage(bytes);
    }

    // GIF: 47 49 46 38
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) {
      return pw.MemoryImage(bytes);
    }

    // WEBP: 52 49 46 46 ... 57 45 42 50
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes.length >= 12 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return pw.MemoryImage(bytes);
    }

    // Unknown format — try as JPEG (most common fallback)
    return pw.MemoryImage(bytes);
  }
}
