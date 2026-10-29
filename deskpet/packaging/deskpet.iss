#ifndef AppVersion
#define AppVersion "0.1.0"
#endif
[Setup]
AppId={{ED7C37EC-A108-4733-89C8-7DF693DD8616}
AppName=何爪爪
SetupIconFile=..\assets\ui\app.ico
AppVersion={#AppVersion}
AppPublisher=Azugawa
DefaultDirName={localappdata}\Programs\PersonalityDeskPet
DefaultGroupName=何爪爪
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=DeskPet-Setup-{#AppVersion}
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
UninstallDisplayIcon={app}\DeskPet.exe
ArchitecturesAllowed=x64compatible
[Files]
Source: "..\..\build\windows\DeskPet.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\DeskPet.pck"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\何爪爪"; Filename: "{app}\DeskPet.exe"; Parameters: "-- --desktop-mode"
Name: "{autodesktop}\何爪爪"; Filename: "{app}\DeskPet.exe"; Parameters: "-- --desktop-mode"
[Run]
Filename: "{app}\DeskPet.exe"; Parameters: "-- --desktop-mode"; Description: "启动何爪爪"; Flags: nowait postinstall skipifsilent

[InstallDelete]
Type: files; Name: "{autodesktop}\Personality DeskPet.lnk"
Type: files; Name: "{userprograms}\Personality DeskPet\Personality DeskPet.lnk"
