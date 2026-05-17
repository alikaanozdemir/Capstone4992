import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoSpeak = true;
  bool _saveHistory = true;
  String _model = 'TSİD v2.1';
  String _inferenceMode = 'Hibrit';
  String _subtitleSize = 'Büyük';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // User card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 0.5),
                ),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Center(
                        child: Text(
                          'AY',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ayşe Yılmaz',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.bgCard2,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pro plan · TSİD + TİD',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSub,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // MODEL section
              _SectionLabel(label: 'MODEL'),
              const SizedBox(height: 8),
              _SettingsCard(children: [
                _SelectTile(
                  icon: Icons.sign_language_rounded,
                  iconColor: AppColors.green,
                  title: 'İşaret dili',
                  value: _model,
                  onTap: () => _showPicker(
                    context,
                    title: 'İşaret Dili Modeli',
                    options: ['TSİD v2.1', 'TSİD v1.8', 'TİD Beta'],
                    selected: _model,
                    onSelect: (v) => setState(() => _model = v),
                  ),
                ),
                _Divider(),
                _SelectTile(
                  icon: Icons.memory_rounded,
                  iconColor: AppColors.teal,
                  title: 'Çıkarım modu',
                  value: _inferenceMode,
                  onTap: () => _showPicker(
                    context,
                    title: 'Çıkarım Modu',
                    options: ['Hibrit', 'Sadece Cihaz', 'Bulut'],
                    selected: _inferenceMode,
                    onSelect: (v) => setState(() => _inferenceMode = v),
                  ),
                ),
              ]),

              const SizedBox(height: 20),

              // ÇIKTI section
              _SectionLabel(label: 'ÇIKTI'),
              const SizedBox(height: 8),
              _SettingsCard(children: [
                _ToggleTile(
                  icon: Icons.volume_up_rounded,
                  iconColor: const Color(0xFF9B59B6),
                  title: 'Otomatik seslendir',
                  value: _autoSpeak,
                  onChanged: (v) => setState(() => _autoSpeak = v),
                ),
                _Divider(),
                _SelectTile(
                  icon: Icons.text_fields_rounded,
                  iconColor: const Color(0xFFE67E22),
                  title: 'Altyazı boyutu',
                  value: _subtitleSize,
                  onTap: () => _showPicker(
                    context,
                    title: 'Altyazı Boyutu',
                    options: ['Küçük', 'Orta', 'Büyük', 'Çok Büyük'],
                    selected: _subtitleSize,
                    onSelect: (v) => setState(() => _subtitleSize = v),
                  ),
                ),
                _Divider(),
                _ToggleTile(
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFF3498DB),
                  title: 'Geçmişi kaydet',
                  value: _saveHistory,
                  onChanged: (v) => setState(() => _saveHistory = v),
                ),
              ]),

              const SizedBox(height: 20),

              // GİZLİLİK section
              _SectionLabel(label: 'GİZLİLİK'),
              const SizedBox(height: 8),
              _SettingsCard(children: [
                _TapTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFFE74C3C),
                  title: 'Geçmişi temizle',
                  onTap: () => _confirmClear(context),
                ),
                _Divider(),
                _TapTile(
                  icon: Icons.shield_outlined,
                  iconColor: AppColors.textSub,
                  title: 'Gizlilik politikası',
                  onTap: () {},
                ),
              ]),

              const SizedBox(height: 32),

              // Version
              Center(
                child: Text(
                  'Sign App v1.0.0',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
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
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
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
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 12),
            ...options.map((o) => ListTile(
                  title: Text(o,
                      style: TextStyle(
                          color: o == selected ? AppColors.green : AppColors.text,
                          fontWeight: o == selected ? FontWeight.w700 : FontWeight.w400)),
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

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Geçmişi Temizle', style: TextStyle(color: AppColors.text)),
        content: const Text(
          'Tüm çeviri geçmişi silinecek. Devam etmek istiyor musunuz?',
          style: TextStyle(color: AppColors.textSub),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Temizle', style: TextStyle(color: Color(0xFFE74C3C))),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textSub,
            letterSpacing: 1.2,
          ),
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(children: children),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.border,
        indent: 52,
      );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: _IconBox(icon: icon, color: iconColor),
        title: Text(title,
            style: const TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500)),
        trailing: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.green,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

class _SelectTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;
  final VoidCallback onTap;

  const _SelectTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: _IconBox(icon: icon, color: iconColor),
        title: Text(title,
            style: const TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
          ],
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      );
}

class _TapTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onTap;

  const _TapTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
        leading: _IconBox(icon: icon, color: iconColor),
        title: Text(title,
            style: const TextStyle(fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted, size: 18),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
