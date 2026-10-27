# Setup and build

## 1. Requirements

Use Node.js 24.3+ within the 24.x line, npm, Git, and an Android Studio/JDK/SDK installation compatible with the committed Gradle project. Check the project's `android/` Gradle files for its SDK/NDK versions; do not arbitrarily upgrade them during onboarding. iOS store distribution also needs Apple Developer signing and access to an Expo/EAS project.

The supplied `node_modules` directory has been excluded. Install from the lockfile:

```sh
npm ci
npm ci --prefix tooling
```

`tooling/` is for tests only; it is not shipped with the mobile application.

## 2. Public client configuration

PowerShell:

```powershell
Copy-Item .\config.public.example.json .\config.public.local.json
notepad .\config.public.local.json
```

Set:

- `supabaseUrl`: your HTTPS project URL.
- `supabaseAnonKey`: an anon/publishable client key, never a `service_role` or secret key.
- `expoProjectId`: your existing Expo project UUID.

Then:

```sh
npm run configure
npm run sync-html
npm run verify
```

These values are embedded into the installed client and must be treated as public. The generator rejects a service-role JWT, `sb_secret_` keys and unknown config properties. The local file and generated JS files are excluded from Git.

Without local config, source checks use `https://example.invalid`, an example key and a zero project UUID. This is suitable for offline review/tests, not for login, push or a live product demonstration. No backend is created automatically.

## 3. Firebase, Android SDK and signing

Restore/download the **Firebase Android application configuration** for the intended package to both:

- `google-services.json`
- `android/app/google-services.json`

This is not a Firebase Admin service-account key. A service-account JSON must never be included in the app.

Create `android/local.properties` with the local SDK path (Android Studio can create it). The local test APK script expects `android/app/debug.keystore`. The owner's existing debug key must remain private; new contributors can generate their own test-only key using the JDK `keytool`. A different test key may require uninstalling a previously signed test app. Never replace the owner's Play upload key.

To create a contributor-only test key, from the project root:

```powershell
keytool -genkeypair -keystore .\android\app\debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US"
```

Only run this if that file does not already exist. The standard debug passwords are not production secrets and are not suitable for Play signing.

## 4. Development and native builds

```sh
npm run sync-html
npm start
```

This starts Expo development tooling. A compatible development/native build is required for native camera and push behavior; do not assume that a browser preview or Expo Go verifies every native feature.

Local test APK on Windows:

```powershell
.\BUILD-APK.cmd
```

This script builds an **ARM64 test APK signed with the local debug key**, despite using Gradle's release variant. It is not the Play upload artifact. For an x86_64 emulator, adjust the architecture argument deliberately or use Android Studio.

Play upload AAB, using an existing upload key stored outside the repository:

```powershell
.\BUILD-AAB.ps1 -Keystore "$env:USERPROFILE\ChemiUbani-Keys\chemi-ubani-upload.jks" -Alias "upload"
```

Passwords are requested interactively. The Gradle configuration requires explicit production signing for `bundleRelease`; it does not silently sign a Play bundle with the debug key. The expected output is `android/app/build/outputs/bundle/release/app-release.aab`.

The unchanged source version is **4.55.0 / 39**. Do not upload it over a newer version already in Play. A future product release must increment version codes consistently in all checked metadata.

The iOS helper is `BUILD-IOS-TESTFLIGHT.ps1`. No iOS device build was verified for this handoff. The committed config has `supportsTablet: false` and OTA updates disabled.

## 5. Backend onboarding

The SQL folder is an incremental history, not a complete bootstrap. Before using a new Supabase project:

1. Obtain a **schema-only**, sanitized baseline and compare it with the deployed migration history.
2. Review prerequisites such as base tables, `app_private` functions, storage buckets, extensions and auth configuration.
3. Decide which standalone patches are already included in timestamped migrations. Do not apply both copies blindly.
4. Replace example project references, example public keys and the `500000000` administrator placeholder in reviewed server configuration. Do not grant a real role to an example identity.
5. Provision server-only secrets through the provider's secret management; never client configuration or Git.
6. Verify authorization and negative access tests in a separate test project before deployment.

Likely server environment inputs are `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `ORS_API_KEY` and, only if the legacy Places endpoint is enabled, `GOOGLE_PLACES_API_KEY`. Scheduled workers also use database/Vault configuration visible in their SQL. This list is an orientation, not a complete deployment recipe.

## 6. Static account-deletion page

`public/` contains historical source pages. They are not the previously published privacy website and are not automatically deployed by this repository. The deletion page expects `public/config.js` defining `window.CHEMI_PUBLIC_CONFIG` with the public backend URL/key. Supply this only for a separately reviewed deployment; do not copy a service key. Review contact details, policy wording and actual deletion behavior before publishing.
