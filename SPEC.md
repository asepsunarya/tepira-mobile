# SPEC: Auth Google dan Goal (kavling) untuk tepira-mobile

Status: disetujui 2026-11-01 (Q1: token = cookie Auth.js; Q2: tiga dependensi; Q3: Desa v1 daftar kavling).
Desain acuan: `docs/design/` (artboard `Login`, `Main`, `GoalDetail`, `BuatGoal`,
`TambahSetoran`, `SkeletonDesa`, `SesiBerakhir`).

## Capability Map

| Module id | Responsibility | Depends on |
|---|---|---|
| `backend-mobile-api` | Endpoint JSON di repo `tepira` untuk klien mobile: tukar Google ID token jadi sesi, daftar/detail/buat goal, tambah setoran | — (repo lain) |
| `core-network` | Klien `dio`, header sesi, pemetaan error ke `AppException`, format rupiah, konstanta base URL | — |
| `auth` | Google Sign-In di perangkat, tukar ke sesi backend, simpan di `flutter_secure_storage`, state auth, redirect rute | `core-network`, `backend-mobile-api` |
| `goals` | Model goal + tahap bangunan, repository, layar Desa (daftar), Kavling (detail), Bangun kavling, Setor | `auth`, `core-network`, `backend-mobile-api` |

Build order: `backend-mobile-api` (kontrak dulu, implementasi di repo `tepira`) → `core-network` → `auth` → `goals`.

Di luar scope spec ini: jajan/warung, dompet, gaji, laporan, kotak pos, jurnal, level/XP, widget,
notifikasi, offline. Semua itu menyusul sebagai spec terpisah dengan modul `goals` sebagai pola.

## 1. Objective

Pengguna tepira.id (allowlist Google) bisa masuk di Android/iOS, melihat goal tabungannya
sebagai kavling bergaya tepira village, membuat goal baru, dan menambah setoran. Data yang
tampil sama persis dengan web tepira.id karena backend dan database sama.

Target pengguna v1: pemilik akun tepira.id saat ini (1 sampai beberapa orang di allowlist).
Bukan untuk publik umum dulu.

## 2. Temuan tentang backend (fakta, bukan asumsi)

Dibaca dari `asepsunarya/tepira` commit `9d366c5`:

- Auth: Auth.js v5 (`next-auth@5.0.0-beta`), provider Google, `session.strategy = "jwt"`,
  cookie sesi `__Secure-authjs.session-token` di https (produksi) dan `authjs.session-token`
  di http (dev lokal) (JWE, kunci `AUTH_SECRET`). Allowlist email lewat
  `TEPIRA_DEFAULT_USER_EMAIL` + `TEPIRA_ALLOWED_EMAILS`.
- Tidak ada endpoint JSON untuk daftar goal yang memakai sesi pengguna. `/api/cyrene/goals`
  memakai Bearer token pemilik tunggal (`TEPIRA_API_KEY`) dan selalu bertindak sebagai
  `TEPIRA_DEFAULT_USER_EMAIL`, jadi tidak cocok untuk multi-akun.
- Buat goal dan hapus goal hanya ada sebagai server action (`app/dashboard/actions.ts`).
- Tambah setoran ada sebagai REST: `POST /api/contribution` (form-data `goalId`, `amount`,
  `note`), butuh cookie sesi.
- Aturan data: `Goal.targetAmount` dan `Contribution.amount` adalah `Int` rupiah;
  `saved` = jumlah contributions; `percent` = `min(100, saved/target*100)`; goal lama dengan
  `userId = null` ikut terlihat oleh semua user (`userOwnedWhere`).

Kesimpulan: ADR 0001 benar, perlu perubahan kecil di backend. Spec ini mendefinisikan kontraknya.

## 3. Kontrak `backend-mobile-api` (dikerjakan di repo `tepira`)

Semua di bawah `/api/mobile/*`, JSON, `Cache-Control: no-store`. Error memakai bentuk
`{ "ok": false, "error": "<kode>", "message": "<Indonesia>" }`.

### 3.1 `POST /api/mobile/session`

Tukar Google ID token dari perangkat menjadi sesi yang sama dengan web.

- Body: `{ "idToken": "<google id token>" }`
- Server: verifikasi token ke Google (`google-auth-library`, audience = client ID Android/iOS
  yang didaftarkan), cek allowlist dengan `isAllowedEmail`, cari/buat `User` + `Account`
  lewat Prisma adapter seperti alur web, lalu **encode JWT Auth.js** (`encode` dari
  `next-auth/jwt`, secret `AUTH_SECRET`, salt nama cookie) dan kembalikan tokennya.
- Respons 200: `{ "ok": true, "token": "<jwe>", "expiresAt": "<ISO>", "user": { "id", "name", "email", "image" } }`
- 401 `invalid_token`, 403 `not_allowed` (email di luar allowlist), 429 bila dibatasi.
- Alasan desain: dengan token yang sama persis seperti cookie web, mobile cukup mengirim
  `Cookie: __Secure-authjs.session-token=<token>` (https; `authjs.session-token` di http lokal) dan **semua route lama yang memanggil `auth()`
  (`/api/contribution`, dll.) langsung bekerja tanpa diubah**. Tidak ada skema token kedua.

### 3.2 `GET /api/mobile/goals`

- Auth: cookie sesi. Filter `userOwnedWhere(userId)`.
- Respons: `{ "ok": true, "asOf": "<ISO>", "goals": [ { "id", "title", "description", "target", "saved", "percent", "remaining", "deadline": "YYYY-MM-DD"|null, "daysLeft": int|null, "perMonthNeeded": int|null, "createdAt", "lastContribution": { "date", "amount" }|null, "contributionCount": int } ] }`
- Urutan sama dengan `/api/cyrene/goals` (belum selesai dulu, lalu deadline terdekat).
- Logika `percent`/`remaining`/`daysLeft`/`perMonthNeeded` memakai `goalPlan` yang sudah ada.

### 3.3 `GET /api/mobile/goals/{id}`

- Seperti satu item di 3.2 plus `"contributions": [ { "id", "amount", "note", "date": "<ISO>" } ]`
  terbaru dulu, maksimal 200.
- 404 `not_found` bila bukan milik user.

### 3.4 `POST /api/mobile/goals`

- Body: `{ "title": string 1..60, "description"?: string ≤200, "target": int > 0, "deadline"?: "YYYY-MM-DD" }`
- Validasi sama dengan `createGoal`. Respons 201 dengan item goal (bentuk 3.2).

### 3.5 Tambah setoran

Memakai endpoint yang sudah ada: `POST /api/contribution` (multipart `goalId`, `amount`,
`note`). Respons `{ "success": true }`. Tidak perlu endpoint baru. Setelah sukses, klien
memanggil ulang 3.3.

### 3.6 Keluar

Tidak ada endpoint; klien menghapus token dari secure storage. JWT tetap berlaku sampai
kedaluwarsa (sama seperti web saat cookie dihapus).

## 4. Acceptance criteria

### `core-network`
- [ ] `ApiClient` (dio) memakai base URL dari `--dart-define=TEPIRA_API_BASE_URL`, default `https://tepira.asepsunarya.com/api`.
- [ ] Interceptor menambahkan cookie sesi bila token ada, hanya ke origin API; nama mengikuti
  skema base URL: https → `__Secure-authjs.session-token`, http → `authjs.session-token`.
- [ ] 401 → `UnauthorizedException`, 403 → `ForbiddenException`, 404 → `NotFoundException`,
  5xx dan `{ok:false}` → `ServerException`, timeout/socket → `NetworkException`; semua
  subclass `AppException` dengan `message` Indonesia untuk UI.
- [ ] Unit test: tiap pemetaan status di atas, dan header cookie terpasang hanya saat ada token.

### `auth`
- [ ] Tombol "Masuk dengan Google" memanggil `google_sign_in`, mengambil `idToken`, memanggil
  `POST /api/mobile/session`, menyimpan `token` + `user` di `flutter_secure_storage`.
- [ ] `authStateProvider` (Riverpod) punya tiga keadaan: `unknown` (saat baca storage),
  `signedOut`, `signedIn(user)`.
- [ ] go_router redirect: `signedOut` → `/login`; `signedIn` di `/login` → `/`.
- [ ] 403 `not_allowed` menampilkan pesan "Akun ini belum terdaftar di tepira.id" di layar Masuk.
- [ ] `UnauthorizedException` dari endpoint mana pun mengosongkan sesi dan membuka overlay
  "Sesi desamu sudah berakhir" (artboard `SesiBerakhir`, tab pertama).
- [ ] Keluar dari Pengaturan menghapus storage dan kembali ke `/login`.
- [ ] Test: provider overrides dengan repository palsu untuk tiga keadaan dan redirect.

### `goals`
- [ ] `Goal` model: `id, title, description, target, saved, percent, remaining, deadline,
  daysLeft, perMonthNeeded, lastContribution, contributionCount`. Semua uang `int`.
- [ ] `buildStage(saved/target)`: `lahan` 0, `fondasi` >0, `dinding` ≥0.3, `atap` ≥0.7,
  `selesai` ≥1 (sama dengan `lib/game.ts` village). Unit test lima ambang.
- [ ] `GoalsRepository`: `list()`, `detail(id)`, `create(...)`, `contribute(goalId, amount, note)`.
  Screen tidak pernah memanggil dio langsung.
- [ ] Layar Desa (`/`): HUD sederhana (nama, jumlah goal aktif), daftar kavling dengan tahap,
  progres, dan nominal dalam format `Rp1.500.000`; skeleton saat loading (artboard
  `SkeletonDesa`); kondisi kosong (artboard `DesaKosong`, versi ringkas); tarik untuk muat ulang.
  Panel pulau 3D/2D, lampu streak, level/XP, dan dock lengkap **tidak** termasuk spec ini;
  dock hanya tab Desa aktif dan tombol Catat.
- [ ] Layar Kavling (`/goal/:id`): ilustrasi tahap bangunan (SVG dari `Ilustrasi.dc.html`),
  nominal, persen, sisa, kejar deadline (`perMonthNeeded`), riwayat setoran, tombol Setor.
- [ ] Layar Bangun kavling (`/goal/new`): nama, target, tanggal; validasi sisi klien sama
  dengan server; sukses → kembali ke Desa dengan goal baru tampil.
- [ ] Layar Setor (`/record?goal=:id`): pilih kavling, chip nominal cepat (10/20/50/100 ribu),
  keypad, catatan opsional; sukses → detail kavling dimuat ulang dan tahap bangunan bisa
  berubah. Bagian Jajan dan catat cepat **tidak** termasuk spec ini (tab Jajan dinonaktifkan).
- [ ] Widget test untuk Desa (loading, kosong, 3 goal), Kavling, dan Setor (validasi nominal 0).
- [ ] Golden test minimal untuk `GoalRow` dan `GoalProgress` dengan tema baru.

### Lintas modul
- [ ] `flutter analyze` bersih, `flutter test` hijau, `dart format` rapi.
- [ ] Tema dari `docs/design/screens/PanduanGaya.dc.html` dipindah ke `lib/core/theme.dart`
  (Nunito via `google_fonts`, warna, radius). Tema gelap seed emerald lama diganti.

## 5. Commands

| Task | Command |
|---|---|
| Install | `flutter pub get` |
| Run | `flutter run --dart-define=TEPIRA_API_BASE_URL=http://10.0.2.2:3000/api` |
| Test | `flutter test` |
| Lint | `flutter analyze` |
| Format | `dart format lib test` |
| Backend lokal | di repo `tepira`: `npm run dev` |

## 6. Project structure (tambahan pada struktur CLAUDE.md)

```
lib/
  core/
    theme.dart            tema village (diganti)
    brands.dart           peta nama dompet → aset/warna (dipakai spec berikutnya)
    widgets/              VillageCard, VillageButton, VillageChip, StatTile, GoalRow, StageNote
    errors.dart           AppException + subclass
    format.dart           formatRupiah (ada)
  data/
    api_client.dart       dio + interceptor cookie
    auth/                 session_store.dart, auth_repository.dart, dto
    goals/                goals_repository.dart, goal_dto.dart
  features/
    auth/                 login_screen.dart, auth_providers.dart
    goals/                goals_screen.dart (Desa), goal_detail_screen.dart (Kavling),
                          new_goal_screen.dart, contribute_screen.dart, goal_providers.dart,
                          widgets/ (build_stage_art.dart, goal_progress.dart)
  app.dart                router + redirect
assets/
  brands/                 dari docs/design/brands/full
  fonts/                  Nunito (atau google_fonts saat runtime)
test/                     mirror lib/
```

## 7. Code style

- Mengikuti CLAUDE.md: feature-first, Riverpod, repository untuk semua API, money `int`,
  error lewat `AppException`, copy Indonesia, kode dan komentar Inggris.
- DTO terpisah dari model UI; parsing JSON di `data/`, tidak di widget.
- Warna dan radius hanya dari `theme.dart`/`ThemeExtension`, tidak ada hex di widget.
- Tiap layar punya tiga keadaan eksplisit: loading (skeleton), error (pesan + coba lagi), data.

## 8. Testing strategy

- Unit: pemetaan error, `buildStage`, DTO parsing dari contoh JSON kontrak (disimpan di
  `test/fixtures/`), `formatRupiah` (ada).
- Widget: tiap layar dengan repository palsu lewat `ProviderScope(overrides:)`.
- Golden: dua komponen inti, diperbarui sadar lewat `--update-goldens`.
- Integrasi manual: `flutter run` ke emulator Android dengan backend lokal dan Google client
  ID debug. Dilakukan oleh OpenClaw/Claude di mesin pemilik; sesi cloud ini tidak punya emulator.
- Prove-It untuk setiap bug: test gagal dulu, baru fix.

## 9. Boundaries

**Always**
- Kirim token hanya sebagai header `Cookie` ke host base URL; tidak pernah ke host lain, log, atau crash report.
- Baca `docs/design/` dan catatan tempel `canvas.json` sebelum membuat layar.
- Jalankan `flutter analyze` dan `flutter test` sebelum commit.

**Ask first**
- Dependensi baru: `google_sign_in`, `google_fonts`, `flutter_svg` (diusulkan di sini, lihat §10).
- Perubahan apa pun di repo `tepira` (modul `backend-mobile-api`).
- Perubahan kontrak §3 setelah disetujui.
- Konfigurasi native: SHA-1/OAuth client Android, URL scheme iOS, `google-services.json`.

**Never**
- Commit `google-services.json`, `GoogleService-Info.plist`, keystore, `.env*`.
- Menyimpan token di SharedPreferences atau log.
- Memakai `/api/cyrene/*` dari aplikasi (token pemilik tunggal, bukan per pengguna).
- Menghitung `percent` dengan cara berbeda dari server; angka dari server adalah kebenaran.

## 10. Dependensi yang diusulkan (butuh persetujuan)

| Paket | Alasan | Ukuran |
|---|---|---|
| `google_sign_in ^6.2` | Google Sign-In native Android/iOS, memberi `idToken` | plugin resmi, kecil |
| `google_fonts ^6.2` | Nunito tanpa membundel berkas font; cache lokal | ~100 KB + unduhan font pertama |
| `flutter_svg ^2.0` | Logo merek dan ilustrasi tahap bangunan dari SVG | ~300 KB |

Alternatif tanpa `google_fonts`: bundel Nunito woff2/ttf di `assets/fonts/` (OFL). Saya
memilih bundel kalau kamu ingin offline-first nanti.

## 11. Asumsi yang perlu dikoreksi kalau salah

1. Backend boleh ditambah `/api/mobile/*` di repo `tepira` (saya buat sebagai PR terpisah
   setelah spec disetujui, memakai modul yang ada: `isAllowedEmail`, `goalPlan`, Prisma adapter).
2. Satu OAuth client Google baru untuk Android (dan iOS) didaftarkan di project Google Cloud
   yang sama; backend menerima audience web + Android + iOS.
3. v1 online-first (ADR 0001); offline hanya pesan error, bukan antrean.
4. Tampilan Desa v1 memakai daftar kavling tanpa panel pulau; panel pulau masuk spec
   "desa-visual" berikutnya supaya auth dan goals bisa dipakai lebih dulu.
5. Nama pengguna di HUD dari `user.name` Google; kalau kosong pakai "Warga".

## 12. Keputusan

- Q1. Kontrak §3 disetujui: token mobile = JWT Auth.js yang sama dengan cookie web.
- Q2. Tiga dependensi §10 disetujui.
- Q3. Desa v1 memakai daftar kavling; panel pulau masuk spec "desa-visual" berikutnya.
