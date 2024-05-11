[Setup]
AppName=Etichetta
AppVersion=0.1.2
DefaultDirName={pf}\etichetta
DefaultGroupName=etichetta
UninstallDisplayIcon={app}\etichetta.ico
Compression=lzma2
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
LicenseFile=LICENSE


[Files]
Source: "output\bin\*.*"; DestDir: "{app}\bin"; Flags: recursesubdirs
Source: "output\etc\*.*"; DestDir: "{app}\etc"; Flags: recursesubdirs
Source: "output\share\*.*"; DestDir: "{app}\share"; Flags: recursesubdirs
Source: "output\lib\*.*"; DestDir: "{app}\lib"; Flags: recursesubdirs
Source: "res\etichetta.ico"; DestDir: "{app}"; DestName: "etichetta.ico"; Flags: recursesubdirs

[Tasks]
Name: desktopicon; Description: "Add link on desktop"; GroupDescription: "Additional icons:";

[Icons]
Name: "{userdesktop}\etichetta"; Filename: "{app}\bin\etichetta.exe"; IconFilename: "{app}\etichetta.ico"; Tasks: desktopicon
Name: "{group}\etichetta"; Filename: "{app}\bin\etichetta.exe"; IconFilename: "{app}\etichetta.ico";
Name: "{app}\Start etichetta"; Filename: "{app}\bin\etichetta.exe"; IconFilename: "{app}\etichetta.ico"

[Run]
Filename: "{app}\bin\etichetta.exe"; Description: "Launch etichetta, now!"; Flags: postinstall
