import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'services.dart';
import 'r2_service.dart';
import 'file_viewer_page.dart';

class NoteDetailPage extends StatefulWidget {
  final Note note;

  const NoteDetailPage({super.key, required this.note});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  bool _isLoading = false;
  bool _isSummarizing = false;
  String? _summary;

  @override
  void initState() {
    super.initState();
    _summary = widget.note.summary;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_summary == null || _summary!.isEmpty) {
        unawaited(_generateSummary(silent: true));
      }
    });
  }

  /// Resolves a note's stored file reference to a downloadable URL.
  /// Handles both Cloudinary URLs and legacy bare Google Drive file IDs.
  String _resolveFileUrl() {
    final raw = widget.note.gDriveId?.trim() ?? '';
    if (raw.isEmpty) return '';
    if (raw.contains('://')) return raw;
    // Legacy Google Drive file ID (no URL scheme) -> public download link
    return 'https://drive.google.com/uc?export=download&id=$raw';
  }

  /// Determines the real file extension from the note title first
  /// (Cloudinary URLs usually have no extension), falling back to the URL.
  String _resolveFileExt() {
    final lowerTitle = widget.note.title.toLowerCase();
    final titleMatch = RegExp(r'\.(pdf|docx|doc|pptx|ppt|txt|md|csv|xlsx|xls|jpg|jpeg|png|mp4|mp3|wav|mov|mkv|m4a)$').firstMatch(lowerTitle);
    if (titleMatch != null) return '.${titleMatch.group(1)}';
    final url = _resolveFileUrl();
    if (url.isNotEmpty) {
      final pathParts = Uri.parse(url).path.split('.');
      if (pathParts.length > 1) return '.${pathParts.last}';
    }
    return '.pdf';
  }

  /// Downloads the note file (if needed) and returns the local File.
  Future<File?> _downloadNoteFile() async {
    final url = _resolveFileUrl();
    if (url.isEmpty) return null;
    final noteService = context.read<NoteService>();
    final appDirPath = await noteService.getAppDirectory();
    final file = File('$appDirPath\\ai_doc_${widget.note.id}${_resolveFileExt()}');
    if (!await file.exists()) {
      final response = await http.get(Uri.parse(url));
      debugPrint('Note file fetch [${widget.note.id}]: HTTP ${response.statusCode} from $url');
      if (response.statusCode != 200) {
        if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
          throw Exception('This file is no longer available on the server (HTTP ${response.statusCode}). It may have been removed by the uploader.');
        }
        throw Exception('Could not fetch file from storage (HTTP ${response.statusCode}): $url');
      }
      await file.writeAsBytes(response.bodyBytes);
    }
    return file;
  }

  /// Generates an AI summary for this note (if missing) and caches it in the DB.
  Future<String?> _generateSummary({bool silent = false}) async {
    if (_summary != null && _summary!.isNotEmpty) return _summary;
    final user = context.read<AuthService>().currentUser;
    if (user == null || user.isGuest) return null;
    if (mounted) setState(() => _isSummarizing = true);
    try {
      final noteService = context.read<NoteService>();
      String text = widget.note.content.trim();
      if (text.isEmpty) {
        final file = await _downloadNoteFile();
        if (file != null) text = await noteService.extractNoteText(file);
      }
      if (text.length < 20) {
        if (!silent && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not read this file. Old .ppt documents aren\'t readable in-app — try a .pptx, PDF, Word or text version.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }

      final summary = await AiChatService().summarizeNote(widget.note.title, text);
      if (summary.isNotEmpty) {
        await noteService.updateNoteSummary(widget.note.id, summary);
        if (mounted) setState(() => _summary = summary);
        return summary;
      }
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI couldn\'t summarize right now. Try again in a moment.'), backgroundColor: Colors.orange),
        );
      }
      return null;
    } catch (e) {
      debugPrint('Summary generation error: $e');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not generate summary right now.'), backgroundColor: Colors.orange),
        );
      }
      return null;
    } finally {
      if (mounted && _isSummarizing) setState(() => _isSummarizing = false);
    }
  }

  void _showSummaryDialog(String summary) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('AI Summary'),
        content: SingleChildScrollView(
          child: SelectableText(summary, style: const TextStyle(fontSize: 15, height: 1.5)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _handleSummaryButton() async {
    if (_summary != null && _summary!.isNotEmpty) {
      _showSummaryDialog(_summary!);
      return;
    }
    setState(() => _isSummarizing = true);
    final summary = await _generateSummary();
    if (mounted) setState(() => _isSummarizing = false);
    if (summary != null && summary.isNotEmpty && mounted) {
      _showSummaryDialog(summary);
    }
  }

  Future<void> _handleOpenNote() async {
    final user = context.read<AuthService>().currentUser!;
    if (user.isGuest) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Access restricted. Sign up to read and download notes!'),
          backgroundColor: Colors.indigo,
          action: SnackBarAction(
            label: 'SIGN UP',
            textColor: Colors.white,
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false),
          ),
        ),
      );
      return;
    }

    if (widget.note.gDriveId == null && widget.note.content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This note has no content or attached file.')),
      );
      return;
    }

    _showReaderPicker();
  }

  void _showReaderPicker() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('How would you like to read?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            const Text('Choose your preferred reading experience', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 24),
            
            _buildReaderOption(
              Icons.system_update_alt_rounded,
              'Device Default Viewer',
              'Open using your phone\'s built-in apps',
              Colors.blue,
              () => _openWithMode(isExternal: true),
            ),
            const SizedBox(height: 12),
            _buildReaderOption(
              Icons.auto_stories_rounded,
              'In-App Reader',
              'Fast, clean, and distraction-free (Recommended)',
              Colors.orange,
              () => _openWithMode(isExternal: false),
              isComingSoon: false,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildReaderOption(IconData icon, String title, String subtitle, Color color, VoidCallback onTap, {bool isComingSoon = false}) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: isComingSoon ? null : () {
        Navigator.pop(context);
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
          borderRadius: BorderRadius.circular(16),
          color: isComingSoon ? theme.disabledColor.withOpacity(0.05) : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: isComingSoon ? Colors.grey : null)),
                      if (isComingSoon) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                          child: const Text('BETA', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.orange)),
                        ),
                      ],
                    ],
                  ),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.withOpacity(0.7))),
                ],
              ),
            ),
            if (!isComingSoon) const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Future<void> _openWithMode({required bool isExternal}) async {
    setState(() => _isLoading = true);
    
    try {
      final noteService = context.read<NoteService>();
      final appDirPath = await noteService.getAppDirectory();
      
      // Determine file extension from title or URL
      String ext = '';
      if (widget.note.gDriveId != null && widget.note.gDriveId!.isNotEmpty) {
        // Extract extension from URL
        final url = Uri.parse(widget.note.gDriveId!);
        final pathParts = url.path.split('.');
        if (pathParts.length > 1) {
          ext = '.${pathParts.last}';
        }
      }
      
      // Fallback: extract from title
      if (ext.isEmpty) {
        final lowerTitle = widget.note.title.toLowerCase();
        final hasExtension = lowerTitle.contains(RegExp(r'\.(pdf|docx|doc|pptx|ppt|txt|md|jpg|png|jpeg|mp4|mp3|wav|mov|mkv|py|java|cpp|dart|csv|xlsx|xls|json|html)$'));
        if (hasExtension) {
          final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(lowerTitle);
          if (match != null) ext = '.${match.group(1)}';
        } else {
          ext = (widget.note.category ?? '').toLowerCase().contains('pdf') ? '.pdf' : '.txt';
        }
      }
      
      final fileName = '${widget.note.title.replaceAll(' ', '_')}$ext';
      final filePath = '$appDirPath\\$fileName';
      final file = File(filePath);

      if (!await file.exists()) {
        final url = _resolveFileUrl();
        if (url.isNotEmpty) {
          // Download from Cloudinary / Google Drive
          final response = await http.get(Uri.parse(url));
          debugPrint('Note file fetch [${widget.note.id}]: HTTP ${response.statusCode} from $url');
          if (response.statusCode != 200) {
            if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 404) {
              throw Exception('This file is no longer available on the server (HTTP ${response.statusCode}). It may have been removed by the uploader.');
            }
            throw Exception('Could not fetch file from storage (HTTP ${response.statusCode}): $url');
          }
          await file.writeAsBytes(response.bodyBytes);
        } else {
          await file.writeAsString(widget.note.content);
        }
      }

      // Log the download for admin usage stats (best-effort)
      unawaited(context.read<NoteService>().logDownload(widget.note.id, await file.length()));

      // Auto-index for AI search the first time this note is opened
      if (['.pdf', '.txt', '.md'].contains(ext.toLowerCase())) {
        unawaited(context.read<NoteService>().ensureIndexedForAi(file, widget.note.title));
      }

      if (mounted) {
        if (isExternal) {
          if (Platform.isWindows) {
            // This is the most reliable way to open files with their default app on Windows
            await Process.run('explorer', [file.path]);
          } else if (Platform.isAndroid || Platform.isIOS) {
            // open_filex uses a FileProvider content:// URI — passing a raw
            // file:// URI to an intent crashes Android 7+ (FileUriExposedException)
            final result = await OpenFilex.open(file.path);
            if (mounted && result.type != ResultType.done) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result.type == ResultType.noAppToOpen
                      ? 'No app installed on this device can open ${ext.toUpperCase()} files.'
                      : 'Could not open externally: ${result.message}'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } else {
            final uri = Uri.file(file.path);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              Navigator.push(context, MaterialPageRoute(builder: (context) => FileViewerPage(file: file, title: widget.note.title, onSave: _uploadEditedFile)));
            }
          }
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (context) => FileViewerPage(file: file, title: widget.note.title, onSave: _uploadEditedFile)));
        }
      }
    } catch (e) {
      if (mounted) {
        final offline = e is SocketException || (e.toString().contains('SocketException'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(offline
                ? "You're offline and this note hasn't been downloaded yet. Go online once to download it, then it works offline."
                : 'Failed to open: $e'),
            backgroundColor: offline ? Colors.orange : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Save-back: re-uploads an edited file to Cloudinary and updates the note.
  Future<void> _uploadEditedFile(File file) async {
    try {
      final authService = context.read<AuthService>();
      final url = await CloudinaryService().uploadFile(
        file: file,
        userId: authService.currentUser?.id ?? 'guest',
        folder: 'notes',
      );
      if (url == null) {
        debugPrint('Edit save-back: Cloudinary upload failed');
        return;
      }
      final updated = await context.read<NoteService>().updateNoteFileUrl(widget.note.id, url);
      debugPrint('Edit save-back: ${updated ? 'note URL updated' : 'note URL update FAILED'}');
    } catch (e) {
      debugPrint('Edit save-back error: $e');
    }
  }

  Future<void> _deleteNote(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${widget.note.title}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    
    // 1. Delete from Cloudinary if it exists
    if (widget.note.gDriveId != null && widget.note.gDriveId!.isNotEmpty) {
      final cloudinaryService = CloudinaryService();
      final publicId = CloudinaryService.extractPublicIdFromUrl(widget.note.gDriveId!);
      if (publicId != null) {
        await cloudinaryService.deleteFile(publicId);
      }
    }
    
    // 2. Delete from Supabase Database
    final user = context.read<AuthService>().currentUser;
    final success = await context.read<NoteService>().deleteNote(
      widget.note.id,
      userId: user?.id,
      isAdmin: user?.hasRole(UserRole.admin) ?? false,
    );
    
    setState(() => _isLoading = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Note deleted successfully.')));
        Navigator.pop(context); // Go back to notes list
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete note.', style: TextStyle(color: Colors.red))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthService>().currentUser;
    final isAdmin = user?.hasRole(UserRole.admin) ?? false;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Note Detail'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        actions: [
          if (isAdmin)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
              tooltip: 'Delete Note (Admin)',
              onPressed: () => _deleteNote(context),
            ),
          IconButton(
            icon: _isSummarizing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.auto_awesome, color: Colors.amber),
            onPressed: _isSummarizing ? null : _handleSummaryButton,
            tooltip: (_summary != null && _summary!.isNotEmpty) ? 'View AI Summary' : 'Generate AI Summary',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Year ${widget.note.targetYear} • Semester ${widget.note.semester}',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.note.title,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  widget.note.lecturerName,
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                ),
                const SizedBox(width: 16),
                const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${widget.note.createdAt.day}/${widget.note.createdAt.month}/${widget.note.createdAt.year}',
                  style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.6), fontSize: 14),
                ),
              ],
            ),
            const Divider(height: 40),
            Text(
              'Full Description',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Text(
              widget.note.content.isEmpty ? 'This note contains an attached file. Use the button below to open and read it.' : widget.note.content,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: theme.colorScheme.onSurface,
              ),
            ),
            if (_isSummarizing) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: theme.colorScheme.primary.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('Generating AI summary...', style: TextStyle(fontSize: 13))),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: _isSummarizing
                          ? () => setState(() => _isSummarizing = false)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
            if (_summary != null && _summary!.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSummaryCard(theme, _summary!),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isLoading ? null : _handleOpenNote,
        label: Text(_isLoading ? 'Loading Note...' : 'OPEN & READ NOTE'),
        icon: _isLoading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.menu_book_rounded),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: theme.colorScheme.onPrimary,
      ),
    );
  }
  Widget _buildSummaryCard(ThemeData theme, String summary) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.summarize_rounded, size: 20, color: theme.colorScheme.secondary),
              const SizedBox(width: 8),
              Text(
                'QUICK SUMMARY',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: theme.colorScheme.onSecondaryContainer,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}
