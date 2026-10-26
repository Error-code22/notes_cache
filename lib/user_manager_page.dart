import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';
import 'models.dart';

class UserManagerPage extends StatefulWidget {
  const UserManagerPage({super.key});

  @override
  State<UserManagerPage> createState() => _UserManagerPageState();
}

class _UserManagerPageState extends State<UserManagerPage> {
  List<UserProfile> _users = [];
  bool _isLoading = true;

  final _resetEmailController = TextEditingController();
  bool _isCreatingResetLink = false;
  String? _resetLinkError;
  AdminResetLink? _resetLink;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _resetEmailController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final authService = context.read<AuthService>();
    final users = await authService.getAllUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleRole(UserProfile user, UserRole role) async {
    final authService = context.read<AuthService>();
    List<UserRole> newRoles = List.from(user.roles);

    if (newRoles.contains(role)) {
      if (newRoles.length > 1) newRoles.remove(role); // Keep at least one role
    } else {
      newRoles.add(role);
    }

    final success = await authService.updateUserRoles(user.id, newRoles);

    if (success && mounted) {
      _loadUsers();
    }
  }

  Future<void> _pasteEmail() async {
    String text;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      text = data?.text?.trim() ?? '';
    } catch (_) {
      text = '';
    }
    final match = RegExp(
      r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
      caseSensitive: false,
    ).firstMatch(text);
    if (!mounted) return;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email address found in the clipboard.'),
        ),
      );
      return;
    }
    setState(() {
      _resetEmailController.text = match.group(0)!;
      _resetLinkError = null;
      _resetLink = null;
    });
  }

  Future<void> _createResetLink() async {
    final email = _resetEmailController.text.trim();
    if (email.isEmpty) {
      setState(() => _resetLinkError = 'Enter the student email first.');
      return;
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      setState(() => _resetLinkError = 'Enter a valid email address.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isCreatingResetLink = true;
      _resetLinkError = null;
      _resetLink = null;
    });

    try {
      final authService = context.read<AuthService>();
      final result = await authService.createPasswordResetLink(email);
      if (!mounted) return;
      setState(() => _resetLink = result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resetLinkError = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isCreatingResetLink = false);
    }
  }

  Future<void> _copyResetLink() async {
    final link = _resetLink?.link;
    if (link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reset link copied. Send it to the student.'),
      ),
    );
  }

  Future<void> _shareResetLinkOnWhatsApp() async {
    final result = _resetLink;
    if (result == null) return;
    final message =
        'Hi, here is your NotesCache password reset link for ${result.email}. '
        'It expires in 1 hour and can be used once.\n\n'
        '${result.link}\n\n'
        'If you did not request this, ignore this message.';
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: result.link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open WhatsApp. The reset link was copied.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUsers,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _users.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildResetLinkCard(theme, primaryColor);
                  }
                  final user = _users[index - 1];
                  return _buildUserCard(user, theme, primaryColor);
                },
              ),
            ),
    );
  }

  Widget _buildResetLinkCard(ThemeData theme, Color primaryColor) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: primaryColor.withOpacity(0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.key_rounded, color: primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create password reset link',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'For a student who cannot open the email link.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface.withOpacity(0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _resetEmailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _createResetLink(),
              decoration: InputDecoration(
                labelText: 'Student email',
                hintText: 'student@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                suffixIcon: IconButton(
                  tooltip: 'Paste copied email',
                  onPressed: _pasteEmail,
                  icon: const Icon(Icons.content_paste_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreatingResetLink ? null : _createResetLink,
                icon: _isCreatingResetLink
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.link_rounded),
                label: Text(
                  _isCreatingResetLink ? 'Generating…' : 'Generate reset link',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_resetLinkError != null) ...[
              const SizedBox(height: 10),
              Text(
                _resetLinkError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
            if (_resetLink != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.07),
                  border: Border.all(color: Colors.green.withOpacity(0.25)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Link ready for ${_resetLink!.email}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Expires in 1 hour. Single use.',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _copyResetLink,
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Copy link'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _shareResetLinkOnWhatsApp,
                        icon: const Icon(Icons.chat_rounded, size: 16),
                        label: const Text('Share on WhatsApp'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(UserProfile user, ThemeData theme, Color primaryColor) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.dividerColor.withOpacity(0.05)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: primaryColor.withOpacity(0.1),
                child: Text(
                  (user.fullName ?? '?').substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                user.fullName ?? 'Unknown User',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${user.id.substring(0, 8)}...'),
                  if (user.email.isNotEmpty)
                    Text(
                      user.email,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurface.withOpacity(0.55),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: user.roles
                        .map((r) => _buildRoleBadge(r))
                        .toList(),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _RoleButton(
                  label: 'Student',
                  isSelected: user.hasRole(UserRole.student),
                  onTap: () => _toggleRole(user, UserRole.student),
                ),
                _RoleButton(
                  label: 'Lecturer',
                  isSelected: user.hasRole(UserRole.lecturer),
                  onTap: () => _toggleRole(user, UserRole.lecturer),
                ),
                _RoleButton(
                  label: 'Mod',
                  isSelected: user.hasRole(UserRole.moderator),
                  onTap: () => _toggleRole(user, UserRole.moderator),
                ),
                _RoleButton(
                  label: 'Admin',
                  isSelected: user.hasRole(UserRole.admin),
                  onTap: () => _toggleRole(user, UserRole.admin),
                ),
                _RoleButton(
                  label: 'Rep',
                  isSelected: user.hasRole(UserRole.classRep),
                  onTap: () => _toggleRole(user, UserRole.classRep),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(UserRole role) {
    Color color;
    switch (role) {
      case UserRole.admin:
        color = Colors.red;
        break;
      case UserRole.moderator:
        color = Colors.purple;
        break;
      case UserRole.lecturer:
        color = Colors.orange;
        break;
      case UserRole.classRep:
        color = Colors.teal;
        break;
      case UserRole.student:
        color = Colors.blue;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        role.name.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : theme.colorScheme.onSurface.withOpacity(0.5),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
