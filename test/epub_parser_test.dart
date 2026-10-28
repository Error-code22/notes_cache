import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_cache/readers/epub_parser.dart';

void main() {
  test('parses EPUB metadata, spine, TOC and inlines local images', () {
    final archive = Archive();

    void add(String name, List<int> bytes) {
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    void addText(String name, String text) {
      add(name, utf8.encode(text));
    }

    addText('mimetype', 'application/epub+zip');
    addText('META-INF/container.xml', '''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''');
    addText('OEBPS/content.opf', '''
<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title>
    <dc:creator>Test Author</dc:creator>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="c1" href="Text/chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="img" href="Images/pixel.png" media-type="image/png"/>
  </manifest>
  <spine>
    <itemref idref="c1"/>
  </spine>
</package>
''');
    addText('OEBPS/nav.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<body>
<nav epub:type="toc">
  <ol><li><a href="Text/chapter1.xhtml">Opening chapter</a></li></ol>
</nav>
</body>
</html>
''');
    addText('OEBPS/Text/chapter1.xhtml', '''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Chapter title from file</title></head>
<body>
<a id="chapter-start"/>
<h1>Hello</h1>
<p>Offline reading.</p>
<img src="../Images/pixel.png" alt="pixel"/>
<script>alert(1)</script>
</body>
</html>
''');
    // A one-pixel PNG.
    add('OEBPS/Images/pixel.png', const [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);

    final bytes = ZipEncoder().encode(archive);
    expect(bytes, isNotNull);
    final book = EpubParser.parse(bytes!, fallbackTitle: 'Fallback');

    expect(book.title, 'Test Book');
    expect(book.author, 'Test Author');
    expect(book.chapters, hasLength(1));
    expect(book.chapters.single.title, 'Opening chapter');
    expect(book.chapters.single.html, contains('data:image/png;base64,'));
    expect(book.chapters.single.html, isNot(contains('<script>')));
    // XHTML self-closing anchors must become a real empty anchor when served
    // as HTML, otherwise the parser turns the rest of the chapter into a link.
    expect(
      book.chapters.single.html,
      contains('<a id="chapter-start"></a>'),
    );
    expect(
      book.chapters.single.html,
      isNot(contains('<a id="chapter-start"/>')),
    );
  });
}
