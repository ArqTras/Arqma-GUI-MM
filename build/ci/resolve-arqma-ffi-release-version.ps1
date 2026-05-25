# Print the ArqTras/FFI release tag for prebuilt downloads (Latest release by default).
param(
    [string]$Repo = $(if ($env:ARQMA_FFI_REPO) { $env:ARQMA_FFI_REPO } else { "ArqTras/FFI" }),
    [string]$Requested = $(if ($env:ARQMA_FFI_RELEASE_VERSION) { $env:ARQMA_FFI_RELEASE_VERSION } else { "latest" })
)

$ErrorActionPreference = "Stop"
$Requested = $Requested -replace '^v', ''
if ($Requested -and $Requested -ne "latest") {
    Write-Output $Requested
    exit 0
}

$headers = @{
    Accept = "application/vnd.github+json"
    "User-Agent" = "Arqma-GUI-MM"
}
$token = if ($env:GITHUB_TOKEN) { $env:GITHUB_TOKEN } elseif ($env:GH_TOKEN) { $env:GH_TOKEN } else { $null }
if ($token) {
    $headers.Authorization = "Bearer $token"
}

if (Get-Command gh -ErrorAction SilentlyContinue) {
    $tag = gh api "repos/$Repo/releases/latest" --jq .tag_name 2>$null
    if ($tag) {
        Write-Output ($tag -replace '^v', '')
        exit 0
    }
}

$url = "https://api.github.com/repos/$Repo/releases/latest"
$release = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
$resolved = ($release.tag_name -replace '^v', '')
if (-not $resolved) {
    throw "Cannot resolve latest FFI release for $Repo"
}
Write-Output $resolved
