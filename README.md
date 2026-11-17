# ResusIGD

Aplikasi iOS native untuk dokter umum IGD di Indonesia: kalkulator titrasi obat high-alert dewasa, dosis pediatri, guideline emergensi offline, dan Code Timer resusitasi. Aplikasi bekerja **100% offline**: semua data obat dan guideline dibundel di dalam aplikasi.

> ⚠️ **Alat bantu keputusan klinis, bukan pengganti penilaian klinis.** Seluruh seed data (dosis, sediaan, batas konsentrasi) **wajib diverifikasi oleh apoteker klinis/Komite Farmasi & Terapi RS** sebelum dipakai pada pasien. Sesuaikan dengan formularium dan sediaan yang tersedia di RS Anda.

---

## Arsitektur

```
ResusIGD/
├── project.yml                     # XcodeGen spec (generate .xcodeproj di Mac)
├── .github/workflows/ios.yml       # CI macOS: test core + build/test app (tanpa perlu Mac sendiri)
├── ClinicalCore/                   # Swift Package — MESIN KLINIS MURNI (tanpa UI)
│   ├── Sources/ClinicalCore/
│   │   ├── Models/                 # AdultDrug, PediatricDrug, Guideline, SafetyAlert, Patient
│   │   ├── Services/
│   │   │   ├── Calculators/        # Infusion, DripRate, PediatricDose, WeightEstimator,
│   │   │   │                       # ResuscitationEquipment, Fluid (Holliday-Segar), Burn (Rule of Nines + Parkland),
│   │   │   │                       # GCS/NIHSS, Electrolyte (Na, KCl, Alteplase), InputPlausibility
│   │   │   ├── ResusSessionEngine  # logika timer RJP/epinefrin/fase kejang
│   │   │   ├── SOAPLogFormatter    # ekspor log ke format SOAP
│   │   │   ├── FuzzySearch         # pencarian offline toleran typo
│   │   │   └── SeedRepository      # loader + validator seed JSON
│   │   └── Resources/SeedData/     # adult_drugs.json, pediatric_drugs.json, guidelines.json
│   └── Tests/ClinicalCoreTests/    # 110 unit test
├── ResusIGD/                       # Target aplikasi iOS (SwiftUI)
│   ├── App/                        # @main, TabView 4 tab + tombol Code Blue mengambang
│   ├── Models/                     # SwiftData @Model (katalog obat/guideline, sesi resusitasi)
│   ├── Services/ClinicalLibrary    # impor seed → SwiftData, sediakan data ke ViewModel
│   ├── ViewModels/                 # @Observable @MainActor (MVVM)
│   ├── Views/                      # Components, Titration, Pediatric, Guidelines(+Calculators), CodeTimer
│   └── Resources/Assets.xcassets
└── ResusIGDTests/                  # tes impor SwiftData & wiring ViewModel
```

**Prinsip desain**

- **Matematika murni & deterministik** di `ClinicalCore`: tidak ada `UIKit/SwiftUI/SwiftData`, sehingga bisa dites di macOS, Linux, maupun Windows. View dan ViewModel tidak menghitung apa pun sendiri.
- **Guardrail sebagai data**: setiap kalkulator mengembalikan `[SafetyAlert]` dengan `AlertCode` yang stabil (`.danger/.warning/.info`). UI menampilkannya sebagai banner berwarna yang terpisah dari angka hasil.
- **SwiftData** menyimpan katalog (payload JSON dari struct `ClinicalCore`) dan sesi resusitasi. Sesi yang belum diakhiri akan dipulihkan bila aplikasi tertutup di tengah resusitasi.
- **Swift 6 strict concurrency**: semua ViewModel `@MainActor @Observable`; semua model inti `Sendable`.
- **UI**: kontras tinggi, angka utama besar (`mL/jam`, `tpm`, `mg`, `mL`), target sentuh ≥ 44 pt, mode Gelap OLED (latar hitam murni), bahasa Indonesia.

## Modul

| Tab | Isi |
|---|---|
| **Titrasi** | Norepinefrin, Dopamin, Dobutamin, Epinefrin, Sulfas Atropin, Amiodaron, Nicardipin, Nitrogliserin. Pembuat sediaan (kekuatan/jumlah ampul, 50/100/250/500 mL, NaCl 0,9% / D5%), cek kompatibilitas pelarut, mL/jam, tpm makro/mikro, konsentrasi, langkah pengenceran, batas konsentrasi perifer vs CVC, peringatan ekstravasasi & dosis maksimal, mode bolus. |
| **Pediatri** | Estimasi BB (APLS, Luscombe-Owens, zona panjang gaya Broselow, Traub-Johnson); ukuran ETT (cuff/tanpa cuff), kedalaman, laringoskop, LMA, energi defibrilasi & kardioversi; bolus 10/20 mL/kg; Holliday-Segar; formularium 19 obat dengan mg **dan** mL per sediaan, deteksi salah ketik BB, batas dosis dewasa (tunggal & harian). |
| **Guideline** | Code Stroke (+NIHSS, Alteplase), Luka Bakar (+Rule of Nines & Parkland berbasis waktu kejadian), ACLS (henti jantung, bradikardia, takikardia), ATLS (primary survey + GCS, syok hemoragik, tension/tamponade), Status Epileptikus, Anafilaksis, SKA, Koreksi Elektrolit (Na & KCl), GCS. |
| **Code Timer** | Mode Code Blue (siklus RJP 2 menit + pengingat epinefrin 3/4/5 menit) & Status Epileptikus (fase 5/20/40 menit), tombol log satu-tap, haptic + suara, undo, salin log format SOAP, riwayat sesi. |

## Menjalankan unit test mesin klinis

Bisa dijalankan di Windows, Linux, maupun macOS (cukup Swift 6):

```bash
swift test --package-path ClinicalCore
```

Di Windows: jalankan dari "x64 Native Tools Command Prompt for VS 2022", atau muat `vcvars64.bat` terlebih dahulu. Bila path folder sangat panjang, tambahkan `--scratch-path C:\b`.

## Build aplikasi iOS

**Dengan Mac (Xcode 16+):**

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
open ResusIGD.xcodeproj
```

Pilih tim signing di target `ResusIGD`, lalu Run ke simulator atau iPhone.

**Tanpa Mac:** push folder ini ke repositori GitHub. Workflow `.github/workflows/ios.yml` akan berjalan di runner macOS: menjalankan unit test core, membuat project dengan XcodeGen, lalu build + test aplikasi di iOS Simulator. Workflow juga gagal bila ada compiler warning. Untuk memasang ke iPhone atau rilis ke App Store tetap dibutuhkan akun Apple Developer (bisa lewat Xcode Cloud atau layanan Mac cloud).

## Mengubah database obat lokal

Semua konten ada di `ClinicalCore/Sources/ClinicalCore/Resources/SeedData/`:

| File | Isi |
|---|---|
| `adult_drugs.json` | Obat titrasi dewasa: `ampoule` (mg/mL per ampul), `defaultAmpouleCount`, `defaultFinalVolumeML`, `diluentRules` (`preferred`/`compatible`/`caution`/`incompatible` + catatan), `peripheralMaxConcentrationMgPerML`, `centralLinePreferred`, `extravasationWarning`, `regimens[]` (`mode` `infusion`/`bolus`, `unit` `mcgPerKgPerMin`/`mcgPerMin`/`mgPerMin`/`mgPerHour`, `minDose`/`maxDose`/`defaultDose`/`step`, `hardCeilingDose`, `maxCumulativeMg`). |
| `pediatric_drugs.json` | Obat anak: `formulations[]` (`liquid` + `mgPerML`, atau `unit` + `mgPerUnit` + `unitDivisibility`), `regimens[]` (`route`, `mgPerKgMin/Default/Max` **atau** `fixedDoseBands`, `dosesPerDay`, `maxSingleDoseMg`, `maxDailyDoseMg`, `maxDailyMgPerKg`, `minAgeMonths`, `minWeightKg`, `formulationIDs`). |
| `guidelines.json` | Guideline: `sections[]` dengan `kind` `targets`/`checklist`/`drugs`/`redFlags`/`notes`/`table` (baris tabel dipisah ` \| `), `calculators[]` (`burnParkland`, `nihss`, `alteplase`, `gcs`, `sodiumCorrection`, `potassiumDrip`). |

**Langkah:**

1. Edit JSON. Contoh: mengganti sediaan Dobutamin RS Anda menjadi 250 mg/20 mL → `"ampoule": { "mg": 250, "mL": 20 }`.
2. **Naikkan `"version"`** di file yang diubah. Aplikasi akan mengimpor ulang saat dibuka berikutnya; record yang ditandai `isUserModified` tetap dipertahankan.
3. Jalankan `swift test --package-path ClinicalCore`. Test `SeedDataTests` akan menjalankan `SeedValidator` (ID duplikat, rentang dosis `min ≤ default ≤ max`, aturan pelarut lengkap, referensi sediaan valid, regimen berbasis BB wajib punya `maxSingleDoseMg`) dan memastikan setiap regimen bisa dihitung.
4. Perbarui ekspektasi `testSeedLoadsAndHasRequiredContent` bila Anda menambah/menghapus obat (signature versi, ID wajib).

Setiap regimen pediatri berbasis BB **wajib** memiliki `maxSingleDoseMg` (batas dosis dewasa). Validator menolak data tanpa batas ini.

## Catatan klinis & keterbatasan

- Zona panjang "gaya Broselow" memakai batas pendekatan yang dipublikasikan, **bukan** pita resmi. Gunakan pita resmi bila tersedia, dan timbang pasien sesegera mungkin.
- Ukuran ETT dibulatkan ke 0,5 terdekat (nilai tengah dibulatkan **ke bawah**). Siapkan juga ukuran ±0,5.
- Koreksi Na memakai rumus Adrogué-Madias; volume > 40 mL/kg (maks 3 L) per 24 jam ditandai tidak realistis.
- Timer memakai jam perangkat; bila aplikasi berada di latar belakang, pengingat audio/haptic baru muncul saat aplikasi dibuka kembali (waktu tetap akurat).
