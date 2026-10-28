import 'dart:io';

/// Small, dependency-free format sniffer used by the universal file viewer.
///
/// Extension-based routing is still the primary path. This is deliberately a
/// final safety net for files that are misnamed, exported by a scanner, or
/// arrive without a useful extension.
enum FileSignature {
  pdf,
  zip,
  png,
  jpeg,
  gif,
  webp,
  bmp,
  legacyOffice,
  text,
  empty,
  unknown,
}

class FileTypeDetector {
  static Future<FileSignature> detect(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open(mode: FileMode.read);
      final bytes = await handle.read(32);
      return _fromBytes(bytes);
    } catch (_) {
      return FileSignature.unknown;
    } finally {
      await handle?.close();
    }
  }

  static FileSignature _fromBytes(List<int> bytes) {
    if (bytes.isEmpty) return FileSignature.empty;
    if (_startsWith(bytes, const [0x25, 0x50, 0x44, 0x46, 0x2d])) {
      return FileSignature.pdf; // %PDF-
    }
    if (_startsWith(bytes, const [0x50, 0x4b, 0x03, 0x04]) ||
        _startsWith(bytes, const [0x50, 0x4b, 0x05, 0x06]) ||
        _startsWith(bytes, const [0x50, 0x4b, 0x07, 0x08])) {
      return FileSignature.zip;
    }
    if (_startsWith(bytes, const [0x89, 0x50, 0x4e, 0x47])) {
      return FileSignature.png;
    }
    if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) {
      return FileSignature.jpeg;
    }
    if (_startsWith(bytes, const [0x47, 0x49, 0x46, 0x38])) {
      return FileSignature.gif;
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return FileSignature.webp;
    }
    if (_startsWith(bytes, const [0x42, 0x4d])) {
      return FileSignature.bmp;
    }
    if (_startsWith(bytes, const [
      0xd0,
      0xcf,
      0x11,
      0xe0,
      0xa1,
      0xb1,
      0x1a,
      0xe1,
    ])) {
      return FileSignature.legacyOffice;
    }
    if (_looksLikeText(bytes)) return FileSignature.text;
    return FileSignature.unknown;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static bool _looksLikeText(List<int> bytes) {
    for (final byte in bytes) {
      if (byte == 0) return false;
      if (byte == 9 || byte == 10 || byte == 13) continue;
      if (byte < 32) return false;
    }
    return true;
  }

  static String label(FileSignature signature) {
    switch (signature) {
      case FileSignature.pdf:
        return 'PDF';
      case FileSignature.zip:
        return 'ZIP-based document (Office/EPUB)';
      case FileSignature.png:
        return 'PNG image';
      case FileSignature.jpeg:
        return 'JPEG image';
      case FileSignature.gif:
        return 'GIF image';
      case FileSignature.webp:
        return 'WebP image';
      case FileSignature.bmp:
        return 'BMP image';
      case FileSignature.legacyOffice:
        return 'legacy Office document (OLE)';
      case FileSignature.text:
        return 'text';
      case FileSignature.empty:
        return 'empty file';
      case FileSignature.unknown:
        return 'unknown binary format';
    }
  }
}
