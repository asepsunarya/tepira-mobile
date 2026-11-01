# SPEC v2: Catat jajan, Dompet (termasuk Dana dicadangkan), dan "Aman dipakai hari ini" untuk tepira-mobile

Status: **disetujui 2026-11-01** (revisi 2). Keputusan produk §14 diambil koordinator atas
wewenang yang didelegasikan pemilik, 2026-11-01; perubahan helper bersama di §9 "Ask first"
(B1b) disetujui. §12 berisi keputusan teknis dan produk, §14 berisi keputusan pemilik.
Dasar: `handoff/mobile-v2-research.md` (riset 2026-11-01), SPEC v1 yang disetujui
(`tepira-mobile` `origin/main` `94c0caa`, `SPEC.md`; selisih dari `fc89b34` hanya CI dan konfigurasi
iOS), dan kode backend `asepsunarya/tepira` `main` commit `aa9a99d`. Nomor baris di spec ini
mengacu ke `aa9a99d`. `origin/main` sekarang `88d59ae` (#31, konfigurasi ESLint). Commit itu
menyentuh satu file yang dikutip, `app/dashboard/components/GoalHelper.tsx` (escape tanda kutip
di baris 175), dan mengubah skrip `lint` di `package.json` menjadi `eslint .`. Baris yang dikutip
di spec ini tidak berubah.

**Migrasi DB:** v2 tidak punya migrasi. Setiap migrasi yang disebut di dokumen ini (semuanya
kandidat v3) ditandai **"migrasi: butuh persetujuan pemilik"** dan tidak boleh dikerjakan tanpa
persetujuan itu.
Desain acuan: `docs/design/` (artboard `Main`, `TambahSetoran` tab Jajan, `Dompet`,
`TambahDompet`, `IkonMerek`, `Riwayat`, `SkeletonDaftar`). Tidak ada artboard untuk
Dana dicadangkan, Uang bebas, dan angka harian; ketiganya dibuat mengikuti gaya
`Dompet`/`TambahDompet` (§14 Q6).

## Capability Map

| Module id | Responsibility | Depends on |
|---|---|---|
| `backend-mobile-api-v2` | Endpoint JSON baru di repo `tepira`: daftar/buat/ubah dompet, ringkasan hari ini (termasuk aman dipakai hari ini), catat/daftar/ubah/hapus jajan | `backend-mobile-api` v1 (sudah di `main`) |
| `core-network` (perluasan) | Pemetaan 400 ke `BadRequestException` dengan `code`; helper tanggal WIB; konstanta kategori | v1 `core-network` |
| `wallets` | Model dompet + total, repository, layar Dompet, layar Tambah/Ubah dompet (termasuk toggle Dana dicadangkan) | `core-network`, `backend-mobile-api-v2` |
| `expenses` | Model jajan, repository, tab Jajan di layar Catat, layar Riwayat jajan dengan ubah/hapus | `wallets`, `core-network`, `backend-mobile-api-v2` |
| `today` | Ringkasan hari ini dan kartu "Aman dipakai hari ini" di Desa, diperbarui dari respons tulis jajan | `expenses`, `backend-mobile-api-v2` |

Build order: `backend-mobile-api-v2` (kontrak dulu, implementasi di repo `tepira`) →
`core-network` (perluasan) → `wallets` → `expenses` (catat) → `today` → `expenses` (riwayat,
ubah/hapus).

Alasan urutan: backend menolak jajan tanpa dompet (`tepira: lib/wallet-expenses.ts`
`resolveRequiredWallet`), dan akun baru belum punya dompet. Angka harian baru bermakna setelah
jajan bisa dicatat.

Di luar scope spec ini: lihat §13 (v3 dan seterusnya).

## 1. Objective

Pengguna yang mencatat jajan setiap hari bisa: membuka app, melihat **berapa yang masih aman
dipakai hari ini**, mencatat jajan dalam maksimal tiga ketukan (nominal, kategori opsional,
simpan dengan dompet terakhir), dan melihat saldo dompet langsung bergerak. Dompet yang
dicadangkan (mis. dana Kurban) tetap tampil sebagai aset tetapi tidak dihitung sebagai uang
yang bebas dipakai. Data sama persis dengan web tepira.id karena backend dan database sama.

Target pengguna v2 tetap pemilik akun tepira.id di allowlist (sama dengan v1).

## 2. Temuan tentang backend (fakta, bukan asumsi)

Dibaca dari `asepsunarya/tepira` `main` commit `aa9a99d` (2026-11-01). Endpoint v1
`/api/mobile/*` sudah ada di `main` (PR #29, `0012c7f`); dompet dicadangkan sudah digabung
(#25, `6420850`).

- **Tidak ada endpoint JSON bersesi untuk dompet, ringkasan, atau daftar jajan.** Satu-satunya
  route bersesi untuk jajan adalah `POST /api/expense` (multipart `amount, category, note,
  source, date, walletId`; respons `{success:true}` tanpa id). Kelemahannya: `amount` non-bulat
  dan dompet milik orang lain menjadi 500, `date` lewat `new Date()` mentah, tidak ada id untuk
  dimuat ulang. Route lain untuk data ini memakai kunci pemilik (`x-api-key` di `/api/expenses`,
  `/api/stats`; Bearer Cyrene di `/api/cyrene/*`) dan dilarang untuk app (SPEC v1 §9).
- **Server action tidak bisa dipakai dari Flutter** (butuh ID action per build dan respons RSC,
  serta redirect alih-alih 401): `app/wallets/actions.ts` (`getWallets`, `createWallet`,
  `updateWallet`, `deleteWallet`), `app/expenses/actions.ts` (`createExpense`, `deleteExpense`).
- **Model data** (`prisma/schema.prisma`):
  - `Wallet { id Int, name String, type String @default("bank"), balance Int, description String?,
    isDebt Boolean, isReserved Boolean, sortOrder Int, userId String? }`. `type` yang dikenal:
    `bank, e-wallet, cash, investment, credit, paylater, other`. Constraint DB: `isDebt` dan
    `isReserved` tidak boleh sama-sama `true` (migrasi `20261101060000_add_wallet_reserved`).
  - `Expense { id Int, amount Int, category String?, note String?, source String? @default("gaji"),
    date DateTime, createdAt, walletId Int? (onDelete: SetNull), placeName?, latitude?, longitude? }`.
- **Saldo dompet ikut bergerak di transaksi yang sama dengan jajan**
  (`lib/wallet-expenses.ts`): dompet aset berkurang, dompet utang bertambah, memakai increment
  atomik SQL (`:17-28`). Batas helper yang ada:
  - `createExpenseWithWallet` (`:53-91`) membuka transaksinya sendiri dan **tidak punya dedupe**.
    Dompet yang tidak ada atau milik orang lain menjadi `Error` generik dari
    `resolveRequiredWallet` (`:46-48`), jadi pemanggil tidak bisa membedakannya dari error lain.
  - `deleteExpenseAndRestoreWallet` (`:93-112`) membaca baris jajan **tanpa kunci baris**.
    Helper ini dipakai web (`app/expenses/actions.ts:41`).
  - **Ubah jajan belum ada di tepira.** Versi yang ada hanya di `tepira-village:
    lib/wallet-expenses.ts:116-163 updateExpenseWithWallet`. Fungsi itu mengunci baris dulu
    (`lockExpense`, `SELECT 1 FROM "Expense" WHERE id = … FOR UPDATE`, `:87-89`), lalu membalik
    gerak lama di dompet lama dan menerapkan gerak baru di dompet baru. Fungsi itu mewajibkan
    `amount` dan `walletId` dan menyimpan `category || null` / `note || null` (`:118-128,145-152`),
    jadi bila diport apa adanya, field yang tidak dikirim akan terhapus.
  - Pola tulis jajan yang aman dari balapan sudah ada di Cyrene
    (`app/api/cyrene/expenses/route.ts:68-121`). Pola itu tidak memakai `createExpenseWithWallet`.
    Dalam satu transaksi, route mengambil `pg_advisory_xact_lock` per user, mencari dompet milik
    user, mengecek duplikat, menyisipkan baris, lalu menggeser saldo dengan `updateMany` atomik
    plus cek `count`.
  - Undo Cyrene (`app/api/cyrene/expenses/[id]/route.ts:35-55`) juga membaca baris tanpa kunci.
    Bila undo berjalan bersamaan dengan ubah jajan dari mobile, saldo bisa dibalik dengan nominal
    lama (§3.8).
- **Revalidasi halaman web:** setiap tulis memanggil `revalidatePath`: v1 mobile
  (`app/api/mobile/goals/route.ts:62-63`), web dompet (`app/wallets/actions.ts:40-41,53-54,62-63`:
  `/wallets`, `/dashboard`), web jajan (`app/expenses/actions.ts:33-34,42-44`), dan Cyrene
  (`app/api/cyrene/expenses/route.ts:135-137`: `/expenses`, `/dashboard`, `/wallets`).
- **Total dompet** (`lib/wallet-totals.ts` `summarizeWallets`): `assets` = jumlah saldo non-utang
  (termasuk dicadangkan), `debts` = jumlah |saldo utang|, `reserved` = jumlah saldo dicadangkan,
  `netWorth = assets − debts`, `free` (Uang bebas) `= netWorth − reserved`. Saldo tampilan utang
  negatif (`walletDisplayBalance`). Bila kedua flag `true`, utang menang.
- **Validasi dompet web** (`app/wallets/actions.ts:9 parseWalletForm`): nama wajib (di-trim),
  `type` di luar daftar jadi `other`, `credit`/`paylater` ⇒ `isDebt`, utang + dicadangkan ditolak
  ("Dompet tidak bisa sekaligus hutang dan dana dicadangkan."). Urutan daftar:
  `sortOrder asc, createdAt asc`.
- **Kategori** (`lib/categories.ts`): 9 kategori tetap dengan `key` dan `label`. Web menyimpan
  `key`, Cyrene menyimpan `label`; `null`/`""`/`"Uncategorized"`/`"Tanpa kategori"` = tanpa
  kategori (`lib/cyrene/core.ts:36 isUncategorized`, `:44 categoryLabelOf`).

  | key | label | group |
  |---|---|---|
  | `makan_harian` | Makan harian | Kebutuhan wajib |
  | `transport` | Transport | Kebutuhan wajib |
  | `pulsa_internet` | Pulsa & Internet | Kebutuhan wajib |
  | `listrik_kos` | Listrik / Air / Kos | Kebutuhan wajib |
  | `langganan` | Langganan (Spotify, Netflix, dll) | Kewajiban & rutin |
  | `kesehatan` | Kesehatan / Obat | Kewajiban & rutin |
  | `sosial` | Sosial (sedekah / bantu keluarga) | Kewajiban & rutin |
  | `nongkrong` | Nongkrong / jajan | Hiburan & fleksibel |
  | `belanja_kecil` | Belanja kecil | Hiburan & fleksibel |

- **Anggaran bulan** (`lib/cyrene/core.ts:342-431 computeMonthSummary`): batas = jumlah
  **baris alokasi kategori** gaji (`salary.allocations`) + baris alokasi bonus selain
  `"Tabungan"` (`:368-378`). Isinya diambil seperti `app/api/cyrene/summary/route.ts:84-88`.
  Fungsi ini **tidak** membaca `Salary.totalExpenseAllocation`. Batas itu dibandingkan dengan
  **semua** jajan bulan itu. Status (`:415`): `NO_BUDGET` bila total alokasi ≤ 0, `OVER_BUDGET`
  bila total jajan > batas, selain itu `WITHIN_BUDGET`. Skor laporan web memakai
  `Salary.totalExpenseAllocation` + alokasi bonus (`lib/report-scoring.ts:53-57`). Bila kolom itu
  tidak sama dengan jumlah baris alokasi, angka web bisa berbeda (§11 asumsi 9).
- **Validator jajan Cyrene hanya sebagian bisa dipakai ulang.** `parseExpenseBody`
  (`lib/cyrene/core.ts:471`) **tidak** cocok untuk mobile: fungsi itu menolak key yang tidak
  dikenal (`:474-476`), membaca `wallet` (id atau nama), bukan `walletId`, membatasi `amount`
  1..5.000.000 (`MAX_EXPENSE_AMOUNT`, `:455`), dan saat gagal hanya mengembalikan `{ field }`
  (`Parsed`, `:113`), bukan pesan. Yang bisa dipakai ulang: `parseExpenseDate` (`:564`; `date`
  `YYYY-MM-DD` dari 7 hari WIB ke belakang sampai besok, hari ini = `null` = "sekarang", hari
  lain = 12:00 WIB) dan aturan teks (`isWellFormedText` `:239`, `clampText` `:246`,
  `MAX_NOTE_LENGTH` 120, kategori harus label, `source` `gaji|bonus`). `expenseDedupeWhere`
  (`:548`, dedupe 120 detik) hanya membaca `amount`, `category`, `note`, `source`, `date` dari
  inputnya dan `walletId` dari argumen, jadi bisa dipanggil dengan hasil parse mobile.
- **Zona waktu belum konsisten.** Batas bulan web memakai waktu lokal server
  (`webMonthRange` = `new Date(y, m-1, 1)`; `Dockerfile` tidak menyetel `TZ`, jadi kemungkinan
  UTC, belum diverifikasi di produksi). Hari di API Cyrene dan di tepira-village memakai WIB
  (`wibDayRange`, `wibDate`).
- **"Aman dipakai hari ini" belum ada di mana pun.** Web tepira, tepira-village, dan artboard tidak
  punya logika angka aman harian. Pencarian `daysLeft|perDay|dailyBudget|safeToSpend|aman dipakai`
  di `app/`, `lib/`, dan `components/` hanya menemukan kode yang mirip:
  - rata-rata jajan per hari di laporan (`app/reports/page.tsx:59-65`, total bulan ÷ jumlah hari
    bulan);
  - laju setoran goal (`app/dashboard/components/GoalHelper.tsx:34-35`, sisa ÷ `max(1, sisa hari)`,
    dibulatkan ke atas);
  - laju goal di village (`tepira-village: lib/game.ts:389-396`).

  Karena itu tidak ada logika web yang bisa diikuti persis. Rumus §3.4 dibuat konsisten dengan
  logika anggaran yang **ada**, yaitu batas dan status `computeMonthSummary` (§12 K1).
- Baris lama `userId = null` terlihat oleh semua user (`lib/auth.ts:48 userOwnedWhere`); semua
  query baru wajib memakainya. Allowlist dicek ulang setiap JWT dibaca (`auth.config.ts`), jadi
  token mobile mati saat email keluar dari allowlist.
- Helper respons v1 tersedia di `lib/mobile/http.ts` (`json`, `apiError`, `unauthorized`,
  `notFound`, `serverError`, `sessionUserId`, `logFailure`).
- **Pola uji backend:** `npm run test:mobile`, `test:wallets`, dan `test:cyrene` menjalankan
  `node --test` biasa. Node menghapus tipe TypeScript secara native; tidak ada loader dan tidak
  ada build. Akibatnya modul yang diuji tidak boleh mengimpor alias `@/…` dan hanya boleh memakai
  TypeScript yang bisa dihapus (pola `lib/mobile/goals.ts`: helper dioper sebagai parameter).
  `lib/wallet-expenses.ts` mengimpor `@prisma/client` dan `@/lib/prisma` (`:1-2`), jadi tidak bisa
  dimuat oleh `node --test` biasa. Handler route sudah pernah dijalankan di luar Next oleh
  generator kontrak `handoff/fixtures-gen/`. Generator itu memakai hook `--import` yang memetakan
  `@/` ke repo dan mengganti `@/lib/prisma`, `@/lib/auth`, `next/cache` dengan stub.

Kesimpulan: v2 butuh 8 endpoint baru di `/api/mobile/*`, **tanpa perubahan skema dan tanpa
migrasi**. Ada dua perubahan kecil di helper bersama yang juga dipakai web dan Cyrene (kunci
baris di hapus jajan dan di undo Cyrene; §3.8, §9 "Ask first").

## 3. Kontrak `backend-mobile-api-v2` (dikerjakan di repo `tepira`)

Status kontrak: **usulan**. Seperti v1, setelah handler selesai `api-contract.md` dibangkitkan
ulang dari handler asli dengan jam tetap `2026-11-01T07:00:00.000Z` dan data fiktif
(`handoff/fixtures-gen/`), lalu SPEC ini disesuaikan dengan backend, bukan sebaliknya.
Fixture baru: `test/fixtures/mobile_wallets.json` (3.1), `mobile_today_budget.json` dan
`mobile_today_wallet.json` (3.4), `mobile_expense_created.json` (3.5),
`mobile_expenses.json` (3.6).

Aturan umum: **sama dengan SPEC v1 §3** (host, header `Cache-Control: no-store…`, amplop
`{ok:true,…}` / `{ok:false,error,message}`, camelCase, uang `int` rupiah, timestamp ISO-8601 UTC
dengan milidetik, tanggal kalender `YYYY-MM-DD` WIB, field nullable tidak pernah hilang, auth =
cookie sesi Auth.js lewat `sessionUserId()`). Tambahan v2:

- **Bulan dan hari = WIB** (UTC+7, tanpa DST) untuk semua endpoint v2 (§12 K3, §14 Q3).
  `period` = `{ "year": 2026, "month": 11 }`.
- **Query param bulan:** `year` (2020..2100) dan `month` (1..12), keduanya atau tidak sama
  sekali; default bulan WIB berjalan. Nilai salah → `400 bad_request` "Bulan atau tahun tidak
  valid.".
- **Body JSON:** `Content-Type: application/json` (`charset` boleh), body harus objek, key tak
  dikenal diabaikan (sama dengan v1 `POST /api/mobile/goals`).
- **Id path** (`{id}`) bukan int32 positif → `404 not_found` (sama dengan v1 §3.3).
- **Kategori di respons selalu `label`** (key lama dipetakan dengan `categoryLabelOf`); semua
  varian tanpa kategori → `null`. Kategori di request harus `label` (§12 K5).
- Kode error baru: `wallet_not_found` 400 (dompet di body tidak ada atau bukan milik user).
  Kode lain sama dengan v1: `bad_request` 400, `unauthorized` 401, `not_found` 404,
  `unsupported_media_type` 415, `server_error` 500.
- Setiap endpoint tulis jajan mengembalikan dompet yang terdampak dan `today` (bentuk 3.4) supaya
  klien memperbarui Desa dan Dompet tanpa memuat ulang semuanya. `today` dihitung **setelah**
  transaksi commit, dengan query terpisah.
- **Semantik PATCH (3.3 dan 3.7):** field yang **tidak ada** di body = tidak diubah. Field yang
  berisi `null` = dikosongkan, **hanya** untuk field yang nullable (`description`, `category`,
  `note`). `null` di field lain → `400 bad_request` dengan pesan validasi field itu. Validasi
  dijalankan atas hasil gabungan baris tersimpan + body, kecuali yang disebut lain di tabel
  (aturan utang negatif 3.2 hanya dicek bila `balance` dikirim). Aturan per field ada di tabel 3.3 dan
  3.7. Server hanya menulis kolom yang dikirim, tidak menulis ulang seluruh baris.
- **Revalidasi web:** setelah tulis yang benar-benar mengubah data, route memanggil
  `revalidatePath` dengan daftar yang sama seperti web, supaya halaman web langsung segar.
  Dompet: `/wallets`, `/dashboard` (`app/wallets/actions.ts:40-41`). Jajan (buat/ubah/hapus):
  `/expenses`, `/dashboard`, `/wallets` (`app/expenses/actions.ts:42-44`). Respons dedupe tidak
  merevalidasi (sama dengan Cyrene `route.ts:127-137`).

### 3.1 `GET /api/mobile/wallets`

- Auth: cookie sesi. Urutan: `sortOrder asc, createdAt asc` (sama dengan `getWallets`).
  Pengelompokan dilakukan klien dari flag.
- Respons 200 (fixture `mobile_wallets.json`, contoh dipotong):

```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "period": { "year": 2026, "month": 11 },
  "wallets": [
    {
      "id": 3,
      "name": "BCA",
      "type": "bank",
      "balance": 8250000,
      "displayBalance": 8250000,
      "isDebt": false,
      "isReserved": false,
      "description": null,
      "sortOrder": 0,
      "spentThisMonth": 385000
    },
    {
      "id": 7,
      "name": "Tabungan Kurban",
      "type": "bank",
      "balance": 3000000,
      "displayBalance": 3000000,
      "isDebt": false,
      "isReserved": true,
      "description": "Kurban 2027",
      "sortOrder": 1,
      "spentThisMonth": 0
    },
    {
      "id": 9,
      "name": "Kartu Kredit",
      "type": "credit",
      "balance": 1200000,
      "displayBalance": -1200000,
      "isDebt": true,
      "isReserved": false,
      "description": null,
      "sortOrder": 2,
      "spentThisMonth": 150000
    }
  ],
  "totals": {
    "assets": 11250000,
    "debts": 1200000,
    "reserved": 3000000,
    "netWorth": 10050000,
    "free": 7050000
  }
}
```

- `balance` = nilai mentah di DB (untuk utang bisa positif atau negatif, tergantung cara web
  menyimpannya); `displayBalance` = `walletDisplayBalance` (utang selalu negatif). Klien menampilkan
  `displayBalance`. `totals` = `summarizeWallets` atas semua dompet user. `spentThisMonth` =
  jumlah jajan dompet itu di bulan WIB berjalan (artboard `Dompet`: "jajan bulan ini").
- Error: `401` `unauthorized`; `500` `server_error`.

### 3.2 `POST /api/mobile/wallets`

- Auth: cookie sesi. Body:
  - `name` string 1–60 karakter (di-trim, tanpa karakter kontrol) **wajib**.
  - `type` salah satu `bank, e-wallet, cash, investment, credit, paylater, other` **wajib**
    (tidak ada fallback diam-diam ke `other`, beda dengan web).
  - `balance` integer −2147483648..2147483647, opsional, default `0`. Untuk dompet utang =
    jumlah terutang, harus ≥0 (artboard `TambahDompet`: "Terutang saat ini").
  - `isDebt` boolean opsional, default `false`; dipaksa `true` bila `type` `credit`/`paylater`.
  - `isReserved` boolean opsional, default `false`.
  - `description` string ≤200 karakter opsional (`""`/`null` → `null`).
  - `sortOrder` tidak diterima; server mengisi `max(sortOrder)+1` milik user.
- Respons **201** `{ "ok": true, "wallet": { …bentuk 3.1… }, "totals": { … } }`
  (`spentThisMonth` = 0).
- Error:
  - `401` `unauthorized`; `415` `unsupported_media_type` "Format permintaan harus JSON."
  - `400` `bad_request` dengan salah satu pesan: "Nama dompet harus diisi, maksimal 60 karakter.",
    "Jenis dompet tidak dikenal.", "Saldo harus berupa angka bulat.", "Jumlah terutang tidak
    boleh negatif.", "Dompet tidak bisa sekaligus utang dan dana dicadangkan.", "Deskripsi
    maksimal 200 karakter.", "Isi permintaan harus berupa objek JSON."
  - `500` `server_error`

### 3.3 `PATCH /api/mobile/wallets/{id}`

- Auth: cookie sesi. Body parsial (semantik PATCH §3). Aturan validasi 3.2 diterapkan pada
  hasil gabungan, **kecuali** "Jumlah terutang tidak boleh negatif.": aturan itu hanya dicek
  bila `balance` ada di body. Web mengizinkan saldo utang negatif (input saldo di
  `app/wallets/components/WalletForm.tsx:107-117` tanpa `min`; `app/wallets/actions.ts:20` hanya
  cek `Number.isFinite`), jadi dompet utang lama bisa tersimpan negatif. Tanpa pengecualian ini,
  ganti nama dompet seperti itu akan ditolak.

  | Field | Tidak dikirim | `null` | Nilai |
  |---|---|---|---|
  | `name` | tetap | 400 "Nama dompet harus diisi, maksimal 60 karakter." | aturan 3.2 |
  | `type` | tetap | 400 "Jenis dompet tidak dikenal." | aturan 3.2; tidak boleh pindah kelompok utang↔aset |
  | `balance` | tetap, **tidak ditulis**; aturan utang negatif tidak dicek | 400 "Saldo harus berupa angka bulat." | koreksi saldo manual; dompet utang: nilai < 0 → 400 "Jumlah terutang tidak boleh negatif." |
  | `isDebt` | tetap | 400 "Jenis utang tidak bisa diubah setelah dompet dibuat." | harus sama dengan nilai tersimpan |
  | `isReserved` | tetap | 400 "Dana dicadangkan harus ya atau tidak." | `true` pada dompet utang → 400 |
  | `description` | tetap | dikosongkan | `""` → dikosongkan; ≤200 karakter |

- **Asumsi: saldo dompet utang tersimpan ≥ 0** (§11 asumsi 11). `applyExpenseToWalletBalance`
  (`lib/wallet-expenses.ts:20-23`) menambah saldo mentah utang (`increment`), sedangkan
  `summarizeWallets` (`lib/wallet-totals.ts:30,38-39`) memakai `|balance|`. Dompet utang yang
  tersimpan negatif bergerak ke arah yang salah: jajan membuat utang tampak berkurang. Pada
  basis `wallet` §3.4, penambahan kembali `E_today'`/`E_next'` untuk dompet seperti itu juga
  terhitung dua kali. Ini bug backend yang sudah ada (bukan dari v2); v2 tidak memperbaikinya.
  Tiket B3 memeriksa data nyata dulu dan melaporkan hasilnya sebelum implementasi.
- Mengubah `balance` = koreksi saldo manual (sama dengan web), tidak membuat baris jajan.
  `balance` **hanya** ditulis bila ada di body. Kalau server menulis ulang saldo yang dibaca
  sebelumnya, increment atomik dari jajan yang berjalan bersamaan akan tertimpa.
- Perpindahan antara jenis utang dan aset (`isDebt` berubah, termasuk lewat `type`) ditolak
  (§11 asumsi 4).
- Respons 200 `{ "ok": true, "wallet": { … }, "totals": { … } }`.
- Error: semua error 3.2, ditambah `400` `bad_request` "Tidak ada perubahan." (body tanpa field
  yang dikenal), `400` `bad_request` "Jenis utang tidak bisa diubah setelah dompet dibuat.",
  `404` `not_found` (tidak ada, bukan milik user, atau id tidak valid).
- **Hapus dompet tidak ada di v2** (§13, §14 Q5).

### 3.4 `GET /api/mobile/today`

Ringkasan untuk Desa. Semua hari dan bulan WIB; dihitung saat permintaan.

- Auth: cookie sesi. Tanpa query param.
- Respons 200, basis anggaran (fixture `mobile_today_budget.json`, contoh A di bawah):

```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "date": "2026-11-01",
  "period": { "year": 2026, "month": 11, "daysInMonth": 30, "daysLeft": 30 },
  "spent": { "today": 35000, "month": 35000 },
  "savedThisMonth": 500000,
  "budget": {
    "status": "WITHIN_BUDGET",
    "limit": 4500000,
    "spent": 35000,
    "remaining": 4465000
  },
  "safeToday": {
    "basis": "budget",
    "state": "ok",
    "days": 30,
    "allowance": 150000,
    "spentToday": 35000,
    "remaining": 115000
  },
  "wallets": { "free": 7050000, "reserved": 3000000 }
}
```

- Respons 200 tanpa anggaran bulan ini (fixture `mobile_today_wallet.json`, contoh F):
  `budget` = `{ "status": "NO_BUDGET", "limit": null, "spent": 35000, "remaining": null }`,
  `safeToday` = `{ "basis": "wallet", "state": "ok", "days": 30, "allowance": 236166,
  "spentToday": 35000, "remaining": 201166 }`.

#### Rumus (keputusan teknis K1; horizon 30 hari dan copy disetujui, §14 Q1)

Logika murni di `lib/mobile/today.ts` `computeSafeToday(...)`, tanpa import. Notasi (semua WIB):

- `m0` = awal bulan berjalan, `t0` = awal hari ini, `t1` = awal besok (`wibDayRange(now)`).
- `D` = `period.daysLeft` = jumlah hari dari hari ini sampai akhir bulan, **termasuk** hari ini
  (1..31).
- `B` = `budget.limit` = total alokasi dari `computeMonthSummary` (§2).
- Jajan dikelompokkan menurut **`date`** (bukan `createdAt`):
  - `S_before` = jumlah semua jajan dengan `date` di `[m0, t0)`;
  - `E_today` = jumlah semua jajan dengan `date` di `[t0, t1)`;
  - `E_month` = jumlah semua jajan bulan ini, termasuk yang bertanggal besok (= `budget.spent`).
  - Jajan bertanggal besok (`date ≥ t1`, boleh menurut `parseExpenseDate`, `lib/cyrene/core.ts:564-581`)
    **tidak** masuk `S_before` maupun `E_today`.
- `spent.today = E_today`, `spent.month = E_month`. Keduanya menghitung semua jajan, sama dengan web
  dan Cyrene.
- **Rentang baca jajan di route.** Route membaca jajan dengan `date` di
  `[m0, max(m1, t2))`, dengan `m1` = awal bulan WIB berikutnya dan `t2` = awal lusa WIB
  (`wibDayRange(now, 2).start`). Pada hari terakhir bulan, `t1 = m1`, sehingga jajan bertanggal
  besok jatuh di bulan berikutnya. Saldo dompet sudah dipotong oleh jajan itu, jadi jajan itu tetap
  harus dibaca dan dikelompokkan sebagai "besok" (`E_next'`). `bucketExpenses` sudah menangani
  baris seperti ini: baris di luar `[m0, m1)` tidak masuk `E_month` maupun `S_before`, dan baris
  `≥ t1` hanya masuk `E_next'`. `computeMonthSummary` tidak menyaring tanggal, jadi route hanya
  mengopernya baris dengan `date` di `[m0, m1)`.

**Basis `budget`** (status bukan `NO_BUDGET`). Semua jajan dihitung, termasuk dari dompet
dicadangkan, supaya angka harian selalu sejalan dengan status anggaran bulan:

```
bila status == OVER_BUDGET:
    allowance = 0
    remaining = B − E_month            (negatif)
    state     = "over_month"
selain itu (WITHIN_BUDGET):
    allowance = max(0, floor((B − S_before) / D))
    remaining = min(allowance − E_today, B − E_month)
    state     = remaining < 0 ? "over_today" : "ok"
spentToday = E_today;  days = D
```

**Basis `wallet`** (`NO_BUDGET`). Uang bebas dibagi horizon tetap, bukan sisa hari bulan:

```
H        = SAFE_TODAY_HORIZON_DAYS = 30
E_today' = jajan [t0, t1) yang dibayar dari dompet yang masih ada dan TIDAK dicadangkan
           (dompet utang dihitung; dompet utang + dicadangkan dianggap utang)
E_next'  = jajan bertanggal ≥ t1 dengan aturan dompet yang sama
F0       = wallets.free + E_today' + E_next'     (perkiraan Uang bebas di awal hari ini)
allowance = max(0, floor(F0 / H))
remaining = allowance − E_today'
state     = remaining < 0 ? "over_today" : "ok"
spentToday = E_today';  days = H
```

Alasan tiap bagian:

- **Tidak ada lonjakan di hari terakhir.** Pada basis `budget`, `allowance` dibatasi oleh sisa
  anggaran `B − S_before`, jadi pada `D = 1` nilainya hanya sisa anggaran bulan itu. Pada basis
  `wallet`, pembaginya tetap `H = 30`, bukan `D`, sehingga tanggal 30 menghasilkan angka yang sama
  dengan tanggal 1 untuk saldo yang sama (contoh F dan G).
- **Jajan bertanggal besok tidak memotong hari ini.** Basis `budget` hanya memakai `S_before` dan
  `E_today`. Basis `wallet` menambahkan `E_next'` kembali, karena saldo dompet sudah bergerak saat
  jajan bertanggal besok dibuat (contoh B).
- **Kartu tidak bisa bilang aman saat anggaran lewat.** `OVER_BUDGET` (status yang sama dengan
  `computeMonthSummary`) selalu menghasilkan `state = "over_month"` dan `remaining < 0`. Pada
  `WITHIN_BUDGET`, `remaining` dibatasi `B − E_month`, jadi angka aman hari ini tidak pernah
  melebihi sisa anggaran bulan (contoh E). Satu konsekuensi disengaja: jajan bertanggal besok
  yang membuat bulan lewat anggaran membuat kartu hari ini sudah `over_month`, supaya kartu dan
  status anggaran tidak berbeda.
- **Dompet dicadangkan.** Jajan dari dompet dicadangkan mengurangi `reserved` dan aset dengan
  jumlah yang sama, jadi `free` tidak berubah. Karena itu basis `wallet` tidak menghitungnya. Basis
  `budget` menghitungnya karena anggaran bulan (`computeMonthSummary`) juga menghitungnya
  (contoh H; keputusan produk §14 Q2).
- **Pembulatan ke bawah** (`floor`, rupiah penuh). Untuk batas belanja, pembulatan ke bawah lebih
  aman daripada `ceil` yang dipakai laju setoran goal (`GoalHelper.tsx:35`).
- **`allowance` tidak dijamin tetap sepanjang hari.** Nilainya berubah bila ada jajan bertanggal
  sebelum hari ini yang dibuat, diubah, atau dihapus (mengubah `S_before`), bila alokasi gaji/bonus
  diubah di web, dan, pada basis `wallet`, bila saldo dompet berubah di luar jajan hari ini/besok
  (koreksi saldo, dompet baru, jajan mundur tanggal). Jajan hari ini dan besok **tidak** mengubah
  `allowance`.

#### Contoh hitungan (November 2026, 30 hari, `B` = 4.500.000 kecuali disebut lain)

| # | Situasi | Input | Hasil |
|---|---|---|---|
| A | 1 Nov, `D` = 30 | `S_before` 0, `E_today` 35.000, `E_month` 35.000 | `allowance` = ⌊4.500.000/30⌋ = 150.000; `remaining` = min(115.000; 4.465.000) = **115.000**, `ok` |
| B | 16 Nov, `D` = 15, ada jajan 200.000 bertanggal 17 Nov | `S_before` 2.400.000, `E_today` 60.000, `E_month` 2.660.000 | `allowance` = ⌊2.100.000/15⌋ = 140.000; `remaining` = min(80.000; 1.840.000) = **80.000**, `ok`. Rumus draf lama (`E_month − E_today` dianggap "sebelum hari ini") memberi 126.666 / 66.666. |
| C | 30 Nov, `D` = 1 | `S_before` 4.380.000, `E_today` 50.000, `E_month` 4.430.000 | `allowance` = 120.000; `remaining` = min(70.000; 70.000) = **70.000**, `ok` |
| D | 10 Nov, `D` = 21, lewat jatah hari ini | `S_before` 1.350.000, `E_today` 170.000, `E_month` 1.520.000 | `allowance` = ⌊3.150.000/21⌋ = 150.000; `remaining` = **−20.000**, `over_today` |
| E | 28 Nov, `D` = 3, lewat anggaran bulan | `S_before` 4.620.000 (300.000 di antaranya dari Tabungan Kurban), `E_today` 0, `E_month` 4.620.000 → `OVER_BUDGET` | `allowance` 0; `remaining` = **−120.000**, `over_month`. Draf lama mengecualikan dompet dicadangkan, jadi memberi ⌊180.000/3⌋ = 60.000 "aman" walaupun status `OVER_BUDGET`. |
| F | `NO_BUDGET`, 1 Nov | `free` 7.050.000 setelah jajan 35.000 dari BCA hari ini | `F0` = 7.085.000; `allowance` = ⌊7.085.000/30⌋ = 236.166; `remaining` = **201.166**, `ok` |
| G | `NO_BUDGET`, 30 Nov, saldo sama dengan F | sama dengan F | **sama dengan F** (236.166 / 201.166). Draf lama (`÷ D`, `D` = 1) memberi 7.085.000. |
| H | `NO_BUDGET`, seperti F ditambah 500.000 dari Tabungan Kurban hari ini | `free` tetap 7.050.000; `E_today'` tetap 35.000 | `safeToday` sama dengan F; `spent.today` = 535.000 |

- `savedThisMonth` = jumlah `Contribution.amount` di bulan WIB berjalan (tile "Ditabung bulan
  ini" di artboard `Main`). `Contribution` tidak punya `userId` (`prisma/schema.prisma:86-94`),
  jadi kepemilikan disaring lewat goal: `contribution.aggregate({ _sum: { amount: true }, where:
  { goal: userOwnedWhere(userId), date: { gte: m0, lt: awal bulan depan } } })`. Angka ini
  **hanya setoran**. Angka "ditabung" di laporan web juga menambahkan `salary.savingsAllocation`
  (`lib/report-scoring.ts:51`). Mobile tidak menambahkannya
  karena tile menunjukkan uang yang benar-benar disetor (§11 asumsi 10).
- Error: `401` `unauthorized`; `500` `server_error`.

### 3.5 `POST /api/mobile/expenses`

- Auth: cookie sesi. Body:
  - `amount` integer 1..100.000.000 **wajib** (angka JSON; §11 asumsi 3).
  - `walletId` integer int32 positif **wajib**.
  - `category` label dari tabel §2 atau `null`, opsional.
  - `note` string ≤120 karakter (aturan `parseExpenseBody`), opsional (`""`/`null` → `null`).
  - `source` `"gaji"` | `"bonus"`, opsional, default `"gaji"`.
  - `date` `"YYYY-MM-DD"` opsional, aturan `parseExpenseDate`: 7 hari WIB ke belakang sampai
    besok; hari ini atau kosong = waktu server sekarang; hari lain = 12:00 WIB hari itu.
- **Tidak** memakai `createExpenseWithWallet`, karena helper itu membuka transaksinya sendiri,
  tidak punya dedupe, dan melempar `Error` generik untuk dompet asing (§2). Route mengikuti pola
  Cyrene (`app/api/cyrene/expenses/route.ts:68-121`). Kunci, cek, dan sisip berada dalam **satu**
  `prisma.$transaction` (`maxWait 5_000`, `timeout 10_000`, seperti `:124`):
  1. `SELECT 1 AS locked FROM pg_advisory_xact_lock(hashtext(${'tepira-mobile-expense:' + userId}))`.
     Ini kunci per user dengan prefiks sendiri (Cyrene memakai `tepira-cyrene-expense:`) yang
     dilepas otomatis saat commit/rollback. Karena prefiksnya berbeda, jajan identik yang dikirim
     bersamaan dari mobile dan Cyrene tidak saling menunggu dan tidak di-dedupe; keduanya
     tercatat. Ini diterima: dua kanal berbeda hampir pasti berarti dua niat berbeda.
  2. Cari dompet: `tx.wallet.findFirst({ where: { id: walletId, ...userOwnedWhere(userId) } })`.
     Tidak ada → kembalikan `{kind:"wallet_not_found"}` → `400 wallet_not_found`.
  3. **Dedupe:** `tx.expense.findFirst({ where: { ...owned, ...expenseDedupeWhere(input, wallet.id,
     now) }, orderBy: [{ createdAt: "desc" }, { id: "desc" }] })`. Ada → kembalikan baris itu
     (`deduped: true`, 200, tanpa tulis, tanpa revalidasi). Aturannya sama dengan Cyrene: nominal,
     dompet, kategori, catatan, sumber, dan tanggal identik, dibuat dalam 120 detik
     (`lib/cyrene/core.ts:541-559`).
  4. `createExpenseInTx(tx, userId, wallet, data)`, ekspor **baru** di `lib/wallet-expenses.ts`:
     `expense.create` lalu `wallet.updateMany({ where: { id, ...owned }, data: { balance:
     applyExpenseToWalletBalance(wallet.isDebt, amount) } })` dengan cek `count === 1`. Cek gagal
     → throw → rollback → 500. `createExpenseWithWallet` yang dipakai web **tidak diubah**.
  
  Ini aman dari tekan ganda karena permintaan kedua menunggu kunci advisory. Setelah kunci
  dilepas, `findFirst` di langkah 3 adalah statement baru (READ COMMITTED), jadi baris dari
  permintaan pertama yang sudah commit terlihat dan permintaan kedua menjadi dedupe.
- Respons **201** (baris baru) atau **200** (dedupe) (fixture `mobile_expense_created.json`):

```json
{
  "ok": true,
  "deduped": false,
  "expense": {
    "id": 501,
    "amount": 25000,
    "category": "Makan harian",
    "note": "nasi padang",
    "source": "gaji",
    "date": "2026-11-01T07:00:00.000Z",
    "createdAt": "2026-11-01T07:00:00.000Z",
    "walletId": 3,
    "walletName": "BCA",
    "placeName": null
  },
  "wallet": { "…": "bentuk 3.1, saldo setelah jajan" },
  "today": { "…": "bentuk 3.4 tanpa ok/asOf" }
}
```

- Bentuk `expense` dipakai juga di 3.6–3.8. `walletId`/`walletName` `null` bila dompet sudah
  dihapus di web (baris yatim). `placeName` selalu dikirim; v2 tidak menulisnya.
- Boleh membayar dari dompet dicadangkan (backend mengizinkan; §14 Q2). Jajan itu masuk `spent`,
  `budget.spent`, dan `safeToday` basis `budget`, tetapi tidak mengubah `free`, jadi tidak
  mengurangi `safeToday` basis `wallet` (§3.4 contoh H).
- Setelah commit, route memanggil revalidasi web (§3), hanya bila baris baru dibuat.
- Error:
  - `401` `unauthorized`; `415` `unsupported_media_type`
  - `400` `bad_request` dengan salah satu pesan: "Nominal harus berupa angka bulat antara 1 dan
    100.000.000.", "Dompet wajib dipilih.", "Kategori tidak dikenal.", "Catatan maksimal 120
    karakter.", "Sumber dana harus gaji atau bonus.", "Tanggal harus berformat YYYY-MM-DD,
    paling lama 7 hari ke belakang atau besok.", "Isi permintaan harus berupa objek JSON."
  - `400` `wallet_not_found` "Dompet tidak ditemukan. Pilih dompet lain."
  - `500` `server_error`

### 3.6 `GET /api/mobile/expenses?year=&month=`

- Auth: cookie sesi. Bulan WIB (default berjalan). Urutan `date desc, id desc`. Maksimal 500
  baris; `more: true` bila ada lebih (§11 asumsi 6).
- Respons 200 (fixture `mobile_expenses.json`):

```json
{
  "ok": true,
  "asOf": "2026-11-01T07:00:00.000Z",
  "period": { "year": 2026, "month": 11 },
  "total": 410000,
  "count": 6,
  "more": false,
  "expenses": [
    {
      "id": 501,
      "amount": 25000,
      "category": "Makan harian",
      "note": "nasi padang",
      "source": "gaji",
      "date": "2026-11-01T07:00:00.000Z",
      "createdAt": "2026-11-01T07:00:00.000Z",
      "walletId": 3,
      "walletName": "BCA",
      "placeName": null
    }
  ]
}
```

- `total` dan `count` menghitung semua jajan bulan itu, bukan hanya 500 yang dikirim.
- Error: `400` `bad_request` "Bulan atau tahun tidak valid."; `401`; `500`.

### 3.7 `PATCH /api/mobile/expenses/{id}`

- Auth: cookie sesi. Body parsial (semantik PATCH §3), per field:

  | Field | Tidak dikirim | `null` | Nilai |
  |---|---|---|---|
  | `amount` | tetap | 400 "Nominal harus berupa angka bulat antara 1 dan 100.000.000." | aturan 3.5 |
  | `walletId` | tetap (baris yatim: 400 "Dompet wajib dipilih.") | 400 "Dompet wajib dipilih." | dompet milik user, selain itu 400 `wallet_not_found` |
  | `category` | tetap | dikosongkan | label §2; `""` → dikosongkan |
  | `note` | tetap | dikosongkan | aturan 3.5; `""` → dikosongkan |
  | `source` | tetap | 400 "Sumber dana harus gaji atau bonus." | `gaji` / `bonus` |
  | `date` | tetap, **tanpa** cek batas 7 hari | 400 pesan tanggal 3.5 | `parseExpenseDate`; hari ini: bila hari WIB tersimpan juga hari ini, `date` tersimpan (jamnya) **tetap**; bila beda hari, = waktu server saat PATCH; hari lain = 12:00 WIB |

  Body tanpa satu pun field yang dikenal → `400 bad_request` "Tidak ada perubahan.". Field yang
  dikirim dengan nilai yang sama dengan nilai tersimpan tetap sah (200). Jajan lama di luar batas
  7 hari tetap bisa diubah nominal, kategori, atau catatannya selama `date` tidak dikirim.
- Penggabungan: `mergeExpensePatch(row, patch)` (murni, `lib/mobile/expenses.ts`) mengembalikan
  nilai akhir atau error. Fungsi ini menggantikan `x || null` versi village, sehingga field yang
  tidak dikirim tidak pernah terhapus.
- Transaksi (port `updateExpenseWithWallet` ke `tepira: lib/wallet-expenses.ts`, dengan hasil
  bertipe, bukan `throw Error` generik):
  1. `lockExpense(tx, id)`: `SELECT 1 FROM "Expense" WHERE id = ${id} FOR UPDATE` (model `Expense`
     tanpa `@@map`).
  2. Baca baris (`id` + `userOwnedWhere`, dengan dompet). Tidak ada → `{kind:"not_found"}` → 404.
  3. Fungsi merge yang dioper pemanggil (B5b mengoper `mergeExpensePatch`). Patch yang digabung
     dengan baris tersimpan gagal validasi → `{kind:"invalid", message}` → 400 `bad_request`
     dengan `message` itu. Baris yatim tanpa `walletId` → `{kind:"wallet_required"}` → 400.
  4. Bila `walletId` berubah: cari dompet baru milik user; tidak ada → `{kind:"wallet_not_found"}`
     → 400, transaksi dibatalkan.
  5. `planExpenseUpdate(old, next)` (murni, `lib/wallet-moves.ts`) menghasilkan daftar gerak saldo
     `{walletId, delta}`: membalik efek lama di dompet lama (bila masih ada) dan menerapkan efek baru
     di dompet baru. Gerak di dompet yang sama digabung, delta 0 dibuang, dan daftar **diurutkan
     menurut `walletId`**. Dua ubah jajan yang saling bertukar dompet (A→B dan B→A) mengunci baris
     dompet dalam urutan yang sama, jadi tidak saling deadlock.
  6. `expense.update` dengan kolom yang berubah, lalu tiap gerak sebagai
     `wallet.updateMany({ where: { id, ...owned }, data: { balance: { increment: delta } } })`
     dengan cek `count === 1` (pola Cyrene `route.ts:116-120`). Cek gagal → throw → rollback → 500.
  
  Perilaku yang diketahui: mengubah jajan yang dompetnya bukan milik user (data tidak konsisten)
  membuat gerak balik di dompet lama gagal cek `count === 1`, sehingga transaksi dibatalkan dan
  respons 500. Tidak ada saldo yang berubah.
- Respons 200 `{ "ok": true, "expense": { … }, "wallets": [ …1 atau 2 dompet terdampak… ],
  "today": { … } }`. Revalidasi web (§3).
- Error: semua error 3.5, ditambah `400` `bad_request` "Tidak ada perubahan.", `404`
  `not_found`.

### 3.8 `DELETE /api/mobile/expenses/{id}`

- Auth: cookie sesi. Lewat `deleteExpenseAndRestoreWallet` yang **diubah** untuk memanggil
  `lockExpense(tx, id)` sebelum membaca baris. Tanpa kunci ini, hapus yang berjalan bersamaan
  dengan ubah jajan membaca nominal dan dompet lama, lalu membalik nominal lama di dompet lama,
  dan saldo jadi salah. Dengan kunci, hapus menunggu ubah selesai, lalu membaca baris terbaru
  (READ COMMITTED). Urutan kunci sama dengan ubah (jajan dulu, lalu dompet).
- **Perubahan helper bersama (perlu izin, §9 "Ask first"):**
  - `deleteExpenseAndRestoreWallet` juga dipakai web (`app/expenses/actions.ts:41`), jadi hapus di
    web ikut terkunci. Perilaku lain web tidak berubah.
  - Undo Cyrene (`app/api/cyrene/expenses/[id]/route.ts:35-55`) ditambah `lockExpense` sebelum
    `findFirst`. Undo yang bersamaan dengan ubah jajan dari mobile akan membalik nominal lama,
    karena `deleteMany` tetap berhasil setelah menunggu kunci baris ubah.
  - Tidak ada perubahan skema dan tidak ada migrasi; kunci memakai SQL mentah di dalam transaksi.
- Tidak ada batas waktu (beda dengan Cyrene yang 15 menit; web juga tanpa batas).
- Respons 200 `{ "ok": true, "deleted": { "id": 501, "amount": 25000 }, "wallet": { … } | null,
  "today": { … } }` (`wallet` `null` untuk baris yatim). Revalidasi web (§3).
- Error: `401`; `404` `not_found`; `500`.

### 3.9 Kategori

Tidak ada endpoint. Klien memakai konstanta 9 label di `lib/core/categories.dart` (tabel §2).
Backend menambah fixture `test/fixtures/categories.json` dari `lib/categories.ts` supaya test
klien gagal bila daftar berubah.

### 3.10 Yang tidak dipakai

`POST /api/expense` (lama) tidak dipakai mobile dan tidak diubah. `/api/cyrene/*`,
`/api/expenses`, `/api/stats` tetap terlarang (SPEC v1 §9).

## 4. Acceptance criteria

### `backend-mobile-api-v2` (repo `tepira`)
- [ ] Logika murni di `lib/mobile/wallets.ts`, `lib/mobile/expenses.ts` (termasuk
  `mergeExpensePatch`), `lib/mobile/today.ts` (`computeSafeToday`, rentang WIB), dan
  `lib/wallet-moves.ts` (`expenseBalanceDelta`, `planExpenseUpdate`). Semuanya tanpa import dan
  hanya memakai TypeScript yang bisa dihapus tipenya, seperti `lib/mobile/goals.ts`; helper dari
  `lib/cyrene/core.ts` dioper sebagai parameter. Route tipis di
  `app/api/mobile/{wallets,today,expenses}/**/route.ts`.
- [ ] Semua query memakai `userOwnedWhere(userId)`. Semua gerak saldo jajan lewat
  `lib/wallet-expenses.ts` (`createExpenseInTx`, `updateExpenseWithWallet`,
  `deleteExpenseAndRestoreWallet`); tidak ada update `Wallet.balance` manual di route.
- [ ] **Buat jajan:** kunci advisory, cari dompet, dedupe, dan sisip dalam satu transaksi (§3.5).
  Test handler memastikan urutan panggilan: `pg_advisory_xact_lock` → `wallet.findFirst` →
  `expense.findFirst` (dedupe) → `expense.create` → `wallet.updateMany`, semuanya di dalam callback
  `$transaction` yang sama. Dompet asing menghasilkan 400 `wallet_not_found`, bukan 500.
- [ ] **Ubah/hapus jajan:** `lockExpense` (`FOR UPDATE`) adalah query pertama di transaksi
  `updateExpenseWithWallet`, `deleteExpenseAndRestoreWallet`, dan undo Cyrene. Gerak saldo diurutkan
  menurut `walletId`.
- [ ] **PATCH:** test "hanya `amount` dikirim" membuktikan `category`, `note`, `source`, `date`,
  dan `walletId` tetap; `null` mengosongkan `category`/`note`; `null` di `amount`/`walletId`/
  `source`/`date` → 400; PATCH dompet tanpa `balance` tidak menulis kolom `balance`.
- [ ] `planExpenseUpdate` dengan test: dompet sama (satu gerak selisih), pindah dompet aset→utang,
  baris yatim, dompet dicadangkan, delta 0 dibuang, urutan `walletId`.
- [ ] `computeSafeToday` dengan test untuk **semua contoh A–H §3.4** (angka persis), ditambah
  batas hari 23:59/00:00 WIB dan bulan 31 hari.
- [ ] Bulan WIB: jajan 2026-10-31T17:30:00Z (= 1 Nov 00:30 WIB) masuk November.
- [ ] Revalidasi web (§3) dipanggil setelah tulis yang berhasil, tidak dipanggil untuk dedupe dan
  error (dicek lewat stub `next/cache`).
- [ ] Tidak ada token, header, atau body di log (pola `logFailure`).
- [ ] `api-contract.md` dan fixture dibangkitkan ulang dari handler asli; SPEC §3 disesuaikan.
- [ ] Tidak ada migrasi Prisma. Migrasi apa pun **butuh persetujuan pemilik**.
- [ ] Uji balapan manual di Postgres lokal sekali pakai lulus (§8) dan hasilnya ditempel di
  deskripsi PR.

### `core-network` (perluasan)
- [ ] `400` dengan amplop `{ok:false}` → `BadRequestException(code, message)` (subclass
  `AppException`); pesan server tampil apa adanya. `wallet_not_found` bisa dibedakan dari
  `bad_request`.
- [ ] `lib/core/wib.dart`: `wibDate(DateTime utc)`, `wibDayKey`, awal/akhir bulan WIB dengan offset
  tetap +7 jam, **tidak** memakai zona waktu perangkat. Unit test termasuk pergantian hari
  dan bulan.
- [ ] `lib/core/categories.dart`: 9 label + group; test membandingkan dengan
  `test/fixtures/categories.json`.

### `wallets`
- [ ] `Wallet` model: `id, name, type, balance, displayBalance, isDebt, isReserved, description,
  sortOrder, spentThisMonth`; `WalletTotals`: `assets, debts, reserved, netWorth, free`. Semua
  uang `int`. `WalletKind` turunan: `debt` bila `isDebt`, `reserved` bila `isReserved && !isDebt`,
  selain itu `normal`.
- [ ] `WalletsRepository`: `list()`, `create(...)`, `update(id, ...)`. Screen tidak memanggil dio.
- [ ] Layar Dompet (`/wallets`, artboard `Dompet`): kepala dengan Total saldo (`assets`), Uang
  bebas (`free`), Dana dicadangkan (`reserved`) dan utang (`debts`); tiga kelompok mengikuti web:
  "Saldo & Tabungan", "Dana Dicadangkan", "Kartu Kredit & Cicilan" (kelompok kosong disembunyikan);
  tiap baris: logo merek (`lib/core/brands.dart`), nama, `displayBalance` (utang merah),
  "jajan bulan ini". Skeleton, kosong ("Buat dompet pertamamu"), error + coba lagi, tarik untuk
  muat ulang.
- [ ] Layar Tambah dompet (`/wallets/new`) dan Ubah dompet (`/wallets/:id/edit`), artboard
  `TambahDompet`: nama (pilihan merek mengisi nama), jenis, "Saldo awal" atau "Terutang saat
  ini" sesuai jenis, deskripsi, toggle **"Dana dicadangkan"** dengan penjelasan singkat
  ("Uang yang disisihkan untuk tujuan tertentu. Tetap dihitung sebagai aset, tidak dihitung
  sebagai uang bebas."). Toggle nonaktif untuk jenis `credit`/`paylater` dan dompet utang. Di
  layar Ubah, jenis hanya bisa diganti dalam kelompok yang sama (aset↔aset). Validasi klien sama
  dengan §3.2.
- [ ] Sukses simpan → kembali ke Dompet; daftar dan total diperbarui dari respons.
- [ ] Widget test: Dompet (loading, kosong, tiga kelompok, utang negatif merah), Tambah dompet
  (nama kosong, toggle dicadangkan nonaktif untuk kartu kredit, sukses memanggil repository sekali).

### `expenses` (catat)
- [ ] `Expense` model dan `ExpensesRepository`: `create`, `list(year, month)`, `update`, `delete`.
  Respons tulis memperbarui `walletsProvider` dan `todayProvider` dari `wallet(s)` dan `today`
  di respons, tanpa GET ulang.
- [ ] Tab **Jajan** di layar Catat (`/record?tab=jajan`, artboard `TambahSetoran`) diaktifkan:
  chip cepat 10/15/25/50 ribu, keypad (`amount_keypad.dart` dipakai ulang), chip kategori
  (opsional), pemilih dompet, tanggal (Hari ini / Kemarin / pilih sampai 7 hari ke belakang),
  catatan opsional; sumber dana `gaji` default, `bonus` di bagian "Lainnya".
- [ ] Pemilih dompet default = dompet terakhir dipakai yang **bukan** dicadangkan (id disimpan di
  `flutter_secure_storage`, kunci `lastExpenseWalletId`); dompet dicadangkan tampil di bagian
  terpisah dengan label "Dicadangkan"; dompet utang dengan label "terutang" dan petunjuk "Jajan
  menambah utang".
- [ ] Alur tercepat: buka Catat → chip nominal → Simpan = jajan tersimpan (3 ketukan).
- [ ] Tanpa dompet: form diganti ajakan "Buat dompet dulu" ke `/wallets/new`.
- [ ] Penjaga tekan ganda: tombol Simpan nonaktif selama request berjalan (pola
  `new_goal_screen_dup_guard`); respons `deduped: true` diperlakukan sebagai sukses biasa.
- [ ] Sukses → snackbar "Jajan Rp25.000 tercatat", kembali ke layar sebelumnya. Nominal 0 ditolak
  di klien. `wallet_not_found` → muat ulang daftar dompet + pesan server.
- [ ] Widget test: nominal 0 ditolak, default dompet bukan dicadangkan, tanpa dompet, sukses
  memanggil `create(amount: 25000, walletId: 3, ...)` sekali walau diketuk dua kali.

### `today`
- [ ] `TodaySummary` model dari §3.4 (`safeToday.state` sebagai enum `ok`/`overToday`/`overMonth`,
  `days`); `todayProvider` (`AsyncNotifier`) dimuat bersama Desa,
  dimuat ulang saat tarik-muat-ulang, saat app kembali ke depan, dan saat tanggal WIB berganti.
- [ ] Kartu "Aman dipakai hari ini" di Desa (di atas daftar kavling, `StatTile`). Tampilan
  ditentukan oleh `safeToday.state`; klien tidak menghitung ulang angka (copy disetujui, §14 Q1):
  - `ok`: angka besar `safeToday.remaining` dalam `formatRupiah`. Keterangan basis `budget`:
    "Jatah Rp150.000/hari dari anggaran bulan ini". Keterangan basis `wallet`: "Dari uang bebas
    dibagi 30 hari (anggaran bulan ini belum diatur di web)". `remaining == 0` → "Jatah hari ini
    sudah habis".
  - `over_today`: "Lewat Rp20.000 hari ini", warna `merah`.
  - `over_month`: judul kartu menjadi "Anggaran bulan ini sudah lewat", angka
    `Rp120.000` (nilai mutlak `remaining`), warna `merah`. Kata "aman" tidak tampil.
  - Nilai `state` yang tidak dikenal dianggap error kartu (pesan + coba lagi), bukan `ok`.
- [ ] Dua tile kecil di bawahnya mengikuti artboard `Main`: "Jajan bulan ini" (`spent.month`) dan
  "Ditabung bulan ini" (`savedThisMonth`).
- [ ] Error `todayProvider` tidak menyembunyikan daftar kavling (kartu menampilkan pesan + coba
  lagi sendiri).
- [ ] Widget test: basis anggaran, basis dompet, `remaining == 0`, `over_today`, `over_month`
  (kata "aman" tidak ada), `state` tak dikenal, error terpisah dari daftar kavling.

### `expenses` (riwayat, ubah, hapus)
- [ ] Layar Riwayat (`/history`, artboard `Riwayat`, skeleton `SkeletonDaftar`): header bulan
  (WIB) dengan total, tombol bulan sebelum/sesudah, daftar dikelompokkan per hari WIB; baris:
  kategori, catatan, nama dompet (atau "Dompet dihapus"), nominal. Filter Semua/Setoran/Jajan
  **tidak** tampil di v2 (hanya jajan, §12 K6). `more: true` → catatan "Menampilkan 500 terbaru".
- [ ] Ketuk baris → bottom sheet Ubah/Hapus. Ubah membuka form Jajan terisi (`/record?expense=:id`);
  Hapus dengan dialog konfirmasi. Sukses → daftar, dompet, dan `today` diperbarui dari respons.
- [ ] Widget test: kelompok per hari pada batas tengah malam WIB, hapus dengan konfirmasi,
  ubah memanggil `update` hanya dengan field yang berubah, dan kategori/catatan yang dikosongkan
  dikirim sebagai `null` (§3.7).

### Navigasi
- [ ] Dock bawah: Desa, Riwayat, Catat (tengah), Dompet; tab lain dari artboard `Main` tetap tidak
  tampil. Rute baru di `lib/core/routes.dart` dengan id path divalidasi seperti `GoalRoutes.parseId`.

### Lintas modul
- [ ] `flutter analyze` bersih, `flutter test` hijau, `dart format` rapi.
- [ ] Tidak ada dependensi baru (§10).
- [ ] Copy Indonesia, kode dan komentar Inggris; warna hanya dari `theme.dart`.

## 5. Commands

| Task | Command |
|---|---|
| Install | `flutter pub get` |
| Run | `flutter run --dart-define=TEPIRA_API_BASE_URL=http://10.0.2.2:3000/api` |
| Test | `flutter test` |
| Lint | `flutter analyze` |
| Format | `dart format lib test` |
| Backend lokal | di repo `tepira`: `npm run dev` |
| Backend test | di repo `tepira`: `npm run test:mobile && npm run test:wallets && npm run test:cyrene && npm run test:mobile-api` |
| Backend lint | di repo `tepira`: `npm run lint` |
| Kontrak | `handoff/fixtures-gen`: `TEPIRA_REPO=~/projects/tepira node --import ./register.mjs run.mjs` |

## 6. Project structure (tambahan pada struktur v1)

```
lib/
  core/
    brands.dart           peta nama dompet → aset/warna (direncanakan v1, dibuat di v2)
    categories.dart       9 label kategori + group
    wib.dart              tanggal/bulan WIB dengan offset tetap
    errors.dart           + BadRequestException(code)
    routes.dart           + WalletRoutes, ExpenseRoutes, kHistoryPath
  data/
    wallets/              wallets_repository.dart, wallet_dto.dart
    expenses/             expenses_repository.dart, expense_dto.dart
    today/                today_repository.dart, today_dto.dart
  features/
    wallets/              wallets_screen.dart (Dompet), wallet_form_screen.dart,
                          wallet_providers.dart, model/, widgets/ (wallet_row.dart, wallet_totals_header.dart)
    expenses/             expense_form.dart (tab Jajan), history_screen.dart (Riwayat),
                          expense_providers.dart, model/, widgets/ (expense_row.dart, expense_action_sheet.dart)
    today/                today_providers.dart, widgets/safe_today_card.dart
    goals/                contribute_screen.dart: tab Jajan diaktifkan, menampung expense_form
    shell/                app_dock.dart
test/                     mirror lib/; fixtures baru di test/fixtures/
```

Di repo `tepira`:

```
lib/mobile/wallets.ts      parse body + merge PATCH dompet, mapper, totals (murni)
lib/mobile/expenses.ts     parse body jajan, mergeExpensePatch, mapper (murni)
lib/mobile/today.ts        computeSafeToday, rentang hari/bulan WIB (murni)
lib/mobile/*.test.mjs      node --test biasa (npm run test:mobile)
lib/wallet-moves.ts        expenseBalanceDelta, planExpenseUpdate (murni, baru)
lib/wallet-moves.test.mjs  node --test biasa (npm run test:wallets)
lib/wallet-expenses.ts     + lockExpense, createExpenseInTx, updateExpenseWithWallet;
                           deleteExpenseAndRestoreWallet memanggil lockExpense (Ask first);
                           `import type { Prisma }` (tanpa perubahan runtime)
app/api/cyrene/expenses/[id]/route.ts   + lockExpense sebelum findFirst (Ask first)
app/api/mobile/wallets/route.ts, wallets/[id]/route.ts
app/api/mobile/today/route.ts
app/api/mobile/expenses/route.ts, expenses/[id]/route.ts
test/harness/              register.mjs, hooks.mjs (alias @/ → repo), fake-prisma.mjs,
                           stub-auth.mjs, stub-cache.mjs; diport dari handoff/fixtures-gen/
test/mobile-api/*.test.mjs test handler (npm run test:mobile-api)
```

## 7. Code style

Sama dengan SPEC v1 §7. Tambahan:
- Tanggal dan pengelompokan hari selalu lewat `lib/core/wib.dart`; jangan pakai
  `DateTime.toLocal()` untuk logika bisnis.
- Angka turunan (total dompet, `safeToday`, sisa anggaran) diambil dari server, tidak dihitung
  ulang di klien, supaya web, Cyrene, dan mobile tidak berbeda.
- Provider yang diperbarui dari respons tulis memakai satu fungsi `applyWriteResult(...)` per
  modul, bukan salinan logika di tiap layar.

## 8. Testing strategy

- **Backend, unit murni** (`node --test` biasa, tanpa loader, tanpa build). Semua logika yang
  perlu diuji dipindah ke modul tanpa import: `lib/mobile/{wallets,expenses,today}.ts` dan
  `lib/wallet-moves.ts`. Test baru didaftarkan di skrip yang sudah ada: `test:mobile`
  (`lib/mobile/wallets.test.mjs`, `expenses.test.mjs`, `today.test.mjs`) dan `test:wallets`
  (`lib/wallet-moves.test.mjs`). Yang diuji: validator body, `mergeExpensePatch` dan merge
  dompet, `computeSafeToday` (contoh A–H), rentang WIB, dan `planExpenseUpdate`.
- **Backend, handler** (skrip baru `test:mobile-api`):
  `node --disable-warning=MODULE_TYPELESS_PACKAGE_JSON --import ./test/harness/register.mjs --test
  test/mobile-api/wallets.test.mjs test/mobile-api/today.test.mjs test/mobile-api/expenses.test.mjs`.
  - Harness diport dari `handoff/fixtures-gen/` (`hooks.mjs` memetakan `@/` ke root repo).
    Stub: `@/lib/auth` (user tetap + `userOwnedWhere` asli), `next/cache` (mencatat panggilan
    `revalidatePath`), dan `@/lib/prisma` (Prisma palsu in-memory: `$transaction(fn)` menjalankan
    `fn` dengan klien yang sama, `$queryRaw` mencatat teks SQL, dan setiap panggilan model dicatat
    berurutan).
  - `lib/wallet-expenses.ts` diubah ke `import type { Prisma }` supaya harness tidak butuh Prisma
    client hasil generate.
  - Jam ditetapkan `2026-11-01T07:00:00.000Z` (seperti generator).
  - Yang diuji: status, header, dan bentuk JSON; urutan panggilan di transaksi (§4); hasil
    bertipe `wallet_not_found` / `not_found` / `wallet_required`; revalidasi; 404 milik orang
    lain; 415.
- **Balapan (manual, tidak di CI).** Prisma palsu tidak bisa membuktikan kunci. Builder
  menjalankan skrip lokal (tidak di-commit) ke Postgres 16 sekali pakai, misalnya
  `docker run --rm -e POSTGRES_PASSWORD=… -p 55432:5432 postgres:16` + `prisma migrate deploy`. PGlite
  tidak dipakai karena satu koneksi tidak bisa menunjukkan tunggu-kunci. Skenario:
  - 2 POST identik paralel → 1 baris, saldo bergerak sekali;
  - PATCH `amount` + DELETE paralel pada baris yang sama ×50 → saldo akhir = saldo awal;
  - PATCH E1 (A→B) dan E2 (B→A) paralel ×50 → tidak ada deadlock, saldo konsisten;
  - undo Cyrene + PATCH paralel → saldo konsisten.
  
  Output ditempel di deskripsi PR. **Tidak pernah ke DB produksi.**
- Kontrak dibangkitkan dari handler asli (generator `handoff/fixtures-gen/`, Prisma palsunya
  diperluas atau memakai `test/harness/fake-prisma.mjs`).
- Unit (mobile): DTO parsing dari fixture baru, `wib.dart`, `BadRequestException`, kategori vs
  fixture, `WalletKind`.
- Widget: tiap layar dengan repository palsu lewat `ProviderScope(overrides:)`, `clockProvider`
  di-override untuk tes batas hari.
- Golden: `WalletRow` (normal, dicadangkan, utang) dan `SafeTodayCard` (positif, negatif).
- Integrasi manual: `flutter run` ke emulator Android dengan backend lokal; skenario: buat dompet
  biasa + dicadangkan + kartu kredit, catat jajan dari masing-masing, cek saldo dan
  "Aman dipakai hari ini" sama dengan hitungan manual, ubah lalu hapus jajan, cek saldo kembali.
  Dilakukan oleh OpenClaw di mesin pemilik.
- Prove-It untuk setiap bug: test gagal dulu, baru fix.

## 9. Boundaries

**Always**
- Semua aturan v1 §9 tetap berlaku (token hanya di header `Cookie` ke host base URL, baca
  `docs/design/` dulu, `flutter analyze` + `flutter test` sebelum commit).
- Pakai `lib/wallet-expenses.ts` untuk setiap gerak saldo jajan di backend; kunci, cek, dan
  tulis dalam satu transaksi.
- Panggil `revalidatePath` setelah setiap tulis mobile yang berhasil (§3).
- Pakai WIB untuk hari dan bulan di endpoint v2 dan di klien.

**Ask first**
- Perubahan apa pun di repo `tepira` (PR terpisah, dibuka hanya setelah diminta).
- Perubahan kontrak §3 setelah disetujui.
- **Migrasi DB / perubahan skema Prisma: butuh persetujuan pemilik**, tanpa pengecualian. v2
  tidak punya migrasi. Kandidat v3 (`Contribution.walletId`, kolom arsip dompet) masing-masing
  butuh persetujuan pemilik tersendiri.
- Mengubah perilaku web (mis. batas bulan web ke WIB, rumus anggaran web).
- **Perubahan helper bersama yang dipakai web/Cyrene** (sudah direncanakan di B1/B5b; izin
  diminta sekali untuk PR backend):
  - `deleteExpenseAndRestoreWallet` + `lockExpense` (hapus di web ikut terkunci);
  - undo Cyrene `app/api/cyrene/expenses/[id]/route.ts` + `lockExpense`;
  - ekspor baru `createExpenseInTx`, `updateExpenseWithWallet`, `lockExpense`, dan modul
    `lib/wallet-moves.ts`;
  - `import type { Prisma }`.
  
  Tidak ada perubahan perilaku web selain kunci baris.
- Menambah artboard atau mengubah `docs/design/`.

**Never**
- Memakai `/api/cyrene/*`, `/api/expenses`, `/api/stats`, atau `POST /api/expense` lama dari app.
- Mengubah `Wallet.balance` di luar fungsi `lib/wallet-expenses.ts` saat menulis jajan.
- Menghitung `safeToday` atau total dompet di klien sebagai sumber kebenaran.
- Menghapus dompet dari mobile (tidak ada di v2).

## 10. Dependensi

Tidak ada dependensi baru. `flutter_secure_storage` (sudah ada) dipakai juga untuk
`lastExpenseWalletId`; tidak menambah `shared_preferences`. Backend tidak menambah paket.

## 11. Asumsi yang perlu dikoreksi kalau salah

1. Backend boleh ditambah 8 endpoint `/api/mobile/*` di repo `tepira` tanpa menyentuh route lama
   (`POST /api/expense` tetap ada untuk web lama). Perubahan helper bersama terbatas pada daftar
   §9 "Ask first".
2. Bulan dan hari WIB untuk mobile walaupun dashboard web mungkin memakai bulan waktu server
   (`webMonthRange`, kemungkinan UTC). Selisihnya hanya untuk jajan 00:00–07:00 WIB tanggal 1
   (§14 Q3).
3. Batas nominal jajan 1..100.000.000. Batas ini lebih longgar dari Cyrene (5.000.000) karena
   mobile juga dipakai untuk bayar kos/listrik, dan tetap jauh di bawah batas `Int`.
4. Dompet tidak boleh pindah antara utang dan aset setelah dibuat (web mengizinkan), supaya saldo
   historis tidak berubah arti. Kalau perlu, pengguna membuat dompet baru.
5. Kategori disimpan sebagai `label` (seperti Cyrene); baris lama dengan `key` tetap terbaca.
6. 500 jajan per bulan cukup untuk satu orang; tanpa paginasi kursor di v2.
7. Brand picker di `TambahDompet` hanya mengisi nama; `type` tetap dipilih pengguna.
8. Anggaran bulan tetap diatur di web; mobile v2 hanya membacanya lewat §3.4.
9. Batas anggaran = jumlah baris alokasi (`computeMonthSummary`, sama dengan Cyrene). Skor laporan
   web memakai `Salary.totalExpenseAllocation`. Diasumsikan keduanya sama untuk data yang diisi
   lewat web; bila tidak, angka mobile mengikuti Cyrene.
10. "Ditabung bulan ini" = setoran saja, tanpa `salary.savingsAllocation` (beda dengan laporan web).
11. Saldo dompet utang tersimpan ≥ 0. Web mengizinkan nilai negatif, dan untuk dompet seperti itu
    jajan menggerakkan saldo ke arah yang salah (bug backend yang sudah ada, §3.3). B3 memeriksa
    data nyata sebelum implementasi.

## 12. Keputusan

**Teknis (diputuskan koordinator; berubah hanya bila ada keberatan):**

- K1. **Rumus aman dipakai hari ini** = §3.4: basis `budget` (laju sisa anggaran berdasarkan
  jajan sebelum hari ini, dibatasi sisa anggaran bulan, `over_month` saat `OVER_BUDGET`) dengan
  fallback basis `wallet` (Uang bebas di awal hari ÷ 30). Dihitung di server; `basis`, `state`,
  dan `days` dikirim agar UI bisa menjelaskan. Kategori tetap (kos, langganan) tidak dikecualikan
  di v2. Horizon 30 hari dan copy kartu disetujui (§14 Q1).
- K3. **WIB** untuk bulan dan hari di semua endpoint v2 (disetujui di §14 Q3).
- K4. **Endpoint baru** `POST /api/mobile/expenses` dengan amplop v1, bukan `POST /api/expense`.
- K5. **Kategori disimpan sebagai label**, dibaca dua bentuk; daftar 9 kategori sebagai konstanta
  klien dengan fixture penjaga.
- K9. **Buat jajan mengikuti pola Cyrene**: kunci advisory per user, dompet, dedupe, dan sisip
  dalam satu transaksi, lewat `createExpenseInTx` baru. `createExpenseWithWallet` tidak diubah.
- K10. **Kunci baris jajan** (`lockExpense`, `FOR UPDATE`) di ubah, hapus, dan undo Cyrene; gerak
  saldo diurutkan menurut `walletId`.
- K11. **Semantik PATCH**: tidak dikirim = tetap, `null` = kosongkan (hanya field nullable);
  penggabungan oleh fungsi murni; server hanya menulis kolom yang dikirim.
- K12. **Revalidasi web** setelah setiap tulis mobile, dengan daftar path yang sama seperti web.
- K13. **Uji backend**: logika murni di modul tanpa import (`node --test` biasa); handler lewat
  harness `test/harness/` (`--import`); balapan diuji manual di Postgres sekali pakai.

**Produk (disetujui 2026-11-01, §14):**

- K2. **Jajan dari dompet dicadangkan** diizinkan tetapi tidak menjadi default pemilih. Jajan itu
  dihitung di anggaran bulan dan di basis `budget` (sama dengan `computeMonthSummary`); di basis
  `wallet` tidak mengurangi angka karena Uang bebas tidak berubah (§14 Q2).
- K6. **Riwayat v2 hanya jajan.** Baris setoran, ubah/hapus setoran, dan filter
  Semua/Setoran/Jajan masuk v3.
- K7. **Hapus dompet tidak ada di v2** (risiko baris yatim, `onDelete: SetNull`; §14 Q5).
- K8. **"Dompet" di form Setor tidak ditampilkan**, karena `Contribution` tidak punya `walletId`
  (artboard menampilkannya, data tidak bisa menyimpannya; §14 Q4).

## 13. Di luar scope / v3

Urut berdasarkan nilai menurut riset:

1. **Gaji / alokasi anggaran di mobile** (`GET/PUT /api/mobile/salary`, artboard `Gaji`). Sampai
   ada, anggaran diatur di web; tanpa anggaran `safeToday` memakai basis dompet.
2. **Laporan** (`GET /api/mobile/report`, artboard `Laporan`, `AliranUang`).
3. **Setoran di Riwayat**: ubah/hapus setoran (`PATCH/DELETE /api/mobile/contributions/{id}`),
   filter Semua/Setoran/Jajan, dan pengganti JSON untuk `POST /api/contribution`.
4. **Hapus atau arsip dompet**. Arsip butuh kolom baru: **migrasi, butuh persetujuan pemilik**.
5. **Dompet di setoran** (`Contribution.walletId`): **migrasi, butuh persetujuan pemilik**.
6. **Ubah/hapus goal** (`UbahGoal`, `ArsipGoal`).
7. Tempat jajan, batas warung, peta jajan (`Warung`, `PetaJajan`, `PilihTempat`, `IzinLokasi`).
8. Kotak pos / tagihan rutin, jurnal / streak / hari tanpa jajan, level/XP, perayaan. Logikanya
   hanya ada di tepira-village dan perlu diport ke tepira (pertanyaan 9 di riset); kemungkinan butuh
   tabel baru: **migrasi, butuh persetujuan pemilik**.
9. Pindah dana antar dompet (`PindahDana`), suara (`Suara`), widget, notifikasi push, offline
   queue, PIN.
10. Menyamakan tepira-village dengan dompet dicadangkan (di luar repo mobile; dicatat untuk
    pemilik).

## 14. Keputusan pemilik (keputusan produk)

Diputuskan koordinator atas wewenang yang didelegasikan pemilik, **2026-11-01**. Pertanyaan
teknis sudah diputuskan di §12. Daftar yang sama ada di akhir `tasks/plan-v2.md`.

- Q1. **Angka "Aman dipakai hari ini"** (§3.4):
  - Bila anggaran bulan belum diatur: **Uang bebas ÷ 30 hari** (`SAFE_TODAY_HORIZON_DAYS = 30`).
  - Saat anggaran bulan sudah lewat: kartu berganti ke **"Anggaran bulan ini sudah lewat Rp…"**
    (`over_month`).
  - Copy kartu yang ada sekarang (§4 `today`) **diterima**.
- Q2. **Jajan dari dompet dicadangkan: diizinkan**, tetapi tidak pernah menjadi dompet default
  pemilih, dan ikut dihitung di anggaran bulan seperti di web (K2).
- Q3. **Mobile memakai bulan WIB.** Menyamakan web ke WIB di luar scope v2 (tindak lanjut
  terpisah).
- Q4. **Tidak ada field dompet di form Setor** (K8). Tidak ada migrasi
  (`Contribution.walletId` tidak direncanakan di v2).
- Q5. **Hapus dompet ditunda ke v3** (K7).
- Q6. **UI Dana dicadangkan dibuat langsung** mengikuti gaya `Dompet`/`TambahDompet` (kelompok
  baru, toggle, Uang bebas di kepala), tanpa artboard baru.

**Izin:** perubahan helper bersama di §9 "Ask first" (B1b: kunci baris pada hapus jajan di web
dan undo Cyrene, ekspor helper baru) **disetujui**. PR backend tetap dibuka hanya setelah diminta.
