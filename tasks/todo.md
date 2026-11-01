# Todo: Auth Google dan Goal (kavling)

Rincian tiap tugas ada di `tasks/plan.md`. Satu commit per tugas.

## Fase 0. Baseline
- [x] T0 Perbaiki `goal_progress_test` di Flutter 3.47; commit `pubspec.lock`

## Fase 2. Fondasi mobile (paralel dengan Fase 1)
- [x] T3 Dependensi (`google_sign_in`, `google_fonts`, `flutter_svg`), tema village, widget bersama, golden
- [x] T4 `core-network`: `SessionStore`, cookie interceptor, pemetaan error + unit test

## Fase 1. Backend di repo `tepira` (branch `feature/mobile-api`)
- [ ] T1 `POST /api/mobile/session` + unit test
- [ ] T2 `GET/POST /api/mobile/goals`, `GET /api/mobile/goals/[id]` + fixtures ke repo mobile
- [ ] Checkpoint 1: fixtures ada; env `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS` dicatat di README tepira

## Fase 3. Auth
- [x] T5 Login Google → sesi → redirect; overlay sesi berakhir; test provider

## Fase 4. Goals
- [x] T6 DTO, model, `buildStage`, `GoalsRepository` + unit test
- [x] T7 Layar Desa: skeleton, kosong, daftar, muat ulang + widget test
- [x] T8 Layar Kavling: ilustrasi tahap, angka, riwayat + widget test
- [ ] T9 Layar Bangun kavling + test validasi
- [ ] T10 Layar Setor + test
- [x] T11 Pengaturan minimal + keluar

## Checkpoint 3
- [ ] `/review` lima sumbu
- [ ] `/ship` checklist
- [ ] Uji manual emulator (OpenClaw) dengan backend lokal
