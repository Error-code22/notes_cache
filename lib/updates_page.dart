import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'services.dart';
import 'models.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key});

  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  final _supabase = Supabase.instance.client;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('App Updates'),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _supabase.from('app_updates').stream(primaryKey: ['id']).order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final updates = snapshot.data ?? [];
          if (updates.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.campaign_rounded, size: 60, color: theme.colorScheme.primary.withOpacity(0.2)),
                  const SizedBox(height: 16),
                  const Text('No updates yet!', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: updates.length,
            itemBuilder: (context, index) {
              final update = updates[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.campaign_rounded, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(update['title'] ?? 'Update', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(update['content'] ?? ''),
                      const SizedBox(height: 12),
                      Text(
                        DateTime.parse(update['created_at']).toLocal().toString().split('.')[0],
                        style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
