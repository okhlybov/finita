; Download path for the MODPATH extension is: http://www.legroom.net/files/software/modpath.iss

#define Version "0.1"

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
OutputBaseFilename="finita-{#Version}"
OutputDir=..
ChangesEnvironment=True

[Files]
Source: ".dist\*"; DestDir: "{app}"; Flags: ignoreversion createallsubdirs recursesubdirs

[Dirs]
Name: "{app}"; Flags: setntfscompression

[Tasks]
Name: "modifypath"; Description: "&Add finitac executable to the path"

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
