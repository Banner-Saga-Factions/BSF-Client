; Inno Setup script for the custom Banner Saga: Factions client (BSF-Custom-Server #47, Wave 3a).
;
; WHAT THIS DOES: turns the self-contained game folder (scripts\build.ps1 -Target bundle) plus the
; game's art and sound folders into one setup file. It installs for the current user only, with no
; admin prompt, into %LOCALAPPDATA%\Programs\tbs_factions_strand, and adds a Start-menu entry, an
; optional desktop shortcut, an uninstaller and a line in "Apps & features".
;
; WHY AN INSTALLER: section 6.1 of the AIR SDK licence forbids "any Developer Application that runs
; without installation", so the game folder cannot be handed out as a zip. See
; docs/build-workflow.md, "Windows installer".
;
; Do not build this file by hand: scripts\build-installer.ps1 prepares the folder it reads and
; passes the settings below. The defaults only let the script compile on its own.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef LaunchArgs
  #define LaunchArgs "--steam true --server http://localhost:8082/"
#endif
#ifndef StageDir
  #define StageDir "..\_build\installer-stage"
#endif
#ifndef InfoFile
  #define InfoFile "..\_build\installer-info.txt"
#endif
#ifndef OutputDir
  #define OutputDir "..\_build\installer"
#endif

#define AppName "The Banner Saga Factions (Community Server)"
#define GameExe "The Banner Saga Factions.exe"

[Setup]
; The AppId ties every version together, so a newer setup installs over an older one.
; Never change it.
AppId={{C3815D4A-7F3C-4C3B-819D-3C85992BFDA9}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Banner Saga Factions community
AppPublisherURL=https://github.com/Banner-Saga-Factions
AppSupportURL=https://github.com/Banner-Saga-Factions/BSF-Client/issues
VersionInfoVersion={#AppVersion}
; Current user only: no admin prompt, and nothing written outside the user's own folders.
PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\tbs_factions_strand
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
; The game and its add-ons are 32-bit.
ArchitecturesAllowed=x86compatible
InfoBeforeFile={#InfoFile}
UninstallDisplayIcon={app}\win32\{#GameExe}
UninstallDisplayName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename=BSF-Client-Setup-{#AppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The second guard behind build-installer.ps1: never ship the SDK's own tools (licence 3.3(a)(iv)),
; the original game file kept as a backup, or the test helper in mods\.
Source: "{#StageDir}\win32\*"; DestDir: "{app}\win32"; Flags: recursesubdirs createallsubdirs ignoreversion; Excludes: "bk-app.game.air.swf,adl*.exe,adt*,\mods"
Source: "{#StageDir}\assets\*"; DestDir: "{app}\assets"; Flags: recursesubdirs createallsubdirs ignoreversion
Source: "{#StageDir}\gui\*"; DestDir: "{app}\gui"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
; The game must start from inside win32\. Started from another folder (measured with the
; repository's) with --steam true, Steam closes it and opens the 2013 copy in the Steam library.
Name: "{userprograms}\{#AppName}"; Filename: "{app}\win32\{#GameExe}"; Parameters: "{#LaunchArgs}"; WorkingDir: "{app}\win32"
Name: "{userdesktop}\{#AppName}"; Filename: "{app}\win32\{#GameExe}"; Parameters: "{#LaunchArgs}"; WorkingDir: "{app}\win32"; Tasks: desktopicon

[Run]
Filename: "{app}\win32\{#GameExe}"; Parameters: "{#LaunchArgs}"; WorkingDir: "{app}\win32"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent unchecked

; Uninstalling removes only what this setup put in the install folder. The saved games live under
; %APPDATA%\TheBannerSagaFactions, shared with the Steam copy, and are never touched.
