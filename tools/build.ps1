<#
Native Windows packaging entry point.

    tools\build.cmd all
    tools\build.cmd love
    tools\build.cmd win
    tools\build.cmd mod

POSIX packaging remains in build_standalone.sh and .github/scripts/build_mod.sh.
This script intentionally shares only manifest parsing and archive creation with
them through build-helper; Windows process and filesystem work stays native.
#>

[CmdletBinding()]
param(
    [ValidateSet('all', 'love', 'win', 'mod')]
    [string]$Target = 'all'
)

$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $PSScriptRoot 'windows_common.ps1')

$ToolsDir = Get-TMSharedToolsDir $Root
$BuildRoot = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_BUILD_ROOT' (Join-Path $Root '.build\standalone')
$OutputDir = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_OUTPUT_DIR' (Join-Path $Root 'dist')
$CacheDir = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_CACHE_DIR' (Join-Path $Root '.build\cache')
$ModId = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_MOD_ID' 'deltarune-ddd-ch1'
$ProjectTitle = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_PROJECT_TITLE' 'deltarune-ddd-ch1'
$OutputBasename = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_OUTPUT_BASENAME' 'deltarune-ddd-ch1'
$ExeBasename = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_EXE_BASENAME' 'DELTARUNE-DDD-CH1'
$LoveVersion = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_LOVE_VERSION' '11.5'
$LoveArch = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_LOVE_ARCH' 'win64'
$script:TMGit = $null

function Get-TMGit {
    if (-not $script:TMGit) {
        $script:TMGit = Get-TMCommand 'git.exe'
    }
    return $script:TMGit
}

function Test-TMGitWorkTree {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (-not (Test-Path -LiteralPath (Join-Path $Directory '.git'))) {
        return $false
    }
    $git = Get-TMGit
    & $git -C $Directory rev-parse --is-inside-work-tree *> $null
    return $LASTEXITCODE -eq 0
}

function Test-TMGitReference {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Reference
    )

    $git = Get-TMGit
    & $git -C $Directory rev-parse --verify --quiet ($Reference + '^{commit}') *> $null
    return $LASTEXITCODE -eq 0
}

function Find-TMLocalKristal {
    $candidate = $Root
    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'main.lua')) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'src\kristal.lua'))) {
            return $candidate
        }
        $parent = [System.IO.Directory]::GetParent($candidate)
        if ($null -eq $parent) {
            break
        }
        $candidate = $parent.FullName
    }

    foreach ($configured in @($env:DELTARUNE_DDD_CH1_KRISTAL_DIR, $env:KRISTAL_ROOT)) {
        if ($configured -and (Test-Path -LiteralPath (Join-Path $configured 'main.lua'))) {
            return [System.IO.Path]::GetFullPath($configured)
        }
    }

    $candidates = @(Join-Path $Root '.build\Kristal')
    $parentRoot = [System.IO.Directory]::GetParent($Root)
    if ($parentRoot) {
        $candidates += Join-Path $parentRoot.FullName 'Kristal'
        $candidates += Join-Path $parentRoot.FullName 'kristal'
    }
    if ($env:USERPROFILE) {
        $candidates += Join-Path $env:USERPROFILE 'Kristal'
        $candidates += Join-Path $env:USERPROFILE 'kristal'
    }
    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath (Join-Path $candidate 'main.lua'))) {
            return [System.IO.Path]::GetFullPath($candidate)
        }
    }
    return $null
}

function Invoke-TMFetchKristalReference {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Reference
    )

    $git = Get-TMGit
    if ($Source -eq 'tag') {
        Invoke-TMNative $git @('-C', $Directory, 'fetch', '--depth', '1', 'origin', ("refs/tags/$Reference:refs/tags/$Reference"))
    } elseif ($Source -eq 'branch') {
        Invoke-TMNative $git @('-C', $Directory, 'fetch', '--depth', '1', 'origin', ("+refs/heads/$Reference:refs/heads/$Reference"))
    } else {
        Invoke-TMNative $git @('-C', $Directory, 'fetch', '--depth', '1', 'origin', $Reference)
    }
}

function Resolve-TMKristal {
    $pinnedReference = '8e592d84065263138d4e92593f0a4ab780d93822'
    $configuredReference = $env:DELTARUNE_DDD_CH1_KRISTAL_REF
    $reference = if ($configuredReference) { $configuredReference } else { $pinnedReference }
    $source = $env:DELTARUNE_DDD_CH1_KRISTAL_SOURCE
    $configuredDirectory = if ($env:DELTARUNE_DDD_CH1_KRISTAL_DIR) {
        $env:DELTARUNE_DDD_CH1_KRISTAL_DIR
    } elseif ($env:KRISTAL_ROOT) {
        $env:KRISTAL_ROOT
    } else {
        $null
    }

    if ($source -eq 'ask') {
        $local = Find-TMLocalKristal
        if ($local) {
            $answer = Read-Host "Use local Kristal at $local? [Y/n]"
            if ($answer -notmatch '^[Nn]') {
                $source = 'local'
                $configuredDirectory = $local
                if (-not $configuredReference) { $reference = 'HEAD' }
            } else {
                $source = 'commit'
            }
        } else {
            $source = 'commit'
        }
    }

    if (-not $source) {
        if ($configuredReference -and $configuredReference -ne $pinnedReference) {
            if ($configuredReference -match '^[0-9a-fA-F]{40}$') {
                $source = 'commit'
            } else {
                $source = 'tag'
            }
        } elseif ($configuredDirectory) {
            $source = 'local'
            if (-not $configuredReference) { $reference = 'HEAD' }
        } else {
            $source = 'commit'
        }
    }

    if ($source -notin @('local', 'path', 'commit', 'tag', 'branch')) {
        throw "Unknown DELTARUNE_DDD_CH1_KRISTAL_SOURCE: $source"
    }
    if ($source -eq 'commit' -and $reference -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'DELTARUNE_DDD_CH1_KRISTAL_SOURCE=commit requires a 40-character DELTARUNE_DDD_CH1_KRISTAL_REF.'
    }
    if ($source -in @('tag', 'branch') -and [string]::IsNullOrWhiteSpace($reference)) {
        throw "DELTARUNE_DDD_CH1_KRISTAL_SOURCE=$source requires DELTARUNE_DDD_CH1_KRISTAL_REF."
    }

    if ($source -in @('local', 'path')) {
        $directory = if ($configuredDirectory) { $configuredDirectory } else { Find-TMLocalKristal }
        if (-not $directory -or -not (Test-Path -LiteralPath (Join-Path $directory 'main.lua'))) {
            throw 'No usable local Kristal checkout was found. Set DELTARUNE_DDD_CH1_KRISTAL_DIR or use the default pinned source.'
        }
        $directory = [System.IO.Path]::GetFullPath($directory)
        $isGit = Test-TMGitWorkTree $directory
        if ($isGit -and -not (Test-TMGitReference $directory $reference)) {
            throw "Local Kristal checkout does not contain ${reference}: $directory"
        }
    } else {
        $git = Get-TMGit
        $directory = if ($configuredDirectory) {
            [System.IO.Path]::GetFullPath($configuredDirectory)
        } else {
            Join-Path $Root '.build\Kristal'
        }
        if (Test-Path -LiteralPath $directory) {
            if (-not (Test-TMGitWorkTree $directory)) {
                throw "Kristal path exists but is not a Git checkout: $directory"
            }
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $directory) | Out-Null
            Invoke-TMNative $git @('init', '-q', $directory)
            Invoke-TMNative $git @('-C', $directory, 'remote', 'add', 'origin', (Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_KRISTAL_REPO' 'https://github.com/KristalTeam/Kristal.git'))
        }

        if (($source -eq 'branch') -or -not (Test-TMGitReference $directory $reference)) {
            Write-TMInfo "Fetching Kristal $source $reference"
            Invoke-TMFetchKristalReference $directory $source $reference
        } elseif ($env:DELTARUNE_DDD_CH1_UPDATE_REPOS -eq '1') {
            Invoke-TMNative $git @('-C', $directory, 'fetch', '--depth', '1', '--tags', 'origin')
        }
        Invoke-TMNative $git @('-C', $directory, '-c', 'advice.detachedHead=false', 'checkout', '--detach', $reference)
        $isGit = $true
    }

    $expectedVersion = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_KRISTAL_EXPECTED_VERSION' '0.11.0-dev'
    $verifyVersion = if ($null -ne $env:DELTARUNE_DDD_CH1_KRISTAL_VERIFY_VERSION) {
        $env:DELTARUNE_DDD_CH1_KRISTAL_VERIFY_VERSION -eq '1'
    } else {
        $source -eq 'commit' -and $reference -eq $pinnedReference
    }
    if ($isGit) {
        $git = Get-TMGit
        $version = (& $git -C $directory show ($reference + ':VERSION')).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read VERSION from Kristal $reference."
        }
    } else {
        $version = (Get-Content -LiteralPath (Join-Path $directory 'VERSION') -TotalCount 1).Trim()
    }
    if ($verifyVersion -and $version -ne $expectedVersion) {
        throw "Kristal $reference reports VERSION=$version, expected $expectedVersion."
    }

    return [PSCustomObject]@{
        Directory = $directory
        Reference = $reference
        IsGit = $isGit
    }
}

function Invoke-TMRobocopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string[]]$ExcludeDirectories = @(),
        [string[]]$ExcludeFiles = @()
    )

    $robocopy = Get-TMCommand 'robocopy.exe'
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    $arguments = @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:T', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS')
    if ($ExcludeDirectories.Count -gt 0) {
        $arguments += '/XD'
        $arguments += $ExcludeDirectories
    }
    if ($ExcludeFiles.Count -gt 0) {
        $arguments += '/XF'
        $arguments += $ExcludeFiles
    }
    & $robocopy @arguments | Out-Null
    if ($LASTEXITCODE -gt 7) {
        throw "robocopy failed with exit code $LASTEXITCODE."
    }
}

function Remove-TMPathIfPresent {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Remove-TMMetadataDirectories {
    param([Parameter(Mandatory = $true)][string]$Directory)

    Get-ChildItem -LiteralPath $Directory -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in @('.git', '.github', '.claude') } |
        ForEach-Object { Remove-TMPathIfPresent $_.FullName }
    Get-ChildItem -LiteralPath $Directory -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq '.git' } |
        Remove-Item -Force
}

function Export-TMKristal {
    param(
        [Parameter(Mandatory = $true)]$Kristal,
        [Parameter(Mandatory = $true)][string]$StageDirectory
    )

    Remove-TMPathIfPresent $StageDirectory
    New-Item -ItemType Directory -Force -Path $StageDirectory | Out-Null
    if ($Kristal.IsGit) {
        $git = Get-TMGit
        $archive = Join-Path (Split-Path -Parent $StageDirectory) 'kristal-source.zip'
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Invoke-TMNative $git @('-C', $Kristal.Directory, 'archive', '--format=zip', "--output=$archive", $Kristal.Reference)
        Expand-TMZip $archive $StageDirectory
        Remove-Item -LiteralPath $archive -Force
    } else {
        Invoke-TMRobocopy $Kristal.Directory $StageDirectory @(
            (Join-Path $Kristal.Directory '.git'),
            (Join-Path $Kristal.Directory 'mods'),
            (Join-Path $Kristal.Directory '.tools'),
            (Join-Path $Kristal.Directory '.build')
        ) @('.git')
    }
    Remove-TMPathIfPresent (Join-Path $StageDirectory '.github')
    Remove-TMPathIfPresent (Join-Path $StageDirectory 'mods')
    Remove-TMPathIfPresent (Join-Path $StageDirectory 'build')
    Remove-TMPathIfPresent (Join-Path $StageDirectory 'output')
}

function Copy-TMModTree {
    param([Parameter(Mandatory = $true)][string]$Destination)

    $excludedDirectories = @(
        (Join-Path $Root '.git'),
        (Join-Path $Root '.github'),
        (Join-Path $Root '.claude'),
        (Join-Path $Root '.build'),
        (Join-Path $Root '.tools'),
        (Join-Path $Root '.emacs'),
        (Join-Path $Root '.helix'),
        (Join-Path $Root '.vscode'),
        (Join-Path $Root '.worktrees'),
        (Join-Path $Root 'tests'),
        (Join-Path $Root 'docs'),
        (Join-Path $Root 'tools'),
        (Join-Path $Root 'build-helper'),
        (Join-Path $Root '__pycache__'),
        (Join-Path $Root 'assets\icon')
    )
    Get-ChildItem -LiteralPath $Root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'dist*' } |
        ForEach-Object { $excludedDirectories += $_.FullName }

    Invoke-TMRobocopy $Root $Destination $excludedDirectories @(
        '.git', 'Makefile', 'justfile', 'release-please-config.json',
        '.release-please-manifest.json', '.gitmodules', '.gitignore',
        '*.pyc', '*.pyo', '*.tiled-project', '*.tiled-session'
    )
    Remove-Item -LiteralPath (Join-Path $Destination 'gui.cmd') -Force -ErrorAction SilentlyContinue
    Remove-TMPathIfPresent (Join-Path $Destination 'libraries\kristal-debug-tools\gui')
    Remove-TMPathIfPresent (Join-Path $Destination 'libraries\kristal-debug-tools-gui')
    Remove-TMPathIfPresent (Join-Path $Destination 'libraries\kristal-debug-tools\dist')
    Remove-TMPathIfPresent (Join-Path $Destination 'libraries\kristal-debug-tools\.tools')
    Remove-Item -LiteralPath (Join-Path $Destination 'libraries\kristal-debug-tools\just.cmd') -Force -ErrorAction SilentlyContinue
    Remove-TMMetadataDirectories $Destination
}

function Invoke-TMReleaseLibraryPrune {
    param(
        [Parameter(Mandatory = $true)][string]$StageMod,
        [Parameter(Mandatory = $true)][string]$LoveExecutable
    )

    $plan = [System.IO.Path]::GetTempFileName()
    try {
        Invoke-TMBuildHelper $Root $LoveExecutable @('plan-release-libraries', $StageMod, $plan)
        foreach ($entry in [System.IO.File]::ReadAllLines($plan)) {
            if ([string]::IsNullOrWhiteSpace($entry) -or $entry -in @('.', '..') -or
                $entry -match '[\\/\r\n]') {
                throw "Unsafe library directory in release plan: $entry"
            }
            $target = Join-Path (Join-Path $StageMod 'libraries') $entry
            Remove-TMPathIfPresent $target
        }
    } finally {
        Remove-Item -LiteralPath $plan -Force -ErrorAction SilentlyContinue
    }
}

function Stage-TMWindowIcon {
    param(
        [Parameter(Mandatory = $true)][string]$StageMod,
        [Parameter(Mandatory = $true)][string]$LoveExecutable
    )

    $iconDirectory = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ICON_DIR' (Join-Path $Root 'assets\icon')
    $windowIcon = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_WINDOW_ICON' (Join-Path $iconDirectory 'window_icon.png')
    if (Test-Path -LiteralPath $windowIcon) {
        Copy-Item -LiteralPath $windowIcon -Destination (Join-Path $StageMod 'window_icon.png') -Force
        Invoke-TMBuildHelper $Root $LoveExecutable @('set-mod-json-flag', (Join-Path $StageMod 'mod.json'), 'setWindowTitleAndIcon', 'true')
    }
}

function Prepare-TMStandaloneStage {
    param(
        [Parameter(Mandatory = $true)]$Kristal,
        [Parameter(Mandatory = $true)][string]$Variant,
        [Parameter(Mandatory = $true)][string]$LoveExecutable
    )

    $stageDirectory = Join-Path (Join-Path $BuildRoot $Variant) 'source'
    Export-TMKristal $Kristal $stageDirectory
    $stageMod = Join-Path (Join-Path $stageDirectory 'mods') $ModId
    Copy-TMModTree $stageMod

    if ($Variant -eq 'release') {
        Invoke-TMReleaseLibraryPrune $stageMod $LoveExecutable
        $releaseMode = 'true'
        $dev = 'false'
        $objectEditor = 'false'
        $identity = $ModId
        $title = $ProjectTitle
    } elseif ($Variant -eq 'debug') {
        $releaseMode = 'false'
        $dev = 'true'
        $objectEditor = 'true'
        $identity = "$ModId`_debug"
        $title = "$ProjectTitle Debug"
    } else {
        throw "Unknown build variant: $Variant"
    }

    Invoke-TMBuildHelper $Root $LoveExecutable @(
        'patch-lua-config', $stageDirectory, $ModId, $releaseMode, $identity, $title
    )
    if ($env:DELTARUNE_DDD_CH1_ANDROID_TOUCH_SKIP_INTRO -eq '1') {
        Invoke-TMBuildHelper $Root $LoveExecutable @(
            'patch-android-loading-touch', (Join-Path $stageDirectory 'src\engine\loadstate.lua')
        )
    }
    Invoke-TMBuildHelper $Root $LoveExecutable @(
        'patch-mod-manifest', (Join-Path $stageMod 'mod.json'), $dev, $objectEditor
    )
    Stage-TMWindowIcon $stageMod $LoveExecutable
    return $stageDirectory
}

function Ensure-TMWindowsLoveDistribution {
    $url = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_LOVE_WINDOWS_ZIP_URL' "https://github.com/love2d/love/releases/download/$LoveVersion/love-$LoveVersion-$LoveArch.zip"
    $archive = Join-Path $CacheDir "love-$LoveVersion-$LoveArch.zip"
    $destination = Join-Path $CacheDir "love-$LoveVersion-$LoveArch"
    if (-not (Test-Path -LiteralPath $archive) -or (Get-Item -LiteralPath $archive).Length -eq 0) {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        Invoke-TMDownload $url $archive
    }
    if (-not (Test-Path -LiteralPath (Join-Path $destination 'love.exe'))) {
        $temporary = "$destination.extract"
        Remove-TMPathIfPresent $temporary
        Expand-TMZip $archive $temporary
        $inner = Get-ChildItem -LiteralPath $temporary -Directory | Select-Object -First 1
        if (-not $inner -or -not (Test-Path -LiteralPath (Join-Path $inner.FullName 'love.exe'))) {
            Remove-TMPathIfPresent $temporary
            throw "Could not locate love.exe in $archive"
        }
        Remove-TMPathIfPresent $destination
        Move-Item -LiteralPath $inner.FullName -Destination $destination
        Remove-TMPathIfPresent $temporary
    }
    return $destination
}

function Get-TMWindowsIcon {
    param([Parameter(Mandatory = $true)][string]$WorkDirectory)

    $iconDirectory = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_ICON_DIR' (Join-Path $Root 'assets\icon')
    $windowsIconDirectory = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_WIN_ICON_DIR' (Join-Path $iconDirectory 'win')
    $readyIcon = Join-Path $windowsIconDirectory 'icon.ico'
    if (Test-Path -LiteralPath $readyIcon) {
        return $readyIcon
    }

    $pngs = @(Get-ChildItem -LiteralPath $windowsIconDirectory -Filter '*x*.png' -File -ErrorAction SilentlyContinue)
    if ($pngs.Count -eq 0) {
        return $null
    }
    $magick = Find-TMCommand 'magick.exe'
    if (-not $magick) {
        Write-TMWarn 'No icon.ico or ImageMagick found; leaving the default Windows executable icon.'
        return $null
    }
    New-Item -ItemType Directory -Force -Path $WorkDirectory | Out-Null
    $output = Join-Path $WorkDirectory 'game.ico'
    & $magick.Source @($pngs.FullName) $output | Out-Host
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $output)) {
        Write-TMWarn 'ImageMagick could not build a Windows icon; leaving the default executable icon.'
        return $null
    }
    return $output
}

function Get-TMRcedit {
    $configured = $env:DELTARUNE_DDD_CH1_RCEDit
    if ($configured) {
        if (Test-Path -LiteralPath $configured) { return $configured }
        $command = Find-TMCommand $configured
        if ($command) { return $command.Source }
        return $null
    }
    $cached = Join-Path $ToolsDir 'rcedit\rcedit-x64.exe'
    if (Test-Path -LiteralPath $cached) { return $cached }
    $command = Find-TMCommand 'rcedit.exe'
    if ($command) { return $command.Source }
    if ($env:DELTARUNE_DDD_CH1_ICON_FETCH_TOOLS -ne '1') { return $null }
    $url = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_RCEDit_URL' 'https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe'
    Invoke-TMDownload $url $cached
    return $cached
}

function Select-TMExecutableWithIcon {
    param(
        [Parameter(Mandatory = $true)][string]$LoveExecutable,
        [Parameter(Mandatory = $true)][string]$Icon,
        [Parameter(Mandatory = $true)][string]$WorkDirectory
    )

    $rcedit = Get-TMRcedit
    if (-not $rcedit) {
        Write-TMWarn 'rcedit is unavailable; leaving the default Windows executable icon.'
        return $LoveExecutable
    }
    New-Item -ItemType Directory -Force -Path $WorkDirectory | Out-Null
    $candidate = Join-Path $WorkDirectory 'love-icon.exe'
    Copy-Item -LiteralPath $LoveExecutable -Destination $candidate -Force
    $before = Get-TMFileSha256 $candidate
    try {
        & $rcedit $candidate --set-icon $Icon | Out-Host
        if ($LASTEXITCODE -ne 0) {
            throw "rcedit exited with $LASTEXITCODE"
        }
        $after = Get-TMFileSha256 $candidate
        if ($before -eq $after) {
            throw 'rcedit did not modify the executable'
        }
        return $candidate
    } catch {
        Write-TMWarn "Could not set the Windows executable icon: $($_.Exception.Message)"
        return $LoveExecutable
    }
}

function Append-TMFile {
    param(
        [Parameter(Mandatory = $true)][string]$BaseFile,
        [Parameter(Mandatory = $true)][string]$AppendFile,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    Copy-Item -LiteralPath $BaseFile -Destination $OutputFile -Force
    $output = [System.IO.File]::Open($OutputFile, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write)
    try {
        $input = [System.IO.File]::OpenRead($AppendFile)
        try {
            $input.CopyTo($output)
        } finally {
            $input.Dispose()
        }
    } finally {
        $output.Dispose()
    }
}

function Build-TMStandaloneVariant {
    param(
        [Parameter(Mandatory = $true)]$Kristal,
        [Parameter(Mandatory = $true)][string]$Variant,
        [Parameter(Mandatory = $true)][string]$LoveExecutable,
        [Parameter(Mandatory = $true)][bool]$BuildLove,
        [Parameter(Mandatory = $true)][bool]$BuildWindows
    )

    Write-TMInfo "Building $Variant"
    $stageDirectory = Prepare-TMStandaloneStage $Kristal $Variant $LoveExecutable
    $loveOutputDirectory = if ($BuildLove) { $OutputDir } else { Join-Path $BuildRoot 'love' }
    New-Item -ItemType Directory -Force -Path $loveOutputDirectory | Out-Null
    $loveFile = Join-Path $loveOutputDirectory "$OutputBasename-$Variant.love"
    Invoke-TMBuildHelper $Root $LoveExecutable @('zip-dir', $loveFile, $stageDirectory, '')
    if (-not (Test-Path -LiteralPath $loveFile) -or (Get-Item -LiteralPath $loveFile).Length -eq 0) {
        throw "LÖVE archive was not created: $loveFile"
    }

    if ($BuildWindows) {
        $loveDistribution = Ensure-TMWindowsLoveDistribution
        $packageName = "$OutputBasename-$Variant-$LoveArch"
        $packageDirectory = Join-Path $OutputDir $packageName
        Remove-TMPathIfPresent $packageDirectory
        New-Item -ItemType Directory -Force -Path $packageDirectory | Out-Null
        $baseExecutable = Join-Path $loveDistribution 'love.exe'
        $icon = Get-TMWindowsIcon (Join-Path (Join-Path $BuildRoot $Variant) 'icon')
        if ($icon) {
            $baseExecutable = Select-TMExecutableWithIcon $baseExecutable $icon (Join-Path (Join-Path $BuildRoot $Variant) 'icon')
        }
        Append-TMFile $baseExecutable $loveFile (Join-Path $packageDirectory "$ExeBasename-$Variant.exe")
        Get-ChildItem -LiteralPath $loveDistribution -Filter '*.dll' -File | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $packageDirectory -Force
        }
        $license = Join-Path $loveDistribution 'license.txt'
        if (Test-Path -LiteralPath $license) {
            Copy-Item -LiteralPath $license -Destination $packageDirectory -Force
        }
        $packageArchive = Join-Path $OutputDir "$packageName.zip"
        Invoke-TMBuildHelper $Root $LoveExecutable @('zip-dir', $packageArchive, $packageDirectory, $packageName)
        if (-not (Test-Path -LiteralPath $packageArchive) -or (Get-Item -LiteralPath $packageArchive).Length -eq 0) {
            throw "Windows package was not created: $packageArchive"
        }
        Remove-TMPathIfPresent $packageDirectory
    }

    if (-not $BuildLove -and $BuildWindows) {
        Remove-Item -LiteralPath $loveFile -Force
    }
}

function Build-TMModPackage {
    param([Parameter(Mandatory = $true)][string]$LoveExecutable)

    $buildDirectory = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_MOD_BUILD_DIR' (Join-Path $Root '.build\mod')
    $stageDirectory = Join-Path $buildDirectory 'source'
    $outputFile = Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_MOD_OUTPUT_FILE' (Join-Path $OutputDir 'deltarune-ddd-ch1-mod.zip')
    Remove-TMPathIfPresent $stageDirectory
    New-Item -ItemType Directory -Force -Path $stageDirectory | Out-Null
    Copy-TMModTree $stageDirectory
    Invoke-TMReleaseLibraryPrune $stageDirectory $LoveExecutable
    Invoke-TMBuildHelper $Root $LoveExecutable @('patch-mod-manifest', (Join-Path $stageDirectory 'mod.json'), 'false', 'false')
    Stage-TMWindowIcon $stageDirectory $LoveExecutable
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputFile) | Out-Null
    Invoke-TMBuildHelper $Root $LoveExecutable @('zip-dir', $outputFile, $stageDirectory, '')
    if (-not (Test-Path -LiteralPath $outputFile) -or (Get-Item -LiteralPath $outputFile).Length -eq 0) {
        throw "Project package was not created: $outputFile"
    }
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$LoveExecutable = Get-TMLoveExecutable $ToolsDir

if ($Target -eq 'mod') {
    Build-TMModPackage $LoveExecutable
    Write-TMInfo "Created project package in $OutputDir"
    Open-TMOutputDirectory $OutputDir
    exit 0
}

$buildLove = $Target -in @('all', 'love')
$buildWindows = $Target -in @('all', 'win')
$variants = (Get-TMEnvOrDefault 'DELTARUNE_DDD_CH1_BUILD_VARIANTS' 'release debug').Split(@(' ', "`t"), [System.StringSplitOptions]::RemoveEmptyEntries)
if ($variants.Count -eq 0) {
    throw 'DELTARUNE_DDD_CH1_BUILD_VARIANTS must name at least one variant.'
}
$Kristal = Resolve-TMKristal
$currentVariant = $null
try {
    foreach ($variant in $variants) {
        if ($variant -notin @('release', 'debug')) {
            throw "Unknown build variant: $variant"
        }
        $currentVariant = $variant
        Build-TMStandaloneVariant $Kristal $variant $LoveExecutable $buildLove $buildWindows
        $currentVariant = $null
    }
} catch {
    if ($currentVariant) {
        $stem = Join-Path $OutputDir "$OutputBasename-$currentVariant"
        Remove-Item -LiteralPath "$stem.love" -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath "$stem-$LoveArch.zip" -Force -ErrorAction SilentlyContinue
        Remove-TMPathIfPresent "$stem-$LoveArch"
    }
    throw
}

Write-TMInfo "Build complete: $OutputDir"
Open-TMOutputDirectory $OutputDir
