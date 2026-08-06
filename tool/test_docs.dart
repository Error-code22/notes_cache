import 'dart:io';
import '../lib/editors/office_docx.dart';
import '../lib/editors/office_pptx.dart';

Future<void> main() async {
  final dir = 'C:/Users/DRONER~1/AppData/Local/Temp/opencode';

  final docx = File('$dir/test54.docx');
  try {
    final paras = await DocxService.readParagraphs(docx);
    final totalChars = paras.fold<int>(0, (sum, p) => sum + p.fold<int>(0, (s, r) => s + r.text.length));
    print('DOCX: ${paras.length} paragraphs, $totalChars chars');
    if (paras.isNotEmpty) {
      print('DOCX first para: ${paras.first.map((r) => r.text).join()}');
    }
  } catch (e) {
    print('DOCX ERROR: $e');
  }

  final pptx = File('$dir/test12.pptx');
  final isBinary = await PptxService.isBinaryPpt(pptx);
  print('PPTX isBinaryPpt: $isBinary');
  if (!isBinary) {
    try {
      final slides = await PptxService.readSlides(pptx);
      print('PPTX: ${slides.length} slides');
      for (var i = 0; i < slides.length && i < 3; i++) {
        print('PPTX slide ${i + 1}: ${slides[i].take(3).join(' | ')}');
      }
    } catch (e) {
      print('PPTX ERROR: $e');
    }
  }
}
