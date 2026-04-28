import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

  @override
  void initState() {
    super.initState();
    _loadUsers();
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
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  return _buildUserCard(user, theme, primaryColor);
                },
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
                  style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold),
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
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: user.roles.map((r) => _buildRoleBadge(r)).toList(),
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
      case UserRole.admin: color = Colors.red; break;
      case UserRole.moderator: color = Colors.purple; break;
      case UserRole.lecturer: color = Colors.orange; break;
      case UserRole.student: color = Colors.blue; break;
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
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
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
            color: isSelected ? Colors.white : theme.colorScheme.onSurface.withOpacity(0.5),
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
