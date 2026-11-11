; Build from the repository root with Inno Setup 6.
[Setup]
AppId=OpenLorikeet
AppName=OpenLorikeet
AppVersion=0.1.0
AppPublisher=Pushkar
AppPublisherURL=https://github.com/PushkarShah0603/OpenLorikeet
DefaultDirName={localappdata}\Programs\OpenLorikeet
DefaultGroupName=OpenLorikeet
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\dist
OutputBaseFilename=OpenLorikeet-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\OpenLorikeet.exe
CloseApplications=yes

[Files]
Source: "..\dist\portable\OpenLorikeet\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\OpenLorikeet"; Filename: "{app}\OpenLorikeet.exe"
Name: "{autodesktop}\OpenLorikeet"; Filename: "{app}\OpenLorikeet.exe"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Run]
Filename: "{app}\OpenLorikeet.exe"; Description: "Launch OpenLorikeet"; Flags: nowait postinstall skipifsilent
