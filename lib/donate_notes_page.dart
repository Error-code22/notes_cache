import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'r2_service.dart';
import 'services.dart';
import 'models.dart';
import 'note_detail_page.dart';

class DonateNotesPage extends StatefulWidget {
  const DonateNotesPage({super.key});

  @override
  State<DonateNotesPage> createState() => _DonateNotesPageState();
}

class _DonateNotesPageState extends State<DonateNotesPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<File> _selectedFiles = [];
  bool _isUploading = false;
  int _uploadedCount = 0;
  int _failedCount = 0;
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  int _selectedYear = 1;
  int _selectedSemester = 1;
  String _searchQuery = '';
  Future<List<Note>>? _donatedNotesFuture;
  Future<List<DonationSubmission>>? _myDonationsFuture;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDonatedNotes();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _tabController.dispose();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _loadDonatedNotes() {
    final noteService = context.read<NoteService>();
    setState(() {
      _donatedNotesFuture = noteService.getDonatedNotes(
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
      );
      _myDonationsFuture = noteService.getMyDonations();
    });
  }

  Future<void> _pickFiles() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt', 'md'],
        allowMultiple: true,
      );

      if (result != null && mounted) {
        setState(() {
          _selectedFiles = result.paths.map((path) => File(path!)).toList();
          if (_selectedFiles.isNotEmpty && _titleController.text.isEmpty) {
            _titleController.text = _selectedFiles.first.path.split(Platform.pathSeparator).last.split('.').first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking files: $e');
    }
  }

  Future<void> _pickFolder() async {
    try {
      String? directoryPath = await FilePicker.getDirectoryPath();
      if (directoryPath != null && mounted) {
        final directory = Directory(directoryPath);
        final files = directory.listSync().whereType<File>().where((f) {
          final ext = f.path.split('.').last.toLowerCase();
          return ['pdf', 'doc', 'docx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'txt', 'md'].contains(ext);
        }).toList();
        
        if (files.isNotEmpty) {
          setState(() {
            _selectedFiles = files;
            if (_titleController.text.isEmpty) {
              _titleController.text = directoryPath.split(Platform.pathSeparator).last;
            }
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No supported files found in the selected directory')),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error picking directory: $e');
    }
  }

  Future<void> _handleDonate() async {
    if (_selectedFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one file!')));
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadedCount = 0;
      _failedCount = 0;
    });

    final authService = context.read<AuthService>();
    final cloudinaryService = CloudinaryService();
    final noteService = NoteService();

    try {
      for (var file in _selectedFiles) {
        if (!mounted) break;

        final fileName = file.path.split(Platform.pathSeparator).last;
        final fileSize = await file.length();
        final ext = fileName.split('.').last.toLowerCase();

        String category = 'Donation';
        if (ext == 'pdf') category = 'PDF';
        else if (ext == 'pptx' || ext == 'ppt') category = 'Slides';
        else if (ext == 'docx' || ext == 'doc') category = 'Document';
        else if (['jpg', 'jpeg', 'png'].contains(ext)) category = 'Image';

        final uploadResult = await cloudinaryService.uploadFileWithBackup(
          file: file,
          userId: authService.currentUser?.id ?? 'guest',
          folder: 'donations',
        );

        if (!mounted) break;

        if (!uploadResult.success) {
          setState(() => _failedCount++);
          continue;
        }

        final dbSuccess = await noteService.saveDonatedNote(
          title: _titleController.text.isNotEmpty ? _titleController.text : fileName.split('.').first,
          lecturerName: authService.currentUser?.fullName ?? 'Student Donation',
          targetYear: _selectedYear,
          semester: _selectedSemester,
          gDriveId: uploadResult.url,
          content: _descController.text,
          category: category,
          fileSize: fileSize,
          // Guests have no real user id (UUID column would reject 'guest_user')
          userId: authService.currentUser?.isGuest == true ? null : authService.currentUser?.id,
        );

        if (dbSuccess) {
          await noteService.indexForAi(file, _titleController.text.isNotEmpty ? _titleController.text : fileName.split('.').first);
        }

        if (mounted) {
          setState(() => dbSuccess ? _uploadedCount++ : _failedCount++);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_failedCount == 0
                ? '$_uploadedCount file(s) submitted for review — an admin will publish them to the library.'
                : '$_uploadedCount submitted, $_failedCount failed'),
            backgroundColor: _failedCount == 0 ? Colors.green : Colors.orange,
          ),
        );
        setState(() {
          _selectedFiles.clear();
          _titleController.clear();
          _descController.clear();
        });
        _loadDonatedNotes();
      }
    } catch (e) {
      debugPrint('Donate error: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Donate Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.upload_rounded), text: 'Donate'),
            Tab(icon: Icon(Icons.library_books_rounded), text: 'Browse'),
            Tab(icon: Icon(Icons.mark_email_read_rounded), text: 'My Submissions'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDonateTab(theme),
          _buildBrowseTab(theme),
          _buildMySubmissionsTab(theme),
        ],
      ),
    );
  }

  Widget _buildDonateTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(Icons.volunteer_activism, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Help fellow students by sharing your lecture notes, slides, and study materials. An admin reviews each submission before it appears in the shared library.',
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (_selectedFiles.isEmpty) ...[
            Center(
              child: Column(
                children: [
                  Icon(Icons.cloud_upload_rounded, size: 80, color: theme.colorScheme.primary.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text('Select files or a folder to donate', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isUploading ? null : _pickFiles,
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Select Files'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _isUploading ? null : _pickFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Select Folder'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ] else ...[
            Text('Donation Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title (optional — auto-filled from filename)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedYear,
                    decoration: InputDecoration(
                      labelText: 'Year',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    items: [1, 2, 3, 4].map((y) => DropdownMenuItem(value: y, child: Text('Year $y'))).toList(),
                    onChanged: (v) => setState(() => _selectedYear = v!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedSemester,
                    decoration: InputDecoration(
                      labelText: 'Semester',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                    ),
                    items: [1, 2].map((s) => DropdownMenuItem(value: s, child: Text('Semester $s'))).toList(),
                    onChanged: (v) => setState(() => _selectedSemester = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ..._selectedFiles.map((file) {
              final name = file.path.split(Platform.pathSeparator).last;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.insert_drive_file, color: theme.colorScheme.primary),
                  title: Text(name, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    onPressed: () => setState(() => _selectedFiles.remove(file)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _handleDonate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isUploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                          SizedBox(width: 12),
                          Text('DONATING...'),
                        ],
                      )
                    : Text('DONATE ${_selectedFiles.length} FILE(S)'),
              ),
            ),
            if (_uploadedCount > 0 || _failedCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$_uploadedCount uploaded, $_failedCount failed',
                style: TextStyle(color: _failedCount > 0 ? Colors.orange : Colors.green, fontWeight: FontWeight.w500),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBrowseTab(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: TextField(
            onChanged: (value) {
              _searchQuery = value.toLowerCase();
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 350), _loadDonatedNotes);
            },
            decoration: InputDecoration(
              hintText: 'Search donated notes...',
              prefixIcon: const Icon(Icons.search, size: 20),
              filled: true,
              fillColor: theme.cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Note>>(
            future: _donatedNotesFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final notes = snapshot.data ?? [];

              if (notes.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.volunteer_activism, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Text('No approved donations yet.', style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(Icons.favorite, color: theme.colorScheme.primary, size: 20),
                      ),
                      title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        'Year ${note.targetYear} • Sem ${note.semester} • ${note.category ?? 'Note'}',
                        style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => NoteDetailPage(note: note)));
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Tab 3: what I sent, and whether an admin has reviewed it yet.
  Widget _buildMySubmissionsTab(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Submissions are reviewed by an admin before they appear in the shared library.',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DonationSubmission>>(
            future: _myDonationsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.mark_email_read_rounded, size: 60, color: theme.colorScheme.onSurface.withOpacity(0.1)),
                      const SizedBox(height: 16),
                      Text('You haven\'t submitted anything yet.',
                          style: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.4))),
                    ],
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _loadDonatedNotes(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final d = items[index];
                    final color = d.isApproved
                        ? Colors.green
                        : d.isRejected
                            ? Colors.red
                            : Colors.orange;
                    final label = d.isApproved
                        ? 'APPROVED'
                        : d.isRejected
                            ? 'REJECTED'
                            : 'PENDING REVIEW';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(
                            d.isApproved
                                ? Icons.check_circle_rounded
                                : d.isRejected
                                    ? Icons.cancel_rounded
                                    : Icons.hourglass_top_rounded,
                            color: color,
                            size: 20,
                          ),
                        ),
                        title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Year ${d.targetYear} • Sem ${d.semester} • ${d.category ?? 'Donation'}',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            ),
                            if (d.reviewNote != null && d.reviewNote!.isNotEmpty)
                              Text(
                                'Reason: ${d.reviewNote}',
                                style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                              ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
