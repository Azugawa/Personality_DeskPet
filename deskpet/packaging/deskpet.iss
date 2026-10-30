#ifndef AppVersion
#define AppVersion "0.3.8"
#endif
[Setup]
AppId={{ED7C37EC-A108-4733-89C8-7DF693DD8616}
AppName=何爪爪
SetupIconFile=..\assets\ui\icons\app.ico
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
[Tasks]
Name: "autostart"; Description: "开机自动启动何爪爪（推荐，定时提醒更可靠）"; GroupDescription: "启动选项："; Flags: checkedonce
[Files]
Source: "..\..\build\windows\DeskPet.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\DeskPet.pck"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\DeskPetUpdater.exe"; DestDir: "{app}"; Flags: ignoreversion
[Icons]
Name: "{group}\何爪爪"; Filename: "{app}\DeskPet.exe"; Parameters: "-- --desktop-mode"
Name: "{autodesktop}\何爪爪"; Filename: "{app}\DeskPet.exe"; Parameters: "-- --desktop-mode"
[Run]
Filename: "{app}\DeskPet.exe"; Parameters: "-- --desktop-mode"; Description: "启动何爪爪"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "Hezhuazhua"; ValueData: """{app}\DeskPet.exe"" -- --desktop-mode"; Flags: uninsdeletevalue; Tasks: autostart

[InstallDelete]
Type: files; Name: "{autodesktop}\Personality DeskPet.lnk"
Type: files; Name: "{userprograms}\Personality DeskPet\Personality DeskPet.lnk"
