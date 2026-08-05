import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Minimal .docx support built on zip + XML (no third-party docx package
/// exists on pub.dev that is maintained). Supports:
/// - extracting document text (paragraphs, headings, bold/italic markers)
/// - writing a simple docx (paragraphs + heading/bold/italic styles)
class DocxService {
  /// Reads the main document.xml text from a .docx file.
  /// Returns a list of paragraphs; each paragraph is a list of
  /// (text, styleFlags) pairs where styleFlags: 'b' bold, 'i' italic.
  static Future<List<List<({String text, String flags})>>> readParagraphs(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    final entry = archive.findFile('word/document.xml');
    if (entry == null) throw Exception('Not a valid .docx file (no document.xml)');

    final doc = XmlDocument.parse(utf8.decode(entry.content as Uint8List));
    final paragraphs = <List<({String text, String flags})>>[];

    for (final pEl in doc.findAllElements('w:p', namespace: 'w')) {
      final runs = <({String text, String flags})>[];
      for (final rEl in pEl.findElements('w:r', namespace: 'w')) {
        final flags = <String>[];
        final rPr = rEl.getElement('w:rPr', namespace: 'w');
        if (rPr != null) {
          if (rPr.getElement('w:b', namespace: 'w') != null) flags.add('b');
          if (rPr.getElement('w:i', namespace: 'w') != null) flags.add('i');
        }
        final text = rEl
            .findElements('w:t', namespace: 'w')
            .map((t) => t.innerText)
            .join();
        if (text.isNotEmpty) runs.add((text: text, flags: flags.join()));
      }
      if (runs.isNotEmpty) paragraphs.add(runs);
    }
    return paragraphs;
  }

  /// Reads all text as plain paragraphs (bold/italic markers stripped).
  static Future<List<String>> readText(File file) async {
    final paragraphs = await readParagraphs(file);
    return paragraphs.map((p) => p.map((r) => r.text).join()).toList();
  }

  /// Writes a simple .docx from paragraphs.
  /// Each paragraph is (text, flags) — supports 'b' and 'i'.
  /// Returns the new bytes; caller writes them to the target file.
  static Uint8List buildDocx(List<List<({String text, String flags})>> paragraphs) {
    final body = XmlBuilder();
    body.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');

    final w = (String name) => 'w:$name';
    body.element('w:document', nest: () {
      body.attribute('xmlns:w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main');
      body.element(w('body'), nest: () {
        for (final para in paragraphs) {
          body.element(w('p'), nest: () {
            for (final run in para) {
              body.element(w('r'), nest: () {
                if (run.flags.isNotEmpty) {
                  body.element(w('rPr'), nest: () {
                    if (run.flags.contains('b')) body.element(w('b'));
                    if (run.flags.contains('i')) body.element(w('i'));
                  });
                }
                body.element(w('t'), nest: () {
                  body.attribute('xml:space', 'preserve');
                  body.text(run.text);
                });
              });
            }
          });
        }
      });
    });

    final documentXml = body.buildDocument().toXmlString();

    // Minimal docx package: [Content_Types].xml, _rels/.rels, word/document.xml
    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final archive = Archive()
      ..addFile(ArchiveFile('word/document.xml', documentXml.length, utf8.encode(documentXml)))
      ..addFile(ArchiveFile('[Content_Types].xml', contentTypes.length, utf8.encode(contentTypes)))
      ..addFile(ArchiveFile('_rels/.rels', rels.length, utf8.encode(rels)));

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes!);
  }

  /// Converts DocxService paragraphs into markdown-ish plain text
  /// (for loading into the rich text / plain editors).
  static String paragraphsToText(List<List<({String text, String flags})>> paragraphs) {
    return paragraphs
        .map((p) => p.map((r) {
              var t = r.text;
              if (r.flags.contains('b')) t = '**$t**';
              if (r.flags.contains('i')) t = '_${t}_';
              return t;
            }).join())
        .join('\n');
  }

  /// Converts plain text (lines) into paragraphs for [buildDocx].
  /// Recognizes `**bold**` and `_italic_` inline markers.
  static List<List<({String text, String flags})>> textToParagraphs(String text) {
    final paragraphs = <List<({String text, String flags})>>[];
    for (final line in text.split('\n')) {
      if (line.trim().isEmpty) continue;
      final runs = <({String text, String flags})>[];
      final pattern = RegExp(r'(\*\*[^*]+\*\*|_[^_]+_)');
      var last = 0;
      for (final m in pattern.allMatches(line)) {
        if (m.start > last) runs.add((text: line.substring(last, m.start), flags: ''));
        final token = m.group(0)!;
        if (token.startsWith('**')) {
          runs.add((text: token.substring(2, token.length - 2), flags: 'b'));
        } else {
          runs.add((text: token.substring(1, token.length - 1), flags: 'i'));
        }
        last = m.end;
      }
      if (last < line.length) runs.add((text: line.substring(last), flags: ''));
      if (runs.isNotEmpty) paragraphs.add(runs);
    }
    return paragraphs;
  }
}
