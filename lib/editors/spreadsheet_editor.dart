import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';

/// Spreadsheet editor for .xlsx files (read + edit cells + save).
/// `.xls` (old binary format) is not supported by the excel package;
/// those fall through to the text editor in the hub.
class SpreadsheetEditorPage extends StatefulWidget {
  final File file;
  final String title;
  final Future<void> Function(File file)? onSave;

  const SpreadsheetEditorPage({super.key, required this.file, required this.title, this.onSave});

  @override
  State<SpreadsheetEditorPage> createState() => _SpreadsheetEditorPageState();
}

class _SpreadsheetEditorPageState extends State<SpreadsheetEditorPage> {
  Excel? _excel;
  String? _activeSheet;
  List<List<String>> _cells = [];
  bool _loading = true;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheets = excel.tables.keys.toList();
      setState(() {
        _excel = excel;
        _activeSheet = sheets.isNotEmpty ? sheets.first : null;
        _loadSheet();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open spreadsheet: $e'), backgroundColor: Colors.red),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _loadSheet() {
    if (_excel == null || _activeSheet == null) return;
    final sheet = _excel!.tables[_activeSheet];
    if (sheet == null) {
      _cells = [];
      return;
    }
    _cells = [];
    final maxRows = sheet.maxRows;
    final maxCols = sheet.maxColumns;
    for (var r = 0; r < maxRows; r++) {
      final row = <String>[];
      for (var c = 0; c < maxCols; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
        final v = cell.value;
        row.add(v?.toString() ?? '');
      }
      _cells.add(row);
    }
  }

  Future<void> _save() async {
    final excel = _excel;
    final sheetName = _activeSheet;
    if (excel == null || sheetName == null) return;
    final sheet = excel.tables[sheetName];
    if (sheet == null) return;

      for (var r = 0; r < _cells.length; r++) {
        for (var c = 0; c < _cells[r].length; c++) {
          final value = _cells[r][c];
          final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
          if (value.isEmpty) {
            cell.value = null;
          } else {
            final numValue = num.tryParse(value);
            if (numValue is int) {
              cell.value = IntCellValue(numValue);
            } else if (numValue is double) {
              cell.value = DoubleCellValue(numValue);
            } else {
              cell.value = TextCellValue(value);
            }
          }
        }
      }

    final bytes = excel.save();
    if (bytes == null) return;
    await widget.file.writeAsBytes(bytes);
    _dirty = false;
    await widget.onSave?.call(widget.file);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Saved'), backgroundColor: Colors.green),
      );
    }
  }

  void _editCell(int row, int col) {
    final controller = TextEditingController(text: _cells[row][col]);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cell ${_colName(col)}${row + 1}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _cells[row][col] = controller.text.trim();
                _dirty = true;
              });
              Navigator.pop(ctx);
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  String _colName(int col) {
    var c = col;
    var name = '';
    while (c >= 0) {
      name = String.fromCharCode(65 + (c % 26)) + name;
      c = (c ~/ 26) - 1;
    }
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheets = _excel?.tables.keys.toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          if (sheets.length > 1)
            PopupMenuButton<String>(
              icon: const Icon(Icons.grid_view_rounded),
              tooltip: 'Sheets',
              onSelected: (name) => setState(() {
                _activeSheet = name;
                _loadSheet();
              }),
              itemBuilder: (_) => [
                for (final s in sheets) PopupMenuItem(value: s, child: Text(s)),
              ],
            ),
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_outlined),
            onPressed: _dirty ? _save : null,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cells.isEmpty
              ? const Center(child: Text('Empty spreadsheet'))
              : Column(
                  children: [
                    if (_activeSheet != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Sheet: $_activeSheet  •  ${_cells.length} rows',
                              style: theme.textTheme.bodySmall),
                        ),
                      ),
                    const Divider(height: 1),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SingleChildScrollView(
                          child: Table(
                            border: TableBorder.all(color: theme.dividerColor, width: 0.5),
                            defaultColumnWidth: const IntrinsicColumnWidth(),
                            children: [
                              for (var r = 0; r < _cells.length; r++)
                                TableRow(
                                  decoration: r == 0
                                      ? BoxDecoration(color: theme.colorScheme.primary.withOpacity(0.08))
                                      : null,
                                  children: [
                                    for (var c = 0; c < _cells[r].length; c++)
                                      InkWell(
                                        onTap: () => _editCell(r, c),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                          constraints: const BoxConstraints(minWidth: 80),
                                          child: Text(
                                            _cells[r][c],
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: r == 0 ? FontWeight.bold : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      color: theme.colorScheme.primary.withOpacity(0.06),
                      child: const Text('Tap a cell to edit it', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
    );
  }
}
