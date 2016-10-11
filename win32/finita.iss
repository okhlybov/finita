#define MyAppName "Finita"
#define MyAppVersion "1"
#define MyAppPublisher "Oleg A. Khlybov"
#define MyAppBuild "1"

[Setup]
AppName="{#MyAppName}"
AppVersion="{#MyAppVersion}"
AppPublisher="{#MyAppPublisher}"
AppId={{9FC3B76A-A9F6-4AE7-8414-50E0667D5B17}
SolidCompression=True
DefaultDirName="{pf}\{#MyAppName}"
OutputBaseFilename="finita-win32-{#MyAppVersion}-{#MyAppBuild}"
OutputDir=.
ChangesEnvironment=True
DefaultGroupName=Finita
DisableProgramGroupPage=yes

[Files]
Source: "dist\*"; DestDir: "{app}"; Flags: ignoreversion createallsubdirs recursesubdirs
Source: "README.txt"; DestDir: "{app}\doc"; Flags: isreadme

[Dirs]                                                        
Name: "{app}"; Flags: setntfscompression

[Tasks]
Name: "modifypath"; Description: "&Add finitac executable to path"

[Icons]
Name: "{group}\README"; Filename: "{app}\doc\README.txt"
Name: "{group}\Samples"; Filename: "{app}\sample"

[Code]

#include "path.iss"

procedure RegisterPaths;
begin
  if IsTaskSelected('modifypath') then RegisterPath('{app}\bin', SystemPath, Prepend);
end;