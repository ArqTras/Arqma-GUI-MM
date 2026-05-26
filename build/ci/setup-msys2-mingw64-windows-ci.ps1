# MSYS2 MinGW64 for Windows desktop CI (replaces msys2/setup-msys2 when action download fails).
$ErrorActionPreference = 'Stop'
$msys = 'C:\msys64'
if (-not (Test-Path $msys)) { throw "MSYS2 not found at $msys (expected on windows-latest)" }
"msys2-location=$msys" | Out-File -FilePath $env:GITHUB_OUTPUT -Append -Encoding utf8
$bash = Join-Path $msys 'usr\bin\bash.exe'
$pkgs = @(
  'mingw-w64-x86_64-gcc',
  'mingw-w64-x86_64-cmake',
  'mingw-w64-x86_64-make',
  'mingw-w64-x86_64-boost',
  'mingw-w64-x86_64-openssl',
  'mingw-w64-x86_64-libsodium',
  'mingw-w64-x86_64-zeromq',
  'mingw-w64-x86_64-hidapi',
  'mingw-w64-x86_64-readline',
  'mingw-w64-x86_64-ncurses',
  'mingw-w64-x86_64-unbound',
  'mingw-w64-x86_64-lmdb',
  'mingw-w64-x86_64-icu',
  'mingw-w64-x86_64-zlib',
  'mingw-w64-x86_64-libunwind',
  'git',
  'zip'
) -join ' '
& $bash -lc "pacman -Syu --noconfirm && pacman -S --noconfirm --needed $pkgs"
Write-Host "MSYS2 ready at $msys"
