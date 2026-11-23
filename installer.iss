; Engine Test Manager Pro 2.3
#define MyAppName "Engine Test Manager Pro"
#define MyAppVersion "2.3.0"
#define MyAppExeName "engine_test_manager.exe"
[Setup]
AppId={{B3E55B20-7E34-4C63-A0E2-7A2200000001}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\Engine Test Manager Pro
DefaultGroupName={#MyAppName}
OutputDir=Output
OutputBaseFilename=Engine-Test-Manager-Pro-2.3-Setup
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
DisableProgramGroupPage=yes
[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion
[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"
[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: postinstall nowait skipifsilent
