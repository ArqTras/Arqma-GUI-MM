# Verify portable ZIP (and optionally Inno Setup) contain wallet FFI + exe.
param(
    [Parameter(Mandatory = $true)]
    [string]$ZipPath,
    [string]$SetupPath = ""
)

$ErrorActionPreference = "Stop"

function Test-ZipContainsWalletFfi {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "ZIP not found: $Path"
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Path).Path)
    try {
        $names = @($zip.Entries | ForEach-Object { ($_.FullName -replace '\\', '/').TrimStart('/') })
        foreach ($required in @(
                'Arqma-Wallet.exe',
                'arqma_wallet_flutter_ffi.dll',
                'libgcc_s_seh-1.dll',
                'libstdc++-6.dll',
                'libwinpthread-1.dll',
                'flutter_windows.dll'
            )) {
            $hit = $names | Where-Object { $_ -eq $required -or $_ -like "*/$required" }
            if (-not $hit) {
                throw "Release ZIP missing entry: $required (in $Path)"
            }
        }
        $libHit = $names | Where-Object { $_ -eq 'lib/arqma_wallet_flutter_ffi.dll' }
        if (-not $libHit) {
            throw "Release ZIP missing legacy mirror: lib/arqma_wallet_flutter_ffi.dll"
        }
    } finally {
        $zip.Dispose()
    }
    Write-Host "verify-windows-release-artifacts: ZIP OK - $Path"
}

function Test-SetupContainsWalletFfi {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Setup.exe not found: $Path"
    }
    $sevenZip = @(
        $env:SEVEN_ZIP
        (Join-Path ${env:ProgramFiles} '7-Zip\7z.exe')
        (Join-Path ${env:ProgramFiles(x86)} '7-Zip\7z.exe')
    ) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $sevenZip) {
        Write-Warning "7-Zip not found; skipped Setup.exe content check (install 7-Zip or set SEVEN_ZIP)"
        return
    }
    $listing = & $sevenZip l $Path 2>&1 | Out-String
    if ($listing -notmatch 'arqma_wallet_flutter_ffi\.dll') {
        throw "Setup.exe listing missing arqma_wallet_flutter_ffi.dll"
    }
    if ($listing -notmatch 'Arqma-Wallet\.exe') {
        throw "Setup.exe listing missing Arqma-Wallet.exe"
    }
    Write-Host "verify-windows-release-artifacts: Setup OK - $Path"
}

Test-ZipContainsWalletFfi -Path $ZipPath
if ($SetupPath) {
    Test-SetupContainsWalletFfi -Path $SetupPath
}
