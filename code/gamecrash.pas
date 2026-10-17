{ Crash reporting in release builds (desktop): an exception that reaches
  the application's event loop is logged with the last log lines (a ring
  buffer of the last RingLines, fed by ApplicationProperties.OnLog), the
  whole report is saved as crash-report.txt in the config directory and
  copied to the clipboard, and a dialog with the newest lines offers to
  continue or quit (CGE's own dialog only says "An error occurred"). In
  autotests (no one to answer a dialog) the report is logged and saved
  and the program exits with code 1. The web build never gets here: an
  exception stops the WebAssembly program, and the page shows its own
  report with a copy button (tools/patch_web_page.py). The demo command
  CRASH raises a test exception (autotest crash-report). }
unit GameCrash;

interface

uses SysUtils;

const
  { Log lines kept for the report, and the newest of them in the dialog. }
  RingLines = 100;
  DialogLines = 20;

{ Make the application report uncaught exceptions this way, and start
  remembering log lines. }
procedure InstallCrashReporter;

{ The report: what happened, where the log is, its last MaxLines lines. }
function CrashReport(const E: Exception; const MaxLines: Integer = RingLines): String;

{ The remembered log lines, oldest first. }
function RecentLogLines: Integer;
function RecentLogLine(const Index: Integer): String;

implementation

uses Classes, Math, CastleWindow, CastleLog, CastleApplicationProperties, CastleStringUtils, CastleUtils,
  CastleUriUtils, CastleControls,
  GameViewMenu;

type
  TCrashReporter = class
    procedure HandleException(Sender: TObject; E: Exception);
    procedure Log(const Message: String);
  end;

var
  Reporter: TCrashReporter;
  Ring: TStringList;

procedure TCrashReporter.Log(const Message: String);
begin
  { A message may hold several lines (the crash report itself does). }
  Ring.Add(TrimRight(Message));
  while Ring.Count > RingLines do
    Ring.Delete(0);
end;

function RecentLogLines: Integer;
begin
  Result := Ring.Count;
end;

function RecentLogLine(const Index: Integer): String;
begin
  Result := Ring[Index];
end;

function CrashReport(const E: Exception; const MaxLines: Integer): String;
var
  I: Integer;
begin
  Result := Format('Castle DOOM %s stopped on an error:', [ApplicationProperties.Version]) + NL +
    E.ClassName + ': ' + E.Message + NL + NL +
    'The log is ' + LogOutput + '; its last lines:' + NL;
  if Ring.Count > 0 then
  begin
    for I := Max(0, Ring.Count - MaxLines) to Ring.Count - 1 do
      Result := Result + '  ' + Ring[I] + NL;
  end else
    { Before InstallCrashReporter: CGE's own short memory (LastLog(0) is
      the newest line). }
    for I := LastLogCount - 1 downto 0 do
      Result := Result + '  ' + TrimRight(LastLog(I)) + NL;
end;

{ crash-report.txt in the config directory (next to the saves); '' when
  it cannot be written. }
function SaveReport(const Report: String): String;
var
  F: TFileStream;
begin
  Result := UriToFilenameSafe(ResolveCastleConfigUrl('castle-config:/crash-report.txt'));
  if Result = '' then Exit;
  try
    ForceDirectories(ExtractFilePath(Result));
    F := TFileStream.Create(Result, fmCreate);
    try
      if Report <> '' then
        F.WriteBuffer(Report[1], Length(Report));
    finally
      FreeAndNil(F);
    end;
  except
    Result := '';
  end;
end;

procedure TCrashReporter.HandleException(Sender: TObject; E: Exception);
var
  Report, FileName, Where: String;
  Continue: Boolean;
begin
  Report := CrashReport(E);
  FileName := SaveReport(Report);
  WritelnWarning('Crash', Report);
  if FileName <> '' then
    WritelnLog('Crash', 'Report saved to %s', [FileName]);
  if (AutoTestPrefix <> '') or (Application.MainWindow = nil) then
    Halt(1);
  Continue := false;
  try
    Clipboard.AsText := Report;
    Where := 'The whole report (' + IntToStr(RingLines) + ' log lines) is on the clipboard';
    if FileName <> '' then
      Where := Where + ' and in ' + FileName;
    Continue := Application.MainWindow.MessageYesNo(CrashReport(E, DialogLines) + NL +
      Where + '; please add it to a bug report at https://github.com/mariuz/castle-doom/issues.' +
      NL + NL + 'Try to continue the game?', mtError);
  except
    { The dialog itself failed (no OpenGL context...): the log has it. }
    Continue := false;
  end;
  if not Continue then
    Halt(1);
end;

procedure InstallCrashReporter;
begin
  if Reporter = nil then
  begin
    Reporter := TCrashReporter.Create;
    ApplicationProperties.OnLog.Add({$ifdef FPC}@{$endif} Reporter.Log);
  end;
  Application.OnException := {$ifdef FPC}@{$endif} Reporter.HandleException;
end;

initialization
  Ring := TStringList.Create;
finalization
  if Reporter <> nil then
    ApplicationProperties.OnLog.Remove({$ifdef FPC}@{$endif} Reporter.Log);
  FreeAndNil(Reporter);
  FreeAndNil(Ring);
end.
