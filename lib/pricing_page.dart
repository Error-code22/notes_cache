import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services.dart';

class PricingPage extends StatelessWidget {
  const PricingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthService>().currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Plans & Pricing')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header
            Text(
              'Choose Your Plan',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Unlock the full power of NotesCache for your studies',
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Free Plan
            _PricingCard(
              title: 'Free',
              price: 'KSh 0',
              period: 'forever',
              color: Colors.grey,
              icon: Icons.school_outlined,
              features: const [
                '5 AI questions per day',
                'Browse all shared notes',
                'Basic chat rooms',
                'Friend code system',
                '100MB file uploads',
              ],
              currentPlan: true,
              buttonText: 'Current Plan',
              onSelected: () {},
            ),
            const SizedBox(height: 16),

            // Student Pro
            _PricingCard(
              title: 'Student Pro',
              price: 'KSh 250',
              period: '/month',
              color: const Color(0xFF1565C0),
              icon: Icons.auto_awesome,
              popular: true,
              features: const [
                '50 AI questions per day',
                'AI lecture search (RAG)',
                'Web search answers',
                'Unlimited chat rooms',
                '1GB file uploads',
                'Priority support',
                'Custom avatar',
                'Read receipts',
              ],
              currentPlan: false,
              buttonText: 'Subscribe',
              onSelected: () => _showMpesaDialog(context, 'Student Pro', 250),
            ),
            const SizedBox(height: 16),

            // Campus License
            _PricingCard(
              title: 'Campus License',
              price: 'KSh 15,000',
              period: '/semester',
              color: const Color(0xFF2E7D32),
              icon: Icons.business,
              features: const [
                'Unlimited AI for all students',
                'Bulk student enrollment',
                'Custom branding',
                'Lecturer dashboard',
                'Exam prep mode',
                'Analytics & usage reports',
                '50GB shared storage',
                'Dedicated support',
                'API access',
              ],
              currentPlan: false,
              buttonText: 'Contact Us',
              onSelected: () => _showContactDialog(context),
            ),
            const SizedBox(height: 32),

            // Comparison Table
            _buildComparisonTable(theme),
            const SizedBox(height: 32),

            // FAQ
            _buildFAQ(theme),
            const SizedBox(height: 32),

            // Footer
            Text(
              'All prices in Kenya Shillings (KSh). Cancel anytime.\nStudent Pro auto-renews monthly. Campus License per semester.',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showMpesaDialog(BuildContext context, String plan, int amount) {
    final phoneController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Subscribe to $plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.phone_android, size: 48, color: Colors.green[700]),
            const SizedBox(height: 16),
            Text('KSh $amount/month', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'M-Pesa Phone Number',
                hintText: '0712345678',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'An M-Pesa STK push will be sent to your phone to complete payment.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('M-Pesa payment initiated! Check your phone for the STK push.'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            icon: const Icon(Icons.payment),
            label: const Text('Pay with M-Pesa'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700]),
          ),
        ],
      ),
    );
  }

  void _showContactDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Campus License'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.business, size: 48, color: Color(0xFF2E7D32)),
            const SizedBox(height: 16),
            const Text(
              'Get NotesCache for your entire campus.\n\nContact us to discuss pricing, custom branding, and bulk enrollment for your institution.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const ListTile(
              leading: Icon(Icons.email),
              title: Text('support@notescache.com'),
            ),
            const ListTile(
              leading: Icon(Icons.phone),
              title: Text('+254 700 000 000'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _buildComparisonTable(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Feature Comparison', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            _comparisonRow('AI Questions/Day', '5', '50', 'Unlimited'),
            _comparisonRow('Lecture Search (RAG)', false, true, true),
            _comparisonRow('Web Search', false, true, true),
            _comparisonRow('Chat Rooms', '3', 'Unlimited', 'Unlimited'),
            _comparisonRow('File Upload Size', '100MB', '1GB', '10GB'),
            _comparisonRow('Custom Avatar', false, true, true),
            _comparisonRow('Read Receipts', false, true, true),
            _comparisonRow('Priority Support', false, true, true),
            _comparisonRow('Lecturer Dashboard', false, false, true),
            _comparisonRow('Analytics', false, false, true),
            _comparisonRow('Custom Branding', false, false, true),
            _comparisonRow('API Access', false, false, true),
          ],
        ),
      ),
    );
  }

  Widget _comparisonRow(String feature, dynamic free, dynamic pro, dynamic campus) {
    Widget _cell(dynamic val) {
      if (val is bool) {
        return val
            ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
            : const Icon(Icons.cancel, color: Colors.grey, size: 20);
      }
      return Text(val.toString(), style: const TextStyle(fontSize: 12));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(feature, style: const TextStyle(fontSize: 13))),
          Expanded(child: Center(child: _cell(free))),
          Expanded(child: Center(child: _cell(pro))),
          Expanded(child: Center(child: _cell(campus))),
        ],
      ),
    );
  }

  Widget _buildFAQ(ThemeData theme) {
    final faqs = [
      {'q': 'Can I upgrade or downgrade anytime?', 'a': 'Yes! You can switch plans at any time. Changes take effect immediately.'},
      {'q': 'What happens when I hit my AI limit?', 'a': 'You\'ll get a friendly reminder. You can still browse notes and chat — just wait until tomorrow for more AI questions.'},
      {'q': 'Do you accept M-Pesa?', 'a': 'Yes! All payments are processed via M-Pesa STK push. No credit card needed.'},
      {'q': 'Is my data safe?', 'a': 'Absolutely. We use Supabase with enterprise-grade encryption. Your notes and chats are private and secure.'},
      {'q': 'What is the Campus License?', 'a': 'It\'s a bulk license for universities. All students on campus get unlimited access with custom branding and lecturer tools.'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Frequently Asked Questions', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...faqs.map((faq) => ExpansionTile(
          title: Text(faq['q']!, style: const TextStyle(fontWeight: FontWeight.w500)),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(faq['a']!, style: const TextStyle(color: Colors.grey)),
            ),
          ],
        )),
      ],
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String title;
  final String price;
  final String period;
  final Color color;
  final IconData icon;
  final bool popular;
  final List<String> features;
  final bool currentPlan;
  final String buttonText;
  final VoidCallback onSelected;

  const _PricingCard({
    required this.title,
    required this.price,
    required this.period,
    required this.color,
    required this.icon,
    this.popular = false,
    required this.features,
    required this.currentPlan,
    required this.buttonText,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: popular ? color : Colors.grey[300]!,
          width: popular ? 2.5 : 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: popular ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))] : null,
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (popular)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
                    child: const Text('MOST POPULAR', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 8),
                Icon(icon, size: 40, color: color),
                const SizedBox(height: 12),
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(price, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: color)),
                    Text(period, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 20),
                ...features.map((f) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check, size: 18, color: color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                    ],
                  ),
                )),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: currentPlan ? null : onSelected,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: currentPlan ? Colors.grey[300] : color,
                      foregroundColor: currentPlan ? Colors.grey[600] : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          if (popular)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(topRight: Radius.circular(14), bottomLeft: Radius.circular(14)),
                ),
                child: const Icon(Icons.star, color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
