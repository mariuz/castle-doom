{ Crash reporting in release builds (desktop): an exception that reaches
  the application's event loop is logged with the log file's place and
  the last log lines, then shown in a dialog that offers to continue or
  quit (CGE's own dialog only says "An error occurred"). In autotests
  (no one to answer a dialog) the report is logged and the program exits
  with code 1. The web build never gets here: an exception stops the
  WebAssembly program, and the page shows its own report
  (tools/patch_web_page.py). The demo command CRASH raises a test
  exception (autotest crash-report). }
unit GameCrash;

interface

uses SysUtils;

{ Make the application report uncaught exceptions this way. }
procedure InstallCrashReporter;

{ The report: what happened, where the log is, its last lines. }
function CrashReport(const E: Exception): String;

implementation

uses Classes, CastleWindow, CastleLog, CastleApplicationProperties, CastleStringUtils, CastleUtils,
  GameViewMenu;

type
  TCrashReporter = class
    procedure HandleException(Sender: TObject; E: Exception);
  end;

var
  Reporter: TCrashReporter;

function CrashReport(const E: Exception): String;
var
  I: Integer;
begin
  Result := Format('Castle DOOM %s stopped on an error:', [ApplicationProperties.Version]) + NL +
    E.ClassName + ': ' + E.Message + NL + NL +
    'The log is ' + LogOutput + '; its last lines:' + NL;
  { LastLog(0) is the newest line. }
  for I := LastLogCount - 1 downto 0 do
    Result := Result + '  ' + TrimRight(LastLog(I)) + NL;
end;

procedure TCrashReporter.HandleException(Sender: TObject; E: Exception);
var
  Report: String;
  Continue: Boolean;
begin
  Report := CrashReport(E);
  WritelnWarning('Crash', Report);
  if (AutoTestPrefix <> '') or (Application.MainWindow = nil) then
    Halt(1);
  Continue := false;
  try
    Continue := Application.MainWindow.MessageYesNo(Report + NL + 'Try to continue the game?', mtError);
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
    Reporter := TCrashReporter.Create;
  Application.OnException := {$ifdef FPC}@{$endif} Reporter.HandleException;
end;

finalization
  FreeAndNil(Reporter);
end.
