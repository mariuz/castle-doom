{ Demo recording and playback (Castle DOOM's own format, not Doom's .lmp).

  The player is moved by CGE's walk navigation, so a demo cannot store
  key presses per tic like Doom's: it stores what TDoomWorld receives.
  Each frame's world update is a line with the player's position, angle,
  camera and walking speed and the number of tics that frame ran; between
  them come the player's actions in the order they reached the world
  (use, fire, fire released, weapon changes, a knockback the walls
  stopped). Playing it back feeds the same inputs with the same tic
  counts, so the world (with its own random numbers, seeded from the
  demo) does the same things at any frame rate. A recording starts from
  a saved state of the level (the recording session reloads it too, so
  both start alike), and a checksum of the player and the actors every
  second tells where a playback goes out of sync.

    CASTLEDOOMDEMO 1
    seed 12345
    state {...one-line save game JSON...}
    T 2 <12 floats as hex bits>      update: tics, feet xyz, angle, camera
                                     position xyz, direction xyz, walk vx vy
    U | F | R | P                    use, fire, fire released, push stopped
    N -1 | W 3                       next / previous weapon, select weapon
    X P 453B8000 437A0000            a demo-script cheat (K, Y, P, CORPSE, D,
                                     V, INVIS, INVUL, AMP, LINE) and its two
                                     numbers as hex bits
    C 35 1a2b3c4d                    checksum at a tic
    E 812 1a2b3c4d kills 3/17 ...    the level's end: tic, checksum, summary
    L {...save game JSON...}         the next level's start (then its lines)

  A recording goes on through the levels that follow (after the
  intermission), each from its own saved state. Command line: --record
  FILE (from the first level started) and --playdemo FILE, or the title
  screen's Options panel; GameViewPlay drives both, TDoomWorld records
  and replays. In the browser a recording stays in memory (Text) and
  is kept in the save storage and downloaded by the page; a demo plays
  from its text (CreateFromText: no exceptions, which would stop the
  WebAssembly program). }
unit DoomDemo;

interface

uses Classes, SysUtils, FpJson;

const
  DemoValues = 12;
  { A checksum line every second of the game. }
  DemoCheckTics = 35;

type
  TDemoEventKind = (deUpdate, deUse, deFire, deReleaseFire, deStopPush,
    deNextWeapon, deSelectWeapon, deCheck, deEnd, deCheat);

  TDemoEvent = record
    Kind: TDemoEventKind;
    Tics, Arg: Integer;
    Hash: Cardinal;
    Values: array [0..DemoValues - 1] of Single;
    { deEnd: the summary; deCheat: the command (Values[0..1] its numbers). }
    Text: String;
  end;

  TDemoRecorder = class
  strict private
    FStream: TStream;
    FFileName: String;
    FFinished: Boolean;
    { A frame that ran no tics: written only when an action follows
      before the next update (the action then sees its position). }
    FPending: String;
    procedure Line(const S: String);
  public
    constructor Create(const AFileName: String; const Seed: Cardinal; const State: TJSONObject);
    { Recording into memory (Text), for the browser's save storage;
      AName is only for the log. }
    constructor CreateInMemory(const AName: String; const Seed: Cardinal; const State: TJSONObject);
    destructor Destroy; override;
    procedure Update(const Tics: Integer; const Values: array of Single);
    procedure Event(const Kind: TDemoEventKind; const Arg: Integer = 0);
    procedure Cheat(const Command: String; const Arg, Arg2: Single);
    { The demo so far (an in-memory recording; '' for a file). }
    function Text: String;
    function InMemory: Boolean;
    procedure Check(const Tic: Integer; const Hash: Cardinal);
    { The level's end line; the file stays open for the next level
      (NextLevel) until the recorder is freed. }
    procedure EndLevel(const Tic: Integer; const Hash: Cardinal; const Summary: String);
    { The next level's start: its saved state. }
    procedure NextLevel(const State: TJSONObject);
    property FileName: String read FFileName;
    { Between two levels: the last one ended, no next one yet. }
    property Finished: Boolean read FFinished;
  end;

  TDemoPlayer = class
  strict private
    FLines: TStringList;
    FPos: Integer;
    FSeed: Cardinal;
    FState: TJSONObject;
    FFileName: String;
    FError: String;
    procedure Parse;
  public
    { Raises an exception when the file is not a demo. }
    constructor Create(const AFileName: String);
    { A demo from its text; check Valid (no exception for a wrong file). }
    constructor CreateFromText(const AName, AText: String);
    destructor Destroy; override;
    { The text was a demo (else Error says why). }
    function Valid: Boolean;
    function Error: String;
    { The next event of this level; False after the last line or at the
      next level's start. }
    function Next(out E: TDemoEvent): Boolean;
    { The next level's saved state (the caller owns it), nil when the
      demo has no more levels. }
    function NextLevelState: TJSONObject;
    function AtEnd: Boolean;
    property Seed: Cardinal read FSeed;
    { The save game the demo starts from (owned). }
    property State: TJSONObject read FState;
    property FileName: String read FFileName;
  end;

function SingleToHex(const V: Single): String;
function HexToSingle(const S: String): Single;

implementation

uses JsonParser;

const
  Magic = 'CASTLEDOOMDEMO 1';
  KindLetters: array [TDemoEventKind] of String = ('T', 'U', 'F', 'R', 'P', 'N', 'W', 'C', 'E', 'X');

function SingleToHex(const V: Single): String;
var
  C: Cardinal;
begin
  Move(V, C, 4);
  Result := IntToHex(C, 8);
end;

function HexToSingle(const S: String): Single;
var
  C: Cardinal;
begin
  C := Cardinal(StrToInt64Def('$' + S, 0));
  Move(C, Result, 4);
end;

{ TDemoRecorder -------------------------------------------------------------- }

constructor TDemoRecorder.Create(const AFileName: String; const Seed: Cardinal; const State: TJSONObject);
begin
  inherited Create;
  FFileName := AFileName;
  ForceDirectories(ExtractFilePath(ExpandFileName(AFileName)));
  FStream := TFileStream.Create(AFileName, fmCreate);
  Line(Magic);
  Line('seed ' + IntToStr(Seed));
  Line('state ' + State.AsJSON);
end;

constructor TDemoRecorder.CreateInMemory(const AName: String; const Seed: Cardinal; const State: TJSONObject);
begin
  inherited Create;
  FFileName := AName;
  FStream := TStringStream.Create('');
  Line(Magic);
  Line('seed ' + IntToStr(Seed));
  Line('state ' + State.AsJSON);
end;

function TDemoRecorder.InMemory: Boolean;
begin
  Result := FStream is TStringStream;
end;

function TDemoRecorder.Text: String;
begin
  if InMemory then
    Result := TStringStream(FStream).DataString
  else
    Result := '';
end;

procedure TDemoRecorder.Cheat(const Command: String; const Arg, Arg2: Single);
begin
  Line(Format('X %s %s %s', [Command, SingleToHex(Arg), SingleToHex(Arg2)]));
end;

destructor TDemoRecorder.Destroy;
begin
  FreeAndNil(FStream);
  inherited;
end;

procedure TDemoRecorder.Line(const S: String);
var
  T: String;
begin
  if FFinished then Exit;
  if FPending <> '' then
  begin
    T := FPending + #10;
    FPending := '';
    FStream.WriteBuffer(T[1], Length(T));
  end;
  T := S + #10;
  FStream.WriteBuffer(T[1], Length(T));
end;

procedure TDemoRecorder.Update(const Tics: Integer; const Values: array of Single);
var
  S: String;
  I: Integer;
begin
  S := 'T ' + IntToStr(Tics);
  for I := 0 to High(Values) do
    S := S + ' ' + SingleToHex(Values[I]);
  FPending := '';
  if Tics = 0 then
    FPending := S
  else
    Line(S);
end;

procedure TDemoRecorder.Event(const Kind: TDemoEventKind; const Arg: Integer);
begin
  if Kind in [deNextWeapon, deSelectWeapon] then
    Line(KindLetters[Kind] + ' ' + IntToStr(Arg))
  else
    Line(KindLetters[Kind]);
end;

procedure TDemoRecorder.Check(const Tic: Integer; const Hash: Cardinal);
begin
  Line(Format('C %d %s', [Tic, IntToHex(Hash, 8)]));
end;

procedure TDemoRecorder.EndLevel(const Tic: Integer; const Hash: Cardinal; const Summary: String);
begin
  FPending := '';
  Line(Format('E %d %s %s', [Tic, IntToHex(Hash, 8), Summary]));
  FFinished := true;
end;

procedure TDemoRecorder.NextLevel(const State: TJSONObject);
begin
  FFinished := false;
  FPending := '';
  Line('L ' + State.AsJSON);
end;

{ TDemoPlayer ---------------------------------------------------------------- }

constructor TDemoPlayer.Create(const AFileName: String);
begin
  inherited Create;
  FFileName := AFileName;
  FLines := TStringList.Create;
  FLines.LoadFromFile(AFileName);
  Parse;
  if not Valid then
    raise Exception.Create(FError);
end;

constructor TDemoPlayer.CreateFromText(const AName, AText: String);
begin
  inherited Create;
  FFileName := AName;
  FLines := TStringList.Create;
  FLines.Text := AText;
  Parse;
end;

procedure TDemoPlayer.Parse;
var
  Data: TJSONData;
  J: String;
begin
  if (FLines.Count < 3) or (FLines[0] <> Magic) or (Copy(FLines[1], 1, 5) <> 'seed ') or
     (Copy(FLines[2], 1, 6) <> 'state ') then
  begin
    FError := Format('%s is not a Castle DOOM demo', [FFileName]);
    Exit;
  end;
  FSeed := Cardinal(StrToInt64Def(Copy(FLines[1], 6, MaxInt), 1));
  { The recorder writes the state as one JSON object: anything else is
    refused before the parser (whose exceptions the web cannot catch)
    sees it. }
  J := Trim(Copy(FLines[2], 7, MaxInt));
  if (J = '') or (J[1] <> '{') or (J[Length(J)] <> '}') then
  begin
    FError := Format('%s has no saved state', [FFileName]);
    Exit;
  end;
  Data := GetJSON(J);
  if not (Data is TJSONObject) then
  begin
    FreeAndNil(Data);
    FError := Format('%s has no saved state', [FFileName]);
    Exit;
  end;
  FState := TJSONObject(Data);
  FPos := 3;
end;

function TDemoPlayer.Valid: Boolean;
begin
  Result := FState <> nil;
end;

function TDemoPlayer.Error: String;
begin
  Result := FError;
end;

destructor TDemoPlayer.Destroy;
begin
  FreeAndNil(FState);
  FreeAndNil(FLines);
  inherited;
end;

function TDemoPlayer.NextLevelState: TJSONObject;
var
  Data: TJSONData;
begin
  Result := nil;
  while (FPos < FLines.Count) and (Copy(FLines[FPos], 1, 2) <> 'L ') do
    Inc(FPos);
  if FPos >= FLines.Count then Exit;
  if Copy(FLines[FPos], 3, 1) <> '{' then Exit;
  Data := GetJSON(Copy(FLines[FPos], 3, MaxInt));
  Inc(FPos);
  if Data is TJSONObject then
    Result := TJSONObject(Data)
  else
    FreeAndNil(Data);
end;

function TDemoPlayer.AtEnd: Boolean;
begin
  Result := FPos >= FLines.Count;
end;

function TDemoPlayer.Next(out E: TDemoEvent): Boolean;
var
  Words: TStringList;
  K: TDemoEventKind;
  I: Integer;
begin
  E := Default(TDemoEvent);
  Result := false;
  Words := TStringList.Create;
  try
    Words.Delimiter := ' ';
    Words.StrictDelimiter := true;
    while FPos < FLines.Count do
    begin
      { The next level starts: this one has no more events. }
      if Copy(FLines[FPos], 1, 2) = 'L ' then Exit;
      Words.DelimitedText := FLines[FPos];
      Inc(FPos);
      if Words.Count = 0 then Continue;
      for K := Low(TDemoEventKind) to High(TDemoEventKind) do
        if Words[0] = KindLetters[K] then
        begin
          E.Kind := K;
          case K of
            deUpdate:
              begin
                if Words.Count < DemoValues + 2 then Break;
                E.Tics := StrToIntDef(Words[1], 0);
                for I := 0 to DemoValues - 1 do
                  E.Values[I] := HexToSingle(Words[I + 2]);
              end;
            deNextWeapon, deSelectWeapon:
              if Words.Count > 1 then E.Arg := StrToIntDef(Words[1], 0);
            deCheat:
              begin
                if Words.Count < 4 then Break;
                E.Text := Words[1];
                E.Values[0] := HexToSingle(Words[2]);
                E.Values[1] := HexToSingle(Words[3]);
              end;
            deCheck, deEnd:
              if Words.Count > 2 then
              begin
                E.Tics := StrToIntDef(Words[1], 0);
                E.Hash := Cardinal(StrToInt64Def('$' + Words[2], 0));
                if K = deEnd then
                begin
                  Words.Delete(0);
                  Words.Delete(0);
                  Words.Delete(0);
                  E.Text := Trim(StringReplace(Words.DelimitedText, '"', '', [rfReplaceAll]));
                end;
              end;
          end;
          Exit(true);
        end;
    end;
  finally
    FreeAndNil(Words);
  end;
end;

end.
