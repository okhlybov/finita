; MODPATH extension URL: http://www.legroom.net/files/software/modpath.iss

#define Version "preview"
#define Build "1"

[PreCompile]
Name: "prepare.cmd"; Flags: abortonerror

[ThirdParty]
UseRelativePaths=True

[Setup]
AppName=Finita
AppVersion="{#Version}"
AppId={{9FC3B76A-A9F6-4AE7-8414-50E0667D5B17}
SolidCompression=True
DefaultDirName={pf}\Finita
OutputBaseFilename="finita-{#Version}-{#Build}"
OutputDir=..
ChangesEnvironment=True
DefaultGroupName=Finita
DisableProgramGroupPage=yes

[Files]
Source: ".dist\*"; DestDir: "{app}"; Flags: ignoreversion createallsubdirs recursesubdirs
Source: "..\sample\*"; DestDir: "{app}\sample"; Flags: ignoreversion createallsubdirs recursesubdirs
Source: "README.txt"; DestDir: "{app}\doc"; Flags: isreadme
[Dirs]                                                        
Name: "{app}"; Flags: setntfscompression

[Tasks]
Name: "modifypath"; Description: "&Add finitac executable to path"

[Icons]
Name: "{group}\README"; Filename: "{app}\doc\README.txt"
Name: "{group}\Samples"; Filename: "{app}\sample"

[Code]
const
	ModPathName = 'modifypath';
	ModPathType = 'system';
function ModPathDir(): TArrayOfString;
begin
	setArrayLength(Result, 1);
	Result[0] := ExpandConstant('{app}') + '\bin';
end;
#include "modpath.iss"
