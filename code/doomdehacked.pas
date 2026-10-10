{ DeHackEd patches: DEHACKED lumps of the loaded WADs (in order, so a
  PWAD's override the IWAD's) and then the -deh / -bex files.

  - Strings (Boom's BEX "[STRINGS]" section): Freedoom ships its own finale
    texts, finale background flats and cast-call names this way (E1TEXT,
    C1TEXT, BGFLATE1, CC_ZOMBIE...); TDoomStrings.
  - "[PARS]": par times for the intermission (Freedoom has its own).
  - "Thing N": hit points, speed, width, height, mass and pain chance of the
    things this port knows (N is info.c's mobjtype + 1), their frames
    (initial, moving, injury, close / far attack, death, exploding,
    respawn), sounds (alert, attack, pain, death, action) and bits (solid,
    float, spawn on the ceiling, shadow are kept).
  - "Frame N": sprite number, sprite subnumber (frame, bit 15 full bright),
    duration and next frame of vanilla's state table (DoomStates);
    "Pointer N (Frame M)" with "Codep Frame = K" gives frame M the code
    pointer of vanilla's frame K, and BEX "[CODEPTR]" "FRAME M = A_Name"
    names it. After the patches the things' frame sequences, sounds and
    attacks are derived again (DoomThings.ApplyStateTable), so changed
    animations play and a monster given another's attack code pointer
    attacks that way.
  - "Ammo N": max ammo and the clip size; "Misc": initial health and
    bullets, health / armor limits, armor classes, soul- and megasphere
    health, IDFA / IDKFA armor, BFG cells per shot.
  - "Weapon N": ammo type and the select, deselect, ready, attack and
    flash frames of the player's weapons; the weapons animate and fire
    from the state table (a shot happens on the frame carrying A_FirePistol
    and the like), so changed weapon frames and code pointers take effect.
    Projectile rows ("Thing N" for MT_TROOPSHOT...) give the projectiles'
    speed, size, "Missile damage", sounds and frames.
  "Sprite" and "Sound" renumbering, cheats and the old "Text"
  replacements are counted and logged as ignored. }
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

uses SysUtils, Math, Generics.Collections, CastleLog, DoomThings, DoomStates, DoomMapInfo;

var
  DehFileNames, DehFileTexts: TStringList;
  DehPars: {$ifdef FPC}specialize{$endif} TDictionary<String, Integer>;

const
  VanillaMaxAmmo: array [0..3] of Integer = (200, 50, 300, 50);
  VanillaClipAmmo: array [0..3] of Integer = (10, 4, 20, 1);
  { DeHackEd's / BEX's mnemonic bits ("Bits = SOLID+SHOOTABLE"). }
  BitNames: array [0..27] of String = (
    'SPECIAL', 'SOLID', 'SHOOTABLE', 'NOSECTOR', 'NOBLOCKMAP', 'AMBUSH', 'JUSTHIT',
    'JUSTATTACKED', 'SPAWNCEILING', 'NOGRAVITY', 'DROPOFF', 'PICKUP', 'NOCLIP',
    'SLIDE', 'FLOAT', 'TELEPORT', 'MISSILE', 'DROPPED', 'SHADOW', 'NOBLOOD',
    'CORPSE', 'INFLOAT', 'COUNTKILL', 'COUNTITEM', 'SKULLFLY', 'NOTDMATCH',
    'TRANSLATION', 'TRANSLATION2');

{ A "Bits" value: a number, or names joined by + | , or blanks. }
function BitsValue(const S: String): Integer;
var
  Words: TStringArray;
  W: String;
  I: Integer;
begin
  Result := StrToIntDef(Trim(S), -1);
  if Result >= 0 then Exit;
  Result := 0;
  Words := S.Split(['+', '|', ',', ' ', #9], TStringSplitOptions.ExcludeEmpty);
  for W in Words do
    for I := 0 to High(BitNames) do
      if SameText(W, BitNames[I]) or SameText(W, 'MF_' + BitNames[I]) then
        Result := Result or (1 shl I);
end;

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
  ResetStates;
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
  I, Eq, N, Value, Changed, Ignored, Par, PointerFrame, Frame: Integer;
  Line, Section, Key, ValueStr: String;
  Words: TStringArray;
  Info: PThingInfo;
  Action: TStateAction;

  { A state number of the table, else -1. }
  function StateNum(const V: Integer): Integer;
  begin
    if (V >= 0) and (V < Length(States)) then Result := V else Result := -1;
  end;

  function SoundNum(const V: Integer): Integer;
  begin
    if (V >= 0) and (V < Length(Sounds)) then Result := V else Result := -1;
  end;

  { "Thing N": the stats go to the thing table, the frames, sounds and
    bits to the mobjinfo row (ApplyStateTable derives from it after the
    patches). Rows without a thing of this port (the player, projectiles)
    still take their frames and sounds. }
  procedure ThingField;
  var
    M: Integer;
  begin
    M := -1;
    if (N >= 1) and (N <= Length(Mobjs)) then M := N - 1;
    if SameText(Key, 'Initial frame') then begin if M >= 0 then Mobjs[M].Spawn := StateNum(Value); end
    else if SameText(Key, 'First moving frame') then begin if M >= 0 then Mobjs[M].See := StateNum(Value); end
    else if SameText(Key, 'Injury frame') then begin if M >= 0 then Mobjs[M].Pain := StateNum(Value); end
    else if SameText(Key, 'Close attack frame') then begin if M >= 0 then Mobjs[M].Melee := StateNum(Value); end
    else if SameText(Key, 'Far attack frame') then begin if M >= 0 then Mobjs[M].Missile := StateNum(Value); end
    else if SameText(Key, 'Death frame') then begin if M >= 0 then Mobjs[M].Death := StateNum(Value); end
    else if SameText(Key, 'Exploding frame') then begin if M >= 0 then Mobjs[M].XDeath := StateNum(Value); end
    else if SameText(Key, 'Respawn frame') then begin if M >= 0 then Mobjs[M].RaiseState := StateNum(Value); end
    else if SameText(Key, 'Alert sound') then begin if M >= 0 then Mobjs[M].SeeSound := SoundNum(Value); end
    else if SameText(Key, 'Attack sound') then begin if M >= 0 then Mobjs[M].AttackSound := SoundNum(Value); end
    else if SameText(Key, 'Pain sound') then begin if M >= 0 then Mobjs[M].PainSound := SoundNum(Value); end
    else if SameText(Key, 'Death sound') then begin if M >= 0 then Mobjs[M].DeathSound := SoundNum(Value); end
    else if SameText(Key, 'Action sound') then begin if M >= 0 then Mobjs[M].ActiveSound := SoundNum(Value); end
    else if SameText(Key, 'Bits') then begin if M >= 0 then Mobjs[M].Flags := BitsValue(ValueStr); end
    else if SameText(Key, 'Missile damage') then begin if M >= 0 then Mobjs[M].Damage := Value; end
    else if (Info = nil) and (M >= 0) and SameText(Key, 'Speed') then
      { Projectiles (no thing of this port): fixed point when large. }
      begin if Value >= 65536 then Mobjs[M].Speed := Value div 65536 else Mobjs[M].Speed := Value; end
    else if (Info = nil) and (M >= 0) and SameText(Key, 'Width') then Mobjs[M].Radius := Value div 65536
    else if (Info = nil) and (M >= 0) and SameText(Key, 'Height') then Mobjs[M].Height := Value div 65536
    else if Info = nil then
    begin
      Inc(Ignored);
      Exit;
    end
    else if SameText(Key, 'Hit points') then Info^.Health := Value
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
    if M < 0 then
      Inc(Ignored)
    else
      Inc(Changed);
  end;

  { "Frame N": a row of the state table. }
  procedure FrameField;
  begin
    if (N < 0) or (N >= Length(States)) then
    begin
      Inc(Ignored);
      Exit;
    end;
    if SameText(Key, 'Sprite number') then
    begin
      if (Value >= 0) and (Value < Length(Sprites)) then States[N].Sprite := Value;
    end
    else if SameText(Key, 'Sprite subnumber') then States[N].Frame := Value
    else if SameText(Key, 'Duration') then States[N].Tics := Value
    else if SameText(Key, 'Next frame') then States[N].Next := Max(0, StateNum(Value))
    else if SameText(Key, 'Unknown 1') or SameText(Key, 'Unknown 2') then
    else
    begin
      Inc(Ignored);
      Exit;
    end;
    Inc(Changed);
  end;

  { "Weapon N" (0 fist .. 8 super shotgun): ammo type and entry frames. }
  procedure WeaponField;
  begin
    if (N < 0) or (N > High(Weapons)) then
    begin
      Inc(Ignored);
      Exit;
    end;
    if SameText(Key, 'Ammo type') then Weapons[N].Ammo := Value
    else if SameText(Key, 'Deselect frame') then Weapons[N].Down := Max(0, StateNum(Value))
    else if SameText(Key, 'Select frame') then Weapons[N].Up := Max(0, StateNum(Value))
    else if SameText(Key, 'Bobbing frame') then Weapons[N].Ready := Max(0, StateNum(Value))
    else if SameText(Key, 'Shooting frame') then Weapons[N].Attack := Max(0, StateNum(Value))
    else if SameText(Key, 'Firing frame') then Weapons[N].Flash := Max(0, StateNum(Value))
    else
    begin
      Inc(Ignored);
      Exit;
    end;
    Inc(Changed);
  end;

  { "Pointer N (Frame M)": "Codep Frame = K" copies vanilla frame K's
    code pointer to frame M. }
  procedure PointerField;
  begin
    if SameText(Key, 'Codep Frame') and (PointerFrame >= 0) and (PointerFrame < Length(States)) and
       (Value >= 0) and (Value < VanillaStateCount) then
    begin
      States[PointerFrame].Action := VanillaStates[Value].Action;
      Inc(Changed);
    end else
      Inc(Ignored);
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
  PointerFrame := -1;
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
      { [STRINGS] is TDoomStrings' (it reads the same patches); [CODEPTR]
        names code pointers ("FRAME 452 = A_SargAttack"); other BEX
        sections ([HELPER], [SPRITES]...) are not supported. }
      if (Section <> '') and (Section[1] = '[') then
      begin
        if Pos('=', Line) > 0 then
        begin
          if Section = '[CODEPTR]' then
          begin
            Eq := Pos('=', Line);
            Words := Trim(Copy(Line, 1, Eq - 1)).Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
            Frame := -1;
            if (Length(Words) = 2) and SameText(Words[0], 'FRAME') then
              Frame := StrToIntDef(Words[1], -1);
            if (Frame >= 0) and (Frame < Length(States)) and
               ActionByName(Trim(Copy(Line, Eq + 1, MaxInt)), Action) then
            begin
              States[Frame].Action := Action;
              Inc(Changed);
            end else
              Inc(Ignored);
          end
          else if Section <> '[STRINGS]' then Inc(Ignored);
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
        if (Section = 'thing') and (N >= 1) and (N <= Length(Mobjs)) and (Mobjs[N - 1].DoomedNum > 0) then
          Info := FindThingInfo(Mobjs[N - 1].DoomedNum);
        { "Pointer 123 (Frame 456)": the frame in parentheses is the one changed. }
        PointerFrame := -1;
        if (Section = 'pointer') and (Length(Words) >= 4) and SameText(Words[2], '(Frame') then
          PointerFrame := StrToIntDef(StringReplace(Words[3], ')', '', [rfReplaceAll]), -1);
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
      else if Section = 'frame' then
        FrameField
      else if Section = 'pointer' then
        PointerField
      else if Section = 'weapon' then
        WeaponField
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
  WritelnLog('DeHackEd', '%s: %d values applied, %d not supported (sprites, sounds, cheats, text...)',
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
  { The things' sequences, sounds and attacks from the patched states. }
  ApplyStateTable;
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
  Info: TMapInfoEntry;
begin
  { UMAPINFO: "label: levelname" (the map lump's name without a label,
    only the level name with "label = clear"). }
  Info := MapInfoFor(MapName);
  if (Info <> nil) and (Info.LevelName <> '') then
  begin
    if Info.LabelClear then
      Result := Info.LevelName
    else if Info.LabelSet then
      Result := Info.LabelText + ': ' + Info.LevelName
    else
      Result := UpperCase(MapName) + ': ' + Info.LevelName;
    Exit;
  end;
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
