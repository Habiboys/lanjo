import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';

/// AI Financial Assistant chat backed strictly by local deterministic SQLite
/// summary functions (FR-20).
class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _msgCtrl = TextEditingController();
  final List<({String role, String text})> _messages = [];
  String? _conversationId;
  bool _sending = false;

  static const _suggestedQuestions = [
    'Kenapa uangku cepat habis bulan ini?',
    'Berapa total pengeluaran makan bulan ini?',
    'Apakah pengeluaran bulan ini lebih besar dari bulan lalu?',
    'Kalau beli sepatu Rp500 ribu, bagaimana dampaknya ke Safe-to-Spend?',
  ];

  @override
  void initState() {
    super.initState();
    _initConversation();
  }

  Future<void> _initConversation() async {
    final db = ref.read(appDatabaseProvider);
    final existing = await (db.select(db.aiConversations)
          ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (existing != null) {
      _conversationId = existing.id;
      final msgs = await (db.select(db.aiMessages)
            ..where((m) => m.conversationId.equals(existing.id))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();
      if (mounted) {
        setState(() {
          for (final m in msgs) {
            _messages.add((role: m.role, text: m.content));
          }
        });
      }
    } else {
      final id = const Uuid().v4();
      final now = DateTime.now();
      await db.into(db.aiConversations).insert(
            AiConversationsCompanion.insert(
              id: id,
              title: 'Asisten Keuangan Lanjo',
              createdAt: now,
              updatedAt: now,
            ),
          );
      _conversationId = id;
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty || _sending) return;
    _msgCtrl.clear();
    setState(() {
      _messages.add((role: 'user', text: q));
      _sending = true;
    });

    try {
      final reply = await ref.read(aiFinanceServiceProvider).askAssistant(
            question: q,
            conversationId: _conversationId,
          );
      if (mounted) {
        setState(() => _messages.add((role: 'assistant', text: reply)));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _messages.add((role: 'assistant', text: 'Maaf, terjadi kendala: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _clearHistory() async {
    final db = ref.read(appDatabaseProvider);
    if (_conversationId != null) {
      await (db.delete(db.aiMessages)
            ..where((m) => m.conversationId.equals(_conversationId!)))
          .go();
    }
    setState(() => _messages.clear());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(appSettingsProvider).valueOrNull;
    final aiEnabled = settings?.aiEnabled ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Asisten Keuangan AI'),
        actions: [
          IconButton(
            tooltip: 'Hapus histori chat',
            icon: const Icon(LucideIcons.trash2, size: 19),
            onPressed: _clearHistory,
          ),
          IconButton(
            tooltip: 'Pengaturan AI',
            icon: const Icon(LucideIcons.slidersHorizontal, size: 19),
            onPressed: () => context.push('/settings/ai'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!aiEnabled)
            MaterialBanner(
              content: const Text(
                'Asisten AI nonaktif. Aktifkan dengan API Key Gemini / OpenCode milikmu di Pengaturan.',
              ),
              actions: [
                TextButton(
                  onPressed: () => context.push('/settings/ai'),
                  child: const Text('Atur AI'),
                ),
              ],
            ),
          Expanded(
            child: _messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text(
                        'Tanyakan kondisi keuanganmu. Angka dihitung langsung secara lokal dari SQLite sebelum dijelaskan oleh AI:',
                      ),
                      const SizedBox(height: 12),
                      for (final q in _suggestedQuestions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ActionChip(
                            label: Text(q),
                            onPressed: () => _send(q),
                          ),
                        ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final m = _messages[index];
                      final isUser = m.role == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 12,
                          ),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color: isUser
                                ? theme.colorScheme.primary
                                : context.lanjoCard,
                            borderRadius: BorderRadius.circular(18),
                            border: isUser
                                ? null
                                : Border.all(color: context.lanjoBorder),
                          ),
                          child: Text(
                            m.text,
                            style: TextStyle(
                              height: 1.45,
                              color: isUser
                                  ? Colors.white
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_sending) const LinearProgressIndicator(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Tanya soal pengeluaran atau tabungan...',
                      ),
                      onSubmitted: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(_msgCtrl.text),
                    icon: const Icon(LucideIcons.send, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
