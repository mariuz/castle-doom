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

    CASTLEDOOMDEMO 2
    seed 12345
    state {...one-line save game JSON...}
    T 2 <12 floats as hex bits>      update: tics, feet xyz, angle, camera
                                     position xyz, direction xyz, walk vx vy
    T 5 C3BBA30E = 3E9C6080          "=": the value of the update before;
                                     the unchanged values at the end are
                                     left out (a level's first update is
                                     written whole)
    U | F | R | P                    use, fire, fire released, push stopped
    N -1 | W 3                       next / previous weapon, select weapon
    X P 453B8000 437A0000            a demo-script cheat (K, Y, P, CORPSE, D,
                                     V, INVIS, INVUL, AMP, LINE) and its two
                                     numbers as hex bits
    C 35 1a2b3c4d                    checksum at a tic
    E 812 1a2b3c4d kills 3/17 ...    the level's end: tic, checksum, summary
                                     (ending "exit" when it was finished)
    L {...save game JSON...}         the next level's start (then its lines)

  A recording goes on through the levels that follow (after the
  intermission), each from its own saved state. Command line: --record
  FILE (from the first level started) and --playdemo FILE, or the title
  screen's Options panel; GameViewPlay drives both, TDoomWorld records
  and replays. In the browser a recording stays in memory (Text) and
  is kept in the save storage and downloaded by the page; a demo plays
  from its text (CreateFromText: no exceptions, which would stop the
  WebAssembly program). Format 1 (every value written, the states in
  FpJson's long float notation) still plays; format 2's states are
  CompactJSON, about a fifth of the size. }
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
    FHasPending: Boolean;
    FPendingValues: array [0..DemoValues - 1] of Single;
    { The last update line written: a value equal to its is written "=",
      and the unchanged values at the end are left out (format 2). }
    FLastValues: array [0..DemoValues - 1] of Single;
    FHaveLast: Boolean;
    procedure Line(const S: String);
    procedure WriteRaw(const S: String);
    procedure WriteUpdate(const Tics: Integer; const Values: array of Single);
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
    { Format 2's "=": the previous update line's values. }
    FLastValues: array [0..DemoValues - 1] of Single;
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

  { A recording's path through one level, for a ghost to race: the
    feet and the angle at each recorded frame (Tic: the world's tic when
    that frame began), and the tic it finished the level (-1: the
    recording stopped without an exit). }
  TGhostPoint = record
    Tic: Integer;
    X, Y, Z, Angle: Single;
  end;

  TGhostTrack = record
    Map: String;
    Points: array of TGhostPoint;
    FinishTic: Integer;
  end;
  TGhostTracks = array of TGhostTrack;

function SingleToHex(const V: Single): String;
function HexToSingle(const S: String): Single;

{ JSON without spaces, each float in the fewest digits that read back
  as the same Double (FpJson's AsJSON writes 0 as
  0.0000000000000000E+000), and an array of objects with the same keys
  as {"#keys":[...],"#rows":[[...],...]}: a demo's saved states shrink
  to a fraction. ExpandJSON gives back the original (a new copy). }
function CompactJSON(const Data: TJSONData): String;
function ExpandJSON(const Data: TJSONData): TJSONData;

{ The paths of every level of Demo (read to its end), for --ghost. }
function ReadGhostTracks(const Demo: TDemoPlayer): TGhostTracks;
{ The first of Tracks on MapName; False when none is. }
function FindGhostTrack(const Tracks: TGhostTracks; const MapName: String; out Track: TGhostTrack): Boolean;

implementation

uses Math, JsonParser;

const
  { Format 2 writes "=" for an update value equal to the previous line's
    and leaves out the unchanged ones at the end; format 1 files (every
    value written) still play. }
  Magic = 'CASTLEDOOMDEMO 2';
  MagicVersion1 = 'CASTLEDOOMDEMO 1';
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

function CompactFloat(const V: Double): String;
var
  P, Code: Integer;
  F: Double;
  Settings: TFormatSettings;
begin
  Settings := DefaultFormatSettings;
  Settings.DecimalSeparator := '.';
  if V = 0 then
  begin
    F := 0;
    if CompareByte(F, V, SizeOf(Double)) = 0 then Exit('0.0') else Exit('-0.0');
  end;
  for P := 1 to 17 do
  begin
    Result := FloatToStrF(V, ffGeneral, P, 0, Settings);
    Val(Result, F, Code);
    { The same bits (so -0 stays -0). }
    if (Code = 0) and (CompareByte(F, V, SizeOf(Double)) = 0) then
    begin
      { Stays a float when read back. }
      if (Pos('.', Result) = 0) and (Pos('E', Result) = 0) then
        Result := Result + '.0';
      Exit;
    end;
  end;
  Str(V, Result);
  Result := Trim(Result);
end;

{ All items objects (two at least, else a table saves nothing). }
function AllObjects(const A: TJSONData): Boolean;
var
  I: Integer;
begin
  Result := false;
  if A.Count < 2 then Exit;
  for I := 0 to A.Count - 1 do
    if not (A.Items[I] is TJSONObject) then Exit;
  Result := true;
end;

function ObjectKeys(const O: TJSONObject): String;
var
  K: Integer;
begin
  Result := '';
  for K := 0 to O.Count - 1 do
  begin
    if K > 0 then Result := Result + ',';
    Result := Result + '"' + StringToJSONString(O.Names[K]) + '"';
  end;
end;

function CompactJSON(const Data: TJSONData): String;
var
  I, K, Shape: Integer;
  Shapes: TStringList;
  Keys, Rows: String;
begin
  if (Data.JSONType = jtArray) and AllObjects(Data) then
  begin
    { Each row: the index of its object's keys in #keys, then the values. }
    Shapes := TStringList.Create;
    try
      Rows := '';
      for I := 0 to Data.Count - 1 do
      begin
        Keys := ObjectKeys(TJSONObject(Data.Items[I]));
        Shape := Shapes.IndexOf(Keys);
        if Shape < 0 then Shape := Shapes.Add(Keys);
        if I > 0 then Rows := Rows + ',';
        Rows := Rows + '[' + IntToStr(Shape);
        for K := 0 to Data.Items[I].Count - 1 do
          Rows := Rows + ',' + CompactJSON(Data.Items[I].Items[K]);
        Rows := Rows + ']';
      end;
      Result := '{"#keys":[';
      for K := 0 to Shapes.Count - 1 do
      begin
        if K > 0 then Result := Result + ',';
        Result := Result + '[' + Shapes[K] + ']';
      end;
      Result := Result + '],"#rows":[' + Rows + ']}';
    finally
      FreeAndNil(Shapes);
    end;
    Exit;
  end;
  case Data.JSONType of
    jtNumber:
      if Data is TJSONFloatNumber then
        Result := CompactFloat(Data.AsFloat)
      else
        Result := Data.AsJSON;
    jtArray:
      begin
        Result := '[';
        for I := 0 to Data.Count - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + CompactJSON(Data.Items[I]);
        end;
        Result := Result + ']';
      end;
    jtObject:
      begin
        Result := '{';
        for I := 0 to Data.Count - 1 do
        begin
          if I > 0 then Result := Result + ',';
          Result := Result + '"' + StringToJSONString(TJSONObject(Data).Names[I]) + '":' +
            CompactJSON(Data.Items[I]);
        end;
        Result := Result + '}';
      end;
    else
      Result := Data.AsJSON;
  end;
end;

function ExpandJSON(const Data: TJSONData): TJSONData;
var
  I, K, Shape: Integer;
  O: TJSONObject;
  Keys, Rows, Row, RowKeys: TJSONData;
  Arr: TJSONArray;
begin
  if Data is TJSONObject then
  begin
    O := TJSONObject(Data);
    Keys := O.Find('#keys');
    Rows := O.Find('#rows');
    if (O.Count = 2) and (Keys is TJSONArray) and (Rows is TJSONArray) then
    begin
      Arr := TJSONArray.Create;
      for I := 0 to Rows.Count - 1 do
      begin
        Row := Rows.Items[I];
        O := TJSONObject.Create;
        Arr.Add(O);
        if not (Row is TJSONArray) or (Row.Count = 0) or not (Row.Items[0] is TJSONIntegerNumber) then Continue;
        Shape := Row.Items[0].AsInteger;
        if (Shape < 0) or (Shape >= Keys.Count) or not (Keys.Items[Shape] is TJSONArray) then Continue;
        RowKeys := Keys.Items[Shape];
        for K := 0 to Min(Row.Count - 1, RowKeys.Count) - 1 do
          O.Add(RowKeys.Items[K].AsString, ExpandJSON(Row.Items[K + 1]));
      end;
      Exit(Arr);
    end;
    Result := TJSONObject.Create;
    for I := 0 to O.Count - 1 do
      TJSONObject(Result).Add(O.Names[I], ExpandJSON(O.Items[I]));
  end else
  if Data is TJSONArray then
  begin
    Result := TJSONArray.Create;
    for I := 0 to Data.Count - 1 do
      TJSONArray(Result).Add(ExpandJSON(Data.Items[I]));
  end else
    Result := Data.Clone;
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
  Line('state ' + CompactJSON(State));
end;

constructor TDemoRecorder.CreateInMemory(const AName: String; const Seed: Cardinal; const State: TJSONObject);
begin
  inherited Create;
  FFileName := AName;
  FStream := TStringStream.Create('');
  Line(Magic);
  Line('seed ' + IntToStr(Seed));
  Line('state ' + CompactJSON(State));
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

procedure TDemoRecorder.WriteRaw(const S: String);
var
  T: String;
begin
  T := S + #10;
  FStream.WriteBuffer(T[1], Length(T));
end;

procedure TDemoRecorder.WriteUpdate(const Tics: Integer; const Values: array of Single);
var
  S: String;
  Words: array of String;
  I, Last: Integer;
begin
  SetLength(Words, Length(Values));
  Last := -1;
  for I := 0 to High(Values) do
  begin
    { The same bits (so -0 and 0 stay apart). }
    if FHaveLast and (I <= High(FLastValues)) and (SingleToHex(Values[I]) = SingleToHex(FLastValues[I])) then
      Words[I] := '='
    else
    begin
      Words[I] := SingleToHex(Values[I]);
      Last := I;
    end;
    if I <= High(FLastValues) then FLastValues[I] := Values[I];
  end;
  FHaveLast := true;
  S := 'T ' + IntToStr(Tics);
  for I := 0 to Last do
    S := S + ' ' + Words[I];
  WriteRaw(S);
end;

procedure TDemoRecorder.Line(const S: String);
begin
  if FFinished then Exit;
  if FHasPending then
  begin
    FHasPending := false;
    WriteUpdate(0, FPendingValues);
  end;
  WriteRaw(S);
end;

procedure TDemoRecorder.Update(const Tics: Integer; const Values: array of Single);
var
  I: Integer;
begin
  if FFinished then Exit;
  if Tics = 0 then
  begin
    { Kept until an action needs it; a later update replaces it. }
    for I := 0 to Min(High(Values), High(FPendingValues)) do
      FPendingValues[I] := Values[I];
    FHasPending := true;
  end else
  begin
    FHasPending := false;
    WriteUpdate(Tics, Values);
  end;
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
  FHasPending := false;
  Line(Format('E %d %s %s', [Tic, IntToHex(Hash, 8), Summary]));
  FFinished := true;
end;

procedure TDemoRecorder.NextLevel(const State: TJSONObject);
begin
  FFinished := false;
  FHasPending := false;
  { Each level's first update line is written in full. }
  FHaveLast := false;
  Line('L ' + CompactJSON(State));
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
  if (FLines.Count < 3) or ((FLines[0] <> Magic) and (FLines[0] <> MagicVersion1)) or (Copy(FLines[1], 1, 5) <> 'seed ') or
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
  FState := TJSONObject(ExpandJSON(Data));
  FreeAndNil(Data);
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
    Result := TJSONObject(ExpandJSON(Data));
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
                if Words.Count < 2 then Break;
                E.Tics := StrToIntDef(Words[1], 0);
                { "=" or a missing value: the previous line's. }
                for I := 0 to DemoValues - 1 do
                begin
                  if (I + 2 < Words.Count) and (Words[I + 2] <> '=') then
                    FLastValues[I] := HexToSingle(Words[I + 2]);
                  E.Values[I] := FLastValues[I];
                end;
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

{ Ghosts ----------------------------------------------------------------------- }

function ReadGhostTracks(const Demo: TDemoPlayer): TGhostTracks;
var
  E: TDemoEvent;
  Tic, N, L, EndTic: Integer;
  Map: String;
  Next: TJSONObject;
begin
  Result := nil;
  Map := UpperCase(Demo.State.Get('map', ''));
  Tic := Demo.State.Get('tic', Int64(0));
  repeat
    L := Length(Result);
    SetLength(Result, L + 1);
    Result[L].Map := Map;
    Result[L].FinishTic := -1;
    EndTic := -1;
    N := 0;
    while Demo.Next(E) do
      case E.Kind of
        deUpdate:
          begin
            if N >= Length(Result[L].Points) then
              SetLength(Result[L].Points, Max(64, 2 * N));
            Result[L].Points[N].Tic := Tic;
            Result[L].Points[N].X := E.Values[0];
            Result[L].Points[N].Y := E.Values[1];
            Result[L].Points[N].Z := E.Values[2];
            Result[L].Points[N].Angle := E.Values[3];
            Inc(N);
            Tic := Tic + E.Tics;
          end;
        deEnd:
          if Copy(E.Text, Length(E.Text) - 4, 5) = ' exit' then
            Result[L].FinishTic := E.Tics
          else
            EndTic := E.Tics;
        else ;
      end;
    SetLength(Result[L].Points, N);
    Next := Demo.NextLevelState;
    { A next level: this one was finished (format 1 has no "exit"). }
    if (Next <> nil) and (Result[L].FinishTic < 0) then
      Result[L].FinishTic := EndTic;
    if Next = nil then Exit;
    try
      Map := UpperCase(Next.Get('map', ''));
      Tic := Next.Get('tic', Int64(0));
    finally
      FreeAndNil(Next);
    end;
  until false;
end;

function FindGhostTrack(const Tracks: TGhostTracks; const MapName: String; out Track: TGhostTrack): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(Tracks) do
    if SameText(Tracks[I].Map, MapName) and (Length(Tracks[I].Points) > 0) then
    begin
      Track := Tracks[I];
      Exit(true);
    end;
  Track := Default(TGhostTrack);
  Result := false;
end;

end.
