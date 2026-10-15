# Run locally. Passwords are entered securely and never written to source files.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:SAILING_KEYSTORE_FILE = Read-Host 'Existing release keystore full path'
$env:SAILING_KEY_ALIAS = Read-Host 'Existing key alias'
if (-not (Test-Path -LiteralPath $env:SAILING_KEYSTORE_FILE -PathType Leaf)) { throw 'Keystore not found' }
function Convert-LocalSecret([Security.SecureString]$secret) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
try {
    $env:SAILING_KEYSTORE_PASSWORD = Convert-LocalSecret (Read-Host 'Keystore password' -AsSecureString)
    $env:SAILING_KEY_PASSWORD = Convert-LocalSecret (Read-Host 'Key password' -AsSecureString)
    Push-Location $projectRoot
    try {
        & "$projectRoot\android\gradlew.bat" -p "$projectRoot\android" :app:testDebugUnitTest :app:assembleRelease --no-daemon
        if ($LASTEXITCODE -ne 0) { throw 'Build failed' }
        $destination = Join-Path $projectRoot 'dist'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -LiteralPath "$projectRoot\android\app\build\outputs\apk\release\app-release.apk" -Destination "$destination\SailingGpsLogger.apk"
        & python "$projectRoot\scripts\release-metadata.py" "$destination\SailingGpsLogger.apk"
        if ($LASTEXITCODE -ne 0) { throw 'Metadata generation failed; install Python 3.11 or later' }
        Write-Host 'Upload dist/SailingGpsLogger.apk and dist/android-update.json to the matching GitHub release after device tests.'
    } finally { Pop-Location }
} finally {
    foreach ($variableName in 'SAILING_KEYSTORE_FILE','SAILING_KEYSTORE_PASSWORD','SAILING_KEY_ALIAS','SAILING_KEY_PASSWORD') {
        Remove-Item -LiteralPath "Env:$variableName" -ErrorAction SilentlyContinue
    }
}
