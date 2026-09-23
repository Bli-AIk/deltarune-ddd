# Native Windows Android packaging entry point.
#
#   tools\build_android.cmd            -> menu
#   tools\build_android.cmd wrap       -> official LÖVE embed APK + game.love
#   tools\build_android.cmd compile    -> love-android source build

[CmdletBinding()]
param(
    [ValidateSet('menu', 'wrap', 'compile')]
    [string]$Mode = 'menu'
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'windows_common.ps1')

$ToolsDir = Get-TMSharedToolsDir $Root
$OutputDir = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_OUTPUT_DIR' (Join-Path $Root 'dist')
$OutputBasename = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_OUTPUT_BASENAME' 'deltarune-ddd-ch1'
$AndroidBuildToolsVersion = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_BUILD_TOOLS_VERSION' '34.0.0'
$AndroidWorkDir = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_WORK_DIR' (Join-Path $Root '.build\android')
$AndroidWrapWorkDir = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_WRAP_WORK_DIR' (Join-Path $Root '.build\android-wrap')
$CacheDir = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_CACHE_DIR' (Join-Path $Root '.build\cache')
$script:TMAndroidGit = $null

function Get-TMAndroidGit {
    if (-not $script:TMAndroidGit) {
        $script:TMAndroidGit = Get-TMCommand 'git.exe'
    }
    return $script:TMAndroidGit
}

function Test-TMJava17 {
    param([Parameter(Mandatory = $true)][string]$JavaExecutable)

    if (-not (Test-Path -LiteralPath $JavaExecutable)) {
        return $false
    }

    # java -version writes its version to stderr. Capture both streams outside
    # PowerShell's native-command error handling so this remains a predicate.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $JavaExecutable
    $startInfo.Arguments = '-version'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        # java -version emits only a short banner, so synchronous reads cannot
        # fill either pipe before the process exits.
        $version = $process.StandardOutput.ReadToEnd() + $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        return $process.ExitCode -eq 0 -and $version -match 'version "17'
    } finally {
        $process.Dispose()
    }
}

function Get-TMJavaHome {
    foreach ($configured in @($env:DELTARUNE_DDD_CH1_ANDROID_JAVA_HOME, $env:JAVA_HOME)) {
        if (-not $configured) { continue }
        $java = Join-Path $configured 'bin\java.exe'
        if (-not (Test-TMJava17 $java)) {
            throw "Android builds require JDK 17; configured Java home is not JDK 17: $configured"
        }
        return [System.IO.Path]::GetFullPath($configured)
    }

    $pathJava = Find-TMCommand 'java.exe'
    if ($pathJava -and (Test-TMJava17 $pathJava.Source)) {
        return Split-Path (Split-Path -Parent $pathJava.Source) -Parent
    }

    foreach ($cached in @((Join-Path $ToolsDir 'jdk17'), (Join-Path $ToolsDir 'jdk-17'))) {
        $java = Join-Path $cached 'bin\java.exe'
        if (Test-TMJava17 $java) {
            return $cached
        }
        $inner = Get-ChildItem -LiteralPath $cached -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-TMJava17 (Join-Path $_.FullName 'bin\java.exe') } |
            Select-Object -First 1
        if ($inner) { return $inner.FullName }
    }

    if ($env:DELTARUNE_DDD_CH1_FETCH_JDK -eq '0') {
        throw 'No JDK 17 is available and DELTARUNE_DDD_CH1_FETCH_JDK=0.'
    }
    $archive = Join-Path $ToolsDir 'jdk17.zip'
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-TMDownload 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk' $archive
    }
    $destination = Join-Path $ToolsDir 'jdk17'
    $temporary = "$destination.extract"
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
    Expand-TMZip $archive $temporary
    $inner = Get-ChildItem -LiteralPath $temporary -Directory | Where-Object {
        Test-TMJava17 (Join-Path $_.FullName 'bin\java.exe')
    } | Select-Object -First 1
    if (-not $inner) {
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        throw "JDK archive does not contain JDK 17: $archive"
    }
    Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath $inner.FullName -Destination $destination
    Remove-Item -LiteralPath $temporary -Recurse -Force
    return $destination
}

function Test-TMAndroidSdk {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $ndkProperties = Join-Path $Directory 'ndk\25.2.9519653\source.properties'
    if (-not (Test-Path -LiteralPath (Join-Path $Directory 'platforms\android-34')) -or
        -not (Test-Path -LiteralPath (Join-Path $Directory "build-tools\$AndroidBuildToolsVersion")) -or
        -not (Test-Path -LiteralPath $ndkProperties)) {
        return $false
    }
    return (Get-Content -LiteralPath $ndkProperties -Raw) -match '(?m)^\s*Pkg\.Revision\s*=\s*25\.2\.9519653\s*$'
}

function Get-TMAndroidSdk {
    param([Parameter(Mandatory = $true)][string]$JavaHome)

    foreach ($configured in @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)) {
        if ($configured -and (Test-TMAndroidSdk $configured)) {
            return [System.IO.Path]::GetFullPath($configured)
        }
    }
    if ($env:DELTARUNE_DDD_CH1_FETCH_SDK -eq '0') {
        throw 'A complete Android SDK is required and DELTARUNE_DDD_CH1_FETCH_SDK=0.'
    }

    $sdk = Join-Path $ToolsDir 'android-sdk'
    $manager = Join-Path $sdk 'cmdline-tools\latest\bin\sdkmanager.bat'
    if (-not (Test-Path -LiteralPath $manager)) {
        $archive = Join-Path $ToolsDir 'commandlinetools-win-9862592_latest.zip'
        if (-not (Test-Path -LiteralPath $archive)) {
            Invoke-TMDownload 'https://dl.google.com/android/repository/commandlinetools-win-9862592_latest.zip' $archive
        }
        $temporary = Join-Path $sdk 'cmdline-tools.extract'
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        Expand-TMZip $archive $temporary
        $inner = Join-Path $temporary 'cmdline-tools'
        if (-not (Test-Path -LiteralPath $inner)) {
            throw "Android command-line tools archive has an unexpected layout: $archive"
        }
        $latest = Join-Path $sdk 'cmdline-tools\latest'
        Remove-Item -LiteralPath $latest -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $latest) | Out-Null
        Move-Item -LiteralPath $inner -Destination $latest
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }

    if (-not (Test-TMAndroidSdk $sdk)) {
        Write-TMInfo 'Installing Android SDK API 34, build-tools 34.0.0, and NDK 25.2.9519653'
        $env:JAVA_HOME = $JavaHome
        $yes = 1..100 | ForEach-Object { 'y' }
        $yes | & $manager "--sdk_root=$sdk" --licenses | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'sdkmanager --licenses failed.' }
        & $manager "--sdk_root=$sdk" 'platforms;android-34' "build-tools;$AndroidBuildToolsVersion" 'ndk;25.2.9519653' | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'sdkmanager installation failed.' }
    }
    return $sdk
}

function Get-TMAndroidBuildTools {
    $candidates = @($env:DELTARUNE_DDD_CH1_ANDROID_BUILD_TOOLS_DIR)
    if ($env:ANDROID_SDK_ROOT) {
        $candidates += Join-Path $env:ANDROID_SDK_ROOT "build-tools\$AndroidBuildToolsVersion"
    }
    if ($env:ANDROID_HOME) {
        $candidates += Join-Path $env:ANDROID_HOME "build-tools\$AndroidBuildToolsVersion"
    }
    $candidates += Join-Path $ToolsDir "android-sdk\build-tools\$AndroidBuildToolsVersion"

    foreach ($configured in $candidates) {
        if ($configured -and (Test-Path -LiteralPath (Join-Path $configured 'zipalign.exe')) -and
            (Test-Path -LiteralPath (Join-Path $configured 'lib\apksigner.jar'))) {
            return $configured
        }
    }

    $major = $AndroidBuildToolsVersion.Split('.')[0]
    $archive = Join-Path $CacheDir "build-tools_r$major-windows.zip"
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-TMDownload "https://dl.google.com/android/repository/build-tools_r$major-windows.zip" $archive
    }
    $destination = Join-Path $AndroidWrapWorkDir "build-tools\$AndroidBuildToolsVersion"
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'zipalign.exe')) -or
        -not (Test-Path -LiteralPath (Join-Path $destination 'lib\apksigner.jar'))) {
        $temporary = "$destination.extract"
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        Expand-TMZip $archive $temporary
        $zipalign = Get-ChildItem -LiteralPath $temporary -Recurse -Filter zipalign.exe -File | Select-Object -First 1
        if (-not $zipalign) {
            throw "Could not find zipalign.exe in $archive"
        }
        if (-not (Test-Path -LiteralPath (Join-Path $zipalign.DirectoryName 'lib\apksigner.jar'))) {
            throw "Could not find apksigner.jar beside zipalign.exe in $archive"
        }
        Remove-Item -LiteralPath $destination -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Move-Item -LiteralPath $zipalign.DirectoryName -Destination $destination
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
    return $destination
}

function Set-TMJavaEnvironment {
    param([Parameter(Mandatory = $true)][string]$JavaHome)

    $env:JAVA_HOME = $JavaHome
    $javaBin = Join-Path $JavaHome 'bin'
    if ($env:Path -notlike "*$javaBin*") {
        $env:Path = "$javaBin;$env:Path"
    }
}

function Get-TMModVersion {
    $match = Select-String -LiteralPath (Join-Path $Root 'mod.json') -Pattern '"version"\s*:\s*"([^"]+)"' |
        Select-Object -First 1
    if (-not $match) { throw 'Could not find mod.json version.' }
    return $match.Matches[0].Groups[1].Value.TrimStart('v')
}

function Build-TMAndroidLove {
    param(
        [Parameter(Mandatory = $true)][string]$WorkDirectory,
        [Parameter(Mandatory = $true)][string]$LoveExecutable
    )

    $loveDirectory = Join-Path $WorkDirectory 'love'
    Remove-Item -LiteralPath $loveDirectory -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $loveDirectory | Out-Null
    $saved = @{}
    foreach ($name in @('LOVE', 'DELTARUNE_DDD_CH1_ANDROID_TOUCH_SKIP_INTRO', 'DELTARUNE_DDD_CH1_BUILD_VARIANTS', 'DELTARUNE_DDD_CH1_OUTPUT_DIR', 'DELTARUNE_DDD_CH1_NO_OPEN_DIR')) {
        $saved[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        $env:LOVE = $LoveExecutable
        $env:DELTARUNE_DDD_CH1_ANDROID_TOUCH_SKIP_INTRO = '1'
        $env:DELTARUNE_DDD_CH1_BUILD_VARIANTS = 'release'
        $env:DELTARUNE_DDD_CH1_OUTPUT_DIR = $loveDirectory
        $env:DELTARUNE_DDD_CH1_NO_OPEN_DIR = '1'
        & (Join-Path $PSScriptRoot 'build.ps1') -Target love | Out-Host
    } finally {
        foreach ($name in $saved.Keys) {
            [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
        }
    }
    $love = Join-Path $loveDirectory "$OutputBasename-release.love"
    if (-not (Test-Path -LiteralPath $love) -or (Get-Item -LiteralPath $love).Length -eq 0) {
        throw "Release LÖVE archive was not created: $love"
    }
    return $love
}

function Get-TMEmbedApk {
    $explicit = $env:DELTARUNE_DDD_CH1_ANDROID_EMBED_APK
    if ($explicit) {
        if (-not (Test-Path -LiteralPath $explicit)) { throw "Embed APK does not exist: $explicit" }
        return [System.IO.Path]::GetFullPath($explicit)
    }
    $url = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_EMBED_APK_URL' 'https://github.com/love2d/love-android/releases/download/11.5a/love-11.5-android-embed.apk'
    $apk = Join-Path $CacheDir (Split-Path -Leaf $url)
    if (-not (Test-Path -LiteralPath $apk)) {
        Invoke-TMDownload $url $apk
    }
    $expected = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_EMBED_APK_SHA256' 'dcf71c1b54c5b5a09598ef1e6cf4852ced5e5e612de3d0f30cfdd39b5014e889'
    if ($expected) {
        $actual = Get-TMFileSha256 $apk
        if ($actual -ne $expected.ToLowerInvariant()) {
            throw "Embed APK checksum mismatch: expected $expected, got $actual"
        }
    }
    return $apk
}

function Set-TMEmbedGameLove {
    param(
        [Parameter(Mandatory = $true)][string]$Apk,
        [Parameter(Mandatory = $true)][string]$LoveArchive
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    Add-Type -AssemblyName System.IO.Compression
    $zip = [System.IO.Compression.ZipFile]::Open($Apk, [System.IO.Compression.ZipArchiveMode]::Update)
    try {
        $existing = $zip.GetEntry('assets/game.love')
        if ($existing) { $existing.Delete() }
        $entry = $zip.CreateEntry('assets/game.love', [System.IO.Compression.CompressionLevel]::Optimal)
        $output = $entry.Open()
        try {
            $input = [System.IO.File]::OpenRead($LoveArchive)
            try { $input.CopyTo($output) } finally { $input.Dispose() }
        } finally {
            $output.Dispose()
        }
    } finally {
        $zip.Dispose()
    }
}

function Get-TMAndroidSigning {
    param(
        [Parameter(Mandatory = $true)][string]$WorkDirectory,
        [Parameter(Mandatory = $true)][string]$JavaHome
    )

    if ($env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE) {
        foreach ($name in @(
            'DELTARUNE_DDD_CH1_ANDROID_SIGNING_STORE_PASSWORD',
            'DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_ALIAS',
            'DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_PASSWORD'
        )) {
            if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
                throw "$name is required with DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE."
            }
        }
        if (-not (Test-Path -LiteralPath $env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE)) {
            throw "Android signing keystore does not exist: $env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE"
        }
        return [PSCustomObject]@{
            Path = [System.IO.Path]::GetFullPath($env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEYSTORE)
            StorePassword = $env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_STORE_PASSWORD
            Alias = $env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_ALIAS
            KeyPassword = $env:DELTARUNE_DDD_CH1_ANDROID_SIGNING_KEY_PASSWORD
        }
    }

    New-Item -ItemType Directory -Force -Path $WorkDirectory | Out-Null
    $keystore = Join-Path $WorkDirectory 'debug.keystore'
    if (-not (Test-Path -LiteralPath $keystore)) {
        $keytool = Join-Path $JavaHome 'bin\keytool.exe'
        Invoke-TMNative $keytool @(
            '-genkeypair', '-keystore', $keystore, '-alias', 'androiddebugkey',
            '-storepass', 'android', '-keypass', 'android',
            '-dname', 'CN=Android Debug,O=Android,C=US',
            '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000'
        )
    }
    return [PSCustomObject]@{
        Path = $keystore
        StorePassword = 'android'
        Alias = 'androiddebugkey'
        KeyPassword = 'android'
    }
}

function Build-TMAndroidWrap {
    param(
        [Parameter(Mandatory = $true)][string]$JavaHome,
        [Parameter(Mandatory = $true)][string]$LoveExecutable
    )

    $love = Build-TMAndroidLove $AndroidWrapWorkDir $LoveExecutable
    $embed = Get-TMEmbedApk
    $buildTools = Get-TMAndroidBuildTools
    $unsigned = Join-Path $AndroidWrapWorkDir 'unsigned.apk'
    $aligned = Join-Path $AndroidWrapWorkDir 'aligned.apk'
    New-Item -ItemType Directory -Force -Path $AndroidWrapWorkDir, $OutputDir | Out-Null
    Copy-Item -LiteralPath $embed -Destination $unsigned -Force
    Set-TMEmbedGameLove $unsigned $love
    Invoke-TMNative (Join-Path $buildTools 'zipalign.exe') @('-f', '4', $unsigned, $aligned)
    $signing = Get-TMAndroidSigning $AndroidWrapWorkDir $JavaHome
    $output = Join-Path $OutputDir "$OutputBasename-android-wrap.apk"
    $java = Join-Path $JavaHome 'bin\java.exe'
    Invoke-TMNative $java @(
        '-jar', (Join-Path $buildTools 'lib\apksigner.jar'), 'sign',
        '--ks', $signing.Path,
        '--ks-pass', "pass:$($signing.StorePassword)",
        '--ks-key-alias', $signing.Alias,
        '--key-pass', "pass:$($signing.KeyPassword)",
        '--v4-signing-enabled', 'false', '--out', $output, $aligned
    )
    Invoke-TMNative $java @('-jar', (Join-Path $buildTools 'lib\apksigner.jar'), 'verify', $output)
    Write-TMInfo "Created Android wrapper APK: $output"
}

function Test-TMGitReference {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Reference
    )
    $git = Get-TMAndroidGit
    & $git -C $Directory rev-parse --verify --quiet ($Reference + '^{commit}') *> $null
    return $LASTEXITCODE -eq 0
}

function Get-TMLoveAndroidSource {
    $git = Get-TMAndroidGit
    $repository = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_REPO' 'https://github.com/love2d/love-android.git'
    $reference = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_REF' '11.5'
    $cache = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_CACHE_DIR' (Join-Path $CacheDir 'love-android-11.5')
    if (Test-Path -LiteralPath $cache) {
        if (-not (Test-Path -LiteralPath (Join-Path $cache '.git'))) {
            throw "Android source cache exists but is not a Git checkout: $cache"
        }
        if (-not (Test-TMGitReference $cache $reference)) {
            Invoke-TMNative $git @('-C', $cache, 'fetch', '--depth', '1', 'origin', ("refs/tags/$reference:refs/tags/$reference"))
        }
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cache) | Out-Null
        Invoke-TMNative $git @('clone', '--recurse-submodules', '--depth', '1', '--branch', $reference, $repository, $cache)
    }
    Invoke-TMNative $git @('-C', $cache, 'checkout', '--detach', $reference)
    Invoke-TMNative $git @('-C', $cache, 'submodule', 'update', '--init', '--recursive')
    return $cache
}

function Copy-TMAndroidSource {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Remove-Item -LiteralPath $Destination -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $robocopy = Get-TMCommand 'robocopy.exe'
    & $robocopy $Source $Destination /E /COPY:DAT /DCOPY:T /R:1 /W:1 /NFL /NDL /NJH /NJS /XD (Join-Path $Source '.git') /XF .git | Out-Null
    if ($LASTEXITCODE -gt 7) { throw "robocopy failed with exit code $LASTEXITCODE." }
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.git' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
    Get-ChildItem -LiteralPath $Destination -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.git' } |
        Remove-Item -Force
}

function Get-TMAndroidDensityDpi {
    param([Parameter(Mandatory = $true)][string]$Density)
    switch ($Density) {
        'ldpi' { return 120 }
        'mdpi' { return 160 }
        'hdpi' { return 240 }
        'xhdpi' { return 320 }
        'xxhdpi' { return 480 }
        'xxxhdpi' { return 640 }
        default { throw "Unknown Android density: $Density" }
    }
}

function Stage-TMAndroidIcons {
    param([Parameter(Mandatory = $true)][string]$StageDirectory)

    $iconDirectory = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_ICON_DIR' (Join-Path $Root 'assets\icon\android')
    $singleIcon = $env:DELTARUNE_DDD_CH1_ANDROID_ICON
    $densities = @('ldpi', 'mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi')
    $available = @($densities | Where-Object { Test-Path -LiteralPath (Join-Path $iconDirectory "$_.png") })
    if ($available.Count -eq 0 -and $singleIcon) {
        if (-not (Test-Path -LiteralPath $singleIcon)) { throw "Android icon does not exist: $singleIcon" }
        $available = $null
    }
    foreach ($density in $densities) {
        if ($available) {
            $targetDpi = Get-TMAndroidDensityDpi $density
            $sourceDensity = $available | Sort-Object {
                [Math]::Abs((Get-TMAndroidDensityDpi $_) - $targetDpi)
            } | Select-Object -First 1
            $source = Join-Path $iconDirectory "$sourceDensity.png"
        } elseif ($singleIcon) {
            $source = $singleIcon
        } else {
            continue
        }
        $targetDirectory = Join-Path $StageDirectory "app\src\main\res\drawable-$density"
        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
        Copy-Item -LiteralPath $source -Destination (Join-Path $targetDirectory 'love.png') -Force
    }
}

function Get-TMAndroidCompileSettings {
    $applicationId = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_APPLICATION_ID' 'org.deltarunedddch1.template'
    $name = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_NAME' 'deltarune-ddd-ch1'
    $orientation = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_ORIENTATION' 'landscape'
    $versionCode = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ANDROID_VERSION_CODE' '1'
    $versionName = if ($env:DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME) {
        $env:DELTARUNE_DDD_CH1_ANDROID_VERSION_NAME
    } else {
        Get-TMModVersion
    }
    if ($applicationId -notmatch '^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$') {
        throw "Invalid Android application id: $applicationId"
    }
    if ([string]::IsNullOrWhiteSpace($name)) { throw 'Android application name cannot be empty.' }
    if ($orientation -notin @('landscape', 'portrait', 'sensorLandscape', 'sensorPortrait')) {
        throw "Unsupported Android orientation: $orientation"
    }
    if ($versionCode -notmatch '^[1-9][0-9]*$') { throw 'Android version code must be a positive integer.' }
    if ([string]::IsNullOrWhiteSpace($versionName)) { throw 'Android version name cannot be empty.' }
    return [PSCustomObject]@{
        ApplicationId = $applicationId
        Name = $name
        Orientation = $orientation
        VersionCode = $versionCode
        VersionName = $versionName
    }
}

function Build-TMAndroidCompile {
    param(
        [Parameter(Mandatory = $true)][string]$JavaHome,
        [Parameter(Mandatory = $true)][string]$LoveExecutable
    )

    $sdk = Get-TMAndroidSdk $JavaHome
    Set-TMJavaEnvironment $JavaHome
    $env:ANDROID_SDK_ROOT = $sdk
    $source = Get-TMLoveAndroidSource
    $stage = Join-Path $AndroidWorkDir 'project'
    $love = Build-TMAndroidLove $AndroidWorkDir $LoveExecutable
    Copy-TMAndroidSource $source $stage
    $embeddedLove = Join-Path $stage 'app\src\embed\assets\game.love'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $embeddedLove) | Out-Null
    Copy-Item -LiteralPath $love -Destination $embeddedLove -Force
    Stage-TMAndroidIcons $stage
    $settings = Get-TMAndroidCompileSettings
    Invoke-TMBuildHelper $Root $LoveExecutable @(
        'patch-android-properties', (Join-Path $stage 'gradle.properties'),
        $settings.ApplicationId, $settings.Name, $settings.Orientation,
        $settings.VersionCode, $settings.VersionName
    )
    Invoke-TMBuildHelper $Root $LoveExecutable @('patch-android-gradle', (Join-Path $stage 'app\build.gradle'))
    Invoke-TMBuildHelper $Root $LoveExecutable @(
        'patch-android-game-activity', (Join-Path $stage 'love\src\main\java\org\love2d\android\GameActivity.java')
    )
    Invoke-TMBuildHelper $Root $LoveExecutable @('patch-android-local-properties', (Join-Path $stage 'local.properties'), $sdk)
    $gradle = Join-Path $stage 'gradlew.bat'
    Push-Location -LiteralPath $stage
    try {
        Invoke-TMNative $gradle @('--no-daemon', 'assembleEmbedNoRecordRelease')
    } finally {
        Pop-Location
    }
    $apk = Get-ChildItem -LiteralPath (Join-Path $stage 'app\build\outputs\apk') -Recurse -Filter '*.apk' -File |
        Where-Object { $_.FullName -match '[\\/]embedNoRecord[\\/]release[\\/]' } |
        Sort-Object LastWriteTime | Select-Object -Last 1
    if (-not $apk) { throw 'Gradle completed without producing an APK.' }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    $output = Join-Path $OutputDir "$OutputBasename-android.apk"
    Copy-Item -LiteralPath $apk.FullName -Destination $output -Force
    Invoke-TMNative (Join-Path $JavaHome 'bin\java.exe') @(
        '-jar', (Join-Path $sdk "build-tools\$AndroidBuildToolsVersion\lib\apksigner.jar"), 'verify', $output
    )
    Write-TMInfo "Created Android APK: $output"
}

if ($Mode -eq 'menu') {
    Write-Host ''
    Write-Host 'deltarune-ddd-ch1 Android packaging'
    Write-Host '  1) Wrap build: official LÖVE APK plus game.love'
    Write-Host '  2) Compile build: source build with Android SDK and NDK'
    Write-Host ''
    $choice = Read-Host 'Choose 1 or 2'
    $Mode = if ($choice -eq '2') { 'compile' } else { 'wrap' }
}

$JavaHome = Get-TMJavaHome
Set-TMJavaEnvironment $JavaHome
$LoveExecutable = Get-TMLoveExecutable $ToolsDir -DownloadIfMissing
if ($Mode -eq 'compile') {
    Build-TMAndroidCompile $JavaHome $LoveExecutable
} else {
    Build-TMAndroidWrap $JavaHome $LoveExecutable
}
Open-TMOutputDirectory $OutputDir
