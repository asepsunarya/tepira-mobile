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

Sumber kebenaran: `api-contract.md` dari handler asli di branch `feature/mobile-api` repo
`tepira` (`app/api/mobile/**/route.ts`), dibangkitkan 2026-11-01 dengan jam tetap
`2026-11-01T07:00:00.000Z` dan data fiktif. SPEC mengikuti backend, bukan sebaliknya.
Fixture dari generator yang sama ada di `test/fixtures/` (`mobile_goals.json` = 3.2,
`mobile_goal_detail.json` = 3.3); pakai untuk test parsing.

Aturan umum:

- Host sama dengan web (produksi `https://tepira.asepsunarya.com`), path `/api/mobile/*`.
- Semua respons JSON dengan header `Cache-Control: no-store, max-age=0, private`,
  `Vary: Cookie`, `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`.
- **Amplop.** Sukses: `{ "ok": true, ... }`. Error (semua endpoint):
  `{ "ok": false, "error": "<kode>", "message": "<teks Indonesia, tampilkan apa adanya>" }`.
  Klien bercabang berdasarkan status HTTP + `error`; `message` tidak pernah di-parse.
- **Nama field camelCase.** Uang (`target`, `saved`, `remaining`, `perMonthNeeded`, `amount`)
  = `int` rupiah. `percent` = angka 0–100, boleh satu desimal (mis. `41.3`), jadi `num`
  di Dart. `id` goal/setoran = `int`; `id` user = `String`.
- **Tanggal.** `asOf`, `createdAt`, `expiresAt`, `lastContribution.date`,
  `contributions[].date` = ISO-8601 UTC dengan milidetik (`2026-10-28T12:45:00.000Z`).
  `deadline` = tanggal kalender `YYYY-MM-DD` (WIB) atau `null`.
- **Nullable, tidak pernah hilang:** `description`, `deadline`, `daysLeft`, `perMonthNeeded`,
  `lastContribution`, `note`, `user.name`, `user.email`, `user.image`. `daysLeft` dan
  `perMonthNeeded` `null` bila tanpa deadline; `perMonthNeeded` juga `null` bila goal sudah
  tercapai. `daysLeft` = `0` bila deadline sudah lewat.
- Kode error yang dipakai: `bad_request` 400, `unauthorized` 401, `invalid_token` 401,
  `not_allowed` 403, `account_not_linked` 403, `not_found` 404,
  `unsupported_media_type` 415, `rate_limited` 429, `server_error` 500.

### 3.1 `POST /api/mobile/session`

Tukar Google ID token dari perangkat menjadi token sesi Auth.js yang sama dengan web.

- Aktif hanya bila env `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS` (daftar client ID Google dipisah
  koma, diterima sebagai `aud`) terisi; kalau tidak, **404 `not_found`** untuk setiap
  permintaan (dicek sebelum rate limit).
- Request: `Content-Type: application/json`, body `{ "idToken": "<Google ID token>" }`
  (string 1–4096 karakter; key lain diabaikan).
- Respons 200:

```json
{
  "ok": true,
  "token": "<Auth.js JWE, ~500 karakter>",
  "expiresAt": "2026-12-01T07:00:00.000Z",
  "user": {
    "id": "user_owner",
    "name": "Rina Contoh",
    "email": "rina@example.test",
    "image": "https://example.test/avatar/rina.png"
  }
}
```

- `expiresAt` = sekarang + 30 hari. `user` berisi tepat `id`, `name`, `email`, `image`.
- Memakai token: kirim di setiap request sebagai cookie sesi Auth.js,
  `Cookie: __Secure-authjs.session-token=<token>` di produksi (`AUTH_URL` https) dan
  `Cookie: authjs.session-token=<token>` di dev lokal (`AUTH_URL` http). Nama cookie juga
  salt enkripsi: nama salah ⇒ dianggap belum masuk (401 di endpoint goal). Dengan token yang
  sama persis seperti cookie web, route lama yang memanggil `auth()` (`/api/contribution`,
  dll.) langsung bekerja. Tidak ada skema token kedua.
- Error:
  - `404` `not_found` — "Data tidak ditemukan." (fitur nonaktif, env kosong)
  - `400` `bad_request` — "Permintaan tidak valid: idToken wajib diisi." (`idToken`
    hilang/tidak valid, juga body bukan JSON)
  - `401` `invalid_token` — "Token Google tidak valid atau sudah kedaluwarsa. Coba masuk lagi."
    (signature/aud/issuer salah atau kedaluwarsa)
  - `403` `not_allowed` — "Akun ini belum terdaftar di tepira.id." (email di luar allowlist
    atau belum diverifikasi Google)
  - `403` `account_not_linked` — "Email ini sudah terdaftar dengan akun lain. Masuk lewat web
    tepira.id dulu." (email ada tanpa akun Google tertaut)
  - `429` `rate_limited` — "Terlalu banyak percobaan masuk. Coba lagi sebentar lagi."
    (10 percobaan/menit per IP; header `Retry-After: <detik>`, mis. `6`)
  - `500` `server_error` — sertifikat Google tak terjangkau / konfigurasi server salah

### 3.2 `GET /api/mobile/goals`

- Auth: cookie sesi. Urutan: yang belum selesai dulu, lalu deadline terdekat, lalu tanpa
  deadline, lalu terbaru; yang sudah selesai (`saved >= target`) paling akhir.
- Respons 200 (= `test/fixtures/mobile_goals.json`, satu item ditampilkan):

```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "goals": [
    {
      "id": 12,
      "title": "Laptop kerja",
      "description": "Ganti laptop lama sebelum proyek baru",
      "target": 15000000,
      "saved": 6200000,
      "percent": 41.3,
      "remaining": 8800000,
      "deadline": "2027-04-30",
      "daysLeft": 180,
      "perMonthNeeded": 1466667,
      "createdAt": "2026-06-01T03:15:00.000Z",
      "lastContribution": {
        "date": "2026-10-28T12:45:00.000Z",
        "amount": 1200000
      },
      "contributionCount": 4
    }
  ]
}
```

- Error: `401` `unauthorized` — "Sesi sudah berakhir. Silakan masuk lagi."; `500` `server_error`.

### 3.3 `GET /api/mobile/goals/{id}`

- Auth: cookie sesi. Respons 200 `{ "ok": true, "asOf": "<ISO>", "goal": { ... } }`:
  field item sama dengan 3.2 ditambah `contributions` (terbaru dulu, seri diurutkan `id`
  lebih besar dulu, maksimal 200; `saved`/`contributionCount` tetap menghitung semua).
  Contoh lengkap: `test/fixtures/mobile_goal_detail.json`. Bentuk satu setoran:

```json
{ "id": 117, "amount": 1500000, "note": null, "date": "2026-08-26T10:30:00.000Z" }
```

- Error:
  - `401` `unauthorized` — "Sesi sudah berakhir. Silakan masuk lagi."
  - `404` `not_found` — "Data tidak ditemukan." (tidak ada, milik user lain, atau id bukan
    int32 positif, mis. `abc`)
  - `500` `server_error`

### 3.4 `POST /api/mobile/goals`

- Auth: cookie sesi. `Content-Type: application/json` (`charset` boleh).
- Body: `title` string 1–60 karakter (di-trim, tanpa karakter kontrol) **wajib**;
  `target` integer 1..2147483647 **wajib** (angka JSON, bukan string);
  `description` string ≤200 karakter, opsional (`""`/`null` → `null`);
  `deadline` `"YYYY-MM-DD"` opsional (`""`/`null` → `null`). Key lain diabaikan.
- Respons **201** `{ "ok": true, "goal": { ... } }` dengan item bentuk 3.2. Contoh: body
  `{"title": "Kamera mirrorless", "description": "Untuk konten", "target": 9000000, "deadline": "2027-06-30"}`
  → `goal` dengan `id` 16, `saved` 0, `percent` 0, `remaining` 9000000, `daysLeft` 241,
  `perMonthNeeded` 1000000, `createdAt` = waktu server, `lastContribution` null,
  `contributionCount` 0. Body `{"title": "Dana pendidikan", "target": 20000000}` → `description`,
  `deadline`, `daysLeft`, `perMonthNeeded` semuanya `null`.
- Error:
  - `401` `unauthorized` — "Sesi sudah berakhir. Silakan masuk lagi."
  - `415` `unsupported_media_type` — "Format permintaan harus JSON." (Content-Type bukan JSON)
  - `400` `bad_request` dengan salah satu pesan: "Judul harus diisi, maksimal 60 karakter.",
    "Target harus berupa angka bulat lebih dari 0.", "Tanggal target harus berformat
    YYYY-MM-DD.", "Isi permintaan harus berupa objek JSON." (body bukan objek / JSON tidak
    valid), "Deskripsi harus berupa teks.", "Deskripsi maksimal 200 karakter."
  - `500` `server_error`

### 3.5 Tambah setoran

Tidak di bawah `/api/mobile`: memakai endpoint yang sudah ada `POST /api/contribution`
(multipart form `goalId`, `amount`, `note`) dengan cookie sesi yang sama. Setelah sukses,
klien memanggil ulang 3.3.

Endpoint lama ini **tidak** memakai amplop `{ok, error, message}`. Responsnya
`{ "success": true }` (200) atau `{ "success": false, "message": "<teks>" }` dengan status
400 (nominal ≤ 0), 401 (tanpa sesi), 404 (goal tidak ditemukan/bukan milik user), atau 500.
Tidak ada field `error`; klien bercabang hanya berdasarkan status HTTP, dan 2xx berarti
setoran tersimpan (body sukses tidak membawa data goal).

### 3.6 Keluar

Tidak ada endpoint; klien menghapus token dari secure storage. Token tetap berlaku sampai
`expiresAt` (sama seperti web saat cookie dihapus).

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
  daysLeft, perMonthNeeded, createdAt, lastContribution, contributionCount`. Semua uang `int`;
  `percent` `double` (server mengirim `num` 0–100, boleh satu desimal, mis. `41.3`);
  `createdAt` `DateTime` UTC. Server **membulatkan** `percent` ke satu desimal
  (`Math.round(saved/target*1000)/10`, maks 100), jadi `percent` tidak dipakai untuk tampilan
  atau ambang tahap: klien menghitung persen tampilan sendiri dari `saved`/`target`
  (lihat §12 Q4).
- [ ] `buildStage(saved, target)`: `lahan` 0, `fondasi` >0, `dinding` ≥30%, `atap` ≥70%,
  `selesai` ≥100%. Ambang diambil dari artboard (catatan "Tahap bangunan dari progres" di
  `docs/design/canvas.json`), dihitung dari `saved`/`target` dengan bilangan bulat supaya batas
  30% dan 70% tepat. Unit test lima ambang.
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
- Memakai `percent` dari server untuk ambang tahap bangunan; nilainya sudah dibulatkan
  (mis. 29,96% terkirim sebagai `30`). Tahap dan persen tampilan dihitung dari `saved`/`target`.

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
- Q4. Server membulatkan `percent` ke satu desimal. Klien menghitung persen tampilan
  sendiri dari `saved`/`target` (`GoalProgress`), dan tahap bangunan juga dari `saved`/`target`
  dengan ambang artboard (30%/70%/100%), bukan dari `percent` server.
