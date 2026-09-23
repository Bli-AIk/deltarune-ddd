$ErrorActionPreference = 'Stop'
$Root = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$scripts = @('tools/windows_common.ps1', 'tools/build.ps1', 'tools/build_android.ps1')

foreach ($script in $scripts) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $Root $script), [ref]$tokens, [ref]$errors
    )
    if ($errors.Count -gt 0) {
        $messages = $errors | ForEach-Object { $_.Message }
        throw "$($script) parse failure: $($messages -join '; ')"
    }
    $shellCalls = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true) | ForEach-Object { $_.GetCommandName() } |
        Where-Object { $_ -and $_ -match '^(bash|sh|git-bash)(\.exe)?$' }
    if ($shellCalls) {
        throw "$script invokes a POSIX shell: $($shellCalls -join ', ')"
    }
    $legacyHashCalls = $ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -eq 'Get-FileHash'
    }, $true)
    if ($legacyHashCalls) {
        throw "$script depends on Get-FileHash; use Get-TMFileSha256 instead."
    }
}

. (Join-Path $Root 'tools/windows_common.ps1')
$hashFixture = [System.IO.Path]::GetTempFileName()
try {
    [System.IO.File]::WriteAllText($hashFixture, 'abc', [System.Text.Encoding]::ASCII)
    $hash = Get-TMFileSha256 $hashFixture
    if ($hash -ne 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') {
        throw "SHA-256 helper returned an unexpected digest: $hash"
    }
} finally {
    Remove-Item -LiteralPath $hashFixture -Force -ErrorAction SilentlyContinue
}

$environmentNames = @('DELTARUNE_DDD_CH1_TOOLS_DIR', 'DELTARUNE_DDD_CH1_KRISTAL_DIR', 'KRISTAL_ROOT')
$previous = @{}
foreach ($name in $environmentNames) {
    $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

try {
    $override = Join-Path ([System.IO.Path]::GetTempPath()) ("deltarune-ddd-ch1-tools-" + [guid]::NewGuid().ToString('N'))
    $env:DELTARUNE_DDD_CH1_TOOLS_DIR = $override
    $actual = Get-TMSharedToolsDir $Root
    if ($actual -ne [System.IO.Path]::GetFullPath($override)) {
        throw "tools override was not respected: $actual"
    }

    Remove-Item Env:DELTARUNE_DDD_CH1_TOOLS_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:DELTARUNE_DDD_CH1_KRISTAL_DIR -ErrorAction SilentlyContinue
    Remove-Item Env:KRISTAL_ROOT -ErrorAction SilentlyContinue
    $boundary = Get-TMSharedToolsDir ([System.IO.Path]::GetPathRoot($Root))
    if ([string]::IsNullOrWhiteSpace($boundary)) {
        throw 'root-directory probe returned an empty tools directory'
    }

    # When LÖVE is present, cross the real native PowerShell -> LÖVE -> Lua
    # boundary once. The plan is read-only and covers the argument-file path
    # used because LÖVE 11 does not preserve positional game arguments.
    $love = Find-TMCommand 'love.exe'
    if (-not $love) {
        $love = Find-TMCommand 'love'
    }
    if ($love) {
        $plan = [System.IO.Path]::GetTempFileName()
        try {
            Invoke-TMBuildHelper $Root $love.Source @('plan-release-libraries', $Root, $plan)
            $entries = [System.IO.File]::ReadAllLines($plan)
            foreach ($expected in @('kristal-debug-tools', 'kristal-object-selector-plus', 'terminal-cli')) {
                if ($expected -notin $entries) {
                    throw "release library plan is missing development library: $expected"
                }
            }
            # This project ships no optional content packs: everything that is
            # not a development library has to survive into the release build.
            foreach ($shipped in @('ddd-3d', 'bloom-tuner', 'love-suit', 'virtualkeyboard')) {
                if ($shipped -in $entries) {
                    throw "release library plan removes shipped library: $shipped"
                }
            }
        } finally {
            Remove-Item -LiteralPath $plan -Force -ErrorAction SilentlyContinue
        }

        $zipRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("deltarune-ddd-ch1-helper-zip-" + [guid]::NewGuid().ToString('N'))
        $zipSource = Join-Path $zipRoot 'source with spaces'
        $zipOutput = Join-Path $zipRoot 'archive.zip'
        try {
            New-Item -ItemType Directory -Force -Path $zipSource | Out-Null
            [System.IO.File]::WriteAllText((Join-Path $zipSource 'payload.txt'), 'zip smoke')
            Invoke-TMBuildHelper $Root $love.Source @('zip-dir', $zipOutput, $zipSource, '')
            if (-not (Test-Path -LiteralPath $zipOutput)) {
                throw 'build helper did not create a ZIP archive'
            }
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            Add-Type -AssemblyName System.IO.Compression
            $zip = [System.IO.Compression.ZipFile]::OpenRead($zipOutput)
            try {
                if (-not $zip.GetEntry('payload.txt')) {
                    throw 'build helper ZIP is missing payload.txt'
                }
            } finally {
                $zip.Dispose()
            }
        } finally {
            Remove-Item -LiteralPath $zipRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Write-Output 'LÖVE unavailable: skipping PowerShell build-helper execution smoke'
    }
} finally {
    foreach ($name in $environmentNames) {
        if ($null -eq $previous[$name]) {
            Remove-Item "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item "Env:$name" $previous[$name]
        }
    }
}

Write-Output 'Windows build smoke: PASS'
