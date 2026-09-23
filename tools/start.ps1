# tools/start.ps1 — PowerShell port of tools/start.sh (keep the two in sync).
#
# Usage: .\tools\start.ps1 [-name PROJECT_NAME] [-yes]
#
# Initialize this template with a project name and fetch all submodules.
# When PROJECT_NAME is omitted, the Git root directory name is used.
$ErrorActionPreference = 'Stop'

function Write-Stderr([string]$Message) {
    [Console]::Error.WriteLine($Message)
}

function Get-TemplateField([string]$Text, [string]$Field) {
    $pattern = "(?m)^[ \t]*`"$Field`"[ \t]*:[ \t]*`"([^`"]*)`""
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $m = [regex]::Match($Text, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return ''
}

function Apply-Pairs([string]$Text, $Pairs) {
    foreach ($pair in $Pairs) {
        $old = $pair[0]
        $new = $pair[1]
        if (-not [string]::IsNullOrEmpty($old)) { $Text = $Text.Replace($old, $new) }
    }
    return $Text
}

function Replace-First([string]$Text, [string]$Pattern, [string]$Replacement) {
    $m = [regex]::Match($Text, $Pattern)
    if (-not $m.Success) { return $Text }
    return $Text.Substring(0, $m.Index) + $m.Result($Replacement) + $Text.Substring($m.Index + $m.Length)
}

$script_dir = $PSScriptRoot
$git_root = (& git -C $script_dir rev-parse --show-toplevel 2>$null) -join ''
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($git_root)) { $git_root = $script_dir }
$project_root = (Resolve-Path -LiteralPath ($git_root).Trim()).Path

$mod_json = Join-Path $project_root 'mod.json'
if (-not (Test-Path -LiteralPath $mod_json)) {
    Write-Stderr "Could not find mod.json in $project_root"
    exit 1
}

$mod_text = [System.IO.File]::ReadAllText($mod_json)
$old_id = Get-TemplateField $mod_text 'id'
$old_display = Get-TemplateField $mod_text 'name'
if ([string]::IsNullOrEmpty($old_id) -or [string]::IsNullOrEmpty($old_display)) {
    Write-Stderr "Could not read project id and name from $mod_json"
    exit 1
}

$default_name = Split-Path -Leaf $project_root
$project_name = ''
$assume_default = $false

$i = 0
while ($i -lt $args.Count) {
    $arg = [string]$args[$i]
    switch -Exact ($arg) {
        '--help' {
            Write-Host "Usage: .\tools\start.ps1 [-name PROJECT_NAME] [-yes]"
            Write-Host ""
            Write-Host "Initialize this template with a project name and fetch all submodules."
            Write-Host "When PROJECT_NAME is omitted, the Git root directory name is used."
            exit 0
        }
        '-h' {
            Write-Host "Usage: .\tools\start.ps1 [-name PROJECT_NAME] [-yes]"
            Write-Host ""
            Write-Host "Initialize this template with a project name and fetch all submodules."
            Write-Host "When PROJECT_NAME is omitted, the Git root directory name is used."
            exit 0
        }
        '--yes' { $assume_default = $true; $i++ }
        '-y' { $assume_default = $true; $i++ }
        '--name' {
            if ($i -ge $args.Count - 1) {
                Write-Stderr '--name requires a value.'
                exit 64
            }
            $project_name = [string]$args[$i + 1]
            $i += 2
        }
        '-n' {
            if ($i -ge $args.Count - 1) {
                Write-Stderr '-n requires a value.'
                exit 64
            }
            $project_name = [string]$args[$i + 1]
            $i += 2
        }
        default {
            if ($arg -like '--name=*') {
                $project_name = $arg.Substring('--name='.Length)
                $i++
            } elseif ($arg -like '--*') {
                Write-Stderr "Unknown option: $arg"
                Write-Stderr 'Usage: .\tools\start.ps1 [-name PROJECT_NAME] [-yes]'
                exit 64
            } else {
                if (-not [string]::IsNullOrEmpty($project_name)) {
                    Write-Stderr 'Only one project name may be provided.'
                    exit 64
                }
                $project_name = $arg
                $i++
            }
        }
    }
}

if ([string]::IsNullOrEmpty($project_name) -and -not $assume_default) {
    $interactive = $false
    try { $interactive = -not [Console]::IsInputRedirected } catch { }
    if ($interactive) {
        $answer = Read-Host "Project name [$default_name]"
        if (-not [string]::IsNullOrEmpty($answer)) { $project_name = $answer }
    }
}
if ([string]::IsNullOrEmpty($project_name)) { $project_name = $default_name }
$project_name = $project_name.Trim()

if ([string]::IsNullOrEmpty($project_name)) {
    Write-Stderr 'Project name cannot be empty.'
    exit 64
}
if ($project_name.Contains("`n") -or $project_name.Contains("`r")) {
    Write-Stderr 'Project name cannot contain a newline.'
    exit 64
}

$project_id = ($project_name.ToLowerInvariant() -replace '[^a-z0-9]+', '-') -replace '^-+', '' -replace '-+$', ''
if ([string]::IsNullOrEmpty($project_id)) {
    Write-Stderr 'Project name must contain at least one ASCII letter or number.'
    exit 64
}

$old_lower_spaced = $old_display.ToLowerInvariant()
$old_upper_spaced = $old_display.ToUpperInvariant()
$old_env_prefix = ($old_id -replace '-', '_').ToUpperInvariant()
$old_upper_hyphen = $old_id.ToUpperInvariant()
$old_compact = $old_id -replace '[-_]', ''

# Some derived projects changed mod.json before this script was introduced.
# Keep the original template aliases so those projects can still be migrated.
$legacy_id = 'deltarune-ddd-ch1'
$legacy_display = 'deltarune-ddd-ch1'
$legacy_lower_spaced = 'deltarune-ddd-ch1'
$legacy_upper_spaced = 'DELTARUNE-DDD-CH1'
$legacy_env_prefix = 'DELTARUNE_DDD_CH1'
$legacy_upper_hyphen = 'DELTARUNE-DDD-CH1'
$legacy_compact = 'deltarunedddch1'

$new_lower_spaced = $project_name.ToLowerInvariant()
$new_upper_spaced = $project_name.ToUpperInvariant()
$new_env_prefix = ($project_id -replace '-', '_').ToUpperInvariant()
$new_upper_hyphen = $project_id.ToUpperInvariant()
$new_compact = $project_id -replace '[-_]', ''
if ($new_env_prefix -match '^[0-9]') { $new_env_prefix = "PROJECT_$new_env_prefix" }

$template_text = ''
$template_lines = (& git -C $project_root show HEAD:mod.json 2>$null) -join "`n"
if ($LASTEXITCODE -eq 0) { $template_text = $template_lines }
$template_id = Get-TemplateField $template_text 'id'
$template_display = Get-TemplateField $template_text 'name'
if ([string]::IsNullOrEmpty($template_id)) { $template_id = $old_id }
if ([string]::IsNullOrEmpty($template_display)) { $template_display = $old_display }
$template_lower_spaced = $template_display.ToLowerInvariant()
$template_upper_spaced = $template_display.ToUpperInvariant()
$template_env_prefix = ($template_id -replace '-', '_').ToUpperInvariant()
$template_upper_hyphen = $template_id.ToUpperInvariant()
$template_compact = $template_id -replace '[-_]', ''

# Brace the expansions: "$legacy_id_*" parses as the variable $legacy_id_
# (underscore is an identifier character), which is empty -- so the pattern
# collapses to "*" and the guard fires for every project.
$legacy_aliases_enabled = $true
if ($old_id -eq $legacy_id -or $old_id -like "${legacy_id}-*" -or $old_id -like "${legacy_id}_*") { $legacy_aliases_enabled = $false }
if ($template_id -eq $legacy_id -or $template_id -like "${legacy_id}-*" -or $template_id -like "${legacy_id}_*") { $legacy_aliases_enabled = $false }
if (-not $legacy_aliases_enabled) {
    # The full current/template ID handles this derived template name.
    # Disabling the short alias prevents it from being replaced twice.
    $sentinel = '__legacy_alias_disabled__'
    $legacy_id = $sentinel
    $legacy_display = $sentinel
    $legacy_lower_spaced = $sentinel
    $legacy_upper_spaced = $sentinel
    $legacy_env_prefix = $sentinel
    $legacy_upper_hyphen = $sentinel
    $legacy_compact = $sentinel
}

$changed_files = 0
if ($old_id -ne $project_id -or $old_display -ne $project_name -or
    $old_env_prefix -ne $new_env_prefix -or $legacy_aliases_enabled) {
    $contentPairs = @(
        @($legacy_id, $project_id), @($legacy_display, $project_name),
        @($legacy_lower_spaced, $new_lower_spaced), @($legacy_upper_spaced, $new_upper_spaced),
        @($legacy_env_prefix, $new_env_prefix), @($legacy_upper_hyphen, $new_upper_hyphen),
        @($legacy_compact, $new_compact),
        @($template_id, $project_id), @($template_display, $project_name),
        @($template_lower_spaced, $new_lower_spaced), @($template_upper_spaced, $new_upper_spaced),
        @($template_env_prefix, $new_env_prefix), @($template_upper_hyphen, $new_upper_hyphen),
        @($template_compact, $new_compact),
        @($old_id, $project_id), @($old_display, $project_name),
        @($old_lower_spaced, $new_lower_spaced), @($old_upper_spaced, $new_upper_spaced),
        @($old_env_prefix, $new_env_prefix), @($old_upper_hyphen, $new_upper_hyphen),
        @($old_compact, $new_compact)
    )
    $grepCandidates = @(
        $old_id, $old_display, $old_lower_spaced, $old_upper_spaced, $old_env_prefix, $old_upper_hyphen, $old_compact,
        $legacy_id, $legacy_display, $legacy_lower_spaced, $legacy_upper_spaced, $legacy_env_prefix, $legacy_upper_hyphen, $legacy_compact,
        $template_id, $template_display, $template_lower_spaced, $template_upper_spaced, $template_env_prefix, $template_upper_hyphen, $template_compact
    )
    $grepArgs = @('-C', $project_root, 'grep', '-I', '-l', '-F')
    foreach ($candidate in $grepCandidates) { $grepArgs += @('-e', $candidate) }
    $grepArgs += @('--', '.')
    $grepOut = @(& git @grepArgs 2>$null)

    foreach ($rel in $grepOut) {
        if ([string]::IsNullOrEmpty($rel)) { continue }
        $file = Join-Path $project_root $rel
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $text = [System.IO.File]::ReadAllText($file)
        $text = Apply-Pairs $text $contentPairs
        [System.IO.File]::WriteAllText($file, $text)
        $changed_files++
    }
}

$renamed_paths = 0
$tiled_project_path = ''
$tiled_project_count = 0
$lsOut = @(& git -C $project_root ls-files -- 2>$null)
foreach ($rel in $lsOut) {
    if ($rel.Contains('/')) { continue }
    if ($rel -like '*.tiled-project') {
        $tiled_project_path = $rel
        $tiled_project_count++
    }
}

$pathPairs = @(
    @($legacy_id, $project_id), @($legacy_lower_spaced, $project_id),
    @($legacy_upper_spaced, $project_id), @($legacy_env_prefix, $project_id),
    @($legacy_upper_hyphen, $project_id), @($legacy_compact, $project_id),
    @($old_id, $project_id), @($old_lower_spaced, $project_id),
    @($old_upper_spaced, $project_id), @($old_env_prefix, $project_id),
    @($old_upper_hyphen, $project_id), @($old_compact, $project_id),
    @($template_id, $project_id), @($template_lower_spaced, $project_id),
    @($template_upper_spaced, $project_id), @($template_env_prefix, $project_id),
    @($template_upper_hyphen, $project_id), @($template_compact, $project_id)
)

foreach ($rel in $lsOut) {
    # Root-level paths only: a project rename owns the files named after the
    # project itself, not whatever happens to contain its name further down
    # the tree (renaming libraries/depthseffects alongside would just break
    # the library).
    if ($rel.Contains('/')) { continue }
    $old_file = Join-Path $project_root $rel
    if (-not (Test-Path -LiteralPath $old_file)) { continue }

    $new_rel = Apply-Pairs $rel $pathPairs
    if ($new_rel -eq $rel -and $tiled_project_count -eq 1 -and $rel -eq $tiled_project_path -and
        $rel -ne "$project_id.tiled-project") {
        $new_rel = "$project_id.tiled-project"
    }
    if ($new_rel -eq $rel) { continue }

    $new_file = Join-Path $project_root $new_rel
    if (Test-Path -LiteralPath $new_file) {
        Write-Stderr "Cannot rename ${rel}: target already exists at ${new_rel}"
        exit 1
    }
    $parent = Split-Path -Parent $new_file
    if (-not [string]::IsNullOrEmpty($parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    Move-Item -LiteralPath $old_file -Destination $new_file
    $renamed_paths++
}

Write-Host "Project name: $project_name"
Write-Host "Mod ID: $project_id"
Write-Host "Updated $changed_files tracked text file(s)."
Write-Host "Renamed $renamed_paths tracked file path(s)."
Write-Host 'Updating submodules...'
& git -C $project_root submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host 'Resetting project version to 0.0.0...'
$versionPattern = '(?m)^([ \t]*"version"[ \t]*:[ \t]*")[^"]*(".*)$'
$mod_text = [System.IO.File]::ReadAllText($mod_json)
$mod_text = Replace-First $mod_text $versionPattern '${1}v0.0.0${2}'
# The pass above is string-based, so a project whose "name" holds the same text
# as its "id" (several derived projects do) ends up with both fields set to the
# slug: the id pair consumes the string before the name pair looks for it.
# These two fields are the project's identity -- pin them to what was asked for.
$idPattern = '(?m)^([ \t]*"id"[ \t]*:[ \t]*")[^"]*(".*)$'
$mod_text = Replace-First $mod_text $idPattern ('${1}' + $project_id.Replace('$', '$$') + '${2}')
$namePattern = '(?m)^([ \t]*"name"[ \t]*:[ \t]*")[^"]*(".*)$'
$mod_text = Replace-First $mod_text $namePattern ('${1}' + $project_name.Replace('$', '$$') + '${2}')
[System.IO.File]::WriteAllText($mod_json, $mod_text)

$manifest_path = Join-Path $project_root '.release-please-manifest.json'
if (Test-Path -LiteralPath $manifest_path) {
    $manifest_content = "{`n  `".`": `"0.0.0`"`n}`n"
    [System.IO.File]::WriteAllText($manifest_path, $manifest_content)
}
$changelog_path = Join-Path $project_root 'CHANGELOG.md'
if (Test-Path -LiteralPath $changelog_path) {
    $changelog_content = "# Changelog`n`nAll notable changes are documented here by release-please.`n"
    [System.IO.File]::WriteAllText($changelog_path, $changelog_content)
}

Write-Host 'Project initialization complete.'
