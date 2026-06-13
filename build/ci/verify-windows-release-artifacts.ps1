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

function Test-SetupInstaller {
    param(
        [string]$Path,
        [string]$ZipReferencePath
    )
    if (-not (Test-Path $Path)) {
        throw "Setup.exe not found: $Path"
    }
    $setup = Get-Item $Path
    $minSetupBytes = 5MB
    if ($setup.Length -lt $minSetupBytes) {
        throw "Setup.exe too small ($($setup.Length) bytes): $Path"
    }
    if (Test-Path $ZipReferencePath) {
        $zip = Get-Item $ZipReferencePath
        # Inno LZMA2 installer is smaller than raw ZIP but should remain in the same order of magnitude.
        $minRatio = [int64]($zip.Length * 0.25)
        if ($setup.Length -lt $minRatio) {
            throw "Setup.exe ($($setup.Length) bytes) suspiciously smaller than ZIP ($($zip.Length) bytes)"
        }
    }
    # Inno Setup .exe is not a 7-Zip archive; ISCC success + ZIP/Release verify is sufficient.
    Write-Host "verify-windows-release-artifacts: Setup OK - $Path ($($setup.Length) bytes)"
}

Test-ZipContainsWalletFfi -Path $ZipPath
if ($SetupPath) {
    Test-SetupInstaller -Path $SetupPath -ZipReferencePath $ZipPath
}
