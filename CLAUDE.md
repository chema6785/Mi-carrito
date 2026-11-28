# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

"Mi carrito": a Spanish-language shopping app (scan barcodes in the supermarket, add up the running total, shopping lists, receipt scanning, household spending). The UI text, code comments and commit messages are all in Spanish. Keep writing them in Spanish. Commit messages describe the change from the user's point of view (for example "Escáner seguido: añade los productos conocidos sin cerrar la cámara…").

## Rules

- **Always reply and explain in Spanish.**
- **The repository is public.** Never commit keys, tokens, the APK signing keystore (it lives only in the GitHub secrets `ANDROID_KEYSTORE_B64` / `ANDROID_KEYSTORE_PASS`) or the owner's personal receipts. The Supabase *publishable* key in `index.html` is meant to be public. Anything secret stays out of the repo.
- Keep the "all rights reserved" notice in the name of **chema6785** (`LICENSE` and the "Autor y derechos" section of `README.md`).
- **The owner's family is beta-testing the app.** A change that alters the shape or meaning of data saved under `cart.*` (or the shared data in Supabase) must migrate existing data when it loads. Never delete it or reset it.

## Build / run / deploy

There is no build step, bundler, linter or test suite. The app is static files in `www/`.

- **Run locally:** serve `www/` with any static server (for example `npx serve www` or `python -m http.server -d www`). The service worker only registers on `*.github.io`, so local runs aren't cached.
- **Web deploy:** every push to `main` publishes `www/` to GitHub Pages (`.github/workflows/web.yml`).
- **Android APK:** every push to `main` also runs `.github/workflows/apk.yml`. It runs `npx cap add android` fresh each time (there's no committed `android/` folder), patches the manifest and styles with `sed`/python (camera permission, `micarrito://` deep-link scheme, icons from `android-icons/`, bar colors), sets `versionCode` to the run number, signs with the keystore from repo secrets, and replaces the `apk` release. Native config changes therefore go in that workflow, not in an Android project. The workflow also writes `www/build.json` (`{t, sha}`), which the app reads to detect a newer APK.

## Architecture

- **Almost all the app is in `www/index.html`** (about 2000 lines, about 220 KB): CSS in `<style>`, markup, then one big `<script>` wrapped in a block `{ … }`. It's organized into sections marked by `/* ---- título ---- */` comments (escáner, lista, tickets, Supabase, cuenta con Google, etc.). Grep for those headers to find your way. Code is dense, minified-style JS (`$=id=>getElementById`, one-liners). Match that style.
- **State** lives in `localStorage` under `cart.*` keys, always through the `load(key, default)` / `put(key, value)` JSON helpers. There's no framework. Rendering is done by hand with `render*()` functions and `esc()` for HTML escaping.
- **Native vs. web:** the same code runs as a PWA and inside Capacitor 6. Branch on `Capacitor.isNativePlatform()`. In the APK it uses native plugins (`Capacitor.Plugins.*`: ML Kit barcode/text recognition, speech recognition, status bar, filesystem, share, clipboard). On the web it falls back to `zxing.min.js` (barcodes), Tesseract in `www/ocr/` (labels and receipts, Spanish traineddata) and pdf.js in `www/pdf/` (PDF receipts). These are vendored files, not npm dependencies.
- **Service worker (`www/sw.js`):** network-first with a 3-second timeout, falling back to cache. `ocr/` and `pdf/` are cache-first in a separate cache. **Bump the `mi-carrito-vNN` cache name when shipping changes** to the cached files.
- **Backend: Supabase**, called with plain `fetch` (no SDK). The URL and publishable key are hard-coded in `index.html`. Data access goes only through `SECURITY DEFINER` RPCs via `sbRpc(fn, args)`, because tables have RLS on and are revoked from anon. The anonymous identity is a random `cart.device` id, and shared family lists use a 10-character `list_code`. Optional Google login (`/auth/v1/…`) syncs the user's data to a `user_data` table. `www/login.html` is the OAuth redirect page that hands the session back to the app via the `micarrito://` scheme.
- **Database schema: `supabase-5-esquema-completo.sql` is the reference.** It's a snapshot of the real project (28-11-2026) with every table (`prices`, `list_items`, `list_members`, `purchases`, `user_data`, `auth_handoff`, `app_errors`, `product_photos`), the `fotos` bucket, the RLS policies, all the RPCs and their grants. It can be re-run and builds a project from scratch. `supabase.sql` and `supabase-2-…` to `supabase-4-…` are old intermediate steps and no longer describe the database. SQL files are run by hand in the Supabase SQL editor. **New server-side changes go in a new numbered file (`supabase-6-…`, etc.).** If a change alters the schema, also update `supabase-5-esquema-completo.sql` so it stays the full picture. A new RPC needs `security definer`, `set search_path = public`, input trimming/validation, and `revoke … from public` plus `grant execute … to anon, authenticated`. The project has an `ensure_rls` event trigger that turns RLS on automatically for every new table in `public`.
- **External read-only APIs:** Open Food Facts and Open Prices (product names, photos, allergens).
- Errors are captured (`logErr`, `unhandledrejection`) and sent to the server through `log_errors`.
