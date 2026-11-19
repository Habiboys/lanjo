import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/providers/service_providers.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/file_ops.dart';

/// Encrypted `.arusbackup` export and verified restore page (FR-27).
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  final _passCtrl = TextEditingController();
  bool _includeAttachments = true;
  bool _busy = false;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _createBackup() async {
    final pass = _passCtrl.text;
    if (pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password backup minimal 6 karakter.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final file = await ref.read(backupServiceProvider).createEncryptedBackup(
            password: pass,
            includeAttachments: _includeAttachments,
          );
      if (!mounted) return;
      await Share.shareXFiles(
        [file],
        subject: 'Backup Terenkripsi Lanjo',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restoreBackup() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (picked == null || !mounted) return;
    final bytes = picked.files.single.bytes ??
        await readFileBytesByPathImpl(picked.files.single.path);
    if (bytes == null || !mounted) return;

    final passCtrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Masukkan Password Backup'),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, passCtrl.text),
            child: const Text('Periksa File'),
          ),
        ],
      ),
    );
    if (pass == null || pass.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final svc = ref.read(backupServiceProvider);
      final manifest = await svc.inspectBackupBytes(
        bytes: bytes,
        password: pass,
      );
      if (!mounted) return;

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Konfirmasi Restore'),
          content: Text(
            'Backup valid ✅\n'
            'Dibuat: ${ArusDateUtils.formatDateTime(manifest.createdAt)}\n'
            'Versi schema: ${manifest.schemaVersion}\n'
            'Lampiran: ${manifest.attachmentCount} file\n\n'
            'Restore akan mengganti seluruh data lokal saat ini (snapshot keamanan dibuat otomatis sebelum menimpa).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore Sekarang'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;

      await svc.restoreFromBytes(
        bytes: bytes,
        password: pass,
        onReopenDatabase: () async {
          ref.invalidate(appDatabaseProvider);
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Restore berhasil diselesaikan!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & Restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const ListTile(
              leading: Icon(LucideIcons.alertTriangle, size: 20),
              title: Text('Data Tersimpan Lokal di Perangkat'),
              subtitle: Text(
                'Menghapus aplikasi atau kehilangan perangkat tanpa backup akan menghilangkan data keuanganmu. Backup terenkripsi tidak menyertakan API Key AI atau PIN.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Buat Backup Terenkripsi (.arusbackup)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (settings?.lastBackupAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Backup terakhir: ${ArusDateUtils.formatDateTime(settings!.lastBackupAt!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Password enkripsi backup (min. 6 karakter)',
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sertakan foto lampiran struk'),
                    value: _includeAttachments,
                    onChanged: (v) => setState(() => _includeAttachments = v),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _createBackup,
                      icon: const Icon(LucideIcons.lock, size: 17),
                      label: Text(_busy ? 'Memproses...' : 'Export Backup'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(LucideIcons.rotateCcw, size: 20),
              title: const Text('Restore dari File Backup'),
              subtitle: const Text('Validasi password, checksum & versi schema'),
              trailing: const Icon(LucideIcons.chevronRight, size: 16),
              onTap: _busy ? null : _restoreBackup,
            ),
          ),
        ],
      ),
    );
  }
}
