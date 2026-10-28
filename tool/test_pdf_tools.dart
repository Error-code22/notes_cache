import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pdf_manipulator/io.dart';
import 'package:pdf_manipulator/pdf_manipulator.dart';

Future<void> main() async {
  final source = File(
    p.join(
      Directory.current.path,
      'linux',
      'flutter',
      'ephemeral',
      '.plugin_symlinks',
      'file_picker',
      'test',
      'test_files',
      'test.pdf',
    ),
  );
  final dir = await Directory.systemTemp.createTemp('foluma_pdf_tools_');
  final work = await source.copy(p.join(dir.path, 'work.pdf'));
  final output = File(p.join(dir.path, 'output.pdf'));

  final pdf = Pdf();
  PdfEditor? editor;
  FileSink? sink;
  try {
    editor = await pdf.edit(FileSource(work));
    await editor.rotatePage(0, degrees: 90);
    await editor.deletePage(1);
    sink = await FileSink.create(output);
    await editor.save(sink);
    await sink.close();
    sink = null;
    await editor.dispose();
    editor = null;
  } finally {
    await sink?.close();
    await editor?.dispose();
  }

  final check = await pdf.open(FileSource(output));
  print('output pages: ${check.pageCount}');
  print('output bytes: ${await output.length()}');
  await check.dispose();
  await pdf.dispose();
  print('ok: ${dir.path}');
}
