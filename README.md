# Chemi Ubani · ჩემი უბანი

A Georgian-language neighborhood community application for local posts, private and group conversations, daily photos, marketplace listings, specialist discovery and nearby places.

**Source version: 4.55.0 · Android versionCode: 39 · Status: pre-release source handoff.**

This repository was prepared from the supplied 4.55.0 archive. It is not a copy of a newer Play Console build. The packaging work does not increment the product version or claim store approval, production security certification, or capacity for thousands of concurrent users.

[ქართული გზამკვლევი](docs/START-HERE-ka.md) · [Architecture](docs/ARCHITECTURE.md) · [Setup](docs/SETUP.md) · [Validation](docs/VALIDATION.md) · [Technical review](docs/TECHNICAL-REVIEW.md)

## Product scope

- Neighborhood feed, reactions, comments and moderation.
- Direct and group conversations with attachments and message actions.
- Daily photo capture and personal calendar views.
- Marketplace and specialist listings; direct specialist chat.
- Nearby businesses with walking/driving route estimates.
- Community issue reports and administrator campaigns.
- Push registration, background delivery helpers and account/content deletion workflows.

These are implemented code paths, not a statement that every feature has been verified on every device. The active UI removes the payment/order screens; historical SQL and modules remain in the source history snapshot.

## Architecture

The mobile shell is **Expo / React Native**, while most screens are **HTML, CSS and JavaScript inside React Native WebView**. This is a hybrid app, not a component-per-screen native React application.

`App.js` bridges camera capture, push notifications, lifecycle, back navigation and external links. `prototype-v4.55.0.html` contains the base web UI. The embedding script applies the ordered feature modules from `src/` and produces the ignored `src/appHtml.js` used by the shell. Supabase supplies backend RPCs, authentication, storage and realtime support; server-side route and notification providers are called through Edge Functions.

## Review the source locally

Use Node.js 24 (24.3+), npm and Git:

```sh
npm ci --ignore-scripts
npm ci --prefix tooling --ignore-scripts
npm run check
```

The check command regenerates the embedded client, verifies release metadata, parses source and runs the selected **offline** regression suite. No backend credentials are needed. CI runs the same checks and never publishes an application.

For development/build installation, use `npm ci` normally and follow [Setup](docs/SETUP.md). A fresh checkout intentionally has no production connection, Firebase file or signing key. It is a source review checkout, not a self-contained working backend.

## Repository map

| Path | Responsibility |
| --- | --- |
| `App.js` | Native shell and WebView bridge |
| `prototype-v4.55.0.html` | Base web UI and embedded feature sections |
| `src/` | Ordered browser feature modules and native helpers |
| `scripts/` | Configuration, embedding, version verification, offline checks |
| `android/` | Native Android Gradle project and resources |
| `assets/` | Application icons and splash artwork |
| `supabase/functions/` | Push, deletion and routing/provider server code |
| `supabase/migrations/` | Available timestamped historical migrations |
| `supabase/*.sql` | Incremental SQL patches, some overlapping migrations |
| `tests/` | Selected current tests plus historical regression scripts |
| `tooling/` | Separately locked Node test dependencies |
| `load-tests/` | Opt-in k6 scenario; never run by CI |
| `public/` | Historical privacy/deletion web pages, not automatically deployed |
| `docs/` | Setup, architecture, review findings and handoff instructions |

## Important engineering boundaries

- The full baseline database schema is **not present**. Do not run all SQL files on an empty or production database. Review the actual migration history and obtain a schema-only baseline first.
- Browser features use shared globals and ordered wrappers. Renaming/reordering modules without integration tests can break behavior.
- Source contains historical phone-based administrator assumptions. The sharing copy replaces the owner's number with `500000000`; this is an example, not a real administrator to provision. Server authorization must be reviewed before a new deployment.
- Historical tests may reference old HTML filenames; only the explicit suite in `scripts/run-tests.mjs` is a supported check command for this snapshot.
- Native Android/iOS builds, real SMS/push delivery, store approval and large-scale load are not validated by this handoff.
- WebView navigation/permissions and the complete backend RLS model need a dedicated security review; see the prioritized findings.

## Configuration and ownership

Copy `config.public.example.json` to `config.public.local.json` and use your own public Supabase URL/client key and Expo project ID. Never put a service-role key, private key, provider secret or signing password in client configuration. `.gitignore` excludes local configuration and generated bundles.

Start with a **private GitHub repository**. No open-source license is granted by this handoff; choose licensing terms with the project owner before making it public. Third-party packages retain their own licenses.
