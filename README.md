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

## Claude Code

Repo ini memakai [claude-code-starter](https://github.com/asepsunarya/claude-starter):
aturan project ada di `CLAUDE.md`, skill/command/agent di `.claude/`. Alur
kerja fitur baru: `/spec` → `/plan` → `/build` → `/review` → `/ship`.
