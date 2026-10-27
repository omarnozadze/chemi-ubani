# Validation record

Date: 2026-10-27. Source baseline: 4.55.0, Android versionCode 39.

## Supported checks

```sh
npm ci --ignore-scripts
npm ci --prefix tooling --ignore-scripts
npm run check
```

The selected suite runs under Node.js 24 with network access disabled inside test processes:

| Test | Behavior checked |
| --- | --- |
| `config-public.mjs` | Example defaults, privileged-key rejection, unknown config fields, safe inline serialization |
| `release-current.mjs` | Consistent product/native versions, wrong build targets, stale embedded output |
| `push-v442.mjs` | Transient retry bounds, account-switch races, permission denial, timeout cleanup |
| `polling-v427.mjs` | No overlapping jobs, pause while inactive/offline, wake/re-entry |
| `load-guard-v427.mjs` | Explicit staging confirmation, distinct production target, fresh unique synthetic sessions |
| `routes-edge-v451.mjs` | Server route request validation, auth requirement, walking/driving mapping, missing provider key |
| `routes-v455.mjs` | Route distance/time, cache/mode behavior, detail updates, batching, quota feedback and logout |

Release metadata verification and JavaScript syntax/pattern checks also run. GitHub Actions uses the same command; its remote result must be checked after the first push.

**Result in this environment: 7/7 selected test scripts passed.** Release metadata matched 4.55.0 / 39, inline browser scripts parsed, and the configured native shell parsed as JSX. Pattern scans found no embedded private key, service-account JSON, provider-token pattern or original production binding in the prepared source. This is not an exhaustive secret/security guarantee.

## Scope limits

Local validation uses the available Node test dependencies and the supplied application's Babel parser. A fresh network install of every mobile dependency is not independently certified here. Both application and test dependency lockfiles are included for reproducible installation.

The older files in `tests/` are historical regression scripts, not a blanket passing suite. Many name superseded HTML files and may assert older UI behavior. They need deliberate porting before inclusion. A passing selected suite does not establish full application coverage.

No native APK/AAB/iOS build, real Firebase push, phone OTP, camera/GPS hardware session, production database migration, dependency-vulnerability audit, store review or high-concurrency load test was performed during this handoff.
