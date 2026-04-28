import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'google_drive_auth_service.dart';
import 'services.dart';
import 'models.dart';

class UploadNotePage extends StatefulWidget {
  const UploadNotePage({super.key});

  @override
  State<UploadNotePage> createState() => _UploadNotePageState();
}

class _UploadNotePageState extends State<UploadNotePage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _summaryController = TextEditingController();
  List<File> _selectedFiles = [];
  final Map<String, double> _uploadProgress = {};
  final Map<String, String> _uploadStatus = {};
  int _selectedYear = 1;
  int _selectedSemester = 1;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    // Default to student's year if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = context.read<AuthService>().currentUser;
      if (user != null && user.hasRole(UserRole.student) && user.yearLevel != null) {
        setState(() {
          _selectedYear = user.yearLevel!;
        });
      }
    });
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt', 'md', 'csv', 'xls', 'xlsx', 'mp4', 'mp3', 'wav', 'mov', 'mkv', 'm4a', 'py', 'java', 'cpp', 'dart', 'html', 'json'],
        allowMultiple: true,
      );

      if (result != null) {
        setState(() {
          _selectedFiles = result.paths.map((path) => File(path!)).toList();
          if (_selectedFiles.isNotEmpty && _titleController.text.isEmpty) {
            // Auto-fill title from first file name
            _titleController.text = _selectedFiles.first.path.split(Platform.pathSeparator).last.split('.').first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  Future<void> _handleBatchUpload() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one file!')));
      return;
    }

    setState(() {
      _isUploading = true;
      for (var file in _selectedFiles) {
        _uploadStatus[file.path] = 'Waiting...';
        _uploadProgress[file.path] = 0;
      }
    });

    final authService = context.read<AuthService>();
    final driveAuth = GoogleDriveAuthService();
    final noteService = NoteService();
    final folderId = dotenv.env['GDRIVE_FOLDER_ID'];

    try {
      final success = await driveAuth.authenticate();
      if (!success) throw Exception('Google Drive authentication failed');

      for (var file in _selectedFiles) {
        if (!mounted) break;
        
        setState(() {
          _uploadStatus[file.path] = 'Checking...';
        });

        final fileName = file.path.split(Platform.pathSeparator).last;
        final fileSize = await file.length();
        final ext = fileName.split('.').last.toLowerCase();
        
        // Auto-determine category
        String category = 'Note';
        if (ext == 'pdf') category = 'PDF';
        else if (ext == 'pptx' || ext == 'ppt') category = 'Slides';
        else if (ext == 'docx' || ext == 'doc') category = 'Document';
        else if (['jpg', 'jpeg', 'png'].contains(ext)) category = 'Image';
        else if (ext == 'txt' || ext == 'md') category = 'Text';
        else if (['mp4', 'mov', 'mkv'].contains(ext)) category = 'Video';
        else if (['mp3', 'wav', 'm4a'].contains(ext)) category = 'Audio';
        else if (['csv', 'xls', 'xlsx'].contains(ext)) category = 'Spreadsheet';
        else if (['py', 'java', 'cpp', 'dart', 'html', 'json'].contains(ext)) category = 'Code';

        final extension = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
        String finalTitle = _selectedFiles.length > 1 ? fileName.split('.').first : _titleController.text;
        
        // Ensure title has the extension for smart detection
        if (!finalTitle.toLowerCase().endsWith(extension.toLowerCase())) {
          finalTitle = "$finalTitle$extension";
        }

        // Smart Duplicate Check
        final duplicate = await noteService.findDuplicateNote(
          title: finalTitle,
          year: _selectedYear,
          semester: _selectedSemester,
          fileSize: fileSize,
        );

        if (duplicate != null && mounted) {
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Potential Duplicate'),
              content: Text('A similar note already exists: "${duplicate['note']['title']}".\n\nDo you still want to upload this file?'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('SKIP')),
                ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('UPLOAD ANYWAY')),
              ],
            ),
          );

          if (proceed != true) {
            setState(() {
              _uploadStatus[file.path] = '⏭️ Skipped';
              _uploadProgress[file.path] = 0;
            });
            continue;
          }
        }

        setState(() {
          _uploadStatus[file.path] = 'Uploading...';
        });

        final fileId = await driveAuth.uploadFile(
          file, 
          fileName, 
          folderId: folderId,
          onProgress: (p) {
            if (mounted) {
              setState(() => _uploadProgress[file.path] = p);
            }
          },
        );

        if (fileId == null) {
          setState(() => _uploadStatus[file.path] = '❌ Drive Failed');
          continue;
        }

        setState(() {
          _uploadStatus[file.path] = 'Syncing...';
          _uploadProgress[file.path] = 0.95;
        });

        final dbSuccess = await noteService.saveNote(
          title: finalTitle,
          lecturerName: (authService.currentUser?.isGuest ?? false) 
              ? 'Guest Contributor' 
              : (authService.currentUser?.fullName ?? 'Student Upload'),
          targetYear: _selectedYear,
          semester: _selectedSemester,
          gDriveId: fileId,
          content: _contentController.text,
          summary: _summaryController.text,
          fileSize: fileSize,
          category: category,
        );

        setState(() {
          if (dbSuccess) {
            _uploadStatus[file.path] = '✅ Success';
            _uploadProgress[file.path] = 1.0;
          } else {
            _uploadStatus[file.path] = '⚠️ DB Failed';
          }
        });
      }

      // Check if all succeeded
      final allSuccess = _uploadStatus.values.every((s) => s.startsWith('✅'));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(allSuccess ? '✅ All files uploaded successfully!' : '⚠️ Some uploads had issues.'),
            backgroundColor: allSuccess ? Colors.green : Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
        if (allSuccess) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'), 
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          )
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthService>().currentUser;
    final isStudent = user?.hasRole(UserRole.student) ?? true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              theme.colorScheme.primaryContainer.withOpacity(0.1),
              theme.colorScheme.surface,
            ],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (user?.isGuest == true)
                Container(
                  margin: const EdgeInsets.only(bottom: 24),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.privacy_tip_outlined, color: Colors.orange),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'Notice: As a Guest, your uploaded notes will be stored permanently, but your other activity will not be saved.',
                          style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_selectedFiles.isEmpty) ...[
                _buildUploadPlaceholder(theme),
              ] else ...[
                _buildSectionHeader(context, 'General Information'),
                const SizedBox(height: 16),
                if (!isStudent && _selectedFiles.length == 1)
                  _buildTextField(
                    theme,
                    controller: _titleController,
                    label: 'Note Title',
                    hint: 'Enter a custom title (optional)',
                    icon: Icons.title,
                  ),
                const SizedBox(height: 16),
                _buildTextField(
                  theme,
                  controller: _contentController,
                  label: isStudent ? 'Description (Optional)' : 'Batch Description (Optional)',
                  hint: 'Add some context...',
                  icon: Icons.description,
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  theme,
                  controller: _summaryController,
                  label: 'Summary (Optional)',
                  hint: 'Brief overview for quick reading...',
                  icon: Icons.summarize,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildDropdown(theme, 'Target Year', _selectedYear, [1, 2, 3, 4], (val) {
                        setState(() => _selectedYear = val!);
                      }),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDropdown(theme, 'Semester', _selectedSemester, [1, 2], (val) {
                        setState(() => _selectedSemester = val!);
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildSectionHeader(context, 'Files to Upload'),
                const SizedBox(height: 12),
                ..._selectedFiles.map((file) => _buildFileItem(theme, file)),
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: _isUploading ? null : _pickFiles,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Add More Files'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 40),
              _buildUploadButton(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildTextField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: theme.colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.6)),
        filled: true,
        fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: theme.dividerColor.withOpacity(0.05)),
        ),
      ),
    );
  }

  Widget _buildUploadButton(ThemeData theme) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: (_selectedFiles.isEmpty || _isUploading) ? null : _handleBatchUpload,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: _isUploading 
          ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
                SizedBox(width: 16),
                Text('UPLOADING...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
              ],
            )
          : const Text('UPLOAD ALL FILES', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }

  Widget _buildUploadPlaceholder(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_upload_rounded, size: 100, color: theme.colorScheme.primary.withOpacity(0.5)),
          ),
          const SizedBox(height: 32),
          Text(
            'Share your notes with the world', 
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 12),
          Text(
            'Select your PDFs or images to start indexing', 
            style: TextStyle(fontSize: 16, color: theme.colorScheme.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: _pickFiles,
            icon: const Icon(Icons.add),
            label: const Text('Select Files'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(ThemeData theme, File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final progress = _uploadProgress[file.path] ?? 0;
    final status = _uploadStatus[file.path] ?? 'Ready';
    final isSuccess = status.contains('✅');
    final isError = status.contains('❌') || status.contains('⚠️');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSuccess ? Colors.green.shade200 : isError ? Colors.red.shade200 : theme.dividerColor.withOpacity(0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isSuccess ? Colors.green : isError ? Colors.red : theme.colorScheme.primary).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isSuccess ? Icons.check_circle_rounded : isError ? Icons.error_rounded : Icons.description_rounded, 
                  color: isSuccess ? Colors.green : isError ? Colors.red : theme.colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name, 
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: theme.colorScheme.onSurface), 
                  overflow: TextOverflow.ellipsis
                ),
              ),
              const SizedBox(width: 8),
              Text(
                status, 
                style: TextStyle(
                  fontSize: 13, 
                  fontWeight: FontWeight.bold,
                  color: isSuccess ? Colors.green : isError ? Colors.red : theme.colorScheme.onSurface.withOpacity(0.5),
                )
              ),
              if (!_isUploading && !isSuccess)
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, size: 20, color: theme.colorScheme.onSurface.withOpacity(0.3)),
                  onPressed: () => setState(() => _selectedFiles.remove(file)),
                ),
            ],
          ),
          if (_isUploading || isSuccess || isError) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: theme.dividerColor.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isSuccess ? Colors.green : isError ? Colors.red : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDropdown(ThemeData theme, String label, int value, List<int> items, ValueChanged<int?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface.withOpacity(0.8))),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: value,
          dropdownColor: theme.cardColor,
          style: TextStyle(color: theme.colorScheme.onSurface),
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i.toString(), style: TextStyle(color: theme.colorScheme.onSurface)))).toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: theme.colorScheme.surfaceVariant.withOpacity(0.2),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ],
    );
  }
}
