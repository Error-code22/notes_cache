import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services.dart';
import 'models.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser!;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Admin Command Center'),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome back, ${user.fullName ?? "Admin"}',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            ),
            const SizedBox(height: 20),
            
            // Stats Row
            Row(
              children: [
                _buildStatCard('Total Users', '128', Icons.people, Colors.blue),
                const SizedBox(width: 16),
                _buildStatCard('Storage Used', '1.2 GB', Icons.storage, Colors.orange),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatCard('Total Notes', '452', Icons.description, Colors.green),
                const SizedBox(width: 16),
                _buildStatCard('Active Drives', '1', Icons.cloud_done, Colors.purple),
              ],
            ),
            
            const SizedBox(height: 30),
            const Text(
              'Management Tools',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            _buildAdminAction(
              context,
              'Manage Users',
              'Promote, demote, or remove accounts',
              Icons.manage_accounts,
              Colors.blue,
            ),
            _buildAdminAction(
              context,
              'Storage Explorer',
              'Manage your Google Drive Pool',
              Icons.folder_shared,
              Colors.orange,
            ),
            _buildAdminAction(
              context,
              'Global Content Moderation',
              'Review all notes across all years',
              Icons.security,
              Colors.red,
            ),
            _buildAdminAction(
              context,
              'System Logs',
              'Check for errors or suspicious activity',
              Icons.terminal,
              Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            Text(title, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminAction(BuildContext context, String title, String subtitle, IconData icon, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          // Future implementations
        },
      ),
    );
  }
}
