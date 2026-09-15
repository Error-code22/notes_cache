import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Structured slide: text blocks + embedded image bytes.
class PptxSlide {
  final List<String> texts;
  final List<Uint8List> images;
  PptxSlide({required this.texts, required this.images});
}

/// Minimal .pptx viewer: extracts slide text from the zip's XML.
/// No maintained Dart pptx package exists, so we parse it directly.
class PptxService {
  /// True if the file is an OLE2 binary file (old .ppt format).
  /// Old binary decks can't be parsed as zip/XML.
  static Future<bool> isBinaryPpt(File file) async {
    try {
      final raf = await file.open();
      try {
        final header = await raf.read(8);
        const ole2Magic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
        if (header.length < 8) return false;
        for (var i = 0; i < 8; i++) {
          if (header[i] != ole2Magic[i]) return false;
        }
        return true;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Returns a list of slides; each slide is a list of text blocks.
  /// Uses buffer decode — entry contents decompress lazily on access,
  /// so large decks don't exhaust memory on phones.
  static Future<List<List<String>>> readSlides(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBuffer(InputStream(bytes));
    final slides = <List<String>>[];

    // ppt/slides/slide1.xml, slide2.xml ... (fall back to any slide*.xml)
    var slideEntries = archive.files
        .where((e) => e.isFile && e.name.startsWith('ppt/slides/slide') && e.name.endsWith('.xml'))
        .toList();
    if (slideEntries.isEmpty) {
      slideEntries = archive.files
          .where((e) => e.isFile && RegExp(r'/slide\d+\.xml$').hasMatch(e.name) && e.name.endsWith('.xml'))
          .toList();
    }
    slideEntries.sort((a, b) {
      int num(String name) => int.tryParse(RegExp(r'\d+').firstMatch(name)?.group(0) ?? '') ?? 0;
      return num(a.name).compareTo(num(b.name));
    });

    for (final entry in slideEntries) {
      final content = Uint8List.fromList(entry.content);
      final doc = XmlDocument.parse(utf8.decode(content));
      final blocks = <String>[];
      // Namespace-agnostic: some decks use different prefixes for the
      // drawingml text element. Match any element whose local name is 't'.
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 't') {
          final text = el.innerText.trim();
          if (text.isNotEmpty) blocks.add(text);
        }
      }
      slides.add(blocks);
    }
    return slides;
  }

  /// Reads slides with embedded images for PDF conversion.
  static Future<List<PptxSlide>> readSlidesWithImages(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBuffer(InputStream(bytes));

    // Collect all media (images) from ppt/media/
    final media = <String, Uint8List>{};
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final name = entry.name.toLowerCase();
      if (!name.startsWith('ppt/media/')) continue;
      if (name.endsWith('.png') || name.endsWith('.jpg') || name.endsWith('.jpeg') ||
          name.endsWith('.gif') || name.endsWith('.webp') || name.endsWith('.emf') ||
          name.endsWith('.wmf')) {
        media[entry.name] = Uint8List.fromList(entry.content);
      }
    }

    var slideEntries = archive.files
        .where((e) => e.isFile && e.name.startsWith('ppt/slides/slide') && e.name.endsWith('.xml'))
        .toList();
    if (slideEntries.isEmpty) {
      slideEntries = archive.files
          .where((e) => e.isFile && RegExp(r'/slide\d+\.xml$').hasMatch(e.name) && e.name.endsWith('.xml'))
          .toList();
    }
    slideEntries.sort((a, b) {
      int num(String name) => int.tryParse(RegExp(r'\d+').firstMatch(name)?.group(0) ?? '') ?? 0;
      return num(a.name).compareTo(num(b.name));
    });

    final slides = <PptxSlide>[];
    for (final entry in slideEntries) {
      final content = Uint8List.fromList(entry.content);
      final doc = XmlDocument.parse(utf8.decode(content));
      final texts = <String>[];
      final images = <Uint8List>[];

      // Extract text
      for (final el in doc.descendants.whereType<XmlElement>()) {
        if (el.name.local == 't') {
          final text = el.innerText.trim();
          if (text.isNotEmpty) texts.add(text);
        }
      }

      // Extract images via .rels relationships
      final relsPath = entry.name.replaceFirst(
        RegExp(r'slides/slide(\d+)\.xml$'),
        'slides/_rels/slide\$1.xml.rels',
      );
      final relsEntry = archive.files.where((e) => e.name == relsPath).firstOrNull;
      if (relsEntry != null) {
        final relsDoc = XmlDocument.parse(utf8.decode(Uint8List.fromList(relsEntry.content)));
        for (final rel in relsDoc.descendants.whereType<XmlElement>()) {
          final target = rel.getAttribute('Target');
          if (target == null) continue;
          final baseName = target.split('/').last;
          // Find matching media entry
          for (final me in media.entries) {
            if (me.key.endsWith('/$baseName') || me.key == 'ppt/media/$baseName') {
              // Skip EMF/WMF (vector formats jsPDF can't handle)
              final lower = me.key.toLowerCase();
              if (lower.endsWith('.emf') || lower.endsWith('.wmf')) continue;
              images.add(me.value);
              break;
            }
          }
        }
      }

      slides.add(PptxSlide(texts: texts, images: images));
    }
    return slides;
  }

  /// All slide text joined as markdown (slide separators), for viewing/export.
  static Future<String> toMarkdown(File file) async {
    final slides = await readSlides(file);
    return slides
        .asMap()
        .entries
        .map((e) => '--- Slide ${e.key + 1} ---\n${e.value.join('\n')}')
        .join('\n\n');
  }
}
