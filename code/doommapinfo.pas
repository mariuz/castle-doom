{ UMAPINFO: the per-map definitions modern PWADs ship in a UMAPINFO lump
  (https://github.com/kraflab/umapinfo): level name and label, the
  intermission's name picture, music, sky, par time, the next and secret
  maps, the story text after a map (with its backdrop and music), the end
  of the game (a picture, the bunny or the cast call) and skipping the
  intermission. LoadMapInfo reads the lump of the loaded WADs (the last
  one wins, like any lump); DoomWorld, DoomDehacked, DoomMusic,
  DoomGraphics, DoomIntermission and DoomFinale ask MapInfoFor before
  their vanilla tables. The "episode" and "bossaction" keys are read but
  not used yet. }
unit DoomMapInfo;

interface

uses Classes, Generics.Collections, DoomWad;

type
  TMapInfoEndGame = (meUnset, meNo, meYes);

  TMapInfoEntry = class
    MapName: String;
    LevelName, LevelPic, Music, SkyTexture, Next, NextSecret: String;
    { Label: the HUD prefix before the level name; LabelClear: none. }
    LabelText: String;
    LabelSet, LabelClear: Boolean;
    ParTime: Integer;
    ParTimeSet: Boolean;
    { Story text after the map ("clear" sets it to '' to drop a default). }
    InterText, InterTextSecret: String;
    InterTextSet, InterTextSecretSet: Boolean;
    InterBackdrop, InterMusic: String;
    EndGame: TMapInfoEndGame;
    EndPic: String;
    EndBunny, EndCast: Boolean;
    NoIntermission: Boolean;
    { Text for the key (the levelname... value), for the log and tests. }
    function Summary: String;
  end;

  TMapInfoList = {$ifdef FPC}specialize{$endif} TObjectList<TMapInfoEntry>;

{ Parse UMAPINFO text into List (entries added; a later MAP block for the
  same map replaces the earlier one). Returns the number of MAP blocks;
  unknown keys are skipped, Errors gets a line per problem. }
function ParseUMapInfo(const Text: String; const List: TMapInfoList; const Errors: TStrings): Integer;

{ Read the UMAPINFO lump of AWad (nothing when it has none). }
procedure LoadMapInfo(const AWad: TDoomWad);

{ The entry for this map (E1M1, MAP01...), nil when UMAPINFO has none. }
function MapInfoFor(const MapName: String): TMapInfoEntry;

{ The next map by UMAPINFO: True with Next set when the entry names one
  ("nextsecret" for the secret exit, else "next"). }
function MapInfoNext(const MapName: String; const Secret: Boolean; out Next: String): Boolean;

implementation

uses SysUtils, CastleLog;

var
  Entries: TMapInfoList;

function TMapInfoEntry.Summary: String;
begin
  Result := Format('%s: "%s" next %s, secret %s, music %s, sky %s, par %d', [MapName, LevelName,
    Next, NextSecret, Music, SkyTexture, ParTime]);
end;

type
  TTokenKind = (tkEnd, tkIdent, tkString, tkNumber, tkSymbol);

  TTokenizer = class
    Text: String;
    Pos_, Line: Integer;
    Kind: TTokenKind;
    Value: String;
    constructor Create(const AText: String);
    procedure Next;
  end;

constructor TTokenizer.Create(const AText: String);
begin
  inherited Create;
  Text := AText;
  Pos_ := 1;
  Line := 1;
  Next;
end;

procedure TTokenizer.Next;
var
  C: Char;
  Start: Integer;
begin
  Value := '';
  { Whitespace and comments. }
  while Pos_ <= Length(Text) do
  begin
    C := Text[Pos_];
    if C = #10 then
    begin
      Inc(Line);
      Inc(Pos_);
    end else
    if C in [#1..' '] then
      Inc(Pos_)
    else
    if (C = '/') and (Pos_ < Length(Text)) and (Text[Pos_ + 1] = '/') then
    begin
      while (Pos_ <= Length(Text)) and (Text[Pos_] <> #10) do Inc(Pos_);
    end else
    if (C = '/') and (Pos_ < Length(Text)) and (Text[Pos_ + 1] = '*') then
    begin
      Inc(Pos_, 2);
      while (Pos_ < Length(Text)) and not ((Text[Pos_] = '*') and (Text[Pos_ + 1] = '/')) do
      begin
        if Text[Pos_] = #10 then Inc(Line);
        Inc(Pos_);
      end;
      Inc(Pos_, 2);
    end else
      Break;
  end;
  if Pos_ > Length(Text) then
  begin
    Kind := tkEnd;
    Exit;
  end;
  C := Text[Pos_];
  if C = '"' then
  begin
    Kind := tkString;
    Inc(Pos_);
    while (Pos_ <= Length(Text)) and (Text[Pos_] <> '"') do
    begin
      if (Text[Pos_] = '\') and (Pos_ < Length(Text)) then
      begin
        Inc(Pos_);
        if Text[Pos_] = 'n' then Value := Value + #10 else Value := Value + Text[Pos_];
      end else
      begin
        if Text[Pos_] = #10 then Inc(Line);
        Value := Value + Text[Pos_];
      end;
      Inc(Pos_);
    end;
    Inc(Pos_);
  end else
  if C in ['A'..'Z', 'a'..'z', '_'] then
  begin
    Kind := tkIdent;
    Start := Pos_;
    while (Pos_ <= Length(Text)) and (Text[Pos_] in ['A'..'Z', 'a'..'z', '0'..'9', '_']) do Inc(Pos_);
    Value := Copy(Text, Start, Pos_ - Start);
  end else
  if C in ['0'..'9', '-', '+'] then
  begin
    Kind := tkNumber;
    Start := Pos_;
    Inc(Pos_);
    while (Pos_ <= Length(Text)) and (Text[Pos_] in ['0'..'9', '.']) do Inc(Pos_);
    Value := Copy(Text, Start, Pos_ - Start);
  end else
  begin
    Kind := tkSymbol;
    Value := C;
    Inc(Pos_);
  end;
end;

function ParseUMapInfo(const Text: String; const List: TMapInfoList; const Errors: TStrings): Integer;
var
  T: TTokenizer;
  E: TMapInfoEntry;
  Key: String;
  Values: TStringList;
  ValueKinds: array of TTokenKind;

  procedure Error(const Msg: String);
  begin
    if Errors <> nil then
      Errors.Add(Format('UMAPINFO line %d: %s', [T.Line, Msg]));
  end;

  function First: String;
  begin
    if Values.Count > 0 then Result := Values[0] else Result := '';
  end;

  function IsClear: Boolean;
  begin
    Result := (Values.Count = 1) and (ValueKinds[0] = tkIdent) and SameText(Values[0], 'clear');
  end;

  function AsBool: Boolean;
  begin
    Result := SameText(First, 'true');
  end;

  function JoinedText: String;
  var
    J: Integer;
  begin
    Result := '';
    for J := 0 to Values.Count - 1 do
    begin
      if J > 0 then Result := Result + #10;
      Result := Result + Values[J];
    end;
  end;

  procedure Apply;
  begin
    if SameText(Key, 'levelname') then E.LevelName := First
    else if SameText(Key, 'label') then
    begin
      if IsClear then E.LabelClear := true else
      begin
        E.LabelSet := true;
        E.LabelText := First;
      end;
    end
    else if SameText(Key, 'levelpic') then E.LevelPic := UpperCase(First)
    else if SameText(Key, 'music') then E.Music := UpperCase(First)
    else if SameText(Key, 'skytexture') then E.SkyTexture := UpperCase(First)
    else if SameText(Key, 'next') then E.Next := UpperCase(First)
    else if SameText(Key, 'nextsecret') then E.NextSecret := UpperCase(First)
    else if SameText(Key, 'partime') then
    begin
      E.ParTime := StrToIntDef(First, 0);
      E.ParTimeSet := true;
    end
    else if SameText(Key, 'intertext') then
    begin
      E.InterTextSet := true;
      if IsClear then E.InterText := '' else E.InterText := JoinedText;
    end
    else if SameText(Key, 'intertextsecret') then
    begin
      E.InterTextSecretSet := true;
      if IsClear then E.InterTextSecret := '' else E.InterTextSecret := JoinedText;
    end
    else if SameText(Key, 'interbackdrop') then E.InterBackdrop := UpperCase(First)
    else if SameText(Key, 'intermusic') then E.InterMusic := UpperCase(First)
    else if SameText(Key, 'endgame') then
    begin
      if AsBool then E.EndGame := meYes else E.EndGame := meNo;
    end
    else if SameText(Key, 'endpic') then E.EndPic := UpperCase(First)
    else if SameText(Key, 'endbunny') then E.EndBunny := AsBool
    else if SameText(Key, 'endcast') then E.EndCast := AsBool
    else if SameText(Key, 'nointermission') then E.NoIntermission := AsBool;
    { Other keys (author, episode, bossaction, exitpic, enterpic...) are
      accepted and ignored. }
  end;

  procedure AddEntry;
  var
    J: Integer;
  begin
    for J := List.Count - 1 downto 0 do
      if List[J].MapName = E.MapName then
        List.Delete(J);
    List.Add(E);
  end;

begin
  Result := 0;
  T := TTokenizer.Create(Text);
  Values := TStringList.Create;
  try
    while T.Kind <> tkEnd do
    begin
      if not ((T.Kind = tkIdent) and SameText(T.Value, 'map')) then
      begin
        Error('expected MAP, found "' + T.Value + '"');
        T.Next;
        Continue;
      end;
      T.Next;
      E := TMapInfoEntry.Create;
      E.MapName := UpperCase(T.Value);
      T.Next;
      if T.Value <> '{' then
      begin
        Error('expected { after MAP ' + E.MapName);
        FreeAndNil(E);
        Continue;
      end;
      T.Next;
      while (T.Kind <> tkEnd) and (T.Value <> '}') do
      begin
        if T.Kind <> tkIdent then
        begin
          Error('expected a key, found "' + T.Value + '"');
          T.Next;
          Continue;
        end;
        Key := T.Value;
        T.Next;
        if T.Value <> '=' then
        begin
          Error('expected = after ' + Key);
          Continue;
        end;
        T.Next;
        Values.Clear;
        SetLength(ValueKinds, 0);
        repeat
          if T.Kind in [tkString, tkNumber, tkIdent] then
          begin
            Values.Add(T.Value);
            SetLength(ValueKinds, Length(ValueKinds) + 1);
            ValueKinds[High(ValueKinds)] := T.Kind;
            T.Next;
          end else
            Break;
          if T.Value = ',' then T.Next else Break;
        until T.Kind = tkEnd;
        Apply;
      end;
      T.Next; { the closing brace }
      AddEntry;
      Inc(Result);
    end;
  finally
    FreeAndNil(Values);
    FreeAndNil(T);
  end;
end;

procedure LoadMapInfo(const AWad: TDoomWad);
var
  Lump, N: Integer;
  Bytes: TBytes;
  Text: String;
  Errors: TStringList;
  I: Integer;
begin
  Entries.Clear;
  Lump := AWad.FindLump('UMAPINFO');
  if Lump < 0 then Exit;
  Bytes := AWad.LumpBytes(Lump);
  SetLength(Text, Length(Bytes));
  if Length(Bytes) > 0 then
    Move(Bytes[0], Text[1], Length(Bytes));
  Errors := TStringList.Create;
  try
    N := ParseUMapInfo(Text, Entries, Errors);
    for I := 0 to Errors.Count - 1 do
      WritelnWarning('MapInfo', Errors[I]);
  finally
    FreeAndNil(Errors);
  end;
  WritelnLog('MapInfo', 'UMAPINFO: %d maps', [N]);
  for I := 0 to Entries.Count - 1 do
    WritelnLog('MapInfo', Entries[I].Summary);
end;

function MapInfoFor(const MapName: String): TMapInfoEntry;
var
  I: Integer;
  N: String;
begin
  N := UpperCase(MapName);
  for I := 0 to Entries.Count - 1 do
    if Entries[I].MapName = N then
      Exit(Entries[I]);
  Result := nil;
end;

function MapInfoNext(const MapName: String; const Secret: Boolean; out Next: String): Boolean;
var
  E: TMapInfoEntry;
begin
  Next := '';
  E := MapInfoFor(MapName);
  if E = nil then Exit(false);
  if Secret and (E.NextSecret <> '') then
    Next := E.NextSecret
  else
    Next := E.Next;
  Result := Next <> '';
end;

initialization
  Entries := TMapInfoList.Create(true);
finalization
  FreeAndNil(Entries);
end.
