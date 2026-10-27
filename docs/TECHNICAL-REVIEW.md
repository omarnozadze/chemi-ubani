# Technical review and next engineering work

Prepared 2026-10-27 from the user-supplied archive. This is a source/package review, not a live production audit.

## Completed in this handoff

- Removed bundled dependencies, personal learning/CV PDFs, unrelated folders, old archives, debug keystore, Firebase project files and machine SDK settings from the sharing copy.
- Kept the application identity and version 4.55.0 / 39; replaced production backend identifiers, embedded client tokens, Expo project binding and owner telephone references with examples.
- Added a local public config loader and generated native/WebView configuration. Public config rejects service-role JWTs, secret keys and unknown fields.
- Added ignored-file rules, editor/line-ending conventions, a separately locked test tool package, an offline test runner and GitHub Actions checks.
- Removed the automatic EAS publish workflow and obsolete archive-unpacking helper. CI does not deploy, send notifications or mutate a database.
- Added current build documentation, architecture, Georgian handoff instructions and explicit review limitations.
- Replaced a stale hardcoded version test with a current-version test; retained historical regression scripts for future migration.
- Strengthened the opt-in load-test guard: an explicit, different production reference and staging confirmation are required. No load test was run.

## Findings requiring follow-up

| Priority | Finding | Concrete next step |
| --- | --- | --- |
| High | No full baseline schema for a fresh database; incremental/duplicate SQL patches coexist | Export schema without rows, reconcile migration history, bootstrap a disposable database and test it |
| High | WebView allows all origins, file access and mixed content; external-link bridge accepts caller URLs | Audit navigation origins and URL schemes; restrict permissions with camera/file/map device tests |
| High | Historical client and SQL use a fixed phone for administrator behavior | Replace owner-specific assumptions with a reviewed role/identity model; test cross-role access server-side |
| High | Full auth/RLS/storage policy behavior not verified in this handoff | Add authenticated multi-user negative tests against a staging backend |
| Medium | Large HTML base, shared globals and many versioned wrapper modules | Extract a stable app state/API layer and module boundaries incrementally; preserve feature tests |
| Medium | Generated feature sections also live in the tracked HTML template | Separate base source from generated distribution after behavioral comparison |
| Medium | Many old tests reference old HTML versions or require historical fixtures | Port tests feature by feature; do not count old files as passing coverage |
| Medium | Provider quotas/network delay affect nearby routing and notifications | Add operational metrics and capacity tests with realistic budgets; no scalability promise yet |
| Medium | iOS config is present but tablet support disabled and native delivery unverified | Run iPhone/TestFlight and Android hardware validation with real permissions and push |
| Medium | No root license decision or recorded ownership/provenance statement | Keep private until owner selects terms and reviews asset/code rights |

## What this is suitable for

A private technical review, portfolio walkthrough with honest scope, and a starting repository for ongoing engineering. It is a meaningful working-app source snapshot with tests and build infrastructure, not an enterprise-ready certification. Describe the project as an Expo/React Native hybrid app backed by Supabase, and explain which parts you designed, implemented or built with assistance.

The original archive is preserved separately. This sanitized repository is not a drop-in replacement for the owner's currently configured production build directory. Its example configuration deliberately prevents accidental connections to the owner's backend.
