# Run from PowerShell: .\BUILD-AAB.ps1 -Keystore 'C:\Keys\upload.jks' -Alias 'upload'
# Uses your existing dedicated upload key. Does not create or upload keys, and never prints passwords.
param([Parameter(Mandatory=$true)][string]$Keystore,[Parameter(Mandatory=$true)][string]$Alias)
$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
$names=@('CHEMI_UPLOAD_KEYSTORE','CHEMI_UPLOAD_ALIAS','CHEMI_UPLOAD_STORE_PASSWORD','CHEMI_UPLOAD_KEY_PASSWORD','NODE_ENV')
$previous=@{}
foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
function Read-Secret([string]$Prompt){
    $secret=Read-Host $Prompt -AsSecureString
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}
    finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
}
try {
    if(!(Test-Path -LiteralPath $Keystore -PathType Leaf)){throw 'Upload keystore not found.'}
    if($Alias -eq 'androiddebugkey' -or (Split-Path $Keystore -Leaf) -eq 'debug.keystore'){throw 'Choose a dedicated Play upload key, not the debug key.'}
    $env:CHEMI_UPLOAD_KEYSTORE=(Resolve-Path -LiteralPath $Keystore).Path
    $env:CHEMI_UPLOAD_ALIAS=$Alias
    $env:CHEMI_UPLOAD_STORE_PASSWORD=Read-Secret 'Keystore password'
    $env:CHEMI_UPLOAD_KEY_PASSWORD=Read-Secret 'Key password'
    & node scripts/configure.mjs --check
    if($LASTEXITCODE -ne 0){throw 'Public configuration is incomplete.'}
    & npm.cmd ci --no-audit --no-fund
    if($LASTEXITCODE -ne 0){throw 'Dependency installation failed.'}
    & node scripts/embed-html.mjs prototype-v4.55.0.html
    if($LASTEXITCODE -ne 0){throw 'HTML embedding failed.'}
    & node scripts/verify-release.mjs
    if($LASTEXITCODE -ne 0){throw 'Release versions or embedded HTML do not match.'}
    $env:NODE_ENV='production'
    Push-Location android
    try{
        & .\gradlew.bat bundleRelease -PproductionSigning=true '-PreactNativeArchitectures=arm64-v8a,armeabi-v7a'
        if($LASTEXITCODE -ne 0){throw 'AAB build failed. Review the error above.'}
    }finally{Pop-Location}
    $bundle=Join-Path $PSScriptRoot 'android\app\build\outputs\bundle\release\app-release.aab'
    if(!(Test-Path $bundle)){throw 'AAB output was not found.'}
    Write-Host "AAB created: $bundle"
    & explorer.exe (Split-Path $bundle)
}finally{
    foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}
    Pop-Location
}
