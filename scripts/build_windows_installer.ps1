param(
  [string]$FlutterRoot = "C:\flutter",
  [string]$IsccPath = "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
  [string]$BashPath = "C:\Program Files\Git\bin\bash.exe",
  [string]$BundleDir = "",
  [string]$Configuration = "release",
  [switch]$SkipBuild,
  [switch]$SkipPubGet,
  [switch]$SkipBundle,
  [switch]$SkipInstaller,
  [switch]$Sign,
  [string]$SigntoolPath = "",
  [string]$PfxPath = "",
  [string]$PfxPassword = "",
  [string]$CertThumbprint = "",
  [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Continue"

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $BundleDir) {
  $ConfigDir = switch ($Configuration.ToLower()) {
    'debug' { 'Debug' }
    'profile' { 'Profile' }
    'release' { 'Release' }
    default { throw "Unsupported Configuration '$Configuration'." }
  }
  $BundleDir = Join-Path $ProjectRoot "build\windows\x64\runner\$ConfigDir"
}

function Invoke-Native {
  param([string]$File, [string[]]$Arguments)
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "${File} exited with code $LASTEXITCODE"
  }
}

function Find-SignTool {
  $KitsRoot = "C:\Program Files (x86)\Windows Kits\10\bin"
  if (Test-Path $KitsRoot) {
    $Candidate = Get-ChildItem $KitsRoot -Directory |
      Sort-Object Name -Descending |
      ForEach-Object { Join-Path $_.FullName "x64\signtool.exe" } |
      Where-Object { Test-Path $_ } |
      Select-Object -First 1
    if ($Candidate) { return $Candidate }
  }
  $FromPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($FromPath) { return $FromPath.Source }
  return ""
}

$FlutterBat = Join-Path $FlutterRoot "bin\flutter.bat"
if (-not (Test-Path $FlutterBat)) {
  throw "Flutter SDK not found at '$FlutterBat'. Set -FlutterRoot."
}

if (-not $SkipPubGet) {
  Write-Host "==> flutter pub get"
  Invoke-Native $FlutterBat @("pub", "get")
}

if (-not $SkipBuild) {
  Write-Host "==> flutter build windows --$Configuration"
  Invoke-Native $FlutterBat @("build", "windows", "--$Configuration")
}

if (-not (Test-Path (Join-Path $BundleDir "newchirp.exe"))) {
  throw "Flutter release bundle not found at '$BundleDir'."
}

if (-not $SkipBundle) {
  if (-not (Test-Path $BashPath)) {
    throw "Git Bash not found at '$BashPath'. Set -BashPath."
  }
  $BashDir = Split-Path $BashPath
  $Cygpath = Join-Path $BashDir "cygpath.exe"
  if (-not (Test-Path $Cygpath)) {
    $Cygpath = Join-Path (Join-Path (Split-Path $BashDir) "usr\bin") "cygpath.exe"
  }
  if (-not (Test-Path $Cygpath)) {
    throw "cygpath.exe not found. Install Git for Windows with its usr\bin directory (looked at '$(Join-Path $BashDir \"cygpath.exe\")' and '$(Join-Path (Join-Path (Split-Path $BashDir) \"usr\bin\") \"cygpath.exe\")')."
  }
  $ScriptPosix = (& $Cygpath -u (Join-Path $ProjectRoot "scripts\bundle_windows_runtime.sh")).Trim()
  $BundlePosix = (& $Cygpath -u $BundleDir).Trim()
  Write-Host "==> bundling Python + CHIRP into $BundleDir"
  Invoke-Native $BashPath @($ScriptPosix, "--bundle-dir", $BundlePosix)
}

$Pubspec = Join-Path $ProjectRoot "pubspec.yaml"
$VersionLine = (Select-String -Path $Pubspec -Pattern '^version:\s*(\S+)' |
  Select-Object -First 1)
if (-not $VersionLine) {
  throw "Could not read the version from pubspec.yaml."
}
$Version = $VersionLine.Matches[0].Groups[1].Value
$DisplayVersion = $Version.Split('+')[0]

if (-not $SkipInstaller) {
  if (-not (Test-Path $IsccPath)) {
    throw "Inno Setup ISCC not found at '$IsccPath'. Set -IsccPath."
  }
  $Iss = Join-Path $ProjectRoot "installer\newchirp.iss"
  Write-Host "==> compiling installer for version $DisplayVersion"
  Invoke-Native $IsccPath @(
    "/DSourceDir=$BundleDir",
    "/DMyAppVersion=$DisplayVersion",
    "/DMyAppPublisher=com.rickext.newchirp",
    $Iss
  )
}

$Installer = Join-Path $ProjectRoot "build\NewChirp-Installer-$DisplayVersion.exe"

if ($Sign) {
  if (-not $CertThumbprint -and -not (Test-Path $PfxPath)) {
    throw "Signing requested (-Sign) but no certificate is configured. Pass -PfxPath/-PfxPassword (pfx) or -CertThumbprint (store cert), or omit -Sign to build unsigned."
  }
  if (-not $SigntoolPath) { $SigntoolPath = Find-SignTool }
  if (-not $SigntoolPath -or -not (Test-Path $SigntoolPath)) {
    throw "signtool.exe not found. Install the Windows SDK (Windows Kits) or pass -SigntoolPath."
  }

  $SignArgs = @("sign", "/fd", "SHA256", "/tr", $TimestampUrl, "/td", "SHA256")
  if ($CertThumbprint) {
    $SignArgs += @("/sha1", $CertThumbprint)
    Write-Host "==> signing installer with certificate thumbprint $CertThumbprint"
  } else {
    $SignArgs += @("/f", (Resolve-Path $PfxPath).Path, "/p", $PfxPassword)
    Write-Host "==> signing installer with PFX '$PfxPath'"
  }
  $SignArgs += $Installer

  Invoke-Native $SigntoolPath $SignArgs
  Write-Host "==> signed: $Installer"
}

Write-Host "Done. Installer: $Installer"