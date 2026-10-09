{ DeHackEd patches: DEHACKED lumps of the loaded WADs (in order, so a
  PWAD's override the IWAD's) and then the -deh / -bex files.

  - Strings (Boom's BEX "[STRINGS]" section): Freedoom ships its own finale
    texts, finale background flats and cast-call names this way (E1TEXT,
    C1TEXT, BGFLATE1, CC_ZOMBIE...); TDoomStrings.
  - "[PARS]": par times for the intermission (Freedoom has its own).
  - "Thing N": hit points, speed, width, height, mass and pain chance of the
    things this port knows (N is info.c's mobjtype + 1).
  - "Ammo N": max ammo and the clip size; "Misc": initial health and
    bullets, health / armor limits, armor classes, soul- and megasphere
    health, IDFA / IDKFA armor, BFG cells per shot.
  Frames, code pointers, sprites, sounds, weapons' frames, cheats and the
  old "Text" replacements need Doom's state tables, which this port does
  not have; they are counted and logged as ignored. }
unit DoomDehacked;

interface

uses Classes,
  DoomWad;

type
  { DeHackEd's "Misc" section, with vanilla's values. }
  TDehMisc = record
    InitialHealth, InitialBullets, MaxHealth, MaxArmor: Integer;
    GreenArmorClass, BlueArmorClass: Integer;
    MaxSoulsphere, SoulsphereHealth, MegasphereHealth: Integer;
    IdfaArmor, IdfaArmorClass, IdkfaArmor, IdkfaArmorClass: Integer;
    BfgCellsPerShot: Integer;
  end;

var
  DehMisc: TDehMisc;
  { DeHackEd "Ammo 0..3" (clip, shell, cell, rocket; DoomWorld's TAmmoType
    order): "Max ammo" and "Per ammo" (a clip; boxes give 5 clips, weapons
    2, backpacks 1, like P_GiveAmmo). }
  DehMaxAmmo, DehClipAmmo: array [0..3] of Integer;

{ Remember a -deh / -bex patch file (read now; applied by ApplyDehacked). }
procedure AddDehackedFile(const FileName: String);
{ Reset things, misc, ammo and par times to vanilla and apply every patch:
  the WAD's DEHACKED lumps, then the -deh files. }
procedure ApplyDehacked(const AWad: TDoomWad);
{ A par time from a [PARS] section, in seconds. }
function DehackedParTime(const MapName: String; out Seconds: Integer): Boolean;

type
  TDoomStrings = class
  strict private
    FValues: TStringList;
    procedure ParseLump(const Text: String);
  public
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;
    { The BEX string for Key (case-insensitive), or Default when absent. }
    function Get(const Key: String; const Default: String = ''): String;
    function Has(const Key: String): Boolean;
    function Count: Integer;
    { Doom's level title (HUSTR_E1M1 / HUSTR_1), e.g. "E1M1: Outer Prison";
      the map name itself when the WAD has none. }
    function LevelName(const MapName: String; const IsDoom2: Boolean): String;
  end;

implementation

uses SysUtils, Generics.Collections, CastleLog, DoomThings;

var
  DehFileNames, DehFileTexts: TStringList;
  DehPars: {$ifdef FPC}specialize{$endif} TDictionary<String, Integer>;

const
  { info.c's mobjinfo order: DeHackEd's "Thing N" is MobjDoomedNum[N]
    (0 = no map number: player, projectiles, effects). }
  MobjDoomedNum: array [1..137] of Integer = (
    0, 3004, 9, 64, 0, 66, 0, 0, 67, 0, 65, 3001, 3002, 58, 3005, 3003, 0, 69,
    3006, 7, 68, 16, 71, 84, 72, 88, 89, 87, 0, 0, 2035, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 14, 0, 2018, 2019, 2014, 2015, 5, 13, 6, 39, 38, 40, 2011, 2012,
    2013, 2022, 2023, 2024, 2025, 2026, 2045, 83, 2007, 2048, 2010, 2046, 2047,
    17, 2008, 2049, 8, 2006, 2002, 2005, 2003, 2004, 2001, 82,
    85, 86, 2028, 30, 31, 32, 33, 37, 36, 41, 42, 43, 44, 45, 46, 55, 56, 57,
    47, 48, 34, 35, 49, 50, 51, 52, 53, 63, 59, 61, 60, 62, 22, 15, 18, 21, 23,
    20, 19, 10, 12, 28, 24, 27, 29, 25, 26, 54, 70, 73, 74, 75, 76, 77, 78, 79,
    80, 81);
  VanillaMaxAmmo: array [0..3] of Integer = (200, 50, 300, 50);
  VanillaClipAmmo: array [0..3] of Integer = (10, 4, 20, 1);

procedure ResetDehacked;
begin
  DehMisc.InitialHealth := 100;
  DehMisc.InitialBullets := 50;
  DehMisc.MaxHealth := 200;
  DehMisc.MaxArmor := 200;
  DehMisc.GreenArmorClass := 1;
  DehMisc.BlueArmorClass := 2;
  DehMisc.MaxSoulsphere := 200;
  DehMisc.SoulsphereHealth := 100;
  DehMisc.MegasphereHealth := 200;
  DehMisc.IdfaArmor := 200;
  DehMisc.IdfaArmorClass := 2;
  DehMisc.IdkfaArmor := 200;
  DehMisc.IdkfaArmorClass := 2;
  DehMisc.BfgCellsPerShot := 40;
  DehMaxAmmo := VanillaMaxAmmo;
  DehClipAmmo := VanillaClipAmmo;
  DehPars.Clear;
  ResetThingInfos;
end;

procedure AddDehackedFile(const FileName: String);
var
  Stream: TFileStream;
  Text: String;
begin
  if not FileExists(FileName) then
  begin
    WritelnWarning('DeHackEd', 'Patch file not found: %s', [FileName]);
    Exit;
  end;
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Text, Stream.Size);
    if Stream.Size > 0 then
      Stream.ReadBuffer(Text[1], Stream.Size);
  finally
    FreeAndNil(Stream);
  end;
  DehFileNames.Add(ExtractFileName(FileName));
  DehFileTexts.Add(Text);
end;

{ One patch. Sections start with "Name N" lines (Thing 12 (Imp)) or BEX
  "[NAME]" lines; "Key = value" lines set fields; "#" starts a comment. }
procedure ApplyPatch(const Text, SourceName: String);
var
  Lines: TStringList;
  I, Eq, N, Value, Changed, Ignored, Par: Integer;
  Line, Section, Key, ValueStr: String;
  Words: TStringArray;
  Info: PThingInfo;

  procedure ThingField;
  begin
    if Info = nil then
    begin
      Inc(Ignored);
      Exit;
    end;
    if SameText(Key, 'Hit points') then Info^.Health := Value
    else if SameText(Key, 'Speed') then Info^.Speed := Value
    else if SameText(Key, 'Width') then Info^.Radius := Value div 65536
    else if SameText(Key, 'Height') then Info^.Height := Value div 65536
    else if SameText(Key, 'Mass') then Info^.Mass := Value
    else if SameText(Key, 'Pain chance') then Info^.PainChance := Value
    else
    begin
      Inc(Ignored);
      Exit;
    end;
    Inc(Changed);
  end;

  procedure MiscField;
  begin
    if SameText(Key, 'Initial Health') then DehMisc.InitialHealth := Value
    else if SameText(Key, 'Initial Bullets') then DehMisc.InitialBullets := Value
    else if SameText(Key, 'Max Health') then DehMisc.MaxHealth := Value
    else if SameText(Key, 'Max Armor') then DehMisc.MaxArmor := Value
    else if SameText(Key, 'Green Armor Class') then DehMisc.GreenArmorClass := Value
    else if SameText(Key, 'Blue Armor Class') then DehMisc.BlueArmorClass := Value
    else if SameText(Key, 'Max Soulsphere') then DehMisc.MaxSoulsphere := Value
    else if SameText(Key, 'Soulsphere Health') then DehMisc.SoulsphereHealth := Value
    else if SameText(Key, 'Megasphere Health') then DehMisc.MegasphereHealth := Value
    else if SameText(Key, 'IDFA Armor') then DehMisc.IdfaArmor := Value
    else if SameText(Key, 'IDFA Armor Class') then DehMisc.IdfaArmorClass := Value
    else if SameText(Key, 'IDKFA Armor') then DehMisc.IdkfaArmor := Value
    else if SameText(Key, 'IDKFA Armor Class') then DehMisc.IdkfaArmorClass := Value
    else if SameText(Key, 'BFG Cells/Shot') then DehMisc.BfgCellsPerShot := Value
    else
    begin
      Inc(Ignored);
      Exit;
    end;
    Inc(Changed);
  end;

begin
  Changed := 0;
  Ignored := 0;
  Section := '';
  Info := nil;
  N := 0;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    I := 0;
    while I < Lines.Count do
    begin
      Line := Trim(Lines[I]);
      Inc(I);
      if Pos('#', Line) > 0 then
        Line := Trim(Copy(Line, 1, Pos('#', Line) - 1));
      if Line = '' then Continue;

      if Line[1] = '[' then
      begin
        Section := UpperCase(Line);
        Continue;
      end;

      if Section = '[PARS]' then
      begin
        { "par E M seconds" or "par MAP seconds" }
        Words := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        if (Length(Words) = 4) and SameText(Words[0], 'par') then
        begin
          DehPars.AddOrSetValue(Format('E%dM%d', [StrToIntDef(Words[1], 0), StrToIntDef(Words[2], 0)]),
            StrToIntDef(Words[3], 0));
          Inc(Changed);
        end else
        if (Length(Words) = 3) and SameText(Words[0], 'par') then
        begin
          DehPars.AddOrSetValue(Format('MAP%.2d', [StrToIntDef(Words[1], 0)]), StrToIntDef(Words[2], 0));
          Inc(Changed);
        end;
        Continue;
      end;
      { [STRINGS] is TDoomStrings' (it reads the same patches); other BEX
        sections ([CODEPTR], [HELPER], [SPRITES]...) are not supported. }
      if (Section <> '') and (Section[1] = '[') then
      begin
        if Pos('=', Line) > 0 then
        begin
          if Section <> '[STRINGS]' then Inc(Ignored);
          { A value continued with a trailing backslash. }
          while (Line <> '') and (Line[Length(Line)] = '\') and (I < Lines.Count) do
          begin
            Line := Trim(Lines[I]);
            Inc(I);
          end;
          Continue;
        end;
        { Only a DeHackEd section header ends a BEX section. }
        Words := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        if (Length(Words) < 2) or (StrToIntDef(Words[1], -1) < 0) then Continue;
      end;

      Eq := Pos('=', Line);
      if Eq = 0 then
      begin
        { A section header: "Thing 12 (Imp)", "Misc 0", "Text 6 6"... }
        Words := Line.Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
        Section := LowerCase(Words[0]);
        N := 0;
        if Length(Words) > 1 then
          N := StrToIntDef(Words[1], 0);
        Info := nil;
        if (Section = 'thing') and (N >= Low(MobjDoomedNum)) and (N <= High(MobjDoomedNum)) and
           (MobjDoomedNum[N] <> 0) then
          Info := FindThingInfo(MobjDoomedNum[N]);
        if (Section = 'text') and (Length(Words) >= 3) then
        begin
          { Old-style replacement: the next Words[1] + Words[2] characters
            (the original text, then the new one), maybe over several lines. }
          Par := StrToIntDef(Words[1], 0) + StrToIntDef(Words[2], 0);
          while (Par > 0) and (I < Lines.Count) do
          begin
            Par := Par - Length(Lines[I]) - 1;
            Inc(I);
          end;
          Inc(Ignored);
        end;
        Continue;
      end;

      Key := Trim(Copy(Line, 1, Eq - 1));
      ValueStr := Trim(Copy(Line, Eq + 1, MaxInt));
      Value := StrToIntDef(ValueStr, 0);
      if Section = 'thing' then
        ThingField
      else if Section = 'misc' then
        MiscField
      else if Section = 'ammo' then
      begin
        if (N >= 0) and (N <= 3) and SameText(Key, 'Max ammo') then
        begin
          DehMaxAmmo[N] := Value;
          Inc(Changed);
        end else
        if (N >= 0) and (N <= 3) and SameText(Key, 'Per ammo') then
        begin
          DehClipAmmo[N] := Value;
          Inc(Changed);
        end else
          Inc(Ignored);
      end else
      if (Section = 'doom') or (Section = 'patch') then
        { "Doom version = 19", "Patch format = 6" }
      else
        Inc(Ignored);
    end;
  finally
    FreeAndNil(Lines);
  end;
  WritelnLog('DeHackEd', '%s: %d values applied, %d not supported (frames, code pointers...)',
    [SourceName, Changed, Ignored]);
end;

function LumpText(const AWad: TDoomWad; const Lump: Integer): String;
var
  Bytes: TBytes;
begin
  Bytes := AWad.LumpBytes(Lump);
  SetLength(Result, Length(Bytes));
  if Length(Bytes) > 0 then
    Move(Bytes[0], Result[1], Length(Bytes));
end;

procedure ApplyDehacked(const AWad: TDoomWad);
var
  I: Integer;
begin
  ResetDehacked;
  if AWad <> nil then
    for I := 0 to AWad.LumpCount - 1 do
      if AWad.LumpName(I) = 'DEHACKED' then
        ApplyPatch(LumpText(AWad, I), 'DEHACKED lump');
  for I := 0 to DehFileTexts.Count - 1 do
    ApplyPatch(DehFileTexts[I], DehFileNames[I]);
end;

function DehackedParTime(const MapName: String; out Seconds: Integer): Boolean;
begin
  Result := DehPars.TryGetValue(UpperCase(MapName), Seconds);
end;

constructor TDoomStrings.Create(const AWad: TDoomWad);
var
  I: Integer;
begin
  inherited Create;
  FValues := TStringList.Create;
  FValues.CaseSensitive := false;
  if AWad <> nil then
    for I := 0 to AWad.LumpCount - 1 do
      if AWad.LumpName(I) = 'DEHACKED' then
        ParseLump(LumpText(AWad, I));
  for I := 0 to DehFileTexts.Count - 1 do
    ParseLump(DehFileTexts[I]);
end;

destructor TDoomStrings.Destroy;
begin
  FreeAndNil(FValues);
  inherited;
end;

{ BEX: "KEY = value", a trailing backslash continues the value on the next
  line (its leading blanks dropped), "\n" is a newline. Lines starting with
  '#' are comments; a line starting with '[' begins another section. }
procedure TDoomStrings.ParseLump(const Text: String);
var
  Lines: TStringList;
  I, Eq: Integer;
  Line, Key, Value: String;
  InStrings: Boolean;

  function Unescape(const S: String): String;
  begin
    Result := StringReplace(S, '\n', #10, [rfReplaceAll]);
  end;

begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text; { handles CR LF and LF }
    InStrings := false;
    I := 0;
    while I < Lines.Count do
    begin
      Line := Trim(Lines[I]);
      Inc(I);
      if (Line = '') or (Line[1] = '#') then Continue;
      if Line[1] = '[' then
      begin
        InStrings := SameText(Line, '[STRINGS]');
        Continue;
      end;
      if not InStrings then Continue;
      Eq := Pos('=', Line);
      if Eq = 0 then Continue;
      Key := Trim(Copy(Line, 1, Eq - 1));
      Value := Trim(Copy(Line, Eq + 1, MaxInt));
      while (Value <> '') and (Value[Length(Value)] = '\') and (I < Lines.Count) do
      begin
        SetLength(Value, Length(Value) - 1);
        Value := Value + Trim(Lines[I]);
        Inc(I);
      end;
      FValues.Values[Key] := Unescape(Value);
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

function TDoomStrings.Get(const Key: String; const Default: String): String;
var
  Idx: Integer;
begin
  Idx := FValues.IndexOfName(Key);
  if Idx < 0 then
    Result := Default
  else
    Result := FValues.ValueFromIndex[Idx];
end;

function TDoomStrings.Has(const Key: String): Boolean;
begin
  Result := FValues.IndexOfName(Key) >= 0;
end;

function TDoomStrings.Count: Integer;
begin
  Result := FValues.Count;
end;

function TDoomStrings.LevelName(const MapName: String; const IsDoom2: Boolean): String;
var
  N: Integer;
begin
  if IsDoom2 and (Copy(MapName, 1, 3) = 'MAP') then
  begin
    N := StrToIntDef(Copy(MapName, 4, 2), 0);
    Result := Get('HUSTR_' + IntToStr(N), MapName);
  end else
    Result := Get('HUSTR_' + MapName, MapName);
end;

initialization
  DehFileNames := TStringList.Create;
  DehFileTexts := TStringList.Create;
  DehPars := {$ifdef FPC}specialize{$endif} TDictionary<String, Integer>.Create;
  ResetDehacked;
finalization
  FreeAndNil(DehFileNames);
  FreeAndNil(DehFileTexts);
  FreeAndNil(DehPars);
end.
