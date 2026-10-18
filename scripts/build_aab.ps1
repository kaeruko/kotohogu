<# Build a Google Play signed AAB on Windows; increment pubspec only on success.
Provide android/key.properties and an upload keystore outside git first. #>
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$properties = Join-Path $root 'android\key.properties'
if (-not (Test-Path -LiteralPath $properties -PathType Leaf)) {
    throw 'Missing android/key.properties. Set up the Android upload key before building.'
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter executable not found.'
}
Push-Location $root
try {
    $json = python tools/android/release_version.py plan --format json
    if ($LASTEXITCODE -ne 0) { throw 'Unable to read pubspec version.' }
    $plan = $json | ConvertFrom-Json
    Write-Host "AAB: $($plan.source_version) -> $($plan.build_name)+$($plan.next_build_number)"

    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get failed.' }
    dart run flutter_launcher_icons -f pubspec.yaml
    if ($LASTEXITCODE -ne 0) { throw 'Launcher icon generation failed.' }
    flutter build appbundle --release --build-name $plan.build_name --build-number $plan.next_build_number
    if ($LASTEXITCODE -ne 0) { throw 'AAB build failed; pubspec.yaml was not changed.' }

    $aab = Join-Path $root 'build\app\outputs\bundle\release\app-release.aab'
    if (-not (Test-Path -LiteralPath $aab -PathType Leaf)) {
        throw 'Build reported success but signed AAB is missing; pubspec.yaml was not changed.'
    }
    if ((Get-Item -LiteralPath $aab).Length -le 0) {
        throw 'AAB is empty; pubspec.yaml was not changed.'
    }
    $jarsigner = Get-Command jarsigner -ErrorAction SilentlyContinue
    if (-not $jarsigner) { throw 'jarsigner (JDK) not found: signature verification required.' }
    # jarsigner localizes its output. Pin English only for this verification
    # so the strict jar verified / sm checks work on non-English Windows.
    $previousJavaToolOptions = [Environment]::GetEnvironmentVariable('JAVA_TOOL_OPTIONS', 'Process')
    try {
        $env:JAVA_TOOL_OPTIONS = ("$previousJavaToolOptions -Duser.language=en -Duser.country=US").Trim()
        $verification = & $jarsigner.Source -verify -verbose $aab
        $verificationExitCode = $LASTEXITCODE
    }
    finally {
        [Environment]::SetEnvironmentVariable('JAVA_TOOL_OPTIONS', $previousJavaToolOptions, 'Process')
    }
    if ($verificationExitCode -ne 0) {
        $verification | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
        throw "AAB signing verification failed (jarsigner exit code $verificationExitCode); pubspec.yaml was not changed."
    }
    $signedOutput = $verification -join "`n"
    if ($signedOutput -notmatch 'jar verified[.]' -or $signedOutput -notmatch '(?m)^\s*sm\s+') {
        $verification | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
        throw 'AAB is not verified as signed; pubspec.yaml was not changed.'
    }

    python tools/android/release_version.py persist --expected-version $plan.source_version --next-build-number $plan.next_build_number
    if ($LASTEXITCODE -ne 0) { throw 'AAB exists but failed to persist version; investigate before next build.' }
    Write-Host "Signed AAB: $aab"
}
finally {
    Pop-Location
}
