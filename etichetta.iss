[Setup]
AppName=etichetta
AppVersion=0.1
DefaultDirName={pf}\etichetta
DefaultGroupName=etichetta
UninstallDisplayIcon={app}\etichetta.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
LicenseFile=LICENSE


[Files]
Source: "deployment\windows\bin\*.*"; DestDir: "{app}\bin"; Flags: recursesubdirs
Source: "deployment\windows\etc\*.*"; DestDir: "{app}\etc"; Flags: recursesubdirs
Source: "deployment\windows\share\*.*"; DestDir: "{app}\share"; Flags: recursesubdirs
Source: "deployment\windows\lib\*.*"; DestDir: "{app}\lib"; Flags: recursesubdirs
Source: "res\logo.ico"; DestDir: "{app}"; DestName: "etichetta.ico"; Flags: recursesubdirs

[Tasks]
Name: desktopicon; Description: "A YOLO annotator, for human beings"; GroupDescription: "Additional icons:";

[Icons]
Name: "{userdesktop}\etichetta"; Filename: "{app}\bin\etichetta.exe"; IconFilename: "{app}\etichetta.ico"; Tasks: desktopicon
Name: "{group}\etichetta"; Filename: "{app}\bin\etichetta.exe"; IconFilename: "{app}\etichetta.ico";
Name: "{app}\Start etichetta"; Filename: "{app}\bin\etichetta.exe"; IconFilename: "{app}\etichetta.ico"

[Run]
Filename: "{app}\bin\etichetta.exe"; Description: "Launch etichetta"; Flags: postinstall
