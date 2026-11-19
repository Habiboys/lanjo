# PRODUCT REQUIREMENTS DOCUMENT (PRD)

# Arus — Personal Finance & Smart Money Assistant

**Versi:** 1.0  
**Platform:** Mobile Application — Flutter  
**Pendekatan:** Local-First, Offline-First  
**AI Provider:** Google Gemini API — Bring Your Own API Key  
**Notification:** Local Notification & Firebase Cloud Messaging  
**Database:** SQLite dengan Drift  
**Status:** Draft Product Specification  
**Nama produk:** Arus (nama sementara)

---

# 1. Product Overview

## 1.1 Latar Belakang

Banyak orang mengalami kesulitan mengelola keuangan pribadi bukan karena tidak memiliki pemasukan, tetapi karena kurang memahami ke mana uang mereka digunakan, tidak memiliki perencanaan pengeluaran yang baik, dan tidak konsisten melakukan pencatatan transaksi.

Aplikasi keuangan konvensional umumnya mengharuskan pengguna mengisi formulir transaksi secara manual, memilih kategori, memasukkan nominal, menentukan sumber dana, dan mengulangi proses tersebut setiap hari. Proses ini membuat pengguna cepat merasa bosan dan berhenti melakukan pencatatan.

Selain itu, banyak aplikasi keuangan hanya membantu pengguna melihat pengeluaran yang sudah terjadi, tetapi belum cukup membantu pengguna mengambil keputusan sebelum melakukan pengeluaran.

Arus dirancang sebagai aplikasi pengelolaan keuangan pribadi yang menggabungkan pencatatan transaksi sederhana, perencanaan keuangan, analisis pengeluaran, dan asisten AI untuk membantu pengguna mengelola uang dengan lebih mudah.

Seluruh data utama pengguna disimpan pada perangkat sehingga aplikasi dapat digunakan tanpa koneksi internet, tanpa akun cloud, dan tanpa backend yang menyimpan data keuangan.

## 1.2 Visi Produk

Menjadi aplikasi keuangan pribadi yang membantu pengguna mencatat, memahami, merencanakan, dan mengambil keputusan finansial secara mudah, cepat, personal, dan privat.

## 1.3 Value Proposition

**"Catat uang tanpa ribet, pahami keuanganmu, dan tahu berapa yang aman kamu belanjakan."**

Tiga nilai utama produk:

1. **Effortless Tracking:** pencatatan keuangan melalui input cepat, bahasa natural, template, suara, dan scan struk.
2. **Smart Financial Decision:** membantu pengguna mengetahui kondisi keuangan, anggaran harian, dan dampak keputusan pembelian.
3. **Privacy First:** seluruh data utama tersimpan lokal, tanpa keharusan registrasi maupun sinkronisasi cloud.

## 1.4 Tujuan Produk

- Memungkinkan transaksi sederhana dicatat dalam waktu kurang dari 5 detik.
- Membantu pengguna memahami pemasukan, pengeluaran, dan saldo secara akurat.
- Membantu pengguna mengetahui batas pengeluaran yang wajar sampai pemasukan berikutnya.
- Meningkatkan konsistensi pencatatan melalui reminder dan input otomatis.
- Membantu pengguna mencapai target tabungan.
- Menyediakan pengalaman pengelolaan keuangan yang tetap berjalan tanpa internet.
- Memberikan manfaat AI tanpa mewajibkan pengguna berlangganan layanan aplikasi.

---

# 2. Target Pengguna

## 2.1 Primary User

- Mahasiswa yang mengatur uang bulanan.
- Fresh graduate dan karyawan yang menerima gaji rutin.
- Anak kos yang mengelola biaya hidup secara mandiri.
- Freelancer dengan pemasukan tidak tetap.
- Individu yang memiliki beberapa rekening bank, e-wallet, dan uang tunai.

## 2.2 User Persona

**Persona 1 — Karyawan**

Menerima gaji Rp5 juta setiap bulan. Memiliki pengeluaran kos, makanan, transportasi, hiburan, dan target tabungan. Membutuhkan informasi mengenai berapa uang yang tersedia sampai gajian berikutnya.

**Persona 2 — Mahasiswa**

Menerima uang bulanan dari orang tua. Sering melakukan transaksi kecil dan kesulitan mengingat pengeluaran sehari-hari. Membutuhkan pencatatan yang cepat dan sederhana.

**Persona 3 — Freelancer**

Memiliki pemasukan yang tidak tetap dan berasal dari beberapa proyek. Membutuhkan pencatatan pemasukan, pengelolaan piutang, dana cadangan, dan proyeksi arus kas.

---

# 3. Product Scope

## 3.1 In Scope

Aplikasi mencakup:

1. Pengelolaan profil lokal.
2. Pengelolaan rekening dan dompet.
3. Pencatatan pemasukan, pengeluaran, dan transfer.
4. Kategori dan subkategori transaksi.
5. Quick Add dan template transaksi.
6. Budgeting dan alokasi dana.
7. Tagihan rutin dan subscription tracker.
8. Target tabungan.
9. Utang, piutang, dan cicilan.
10. Split Bill.
11. Safe-to-Spend.
12. Salary Day.
13. Wishlist dan simulasi pembelian.
14. AI Quick Expense.
15. AI Receipt Scanner.
16. Voice Input.
17. AI Financial Assistant.
18. Laporan dan analisis keuangan.
19. Import transaksi dan rekonsiliasi saldo.
20. Local Notification dan FCM.
21. Backup, restore, dan export.
22. Pengaturan keamanan dan privasi.

## 3.2 Out of Scope

Fitur berikut tidak menjadi bagian pengembangan awal:

- Integrasi langsung dengan API rekening bank.
- Transfer uang atau pembayaran sungguhan.
- Pinjaman online dan layanan kredit.
- Trading saham atau cryptocurrency.
- Cloud database.
- Cloud synchronization.
- Registrasi dan autentikasi akun melalui server.
- Pengelolaan keuangan perusahaan.
- Shared wallet secara real-time antarperangkat.

Aplikasi merupakan alat pengelolaan dan pencatatan keuangan, bukan penyedia layanan perbankan.

---

# 4. Product Principles

## 4.1 Local-First

SQLite menjadi sumber data utama aplikasi. Seluruh proses pencatatan, perhitungan saldo, laporan, anggaran, dan target tabungan dijalankan pada perangkat.

Aplikasi tidak membutuhkan Firebase Firestore, Supabase, MySQL server, atau backend khusus untuk fitur utama.

## 4.2 Offline-First

Seluruh fitur utama tetap berfungsi saat perangkat tidak terhubung ke internet.

Fitur yang memerlukan internet:

- Gemini AI.
- Firebase Cloud Messaging.
- Pengiriman voice input ke layanan eksternal apabila pengenalan suara lokal tidak tersedia dan pengguna menyetujuinya.

Jika internet tidak tersedia, aplikasi menyediakan alternatif pencatatan manual.

## 4.3 AI Optional

AI merupakan fitur tambahan, bukan ketergantungan utama aplikasi.

Pengguna dapat menggunakan aplikasi sepenuhnya tanpa mengaktifkan Gemini API.

Seluruh hasil AI harus dianggap sebagai usulan yang perlu divalidasi sebelum memengaruhi data keuangan.

## 4.4 No Unnecessary Friction

Pencatatan transaksi tidak boleh membutuhkan terlalu banyak langkah.

Aplikasi harus mengutamakan default wallet, kategori yang sering digunakan, transaksi favorit, input nominal cepat, dan kemampuan undo.

## 4.5 Accuracy First

Seluruh perhitungan saldo, transaksi, utang, anggaran, dan laporan dilakukan oleh logika aplikasi yang deterministik, bukan oleh AI.

## 4.6 User Data Ownership

Pengguna memiliki kendali penuh terhadap data lokalnya, termasuk export, backup, restore, dan penghapusan data.

---

# 5. Information Architecture

Aplikasi menggunakan lima navigasi utama:

| Menu | Fungsi |
|---|---|
| Beranda | Dashboard, saldo, safe-to-spend, ringkasan |
| Transaksi | Riwayat transaksi, filter, pencarian |
| Catat (+) | Input manual, AI, scan, transfer, suara |
| Rencana | Budget, tagihan, target, utang, wishlist |
| Pengaturan | Wallet, kategori, Gemini API, keamanan, backup |

## 5.1 Beranda

Menampilkan:

- Total saldo.
- Saldo yang dapat digunakan.
- Safe-to-Spend.
- Pemasukan dan pengeluaran periode berjalan.
- Quick Action.
- Daftar wallet.
- Transaksi terbaru.
- Tagihan mendatang.
- Progress anggaran.
- Financial Insight.
- Akses laporan lengkap.

## 5.2 Transaksi

Menampilkan:

- Seluruh transaksi.
- Pencarian berdasarkan nominal, deskripsi, dan kategori.
- Filter tanggal, wallet, jenis transaksi, kategori, dan tag.
- Detail transaksi.
- Edit dan hapus transaksi.
- Duplikasi transaksi.
- Export hasil pencarian.

## 5.3 Catat

Tombol utama yang membuka bottom sheet dengan pilihan:

- Pengeluaran.
- Pemasukan.
- Transfer.
- Catat dengan AI.
- Scan struk.
- Input suara.
- Transaksi favorit.

## 5.4 Rencana

Memiliki subhalaman:

- Anggaran.
- Tagihan & Subscription.
- Target tabungan.
- Utang & Piutang.
- Wishlist.
- Split Bill.
- Salary Day.

## 5.5 Pengaturan

Memiliki subhalaman:

- Profil.
- Dompet dan rekening.
- Kategori.
- Pengaturan AI.
- Notifikasi.
- Tampilan.
- Mata uang dan periode keuangan.
- Keamanan.
- Import dan export.
- Backup dan restore.
- Tentang aplikasi.

---

# 6. Functional Requirements

## FR-01 — Onboarding & Profil Lokal

**Prioritas: P0**

Pengguna dapat menggunakan aplikasi tanpa registrasi atau login.

### Alur onboarding

1. Pengguna membuka aplikasi untuk pertama kali.
2. Aplikasi menampilkan pengenalan singkat.
3. Pengguna memasukkan nama panggilan secara opsional.
4. Pengguna memilih mata uang.
5. Pengguna membuat dompet pertama.
6. Pengguna memasukkan saldo awal.
7. Pengguna dapat menentukan tanggal gajian.
8. Aplikasi menampilkan dashboard.

### Ketentuan

- Mata uang default adalah Rupiah (IDR).
- Pengaturan tanggal gajian dapat dilewati.
- Pengaturan Gemini API dapat dilewati.
- Biometrik dan PIN bersifat opsional.
- Tidak memerlukan email, nomor telepon, atau akun Firebase.

### Acceptance Criteria

- Pengguna dapat menyelesaikan onboarding tanpa internet.
- Profil dan pengaturan tersimpan setelah aplikasi ditutup.
- Saldo awal tidak dihitung sebagai pemasukan bulanan.

---

## FR-02 — Wallet Management

**Prioritas: P0**

Pengguna dapat mengelola beberapa tempat penyimpanan uang.

### Jenis wallet

- Cash.
- Bank Account.
- E-Wallet.
- Savings.
- Credit Card.
- PayLater.
- Other.

### Informasi wallet

- Nama wallet.
- Jenis wallet.
- Icon.
- Warna.
- Mata uang.
- Saldo awal.
- Status aktif.
- Status penyertaan dalam total saldo.
- Status dana yang dapat digunakan.
- Urutan tampilan.

### Fitur

- Tambah, edit, dan arsip wallet.
- Menentukan default wallet.
- Menyembunyikan saldo.
- Mengatur urutan wallet.
- Melihat riwayat transaksi per wallet.
- Rekonsiliasi saldo aktual.

### Aturan bisnis

Wallet aset memiliki saldo dana, sedangkan kartu kredit dan PayLater merepresentasikan kewajiban.

Saldo wallet tidak boleh diubah langsung tanpa pencatatan penyesuaian saldo.

Wallet yang sudah memiliki transaksi tidak dapat dihapus permanen melalui operasi penghapusan biasa. Wallet dapat diarsipkan agar riwayat keuangan tetap terjaga.

Wallet yang diarsipkan dengan saldo tidak nol harus tetap diperhitungkan dalam laporan kekayaan bersih atau diselesaikan melalui transfer maupun penyesuaian saldo.

### Acceptance Criteria

- Pengguna dapat membuat beberapa wallet.
- Saldo berubah sesuai transaksi.
- Wallet tabungan yang dikecualikan dari dana belanja tetap dapat masuk dalam total aset.
- Pengarsipan wallet tidak menghilangkan riwayat transaksi.

---

## FR-03 — Transaction Management

**Prioritas: P0**

Pengguna dapat mencatat seluruh aktivitas keuangan.

### Jenis transaksi

1. Income.
2. Expense.
3. Transfer.
4. Balance Adjustment.
5. Debt Disbursement.
6. Debt Repayment.
7. Refund.

### Informasi transaksi

- ID transaksi.
- Jenis transaksi.
- Nominal.
- Tanggal dan waktu.
- Wallet.
- Kategori dan subkategori.
- Deskripsi.
- Merchant.
- Tag.
- Attachment.
- Lokasi opsional.
- Sumber input: manual, AI, scan, voice, import, template.
- Status transaksi.
- Tanggal pembuatan dan perubahan.

### Fitur

- Tambah transaksi.
- Edit transaksi.
- Hapus transaksi.
- Undo.
- Duplikasi transaksi.
- Split kategori.
- Pencarian dan filter.
- Lampiran foto struk.
- Pencatatan transaksi dengan tanggal sebelumnya.

### Aturan bisnis

- Nominal transaksi harus lebih besar dari nol.
- Saldo awal tidak termasuk pendapatan.
- Transfer internal tidak termasuk pemasukan atau pengeluaran.
- Penyesuaian saldo tidak dikategorikan sebagai pendapatan atau pengeluaran normal.
- Refund mengurangi pengeluaran pada kategori terkait, dengan referensi transaksi asal jika tersedia.
- Perubahan transaksi harus memperbarui seluruh saldo, anggaran, dan laporan terkait.
- Seluruh perubahan transaksi keuangan dijalankan secara atomik.
- Saldo negatif pada wallet aset memunculkan peringatan. Pengguna dapat mengonfirmasi pencatatan apabila memang merepresentasikan kondisi aktual.

### Acceptance Criteria

- Pengeluaran Rp25.000 mengurangi saldo wallet sebesar Rp25.000.
- Pemasukan Rp5.000.000 menambah saldo wallet sebesar Rp5.000.000.
- Edit nominal Rp25.000 menjadi Rp30.000 menghasilkan selisih perubahan saldo Rp5.000.
- Hapus transaksi mengembalikan pengaruh transaksi terhadap saldo.
- Transaksi dengan beberapa kategori memiliki total alokasi yang sama dengan nominal transaksi.

---

## FR-04 — Transfer Antarwallet

**Prioritas: P0**

Pengguna dapat mencatat perpindahan uang antar rekening atau dompet.

### Contoh

Transfer BCA ke GoPay sebesar Rp100.000 dengan biaya admin Rp1.000.

Hasil:

- Saldo BCA berkurang Rp101.000.
- Saldo GoPay bertambah Rp100.000.
- Pengeluaran bertambah Rp1.000.
- Total aset berkurang Rp1.000.

### Ketentuan

- Wallet asal dan tujuan tidak boleh sama.
- Transfer hanya dicatat sekali sebagai satu transaksi yang terhubung.
- Biaya admin diperlakukan sebagai pengeluaran tambahan.
- Edit dan hapus transfer memengaruhi kedua wallet secara bersamaan.
- Pembayaran kartu kredit mengurangi wallet aset dan kewajiban, bukan pengeluaran kedua.

### Acceptance Criteria

Transfer tanpa biaya tidak mengubah total aset maupun total pengeluaran pengguna.

---

## FR-05 — Category Management

**Prioritas: P0**

Aplikasi menyediakan kategori default dan kategori kustom.

### Kategori pengeluaran default

- Makanan & Minuman.
- Transportasi.
- Tempat Tinggal.
- Belanja.
- Kesehatan.
- Pendidikan.
- Hiburan.
- Internet & Komunikasi.
- Tagihan.
- Keluarga.
- Biaya Administrasi.
- Lainnya.

### Kategori pemasukan default

- Gaji.
- Freelance.
- Bonus.
- Usaha.
- Hadiah.
- Lainnya.

### Fitur

- Tambah dan edit kategori.
- Subkategori.
- Icon dan warna.
- Pengarsipan kategori.
- Kategori favorit.
- Saran kategori berdasarkan riwayat merchant dan transaksi.
- Penggabungan kategori dengan konfirmasi pengguna.

### Ketentuan

Kategori tabungan virtual dan transfer tidak boleh menambah total pengeluaran secara otomatis.

---

## FR-06 — Quick Add & Transaction Template

**Prioritas: P0**

Pengguna dapat mencatat transaksi berulang melalui satu atau dua interaksi.

### Contoh template

- Makan siang — Rp25.000.
- Kopi — Rp18.000.
- Bensin — Rp20.000.
- Parkir — Rp2.000.

### Fitur

- Membuat template secara manual.
- Mengubah transaksi sebelumnya menjadi template.
- Menyematkan template favorit.
- Menampilkan transaksi yang sering dilakukan.
- Mengulangi transaksi terakhir.
- Menampilkan quick amount.
- Undo setelah pencatatan cepat.

### Acceptance Criteria

- Template menyimpan nominal, kategori, wallet, dan deskripsi.
- Pengguna dapat memilih simpan langsung atau mengedit terlebih dahulu.
- Tanggal transaksi menggunakan waktu pencatatan saat ini.
- Double tap tidak boleh menghasilkan transaksi duplikat yang tidak disengaja.

---

## FR-07 — Dashboard

**Prioritas: P0**

Dashboard memberikan informasi kondisi finansial pengguna dalam satu tampilan.

### Komponen

1. Total aset likuid.
2. Total kekayaan bersih.
3. Saldo tersedia untuk belanja.
4. Safe-to-Spend.
5. Pemasukan periode berjalan.
6. Pengeluaran periode berjalan.
7. Daftar wallet.
8. Transaksi terbaru.
9. Quick Add.
10. Tagihan mendatang.
11. Progress budget.
12. Insight.

### Ketentuan

- Saldo dan laporan diperbarui setelah transaksi tersimpan.
- Pengguna dapat menyembunyikan nominal dengan tombol privasi.
- Dashboard mendukung dark mode.
- Pengguna dapat menyembunyikan komponen yang tidak diperlukan.

---

## FR-08 — Budget Management

**Prioritas: P0**

Pengguna dapat menentukan batas pengeluaran per periode.

### Jenis budget

- Harian.
- Mingguan.
- Bulanan.
- Per kategori.
- Per kelompok kategori.
- Periode custom.

### Contoh

| Kategori | Anggaran | Terpakai | Sisa |
|---|---:|---:|---:|
| Makanan | Rp1.000.000 | Rp650.000 | Rp350.000 |
| Transportasi | Rp400.000 | Rp300.000 | Rp100.000 |
| Hiburan | Rp200.000 | Rp200.000 | Rp0 |

### Fitur

- Buat dan edit budget.
- Progress penggunaan.
- Reminder pada 80% dan 100%.
- Rollover anggaran opsional.
- Duplikasi budget bulan sebelumnya.
- Prediksi pengeluaran hingga akhir periode.
- Rekomendasi anggaran berdasarkan histori.

### Aturan bisnis

Budget menghitung pengeluaran aktual dalam kategori dan periode yang ditentukan. Transfer dan pembayaran pokok utang tidak mengurangi budget pengeluaran.

Budget adalah batas atau rencana penggunaan dana, bukan saldo wallet baru.

---

## FR-09 — Safe-to-Spend

**Prioritas: P0**

Fitur utama untuk mengetahui estimasi jumlah uang yang dapat digunakan sampai periode keuangan berikutnya.

### Input perhitungan

- Saldo aset likuid yang tersedia untuk belanja.
- Tagihan belum dibayar sebelum periode berikutnya.
- Target tabungan yang belum dialokasikan.
- Cadangan dana yang belum dipisahkan.
- Estimasi kebutuhan rutin yang masih harus dipenuhi.
- Tanggal pemasukan berikutnya atau akhir periode anggaran.

### Rumus utama

Dana bebas = Saldo likuid yang dapat digunakan − Komitmen pembayaran − Alokasi tabungan tertunda − Cadangan tambahan − Estimasi kebutuhan pokok tersisa.

Anggaran bebas harian = Maksimum antara nol dan dana bebas, dibagi jumlah hari yang tersisa.

### Contoh

Saldo tersedia: Rp3.000.000.

- Tagihan mendatang: Rp1.000.000.
- Target tabungan belum dialokasikan: Rp500.000.
- Kebutuhan pokok tersisa: Rp750.000.
- Dana bebas: Rp750.000.
- Hari menuju gajian: 15 hari.

Safe-to-Spend bebas per hari = Rp50.000.

### Fitur

- Anggaran bebas per hari.
- Sisa dana bebas sampai gajian.
- Indikator kekurangan dana.
- Rincian perhitungan.
- Simulasi pembelian.
- Perhitungan otomatis setelah transaksi.
- Penyesuaian tanggal periode untuk freelancer.

### Aturan bisnis

- Dana yang sudah dipisahkan dalam wallet tabungan tidak dikurangi kembali.
- Alokasi budget dan tagihan yang merepresentasikan kewajiban sama tidak boleh dihitung dua kali.
- Piutang yang belum diterima tidak dianggap saldo yang tersedia.
- Gaji yang belum diterima tidak dianggap kas aktual.
- Jika dana bebas negatif, tampilkan kekurangan dana dan anggaran bebas nol.
- Jika tanggal gajian belum diatur, gunakan akhir periode yang dipilih pengguna.
- Jumlah hari minimum untuk pembagian adalah satu hari.
- Pengguna dapat melihat dan mengoreksi asumsi perhitungan.

### Acceptance Criteria

- Pengeluaran tambahan memperbarui estimasi dana bebas.
- Pemindahan uang ke wallet tabungan yang sudah dipisahkan tidak menyebabkan pengurangan dana dua kali.
- Sistem dapat membedakan dana kebutuhan pokok dan dana bebas.
- Aplikasi tidak menyatakan suatu pembelian pasti aman hanya berdasarkan saldo.

---

## FR-10 — Recurring Transaction & Bill Management

**Prioritas: P0**

Pengguna dapat mengelola pemasukan dan pengeluaran yang terjadi secara rutin.

### Contoh

- Gaji bulanan.
- Uang kos.
- Internet.
- Listrik.
- Cicilan.
- Subscription Netflix.
- Biaya langganan software.

### Informasi

- Nama tagihan.
- Nominal estimasi.
- Kategori.
- Wallet.
- Frekuensi.
- Tanggal jatuh tempo.
- Jadwal pengingat.
- Tanggal mulai dan selesai.
- Status.

### Status tagihan

- Upcoming.
- Unpaid.
- Paid.
- Overdue.
- Skipped.
- Cancelled.

### Fitur

- Reminder H-7, H-3, H-1, atau custom.
- Konfirmasi pembayaran.
- Perubahan nominal aktual.
- Pembayaran sebagian.
- Tunda atau lewati tagihan.
- Riwayat pembayaran.
- Daftar subscription aktif.
- Estimasi biaya subscription per bulan dan tahun.

### Aturan bisnis

Tagihan mendatang merupakan komitmen, bukan transaksi aktual. Saldo baru berubah ketika pengguna mengonfirmasi pembayaran atau mencatat transaksi yang benar-benar terjadi.

Setiap kejadian tagihan memiliki identitas unik agar transaksi tidak tercatat dua kali.

Tagihan bulanan tanggal 29–31 harus memiliki aturan penyesuaian ke hari terakhir bulan yang lebih pendek.

---

## FR-11 — Saving Goals

**Prioritas: P1**

Pengguna dapat membuat target tabungan.

### Informasi

- Nama target.
- Nominal target.
- Tanggal target.
- Nominal terkumpul.
- Wallet atau alokasi sumber.
- Icon.
- Prioritas.
- Status.

### Fitur

- Progress target.
- Estimasi tanggal tercapai.
- Kontribusi rutin.
- Perhitungan kebutuhan tabungan per bulan.
- Reminder.
- Penarikan dana target.
- Riwayat kontribusi.

### Aturan bisnis

Kontribusi target dapat berupa alokasi virtual atau transfer ke wallet tabungan.

Alokasi virtual tidak membuat saldo tambahan. Dana yang sudah dialokasikan tidak dapat digunakan oleh target lain secara bersamaan.

---

## FR-12 — Salary Day

**Prioritas: P1**

Fitur untuk membantu pengguna mengatur uang ketika menerima gaji.

### Alur

1. Pengguna mencatat gaji masuk.
2. Aplikasi mendeteksi transaksi kategori gaji.
3. Aplikasi menawarkan pembagian dana.
4. Pengguna memilih template alokasi.
5. Sistem menampilkan rekomendasi.
6. Pengguna mengonfirmasi.
7. Anggaran dan alokasi diperbarui.

### Contoh alokasi

Gaji Rp5.000.000:

| Kebutuhan | Alokasi |
|---|---:|
| Kos | Rp900.000 |
| Makanan | Rp1.500.000 |
| Transportasi | Rp400.000 |
| Tabungan | Rp1.000.000 |
| Tagihan | Rp300.000 |
| Hiburan | Rp400.000 |
| Cadangan | Rp500.000 |

### Fitur

- Template alokasi gaji.
- Metode 50/30/20.
- Pembagian nominal atau persentase.
- Alokasi custom.
- Saran berdasarkan pengeluaran historis.
- Perbandingan alokasi dan realisasi.

### Ketentuan

Alokasi tidak melakukan transfer uang sungguhan. Jika berupa amplop virtual, saldo wallet tetap sama.

Total alokasi tidak boleh melebihi dana yang tersedia.

---

## FR-13 — Debt & Receivable Management

**Prioritas: P1**

Pengguna dapat mencatat utang dan piutang pribadi.

### Informasi

- Nama pihak.
- Jenis: utang atau piutang.
- Nominal pokok.
- Tanggal transaksi.
- Tanggal jatuh tempo.
- Sisa pembayaran.
- Wallet terkait.
- Catatan.
- Status.

### Fitur

- Tambah utang dan piutang.
- Pembayaran sebagian.
- Pelunasan.
- Riwayat pembayaran.
- Reminder jatuh tempo.
- Biaya bunga atau denda.
- Catatan per kontak.

### Aturan bisnis

**Piutang:** ketika meminjamkan uang Rp200.000, kas berkurang Rp200.000 dan aset piutang bertambah Rp200.000. Tidak dihitung sebagai konsumsi pribadi.

**Utang:** ketika menerima pinjaman Rp500.000, kas bertambah Rp500.000 dan kewajiban bertambah Rp500.000. Tidak dihitung sebagai pendapatan.

Pelunasan pokok tidak dianggap sebagai pendapatan atau pengeluaran baru. Bunga dan biaya terkait dicatat sebagai pengeluaran atau pendapatan sesuai jenisnya.

---

## FR-14 — Split Bill

**Prioritas: P1**

Pengguna dapat membagi tagihan bersama orang lain.

### Fitur

- Pembagian sama rata.
- Pembagian berdasarkan item.
- Pembagian berdasarkan nominal.
- Pembagian persentase.
- Alokasi pajak dan service charge.
- Pencatatan pembayaran peserta.
- Share ringkasan melalui WhatsApp atau aplikasi lain.

### Contoh

Total tagihan Rp240.000, dibayar oleh pengguna untuk empat orang.

- Bagian pengguna: Rp60.000.
- Piutang teman: Rp180.000.
- Pengurangan saldo pengguna: Rp240.000.
- Pengeluaran pribadi: Rp60.000.

### Acceptance Criteria

- Jumlah seluruh bagian peserta sama dengan total tagihan.
- Selisih pembulatan Rupiah dialokasikan secara deterministik.
- Pembayaran teman menambah saldo dan mengurangi piutang.
- Pembayaran teman tidak dihitung sebagai pendapatan baru.
- Pembatalan Split Bill membatalkan seluruh catatan terkait secara konsisten.

---

## FR-15 — Wishlist & Purchase Simulator

**Prioritas: P1**

Pengguna dapat merencanakan pembelian sebelum mengeluarkan uang.

### Informasi

- Nama barang.
- Harga.
- Prioritas.
- Target pembelian.
- Link produk opsional.
- Foto opsional.
- Status.

### Fitur

- Simulasi dampak pembelian terhadap Safe-to-Spend.
- Estimasi dampak terhadap target tabungan.
- Perbandingan harga dengan dana bebas.
- Cooling-off period.
- Reminder setelah masa tunggu.
- Konversi wishlist menjadi transaksi pengeluaran.

### Contoh

Harga headphone Rp800.000.

Sistem menampilkan:

- Dana bebas saat ini.
- Dana bebas setelah membeli.
- Anggaran harian sebelum dan sesudah pembelian.
- Tagihan yang perlu diprioritaskan.
- Apakah pembelian menyebabkan kekurangan dana.

Sistem memberikan informasi, bukan melarang atau memaksakan keputusan kepada pengguna.

---

# 7. AI Features

## FR-16 — Gemini AI Configuration

**Prioritas: P0**

Pengguna dapat mengatur Gemini API melalui halaman pengaturan.

### Pengaturan yang tersedia

- Enable/disable AI.
- API Key.
- Model Gemini.
- Test Connection.
- Status koneksi.
- Pengaturan konteks data AI.
- Pengaturan histori chat.
- Pengaturan penggunaan gambar.
- Hapus API Key.

### Alur konfigurasi

1. Pengguna membuka Pengaturan.
2. Memilih Asisten AI.
3. Membuat API Key melalui Google AI Studio.
4. Menempelkan API Key.
5. Aplikasi menyimpan key ke secure storage.
6. Pengguna menjalankan Test Connection.
7. Aplikasi menampilkan model yang kompatibel.
8. Pengguna memilih model.
9. AI dapat digunakan.

### Ketentuan teknis

- Menggunakan konsep Bring Your Own Key (BYOK).
- API Key tidak ditanamkan dalam source code maupun APK.
- API Key disimpan menggunakan flutter_secure_storage.
- API Key tidak disimpan dalam SQLite, log, export, atau backup aplikasi.
- API Key ditampilkan dalam bentuk masked.
- Gunakan kredensial Gemini API yang masih didukung oleh Google.
- Model tidak ditentukan permanen di source code.
- Aplikasi dapat menampilkan daftar model yang didukung sesuai API.
- Prioritaskan model Flash yang mendukung kebutuhan text, image, dan structured output.
- Pengguna dapat mengganti API Key dan model tanpa menginstal ulang aplikasi.

### Error handling

- Invalid API Key.
- API Key tidak memiliki izin.
- Model tidak tersedia.
- Rate limit.
- Kuota habis.
- Billing belum aktif jika diperlukan.
- Tidak ada koneksi internet.
- Request timeout.
- Respons tidak valid.

### Acceptance Criteria

- Aplikasi tetap berfungsi tanpa API Key.
- API Key tidak dapat dibaca dari export database.
- Pergantian model tidak memengaruhi data transaksi.
- Jika AI gagal, pengguna dapat melanjutkan secara manual.

---

## FR-17 — AI Quick Expense

**Prioritas: P0**

Pengguna dapat mencatat transaksi menggunakan bahasa sehari-hari.

### Contoh input

"Tadi makan ayam geprek 25 ribu, bensin 20 ribu, dan kopi 18 ribu. Semuanya pakai BCA."

### Alur

1. Pengguna mengetik kalimat.
2. Aplikasi mengirim teks dan konteks minimum kepada Gemini.
3. Gemini menghasilkan structured output.
4. Aplikasi memvalidasi hasil.
5. Aplikasi menampilkan draft transaksi.
6. Pengguna dapat mengubah hasil.
7. Pengguna mengonfirmasi penyimpanan.
8. Database menyimpan transaksi secara lokal.
9. Dashboard dan saldo diperbarui.

### Output yang diharapkan

| Deskripsi | Jenis | Nominal | Wallet |
|---|---|---:|---|
| Ayam geprek | Pengeluaran | Rp25.000 | BCA |
| Bensin | Pengeluaran | Rp20.000 | BCA |
| Kopi | Pengeluaran | Rp18.000 | BCA |

### Kemampuan AI

- Memahami bahasa Indonesia.
- Memahami nominal seperti 25k, 25rb, 25 ribu, dan 1,5 juta.
- Memahami tanggal relatif seperti tadi, kemarin, dan minggu lalu.
- Menangani beberapa transaksi dalam satu pesan.
- Mengidentifikasi kategori.
- Mengidentifikasi wallet.
- Membedakan transfer, pengeluaran, pemasukan, utang, dan piutang.
- Mendeteksi informasi yang belum lengkap.
- Memberikan pertanyaan klarifikasi jika diperlukan.

### Contoh kontrak structured output

```json
{
  "intent": "create_transactions",
  "transactions": [
    {
      "type": "expense",
      "amount": 25000,
      "currency": "IDR",
      "description": "Ayam geprek",
      "category_id": "food",
      "wallet_id": "wallet_bca",
      "occurred_at": "2026-11-16T12:30:00+07:00"
    }
  ],
  "requires_confirmation": true,
  "missing_fields": [],
  "clarification_question": null
}
```

Contoh tersebut bersifat ilustratif. ID wallet dan kategori harus menggunakan data yang benar-benar tersedia dalam database lokal.

### Aturan bisnis

- AI tidak boleh langsung menulis data ke database.
- Semua hasil AI menjadi draft transaksi.
- ID wallet dan kategori harus divalidasi.
- Jika wallet tidak diketahui, gunakan default dengan indikator asumsi atau tanyakan kepada pengguna.
- Waktu yang tidak disebutkan dapat menggunakan waktu pencatatan, dengan informasi yang jelas.
- Nominal tidak boleh ditebak jika tidak tersedia.
- Respons AI yang tidak sesuai schema harus ditolak.
- Penyimpanan beberapa transaksi dilakukan secara atomik atau melalui pilihan draft yang valid.
- Setiap request memiliki idempotency key untuk mencegah duplikasi ketika pengguna melakukan retry.

### Acceptance Criteria

- Input tiga pengeluaran menghasilkan tiga draft transaksi.
- Input top-up menghasilkan transfer, bukan pengeluaran biasa.
- Nominal yang tidak jelas menghasilkan permintaan klarifikasi.
- Jika pengguna membatalkan draft, saldo tidak berubah.
- Pencatatan ulang akibat retry tidak menghasilkan transaksi ganda.

---

## FR-18 — AI Receipt Scanner

**Prioritas: P1**

Pengguna dapat mencatat transaksi dari foto struk atau screenshot pembayaran.

### Jenis dokumen

- Struk minimarket.
- Nota restoran.
- Invoice.
- Screenshot mobile banking.
- Bukti transfer.
- Bukti pembayaran e-wallet.

### Informasi yang diekstrak

- Merchant.
- Tanggal.
- Nominal total.
- Daftar barang.
- Pajak.
- Biaya layanan.
- Diskon.
- Metode pembayaran jika tersedia.
- Saran kategori.

### Alur

Ambil foto atau pilih gambar → Preview → Persetujuan pengiriman ke Gemini → Ekstraksi → Validasi → Draft → Konfirmasi → Simpan lokal.

### Fitur tambahan

- Crop gambar.
- Kompresi sebelum pengiriman.
- Pemisahan kategori per item.
- Deteksi struk duplikat.
- Pilihan menyimpan gambar asli secara lokal.
- Penghapusan gambar setelah pemrosesan.

### Aturan bisnis

- Total item harus direkonsiliasi dengan diskon, pajak, dan total pembayaran.
- Screenshot transfer tidak otomatis dianggap pengeluaran.
- Nomor rekening dan informasi yang tidak diperlukan dapat disamarkan sebelum dikirim.
- Instruksi atau teks dalam gambar diperlakukan sebagai data, bukan instruksi untuk AI.
- Pengguna harus mengonfirmasi hasil ekstraksi.

---

## FR-19 — Voice Input

**Prioritas: P1**

Pengguna dapat mencatat transaksi melalui suara.

### Contoh

"Makan nasi goreng dua puluh ribu pakai GoPay."

### Alur

Tekan mikrofon → Speech-to-text → Preview transkrip → AI parsing → Draft → Konfirmasi.

### Ketentuan

- Pengenalan suara lokal diprioritaskan jika tersedia.
- Jika pengenalan suara menggunakan layanan eksternal, aplikasi harus menjelaskan kebutuhan internet dan meminta persetujuan.
- Rekaman audio tidak disimpan secara default.
- Pengguna dapat mengedit transkrip.
- Jika pengenalan suara gagal, sediakan input teks.

---

## FR-20 — AI Financial Assistant

**Prioritas: P1**

Asisten AI membantu pengguna memahami keuangannya.

### Contoh pertanyaan

- Kenapa uangku cepat habis bulan ini?
- Berapa total pengeluaran makan bulan ini?
- Apakah pengeluaran bulan ini lebih besar daripada bulan lalu?
- Kira-kira bisa nggak aku nabung Rp1 juta bulan depan?
- Apa pengeluaran yang bisa aku kurangi?
- Kalau beli sepatu Rp500 ribu, bagaimana dampaknya?

### Mekanisme

AI tidak menghitung saldo secara mandiri.

Aplikasi menyediakan fungsi lokal seperti:

- get_financial_summary.
- get_expense_by_category.
- compare_periods.
- get_wallet_balances.
- get_upcoming_bills.
- get_saving_goals.
- calculate_safe_to_spend.
- simulate_purchase.

Fungsi tersebut membaca dan menghitung data dari SQLite. Hasil perhitungan kemudian dikirim ke Gemini untuk dijelaskan dalam bahasa yang mudah dipahami.

### Fitur

- Chat dengan konteks keuangan.
- Suggested questions.
- Analisis kategori.
- Analisis tren.
- Rekomendasi penghematan.
- Simulasi keputusan.
- Riwayat chat lokal.
- Hapus histori chat.

### Batasan

- AI tidak memiliki akses langsung ke database.
- Query database bebas yang dibuat AI tidak boleh langsung dieksekusi.
- Akses data menggunakan daftar fungsi yang telah ditentukan.
- AI tidak boleh menghapus atau mengubah data keuangan tanpa konfirmasi.
- AI tidak memberikan jaminan hasil investasi atau keputusan finansial.
- Angka yang ditampilkan harus berasal dari hasil perhitungan lokal.

---

# 8. Financial Reports & Insights

## FR-21 — Reporting

**Prioritas: P0**

Aplikasi menyediakan laporan keuangan yang dapat digunakan tanpa internet.

### Jenis laporan

- Ringkasan harian, mingguan, bulanan, tahunan.
- Pemasukan vs pengeluaran.
- Cash flow.
- Pengeluaran per kategori.
- Pengeluaran per merchant.
- Saldo per wallet.
- Budget vs actual.
- Tabungan.
- Utang dan piutang.
- Kekayaan bersih.
- Tren pengeluaran.
- Kalender transaksi.

### Fitur

- Filter periode custom.
- Perbandingan periode.
- Drill-down dari grafik ke transaksi.
- Export CSV.
- Export PDF.
- Tampilan grafik interaktif.

### Aturan bisnis

Laporan arus kas dan laporan konsumsi pribadi harus dibedakan.

Contoh: pembayaran piutang kepada teman menyebabkan arus kas keluar, tetapi bukan konsumsi pribadi.

Kekayaan bersih dihitung dari total aset, termasuk piutang, dikurangi kewajiban yang masih outstanding.

---

## FR-22 — Financial Recap

**Prioritas: P1**

Pengguna dapat melihat ringkasan menarik seperti Spotify Wrapped.

### Informasi

- Total pemasukan.
- Total pengeluaran.
- Kategori terbesar.
- Transaksi terbesar.
- Hari dengan pengeluaran tertinggi.
- Merchant paling sering dikunjungi.
- Saving rate.
- Target yang tercapai.
- Perbandingan periode.
- Potensi penghematan.

### Contoh insight

"Kamu membeli kopi 18 kali bulan ini dengan total Rp360.000. Jika mengurangi dua pembelian kopi per minggu, estimasi penghematanmu adalah Rp160.000 dalam empat minggu."

### Ketentuan

- Insight dasar dihitung secara lokal.
- AI hanya digunakan untuk narasi tambahan jika pengguna mengaktifkannya.
- Perbandingan periode harus memperhitungkan jumlah hari yang sebanding.
- Saving rate hanya dihitung jika terdapat pemasukan yang valid.
- Recap dapat dibagikan sebagai gambar tanpa menampilkan saldo sensitif secara default.

---

# 9. Notification System

## FR-23 — Local Notification

**Prioritas: P0**

Local Notification menjadi mekanisme utama untuk pengingat aktivitas keuangan pribadi.

### Jenis notifikasi

| Notifikasi | Trigger |
|---|---|
| Daily Reminder | Jadwal pencatatan harian |
| Bill Reminder | Sebelum jatuh tempo |
| Budget Warning | Anggaran mencapai batas |
| Salary Reminder | Tanggal gajian |
| Saving Reminder | Jadwal kontribusi |
| Debt Reminder | Jatuh tempo utang/piutang |
| Weekly Recap | Jadwal mingguan |
| Monthly Recap | Jadwal bulanan |
| Wishlist Reminder | Cooling-off period selesai |

### Fitur

- Mengaktifkan atau menonaktifkan jenis notifikasi.
- Custom waktu pengingat.
- Quiet hours.
- Snooze.
- Deep link ke halaman terkait.
- Penyembunyian nominal pada lock screen.

### Ketentuan teknis

- Menggunakan flutter_local_notifications.
- Menggunakan timezone untuk penjadwalan sesuai waktu perangkat.
- Jadwal disimpan dalam database lokal.
- Notifikasi dibatalkan saat tagihan dibayar atau dihapus.
- Penjadwalan ulang setelah perubahan jadwal, restore, atau restart perangkat sesuai dukungan OS.
- Jadwal berulang menggunakan mekanisme yang sesuai dengan batas platform.
- Notifikasi budget dihitung setelah perubahan transaksi.
- Notifikasi tidak bergantung pada Firebase maupun internet.

Waktu pengiriman aktual dapat dipengaruhi oleh izin pengguna, penghematan baterai, dan pembatasan sistem operasi.

---

## FR-24 — Firebase Cloud Messaging

**Prioritas: P0 — Integration Foundation**

FCM digunakan untuk menerima push notification eksternal tanpa mengharuskan data keuangan pengguna disimpan dalam Firebase.

### Penggunaan FCM

- Informasi update aplikasi.
- Pengumuman fitur baru.
- Informasi maintenance.
- Tips penggunaan aplikasi.
- Pengumuman umum.
- Push notification testing.

### Alur

Firebase Console atau trusted sender → Firebase Cloud Messaging → Perangkat → Flutter Notification Handler.

### Ketentuan teknis

- Menggunakan firebase_core dan firebase_messaging.
- Firebase Firestore tidak digunakan.
- Firebase Authentication tidak digunakan.
- Push umum dapat menggunakan topic subscription.
- Pengguna dapat menonaktifkan push notification eksternal.
- FCM registration token tidak digunakan untuk menyimpan profil keuangan.
- Tidak mengirim nominal, saldo, detail transaksi, maupun API Key melalui payload.
- Menangani foreground, background, dan cold start.
- Penggunaan FCM dapat dinonaktifkan tanpa mengganggu fitur utama.
- Kredensial Firebase Admin SDK tidak boleh disimpan dalam aplikasi Flutter.

### Keputusan implementasi

Karena aplikasi tidak memiliki backend, pengiriman broadcast awal dapat dilakukan melalui Firebase Console.

Jika nanti diperlukan push notification yang dipicu otomatis oleh layanan eksternal, diperlukan trusted server environment seperti Cloud Functions. Fitur tersebut berada di luar lingkup backend-less versi awal.

Reminder finansial yang berasal dari database lokal tidak perlu menggunakan FCM.

---

# 10. Import, Export & Data Ownership

## FR-25 — Import Transaction

**Prioritas: P1**

Pengguna dapat mengimpor transaksi dari file CSV atau Excel.

### Alur

1. Pilih file.
2. Preview data.
3. Mapping kolom.
4. Tentukan wallet.
5. Validasi nominal dan tanggal.
6. Deteksi duplikat.
7. Preview hasil import.
8. Konfirmasi.
9. Simpan lokal.

### Ketentuan

- Import tidak langsung mengubah database tanpa preview.
- Baris tidak valid ditampilkan beserta alasannya.
- Pengguna dapat melewati transaksi duplikat.
- Import memiliki batch ID untuk audit dan pembatalan.
- Pembatalan import harus mempertimbangkan transaksi lain yang terkait.

---

## FR-26 — Balance Reconciliation

**Prioritas: P1**

Pengguna dapat mencocokkan saldo aplikasi dengan saldo nyata.

### Contoh

Saldo BCA di aplikasi Rp2.450.000.

Saldo aktual Rp2.400.000.

Selisih Rp50.000.

Aplikasi menyediakan pilihan:

- Cari transaksi yang belum dicatat.
- Catat transaksi yang hilang.
- Buat penyesuaian saldo dengan alasan tertentu.

Penyesuaian saldo memiliki jejak audit dan tidak otomatis dianggap pengeluaran konsumsi.

---

## FR-27 — Backup & Restore

**Prioritas: P0**

Karena seluruh data tersimpan lokal, backup menjadi fitur penting sejak versi pertama.

### Fitur backup

- Backup database.
- Backup attachment.
- Backup kategori dan pengaturan.
- Export file backup terenkripsi.
- Pemilihan lokasi penyimpanan oleh pengguna.
- Backup reminder.
- Riwayat backup.

### Fitur restore

- Pilih file backup.
- Validasi versi schema.
- Validasi integritas file.
- Masukkan password backup.
- Preview informasi backup.
- Konfirmasi restore.
- Buat snapshot sebelum restore.
- Restore database dan attachment.
- Penjadwalan ulang local notification.

### Aturan bisnis

- Backup tidak menyertakan Gemini API Key, PIN mentah, maupun FCM token.
- Backup terenkripsi menjadi format default.
- Restore versi awal menggunakan metode replace seluruh data, bukan merge.
- Restore yang gagal tidak boleh merusak database aktif.
- File backup dapat dipindahkan secara manual ke perangkat lain.
- Pengguna harus diberi tahu bahwa uninstall atau kehilangan perangkat dapat menghilangkan data apabila tidak memiliki backup.

### Format

File backup khusus aplikasi, misalnya `.arusbackup`, berisi database snapshot, manifest versi, checksum, pengaturan yang aman untuk diekspor, dan attachment yang dipilih.

---

# 11. Business Rules & Financial Data Integrity

## BR-01 — Monetary Representation

Nominal IDR disimpan sebagai integer Rupiah. Jangan menggunakan floating point untuk menyimpan atau menjumlahkan uang.

Versi pertama menggunakan satu mata uang dasar, yaitu IDR. Multi-currency dan konversi kurs menjadi pengembangan berikutnya.

## BR-02 — Single Source of Truth

Saldo wallet berasal dari transaksi dan ledger entries yang tersimpan di SQLite.

Apabila cached balance digunakan untuk performa, nilainya harus dapat dihitung kembali dari ledger.

## BR-03 — Atomic Transaction

Perubahan transaksi, ledger entries, split kategori, dan catatan terkait harus dilakukan dalam satu database transaction.

Jika salah satu proses gagal, seluruh perubahan dibatalkan.

## BR-04 — Transfer Integrity

Satu transfer memiliki wallet asal dan tujuan yang terhubung melalui satu transaction ID.

Transfer internal tidak boleh dihitung sebagai pendapatan atau pengeluaran.

## BR-05 — No Double Counting

Sistem harus mencegah penghitungan ganda pada:

- Transfer antarwallet.
- Pembayaran kartu kredit.
- Pelunasan utang.
- Pengembalian piutang.
- Refund.
- Split Bill.
- Alokasi tabungan.
- Tagihan yang sudah dibayar.
- Import transaksi duplikat.

## BR-06 — Transaction History

Setiap perubahan dan penghapusan transaksi penting memiliki jejak audit.

Penghapusan dapat dilakukan melalui void atau mekanisme koreksi yang tidak meninggalkan pengaruh transaksi terhadap saldo aktif.

## BR-07 — Time & Period

Tanggal transaksi disimpan secara konsisten dengan informasi zona waktu yang diperlukan.

Periode laporan dan tanggal relatif mengikuti zona waktu lokal pengguna. Default Indonesia menggunakan Asia/Jakarta.

## BR-08 — Recurring Occurrence

Setiap kejadian tagihan rutin memiliki identitas unik.

Pembuatan jadwal tidak sama dengan pembayaran aktual.

## BR-09 — AI Confirmation

Seluruh perubahan data yang disarankan AI harus melalui validasi aplikasi dan persetujuan pengguna.

## BR-10 — Privacy Boundaries

Data keuangan tidak dikirim ke Firebase.

Data hanya dikirim ke Gemini untuk permintaan yang diinisiasi dan disetujui pengguna, sesuai kebutuhan fitur.

---

# 12. Technical Architecture

## 12.1 Technology Stack

| Layer | Technology |
|---|---|
| Mobile Framework | Flutter |
| Language | Dart |
| State Management | Riverpod |
| Local Database | SQLite |
| Database ORM | Drift |
| Navigation | go_router |
| AI Integration | Gemini REST API |
| HTTP Client | Dio |
| Secret Storage | flutter_secure_storage |
| Local Authentication | local_auth |
| Push Notification | Firebase Cloud Messaging |
| Local Notification | flutter_local_notifications |
| Chart | fl_chart |
| Image Capture | image_picker |
| Speech Input | speech_to_text |
| File Selection | file_picker |
| Local File Storage | path_provider |
| Sharing | share_plus |
| Serialization | json_serializable |
| Localization | intl |
| Testing | flutter_test, integration_test |

Versi dependency mengikuti versi Flutter yang kompatibel saat implementasi. Seluruh dependency dikunci melalui lockfile.

## 12.2 Architecture Pattern

Menggunakan feature-first architecture dengan pemisahan presentation, application, domain, dan data.

```text
lib/
├── app/
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── core/
│   ├── database/
│   ├── money/
│   ├── errors/
│   ├── security/
│   ├── notifications/
│   ├── network/
│   └── utils/
│
├── features/
│   ├── onboarding/
│   ├── dashboard/
│   ├── wallets/
│   ├── transactions/
│   ├── categories/
│   ├── budgets/
│   ├── bills/
│   ├── goals/
│   ├── safe_to_spend/
│   ├── debts/
│   ├── split_bill/
│   ├── salary_day/
│   ├── wishlist/
│   ├── reports/
│   ├── ai_assistant/
│   ├── receipt_scanner/
│   ├── import_export/
│   ├── backup/
│   └── settings/
│
└── main.dart
```

Struktur internal feature:

```text
transactions/
├── presentation/
│   ├── pages/
│   ├── widgets/
│   └── providers/
├── application/
│   └── use_cases/
├── domain/
│   ├── entities/
│   └── repositories/
└── data/
    ├── datasources/
    ├── models/
    └── repositories/
```

## 12.3 Architecture Flow

```text
Flutter UI
    |
Riverpod Controller / Provider
    |
Application Use Case
    |
Domain Repository Interface
    |
Repository Implementation
    |
Drift / SQLite
```

Integrasi eksternal:

```text
AI Feature
    |
Gemini Service
    |
HTTPS Request
    |
Google Gemini API
```

```text
Local Database
    |
Notification Scheduler
    |
Device Notification
```

```text
Firebase Console
    |
FCM
    |
Flutter Notification Handler
```

## 12.4 Architecture Principles

- UI tidak mengakses database secara langsung.
- Business logic tidak ditempatkan dalam widget.
- Financial calculation berada pada domain service.
- Repository menjadi abstraksi akses data.
- SQLite menjadi sumber data utama.
- Integrasi Gemini dan notifikasi menggunakan service interface.
- Perhitungan finansial tidak bergantung pada respons API.

---

# 13. Local Database Design

## 13.1 Core Tables

| Tabel | Tanggung jawab |
|---|---|
| app_settings | Profil dan preferensi lokal |
| accounts | Wallet, akun aset, dan kewajiban |
| categories | Kategori transaksi |
| transactions | Header transaksi |
| ledger_entries | Perubahan saldo akun |
| transaction_splits | Pembagian kategori transaksi |
| transaction_tags | Relasi tag transaksi |
| tags | Master tag |
| attachments | Referensi file lokal |
| transaction_templates | Template pencatatan |
| budgets | Definisi anggaran |
| bills | Master tagihan |
| bill_occurrences | Kejadian tagihan per periode |
| bill_payments | Relasi pembayaran tagihan |
| goals | Target tabungan |
| fund_allocations | Alokasi dana virtual |
| goal_contributions | Riwayat kontribusi |
| debts | Detail utang/piutang |
| debt_payments | Riwayat pembayaran pokok dan biaya |
| split_bills | Header pembagian tagihan |
| split_bill_members | Bagian peserta |
| wishlists | Rencana pembelian |
| salary_plans | Template alokasi pemasukan |
| salary_plan_items | Detail pembagian gaji |
| notifications | Jadwal dan status notifikasi |
| ai_conversations | Histori percakapan |
| ai_messages | Pesan percakapan |
| import_batches | Riwayat import |
| audit_logs | Jejak perubahan data |

Gemini API Key tidak termasuk dalam tabel database.

## 13.2 Transaction & Ledger

**transactions**

- id
- type
- amount
- currency
- description
- merchant
- occurred_at
- source
- status
- created_at
- updated_at

**ledger_entries**

- id
- transaction_id
- account_id
- side: debit atau credit
- amount
- created_at

**accounts**

- id
- name
- account_type
- account_class: asset, liability, income, expense, atau equity
- currency
- icon
- color
- is_visible
- include_in_spendable
- is_archived

**transaction_splits**

- id
- transaction_id
- category_id
- amount
- description

## 13.3 Accounting Model

Aplikasi menggunakan ledger berpasangan di belakang layar untuk menjaga konsistensi, tanpa menampilkan kerumitan akuntansi kepada pengguna.

Contoh pengeluaran makanan Rp25.000:

- Debit Expense Makanan Rp25.000.
- Credit Aset BCA Rp25.000.

Contoh pemasukan gaji Rp5.000.000:

- Debit Aset BCA Rp5.000.000.
- Credit Income Gaji Rp5.000.000.

Contoh transfer Rp100.000 dari BCA ke GoPay:

- Debit Aset GoPay Rp100.000.
- Credit Aset BCA Rp100.000.

Contoh saldo awal Rp1.000.000:

- Debit Aset Wallet Rp1.000.000.
- Credit Equity Saldo Awal Rp1.000.000.

Total debit dan credit dalam setiap transaksi yang disimpan harus seimbang.

Akun income, expense, dan equity merupakan akun internal sistem, bukan wallet yang harus ditampilkan kepada pengguna.

Kategori transaksi dan akun ledger internal harus memiliki pemetaan yang konsisten agar laporan kategori tidak bertentangan dengan ledger.

## 13.4 Main Relationships

```text
Account 1 --- N LedgerEntry

Transaction 1 --- N LedgerEntry

Transaction 1 --- N TransactionSplit

Category 1 --- N TransactionSplit

Category 1 --- N Category (subkategori)

Transaction 1 --- N Attachment

Bill 1 --- N BillOccurrence

BillOccurrence 1 --- N BillPayment

BillPayment N --- 1 Transaction

Goal 1 --- N GoalContribution

Debt 1 --- N DebtPayment

DebtPayment N --- 1 Transaction

SplitBill 1 --- N SplitBillMember
```

## 13.5 Database Requirements

- Menggunakan UUID untuk identifier.
- Mengaktifkan foreign key constraints.
- Menyediakan index pada tanggal transaksi, kategori, status, dan account ID.
- Mendukung database migration.
- Menyediakan database transaction.
- Memastikan perubahan schema tidak menghapus data lama.
- Menyimpan attachment dalam direktori aplikasi, bukan sebagai blob besar di database.
- Menggunakan relative path untuk attachment agar backup dapat dipindahkan.

---

# 14. UI/UX Requirements

## 14.1 Design Direction

Desain aplikasi harus:

- Modern.
- Minimalis.
- Mobile-first.
- Tidak terasa seperti aplikasi akuntansi.
- Menggunakan informasi visual yang mudah dipahami.
- Mengutamakan kecepatan penggunaan.

## 14.2 Visual Style

- Material 3.
- Light mode dan dark mode.
- Typography yang jelas.
- Rounded cards secukupnya.
- Warna hijau untuk pemasukan.
- Warna merah atau oranye untuk pengeluaran dan peringatan.
- Warna netral untuk transfer.
- Icon yang konsisten.

Warna tidak boleh menjadi satu-satunya indikator status.

## 14.3 Transaction Experience

Form transaksi memiliki input nominal besar sebagai fokus utama.

Field utama:

1. Nominal.
2. Jenis.
3. Wallet.
4. Kategori.

Field tambahan disembunyikan dalam bagian More Details.

Tanggal menggunakan hari ini sebagai default. Pengguna dapat mengganti tanggal jika diperlukan.

## 14.4 Empty State

Aplikasi menyediakan empty state yang informatif, seperti:

- "Belum ada transaksi. Yuk catat pengeluaran pertama."
- "Belum ada wallet. Tambahkan rekening atau uang tunai."
- "AI belum diaktifkan. Kamu bisa mengaturnya kapan saja."

## 14.5 Privacy Mode

Pengguna dapat menyembunyikan seluruh nominal pada dashboard dengan satu tombol.

## 14.6 Accessibility

- Dukungan text scaling.
- Kontras warna yang memadai.
- Label untuk screen reader.
- Touch target yang nyaman.
- Tampilan nominal tidak terpotong pada layar kecil.
- Informasi tetap dapat dipahami tanpa mengandalkan warna.

---

# 15. Security & Privacy

## 15.1 Data Security

- Database dan attachment berada dalam direktori aplikasi.
- Mendukung enkripsi database lokal melalui solusi SQLite encryption yang kompatibel dengan Drift.
- Kunci enkripsi disimpan dalam secure storage.
- Backup dienkripsi menggunakan password pengguna.
- Informasi keuangan tidak ditulis ke log produksi.
- API Key tidak disimpan dalam plaintext database.
- Tidak menggunakan analytics yang mengirim informasi finansial.

## 15.2 App Lock

Aplikasi menyediakan:

- PIN.
- Biometric authentication.
- Auto lock.
- Custom lock timeout.
- Recovery flow lokal.

PIN tidak boleh disimpan secara plaintext. Mekanisme app lock tidak menggantikan kebutuhan enkripsi database.

## 15.3 Gemini API Key Security

Model BYOK dipilih karena aplikasi tidak memiliki backend.

Pengguna memasukkan API Key sendiri dan key disimpan menggunakan Android Keystore atau iOS Keychain melalui secure storage.

Namun, penggunaan API Key langsung dari aplikasi mobile tetap memiliki risiko pada perangkat yang dimodifikasi atau dikompromikan. Secure storage mengurangi risiko penyimpanan, tetapi tidak menjamin key tidak dapat diekstraksi ketika sedang digunakan.

Aplikasi harus menjelaskan risiko penggunaan key pribadi dan kemungkinan biaya API.

Aplikasi tidak boleh menggunakan satu API Key bersama untuk seluruh pengguna.

## 15.4 AI Data Privacy

- AI disabled secara default sampai pengguna mengaktifkannya.
- Pengguna dapat melihat jenis data yang dikirim.
- Gunakan konteks minimum untuk setiap permintaan.
- Jangan mengirim seluruh database.
- Jangan mengirim API Key dalam prompt.
- Jangan mengirim detail rekening yang tidak diperlukan.
- Foto struk hanya dikirim setelah persetujuan.
- Histori chat disimpan lokal jika diaktifkan.
- Pengguna dapat menghapus histori chat.
- Kebijakan pemrosesan dan retensi data mengikuti ketentuan layanan Gemini yang digunakan.

## 15.5 Firebase Privacy

Firebase hanya digunakan untuk kebutuhan push notification.

Tidak menyimpan transaksi, saldo, utang, maupun profil finansial dalam Firebase.

Pengguna dapat menonaktifkan FCM dan tetap menggunakan notifikasi lokal.

---

# 16. Non-Functional Requirements

| ID | Requirement | Target |
|---|---|---|
| NFR-01 | Cold start aplikasi | Maksimal 3 detik pada perangkat pengujian |
| NFR-02 | Simpan transaksi lokal | Maksimal 300 ms untuk transaksi biasa |
| NFR-03 | Quick Add | Maksimal 5 detik untuk alur sederhana |
| NFR-04 | Dashboard load | Maksimal 1 detik pada data representatif |
| NFR-05 | Offline operation | Seluruh fitur inti berfungsi |
| NFR-06 | Data capacity | Minimal diuji dengan 100.000 transaksi |
| NFR-07 | Data integrity | Ledger selalu seimbang |
| NFR-08 | Crash handling | Transaksi tidak tersimpan sebagian |
| NFR-09 | AI failure | Tidak mengganggu fungsi utama |
| NFR-10 | Backup integrity | Restore berhasil tanpa kehilangan data valid |
| NFR-11 | Privacy | Tidak ada upload database otomatis |
| NFR-12 | Maintainability | Feature-first dan modular |
| NFR-13 | Localization | Bahasa Indonesia sebagai default |
| NFR-14 | Accessibility | Mendukung screen reader dan text scaling |
| NFR-15 | Notification | Pengiriman sesuai dukungan izin dan OS |
| NFR-16 | API Security | Tidak ada key bersama dalam source code |

Target performa diukur pada perangkat Android kelas menengah yang ditetapkan sebelum pengujian. Angka tersebut merupakan target pengembangan, bukan performa yang sudah terbukti.

---

# 17. Edge Cases & Acceptance Testing

| Skenario | Expected Result |
|---|---|
| Catat transaksi tanpa internet | Berhasil |
| Aplikasi ditutup ketika menyimpan transaksi | Seluruh transaksi tersimpan atau tidak sama sekali |
| Transfer antarwallet | Total aset tetap, kecuali biaya admin |
| Saldo awal wallet | Tidak menambah pendapatan |
| Hapus pengeluaran | Saldo dan budget diperbarui |
| Edit tanggal transaksi ke bulan sebelumnya | Laporan kedua bulan diperbarui |
| Top-up e-wallet | Dicatat sebagai transfer |
| Pembayaran kartu kredit | Mengurangi kewajiban, bukan pengeluaran kedua |
| Tagihan jatuh tempo belum dibayar | Saldo tidak berubah |
| Pinjaman masuk | Kas dan utang bertambah |
| Teman membayar piutang | Kas bertambah, piutang berkurang |
| AI menghasilkan kategori tidak valid | Draft meminta koreksi |
| AI timeout | Tidak terjadi penyimpanan ganda |
| API Key salah | Tampilkan error, input manual tetap berfungsi |
| Scan struk yang sama | Tampilkan peringatan duplikat |
| Safe-to-Spend negatif | Tampilkan kekurangan dana |
| Wallet tabungan sudah dipisahkan | Tidak dikurangi dua kali |
| Pembatalan tagihan | Reminder terkait dibatalkan |
| Notifikasi ditolak | Aplikasi tetap berfungsi |
| Restore backup rusak | Database aktif tidak berubah |
| Restore backup dari schema lama | Migrasi jika didukung |
| Aplikasi dihapus tanpa backup | Pengguna telah diberi informasi risiko kehilangan data |
| Pergantian bulan | Budget dan tagihan periode baru dibuat tanpa duplikasi |

---

# 18. Development Roadmap

## Phase 1 — Core Financial Engine

**Target:** aplikasi sudah dapat digunakan sebagai pencatatan keuangan pribadi.

- Inisialisasi Flutter.
- Theme dan navigation.
- Drift database dan migration.
- Ledger engine.
- Wallet management.
- Category management.
- Transaction CRUD.
- Transfer.
- Quick Add.
- Dashboard dasar.
- Unit test financial calculation.

## Phase 2 — MVP Smart Finance

**Target:** aplikasi memiliki fitur pembeda dan siap digunakan sehari-hari.

- Budgeting.
- Recurring bill.
- Safe-to-Spend.
- Local Notification.
- FCM integration.
- Gemini API settings.
- AI Quick Expense.
- Backup dan restore.
- App lock.
- Laporan dasar.
- Security testing.

## Phase 3 — Financial Planning

**Target:** aplikasi membantu pengguna merencanakan keuangan.

- Saving Goals.
- Salary Day.
- Debt & Receivable.
- Split Bill.
- Wishlist.
- Purchase Simulator.
- Calendar transaction.
- Subscription tracker.

## Phase 4 — AI & Automation Enhancement

**Target:** mengurangi beban pencatatan dan memberikan insight yang lebih personal.

- AI Receipt Scanner.
- Voice Input.
- AI Financial Assistant.
- Financial Recap.
- Smart Category.
- Import CSV dan Excel.
- Balance Reconciliation.
- Export PDF.
- Advanced reporting.

## Phase 5 — Product Refinement

- Android home screen widget.
- Shortcut pencatatan cepat.
- Peningkatan aksesibilitas.
- Optimalisasi database.
- Pengujian perangkat iOS.
- Multi-currency.
- Peningkatan mekanisme backup.

---

# 19. MVP Release Criteria

Versi MVP dinyatakan siap digunakan apabila:

1. Pengguna dapat menggunakan aplikasi tanpa login dan tanpa internet.
2. Pengguna dapat membuat dan mengelola beberapa wallet.
3. Pemasukan, pengeluaran, transfer, refund, dan penyesuaian saldo berjalan konsisten.
4. Seluruh ledger transaction seimbang.
5. Dashboard menampilkan saldo dan laporan yang akurat.
6. Budget dan Safe-to-Spend dihitung secara lokal.
7. Tagihan dapat dijadwalkan dan dikonfirmasi pembayarannya.
8. Local Notification dapat dijadwalkan pada perangkat yang mendukungnya.
9. FCM dapat menerima pesan pengujian.
10. Pengguna dapat memasukkan, menguji, mengganti, dan menghapus Gemini API Key.
11. AI Quick Expense dapat menghasilkan draft beberapa transaksi dalam satu pesan.
12. AI tidak dapat mengubah database tanpa konfirmasi pengguna.
13. Backup dan restore sudah diuji.
14. App lock berfungsi.
15. Tidak ada API Key atau informasi keuangan dalam log produksi.
16. Tidak ada bug kritis yang menyebabkan saldo atau laporan tidak konsisten.

---

# 20. Success Metrics

Karena aplikasi local-first, metrik awal dapat dievaluasi melalui pengujian lokal dan usability testing, tanpa analytics cloud.

- Rata-rata waktu pencatatan manual.
- Rata-rata waktu pencatatan melalui Quick Add.
- Persentase keberhasilan ekstraksi transaksi AI.
- Persentase draft AI yang membutuhkan koreksi.
- Jumlah error konsistensi saldo.
- Keberhasilan backup dan restore.
- Persentase fitur inti yang tersedia dalam airplane mode.
- Tingkat penyelesaian onboarding.
- Kepuasan pengguna terhadap dashboard.
- Konsistensi penggunaan selama uji coba 7 dan 30 hari.

Target awal:

- Quick Add kurang dari 5 detik.
- Seluruh skenario ledger lulus pengujian.
- Tidak ada kehilangan data akibat kegagalan penyimpanan.
- Minimal 90% keberhasilan parsing pada dataset kalimat transaksi sederhana yang telah ditentukan.
- Seluruh fitur inti dapat digunakan dalam airplane mode.

---

# 21. Product Risks & Mitigation

| Risiko | Mitigasi |
|---|---|
| Data hilang ketika uninstall | Backup terenkripsi dan reminder |
| Gemini API Key bocor | Secure storage, BYOK, tidak mencatat key |
| Gemini menghasilkan informasi salah | Structured output, validasi, konfirmasi |
| Saldo tidak konsisten | Ledger berpasangan dan atomic transaction |
| Transfer terhitung pengeluaran | Aturan bisnis transfer dan unit test |
| Dana tabungan dihitung dua kali | Allocation ledger dan referensi kewajiban |
| Notifikasi tidak muncul | Permission handling, scheduler, informasi pembatasan OS |
| FCM membutuhkan layanan eksternal | Local Notification menjadi mekanisme utama |
| Model Gemini berubah | Model configurable dan capability validation |
| Pengguna malas mencatat | Quick Add, template, AI Quick Expense |
| Aplikasi terlalu kompleks | Navigasi sederhana dan progressive disclosure |
| Database migration gagal | Snapshot, migration test, dan rollback |
| Perangkat dikompromikan | Enkripsi, app lock, dan transparansi risiko |
| Biaya API meningkat | Request hanya saat diperlukan, batas input, tanpa retry berlebihan |

---

# 22. Final Product Experience

Pengguna menerima gaji dan mencatat:

"Gajian 5 juta masuk BCA."

Aplikasi membuat draft pemasukan. Setelah dikonfirmasi, saldo diperbarui dan fitur Salary Day menawarkan pembagian gaji.

Dana dialokasikan untuk kos, makanan, transportasi, tabungan, dan kebutuhan lainnya.

Setiap hari, pengguna dapat mencatat pengeluaran dengan cepat melalui template atau bahasa natural.

Ketika pengguna ingin membeli suatu barang, Purchase Simulator menunjukkan dampaknya terhadap anggaran dan target tabungan.

Menjelang akhir bulan, aplikasi memberikan Financial Recap yang menjelaskan kebiasaan pengeluaran serta perkembangan keuangan.

Semua data tersebut tersimpan di perangkat pengguna.

Aplikasi dapat digunakan tanpa internet untuk pencatatan, pengelolaan saldo, laporan, dan pengingat lokal. AI hanya digunakan ketika pengguna membutuhkannya dan telah mengaktifkan API Key sendiri.

**Arus bukan sekadar aplikasi pencatatan pengeluaran. Arus adalah asisten keuangan pribadi yang membantu pengguna mencatat uang dengan mudah, memahami kondisi finansial, dan mengambil keputusan sebelum membelanjakan uang.**
