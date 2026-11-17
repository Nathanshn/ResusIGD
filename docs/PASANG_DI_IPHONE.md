# Memasang ResusIGD di iPhone (pakai Mac teman, gratis)

Perkiraan waktu: 30–60 menit, termasuk unduh Xcode bila belum ada.

## Yang dibutuhkan

- **Mac** dengan **Xcode 16 atau lebih baru**. Versi Xcode harus mendukung versi iOS di iPhone-mu: iPhone dengan iOS 26 butuh Xcode 26, yang butuh macOS 15.6+.
- **iPhone** dengan **iOS 17 atau lebih baru**, plus **kabel** ke Mac.
- **Apple ID-mu sendiri**. Akun gratis cukup, tidak perlu Apple Developer Program.

> Dengan Apple ID gratis, aplikasi aktif **7 hari**. Setelah itu buka lagi lewat Mac dan tekan Run untuk memperpanjang. Maksimal 3 aplikasi sekaligus.

## 1. Unduh proyek di Mac

Buka **Terminal** di Mac, lalu jalankan:

```bash
git clone https://github.com/Nathanshn/ResusIGD.git
```

```bash
cd ResusIGD
```

(Bila muncul jendela untuk memasang "Command Line Developer Tools", klik **Install**, tunggu, lalu ulangi perintahnya.)

## 2. Jalankan skrip setup

```bash
bash scripts/setup-mac.sh
```

Skrip ini memeriksa Xcode, mengunduh XcodeGen ke folder proyek (tidak memasang apa pun ke sistem Mac), membuat `ResusIGD.xcodeproj`, lalu membuka Xcode.

## 3. Login Apple ID di Xcode

**Xcode → Settings… → Accounts → +** → **Apple ID** → login dengan Apple ID-**mu**.

## 4. Atur signing

1. Di panel kiri Xcode, klik **ResusIGD** (ikon biru paling atas).
2. Pilih target **ResusIGD** → tab **Signing & Capabilities**.
3. Centang **Automatically manage signing**. Pada **Team**, pilih *Nama Kamu (Personal Team)*.
4. Bila muncul error *"Failed to register bundle identifier"*, ubah **Bundle Identifier** menjadi sesuatu yang unik, misalnya `id.resusigd.namakamu`.

## 5. Siapkan iPhone

1. Colok iPhone ke Mac → buka kunci iPhone → ketuk **Trust / Percayai**.
2. Aktifkan **Developer Mode**: **Pengaturan → Privasi & Keamanan → Mode Pengembang → ON**, lalu restart iPhone dan konfirmasi.
   (Menu ini baru muncul setelah iPhone pernah dicolok ke Mac yang menjalankan Xcode.)

## 6. Jalankan

1. Di toolbar atas Xcode, pilih **iPhone-mu** sebagai tujuan (bukan simulator).
2. Tekan **▶ Run** (atau ⌘R). Build pertama butuh beberapa menit.
3. Bila iPhone menolak membuka aplikasi ("Untrusted Developer"): **Pengaturan → Umum → VPN & Manajemen Perangkat** → pilih Apple ID-mu → **Percayai**. Lalu buka ResusIGD lagi.

## Kalau build gagal

Aplikasi ini belum pernah dikompilasi di Mac, jadi mungkin masih ada error kecil.

1. Di Xcode, buka **Report Navigator** (ikon paling kanan di panel kiri, atau ⌘9) → klik build terakhir.
2. Salin teks error berwarna merah (atau screenshot), lalu kirim ke pengembang/Claude.
3. Setelah perbaikan di-push ke GitHub, di Terminal Mac jalankan:

```bash
git pull
```

```bash
bash scripts/setup-mac.sh
```

lalu tekan **▶ Run** lagi.

## Menjalankan tes (opsional)

Di Xcode pilih simulator iPhone mana pun → **Product → Test** (⌘U).
