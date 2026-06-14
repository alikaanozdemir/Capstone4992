import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/language_notifier.dart';
import '../services/theme_notifier.dart';
import '../services/history_service.dart';
import '../theme/app_theme.dart';
import '../widgets/disclaimer_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _saveHistory = true;
  String _subtitleSize = 'Large';

  @override
  Widget build(BuildContext context) {
    final isTr = context.watch<LanguageNotifier>().isTurkish;
    final themeNotifier = context.watch<ThemeNotifier>();
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // GÖRÜNÜM / APPEARANCE section
              _SectionLabel(label: isTr ? 'GÖRÜNÜM' : 'APPEARANCE', c: c),
              const SizedBox(height: 8),
              _SettingsCard(c: c, children: [
                ListTile(
                  leading: _IconBox(
                    icon: themeNotifier.isDark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_rounded,
                    color: themeNotifier.isDark
                        ? const Color(0xFF9B59B6)
                        : const Color(0xFFF39C12),
                  ),
                  title: Text(
                    isTr ? 'Karanlık mod' : 'Dark mode',
                    style: TextStyle(
                      fontSize: 14,
                      color: c.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  trailing: Switch.adaptive(
                    value: themeNotifier.isDark,
                    onChanged: (_) => themeNotifier.toggle(),
                    activeColor: AppColors.green,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                ),
              ]),

              const SizedBox(height: 20),

              // OUTPUT section
              _SectionLabel(label: isTr ? 'ÇIKTI' : 'OUTPUT', c: c),
              const SizedBox(height: 8),
              _SettingsCard(c: c, children: [
                _SelectTile(
                  icon: Icons.text_fields_rounded,
                  iconColor: const Color(0xFFE67E22),
                  title: isTr ? 'Altyazı boyutu' : 'Subtitle size',
                  value: _subtitleSize,
                  c: c,
                  onTap: () => _showPicker(
                    context,
                    title: isTr ? 'Altyazı Boyutu' : 'Subtitle Size',
                    options: isTr
                        ? ['Küçük', 'Orta', 'Büyük', 'Çok Büyük']
                        : ['Small', 'Medium', 'Large', 'Extra Large'],
                    selected: _subtitleSize,
                    onSelect: (v) => setState(() => _subtitleSize = v),
                    c: c,
                  ),
                ),
                _Divider(c: c),
                _ToggleTile(
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF3498DB),
                  title: isTr ? 'Geçmişi kaydet' : 'Save history',
                  value: _saveHistory,
                  c: c,
                  onChanged: (v) => setState(() => _saveHistory = v),
                ),
              ]),

              const SizedBox(height: 20),

              // PRIVACY section
              _SectionLabel(label: isTr ? 'GİZLİLİK' : 'PRIVACY', c: c),
              const SizedBox(height: 8),
              _SettingsCard(c: c, children: [
                _TapTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFFE74C3C),
                  title: isTr ? 'Geçmişi temizle' : 'Clear history',
                  c: c,
                  onTap: () => _confirmClear(context, isTr, c),
                ),
                _Divider(c: c),
                _TapTile(
                  icon: Icons.shield_outlined,
                  iconColor: c.textSub,
                  title: isTr ? 'Gizlilik politikası' : 'Privacy policy',
                  c: c,
                  onTap: () => _showPrivacyPolicy(context, isTr, c),
                ),
                _Divider(c: c),
                _TapTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: c.textSub,
                  title: isTr ? 'Önemli not' : 'Important notice',
                  c: c,
                  onTap: () => showDisclaimerDialog(context, isTr: isTr),
                ),
              ]),

              const SizedBox(height: 32),

              Center(
                child: Text(
                  'Sign App v1.0.0',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showPicker(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelect,
    required AppColorSet c,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 12),
            ...options.map((o) => ListTile(
                  title: Text(o,
                      style: TextStyle(
                          color: o == selected ? AppColors.green : c.text,
                          fontWeight: o == selected
                              ? FontWeight.w700
                              : FontWeight.w400)),
                  trailing: o == selected
                      ? const Icon(Icons.check_rounded, color: AppColors.green)
                      : null,
                  onTap: () {
                    onSelect(o);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showPrivacyPolicy(BuildContext context, bool isTr, AppColorSet c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: c.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isTr ? 'Gizlilik Politikası' : 'Privacy Policy',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.text),
              ),
              const SizedBox(height: 16),
              Text(
                isTr
                    ? 'Sign App, kameranızı yalnızca gerçek zamanlı işaret dili tanıma için kullanır. '
                        'Tüm işlemler cihazınızda gerçekleştirilir — harici sunuculara video veya görüntü iletilmez.\n\n'
                        'Çeviri geçmişi, cihazınızda yerel olarak saklanır. '
                        'Geçmişinizi istediğiniz zaman Ayarlar\'daki Gizlilik bölümünden silebilirsiniz.\n\n'
                        'Herhangi bir kişisel veri toplamıyor, paylaşmıyor veya satmıyoruz. '
                        'Uygulama, hesap kaydı veya giriş gerektirmez.\n\n'
                        'Kamera izinleri yalnızca işaret dili tespiti için kullanılır. '
                        'Bu izinler, cihaz ayarlarınızdan istediğiniz zaman iptal edilebilir.'
                    : 'Sign App uses your device camera solely for real-time sign language recognition. '
                        'All processing is performed on-device — no video or images are transmitted to external servers.\n\n'
                        'Translation history is stored locally on your device. '
                        'You can delete your history at any time from the Privacy section in Settings.\n\n'
                        'We do not collect, share, or sell any personal data. '
                        'The app does not require account registration or login.\n\n'
                        'Camera permissions are used exclusively for sign language detection. '
                        'These permissions can be revoked at any time through your device settings.',
                style: TextStyle(fontSize: 14, color: c.textSub, height: 1.6),
              ),
              const SizedBox(height: 20),
              Text(
                isTr ? 'Son güncelleme: Haziran 2025' : 'Last updated: June 2025',
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context, bool isTr, AppColorSet c) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Text(
          isTr ? 'Geçmişi Temizle' : 'Clear History',
          style: TextStyle(color: c.text),
        ),
        content: Text(
          isTr
              ? 'Tüm çeviri geçmişi silinecek. Devam edilsin mi?'
              : 'All translation history will be deleted. Continue?',
          style: TextStyle(color: c.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              isTr ? 'İptal' : 'Cancel',
              style: TextStyle(color: c.textSub),
            ),
          ),
          TextButton(
            onPressed: () async {
              await HistoryService.clear();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Clear', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppColorSet c;
  const _SectionLabel({required this.label, required this.c});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.textSub,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final AppColorSet c;
  const _SettingsCard({required this.children, required this.c});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border, width: 0.5),
        ),
        child: Column(children: children),
      );
}

class _Divider extends StatelessWidget {
  final AppColorSet c;
  const _Divider({required this.c});

  @override
  Widget build(BuildContext context) => Divider(
        height: 0.5,
        thickness: 0.5,
        color: c.border,
        indent: 52,
      );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final AppColorSet c;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
    required this.c,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: _IconBox(icon: icon, color: iconColor),
        title: Text(title,
            style: TextStyle(
                fontSize: 14, color: c.text, fontWeight: FontWeight.w500)),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.green,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

class _SelectTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback onTap;
  final AppColorSet c;

  const _SelectTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: _IconBox(icon: icon, color: iconColor),
        title: Text(title,
            style: TextStyle(
                fontSize: 14, color: c.text, fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: TextStyle(fontSize: 13, color: c.textSub)),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: c.textMuted, size: 18),
          ],
        ),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

class _TapTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;
  final AppColorSet c;

  const _TapTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    required this.c,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: _IconBox(icon: icon, color: iconColor),
        title: Text(title,
            style: TextStyle(
                fontSize: 14, color: c.text, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.chevron_right_rounded, color: c.textMuted, size: 18),
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

class _IconBox extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _IconBox({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 17, color: color),
      );
}
