# Contributing

1. Work on a branch and keep changes scoped to one behavior.
2. Edit browser feature modules in `src/`; do not edit `src/appHtml.js`.
3. Run `npm run check` and include the result in the pull request.
4. If changing native behavior, also test it on a real device and state the OS/version.
5. If changing SQL, document prerequisites, authorization impact, migration order and rollback. Use a test database and review the baseline before applying historical patches.
6. Never commit user data, auth sessions, signing files or provider secrets. Use synthetic test identities.
7. Keep product versions consistent. Packaging/documentation changes alone must not pretend to be a new tested mobile release.

Historical tests are retained for reference. Adding a test to the supported suite means making it work with the current source and preventing outbound network calls; do not remove meaningful assertions merely to obtain a passing result.
