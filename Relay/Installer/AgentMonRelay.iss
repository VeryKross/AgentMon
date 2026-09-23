#if PREPROCVER != EncodeVer(6, 7, 3)
  #error Inno Setup 6.7.3 is required
#endif

#ifndef AppVersion
  #error AppVersion must be supplied, for example /DAppVersion=0.2.0
#endif
#ifndef Runtime
  #error Runtime must be supplied, for example /DRuntime=win-x64
#endif
#ifndef SourceDir
  #error SourceDir must be supplied
#endif
#ifndef ArtifactDir
  #error ArtifactDir must be supplied
#endif
#ifndef SigningLabel
  #error SigningLabel must be supplied as signed or unsigned
#endif

#if Runtime == "win-x64"
  #define AllowedArchitectures "x64compatible and not arm64"
  #define Install64BitMode "x64compatible"
#elif Runtime == "win-arm64"
  #define AllowedArchitectures "arm64"
  #define Install64BitMode "arm64"
#else
  #error Runtime must be win-x64 or win-arm64
#endif

#if SigningLabel == "signed"
  #ifndef SignRelay
    #error SigningLabel=signed requires /DSignRelay
  #endif
#elif SigningLabel == "unsigned"
  #ifdef SignRelay
    #error /DSignRelay requires SigningLabel=signed
  #endif
#else
  #error SigningLabel must be signed or unsigned
#endif

#define ProductName "AgentMon Relay"
#define ProductExe "AgentMonRelay.exe"
#define ProductAppId "{{A3245D0A-76A9-4CD7-B203-AEA4B13861F1}"
#define ProductUninstallKey "{A3245D0A-76A9-4CD7-B203-AEA4B13861F1}_is1"

[Setup]
AppId={#ProductAppId}
AppName={#ProductName}
AppVersion={#AppVersion}
AppVerName={#ProductName} {#AppVersion}
AppPublisher=VeryKross
AppPublisherURL=https://github.com/VeryKross/AgentMon
AppSupportURL=https://github.com/VeryKross/AgentMon/issues
AppUpdatesURL=https://github.com/VeryKross/AgentMon/releases
DefaultDirName={localappdata}\Programs\AgentMonRelay
DisableDirPage=yes
DisableProgramGroupPage=yes
UsePreviousAppDir=no
PrivilegesRequired=lowest
ArchitecturesAllowed={#AllowedArchitectures}
ArchitecturesInstallIn64BitMode={#Install64BitMode}
OutputDir={#ArtifactDir}
OutputBaseFilename=AgentMonRelay-{#AppVersion}-{#Runtime}-{#SigningLabel}-Setup
VersionInfoVersion={#AppVersion}
VersionInfoProductName={#ProductName}
VersionInfoProductVersion={#AppVersion}
VersionInfoCompany=VeryKross
VersionInfoDescription={#ProductName} installer
UninstallDisplayName={#ProductName}
UninstallDisplayIcon={app}\{#ProductExe}
SetupIconFile=..\AgentMon.Relay.Windows\Assets\AgentMonRelay.ico
CloseApplications=no
RestartApplications=no
RestartIfNeededByRun=no
AllowCancelDuringInstall=yes
DirExistsWarning=no
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
SetupLogging=no
#ifdef SignRelay
SignTool=relay
SignedUninstaller=yes
#endif

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "{#SourceDir}\AgentMonRelay.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#SourceDir}\THIRD-PARTY-NOTICES.txt"; DestDir: "{app}"
Source: "{#SourceDir}\Microsoft.NETCore.App-LICENSE.txt"; DestDir: "{app}"
Source: "{#SourceDir}\Microsoft.NETCore.App-NOTICES.txt"; DestDir: "{app}"
Source: "{#SourceDir}\Microsoft.AspNetCore.App-NOTICES.txt"; DestDir: "{app}"
Source: "{#SourceDir}\Microsoft.WindowsDesktop.App-LICENSE.txt"; DestDir: "{app}"
Source: "{#SourceDir}\README.md"; DestDir: "{app}"

[Icons]
Name: "{autoprograms}\AgentMon Relay"; Filename: "{app}\{#ProductExe}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#ProductExe}"; Description: "Launch AgentMon Relay"; WorkingDir: "{app}"; Flags: postinstall nowait skipifsilent unchecked

[Code]
type
  TVersionParts = array[0..3] of Integer;

var
  TrustPage: TOutputMsgWizardPage;
  RemoveUserData: Boolean;

function FixedInstallPath: String;
begin
  Result := ExpandConstant('{localappdata}\Programs\AgentMonRelay');
end;

function InstalledExecutablePath: String;
begin
  Result := FixedInstallPath + '\{#ProductExe}';
end;

function PathsMatch(const FirstPath, SecondPath: String): Boolean;
begin
  Result :=
    CompareText(
      RemoveBackslashUnlessRoot(FirstPath),
      RemoveBackslashUnlessRoot(SecondPath)) = 0;
end;

function TryParseVersion(const Value: String; var Parts: TVersionParts): Boolean;
var
  CharacterIndex: Integer;
  PartIndex: Integer;
  Token: String;
  CharacterValue: Char;
begin
  Result := False;
  for PartIndex := 0 to 3 do
    Parts[PartIndex] := 0;

  if Value = '' then
    Exit;

  PartIndex := 0;
  Token := '';
  for CharacterIndex := 1 to Length(Value) do
  begin
    CharacterValue := Value[CharacterIndex];
    if CharacterValue = '.' then
    begin
      if (Token = '') or (PartIndex >= 3) then
        Exit;
      Parts[PartIndex] := StrToIntDef(Token, -1);
      if (Parts[PartIndex] < 0) or (Parts[PartIndex] > 65535) then
        Exit;
      PartIndex := PartIndex + 1;
      Token := '';
    end
    else if (CharacterValue >= '0') and (CharacterValue <= '9') then
      Token := Token + CharacterValue
    else
      Exit;
  end;

  if Token = '' then
    Exit;
  Parts[PartIndex] := StrToIntDef(Token, -1);
  if (Parts[PartIndex] < 0) or (Parts[PartIndex] > 65535) then
    Exit;

  Result := True;
end;

function CompareVersionStrings(
  const FirstVersion, SecondVersion: String;
  var Comparison: Integer): Boolean;
var
  FirstParts: TVersionParts;
  SecondParts: TVersionParts;
  PartIndex: Integer;
begin
  Result := False;
  Comparison := 0;
  if not TryParseVersion(FirstVersion, FirstParts) then
    Exit;
  if not TryParseVersion(SecondVersion, SecondParts) then
    Exit;

  for PartIndex := 0 to 3 do
  begin
    if FirstParts[PartIndex] < SecondParts[PartIndex] then
    begin
      Comparison := -1;
      Break;
    end;
    if FirstParts[PartIndex] > SecondParts[PartIndex] then
    begin
      Comparison := 1;
      Break;
    end;
  end;
  Result := True;
end;

function TryGetInstalledVersion(var InstalledVersion: String): Boolean;
begin
  Result :=
    GetVersionNumbersString(InstalledExecutablePath, InstalledVersion);
  if Result then
    Exit;

  Result :=
    RegQueryStringValue(
      HKCU64,
      'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#ProductUninstallKey}',
      'DisplayVersion',
      InstalledVersion);
end;

function CheckForDowngrade(var ErrorMessage: String): Boolean;
var
  Comparison: Integer;
  InstalledVersion: String;
begin
  Result := False;
  ErrorMessage := '';

  if not FileExists(InstalledExecutablePath) then
  begin
    if not TryGetInstalledVersion(InstalledVersion) then
    begin
      Result := True;
      Exit;
    end;
  end
  else if not TryGetInstalledVersion(InstalledVersion) then
  begin
    ErrorMessage :=
      'Setup cannot safely determine the version of the installed AgentMon Relay. ' +
      'No files were changed.';
    Exit;
  end;

  if not CompareVersionStrings(InstalledVersion, '{#AppVersion}', Comparison) then
  begin
    ErrorMessage :=
      'Setup cannot safely compare the installed AgentMon Relay version with ' +
      'this package. No files were changed.';
    Exit;
  end;

  if Comparison > 0 then
  begin
    ErrorMessage :=
      'A newer version of AgentMon Relay (' + InstalledVersion +
      ') is already installed. Downgrades are not supported. No files were changed.';
    Exit;
  end;

  Result := True;
end;

function RunExecutableHelper(
  const ExecutablePath, WorkingDirectory: String;
  const Parameters: String;
  var ErrorMessage: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  ErrorMessage := '';

  if not FileExists(ExecutablePath) then
  begin
    ErrorMessage := 'A required AgentMon Relay helper is missing. No files were changed.';
    Exit;
  end;

  if not Exec(
    ExecutablePath,
    Parameters,
    WorkingDirectory,
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode) then
  begin
    ErrorMessage :=
      'AgentMon Relay could not perform a required safety check. No files were changed.';
    Exit;
  end;

  if ResultCode <> 0 then
  begin
    ErrorMessage :=
      'AgentMon Relay is still running or could not complete a required safety check. ' +
      'Quit AgentMon Relay from its notification-area icon, then try again. ' +
      'No files were changed.';
    Exit;
  end;

  Result := True;
end;

function RunInstalledHelper(
  const Parameters: String;
  var ErrorMessage: String): Boolean;
begin
  Result :=
    RunExecutableHelper(
      InstalledExecutablePath,
      FixedInstallPath,
      Parameters,
      ErrorMessage);
end;

function CheckInstalledRelayNotRunning(var ErrorMessage: String): Boolean;
begin
  if not FileExists(InstalledExecutablePath) then
  begin
    ErrorMessage := '';
    Result := True;
    Exit;
  end;

  Result := RunInstalledHelper('--check-not-running', ErrorMessage);
end;

function CheckRelayNotRunningForSetup(var ErrorMessage: String): Boolean;
var
  SetupHelperPath: String;
begin
  if not FileExists(InstalledExecutablePath) then
  begin
    ErrorMessage := '';
    Result := True;
    Exit;
  end;

  try
    ExtractTemporaryFile('{#ProductExe}');
    SetupHelperPath := ExpandConstant('{tmp}\{#ProductExe}');
    Result :=
      RunExecutableHelper(
        SetupHelperPath,
        ExpandConstant('{tmp}'),
        '--check-not-running',
        ErrorMessage);
  except
    ErrorMessage :=
      'AgentMon Relay could not prepare its required safety check. No files were changed.';
    Result := False;
  end;
end;

procedure InitializeWizard;
begin
  WizardForm.DirEdit.Text := FixedInstallPath;

#if SigningLabel == "signed"
  TrustPage := CreateOutputMsgPage(
    wpWelcome,
    'Package signature',
    'This is a signed AgentMon Relay installer.',
    'Windows can verify the publisher signature on this installer. ' +
    'The installer will not change firewall, network profile, startup, or trust settings.');
#else
  TrustPage := CreateOutputMsgPage(
    wpWelcome,
    'Unsigned development package',
    'This AgentMon Relay installer is not Authenticode-signed.',
    'This unsigned package is intended for development or release-candidate testing. ' +
    'Verify that it came from the expected source and verify its published SHA-256 checksum. ' +
    'The installer will not change firewall, network profile, startup, or trust settings.');
#endif
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  NeedsRestart := False;
  Result := '';

  WizardForm.DirEdit.Text := FixedInstallPath;
  if not PathsMatch(WizardDirValue, FixedInstallPath) then
  begin
    Result :=
      'AgentMon Relay must be installed in its fixed per-user location. ' +
      'Setup refused a directory override and made no changes.';
    Exit;
  end;

  if not CheckForDowngrade(Result) then
    Exit;

  CheckRelayNotRunningForSetup(Result);
end;

function HasRemoveUserDataParameter: Boolean;
var
  ParameterIndex: Integer;
begin
  Result := False;
  for ParameterIndex := 1 to ParamCount do
  begin
    if CompareText(ParamStr(ParameterIndex), '/REMOVEUSERDATA=1') = 0 then
    begin
      Result := True;
      Exit;
    end;
  end;
end;

function ConfirmUserDataRemoval: Boolean;
var
  Answer: Integer;
begin
  Result := True;
  RemoveUserData := HasRemoveUserDataParameter;

  if UninstallSilent then
    Exit;
  if RemoveUserData then
    Exit;

  Answer := MsgBox(
    'Also delete this Windows user''s AgentMon Relay pairing identity, credentials, and logs?' +
    Chr(13) + Chr(10) + Chr(13) + Chr(10) +
    'Choose No to preserve pairing data for a future reinstall. ' +
    'Deleting it will require pairing Macs again.',
    mbConfirmation,
    MB_YESNOCANCEL or MB_DEFBUTTON2);

  if Answer = IDCANCEL then
  begin
    Result := False;
    Exit;
  end;
  RemoveUserData := Answer = IDYES;
end;

function InitializeUninstall: Boolean;
var
  ErrorMessage: String;
begin
  Result := False;
  RemoveUserData := False;

  if not CheckInstalledRelayNotRunning(ErrorMessage) then
  begin
    if not UninstallSilent then
      MsgBox(ErrorMessage, mbError, MB_OK);
    Exit;
  end;

  if not ConfirmUserDataRemoval then
    Exit;

  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ErrorMessage: String;
  CleanupParameters: String;
begin
  if CurUninstallStep <> usUninstall then
    Exit;

  // Inno reaches usUninstall only after its standard confirmation, so cancellation cannot trigger mutations.
  if not CheckInstalledRelayNotRunning(ErrorMessage) then
    RaiseException(ErrorMessage);

  CleanupParameters := '--uninstall-cleanup';
  if UninstallSilent then
    CleanupParameters := CleanupParameters + ' --silent';
  if not RunInstalledHelper(CleanupParameters, ErrorMessage) then
    RaiseException(
      'AgentMon Relay could not remove its owned startup or firewall configuration. ' +
      'Uninstall was stopped before files were removed.' +
      Chr(13) + Chr(10) + Chr(13) + Chr(10) + ErrorMessage);

  if RemoveUserData then
  begin
    if not RunInstalledHelper('--remove-user-data', ErrorMessage) then
      RaiseException(
        'AgentMon Relay could not safely remove its pairing identity, credentials, and logs. ' +
        'Uninstall was stopped before program files were removed.' +
        Chr(13) + Chr(10) + Chr(13) + Chr(10) + ErrorMessage);
  end;
end;
