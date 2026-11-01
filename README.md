# tepira-mobile

Aplikasi mobile (Android & iOS) untuk [tepira.id](https://tepira.asepsunarya.com):
nabung sedikit-sedikit ("teu pira") untuk mencapai goal finansial. Backend dan
web app ada di repo `tepira` (Next.js + Prisma); app ini hanya klien API.

## Mulai

Butuh Flutter stable 3.x. Folder `android/` dan `ios/` sudah di-commit
(applicationId / bundle ID `id.tepira.tepira_mobile` / `id.tepira.tepiraMobile`).

```bash
flutter pub get
flutter run
```

## APK dari CI

Workflow `.github/workflows/apk.yml` membangun APK release di setiap push ke
`main` (atau manual lewat *Run workflow*) dan mengunggahnya sebagai artifact
`tepira-apk-<sha>`. Konfigurasi repo:

| Nama | Jenis | Isi |
|---|---|---|
| `ANDROID_KEYSTORE_BASE64` | secret | `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | secret | password keystore |
| `ANDROID_KEY_ALIAS` | secret | alias key |
| `ANDROID_KEY_PASSWORD` | secret | password key |
| `TEPIRA_GOOGLE_SERVER_CLIENT_ID` | secret atau variable | lihat *Login Google* |
| `TEPIRA_GOOGLE_IOS_CLIENT_ID` | secret atau variable | lihat *Login Google* |

Tanpa secret keystore, APK ditandatangani dengan debug key (tetap bisa
di-install untuk test). Lokal, release signing dibaca dari
`android/key.properties` (`storeFile`, `storePassword`, `keyAlias`,
`keyPassword`) bila file itu ada; file ini dan `*.jks` di-ignore git.

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
