; Inno Setup — packs Flutter `windows/runner/Release` into a single Setup.exe (similar role to Tauri NSIS).
; Build from repo root, e.g.:
;   ISCC.exe build\ci\flutter-windows-installer.iss /DMyAppVersion=5.1.1 /DVersionSafe=5.1.1 /DSrcRelease=C:\full\path\to\Release
#ifndef SrcRelease
  #error Pass /DSrcRelease=... (absolute path to Flutter Release folder, no trailing backslash)
#endif
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
; Release filename segment: pubspec semver before + (e.g. 5.1.1 from 5.1.1+1); pass /DVersionSafe=... from CI or ISCC.
#ifndef VersionSafe
  #define VersionSafe "0.0.0"
#endif

#define MyAppName "Arqma Wallet (Flutter)"
#define MyAppPublisher "Arqma"
; Output next to repo root (this .iss lives under build/ci/).
#define RepoRoot "..\\..\\"
; Setup icon: copied into {#SrcRelease}\app_icon.ico by package-flutter-windows-release.ps1 before ISCC.

[Setup]
AppId={{E7F3A1B2-4C5D-6789-ABCD-EF0123456789}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
OutputDir={#RepoRoot}
OutputBaseFilename=Arqma-Wallet-Flutter-{#VersionSafe}-windows-x64-Setup
SetupIconFile={#SrcRelease}\app_icon.ico
UninstallDisplayIcon={app}\app_icon.ico
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
DisableProgramGroupPage=yes
PrivilegesRequired=admin

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SrcRelease}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\Arqma-Wallet.exe"; IconFilename: "{app}\app_icon.ico"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\Arqma-Wallet.exe"; IconFilename: "{app}\app_icon.ico"

[Run]
Filename: "{app}\Arqma-Wallet.exe"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
