# Plan v2: Catat jajan, Dompet (termasuk Dana dicadangkan), dan "Aman dipakai hari ini"

Sumber: `SPEC-v2.md` (revisi 2, **disetujui 2026-11-01**). Desain: `docs/design/`.
Status plan: **disetujui 2026-11-01**; keputusan pemilik ada di bagian akhir. Tiket backend (prefiks **B**, repo `tepira`) dipisah dari tiket mobile (prefiks **T**,
melanjutkan penomoran v1).

Revisi 2 mengikuti review SPEC/plan v2:
- B4 memakai pola transaksi Cyrene.
- Hapus jajan dikunci per baris.
- PATCH memakai semantik merge.
- Rumus `safeToday` baru (SPEC §3.4).
- Uji backend disesuaikan dengan `node --test` yang ada.
- B1 dipecah menjadi B1a/B1b, B5 dipecah menjadi B5a/B5b, dan ada uji balapan manual B7.
- Ada revalidasi web.
- T18 bergantung pada T15.

**Migrasi DB: tidak ada di v2.** Migrasi apa pun **butuh persetujuan pemilik**; tiket yang
ternyata membutuhkan migrasi berhenti dan dilaporkan, tidak dikerjakan.

## Dependency graph

```
B1a logika murni (safeToday, WIB, wallet-moves)
 └─► B1b harness uji + helper bersama (lock, createExpenseInTx, updateExpenseWithWallet) [Ask first]
      ├─► B2 wallets ───────┐
      ├─► B3 today ─────────┤
      │    (B1a juga)       ├─► B4 POST expenses ─► B5a GET expenses ─┐
      │                     │                    └► B5b PATCH/DELETE ─┼─► B6 kontrak + fixtures
      │                     │                         └► B7 uji balapan manual (lokal)
                                         B6 ─► (mobile T15, T17, T19, T20 memakai fixture nyata)

T12 housekeeping ─► T13 core-network ─► T14 wallets data ─► T15 Dompet ─► T16 Tambah/Ubah dompet
                                      └► T17 expenses+today data ─┬► T18 Catat Jajan (+T15) ─► T19 kartu Desa
                                                                  └► T20 Riwayat ─► T21 Ubah/Hapus (+T18)
T15, T18, T20 ─► T22 dock navigasi
```

- Backend (B*) dan fondasi mobile (T12–T14) tidak saling bergantung, jadi bisa jalan paralel.
- Tiket mobile memakai repository palsu dan fixture sementara yang ditulis dari contoh SPEC §3.
  Setelah B6, fixture diganti dengan hasil generator dan test parsing dijalankan ulang.
- Setiap layar adalah irisan vertikal: DTO → repository → provider → layar → test.

Ukuran: **S** ≤150 baris, **M** 150–350, **L** 350–500. Satu commit per tiket. Tidak ada commit
atau push tanpa permintaan.

## Fase dan tugas

### Fase B. Backend (repo `tepira`, branch `feature/mobile-api-v2`, PR terpisah)

Seluruh fase B butuh izin sebelum PR dibuka (SPEC §9 "Ask first"). B1b mengubah helper yang juga
dipakai web dan Cyrene; izin untuk itu diminta eksplisit bersama PR.

**B1a. Logika murni: `safeToday`, rentang WIB, gerak saldo** · M · bergantung: —
- `lib/mobile/today.ts` (tanpa import, hanya TypeScript yang bisa dihapus tipenya):
  - `wibMonthRange(year, month)`, `daysLeftInWibMonth(now)`;
  - `bucketExpenses(rows, now)` → `S_before`, `E_today`, `E_month`, `E_today'`, `E_next'` menurut
    `date` (SPEC §3.4);
  - `computeSafeToday({ status, limit, sBefore, eToday, eMonth, free, eTodayFree, eNextFree,
    daysLeft })` → `{ basis, state, days, allowance, spentToday, remaining }`;
  - `SAFE_TODAY_HORIZON_DAYS = 30`.
- `lib/wallet-moves.ts` (baru, tanpa import): `expenseBalanceDelta(isDebt, amount)`,
  `planExpenseUpdate(old, next)` → gerak `{walletId, delta}`, digabung per dompet, delta 0 dibuang,
  diurutkan menurut `walletId`.
- Test (`node --test` biasa):
  - `lib/mobile/today.test.mjs` didaftarkan di `test:mobile`. Isinya **contoh A–H SPEC §3.4 dengan
    angka persis**, ditambah 23:59/00:00 WIB, bulan 31 hari, dan jajan 2026-10-31T17:30Z yang masuk
    November.
  - `lib/wallet-moves.test.mjs` didaftarkan di `test:wallets`. Isinya: dompet sama, aset→utang,
    baris yatim, dompet dicadangkan, dan urutan.
- Verifikasi: `npm run test:mobile && npm run test:wallets && npm run lint`.

**B1b. Harness uji handler + perubahan helper bersama** · M · bergantung: B1a · **Ask first**
- `test/harness/` diport dari `handoff/fixtures-gen/`:
  - `register.mjs` dan `hooks.mjs` memetakan `@/` ke root repo lewat `import.meta.url`;
  - `stub-auth.mjs`;
  - `stub-cache.mjs` mencatat `revalidatePath`;
  - `fake-prisma.mjs` berisi tabel in-memory, `$transaction(fn)` dengan klien yang sama,
    `$queryRaw` yang mencatat SQL, dan log urutan panggilan.
- Skrip baru `test:mobile-api`: `node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON --import
  ./test/harness/register.mjs --test <daftar file test/mobile-api/*.test.mjs>`.
- `.github/workflows/ci.yml`: tambah langkah `npm run test:mobile-api` (disetujui).
- `lib/wallet-expenses.ts`:
  - `import type { Prisma }` (tanpa perubahan runtime);
  - ekspor `lockExpense(tx, id)`, `SELECT 1 FROM "Expense" WHERE id = ${id} FOR UPDATE`;
  - `createExpenseInTx(tx, userId, wallet, data)`: `create` + `updateMany` atomik + cek
    `count === 1`;
  - `updateExpenseWithWallet(userId, id, patch, merge)`: lock → baca → merge → dompet baru →
    `planExpenseUpdate` → update. Hasilnya bertipe `not_found` / `invalid` (`{ kind: "invalid",
    message }`, patch yang digabung dengan baris tersimpan gagal validasi) / `wallet_required` /
    `wallet_not_found` / `updated`, bukan `throw Error`. Dompet lama yang bukan milik user (data
    tidak konsisten) → cek `count === 1` gagal → rollback → 500 (perilaku yang diketahui, SPEC
    §3.7);
  - `deleteExpenseAndRestoreWallet` memanggil `lockExpense` dulu. Web (`app/expenses/actions.ts:41`)
    ikut memakainya;
  - `createExpenseWithWallet` tidak diubah.
- `app/api/cyrene/expenses/[id]/route.ts`: `lockExpense` sebelum `findFirst` (undo).
- Kriteria:
  - `npm run test:cyrene` tetap hijau;
  - test handler pertama (smoke) memuat route v1 `GET /api/mobile/goals` lewat harness;
  - test helper lewat harness: query pertama di ubah/hapus/undo adalah `FOR UPDATE`.
- Verifikasi: `npm run test:mobile && npm run test:wallets && npm run test:cyrene &&
  npm run test:mobile-api && npm run lint && npm run build`.

**B2. `GET/POST /api/mobile/wallets`, `PATCH /api/mobile/wallets/[id]`** · M · bergantung: B1b
- `lib/mobile/wallets.ts`:
  - parse body (SPEC §3.2), termasuk kunci jenis utang;
  - merge PATCH per tabel §3.3: tidak dikirim = tetap, `null` hanya mengosongkan `description`;
  - mapper `MobileWallet` (`displayBalance`, `spentThisMonth`); totals lewat `summarizeWallets`.
- Route `app/api/mobile/wallets/route.ts` dan `[id]/route.ts`:
  - `sortOrder` baru = `max+1`;
  - PATCH hanya menulis kolom yang dikirim (`balance` tidak ditulis bila tidak ada di body);
  - `revalidatePath("/wallets")` dan `revalidatePath("/dashboard")` setelah tulis.
- Kriteria:
  - bentuk JSON persis SPEC §3.1–3.3;
  - 404 untuk dompet orang lain;
  - 400 untuk: utang + dicadangkan, jenis tak dikenal, utang negatif (POST; PATCH hanya bila
    `balance` dikirim), pindah jenis utang, `null` di field non-nullable;
  - PATCH `name` saja pada dompet utang bersaldo negatif → 200;
  - 415 untuk non-JSON;
  - test "PATCH hanya `name`" tidak menyentuh `balance`.
- Verifikasi: `npm run test:mobile && npm run test:mobile-api && npm run lint`.

**B3. `GET /api/mobile/today`** · M · bergantung: B1a, B1b
- **Langkah 0, sebelum implementasi (baca saja):** query data nyata untuk dompet utang bersaldo
  negatif (`SELECT count(*), min(balance) FROM "Wallet" WHERE "isDebt" AND balance < 0`, plus
  jumlah jajan yang memakai dompet itu). Laporkan hasilnya ke koordinator dan tunggu keputusan
  sebelum lanjut. SPEC §3.3 dan §11 asumsi 11 menganggap nilainya 0 baris.
- Route `app/api/mobile/today/route.ts` mengambil:
  - jajan dengan `date ≥ m0`, **tanpa batas atas** (WIB, dengan `isReserved`/`isDebt` dompet).
    Form web bisa menyimpan jajan bertanggal jauh di depan yang sudah memotong saldo dompet, jadi
    semua baris `≥ t1` harus terbaca sebagai `E_next'` (SPEC §3.4). `bucketExpenses` sudah
    menangani baris itu; `computeMonthSummary` hanya menerima baris di `[m0, awal bulan depan)`;
  - Salary + Bonus beserta `allocations` bulan itu (seperti `app/api/cyrene/summary/route.ts:84-88`);
  - setoran bulan itu: `Contribution` tidak punya `userId`, jadi disaring lewat goal,
    `where: { goal: userOwnedWhere(userId), date: { gte: m0, lt: awal bulan depan } }`;
  - dompet.

  Setelah itu memanggil `computeMonthSummary`, `bucketExpenses`, dan `computeSafeToday`.
  `buildToday(userId, now)` diekspor dari modul server kecil supaya bisa dipakai ulang oleh B4/B5b.
- Kriteria:
  - bentuk SPEC §3.4 untuk `ok`, `over_today`, `over_month`, dan basis `wallet`;
  - `budget.limit/remaining` `null` saat `NO_BUDGET`;
  - jajan bertanggal besok tidak mengubah `allowance`;
  - `savedThisMonth` tidak menghitung setoran ke goal milik user lain;
  - hari terakhir bulan: jajan bertanggal besok dari dompet bebas masuk `E_next'` (basis `wallet`
    tidak turun), tidak masuk `budget.spent`;
  - jajan bertanggal bulan depan atau lebih jauh (dari web) masuk `E_next'`, tidak masuk
    `budget.spent`.
- Verifikasi: `npm run test:mobile && npm run test:mobile-api && npm run lint`.

**B4. `POST /api/mobile/expenses`** · M · bergantung: B2 (mapper dompet), B3 (`buildToday`)
- `lib/mobile/expenses.ts`:
  - parse body (SPEC §3.5), memakai `parseExpenseDate` dan aturan teks dari `lib/cyrene/core.ts`
    yang dioper sebagai parameter; batas nominal 100.000.000; `walletId` wajib;
  - mapper `MobileExpense`: kategori → label, tanpa kategori → `null`.
- Route mengikuti pola Cyrene (`app/api/cyrene/expenses/route.ts:68-121`). Dalam satu
  `$transaction`:
  1. `pg_advisory_xact_lock(hashtext('tepira-mobile-expense:' + userId))`;
  2. dompet milik user, bila tidak ada → `400 wallet_not_found`;
  3. dedupe `expenseDedupeWhere` → `200 deduped:true`;
  4. `createExpenseInTx`.

  Setelah commit: `buildToday` dan revalidasi `/expenses`, `/dashboard`, `/wallets` (tidak
  dijalankan untuk dedupe).
- Kriteria:
  - test handler memastikan urutan panggilan lock → wallet → dedupe → create → updateMany di
    dalam satu callback transaksi;
  - 201 dengan `expense`, `wallet`, `today`;
  - permintaan kedua yang identik → 200, baris sama, tanpa tulis;
  - dompet asing → 400 `wallet_not_found` (bukan 500);
  - semua pesan 400 SPEC §3.5.
- Verifikasi: `npm run test:mobile && npm run test:mobile-api && npm run lint`.

**B5a. `GET /api/mobile/expenses`** · S · bergantung: B4 (mapper)
- Bulan WIB, urutan `date desc, id desc`, maksimal 500 baris; `total`/`count` seluruh bulan;
  `more`.
- Kriteria:
  - bentuk SPEC §3.6;
  - jajan 2026-10-31T17:30Z masuk November;
  - baris yatim → `walletId`/`walletName` `null`;
  - `year`/`month` salah → 400.
- Verifikasi: `npm run test:mobile-api && npm run lint`.

**B5b. `PATCH/DELETE /api/mobile/expenses/[id]`** · M · bergantung: B4, B1b
- `mergeExpensePatch(row, patch)` di `lib/mobile/expenses.ts` (murni) mengikuti tabel SPEC §3.7.
- PATCH memanggil `updateExpenseWithWallet` dengan `mergeExpensePatch` sebagai fungsi merge;
  hasil `invalid` → 400 `bad_request` dengan `message`-nya. DELETE memanggil
  `deleteExpenseAndRestoreWallet` (sudah terkunci). Keduanya mengembalikan dompet terdampak + `today` dan merevalidasi web.
- Kriteria:
  - unit: hanya `amount` dikirim → `category`, `note`, `source`, `date`, `walletId` tetap;
  - unit: `null` mengosongkan `category`/`note`; `null` di `amount`/`walletId`/`source`/`date`
    → 400;
  - unit: `date` lama tanpa `date` di body tetap boleh diubah nominalnya;
  - unit: `date` = hari ini pada jajan yang hari WIB-nya sudah hari ini → jam tersimpan tetap;
  - unit: body kosong → "Tidak ada perubahan.";
  - handler: `FOR UPDATE` adalah query pertama;
  - handler: 404 untuk jajan orang lain;
  - handler: baris yatim tanpa `walletId` → 400.
- Verifikasi: `npm run test:mobile && npm run test:mobile-api && npm run lint`.

**B6. Kontrak dan fixtures** · S · bergantung: B2–B5b
- Perluas generator `handoff/fixtures-gen/` untuk 8 endpoint baru (stub Prisma diperluas, atau
  memakai `test/harness/fake-prisma.mjs` dari repo).
- Bangkitkan ulang `handoff/api-contract.md`.
- Salin `mobile_wallets.json`, `mobile_today_budget.json` (contoh A), `mobile_today_wallet.json`
  (contoh F), `mobile_expense_created.json`, `mobile_expenses.json`, dan `categories.json` ke
  `tepira-mobile/test/fixtures/`.
- Sesuaikan SPEC-v2 §3 dengan output handler (SPEC mengikuti backend).
- Verifikasi: `cd handoff/fixtures-gen && TEPIRA_REPO=~/projects/tepira node --import ./register.mjs run.mjs`;
  diff fixture vs contoh SPEC; `npm run build` di `tepira`.

**B7. Uji balapan manual (lokal, tidak di-commit)** · S · bergantung: B5b
- Postgres 16 sekali pakai (`docker run --rm … postgres:16`, `prisma migrate deploy` dari migrasi
  yang **sudah ada**, seed fiktif). PGlite tidak dipakai karena hanya satu koneksi.
- Skenario SPEC §8:
  - 2 POST identik paralel;
  - PATCH + DELETE paralel ×50;
  - PATCH A→B dan B→A paralel ×50;
  - undo Cyrene + PATCH paralel.

  Saldo akhir dicocokkan dengan hitungan manual.
- Verifikasi: output skrip ditempel di deskripsi PR. **Tidak pernah ke DB produksi.**

**Checkpoint B**:
- PR `tepira` dibuka hanya setelah diminta, dengan izin eksplisit untuk perubahan helper bersama
  (B1b);
- tidak ada migrasi (migrasi butuh persetujuan pemilik);
- tidak ada env baru;
- semua skrip test, `lint`, dan `build` hijau.

### Fase 5. Fondasi mobile v2 (repo `tepira-mobile`, paralel dengan Fase B)

**T12. Housekeeping** · S · bergantung: —
- `tasks/todo.md`: tandai T1/T2 v1 selesai (sudah di `tepira` `0012c7f`), tambahkan bagian v2.
  Salin SPEC-v2 dan plan-v2 ke repo hanya bila pemilik meminta (mis. `docs/spec-v2.md`).
- Verifikasi: `git diff --stat` hanya menyentuh `tasks/`.

**T13. `core-network`: `BadRequestException`, `wib.dart`, `categories.dart`** · S · bergantung: T12
- `lib/core/errors.dart`: `BadRequestException(code, message)` untuk 400 `{ok:false}`;
  `lib/data/api_client.dart` memetakan. `lib/core/wib.dart` (offset tetap +7 jam).
  `lib/core/categories.dart` (9 label + group).
- Kriteria:
  - unit test 400 `bad_request` vs `wallet_not_found`;
  - pergantian hari/bulan WIB;
  - daftar kategori sama dengan `test/fixtures/categories.json` (sementara ditulis dari SPEC §2).
- Verifikasi: `flutter test test/core test/data/api_client_test.dart && flutter analyze`.

**T14. `wallets` data: DTO, model, repository** · M · bergantung: T13
- `lib/data/wallets/wallet_dto.dart`, `wallets_repository.dart` (`list`, `create`, `update`);
  `lib/features/wallets/model/wallet.dart` (`WalletKind`, `WalletTotals`);
  `lib/core/brands.dart` (nama → aset `assets/brands/`).
- Kriteria:
  - parsing `mobile_wallets.json` (sementara dari SPEC §3.1);
  - `WalletKind` tiga jenis;
  - utang `displayBalance` negatif;
  - `update` hanya mengirim field yang berubah.
- Verifikasi: `flutter test test/data/wallets test/features/wallets/model`.

### Fase 6. Dompet

**T15. Layar Dompet** · M · bergantung: T14
- `walletsProvider` (`AsyncNotifier`), `WalletsScreen` (`/wallets`):
  - kepala total (Total saldo, Uang bebas, Dana dicadangkan, utang);
  - tiga kelompok, `WalletRow`;
  - skeleton/kosong/error, tarik-muat-ulang;
  - konstanta rute `WalletRoutes` (`/wallets`, `/wallets/new`, `/wallets/:id/edit`) didefinisikan
    di tiket ini.
- Kriteria: SPEC §4 `wallets` (layar Dompet); golden `WalletRow` tiga jenis.
- Verifikasi: `flutter test test/features/wallets && flutter analyze`.

**T16. Layar Tambah/Ubah dompet** · M · bergantung: T15
- `WalletFormScreen` (`/wallets/new`, `/wallets/:id/edit`):
  - merek → nama, jenis, saldo/terutang, deskripsi;
  - toggle "Dana dicadangkan" (nonaktif untuk utang);
  - kunci kelompok jenis saat ubah;
  - ubah hanya mengirim field yang berubah.
- Kriteria:
  - test nama kosong;
  - toggle nonaktif untuk kartu kredit;
  - sukses memanggil repository sekali (penjaga tekan ganda);
  - daftar diperbarui dari respons.
- Verifikasi: `flutter test test/features/wallets && flutter analyze`.

### Fase 7. Catat jajan dan angka harian

**T17. `expenses` + `today` data** · M · bergantung: T14
- `lib/data/expenses/*` (`create`, `list`, `update`, `delete`) dan `lib/data/today/*`.
- Model `Expense` dan `TodaySummary` (`state` enum, `days`).
- `applyWriteResult` memperbarui `walletsProvider` dan `todayProvider` dari respons tulis.
- Kriteria:
  - parsing fixture §3.4–3.6 (sementara dari SPEC; `state` tak dikenal → error parsing);
  - `deduped` 200 dan 201 sama-sama sukses;
  - `applyWriteResult` mengganti dompet yang tepat;
  - `update` mengirim `null` untuk kategori/catatan yang dikosongkan.
- Verifikasi: `flutter test test/data/expenses test/data/today`.

**T18. Tab Jajan di layar Catat** · L · bergantung: T15 (rute `/wallets/new`), T17
- `ExpenseForm` di `contribute_screen.dart` (tab Jajan aktif, `/record?tab=jajan`):
  - chip 10/15/25/50 ribu, keypad, kategori;
  - pemilih dompet: default dompet terakhir yang bukan dicadangkan, `lastExpenseWalletId` di
    secure storage;
  - tanggal dan catatan langsung di form; "Lainnya" hanya berisi sumber dana (SPEC §4 `expenses`);
  - tanpa dompet → ajakan ke `/wallets/new`;
  - hilangkan pemilih "Dompet" di tab Setor bila ada (K8).
- Dikerjakan setelah T16 dalam urutan eksekusi, tetapi hanya butuh konstanta rute dari T15.
- Kriteria: SPEC §4 `expenses` (catat), termasuk alur 3 ketukan dan penjaga tekan ganda.
- Verifikasi: `flutter test test/features/expenses test/features/goals && flutter analyze`.

**T19. Kartu "Aman dipakai hari ini" di Desa** · M · bergantung: T17
- `todayProvider` dimuat ulang saat resume dan saat tanggal WIB berganti (lewat `clockProvider`).
- `SafeTodayCard` + tile "Jajan bulan ini" / "Ditabung bulan ini" di `goals_screen.dart`.
- Tampilan mengikuti `safeToday.state` (`ok`, `over_today`, `over_month`; SPEC §4 `today`).
- Kriteria:
  - `over_month` tidak pernah menampilkan kata "aman";
  - `remaining == 0` → "Jatah hari ini sudah habis";
  - golden `SafeTodayCard` untuk `ok`, `over_today`, `over_month`;
  - error kartu tidak menyembunyikan daftar kavling.
- Verifikasi: `flutter test test/features/today test/features/goals && flutter analyze`.

### Fase 8. Riwayat

**T20. Layar Riwayat (jajan)** · M · bergantung: T17
- `historyProvider(year, month)`, `HistoryScreen` (`/history`): header bulan + total, navigasi
  bulan, kelompok per hari WIB, `ExpenseRow`, skeleton `SkeletonDaftar`, catatan `more`.
- Kriteria: test kelompok pada batas tengah malam WIB, bulan kosong, error + coba lagi.
- Verifikasi: `flutter test test/features/expenses && flutter analyze`.

**T21. Ubah dan hapus jajan** · M · bergantung: T18, T20
- Bottom sheet Ubah/Hapus.
- Form Jajan terisi (`/record?expense=:id`) mengirim hanya field yang berubah; kategori/catatan yang
  dikosongkan dikirim sebagai `null`.
- Hapus dengan dialog konfirmasi; semua provider diperbarui dari respons.
- Kriteria:
  - test PATCH parsial (hanya nominal → body `{amount}`);
  - kosongkan catatan → `{note: null}`;
  - hapus butuh konfirmasi;
  - baris yatim wajib pilih dompet.
- Verifikasi: `flutter test test/features/expenses && flutter analyze`.

**T22. Dock navigasi** · S · bergantung: T15, T18, T20
- `lib/features/shell/app_dock.dart`: Desa, Riwayat, Catat (tengah), Dompet.
- Rute di `lib/core/routes.dart` dengan validasi id seperti `GoalRoutes.parseId`.
- Redirect auth v1 tetap berlaku untuk rute baru.
- Kriteria: test rute dan `?from=` untuk `/wallets` dan `/history`.
- Verifikasi: `flutter analyze && flutter test && dart format --set-exit-if-changed lib test`.

**Checkpoint 4**:
- fixture B6 menggantikan fixture sementara dan semua test hijau;
- `/review` lima sumbu;
- `/ship` checklist;
- OpenClaw uji manual di emulator dengan backend lokal (skenario SPEC §8), termasuk mengecek bahwa
  halaman web `/wallets` dan `/expenses` langsung segar setelah tulis dari mobile.

## Ukuran dan urutan

| Task | Ukuran | Perkiraan baris | Bergantung pada |
|---|---|---|---|
| B1a | M | 250 (tepira) | — |
| B1b | M | 350 (tepira, termasuk harness) | B1a |
| B2 | M | 300 (tepira) | B1b |
| B3 | M | 250 (tepira) | B1a, B1b |
| B4 | M | 250 (tepira) | B2, B3 |
| B5a | S | 120 (tepira) | B4 |
| B5b | M | 300 (tepira) | B4, B1b |
| B6 | S | 150 (generator) | B2–B5b |
| B7 | S | lokal, tidak di-commit | B5b |
| T12 | S | 30 | — |
| T13 | S | 150 | T12 |
| T14 | M | 250 | T13 |
| T15 | M | 350 | T14 |
| T16 | M | 350 | T15 |
| T17 | M | 300 | T14 |
| T18 | L | 450 | T15, T17 |
| T19 | M | 250 | T17 |
| T20 | M | 300 | T17 |
| T21 | M | 250 | T18, T20 |
| T22 | S | 150 | T15, T18, T20 |

Urutan eksekusi usulan:

T12 → T13 → B1a → B1b → B2 → T14 → T15 → T16 → B3 → B4 → T17 → T18 → T19 → B5a → B5b → B7 → B6 →
T20 → T21 → T22.

Backend disisipkan tepat sebelum tiket mobile yang membutuhkan endpoint nyata untuk uji manual.

## Risiko

- **Copy dan horizon `safeToday`** disetujui (Q1: ÷ 30 hari). Bila nanti horizon diganti, hanya
  konstanta, contoh F/G, dan copy kartu yang berubah.
- **Helper bersama diubah** (B1b): hapus jajan di web dan undo Cyrene sekarang menunggu kunci
  baris. Risikonya rendah karena ubah/hapus selesai dalam milidetik. Mitigasi: `test:cyrene` +
  uji balapan B7. Izin (Ask first) sudah diberikan 2026-11-01.
- **Kunci tidak terbukti oleh Prisma palsu**; buktinya hanya B7 (manual). Bila B7 tidak bisa
  dijalankan (mis. tanpa Docker), laporkan sebagai celah, jangan dianggap lulus.
- **Bulan WIB vs web jam server** (Q3): angka "Jajan bulan ini" di mobile bisa berbeda dari
  dashboard web untuk jajan 00:00–07:00 WIB tanggal 1. TZ kontainer produksi belum diverifikasi.
- **Batas anggaran**: mobile mengikuti `computeMonthSummary` (baris alokasi), sedangkan skor laporan
  web memakai `Salary.totalExpenseAllocation` (SPEC §11 asumsi 9).
- **Baris lama `userId = null`** ikut terlihat dan bisa diubah semua user (perilaku web
  dipertahankan).
- **Tanpa artboard** untuk Dana dicadangkan dan kartu harian (Q6): risiko ulang desain setelah
  pemilik melihat hasil.
- `docs/design/` menampilkan dompet di form Setor yang tidak didukung data (K8/Q4).

## Keputusan

Diputuskan koordinator atas wewenang yang didelegasikan pemilik, 2026-11-01. Nomor sama dengan
SPEC §14.

1. **Angka "Aman dipakai hari ini"**: tanpa anggaran bulan, Uang bebas ÷ **30 hari**; saat
   anggaran lewat, kartu menampilkan "Anggaran bulan ini sudah lewat Rp…"; copy kartu sekarang
   diterima.
2. **Jajan dari dompet dicadangkan** diizinkan, tidak pernah dompet default, dan ikut dihitung di
   anggaran bulan seperti web (K2).
3. **Bulan WIB untuk mobile.** Menyamakan web di luar scope (tindak lanjut).
4. **Tidak ada field dompet di form Setor** (K8); tidak ada migrasi.
5. **Hapus dompet ditunda ke v3** (K7).
6. **Dana dicadangkan** dibuat mengikuti gaya `Dompet`/`TambahDompet` tanpa artboard baru.

Izin perubahan helper bersama di B1b (kunci baris pada hapus jajan di web dan undo Cyrene)
**disetujui**. PR backend tetap dibuka hanya setelah diminta.
