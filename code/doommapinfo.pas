{ UMAPINFO: the per-map definitions modern PWADs ship in a UMAPINFO lump
  (https://github.com/kraflab/umapinfo): level name and label, the
  intermission's name picture, music, sky, par time, the next and secret
  maps, the story text after a map (with its backdrop and music), the end
  of the game (a picture, the bunny or the cast call) and skipping the
  intermission, new episodes for the New Game menu (DoomMenu) and boss
  actions (what the death of the last monster of a type does,
  DoomWorld.BossDeath). LoadMapInfo reads the lump of the loaded WADs
  (the last one wins, like any lump); DoomWorld, DoomDehacked, DoomMusic,
  DoomGraphics, DoomIntermission and DoomFinale ask MapInfoFor before
  their vanilla tables.

  Without a UMAPINFO lump, ZDoom's ZMAPINFO or MAPINFO is read into the
  same entries (ParseZMapInfo: the new syntax with braces and the old
  line-based one): maps (title, title patch, next / secret next, sky,
  par, music, enter / exit pictures, no intermission, the EndGame
  targets), clusters (their exit / enter texts become the story text
  after the last map of a cluster, with the cluster's flat or picture and
  music), episodes and defaultmap. LANGUAGE lookups ("lookup", "$NAME")
  of titles, cluster texts, episode names and music ("$MUSIC_X" names
  D_ plus the string) resolve through the strings of the loaded WADs
  (TDoomStrings: their LANGUAGE lumps, ParseLanguage, and BEX strings);
  an unknown name, or a map's own vanilla title (HUSTR_E1M1), leaves the
  vanilla value. }
unit DoomMapInfo;

interface

uses Classes, Generics.Collections, DoomWad, DoomDehacked;

type
  TMapInfoEndGame = (meUnset, meNo, meYes);

  { "bossaction = BaronOfHell, 23, 666": when the last monster of the
    THINGS type ThingType dies, line special Special acts on Tag. }
  TMapInfoBossAction = record
    ThingType, Special, Tag: Integer;
  end;

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
    { A flat, else a patch drawn at the top left (UMAPINFO allows both). }
    InterBackdrop, InterMusic: String;
    { Intermission backgrounds: ExitPic behind this map's statistics,
      EnterPic behind "Entering" this map (patches). }
    ExitPic, EnterPic: String;
    EndGame: TMapInfoEndGame;
    EndPic: String;
    EndBunny, EndCast: Boolean;
    NoIntermission: Boolean;
    { "episode = patch, name, key": this map starts a New Game episode;
      EpisodeClear ("episode = clear") drops the episodes defined before
      (vanilla's included). }
    EpisodeSet, EpisodeClear: Boolean;
    EpisodePatch, EpisodeName, EpisodeKey: String;
    { Boss actions replace the vanilla ones of the map once any is given
      ("bossaction = clear" gives none). }
    BossActionsSet: Boolean;
    BossActions: array of TMapInfoBossAction;
    { Text for the key (the levelname... value), for the log and tests. }
    function Summary: String;
    { ZDoom's defaultmap: the map settings of Src (not the map name, the
      episode or the boss actions). }
    procedure CopySettings(const Src: TMapInfoEntry);
  end;

  TMapInfoList = {$ifdef FPC}specialize{$endif} TObjectList<TMapInfoEntry>;

{ Parse UMAPINFO text into List (entries added; a later MAP block for the
  same map replaces the earlier one). Returns the number of MAP blocks;
  unknown keys are skipped, Errors gets a line per problem. }
function ParseUMapInfo(const Text: String; const List: TMapInfoList; const Errors: TStrings): Integer;

{ Parse ZDoom's ZMAPINFO / MAPINFO text into List (entries added, a later
  map replaces an earlier one). Returns the number of maps; AWad (may be
  nil) gives the lumps "exittextislump" names. Unknown blocks and keys are
  skipped. }
function ParseZMapInfo(const Text: String; const List: TMapInfoList; const Errors: TStrings;
  const AWad: TDoomWad = nil; const Strings: TDoomStrings = nil): Integer;

{ Parse a ZDoom LANGUAGE lump into Values ("NAME=text" lines, names in
  upper case; an existing name is replaced): the strings of sections
  for English ([enu], [en], [eng]) win over [default] ones, other
  languages are skipped, and so are "$ifgame(...)" lines for games other
  than Doom. Returns the number of strings set. }
function ParseLanguage(const Text: String; const Values: TStrings; const Errors: TStrings = nil): Integer;

{ Read the UMAPINFO lump of AWad, else its ZMAPINFO or MAPINFO (nothing
  when it has none). }
procedure LoadMapInfo(const AWad: TDoomWad);

{ The entry for this map (E1M1, MAP01...), nil when UMAPINFO has none. }
function MapInfoFor(const MapName: String): TMapInfoEntry;

{ All entries, in the lump's order (for the episodes). }
function MapInfoEntries: TMapInfoList;

{ The THINGS type of a ZDoom class name used by bossaction (BaronOfHell
  -> 3003), 0 for an unknown one; a number is taken as a type. }
function MapInfoThingType(const ClassName: String): Integer;

{ The next map by UMAPINFO: True with Next set when the entry names one
  ("nextsecret" for the secret exit, else "next"). }
function MapInfoNext(const MapName: String; const Secret: Boolean; out Next: String): Boolean;

implementation

uses SysUtils, CastleLog;

var
  Entries: TMapInfoList;

function TMapInfoEntry.Summary: String;
begin
  if EpisodeClear then
    Exit('episodes cleared');
  if EpisodeSet and (LevelName = '') and (Next = '') and (EndGame = meUnset) then
    Exit(Format('episode "%s" (key %s, patch %s) starts %s', [EpisodeName, EpisodeKey, EpisodePatch, MapName]));
  Result := Format('%s: "%s" next %s, secret %s, music %s, sky %s, par %d', [MapName, LevelName,
    Next, NextSecret, Music, SkyTexture, ParTime]);
  if InterText <> '' then
    Result := Result + Format(', text of %d characters on %s', [Length(InterText), InterBackdrop]);
  if EndGame = meYes then
  begin
    if EndCast then Result := Result + ', ends with the cast'
    else if EndBunny then Result := Result + ', ends with the bunny'
    else Result := Result + ', ends with ' + EndPic;
  end;
  if ExitPic <> '' then Result := Result + ', exit picture ' + ExitPic;
  if EnterPic <> '' then Result := Result + ', enter picture ' + EnterPic;
end;

procedure TMapInfoEntry.CopySettings(const Src: TMapInfoEntry);
begin
  LevelName := Src.LevelName;
  LevelPic := Src.LevelPic;
  Music := Src.Music;
  SkyTexture := Src.SkyTexture;
  Next := Src.Next;
  NextSecret := Src.NextSecret;
  ParTime := Src.ParTime;
  ParTimeSet := Src.ParTimeSet;
  ExitPic := Src.ExitPic;
  EnterPic := Src.EnterPic;
  NoIntermission := Src.NoIntermission;
  EndGame := Src.EndGame;
  EndPic := Src.EndPic;
  EndBunny := Src.EndBunny;
  EndCast := Src.EndCast;
end;

type
  TTokenKind = (tkEnd, tkIdent, tkString, tkNumber, tkSymbol);

  TTokenizer = class
    Text: String;
    Pos_, Line: Integer;
    { Old MAPINFO: ";" starts a comment too. }
    SemicolonComments: Boolean;
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
    if ((C = '/') and (Pos_ < Length(Text)) and (Text[Pos_ + 1] = '/')) or
       ((C = ';') and SemicolonComments) then
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
    else if SameText(Key, 'exitpic') then E.ExitPic := UpperCase(First)
    else if SameText(Key, 'enterpic') then E.EnterPic := UpperCase(First)
    else if SameText(Key, 'intermusic') then E.InterMusic := UpperCase(First)
    else if SameText(Key, 'endgame') then
    begin
      if AsBool then E.EndGame := meYes else E.EndGame := meNo;
    end
    else if SameText(Key, 'endpic') then E.EndPic := UpperCase(First)
    else if SameText(Key, 'endbunny') then E.EndBunny := AsBool
    else if SameText(Key, 'endcast') then E.EndCast := AsBool
    else if SameText(Key, 'nointermission') then E.NoIntermission := AsBool
    else if SameText(Key, 'episode') then
    begin
      E.EpisodeSet := true;
      if IsClear then E.EpisodeClear := true else
      begin
        E.EpisodeClear := false;
        E.EpisodePatch := UpperCase(First);
        if Values.Count > 1 then E.EpisodeName := Values[1];
        if Values.Count > 2 then E.EpisodeKey := Values[2];
      end;
    end
    else if SameText(Key, 'bossaction') then
    begin
      E.BossActionsSet := true;
      if IsClear then
        SetLength(E.BossActions, 0)
      else if (Values.Count >= 3) and (MapInfoThingType(Values[0]) > 0) then
      begin
        SetLength(E.BossActions, Length(E.BossActions) + 1);
        E.BossActions[High(E.BossActions)].ThingType := MapInfoThingType(Values[0]);
        E.BossActions[High(E.BossActions)].Special := StrToIntDef(Values[1], 0);
        E.BossActions[High(E.BossActions)].Tag := StrToIntDef(Values[2], 0);
      end else
        Error('bossaction needs a known thing, a special and a tag');
    end;
    { Other keys (author...) are accepted and ignored. }
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

{ ZDoom MAPINFO ---------------------------------------------------------------- }

type
  TMapInfoCluster = class
    Num: Integer;
    ExitText, EnterText, Flat, Pic, Music: String;
  end;
  TMapInfoClusterList = {$ifdef FPC}specialize{$endif} TObjectList<TMapInfoCluster>;

function ParseZMapInfo(const Text: String; const List: TMapInfoList; const Errors: TStrings;
  const AWad: TDoomWad; const Strings: TDoomStrings): Integer;
var
  T: TTokenizer;
  Values: TStringList;
  Clusters: TMapInfoClusterList;
  ClusterOfMap: TStringList;
  Episodes: TMapInfoList;
  Defaults: TMapInfoEntry;
  ClearEpisodes: Boolean;
  Key: String;
  ExitIsLump, EnterIsLump: Boolean;

  procedure Error(const Msg: String);
  begin
    if Errors <> nil then
      Errors.Add(Format('MAPINFO line %d: %s', [T.Line, Msg]));
  end;

  function First: String;
  begin
    if Values.Count > 0 then Result := Values[0] else Result := '';
  end;

  { A value is a LANGUAGE lookup: "$NAME" or "lookup, NAME". }
  function IsLookup: Boolean;
  begin
    Result := ((Values.Count > 0) and (Copy(Values[0], 1, 1) = '$')) or
      ((Values.Count > 0) and SameText(Values[0], 'lookup'));
  end;

  { The text a lookup value names ('' when unknown). }
  function Lookup(const Name: String): String;
  begin
    if Strings = nil then Exit('');
    Result := Strings.Get(Name, '');
  end;

  function LookupValue: String;
  begin
    Result := '';
    if Values.Count = 0 then Exit;
    if Copy(Values[0], 1, 1) = '$' then
      Result := Lookup(Copy(Values[0], 2, MaxInt))
    else if Values.Count > 1 then
      Result := Lookup(Values[1]);
  end;

  { "$MUSIC_RUNNIN" names the lump D_ plus the string (ZDoom's rule). }
  function LookupMusic: String;
  begin
    Result := LookupValue;
    if Result <> '' then Result := 'D_' + UpperCase(Result);
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

  function LumpText(const Name: String): String;
  var
    Lump: Integer;
    Bytes: TBytes;
  begin
    Result := '';
    if AWad = nil then Exit;
    Lump := AWad.FindLump(UpperCase(Name));
    if Lump < 0 then Exit;
    Bytes := AWad.LumpBytes(Lump);
    SetLength(Result, Length(Bytes));
    if Length(Bytes) > 0 then
      Move(Bytes[0], Result[1], Length(Bytes));
    Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  end;

  { A key's values: the tokens after it (and an optional "=") on its line,
    a trailing comma carrying them over to the next line. }
  procedure ReadValues(const KeyLine: Integer);
  var
    LastLine: Integer;
    AfterComma: Boolean;
  begin
    Values.Clear;
    LastLine := KeyLine;
    if T.Value = '=' then
    begin
      T.Next;
      AfterComma := true;
    end else
      AfterComma := false;
    while (T.Kind in [tkString, tkNumber, tkIdent]) and ((T.Line = LastLine) or AfterComma) do
    begin
      Values.Add(T.Value);
      LastLine := T.Line;
      T.Next;
      AfterComma := T.Value = ',';
      if AfterComma then T.Next;
    end;
  end;

  { "map MAP01 "Title"", "map MAP01 lookup "HUSTR_1"" or Hexen's numbers. }
  function MapNameOf(const S: String): String;
  var
    N: Integer;
  begin
    if TryStrToInt(S, N) then
      Result := Format('MAP%2.2d', [N])
    else
      Result := UpperCase(S);
  end;

  { next / secretnext: a map, or ZDoom's ending names. }
  procedure ApplyNext(const E: TMapInfoEntry; const Secret: Boolean);
  var
    N: String;
  begin
    N := UpperCase(First);
    if (N = 'ENDPIC') and (Values.Count > 1) then
    begin
      E.EndGame := meYes;
      E.EndPic := UpperCase(Values[1]);
    end else
    if (Copy(N, 1, 7) = 'ENDGAME') or (N = 'ENDTITLE') or (N = 'ENDSEQUENCE') then
    begin
      E.EndGame := meYes;
      if (N = 'ENDGAME3') or (N = 'ENDGAMEW') then E.EndBunny := true
      else if (N = 'ENDGAMEC') then E.EndCast := true
      else if N = 'ENDGAME2' then E.EndPic := 'VICTORY2'
      else if N = 'ENDGAME4' then E.EndPic := 'ENDPIC'
      else if N = 'ENDGAME1' then E.EndPic := 'CREDIT';
    end else
    if Secret then
      E.NextSecret := MapNameOf(N)
    else
      E.Next := MapNameOf(N);
  end;

  procedure ApplyMapKey(const E: TMapInfoEntry);
  begin
    if SameText(Key, 'next') then ApplyNext(E, false)
    else if SameText(Key, 'secretnext') or SameText(Key, 'secret') then ApplyNext(E, true)
    else if SameText(Key, 'titlepatch') then E.LevelPic := UpperCase(First)
    else if SameText(Key, 'sky1') then E.SkyTexture := UpperCase(First)
    else if SameText(Key, 'cluster') then ClusterOfMap.Values[E.MapName] := First
    else if SameText(Key, 'par') then
    begin
      E.ParTime := StrToIntDef(First, 0);
      E.ParTimeSet := true;
    end
    else if SameText(Key, 'music') then
    begin
      if not IsLookup then E.Music := UpperCase(First)
      else if LookupMusic <> '' then E.Music := LookupMusic;
    end
    else if SameText(Key, 'nointermission') then E.NoIntermission := true
    else if SameText(Key, 'exitpic') then
    begin
      { "$name" is an intermission script, not a picture. }
      if not IsLookup then E.ExitPic := UpperCase(First);
    end
    else if SameText(Key, 'enterpic') then
    begin
      if not IsLookup then E.EnterPic := UpperCase(First);
    end;
    { levelnum, sucktime, flags of other ports... are skipped. }
  end;

  procedure ApplyClusterKey(const C: TMapInfoCluster);
  begin
    if SameText(Key, 'exittext') then
    begin
      if not IsLookup then C.ExitText := JoinedText
      else C.ExitText := LookupValue;
    end
    else if SameText(Key, 'entertext') then
    begin
      if not IsLookup then C.EnterText := JoinedText
      else C.EnterText := LookupValue;
    end
    else if SameText(Key, 'exittextislump') then ExitIsLump := true
    else if SameText(Key, 'entertextislump') then EnterIsLump := true
    else if SameText(Key, 'flat') then C.Flat := UpperCase(First)
    else if SameText(Key, 'pic') then C.Pic := UpperCase(First)
    else if SameText(Key, 'music') then
    begin
      if not IsLookup then C.Music := UpperCase(First)
      else C.Music := LookupMusic;
    end;
  end;

  { "cluster N" followed by an opening brace is a new-style block; alone
    it is an old-style map's key. }
  function ClusterBlockFollows: Boolean;
  var
    SavePos, SaveLine: Integer;
    SaveKind: TTokenKind;
    SaveValue: String;
  begin
    SavePos := T.Pos_;
    SaveLine := T.Line;
    SaveKind := T.Kind;
    SaveValue := T.Value;
    T.Next;
    T.Next;
    Result := T.Value = '{';
    T.Pos_ := SavePos;
    T.Line := SaveLine;
    T.Kind := SaveKind;
    T.Value := SaveValue;
  end;

  { A top-level keyword ends an old-style (brace-less) block. }
  function IsTopLevel(const S: String): Boolean;
  begin
    Result := SameText(S, 'map') or SameText(S, 'defaultmap') or SameText(S, 'adddefaultmap') or
      (SameText(S, 'cluster') and ClusterBlockFollows) or SameText(S, 'clusterdef') or SameText(S, 'episode') or
      SameText(S, 'clearepisodes') or SameText(S, 'include') or SameText(S, 'gameinfo') or
      SameText(S, 'skill') or SameText(S, 'clearskills') or SameText(S, 'intermission') or
      SameText(S, 'automap') or SameText(S, 'doomednums') or SameText(S, 'spawnnums') or
      SameText(S, 'conversationids') or SameText(S, 'damagetype') or SameText(S, 'cutscenes');
  end;

  { The keys of a block: inside braces, or old style up to the next
    top-level keyword. Calls Apply for each with Key and Values set. }
  type
    TApplyKind = (akMap, akCluster, akEpisode, akSkip);

  procedure ReadBlock(const Kind: TApplyKind; const E: TMapInfoEntry; const C: TMapInfoCluster);
  var
    Braced: Boolean;
    KeyLine: Integer;
  begin
    Braced := T.Value = '{';
    if Braced then T.Next;
    while T.Kind <> tkEnd do
    begin
      if Braced and (T.Value = '}') then
      begin
        T.Next;
        Exit;
      end;
      if (not Braced) and (T.Kind = tkIdent) and IsTopLevel(T.Value) then Exit;
      if T.Kind <> tkIdent then
      begin
        { A nested block of another port, or junk: skip it. }
        if T.Value = '{' then
          ReadBlock(akSkip, nil, nil)
        else
          T.Next;
        Continue;
      end;
      Key := T.Value;
      KeyLine := T.Line;
      T.Next;
      ReadValues(KeyLine);
      case Kind of
        akMap: ApplyMapKey(E);
        akCluster: ApplyClusterKey(C);
        akEpisode:
          if SameText(Key, 'name') then
          begin
            if not IsLookup then E.EpisodeName := First
            else E.EpisodeName := LookupValue;
          end
          else if SameText(Key, 'picname') then E.EpisodePatch := UpperCase(First)
          else if SameText(Key, 'key') then E.EpisodeKey := First;
        else ;
      end;
    end;
  end;

  function ClusterNum(const Num: Integer): TMapInfoCluster;
  var
    C: TMapInfoCluster;
  begin
    for C in Clusters do
      if C.Num = Num then Exit(C);
    Result := TMapInfoCluster.Create;
    Result.Num := Num;
    Clusters.Add(Result);
  end;

  { The map's own vanilla title (HUSTR_E1M1 for E1M1, HUSTR_1 for MAP01)
    stays vanilla, with its intermission patch; another name is shown as
    it is. }
  procedure LookupTitle(const E: TMapInfoEntry; const Name: String);
  var
    VanillaKey: String;
  begin
    if (Copy(E.MapName, 1, 3) = 'MAP') then
      VanillaKey := 'HUSTR_' + IntToStr(StrToIntDef(Copy(E.MapName, 4, 2), 0))
    else
      VanillaKey := 'HUSTR_' + E.MapName;
    if SameText(Name, VanillaKey) then Exit;
    E.LevelName := Lookup(Name);
    E.LabelClear := E.LevelName <> '';
  end;

  procedure ReadMap;
  var
    E: TMapInfoEntry;
    J: Integer;
  begin
    E := TMapInfoEntry.Create;
    E.CopySettings(Defaults);
    E.MapName := MapNameOf(T.Value);
    T.Next;
    { The title: a string, or "lookup" and a LANGUAGE name (or "$NAME").
      A looked-up title is shown as it is, like vanilla's HUSTR strings
      that carry their own "E1M1: " (no label). }
    if (T.Kind = tkIdent) and SameText(T.Value, 'lookup') then
    begin
      T.Next;
      LookupTitle(E, T.Value);
      T.Next;
    end else
    if (T.Kind = tkString) and (Copy(T.Value, 1, 1) = '$') then
    begin
      LookupTitle(E, Copy(T.Value, 2, MaxInt));
      T.Next;
    end else
    if T.Kind = tkString then
    begin
      E.LevelName := T.Value;
      T.Next;
    end;
    ReadBlock(akMap, E, nil);
    for J := List.Count - 1 downto 0 do
      if List[J].MapName = E.MapName then
        List.Delete(J);
    List.Add(E);
    Inc(Result);
  end;

  procedure ReadCluster;
  var
    C: TMapInfoCluster;
  begin
    C := ClusterNum(StrToIntDef(T.Value, 0));
    T.Next;
    ExitIsLump := false;
    EnterIsLump := false;
    ReadBlock(akCluster, nil, C);
    if ExitIsLump then C.ExitText := LumpText(C.ExitText);
    if EnterIsLump then C.EnterText := LumpText(C.EnterText);
  end;

  procedure ReadEpisode;
  var
    E: TMapInfoEntry;
  begin
    E := TMapInfoEntry.Create;
    E.MapName := MapNameOf(T.Value);
    E.EpisodeSet := true;
    T.Next;
    { "teaser MAPxx" for shareware: ignored. }
    if (T.Kind = tkIdent) and SameText(T.Value, 'teaser') then
    begin
      T.Next;
      T.Next;
    end;
    ReadBlock(akEpisode, E, nil);
    Episodes.Add(E);
  end;

  { The story text after each map that leaves its cluster: the old
    cluster's exit text, else the new one's enter text. }
  procedure ApplyClusters;
  var
    E: TMapInfoEntry;
    Own, Other: TMapInfoCluster;

    function ClusterOf(const MapName: String): TMapInfoCluster;
    var
      Num: Integer;
    begin
      Num := StrToIntDef(ClusterOfMap.Values[MapName], -1);
      if Num < 0 then Exit(nil);
      Result := ClusterNum(Num);
    end;

    procedure Story(const NextMap: String; const Secret: Boolean);
    var
      Text: String;
      C: TMapInfoCluster;
    begin
      Other := nil;
      if NextMap <> '' then Other := ClusterOf(NextMap);
      if (NextMap <> '') and (Other = Own) then Exit;
      Text := '';
      C := nil;
      if (Own <> nil) and (Own.ExitText <> '') then
      begin
        Text := Own.ExitText;
        C := Own;
      end else
      if (Other <> nil) and (Other.EnterText <> '') then
      begin
        Text := Other.EnterText;
        C := Other;
      end;
      if Text = '' then Exit;
      if Secret then
      begin
        E.InterTextSecret := Text;
        E.InterTextSecretSet := true;
      end else
      begin
        E.InterText := Text;
        E.InterTextSet := true;
      end;
      if C.Flat <> '' then E.InterBackdrop := C.Flat
      else if C.Pic <> '' then E.InterBackdrop := C.Pic;
      if C.Music <> '' then E.InterMusic := C.Music;
    end;

  begin
    for E in List do
    begin
      Own := ClusterOf(E.MapName);
      if (E.Next <> '') or (E.EndGame = meYes) then
        Story(E.Next, false);
      if E.NextSecret <> '' then
        Story(E.NextSecret, true);
    end;
  end;

var
  E: TMapInfoEntry;
begin
  Result := 0;
  T := TTokenizer.Create('');
  T.SemicolonComments := true;
  T.Text := Text;
  T.Pos_ := 1;
  T.Line := 1;
  T.Next;
  Values := TStringList.Create;
  Clusters := TMapInfoClusterList.Create(true);
  ClusterOfMap := TStringList.Create;
  Episodes := TMapInfoList.Create(false);
  Defaults := TMapInfoEntry.Create;
  ClearEpisodes := false;
  try
    while T.Kind <> tkEnd do
    begin
      if T.Kind <> tkIdent then
      begin
        if T.Value = '{' then ReadBlock(akSkip, nil, nil) else T.Next;
        Continue;
      end;
      Key := T.Value;
      T.Next;
      if SameText(Key, 'map') then
        ReadMap
      else if SameText(Key, 'defaultmap') then
      begin
        FreeAndNil(Defaults);
        Defaults := TMapInfoEntry.Create;
        ReadBlock(akMap, Defaults, nil);
      end
      else if SameText(Key, 'adddefaultmap') then
        ReadBlock(akMap, Defaults, nil)
      else if SameText(Key, 'cluster') or SameText(Key, 'clusterdef') then
        ReadCluster
      else if SameText(Key, 'episode') then
        ReadEpisode
      else if SameText(Key, 'clearepisodes') then
        ClearEpisodes := true
      else if SameText(Key, 'include') then
      begin
        Error('include is not supported');
        T.Next;
      end else
      begin
        { gameinfo, skill, intermission...: the name, then the block. }
        while (T.Kind <> tkEnd) and (T.Value <> '{') and not ((T.Kind = tkIdent) and IsTopLevel(T.Value)) do
          T.Next;
        if T.Value = '{' then ReadBlock(akSkip, nil, nil);
      end;
    end;
    ApplyClusters;
    { Episodes go last, after a clearing entry ("clearepisodes"). }
    if ClearEpisodes then
    begin
      E := TMapInfoEntry.Create;
      E.EpisodeSet := true;
      E.EpisodeClear := true;
      List.Add(E);
    end;
    for E in Episodes do
      List.Add(E);
  finally
    FreeAndNil(Defaults);
    FreeAndNil(Episodes);
    FreeAndNil(ClusterOfMap);
    FreeAndNil(Clusters);
    FreeAndNil(Values);
    FreeAndNil(T);
  end;
end;

function ParseLanguage(const Text: String; const Values: TStrings; const Errors: TStrings): Integer;
var
  T: TTokenizer;
  { 2: an English section, 1: [default] only, 0: another language. }
  Rank: Integer;
  Ranks: TStringList;
  Name, Value, Game: String;
  Skip: Boolean;

  procedure Error(const Msg: String);
  begin
    if Errors <> nil then
      Errors.Add(Format('LANGUAGE line %d: %s', [T.Line, Msg]));
  end;

  procedure ReadSection;
  var
    L: String;
  begin
    Rank := 0;
    T.Next;
    while (T.Kind <> tkEnd) and (T.Value <> ']') do
    begin
      L := LowerCase(T.Value);
      if (L = 'enu') or (L = 'en') or (L = 'eng') then
        Rank := 2
      else if ((L = 'default') or (L = '*')) and (Rank < 1) then
        Rank := 1;
      T.Next;
    end;
    T.Next;
  end;

  procedure SetValue;
  var
    Idx, Old: Integer;
  begin
    Name := UpperCase(Name);
    Old := StrToIntDef(Ranks.Values[Name], 0);
    { Within a lump, English beats [default] whatever their order. }
    if Rank < Old then Exit;
    Ranks.Values[Name] := IntToStr(Rank);
    Idx := Values.IndexOfName(Name);
    if Idx >= 0 then
      Values.ValueFromIndex[Idx] := Value
    else
      Values.Add(Name + '=' + Value);
    Inc(Result);
  end;

begin
  Result := 0;
  { Without a section header the strings count as [default]. }
  Rank := 1;
  T := TTokenizer.Create('');
  Ranks := TStringList.Create;
  try
    T.Text := Text;
    T.Pos_ := 1;
    T.Line := 1;
    T.Next;
    while T.Kind <> tkEnd do
    begin
      if T.Value = '[' then
      begin
        ReadSection;
        Continue;
      end;
      Skip := false;
      { "$ifgame(doom2) NAME = ...": only Doom's games. }
      if T.Value = '$' then
      begin
        T.Next;
        if SameText(T.Value, 'ifgame') then
        begin
          T.Next;
          if T.Value = '(' then T.Next;
          Game := LowerCase(T.Value);
          Skip := not ((Game = 'doom') or (Game = 'doom1') or (Game = 'doom2') or
            (Game = 'plutonia') or (Game = 'tnt') or (Game = 'freedoom') or (Game = 'any'));
          T.Next;
          if T.Value = ')' then T.Next;
        end;
      end;
      if T.Kind <> tkIdent then
      begin
        Error('a string name expected, not "' + T.Value + '"');
        T.Next;
        Continue;
      end;
      Name := T.Value;
      T.Next;
      if T.Value <> '=' then
      begin
        Error('"=" expected after ' + Name);
        Continue;
      end;
      T.Next;
      { Strings in a row join: "line one\n" "line two"; }
      Value := '';
      while T.Kind = tkString do
      begin
        Value := Value + T.Value;
        T.Next;
      end;
      if T.Value = ';' then
        T.Next
      else
        Error('";" expected after ' + Name);
      if (Rank > 0) and not Skip then
        SetValue;
    end;
  finally
    FreeAndNil(Ranks);
    FreeAndNil(T);
  end;
end;

procedure LoadMapInfo(const AWad: TDoomWad);
var
  Lump, N: Integer;
  Bytes: TBytes;
  Text, LumpName: String;
  Errors: TStringList;
  Strings: TDoomStrings;
  I: Integer;
begin
  Entries.Clear;
  { UMAPINFO first (the Doom ports' own format), then ZDoom's. }
  LumpName := 'UMAPINFO';
  Lump := AWad.FindLump(LumpName);
  if Lump < 0 then
  begin
    LumpName := 'ZMAPINFO';
    Lump := AWad.FindLump(LumpName);
  end;
  if Lump < 0 then
  begin
    LumpName := 'MAPINFO';
    Lump := AWad.FindLump(LumpName);
  end;
  if Lump < 0 then Exit;
  Bytes := AWad.LumpBytes(Lump);
  SetLength(Text, Length(Bytes));
  if Length(Bytes) > 0 then
    Move(Bytes[0], Text[1], Length(Bytes));
  Errors := TStringList.Create;
  Strings := nil;
  try
    if LumpName = 'UMAPINFO' then
      N := ParseUMapInfo(Text, Entries, Errors)
    else
    begin
      { The LANGUAGE and BEX strings for "lookup" / "$NAME". }
      Strings := TDoomStrings.Create(AWad);
      N := ParseZMapInfo(Text, Entries, Errors, AWad, Strings);
    end;
    for I := 0 to Errors.Count - 1 do
      WritelnWarning('MapInfo', Errors[I]);
  finally
    FreeAndNil(Strings);
    FreeAndNil(Errors);
  end;
  WritelnLog('MapInfo', '%s: %d maps', [LumpName, N]);
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

function MapInfoEntries: TMapInfoList;
begin
  Result := Entries;
end;

function MapInfoThingType(const ClassName: String): Integer;
const
  Names: array [0..19] of String = ('ZombieMan', 'ShotgunGuy', 'ChaingunGuy', 'DoomImp', 'Demon',
    'Spectre', 'LostSoul', 'Cacodemon', 'HellKnight', 'BaronOfHell', 'Arachnotron', 'PainElemental',
    'Revenant', 'Fatso', 'Archvile', 'SpiderMastermind', 'Cyberdemon', 'WolfensteinSS',
    'CommanderKeen', 'BossBrain');
  Types: array [0..19] of Integer = (3004, 9, 65, 3001, 3002, 58, 3006, 3005, 69, 3003, 68, 71,
    66, 67, 64, 7, 16, 84, 72, 88);
var
  I: Integer;
begin
  for I := 0 to High(Names) do
    if SameText(Names[I], ClassName) then
      Exit(Types[I]);
  Result := StrToIntDef(ClassName, 0);
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
