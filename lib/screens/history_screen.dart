import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/translation_entry.dart';
import '../services/history_service.dart';
import '../services/language_notifier.dart';
import '../theme/app_theme.dart';
import '../widgets/type_badge.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<TranslationEntry> _all = [];
  List<TranslationEntry> _filtered = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.toLowerCase();
        _filtered = _all
            .where((e) => e.text.toLowerCase().contains(_query))
            .toList();
      });
    });
  }

  Future<void> _loadHistory() async {
    final entries = await HistoryService.load();
    if (mounted) {
      setState(() {
        _all = entries;
        _filtered = entries;
        _loading = false;
      });
    }
  }

  Future<void> _clearAll() async {
    await HistoryService.clear();
    if (mounted) {
      setState(() {
        _all = [];
        _filtered = [];
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt, bool isTr) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 0) {
      return isTr ? 'Bugün $time' : 'Today $time';
    } else if (diff.inDays == 1) {
      return isTr ? 'Dün $time' : 'Yesterday $time';
    } else {
      return isTr ? '${diff.inDays} gün önce' : '${diff.inDays} days ago';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTr = context.watch<LanguageNotifier>().isTurkish;
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isTr ? 'Geçmiş' : 'History',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showClearDialog(context),
                    icon: Icon(Icons.delete_outline_rounded, color: c.textSub),
                  ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border, width: 0.5),
                ),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: c.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: isTr ? 'Çeviri ara...' : 'Search translations...',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 14),
                    prefixIcon: Icon(Icons.search, color: c.textMuted, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    suffixIcon: _query.isNotEmpty
                        ? GestureDetector(
                            onTap: () => _searchController.clear(),
                            child: Icon(Icons.close, color: c.textMuted, size: 18),
                          )
                        : null,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // List
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.green, strokeWidth: 2),
                    )
                  : _filtered.isEmpty
                      ? Center(
                          child: Text(
                            _query.isNotEmpty
                                ? (isTr ? 'Sonuç bulunamadı' : 'No results found')
                                : (isTr ? 'Henüz çeviri yok' : 'No translations yet'),
                            style: TextStyle(color: c.textSub, fontSize: 14),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.green,
                          onRefresh: _loadHistory,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => Divider(
                              color: c.border,
                              height: 0.5,
                              thickness: 0.5,
                            ),
                            itemBuilder: (_, i) {
                              final entry = _filtered[i];
                              return _HistoryItem(
                                entry: entry,
                                timeLabel: _formatTime(entry.createdAt, isTr),
                                c: c,
                              );
                            },
                          ),
                        ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border, width: 0.5)),
              ),
              child: Text(
                isTr
                    ? 'Toplam ${_all.length} çeviri'
                    : '${_all.length} translation${_all.length == 1 ? '' : 's'} total',
                style: TextStyle(fontSize: 12, color: c.textSub),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    final isTr = context.read<LanguageNotifier>().isTurkish;
    final c = AppColors.of(context);
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
              ? 'Tüm çeviri geçmişi silinecek. Devam etmek istiyor musunuz?'
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
            onPressed: () {
              Navigator.pop(context);
              _clearAll();
            },
            child: Text(
              isTr ? 'Temizle' : 'Clear',
              style: const TextStyle(color: Color(0xFFE74C3C)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final TranslationEntry entry;
  final String timeLabel;
  final AppColorSet c;

  const _HistoryItem({
    required this.entry,
    required this.timeLabel,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.sign_language_rounded,
              size: 18,
              color: AppColors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.text,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: c.text,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text(
                      timeLabel,
                      style: TextStyle(fontSize: 11, color: c.textSub),
                    ),
                    const SizedBox(width: 8),
                    TypeBadge(type: entry.type),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.chevron_right_rounded, color: c.textMuted, size: 18),
        ],
      ),
    );
  }
}
