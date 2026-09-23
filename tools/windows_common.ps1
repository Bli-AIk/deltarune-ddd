# Shared native Windows primitives for the project build entry points.
# Keep policy in the caller: this file only resolves tools, downloads files,
# and invokes the repository-local Lua helper.

function Get-TMEnvOrDefault {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Default
    )

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }
    return $value
}

function Write-TMInfo {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[build] $Message"
}

function Write-TMWarn {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[warning] $Message" -ForegroundColor Yellow
}

function Find-TMCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    # GitHub's Windows image can expose the same executable from both
    # system and Git locations. Keep a single command object for callers.
    $commands = @(Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue)
    if ($commands.Count -eq 0) {
        return $null
    }
    return $commands[0]
}

function Get-TMCommand {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Find-TMCommand $Name
    if ($null -eq $command) {
        throw "Missing required command: $Name"
    }
    return $command.Source
}

function Invoke-TMNative {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @()
    )

    # Keep native stdout visible without allowing it to become a function's
    # return value. Callers such as Resolve-TMKristal return paths/objects.
    & $File @Arguments | Out-Host
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Command failed with exit code ${exitCode}: $File"
    }
}

function Invoke-TMDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutputFile
    )

    $parent = Split-Path -Parent $OutputFile
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-TMInfo "Downloading $(Split-Path -Leaf $OutputFile)"

    $curl = Find-TMCommand 'curl.exe'
    if ($curl) {
        & $curl.Source --fail --location --retry 3 --output $OutputFile $Url | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Remove-Item -LiteralPath $OutputFile -Force -ErrorAction SilentlyContinue
            throw "Download failed: $Url"
        }
    } else {
        $previousProgressPreference = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $OutputFile
        } finally {
            $ProgressPreference = $previousProgressPreference
        }
    }

    if (-not (Test-Path -LiteralPath $OutputFile) -or (Get-Item -LiteralPath $OutputFile).Length -eq 0) {
        throw "Download did not produce a file: $Url"
    }
}

function Get-TMFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    $algorithm = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $algorithm = [System.Security.Cryptography.SHA256]::Create()
        $hash = $algorithm.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        if ($null -ne $algorithm) { $algorithm.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Expand-TMZip {
    param(
        [Parameter(Mandatory = $true)][string]$Archive,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
}

function Get-TMSharedToolsDir {
    param([Parameter(Mandatory = $true)][string]$Root)

    if ($env:DELTARUNE_DDD_CH1_TOOLS_DIR) {
        return [System.IO.Path]::GetFullPath($env:DELTARUNE_DDD_CH1_TOOLS_DIR)
    }

    $candidate = [System.IO.Path]::GetFullPath($Root)
    while ($true) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'main.lua')) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'src\kristal.lua'))) {
            return Join-Path $candidate '.tools'
        }
        $parent = [System.IO.Directory]::GetParent($candidate)
        if ($null -eq $parent) {
            break
        }
        $candidate = $parent.FullName
    }

    $projectLocalKristal = [System.IO.Path]::GetFullPath((Join-Path $Root '.build\Kristal'))
    foreach ($engine in @($env:DELTARUNE_DDD_CH1_KRISTAL_DIR, $env:KRISTAL_ROOT)) {
        if (-not $engine) {
            continue
        }
        $resolvedEngine = [System.IO.Path]::GetFullPath($engine)
        if ($resolvedEngine -ieq $projectLocalKristal) {
            continue
        }
        if (Test-Path -LiteralPath (Join-Path $resolvedEngine 'main.lua')) {
            return Join-Path $resolvedEngine '.tools'
        }
    }
    return Join-Path $Root '.tools'
}

function Get-TMLoveExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$ToolsDir,
        [switch]$DownloadIfMissing
    )

    if ($env:LOVE) {
        if (Test-Path -LiteralPath $env:LOVE) {
            return [System.IO.Path]::GetFullPath($env:LOVE)
        }
        $configuredCommand = Find-TMCommand $env:LOVE
        if ($configuredCommand) {
            return $configuredCommand.Source
        }
        throw "LOVE points to a missing executable: $env:LOVE"
    }

    foreach ($name in @('love.exe', 'love')) {
        $command = Find-TMCommand $name
        if ($command) {
            return $command.Source
        }
    }

    $candidates = @()
    if ($env:ProgramFiles) {
        $candidates += Join-Path $env:ProgramFiles 'LOVE\love.exe'
    }
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA 'Programs\LOVE\love.exe'
    }
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    if (-not $DownloadIfMissing) {
        throw 'Missing LÖVE. Install LÖVE 11.5 or set LOVE to love.exe.'
    }

    $archive = Join-Path $ToolsDir 'love-11.5-win64.zip'
    $extractRoot = Join-Path $ToolsDir 'love-11.5-win64'
    if (-not (Test-Path -LiteralPath $archive)) {
        Invoke-TMDownload 'https://github.com/love2d/love/releases/download/11.5/love-11.5-win64.zip' $archive
    }
    if (-not (Test-Path -LiteralPath (Join-Path $extractRoot 'love.exe'))) {
        $temporary = "$extractRoot.extract"
        Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
        Expand-TMZip $archive $temporary
        $inner = Get-ChildItem -LiteralPath $temporary -Directory | Select-Object -First 1
        if (-not $inner -or -not (Test-Path -LiteralPath (Join-Path $inner.FullName 'love.exe'))) {
            throw "Could not find love.exe in $archive"
        }
        Remove-Item -LiteralPath $extractRoot -Recurse -Force -ErrorAction SilentlyContinue
        Move-Item -LiteralPath $inner.FullName -Destination $extractRoot
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
    return Join-Path $extractRoot 'love.exe'
}

function Invoke-TMBuildHelper {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LoveExecutable,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string[]]$Arguments
    )

    foreach ($argument in $Arguments) {
        if ($argument.Contains("`n") -or $argument.Contains("`r")) {
            throw 'Build-helper arguments cannot contain newlines.'
        }
    }

    $argumentsFile = [System.IO.Path]::GetTempFileName()
    $previousArgumentsFile = $env:DELTARUNE_DDD_CH1_HELPER_ARGS
    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($argumentsFile, (($Arguments -join "`n") + "`n"), $encoding)
        $env:DELTARUNE_DDD_CH1_HELPER_ARGS = $argumentsFile
        & $LoveExecutable (Join-Path $Root 'build-helper') | Out-Host
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) {
            throw "Build helper failed with exit code $exitCode."
        }
    } finally {
        Remove-Item -LiteralPath $argumentsFile -Force -ErrorAction SilentlyContinue
        if ($null -eq $previousArgumentsFile) {
            Remove-Item Env:DELTARUNE_DDD_CH1_HELPER_ARGS -ErrorAction SilentlyContinue
        } else {
            $env:DELTARUNE_DDD_CH1_HELPER_ARGS = $previousArgumentsFile
        }
    }
}

function Open-TMOutputDirectory {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if ($env:DELTARUNE_DDD_CH1_NO_OPEN_DIR -eq '1') {
        return
    }
    Invoke-Item -LiteralPath $Directory
}
