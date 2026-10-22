; Установщик «Жизни» для Windows (Inno Setup 6).
; Версию передаёт сборка: iscc /DAppVersion=1.2.3 windows\installer.iss

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{8C2B6A51-3F0E-4E6B-9C1D-5A7F2E4B1D90}
AppName=Жизнь
AppVersion={#AppVersion}
AppPublisher=Жизнь
DefaultDirName={localappdata}\Programs\Zhizn
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\installer
OutputBaseFilename=Zhizn-Setup-{#AppVersion}
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\zhizn.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=force
RestartApplications=no

[Languages]
Name: "ru"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "desktopicon"; Description: "Значок на рабочем столе"; Flags: unchecked
Name: "autostart"; Description: "Запускать вместе с Windows (в трее, для напоминаний и горячей клавиши)"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\Жизнь"; Filename: "{app}\zhizn.exe"; AppUserModelID: "Zhizn.Zhizn.App"
Name: "{userdesktop}\Жизнь"; Filename: "{app}\zhizn.exe"; Tasks: desktopicon
Name: "{userstartup}\Жизнь"; Filename: "{app}\zhizn.exe"; Parameters: "--tray"; Tasks: autostart

[Run]
Filename: "{app}\zhizn.exe"; Description: "Открыть «Жизнь»"; Flags: nowait postinstall

[Code]
// Приложение живёт в трее — перед обновлением его нужно закрыть.
function InitializeSetup(): Boolean;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM zhizn.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Result := True;
end;
