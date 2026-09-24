; Pixora installer for Windows (Inno Setup 6).
; Built by .github/workflows/release.yml:
;   iscc /DAppVersion=1.2.3 /DSourceDir=<Release folder> /DOutputDir=<dist> pixora.iss
;
; Installs per-user by default (no admin prompt) and registers the .pixora
; file type so double-clicking a project opens it in Pixora.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{6C1F4B2E-5E0B-4E8B-9C39-7A2B1D0F4C11}
AppName=Pixora
AppVersion={#AppVersion}
AppPublisher=Pixora
DefaultDirName={autopf}\Pixora
DefaultGroupName=Pixora
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Pixora-{#AppVersion}-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\pixora.exe
Compression=lzma2/ultra64
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
ChangesAssociations=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "arabic"; MessagesFile: "compiler:Languages\Arabic.isl"
Name: "turkish"; MessagesFile: "compiler:Languages\Turkish.isl"
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Pixora"; Filename: "{app}\pixora.exe"
Name: "{autodesktop}\Pixora"; Filename: "{app}\pixora.exe"; Tasks: desktopicon

[Registry]
Root: HKA; Subkey: "Software\Classes\.pixora"; ValueType: string; ValueName: ""; ValueData: "Pixora.Project"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\.pixora"; ValueType: string; ValueName: "Content Type"; ValueData: "application/vnd.pixora.project+zip"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\Pixora.Project"; ValueType: string; ValueName: ""; ValueData: "Pixora Project"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\Pixora.Project\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\pixora.exe,0"
Root: HKA; Subkey: "Software\Classes\Pixora.Project\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\pixora.exe"" ""%1"""

[Run]
Filename: "{app}\pixora.exe"; Description: "{cm:LaunchProgram,Pixora}"; Flags: nowait postinstall skipifsilent
