# Project: tepira-mobile

Rules file for AI coding agents working in this repository. It is loaded into
every session, so keep it short and current. Long workflows live in
`.claude/skills/`; shared checklists live in `.claude/references/`.
If `.claude/skills/` does not exist in this repository, the kit is installed
at user level: read every `.claude/...` path in this file and in
`.claude/rules/` as `~/.claude/...`.

Mobile client (Android + iOS) for **tepira.id**: savings goals reached through
small "teu pira" deposits. The web app and API live in the separate `tepira`
repo (Next.js 15, Prisma, Auth.js Google login); this app is an API client only.

## Tech Stack

- Flutter 3.x (stable), Dart 3.x, Material 3, dark-first theme
- State: Riverpod (`flutter_riverpod`); navigation: `go_router`
- Networking: `dio` against the tepira API (`https://tepira.asepsunarya.com/api/...`)
- Auth: Google Sign-In, session cookie / token stored in `flutter_secure_storage`
- Tooling: `flutter analyze` (lints from `flutter_lints`), `flutter test`, `dart format`
- Copy and UI text are in Indonesian, code and comments in English

## Commands

| Task            | Command                                               |
|-----------------|-------------------------------------------------------|
| Install         | `flutter pub get`                                     |
| Run (device)    | `flutter run` (`-d chrome` for a quick web preview)   |
| Build Android   | `flutter build apk --release`                         |
| Build iOS       | `flutter build ipa --release`                         |
| Test (all)      | `flutter test`                                        |
| Test (one file) | `flutter test test/features/goals/goal_card_test.dart`|
| Lint            | `flutter analyze`                                     |
| Format          | `dart format lib test`                                |

Run `flutter analyze` and `flutter test` before claiming a task is done. "Seems right" is not evidence.

## Project Structure

```
lib/
  main.dart           → entry point, ProviderScope, runApp
  app.dart            → MaterialApp.router, theme, router wiring
  core/               → theme, constants, formatting (Rupiah, dates), errors
  data/               → API client (dio), DTOs, repositories
  features/<name>/    → one folder per feature: screens, widgets, providers
    goals/            → goal list, progress, add deposit ("setoran")
    auth/             → Google login, session handling
test/                 → mirrors lib/: lib/features/goals/x.dart → test/features/goals/x_test.dart
docs/                 → ADRs (docs/adr/), specs, ideas
tasks/                → tasks/plan.md and tasks/todo.md written by /plan
```

`android/` and `ios/` come from `flutter create .`; edit only for native config.

## Code Conventions

- Feature-first folders; nothing in `features/a` imports from `features/b`. Share through `core/` or `data/`.
- Widgets are small and `const` where possible; prefer composition over large `build` methods.
- State lives in Riverpod providers, never in global variables or singletons.
- All API calls go through a repository in `data/`; screens never call `dio` directly.
- Money is `int` rupiah (no doubles). Format with the helper in `core/format.dart`.
- Errors: throw `AppException` subclasses from `core/errors.dart`; show user-facing messages in Indonesian.
- Code reveals intent through names and structure. No dead code, no debug `print`, no commented-out blocks.

## Boundaries

**Always**
- Read the file (and its tests) before editing it; copy an existing pattern instead of inventing one.
- Run `flutter analyze` and `flutter test` before committing.
- Keep changes scoped to the task. Touch only what you were asked to touch.
- Keep the API contract in sync with the `tepira` backend; do not invent endpoints.

**Ask first**
- New dependencies in `pubspec.yaml` (state the size and the reason)
- Changes to auth, token storage, or anything touching money calculations
- Native changes in `android/` or `ios/` (permissions, signing, build config)
- Deleting code that "seems unused"

**Never**
- Commit secrets, keystores, `google-services.json`, `GoogleService-Info.plist`, or `.env*` files
- Silence failing tests, lower thresholds, or add `// ignore:` to get green
- Force-push to shared branches
- Invent requirements the spec does not cover: stop and ask

## How to Work

These behaviours apply at all times (see the `using-agent-skills` skill):

1. **Surface assumptions** before non-trivial work: list them and ask for correction.
2. **Manage confusion.** When the spec and the code disagree, stop and ask. Do not guess.
3. **Push back** when an approach has a concrete downside; propose an alternative, then accept the decision.
4. **Prefer the boring solution.** If 100 lines would do, do not write 1000.
5. **Scope discipline.** No drive-by refactors; never remove things you do not understand.
6. **Verify, do not assume.** Every task ends with evidence: test output, build result, runtime check.

For multi-step work, emit a short plan first and proceed unless redirected.

## Workflow

Skills in `.claude/skills/` activate automatically from their descriptions.
The slash commands are the entry points:

| Phase       | Command                      | Skill(s) and artifacts                                              |
|-------------|------------------------------|---------------------------------------------------------------------|
| Define      | `/spec`                      | spec-driven-development → `SPEC.md`                                 |
| Quality bar | `/constraints`               | constraint-driven-development → `CONSTRAINTS.md`                    |
| Plan        | `/plan`                      | planning-and-task-breakdown → `tasks/plan.md`, `tasks/todo.md`      |
| Build       | `/build` or `/build auto`    | incremental-implementation + test-driven-development                |
| Verify      | `/test`                      | test-driven-development (Prove-It pattern for bugs)                 |
| Review      | `/review`, `/code-simplify`  | code-review-and-quality, code-simplification                        |
| Ship        | `/ship`                      | shipping-and-launch (fans out to code-reviewer, security-auditor, test-engineer) |

`/webperf` targets web apps and does not apply here; use the
`performance-optimization` skill for jank, build size, and startup time.

Typical paths:
- New feature: `/spec` → `/plan` → `/build` (repeat per task) → `/review` → `/ship`
- Bug fix: debugging-and-error-recovery → `/test` (failing test first) → `/review`
- Unclear request: interview-me or idea-refine before `/spec`

Specialist subagents live in `.claude/agents/`. They never call each other;
the user or a slash command does the orchestration.

If `CONSTRAINTS.md` exists, read it before writing code and never weaken it to make a change pass.

## Definition of Done

A task is done only when its acceptance criteria are met **and** the standing
bar in `.claude/references/definition-of-done.md` holds: verified at runtime,
covered by a test that fails without the change and passes with it, no
regressions, lint and types clean, scoped to the task, and documented where
public behaviour changes.

## Git

- Conventional commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`. The body explains *why*.
- One logical change per commit, ~100 lines target; split anything over ~1000.
- Keep refactors separate from behaviour changes.
- Commit only when the user asks, or when a command defines the commit step (`/build` commits once per task; `/ship` never commits).
- Branch names: `feature/<desc>`, `fix/<desc>`, `chore/<desc>`.

## Patterns

A feature widget in this project's style:

```dart
class GoalProgress extends StatelessWidget {
  const GoalProgress({super.key, required this.saved, required this.target});

  final int saved;
  final int target;

  @override
  Widget build(BuildContext context) {
    final ratio = target == 0 ? 0.0 : (saved / target).clamp(0.0, 1.0);
    return Semantics(
      label: 'Progres ${(ratio * 100).round()}%',
      child: LinearProgressIndicator(value: ratio),
    );
  }
}
```
