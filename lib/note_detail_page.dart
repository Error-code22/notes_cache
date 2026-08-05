import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
        if (widget.note.gDriveId != null && widget.note.gDriveId!.isNotEmpty) {
          // Download from R2 via public URL
          final response = await http.get(Uri.parse(widget.note.gDriveId!));
          if (response.statusCode != 200) throw Exception('Could not fetch file from storage');
          await file.writeAsBytes(response.bodyBytes);
        } else {
          await file.writeAsString(widget.note.content);
        }
      }

      // Auto-index for AI search the first time this note is opened
      if (['.pdf', '.txt', '.md'].contains(ext.toLowerCase())) {
        unawaited(context.read<NoteService>().ensureIndexedForAi(file, widget.note.title));
      }

      if (mounted) {
        if (isExternal) {
          if (Platform.isWindows) {
            // This is the most reliable way to open files with their default app on Windows
            await Process.run('explorer', [file.path]);
          } else {
            final uri = Uri.file(file.path);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            } else {
              Navigator.push(context, MaterialPageRoute(builder: (context) => FileViewerPage(file: file, title: widget.note.title)));
            }
          }
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (context) => FileViewerPage(file: file, title: widget.note.title)));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
            icon: const Icon(Icons.auto_awesome, color: Colors.amber),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.note.summary != null ? 'This summary was provided by the uploader.' : 'AI Summary feature coming soon!')),
              );
            },
            tooltip: widget.note.summary != null ? 'Uploader Summary' : 'AI Summary',
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
            if (widget.note.summary != null && widget.note.summary!.isNotEmpty) ...[
              _buildSummaryCard(theme, widget.note.summary!),
              const SizedBox(height: 24),
            ],
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
