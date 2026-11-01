# Desain tepira-mobile

Sumber desain UI aplikasi, bergaya **tepira village** (pastel, cozy, goal = bangunan).
Kanvas interaktifnya ada di claude.ai (privat, perlu dibagikan pemilik):

- Kanvas desain: https://claude.ai/artifact/Nf3mfX9VBS2aK2R5ahJsGi
- Animasi setoran (Motion, 20 dtk): https://claude.ai/artifact/CbBfKLcyM1mjszcM81Vths

Folder ini adalah salinan sumbernya supaya bisa dibaca tanpa akun claude.ai, oleh
manusia maupun agen lain.

## Isi

| Path | Isi |
|---|---|
| `canvas.json` | Tata letak artboard (`boards`, `order`) dan **catatan tempel** (`notes`) yang berisi aturan bisnis tiap layar |
| `screens/*.dc.html` | 46 artboard. Tiap berkas HTML mandiri: buka di browser untuk melihat tampilannya |
| `brands/full/*.svg` | Logo resmi berwarna penuh dompet/bank/kartu (dari [wynhnzz/idn-finance-logo](https://github.com/wynhnzz/idn-finance-logo), MIT, lihat `LICENSE`) |
| `brands/mark/*.svg` | Varian ikon kecil: `arct-*` dari Arcticons (CC BY-SA 4.0, garis putih), `logo-*` dari SVG Logos (MIT) |

Logo tetap milik merek masing-masing; dipakai hanya untuk mengenali dompet pengguna.

## Cara membaca `.dc.html`

- Ukuran ponsel 390×844 (iPhone 14 class). Root `<div>` pertama di dalam `<x-dc>` adalah layar.
- Semua gaya inline (`style="…"`): nilai px, warna hex, radius bisa disalin langsung ke Flutter.
- `<sc-for>` / `<sc-if>` dan `{{hole}}` adalah template data; nilainya ada di `renderVals()` pada
  `<script type="text/x-dc">` di bawah markup. Contoh data (nama goal, nominal) fiktif.
- `<a href="Lain.dc.html">` adalah tautan prototipe antar layar; petakan ke rute go_router (lihat Peta alur).
- `/_blob/<id>` pada `<img src>` adalah aset kanvas; padanannya ada di `brands/`.
- Berkas lebar 860 px (`PanduanGaya`, `Komponen`, `PetaAlur`, `Ilustrasi`, `IkonMerek`) adalah lembar
  referensi, bukan layar aplikasi. `KartuFeed` 1080×1080 dan `KartuStory` 1080×1920 adalah gambar ekspor.

## Peta artboard → rute

| Artboard | Rute | Catatan |
|---|---|---|
| `Login` | `/login` | Google saja (Auth.js) |
| `Tutorial` | `/tour` | 9 langkah, progres tersimpan di akun |
| `IzinNotifikasi`, `IzinLokasi` | `/tour/permissions` | pra-izin lalu dialog OS |
| `Main` | `/` | Desa: HUD level, pulau, lampu streak, kavling, dock |
| `DesaKosong` | `/` (akun baru) | tiga langkah awal |
| `SkeletonDesa`, `SkeletonDaftar` | — | status memuat (`AsyncValue.loading`) |
| `GoalDetail` | `/goal/:id` | Kavling: tahap bangunan, kejar deadline |
| `UbahGoal` | `/goal/:id/edit` | status, target tanggal, zona bahaya |
| `BuatGoal` | `/goal/new` | jenis bangunan |
| `GoalSelesai` | `/goal/:id/done` | perayaan rampung |
| `Bagikan`, `KartuFeed`, `KartuStory` | `/goal/:id/share` | kartu gambar, sembunyikan nominal |
| `PindahDana` | `/goal/:id/move` | dua setoran (minus/plus), tanpa lampu streak |
| `SetoranRutinGoal` | `/goal/:id/recurring` | aturan rutin per kavling |
| `ArsipGoal` | `/archive` | goal selesai |
| `TambahSetoran` | `/record` | Setor/Jajan, catat cepat, keypad |
| `Suara` | `/record/voice` | speech_to_text id-ID |
| `PilihTempat` | `/record/place` | geolocator opsional |
| `Warung` | `/shop` | jajan per tempat, batas jajan |
| `PetaJajan` | `/shop/map` | penanda nominal per tempat |
| `Riwayat` | `/history` | edit/hapus lewat lembar bawah |
| `TagihanRutin` | `/recurring/new` | Pengeluaran/Setoran, jadwal, otomatis |
| `KotakPos` | `/mailbox` | Pak Pos, surat Cyrene |
| `Laporan` | `/report` | skor kesehatan, cuaca |
| `AliranUang` | `/report/flow` | sungai gaji → waduk → tujuan |
| `Gaji` | `/salary` | alokasi 9 kategori + tabungan |
| `Dompet`, `TambahDompet` | `/wallets`, `/wallets/new` | peti harta, logo merek |
| `Jurnal` | `/journal` | hari ke-N, musim, kalender kebiasaan |
| `Perkembangan`, `Perayaan` | `/progress` | bangunan level, warga |
| `Pengaturan`, `PinGate` | `/settings`, `/settings/pin` | pengingat, PIN |
| `Notifikasi`, `Widget` | sistem | push, home-screen widget |
| `Offline`, `SesiBerakhir` | overlay | cache, 401/500/migrasi |
| `Splash` | — | splash & ikon aplikasi |

## Token (ringkas; lengkap di `screens/PanduanGaya.dc.html`)

Warna: langit `#cfe9f7`, kartu `#fffaf7`, ink `#5a4a5e`, redup `#74647a`, garis `#f1e4ea`,
pink `#ff7eb3` / teks `#c2457d` / CTA `#cf3b7b→#bf3571`, mint `#6cc8ad` / teks `#1f8a63`,
koin `#f3c35b`, peach `#f0a06a`, merah `#c23b3b`, biru `#5b9ae0`.
Font: Nunito 700/800/900. Radius: kartu 22, tile 12–16, pil 999. Sentuh min 44 px, tombol utama 56 px.

## Urutan implementasi yang disarankan

1. `lib/core/theme.dart` dari Panduan gaya.
2. Widget bersama di `lib/core/widgets/` dari Katalog komponen.
3. Rute go_router dari Peta alur.
4. Aset: salin `brands/full` ke `assets/brands/`, ilustrasi dari `Ilustrasi.dc.html` (flutter_svg).
5. Tiap layar dibangun dari artboard-nya; artboard bisa jadi acuan golden test.
