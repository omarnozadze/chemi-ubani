# Requires an active Apple Developer Program account and access to the Expo project.
# Creates a store-signed iOS build only; does not submit for public App Store review.
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
  & node scripts/configure.mjs --check
  if($LASTEXITCODE -ne 0){throw 'Public configuration is incomplete'}
  & npm.cmd ci --no-audit --no-fund
  if($LASTEXITCODE -ne 0){throw 'Dependency installation failed'}
  & node scripts/embed-html.mjs prototype-v4.55.0.html
  if($LASTEXITCODE -ne 0){throw 'HTML embedding failed'}
  & node scripts/verify-release.mjs
  if($LASTEXITCODE -ne 0){throw 'Release verification failed'}
  & npx.cmd eas-cli@latest build --platform ios --profile ios-testflight
  if($LASTEXITCODE -ne 0){throw 'iOS cloud build failed. Check account, signing and build quota.'}
  Write-Host 'Build requested. After it succeeds, upload the selected build to TestFlight with EAS Submit or App Store Connect. Public review is a separate step.'
} finally {Pop-Location}
