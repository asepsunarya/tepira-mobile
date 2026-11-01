# tepira-mobile

Aplikasi mobile (Android & iOS) untuk [tepira.id](https://tepira.asepsunarya.com):
nabung sedikit-sedikit ("teu pira") untuk mencapai goal finansial. Backend dan
web app ada di repo `tepira` (Next.js + Prisma); app ini hanya klien API.

## Mulai

Butuh Flutter stable 3.x. Platform folder (`android/`, `ios/`) belum ada di
repo ini, jadi setelah clone jalankan sekali:

```bash
flutter create . --org id.tepira --project-name tepira_mobile --platforms android,ios
flutter pub get
flutter run
```

`flutter create .` hanya menambah file yang belum ada; `lib/`, `test/`, dan
`pubspec.yaml` tidak ditimpa. Commit folder `android/` dan `ios/` yang dihasilkan
(kecuali file yang sudah ada di `.gitignore`).

## Perintah

| Tugas | Perintah |
|---|---|
| Analisis | `flutter analyze` |
| Test | `flutter test` |
| Format | `dart format lib test` |
| Build APK | `flutter build apk --release` |
| Ganti base URL API | `flutter run --dart-define=TEPIRA_API_BASE_URL=http://10.0.2.2:3000/api` |

## Login Google

Client ID Google tidak pernah ditulis di kode; isi lewat `--dart-define`:

| Define | Isi | Wajib |
|---|---|---|
| `TEPIRA_GOOGLE_SERVER_CLIENT_ID` | Client ID OAuth tipe *Web application* (yang sama dipakai web tepira). Google memakai ini sebagai audience `idToken`, yang diverifikasi backend. | Android dan iOS |
| `TEPIRA_GOOGLE_IOS_CLIENT_ID` | Client ID OAuth tipe *iOS* (bundle ID `id.tepira.tepiraMobile`). | iOS |

```bash
flutter run \
  --dart-define=TEPIRA_API_BASE_URL=http://10.0.2.2:3000/api \
  --dart-define=TEPIRA_GOOGLE_SERVER_CLIENT_ID=<web-client-id>.apps.googleusercontent.com \
  --dart-define=TEPIRA_GOOGLE_IOS_CLIENT_ID=<ios-client-id>.apps.googleusercontent.com
```

Di Google Cloud (project yang sama dengan web tepira):

- **Android**: buat client ID tipe *Android* dengan package name `id.tepira.tepira_mobile` dan SHA-1
  keystore (debug: `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android`;
  rilis: SHA-1 kunci upload atau Play App Signing). Client ini tidak dipakai di kode,
  Google mencocokkannya lewat package name + SHA-1.
- **iOS**: buat client ID tipe *iOS*, lalu tambahkan *reversed client ID* sebagai URL scheme
  di `ios/Runner/Info.plist` (`CFBundleURLSchemes`).
- **Backend**: `TEPIRA_MOBILE_GOOGLE_CLIENT_IDS` di repo `tepira` harus memuat client ID web
  (audience `idToken` saat `serverClientId` diisi); boleh ditambah client Android/iOS.

Tanpa `TEPIRA_GOOGLE_SERVER_CLIENT_ID`, Android tidak memberi `idToken` dan layar Masuk
menampilkan "Google tidak memberi token masuk".

## Claude Code

Repo ini memakai [claude-code-starter](https://github.com/asepsunarya/claude-starter):
aturan project ada di `CLAUDE.md`, skill/command/agent di `.claude/`. Alur
kerja fitur baru: `/spec` → `/plan` → `/build` → `/review` → `/ship`.
