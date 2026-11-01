# Plan: Auth Google dan Goal (kavling)

Sumber: `SPEC.md` (disetujui 2026-11-01). Desain: `docs/design/`.

## Dependency graph

```
backend-mobile-api (repo tepira)
   │
   ▼
core-network ──► auth ──► goals (Desa → Kavling → Bangun → Setor)
   ▲
   └── foundation (tema, widget bersama, dependensi)
```

- `foundation` dan `backend-mobile-api` tidak saling bergantung: bisa jalan paralel
  (backend oleh saya sebagai PR di `tepira`; foundation di repo ini).
- `auth` butuh endpoint 3.1 nyata hanya untuk uji manual; unit/widget test memakai repository palsu,
  jadi mobile bisa maju tanpa menunggu backend deploy.
- Setiap layar `goals` adalah irisan vertikal: DTO → repository → provider → layar → test.

## Fase dan tugas

### Fase 0. Baseline hijau

**T0. Perbaiki test `goal_progress_test` yang gagal di Flutter 3.47**
- Masalah: `find.bySemanticsLabel('Progres 25%')` tidak menemukan apa pun. Kemungkinan
  `LinearProgressIndicator` kini memasang semantics sendiri sehingga label induk digabung.
- Kriteria: `flutter test` hijau tanpa mengubah perilaku widget yang terlihat; `pubspec.lock` ikut
  di-commit (app, bukan package).
- Verifikasi: `flutter analyze && flutter test`.

### Fase 1. Backend (repo `tepira`, branch `feature/mobile-api`, PR terpisah)

**T1. `POST /api/mobile/session`**
- `lib/mobile/session.ts`: verifikasi Google ID token (`google-auth-library`), audience dari
  `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS` (koma), `isAllowedEmail`, upsert User+Account lewat
  Prisma adapter, `encode()` JWT Auth.js dengan `AUTH_SECRET` dan salt `authjs.session-token`.
- Rate limit per IP seperti `guard()`; tidak pernah log token.
- Kriteria: 200 dengan `token` yang diterima `auth()` saat dikirim sebagai cookie; 401 token
  salah; 403 email di luar allowlist. Unit test `lib/mobile/session.test.ts` dengan verifier palsu.
- Verifikasi: `node --test lib/mobile/session.test.mjs` (pola `test:auth` yang ada, tanpa vitest); `npm run lint`.

**T2. `GET /api/mobile/goals`, `POST /api/mobile/goals`, `GET /api/mobile/goals/[id]`**
- Pakai `auth()` + `userOwnedWhere`, `goalPlan`, validasi sama dengan `createGoal`.
- Simpan contoh respons nyata ke `tepira-mobile/test/fixtures/mobile_goals.json` dan
  `mobile_goal_detail.json` (data fiktif) sebagai kontrak.
- Kriteria: bentuk JSON persis SPEC §3.2 sampai §3.4; 404 untuk goal orang lain; 400 untuk
  target ≤ 0.
- Verifikasi: unit test mapper `lib/mobile/goals.test.mjs` lewat `node --test`; tambah skrip `test:mobile` di `package.json`.

**Checkpoint 1**: PR `tepira` dibuka (hanya setelah kamu minta), fixtures ada di repo mobile,
`.env` produksi butuh `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS`.

### Fase 2. Fondasi mobile

**T3. Dependensi + tema village + widget bersama**
- `pubspec.yaml`: `google_sign_in`, `google_fonts`, `flutter_svg`; `assets/brands/` dari
  `docs/design/brands/full`.
- `lib/core/theme.dart`: token dari `PanduanGaya` sebagai `ThemeData` + `ThemeExtension<VillageColors>`
  (langit, kartu, ink, redup, garis, pink, pinkSoft, pinkText, cta, mint, mintSoft, mintText, koin,
  peach, merah, biru). Nunito via `GoogleFonts.nunitoTextTheme`.
- `lib/core/widgets/`: `VillageCard`, `VillageButton` (primary/ghost/soft/danger), `VillageChip`,
  `StatTile`, `StageNote`, `Pill`.
- Kriteria: golden `VillageButton` dan `VillageCard`; `GoalProgress` dirender dengan warna tema
  (test yang ada tetap hijau).
- Verifikasi: `flutter analyze && flutter test`.

**T4. `core-network`: sesi di header + pemetaan error**
- `lib/data/session_store.dart`: `flutter_secure_storage` (`token`, `user` JSON), antarmuka
  `SessionStore` agar bisa dipalsukan.
- `lib/data/api_client.dart`: interceptor `onRequest` menambah `Cookie: authjs.session-token=<token>`;
  `onError` memetakan 401/403/404/5xx/timeout ke subclass `AppException` (tambah `ForbiddenException`,
  `NotFoundException`, `ServerException` di `core/errors.dart`).
- Kriteria: unit test dengan `dio` adapter palsu untuk setiap status dan untuk ada/tidaknya cookie.
- Verifikasi: `flutter test test/data/api_client_test.dart`.

**Checkpoint 2**: commit per task; branch di-push.

### Fase 3. Auth

**T5. Login Google → sesi → redirect**
- `lib/data/auth/auth_repository.dart`: `signInWithGoogle()` (google_sign_in → idToken →
  `POST /api/mobile/session` → simpan), `restore()`, `signOut()`.
- `lib/features/auth/auth_providers.dart`: `authStateProvider` (`unknown | signedOut | signedIn`).
- `lib/features/auth/login_screen.dart` dari artboard `Login`.
- `lib/app.dart`: `GoRouter` dengan `redirect` + `refreshListenable` dari auth state; rute `/login`, `/`.
- `UnauthorizedException` global → `authState` jadi `signedOut` + overlay `SesiBerakhir` ringkas.
- Kriteria: SPEC §4 `auth` semua centang; test provider + redirect dengan repository palsu.
- Verifikasi: `flutter test`; manual di emulator oleh OpenClaw setelah backend T1 tersedia.

### Fase 4. Goals (irisan vertikal per layar)

**T6. Model, DTO, repository, `buildStage`**
- `lib/data/goals/goal_dto.dart` parse fixtures; `lib/features/goals/model/goal.dart`;
  `build_stage.dart` dengan lima ambang; `GoalsRepository` (`list`, `detail`, `create`, `contribute`).
- Kriteria: unit test parsing dari fixtures dan lima ambang tahap.

**T7. Layar Desa (daftar kavling)**
- `goalsProvider` (`AsyncNotifier`), `GoalsScreen` dengan skeleton, kosong, data, tarik-muat-ulang,
  tombol Bangun kavling, tombol Catat; `GoalRow` + `BuildStageIcon`.
- Kriteria: widget test tiga keadaan; angka pakai `formatRupiah`.

**T8. Layar Kavling (detail)**
- `goalDetailProvider(id)`, `GoalDetailScreen`: ilustrasi tahap (SVG), nominal, persen, sisa,
  `perMonthNeeded`, riwayat setoran, tombol Setor.
- Kriteria: widget test dengan fixture detail; tahap tampil sesuai persen.

**T9. Layar Bangun kavling**
- `NewGoalScreen`: nama, target (int), tanggal; validasi klien; sukses → invalidasi `goalsProvider`.
- Kriteria: test validasi (nama kosong, target 0) dan sukses memanggil repository sekali.

**T10. Layar Setor**
- `ContributeScreen`: pilih kavling, chip cepat, keypad, catatan; `POST /api/contribution`;
  sukses → invalidasi detail + daftar.
- Kriteria: test nominal 0 ditolak; sukses memanggil `contribute(goalId, 20000, note)`.

**T11. Pengaturan minimal + keluar**
- `SettingsScreen` ringkas: nama/email, tombol Keluar; rute `/settings` dari avatar HUD.
- Kriteria: keluar mengosongkan store dan redirect ke `/login`.

**Checkpoint 3**: `/review` lima sumbu, lalu `/ship` checklist; OpenClaw uji manual di emulator
dengan backend lokal.

## Ukuran dan urutan

| Task | Perkiraan baris | Bergantung pada |
|---|---|---|
| T0 | 20 | — |
| T1 | 250 (tepira) | — |
| T2 | 250 (tepira) | T1 |
| T3 | 400 | T0 |
| T4 | 200 | T3 |
| T5 | 350 | T4 |
| T6 | 250 | T2 (fixtures) atau fixtures sementara dari SPEC |
| T7 | 300 | T5, T6 |
| T8 | 300 | T7 |
| T9 | 200 | T7 |
| T10 | 300 | T8 |
| T11 | 120 | T5 |

Urutan eksekusi saya: T0 → T3 → T4 → T1 → T2 → T5 → T6 → T7 → T8 → T9 → T10 → T11.
Backend (T1, T2) disisipkan setelah fondasi supaya fixtures nyata siap sebelum T6.

## Risiko

- Google ID token audience: client ID Android/iOS harus terdaftar di project Google Cloud
  yang sama; tanpa itu T5 hanya bisa diuji dengan repository palsu.
- `encode()` dari `next-auth/jwt` di v5 beta memakai salt nama cookie; harus dicek terhadap
  versi terpasang (`5.0.0-beta.31`) agar `auth()` menerima token.
- Goal lama `userId = null` terlihat semua user: perilaku web dipertahankan, dicatat di DTO.
