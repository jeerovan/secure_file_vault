[Setup]
AppName=FiFe
AppVersion=1.0.8
DefaultDirName={autopf}\FiFe
DefaultGroupName=FiFe
OutputDir=Output
OutputBaseFilename=FiFe_Setup
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "build\windows\x64\runner\Release\fife.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\FiFe"; Filename: "{app}\fife.exe"
Name: "{autodesktop}\FiFe"; Filename: "{app}\fife.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\fife.exe"; Description: "Launch FiFe"; Flags: nowait postinstall skipifsilent