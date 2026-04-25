import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'google_drive_auth_service.dart';
import 'services.dart';
import 'models.dart';
import 'package:provider/provider.dart';

class UploadNotePage extends StatefulWidget {
  const UploadNotePage({super.key});

  @override
  State<UploadNotePage> createState() => _UploadNotePageState();
}

class _UploadNotePageState extends State<UploadNotePage> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  int _selectedYear = 1;
  int _selectedSemester = 1;
  File? _selectedFile;
  bool _isUploading = false;
  double _uploadProgress = 0;

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'png'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
  }

  Future<void> _handleUpload() async {
    if (_selectedFile == null || _titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a title and select a file!')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
    });

    try {
      final driveAuth = GoogleDriveAuthService();
      final success = await driveAuth.authenticate();
      
      if (!success) throw Exception('Google Drive authentication failed');

      setState(() => _uploadProgress = 0.3);

      final folderId = dotenv.env['GDRIVE_FOLDER_ID'];
      final fileId = await driveAuth.uploadFile(
        _selectedFile!,
        _selectedFile!.path.split(Platform.pathSeparator).last,
        folderId: folderId,
      );

      if (fileId == null) throw Exception('Upload to Google Drive failed');

      setState(() => _uploadProgress = 0.7);

      // Save to Supabase (NoteService)
      final authService = context.read<AuthService>();
      final noteService = NoteService();
      
      final dbSuccess = await noteService.saveNote(
        title: _titleController.text,
        lecturerName: authService.currentUser?.fullName ?? 'Unknown Lecturer',
        targetYear: _selectedYear,
        semester: _selectedSemester,
        gDriveId: fileId,
        content: _contentController.text,
      );

      if (!dbSuccess) throw Exception('Failed to sync note metadata to database');

      if (mounted) {
        setState(() => _uploadProgress = 1.0);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Note Uploaded & Synced Successfully!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload New Note'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Note Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Note Title',
                hintText: 'e.g., Intro to Thermodynamics',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.title),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.description_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildDropdown('Year Level', _selectedYear, [1, 2, 3, 4], (val) {
                    setState(() => _selectedYear = val!);
                  }),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildDropdown('Semester', _selectedSemester, [1, 2], (val) {
                    setState(() => _selectedSemester = val!);
                  }),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text('File Attachment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _isUploading ? null : _pickFile,
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade200, style: BorderStyle.solid),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_upload, size: 40, color: Colors.blue.shade700),
                    const SizedBox(height: 8),
                    Text(
                      _selectedFile == null 
                          ? 'Tap to select PDF or Document' 
                          : _selectedFile!.path.split(Platform.pathSeparator).last,
                      style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            if (_isUploading)
              Column(
                children: [
                  LinearProgressIndicator(value: _uploadProgress, backgroundColor: Colors.grey[200]),
                  const SizedBox(height: 8),
                  Text('Uploading... ${( _uploadProgress * 100).toInt()}%', style: const TextStyle(color: Colors.grey)),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  onPressed: _handleUpload,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A237E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('UPLOAD TO DRIVE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, int value, List<int> items, Function(int?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              items: items.map((i) => DropdownMenuItem(value: i, child: Text('Year $i'))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
