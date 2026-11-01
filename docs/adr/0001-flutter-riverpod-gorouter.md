# ADR 0001: Flutter with Riverpod and go_router

Status: accepted. Date: 2026-11-01.

## Context

tepira.id already has a Next.js web app and API. The mobile app must reach
Android and iOS from one codebase and stay small enough for one developer.

## Decision

- Flutter (stable) with Material 3, dark-first theme to match the web app.
- Riverpod for state and dependency injection (testable via provider overrides).
- go_router for navigation (declarative routes, deep links later).
- dio as the HTTP client with a single provider; repositories own all API calls.
- Whole-rupiah integers for money; no floating point.

## Consequences

- No local database in v1: the app is online-first and depends on the API.
- Google Sign-In must reuse the backend's Auth.js session or a token endpoint;
  this needs a small backend change and is tracked as the first `/spec`.
