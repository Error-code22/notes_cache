; Foluma Windows installer.
; Build with: ISCC.exe installer\foluma.iss
; The Flutter release folder must exist first:
;   flutter build windows --release

#define MyAppName "Foluma"
#define MyAppVersion "1.0.6"
#define MyAppExeName "notes_cache.exe"
#define MyAppPublisher "Foluma"

[Setup]
AppId={{c945c160-ee51-489b-a0d5-f454cceb53bc}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Foluma
DefaultGroupName=Foluma
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=Foluma-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
SetupLogging=yes
LicenseFile=..\LICENSE
; Keep user notes/settings on uninstall. Only the installed program is removed.
UninstallDisplayName={#MyAppName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "notes_cache.exp,notes_cache.lib"

[Icons]
Name: "{group}\Foluma"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall Foluma"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Foluma"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch Foluma"; Flags: nowait postinstall skipifsilent
