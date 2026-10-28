import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// A parsed, offline-ready EPUB.
///
/// This intentionally does not use a rendering engine. It extracts the spine,
/// resolves the package metadata, inlines local images/CSS and hands each
/// chapter to the WebView reader. That keeps the reader small, predictable and
/// fully offline while still honouring the book's own styling.
class EpubBookData {
  final String title;
  final String author;
  final List<EpubChapterData> chapters;

  const EpubBookData({
    required this.title,
    required this.author,
    required this.chapters,
  });
}

class EpubChapterData {
  final String title;
  final String html;

  const EpubChapterData({required this.title, required this.html});
}

class EpubParser {
  static EpubBookData parse(List<int> bytes, {String fallbackTitle = 'EPUB'}) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    final files = <String, ArchiveFile>{};
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = _normalize(file.name);
      if (name.isEmpty) continue;
      files[name] = file;
      files[name.toLowerCase()] = file;
    }

    final containerFile = files['META-INF/container.xml'];
    if (containerFile == null) {
      throw const FormatException(
        'This EPUB is missing META-INF/container.xml.',
      );
    }
    final container = XmlDocument.parse(_decode(containerFile) ?? '');
    final rootfile = _firstDescendant(container, 'rootfile');
    final rootPath = rootfile?.getAttribute('full-path');
    if (rootPath == null || rootPath.trim().isEmpty) {
      throw const FormatException(
        'This EPUB does not declare a package document.',
      );
    }
    final opfPath = _normalize(_decodeUriPath(rootPath));
    final opfFile = files[opfPath] ?? files[opfPath.toLowerCase()];
    if (opfFile == null) {
      throw const FormatException('The EPUB package document is missing.');
    }
    final opf = XmlDocument.parse(_decode(opfFile) ?? '');
    final package = _firstDescendant(opf, 'package');
    if (package == null) {
      throw const FormatException('The EPUB package document is invalid.');
    }

    final metadata = _firstChild(package, 'metadata');
    final title = _cleanText(
      _firstChildText(metadata, 'title') ?? _cleanText(fallbackTitle),
    );
    final authors = <String>[];
    if (metadata != null) {
      for (final creator in _children(metadata, 'creator')) {
        final name = _cleanText(creator.innerText);
        if (name.isNotEmpty && !authors.contains(name)) authors.add(name);
      }
    }

    final manifest = _firstChild(package, 'manifest');
    final items = <String, _ManifestItem>{};
    if (manifest != null) {
      for (final element in _children(manifest, 'item')) {
        final id = element.getAttribute('id');
        final href = element.getAttribute('href');
        if (id == null || href == null) continue;
        items[id] = _ManifestItem(
          id: id,
          href: href,
          mediaType: element.getAttribute('media-type') ?? '',
          properties: element.getAttribute('properties') ?? '',
        );
      }
    }

    final opfDir = p.posix.dirname(opfPath);
    final tocTitles = _readTableOfContents(files, items, opfDir);

    final chapters = <EpubChapterData>[];
    final spine = _firstChild(package, 'spine');
    if (spine != null) {
      for (final reference in _children(spine, 'itemref')) {
        final idref = reference.getAttribute('idref');
        if (idref == null) continue;
        final item = items[idref];
        if (item == null || !_isHtmlItem(item)) continue;
        final path = _resolve(opfDir, item.href);
        final file = files[path] ?? files[path.toLowerCase()];
        if (file == null) continue;
        final raw = _decode(file);
        if (raw == null || raw.trim().isEmpty) continue;
        final prepared = _prepareChapter(raw, path, files);
        if (prepared.trim().isEmpty) continue;
        final chapterTitle =
            tocTitles[path] ??
            tocTitles[path.toLowerCase()] ??
            _extractHtmlTitle(raw);
        chapters.add(
          EpubChapterData(
            title: chapterTitle == null || chapterTitle.trim().isEmpty
                ? 'Chapter ${chapters.length + 1}'
                : _cleanText(chapterTitle),
            html: prepared,
          ),
        );
      }
    }

    // Some malformed EPUBs have no spine. Fall back to the manifest so the
    // book is still readable rather than rejecting the entire file.
    if (chapters.isEmpty) {
      for (final item in items.values) {
        if (!_isHtmlItem(item)) continue;
        final path = _resolve(opfDir, item.href);
        final file = files[path] ?? files[path.toLowerCase()];
        if (file == null) continue;
        final raw = _decode(file);
        if (raw == null || raw.trim().isEmpty) continue;
        final prepared = _prepareChapter(raw, path, files);
        if (prepared.trim().isEmpty) continue;
        chapters.add(
          EpubChapterData(
            title:
                tocTitles[path] ??
                _extractHtmlTitle(raw) ??
                'Chapter ${chapters.length + 1}',
            html: prepared,
          ),
        );
      }
    }

    if (chapters.isEmpty) {
      throw const FormatException(
        'No readable chapters were found. The book may be DRM-protected.',
      );
    }

    return EpubBookData(
      title: title.isEmpty ? fallbackTitle : title,
      author: authors.join(', '),
      chapters: chapters,
    );
  }

  static Map<String, String> _readTableOfContents(
    Map<String, ArchiveFile> files,
    Map<String, _ManifestItem> items,
    String opfDir,
  ) {
    final titles = <String, String>{};
    for (final item in items.values) {
      final isNav =
          item.properties.split(RegExp(r'\s+')).contains('nav') ||
          item.mediaType == 'application/x-dtbncx+xml';
      if (!isNav) continue;
      final path = _resolve(opfDir, item.href);
      final file = files[path] ?? files[path.toLowerCase()];
      if (file == null) continue;
      final source = _decode(file);
      if (source == null) continue;
      try {
        final doc = XmlDocument.parse(source);
        if (item.mediaType == 'application/x-dtbncx+xml' ||
            item.href.toLowerCase().endsWith('.ncx')) {
          for (final point in _descendants(doc, 'navPoint')) {
            final label = _firstDescendant(point, 'navLabel');
            final text = label == null
                ? null
                : _firstDescendantText(label, 'text');
            final content = _firstDescendant(point, 'content');
            final src = content?.getAttribute('src');
            if (text == null || src == null) continue;
            _putTitle(titles, p.posix.dirname(path), src, text);
          }
        } else {
          for (final anchor in _descendants(doc, 'a')) {
            final href = anchor.getAttribute('href');
            final text = _cleanText(anchor.innerText);
            if (href == null || text.isEmpty) continue;
            _putTitle(titles, p.posix.dirname(path), href, text);
          }
        }
      } catch (_) {
        // A broken TOC should never stop the book from opening.
      }
    }
    return titles;
  }

  static void _putTitle(
    Map<String, String> titles,
    String baseDir,
    String href,
    String title,
  ) {
    if (title.trim().isEmpty) return;
    final path = _resolve(baseDir, href);
    titles[path] = _cleanText(title);
    titles[path.toLowerCase()] = _cleanText(title);
  }

  static String _prepareChapter(
    String raw,
    String chapterPath,
    Map<String, ArchiveFile> files,
  ) {
    final styles = <String>[];
    for (final match in RegExp(
      r'<style\b[^>]*>([\s\S]*?)</style>',
      caseSensitive: false,
    ).allMatches(raw)) {
      styles.add(match.group(1) ?? '');
    }

    var html = raw.replaceAllMapped(
      RegExp(r'<link\b[^>]*>', caseSensitive: false),
      (match) {
        final tag = match.group(0) ?? '';
        if (!RegExp(r'stylesheet', caseSensitive: false).hasMatch(tag)) {
          return '';
        }
        final href = _attributeFromTag(tag, 'href');
        if (href == null || href.trim().isEmpty) return '';
        final path = _resolve(p.posix.dirname(chapterPath), href);
        final file = files[path] ?? files[path.toLowerCase()];
        if (file == null) return '';
        final css = _decode(file);
        if (css == null) return '';
        styles.add(_rewriteCssUrls(css, path, files));
        return '';
      },
    );

    html = html.replaceAll(
      RegExp(r'<script\b[^>]*>[\s\S]*?</script>', caseSensitive: false),
      '',
    );
    html = html.replaceAll(
      RegExp(
        r'<(iframe|object|embed)\b[^>]*>[\s\S]*?</\1>',
        caseSensitive: false,
      ),
      '',
    );
    html = html.replaceAll(
      RegExp(r'<(iframe|object|embed)\b[^>]*/?>', caseSensitive: false),
      '',
    );
    html = html.replaceAll(
      RegExp(r'''\s+on[a-z]+\s*=\s*(["']).*?\1''', caseSensitive: false),
      '',
    );
    html = html.replaceAll(
      RegExp(r'\s+on[a-z]+\s*=\s*[^\s>]+', caseSensitive: false),
      '',
    );

    var body =
        RegExp(
          r'<body\b[^>]*>([\s\S]*?)</body>',
          caseSensitive: false,
        ).firstMatch(html)?.group(1) ??
        html;
    body = body.replaceAll(RegExp(r'<base\b[^>]*>', caseSensitive: false), '');
    body = body.replaceAll(
      RegExp(r'''\bsrcset\s*=\s*(["']).*?\1''', caseSensitive: false),
      '',
    );
    body = body.replaceAllMapped(
      RegExp(
        r'''(<img\b[^>]*?\bsrc\s*=\s*["'])([^"']+)(["'])''',
        caseSensitive: false,
      ),
      (match) =>
          '${match.group(1)}${_dataUri(match.group(2) ?? '', chapterPath, files)}${match.group(3)}',
    );
    body = body.replaceAllMapped(
      RegExp(
        r'''(<image\b[^>]*?\b(?:xlink:)?href\s*=\s*["'])([^"']+)(["'])''',
        caseSensitive: false,
      ),
      (match) =>
          '${match.group(1)}${_dataUri(match.group(2) ?? '', chapterPath, files)}${match.group(3)}',
    );
    body = body.replaceAll(
      RegExp(r'<(?:html|head)\b[^>]*>|</(?:html|head)>', caseSensitive: false),
      '',
    );
    body = body.replaceAll(
      RegExp(r'</?(?:body)\b[^>]*>', caseSensitive: false),
      '',
    );
    body = _expandSelfClosingElements(body);

    final css = styles
        .where((style) => style.trim().isNotEmpty)
        .map((style) => '<style>${_sanitizeCss(style)}</style>')
        .join('\n');
    return '$css<div class="epub-content">$body</div>';
  }

  static String _rewriteCssUrls(
    String css,
    String cssPath,
    Map<String, ArchiveFile> files,
  ) {
    var result = css.replaceAll(
      RegExp(r'@import\b[^;]+;', caseSensitive: false),
      '',
    );
    result = result.replaceAllMapped(
      RegExp(r'''url\(\s*(["']?)(.*?)\1\s*\)''', caseSensitive: false),
      (match) {
        final value = (match.group(2) ?? '').trim();
        if (value.isEmpty || value.startsWith('data:')) {
          return match.group(0) ?? '';
        }
        return 'url("${_dataUri(value, cssPath, files)}")';
      },
    );
    return result;
  }

  static String _dataUri(
    String source,
    String basePath,
    Map<String, ArchiveFile> files,
  ) {
    final value = source.trim();
    if (value.isEmpty || value.startsWith('data:') || value.startsWith('#')) {
      return source;
    }
    if (value.startsWith('http://') ||
        value.startsWith('https://') ||
        value.startsWith('//')) {
      // Do not silently fetch remote tracking images in a local reader.
      return _transparentPixel;
    }
    final path = _resolve(p.posix.dirname(basePath), value);
    final file = files[path] ?? files[path.toLowerCase()];
    if (file == null) return value;
    final content = file.content;
    if (content is! List<int>) return value;
    return 'data:${_mimeType(path)};base64,${base64Encode(content)}';
  }

  /// EPUB chapters are XHTML, where `<a id="..."/>` is a valid empty anchor.
  /// The WebView parses the prepared chapter as HTML, where that same tag is
  /// an opening anchor and would swallow the rest of the chapter (including
  /// making all following text look like a link). Expand self-closing
  /// non-void elements so the HTML parser sees an explicit closing tag.
  static String _expandSelfClosingElements(String html) {
    const tags =
        'a|abbr|address|article|aside|audio|b|bdi|bdo|blockquote|button|'
        'caption|cite|code|colgroup|data|dd|del|details|dfn|dialog|div|dl|'
        'dt|em|fieldset|figcaption|figure|footer|form|h1|h2|h3|h4|h5|h6|'
        'header|hgroup|i|label|legend|li|main|mark|nav|ol|p|picture|pre|q|'
        'rp|rt|ruby|s|samp|section|small|span|strong|sub|summary|sup|table|'
        'tbody|td|tfoot|th|thead|time|title|tr|u|ul|var|video';
    return html.replaceAllMapped(
      RegExp('<(?:$tags)\\b[^>]*?/>', caseSensitive: false),
      (match) {
        final tag = match.group(0)!;
        final name = RegExp(r'^<([A-Za-z0-9]+)').firstMatch(tag)!.group(1)!;
        final attributes = tag
            .substring(1 + name.length, tag.length - 2)
            .trimRight();
        return '<$name$attributes></$name>';
      },
    );
  }

  static String _sanitizeCss(String css) {
    return css
        .replaceAll(RegExp(r'expression\s*\(', caseSensitive: false), '')
        .replaceAll(RegExp(r'javascript\s*:', caseSensitive: false), '');
  }

  static String? _extractHtmlTitle(String html) {
    final match = RegExp(
      r'<title\b[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return null;
    final title = _cleanText(match.group(1) ?? '');
    return title.isEmpty ? null : title;
  }

  static bool _isHtmlItem(_ManifestItem item) {
    final type = item.mediaType.toLowerCase();
    if (type == 'application/xhtml+xml' ||
        type == 'text/html' ||
        type == 'application/xml') {
      return true;
    }
    return item.href.toLowerCase().endsWith('.xhtml') ||
        item.href.toLowerCase().endsWith('.html') ||
        item.href.toLowerCase().endsWith('.htm');
  }

  static String _resolve(String baseDir, String href) {
    final withoutFragment = href.split('#').first.split('?').first;
    final decoded = _decodeUriPath(withoutFragment);
    return _normalize(p.posix.join(baseDir, decoded));
  }

  static String _normalize(String value) {
    var path = value.replaceAll('\\', '/');
    final parts = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (parts.isNotEmpty) parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    return parts.join('/');
  }

  static String _decodeUriPath(String value) {
    try {
      return Uri.decodeFull(value);
    } catch (_) {
      return value;
    }
  }

  static String? _decode(ArchiveFile file) {
    final content = file.content;
    if (content is List<int>) {
      try {
        final decoded = utf8.decode(content, allowMalformed: true);
        return decoded.startsWith('\uFEFF') ? decoded.substring(1) : decoded;
      } catch (_) {
        return null;
      }
    }
    return content?.toString();
  }

  static String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _attributeFromTag(String tag, String name) {
    final match = RegExp(
      '\\b${RegExp.escape(name)}\\s*=\\s*(["\'])(.*?)\\1',
      caseSensitive: false,
    ).firstMatch(tag);
    return match?.group(2);
  }

  static XmlElement? _firstDescendant(XmlNode node, String localName) {
    for (final element in node.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  static Iterable<XmlElement> _descendants(XmlNode node, String localName) {
    return node.descendants.whereType<XmlElement>().where(
      (element) => element.name.local == localName,
    );
  }

  static XmlElement? _firstChild(XmlElement? node, String localName) {
    if (node == null) return null;
    for (final child in node.childElements) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  static Iterable<XmlElement> _children(
    XmlElement? node,
    String localName,
  ) sync* {
    if (node == null) return;
    for (final child in node.childElements) {
      if (child.name.local == localName) yield child;
    }
  }

  static String? _firstChildText(XmlElement? node, String localName) {
    final child = _firstChild(node, localName);
    return child == null ? null : child.innerText;
  }

  static String? _firstDescendantText(XmlNode node, String localName) {
    final element = _firstDescendant(node, localName);
    return element == null ? null : element.innerText;
  }

  static String _mimeType(String path) {
    switch (p.posix.extension(path).toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.svg':
        return 'image/svg+xml';
      case '.bmp':
        return 'image/bmp';
      case '.woff':
        return 'font/woff';
      case '.woff2':
        return 'font/woff2';
      case '.ttf':
        return 'font/ttf';
      case '.otf':
        return 'font/otf';
      default:
        return 'application/octet-stream';
    }
  }

  static const String _transparentPixel =
      'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==';
}

class _ManifestItem {
  final String id;
  final String href;
  final String mediaType;
  final String properties;

  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    required this.properties,
  });
}
