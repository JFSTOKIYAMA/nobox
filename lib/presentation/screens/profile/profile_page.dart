import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'profile_detail_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil NoBox.ai'),
        backgroundColor: isDark ? const Color(0xFF1F2C34) : Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: isDark ? const Color(0xFF121B22) : Colors.grey[50],
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              children: [
                // Hero Section
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.only(
                      top: 30,
                      bottom: 40,
                      left: 24,
                      right: 24,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF2C3940), const Color(0xFF1F2C34)]
                            : [Colors.blue.shade600, Colors.blue.shade800],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(30),
                        bottomRight: Radius.circular(30),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black26
                              : Colors.blue.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/nobox2.png',
                            height: 50,
                            width: 50,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'NoBox.AI',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'AI-Powered Omnichannel Platform',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.9),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // About NoBox AI Section
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Text(
                          'Informasi NoBox.AI',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _ProfileMenuList(isDark: isDark),
                      const SizedBox(height: 32),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final Uri url = Uri.parse('https://nobox.ai/');
                              if (!await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              )) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Tidak dapat membuka tautan.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Kunjungi Website NoBox.AI'),
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: isDark
                                  ? Colors.blue.shade700
                                  : Colors.blue.shade600,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final Uri url = Uri.parse(
                                'https://docs.nobox.ai/id/docs',
                              );
                              if (!await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              )) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Tidak dapat membuka tautan.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.menu_book, size: 18),
                            label: const Text('Baca Selengkapnya'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? Colors.blue.shade300
                                  : Colors.blue,
                              side: BorderSide(
                                color: isDark
                                    ? Colors.blue.withOpacity(0.3)
                                    : Colors.blue.shade200,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // Footer App Version
                Center(
                  child: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final version = snapshot.hasData
                          ? snapshot.data!.version
                          : '1.0.0';
                      return Column(
                        children: [
                          Image.asset(
                            'assets/nobox2.png',
                            height: 40,
                            color: isDark ? Colors.white30 : Colors.grey[400],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'NoBox Chat App',
                            style: TextStyle(
                              color: isDark ? Colors.white54 : Colors.grey[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Versi $version',
                            style: TextStyle(
                              color: isDark ? Colors.white30 : Colors.grey[500],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileMenuList extends StatefulWidget {
  final bool isDark;
  const _ProfileMenuList({required this.isDark});

  @override
  State<_ProfileMenuList> createState() => _ProfileMenuListState();
}

class _ProfileMenuListState extends State<_ProfileMenuList> {
  final List<ExpansionTileController> _controllers = List.generate(
    7,
    (index) => ExpansionTileController(),
  );
  final List<GlobalKey> _itemKeys = List.generate(7, (index) => GlobalKey());

  Widget _buildRichText(String text, BuildContext context, bool isDark) {
    final List<TextSpan> spans = [];
    final parts = text.split('**');

    final baseStyle = TextStyle(
      color: isDark ? Colors.white70 : Colors.grey.shade700,
      fontSize: 14,
      height: 1.5,
    );

    for (int i = 0; i < parts.length; i++) {
      if (i % 2 == 1) {
        spans.add(
          TextSpan(
            text: parts[i],
            style: baseStyle.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: parts[i], style: baseStyle));
      }
    }
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildMenuSection(
    BuildContext context,
    int index, {
    required String title,
    required String content,
  }) {
    return Padding(
      key: _itemKeys[index],
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: widget.isDark ? const Color(0xFF2C3940) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: widget.isDark 
                  ? Colors.black.withOpacity(0.3) 
                  : Colors.blue.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: widget.isDark ? Colors.white12 : Colors.transparent,
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: Material(
            color: Colors.transparent,
            child: ExpansionTile(
              controller: _controllers[index],
            onExpansionChanged: (isExpanded) {
              if (isExpanded) {
                // Tutup item lain
                for (int i = 0; i < _controllers.length; i++) {
                  if (i != index && _controllers[i].isExpanded) {
                    _controllers[i].collapse();
                  }
                }
                // Gulir ke item ini setelah sedikit delay agar animasi expand mulai
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (_itemKeys[index].currentContext != null) {
                    Scrollable.ensureVisible(
                      _itemKeys[index].currentContext!,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      alignment: 0.1, // Beri sedikit margin di atas
                    );
                  }
                });
              }
            },
            leading: Icon(
              Icons.help_outline,
              color: widget.isDark ? Colors.blue.shade300 : Colors.blue,
              size: 22,
            ),
            title: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: widget.isDark ? Colors.white : const Color(0xFF1F2C34),
                letterSpacing: 0.3,
              ),
            ),
            iconColor: widget.isDark ? Colors.blue.shade300 : Colors.blue,
            collapsedIconColor: widget.isDark
                ? Colors.blue.shade300
                : Colors.blue,
            childrenPadding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 16,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [_buildRichText(content, context, widget.isDark)],
          ),
        ),
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildMenuSection(
          context,
          0,
          title: 'About NoBox.AI',
          content:
              'NoBox.AI is an AI-powered platform designed to integrate communication, marketing, and customer service into a single centralized system. It helps businesses manage customer interactions automatically, structurally, and efficiently.\n\nNoBox.AI supports multiple communication channels such as WhatsApp, Telegram, website, social media, and marketplaces, allowing all customer messages to be managed in one dashboard. With human-like AI technology, the system delivers fast, relevant, and consistent responses.\n\nAdditionally, NoBox.AI includes Automation, AI Agent, Human Agent, monitoring, and reporting features. These enable companies to monitor service performance, manage teams, and analyze customer interaction data comprehensively.',
        ),
        _buildMenuSection(
          context,
          1,
          title: 'Why NoBox.AI?',
          content:
              'NoBox.AI helps businesses improve customer service quality without increasing manual workload. With automation, companies can respond to customers faster and more accurately.',
        ),
        _buildMenuSection(
          context,
          2,
          title: 'Key Advantages',
          content:
              '• Saves time and operational costs through service automation.\n• Improves customer satisfaction with fast and consistent responses.\n• Simplifies communication management from multiple platforms in one system.\n• Supports data-driven decision-making with reporting and monitoring features.\n• Flexible and customizable to business needs.\n\nWith these advantages, NoBox.AI is the right solution for SMEs to large enterprises to build professional, modern, and sustainable customer service.',
        ),
        _buildMenuSection(
          context,
          3,
          title: 'Target Users',
          content:
              'NoBox.AI is designed to help various organizations and businesses manage communication and customer service more effectively:\n\n• **SMEs:** Manage messages, promotions, and automated services without a large team.\n• **Medium & Large Enterprises:** Support complex CS operations with integrated systems and reporting.\n• **Digital Startups:** Build modern AI-based customer service systems.\n• **Educational Institutions:** Handle student and parent inquiries across channels.\n• **Government Agencies:** Support responsive and transparent public services.\n• **E-Commerce & Marketplaces:** Automated and centralized order and complaint management.',
        ),
        _buildMenuSection(
          context,
          4,
          title: 'Overview',
          content:
              'NoBox.AI is an artificial intelligence (AI) application designed to enhance marketing and customer service quality in educational institutions, businesses, and government. The platform helps collect, manage, and analyze customer data in an integrated manner.\n\nWith intelligent chatbot support and omnichannel systems, NoBox.AI can handle customer communication 24/7 throughout the year, enabling businesses to provide faster, more consistent, and professional service.',
        ),
        _buildMenuSection(
          context,
          5,
          title: 'Core NoBox.AI Modules',
          content:
              'NoBox.AI consists of several core modules that integrate to support comprehensive business operations, from customer communication to system management.\n\n• **Messages:** Manage all customer conversations from multiple channels.\n• **CRM:** Store and manage customer data, prospect status, and sales activities.\n• **Forms:** Create digital forms for registration and customer surveys.\n• **Promotions:** Schedule and send promotional messages and marketing campaigns.\n• **Contacts:** Manage customer databases.\n• **Accounts:** Manage user accounts, licenses, and service status.\n• **AI Agents:** Manage AI chatbots based on scenarios.\n• **Human Agents:** Manage human agents for advanced conversations.\n• **Subscriptions:** Service package and feature information.\n• **Billing:** Manage invoices and transaction status.\n• **Settings:** Comprehensive system configuration including profile, file manager, and integrations.',
        ),
        _buildMenuSection(
          context,
          6,
          title: 'Feature Details',
          content:
              'NoBox.AI offers various advantages supporting ease of use, data security, and system integration.\n\n**Interface:**\n• **Role-based Menus:** Menu display tailored to user roles\n• **Data Tracking:** Easy monitoring of system activities and data\n• **Flexible Layout:** Customizable layout per user needs\n• **Theme Options:** Light and dark themes available\n\n**Security:**\n• **User Access Rights:** Role-based access control\n\n**Integration:**\n• **Contact Import:** Supports Excel and CSV files\n• **Contact Export:** Supports Google Contacts format',
        ),
      ],
    );
  }
}
