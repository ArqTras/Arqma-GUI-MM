; Inno Setup — packs Flutter `windows/runner/Release` into a single Setup.exe (similar role to Tauri NSIS).
; Build from repo root, e.g.:
;   ISCC.exe build\ci\flutter-windows-installer.iss /DMyAppVersion=5.0.5 /DSrcRelease=C:\full\path\to\Release
#ifndef SrcRelease
  #error Pass /DSrcRelease=... (absolute path to Flutter Release folder, no trailing backslash)
#endif
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif

#define MyAppName "Arqma Wallet (Flutter)"
#define MyAppPublisher "Arqma"
; Output next to repo root (this .iss lives under build/ci/).
#define RepoRoot "..\\..\\"

[Setup]
AppId={{E7F3A1B2-4C5D-6789-ABCD-EF0123456789}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\{#MyAppName}
OutputDir={#RepoRoot}
OutputBaseFilename=Arqma-Wallet-Flutter-windows-x64-Setup
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
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\Arqma-Wallet.exe"

[Run]
Filename: "{app}\Arqma-Wallet.exe"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
