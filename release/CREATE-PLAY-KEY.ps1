# Run once for a NEW Play app with no existing upload key. Keep the key/passwords private.
# Does not replace the debug key used by existing sideloaded APKs.
param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'File already exists; no key was overwritten.'}
if(!(Get-Command keytool -ErrorAction SilentlyContinue)){throw 'Java keytool must be available in PATH.'}
$parent=Split-Path -Parent $OutputPath
if(!$parent -or !(Test-Path -LiteralPath $parent -PathType Container)){throw 'Choose an existing private folder outside the project.'}
& keytool -genkeypair -v -keystore $OutputPath -alias chemi-upload -keyalg RSA -keysize 3072 -validity 10000 -storetype JKS
if($LASTEXITCODE -ne 0){throw 'Key generation failed'}
Write-Host 'Key created. Back it up securely together with the passwords. Do not send it in chat or commit it.'
