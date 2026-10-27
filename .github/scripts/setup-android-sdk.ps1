$ErrorActionPreference = 'Stop'

# The GitHub-hosted Ubuntu and Windows images already provide Android cmdline
# tools. Resolve them from the SDK root instead of a third-party setup action.
# https://github.com/actions/runner-images/tree/main/images
$sdk = $env:ANDROID_SDK_ROOT
if ([string]::IsNullOrWhiteSpace($sdk)) { $sdk = $env:ANDROID_HOME }
if ([string]::IsNullOrWhiteSpace($sdk)) {
    throw 'The GitHub-hosted runner did not provide ANDROID_SDK_ROOT or ANDROID_HOME.'
}

$tools = Join-Path $sdk 'cmdline-tools/latest/bin'
if (-not (Test-Path -LiteralPath (Join-Path $tools 'sdkmanager') -PathType Leaf) -and
    -not (Test-Path -LiteralPath (Join-Path $tools 'sdkmanager.bat') -PathType Leaf)) {
    throw "Android command-line tools are missing from the runner SDK: $tools"
}
if ([string]::IsNullOrWhiteSpace($env:GITHUB_ENV) -or
    [string]::IsNullOrWhiteSpace($env:GITHUB_PATH)) {
    throw 'This SDK setup script requires GitHub Actions environment files.'
}

@("ANDROID_SDK_ROOT=$sdk", "ANDROID_HOME=$sdk") |
    Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
$tools | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
(Join-Path $sdk 'platform-tools') |
    Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
