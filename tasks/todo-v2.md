# Todo v2: Catat jajan, Dompet, dan "Aman dipakai hari ini"

Rincian tiap tugas ada di `tasks/plan-v2.md`; spec di `SPEC-v2.md` (disetujui 2026-11-01).
Satu commit per tugas. Tidak ada migrasi DB di v2.

## Fase B. Backend di repo `tepira` (branch `feature/mobile-api-v2`)
- [ ] B1a Logika murni: `safeToday`, rentang WIB, gerak saldo + unit test
- [ ] B1b Harness uji handler + perubahan helper bersama (`lockExpense`, `createExpenseInTx`, `updateExpenseWithWallet`); izin disetujui 2026-11-01
- [ ] B2 `GET/POST /api/mobile/wallets`, `PATCH /api/mobile/wallets/[id]`
- [ ] B3 `GET /api/mobile/today`
- [ ] B4 `POST /api/mobile/expenses`
- [ ] B5a `GET /api/mobile/expenses`
- [ ] B5b `PATCH/DELETE /api/mobile/expenses/[id]`
- [ ] B6 Kontrak dan fixtures ke repo mobile
- [ ] B7 Uji balapan manual di Postgres lokal (tidak di-commit; output di deskripsi PR)
- [ ] Checkpoint B: PR `tepira` dibuka hanya setelah diminta; tanpa migrasi, tanpa env baru; test, `lint`, `build` hijau

## Fase 5. Fondasi mobile v2 (paralel dengan Fase B)
- [ ] T12 Housekeeping
- [ ] T13 `core-network`: `BadRequestException`, `wib.dart`, `categories.dart`
- [ ] T14 `wallets` data: DTO, model, repository + unit test

## Fase 6. Dompet
- [ ] T15 Layar Dompet (termasuk kelompok Dana dicadangkan, Uang bebas di kepala) + widget test
- [ ] T16 Layar Tambah/Ubah dompet (toggle dicadangkan) + test validasi

## Fase 7. Catat jajan dan angka harian
- [ ] T17 `expenses` + `today` data + unit test
- [ ] T18 Tab Jajan di layar Catat (dompet dicadangkan boleh, tidak pernah default) + widget test
- [ ] T19 Kartu "Aman dipakai hari ini" di Desa + widget test

## Fase 8. Riwayat
- [ ] T20 Layar Riwayat (jajan) + widget test
- [ ] T21 Ubah dan hapus jajan + test
- [ ] T22 Dock navigasi + test rute

## Checkpoint 4
- [ ] Fixture B6 menggantikan fixture sementara; semua test hijau
- [ ] `/review` lima sumbu
- [ ] `/ship` checklist
- [ ] Uji manual emulator (OpenClaw) dengan backend lokal, termasuk web `/wallets` dan `/expenses` segar setelah tulis dari mobile

## Tindak lanjut (di luar v2)
- [ ] Samakan batas bulan web ke WIB (SPEC §14 Q3)
