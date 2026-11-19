# Lanjo — Personal Finance & Smart Money Assistant

**Lanjo** adalah aplikasi pencatat keuangan pribadi & asisten manajemen uang harian berbasis **Flutter (Local-First & Offline-First)** dengan sistem pembukuan *double-entry ledger* di atas **SQLite (Drift)**, antarmuka modern minimalis, integrasi **BYOK AI (Google Gemini & OpenCode Inference)**, serta fitur pintar native Android.

## Fitur Utama

- **100% Local-First & Offline-First:** Seluruh data dompet, transaksi, anggaran, tagihan, dan utang tersimpan secara lokal di perangkat tanpa perlu registrasi akun.
- **Double-Entry Ledger & Multi-Wallet:** Mendukung rekening bank, uang tunai, e-wallet, tabungan terpisah, kartu kredit/paylater, transfer antar-dompet beserta biaya admin, dan rekonsiliasi saldo.
- **Safe-to-Spend Harian & Skor Kesehatan Finansial:** Menghitung batas aman belanja harian sampai tanggal gajian berikutnya secara otomatis dengan memperhitungkan tagihan, alokasi tabungan, dan cadangan dana.
- **Kalkulator Transaksi Pintar:** Dilengkapi tombol `000`, preset `+10% PB1`, `+11% PPN`, `+15% Tax+Service`, `-10% Diskon`, `÷2 Bagi Dua`, serta pembaca skala Rupiah *live*.
- **Asisten AI (BYOK Gemini & OpenCode):**
  - *Catat Cepat dengan AI* (input teks bebas multi-item & multi-tanggal + input suara).
  - *Scan Struk AI (OCR)* dari kamera, galeri, atau *Share Target* bukti transfer m-Banking.
  - *Chat Asisten Keuangan AI* berbasis data SQLite lokal.
- **Perencanaan Keuangan Lengkap:** Anggaran (*Budget*) dengan *rollover*, Tagihan & *Subscription*, Target Tabungan, Utang & Piutang (lengkap dengan simulator cicilan & strategi pelunasan *Snowball vs Avalanche*), *Wishlist* & Simulasi Beli, *Split Bill*, dan *Salary Day* (50/30/20).
- **Integrasi Native Android:** Home Screen Widget (*Lanjo Safe-to-Spend*), Quick Settings Tile (*Catat Lanjo*), Launcher App Shortcuts, *Share Target* gambar/teks, dan *Smart Notification Auto-Detector* lokal.
- **Keamanan & Portabilitas Data:** Kunci PIN & Biometrik, *Backup & Restore* terenkripsi (`.arusbackup` AES-GCM), serta *Import/Export* CSV, Excel, dan laporan PDF.

## Menjalankan Proyek

```bash
flutter pub get
flutter test
flutter run
```
