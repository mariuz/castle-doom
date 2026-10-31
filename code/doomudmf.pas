{ UDMF, the Universal Doom Map Format (the TEXTMAP lump of maps made for
  UZDoom / GZDoom, Eternity, DSDA-Doom...): a text of "key = value;"
  assignments, global ones (namespace = "zdoom";) and blocks (vertex,
  linedef, sidedef, sector, thing, each a name and its assignments in
  braces). TUdmfMap reads it without exceptions (the web build cannot
  catch one): Error says what went wrong.

  Maps in the "hexen" / "zdoom" namespaces use Hexen's line specials (an
  action number, five arguments and activation flags such as playercross,
  playeruse, repeatspecial) and ZDoom's sector types. The world runs
  Doom's and Boom's specials, so TranslateHexenLine turns an action into
  the vanilla or Boom number, or the Boom generalized type, that does the
  same (a door with that speed and delay, a lift, a floor to the lowest
  neighbour...), or into one of the UdmfSpecial* types for what only
  Hexen's arguments can say (a floor to a height, a light level);
  TranslateZDoomSectorSpecial maps sector types the same way. DoomMap uses
  both while loading. }
unit DoomUdmf;

interface

uses SysUtils, Classes;

type
  TUdmfBlock = record
    { Lower case: vertex, linedef, sidedef, sector, thing (others kept). }
    Kind: String;
    Keys, Values: array of String;
    Count: Integer;
  end;
  PUdmfBlock = ^TUdmfBlock;

  TUdmfMap = class
  strict private
    FError: String;
    FNamespace: String;
    procedure Parse(const Text: String);
  public
    Blocks: array of TUdmfBlock;
    BlockCount: Integer;
    constructor Create(const Text: String);
    { '' when the whole text was read. }
    property Error: String read FError;
    { Lower case, '' when the text has none. }
    property Namespace: String read FNamespace;
    { Hexen's line specials and ZDoom's sector types (hexen, zdoom,
      eternity, vavoom); the others (doom, heretic, strife,
      zdoomtranslated, dsda) use Doom's numbers. }
    function HexenSpecials: Boolean;
  end;

{ A block's value by key (lower case): the default when missing or
  unreadable. Strings come unquoted, numbers as written. }
function UdmfStr(const B: TUdmfBlock; const Key: String; const Default: String = ''): String;
function UdmfInt(const B: TUdmfBlock; const Key: String; const Default: Integer = 0): Integer;
function UdmfFloat(const B: TUdmfBlock; const Key: String; const Default: Double = 0): Double;
function UdmfBool(const B: TUdmfBlock; const Key: String; const Default: Boolean = false): Boolean;
function UdmfHas(const B: TUdmfBlock; const Key: String): Boolean;

const
  { The world's own line types for Hexen actions that need their
    arguments (TDoomLinedef.Args, activated as TDoomLinedef.Trigger says);
    far above Doom's and Boom's numbers. }
  UdmfSpecialBase = 100000;
  { Args: tag, speed (map units a tic x 8), signed height. }
  UdmfFloorByValue = UdmfSpecialBase + 1;
  UdmfFloorToValue = UdmfSpecialBase + 2;
  UdmfCeilingByValue = UdmfSpecialBase + 3;
  UdmfCeilingToValue = UdmfSpecialBase + 4;
  { Args: tag, light level / signed change. }
  UdmfLightToValue = UdmfSpecialBase + 5;
  UdmfLightByValue = UdmfSpecialBase + 6;
  { Static: the line's front side scrolls by Args[0], Args[1] / 64 texels
    a tic (x: left, y: up, like Boom's 255). }
  UdmfScrollWall = UdmfSpecialBase + 50;
  { ACS scripts (DoomAcs). Args as Hexen's: script, map (0 = this one),
    the script's arguments; ACS_ExecuteWithResult: script and four
    arguments; the locked ones: the lock in Args[4]. }
  UdmfAcsExecute = UdmfSpecialBase + 20;
  UdmfAcsExecuteAlways = UdmfSpecialBase + 21;
  UdmfAcsExecuteWithResult = UdmfSpecialBase + 22;
  UdmfAcsLockedExecute = UdmfSpecialBase + 23;
  UdmfAcsTerminate = UdmfSpecialBase + 24;
  UdmfAcsSuspend = UdmfSpecialBase + 25;

  { UDMF line activation flags (TUdmfLine.Activation). }
  UaPlayerCross = 1;
  UaPlayerUse = 2;
  UaMonsterCross = 4;
  UaMonsterUse = 8;
  UaImpact = 16;
  UaPlayerPush = 32;
  UaMonsterPush = 64;
  UaMissileCross = 128;
  UaRepeat = 256;

type
  { What TranslateHexenLine makes of a line. }
  THexenLine = record
    Special: Integer;
    { The line's sector tag (Doom's meaning), Args[0] for most actions. }
    Tag: Integer;
    { Teleports by thing id (TID) with no sector tag: the destination's
      TID; DoomMap then tags the sector it stands in. }
    TeleportTid: Integer;
    { Teleport_Line: the destination line's id. }
    LineTeleportId: Integer;
    { TranslucentLine: the line id (0 = this line) and its opacity. }
    TranslucentId: Integer;
    Alpha: Single;
    { For the UdmfSpecial* types: the arguments the world reads, and how
      the line is triggered (a TGenTrigger: 0 W1, 1 WR, 2 S1, 3 SR, 4 G1,
      5 GR, 6 D1, 7 DR; + 8 when monsters may). }
    Args: array [0..4] of Integer;
    Trigger: Integer;
    { Not supported (Special 0): what it was, for the log. }
    Unsupported: String;
  end;

{ Hexen's action Special with Args, triggered as Activation (Ua* flags),
  as a Doom / Boom / generalized / UdmfSpecial* line. }
function TranslateHexenLine(const Special: Integer; const Args: array of Integer;
  const Activation: Integer): THexenLine;
{ ZDoom's sector type (low byte: 65..81 are Doom's 1..17; 1024 secret,
  256..768 damage, 2048 friction, 4096 pushers) as Doom's with Boom's
  bits. }
function TranslateZDoomSectorSpecial(const Special: Integer): Integer;
{ Hexen's action name (or "action N"), for the log. }
function HexenActionName(const Special: Integer): String;
{ A UdmfSpecial* type's name, for the log. }
function UdmfSpecialName(const Special: Integer): String;
{ One of the UdmfAcs* types. }
function UdmfAcsSpecial(const Special: Integer): Boolean;

implementation

uses Math, DoomGeneralized;

{ TUdmfMap ------------------------------------------------------------------ }

constructor TUdmfMap.Create(const Text: String);
begin
  inherited Create;
  Parse(Text);
end;

function TUdmfMap.HexenSpecials: Boolean;
begin
  Result := (FNamespace = 'hexen') or (FNamespace = 'zdoom') or (FNamespace = 'eternity') or
    (FNamespace = 'vavoom');
end;

procedure TUdmfMap.Parse(const Text: String);
var
  P, N, Line: Integer;
  Tok, TokKind: String;

  procedure Fail(const Msg: String);
  begin
    if FError = '' then
      FError := Format('TEXTMAP line %d: %s', [Line, Msg]);
  end;

  { The next token: TokKind 'id' (identifiers, numbers, true / false),
    'str' (Tok unquoted), a single character (=, ;, the braces) or '' at the end. }
  procedure Next;
  var
    S: Integer;
    C: Char;
  begin
    Tok := '';
    TokKind := '';
    while P <= N do
    begin
      C := Text[P];
      if C = #10 then
      begin
        Inc(Line);
        Inc(P);
      end else
      if C <= ' ' then
        Inc(P)
      else
      if (C = '/') and (P < N) and (Text[P + 1] = '/') then
      begin
        while (P <= N) and (Text[P] <> #10) do Inc(P);
      end else
      if (C = '/') and (P < N) and (Text[P + 1] = '*') then
      begin
        Inc(P, 2);
        while (P < N) and not ((Text[P] = '*') and (Text[P + 1] = '/')) do
        begin
          if Text[P] = #10 then Inc(Line);
          Inc(P);
        end;
        Inc(P, 2);
      end else
        Break;
    end;
    if P > N then Exit;
    C := Text[P];
    if C = '"' then
    begin
      Inc(P);
      S := P;
      while (P <= N) and (Text[P] <> '"') do
      begin
        if (Text[P] = '\') and (P < N) then
        begin
          Tok := Tok + Copy(Text, S, P - S) + Text[P + 1];
          Inc(P, 2);
          S := P;
          Continue;
        end;
        if Text[P] = #10 then Inc(Line);
        Inc(P);
      end;
      Tok := Tok + Copy(Text, S, P - S);
      Inc(P);
      TokKind := 'str';
    end else
    if C in ['=', ';', '{', '}'] then
    begin
      Tok := C;
      TokKind := C;
      Inc(P);
    end else
    begin
      S := P;
      while (P <= N) and not (Text[P] in [#0..' ', '=', ';', '{', '}', '"', '/']) do Inc(P);
      if P = S then
      begin
        { A stray '/' or another character the format does not have. }
        Fail(Format('unexpected "%s"', [C]));
        P := N + 1;
        Exit;
      end;
      Tok := Copy(Text, S, P - S);
      TokKind := 'id';
    end;
  end;

  procedure AddBlock(const Kind: String);
  begin
    if BlockCount >= Length(Blocks) then
      SetLength(Blocks, Max(64, 2 * BlockCount));
    Blocks[BlockCount] := Default(TUdmfBlock);
    Blocks[BlockCount].Kind := LowerCase(Kind);
    Inc(BlockCount);
  end;

  procedure AddValue(var B: TUdmfBlock; const Key, Value: String);
  begin
    if B.Count >= Length(B.Keys) then
    begin
      SetLength(B.Keys, Max(8, 2 * B.Count));
      SetLength(B.Values, Length(B.Keys));
    end;
    B.Keys[B.Count] := LowerCase(Key);
    B.Values[B.Count] := Value;
    Inc(B.Count);
  end;

var
  Name, Value: String;
begin
  FError := '';
  FNamespace := '';
  BlockCount := 0;
  Blocks := nil;
  P := 1;
  N := Length(Text);
  Line := 1;
  Next;
  while (TokKind <> '') and (FError = '') do
  begin
    if TokKind <> 'id' then
    begin
      Fail(Format('expected a name, found "%s"', [Tok]));
      Break;
    end;
    Name := Tok;
    Next;
    if TokKind = '=' then
    begin
      { A global assignment. }
      Next;
      Value := Tok;
      Next;
      if TokKind <> ';' then Fail('expected ";"');
      if LowerCase(Name) = 'namespace' then
        FNamespace := LowerCase(Value);
      Next;
    end else
    if TokKind = '{' then
    begin
      AddBlock(Name);
      Next;
      while (TokKind = 'id') and (FError = '') do
      begin
        Name := Tok;
        Next;
        if TokKind <> '=' then
        begin
          Fail(Format('expected "=" after "%s"', [Name]));
          Break;
        end;
        Next;
        if (TokKind <> 'id') and (TokKind <> 'str') then
        begin
          Fail(Format('expected a value for "%s"', [Name]));
          Break;
        end;
        AddValue(Blocks[BlockCount - 1], Name, Tok);
        Next;
        if TokKind <> ';' then
        begin
          Fail(Format('expected ";" after "%s"', [Name]));
          Break;
        end;
        Next;
      end;
      if FError <> '' then Break;
      if TokKind <> '}' then
      begin
        Fail('expected "}"');
        Break;
      end;
      Next;
    end else
      Fail(Format('expected "=" or "{" after "%s"', [Name]));
  end;
  SetLength(Blocks, BlockCount);
end;

{ Block values -------------------------------------------------------------- }

function FindValue(const B: TUdmfBlock; const Key: String; out Value: String): Boolean;
var
  I: Integer;
begin
  for I := 0 to B.Count - 1 do
    if B.Keys[I] = Key then
    begin
      Value := B.Values[I];
      Exit(true);
    end;
  Value := '';
  Result := false;
end;

function UdmfHas(const B: TUdmfBlock; const Key: String): Boolean;
var
  V: String;
begin
  Result := FindValue(B, Key, V);
end;

function UdmfStr(const B: TUdmfBlock; const Key: String; const Default: String): String;
begin
  if not FindValue(B, Key, Result) then Result := Default;
end;

function UdmfFloat(const B: TUdmfBlock; const Key: String; const Default: Double): Double;
var
  V, Hex: String;
  Neg: Boolean;
  Code: Integer;
  I: Int64;
begin
  Result := Default;
  if not FindValue(B, Key, V) then Exit;
  Neg := (V <> '') and (V[1] in ['-', '+']);
  if Neg then Hex := Copy(V, 2, MaxInt) else Hex := V;
  if (Length(Hex) > 2) and (Hex[1] = '0') and (Hex[2] in ['x', 'X']) then
  begin
    Val('$' + Copy(Hex, 3, MaxInt), I, Code);
    if Code = 0 then
    begin
      if V[1] = '-' then I := -I;
      Result := I;
    end;
    Exit;
  end;
  Val(V, Result, Code);
  if Code <> 0 then Result := Default;
end;

function UdmfInt(const B: TUdmfBlock; const Key: String; const Default: Integer): Integer;
begin
  Result := Round(UdmfFloat(B, Key, Default));
end;

function UdmfBool(const B: TUdmfBlock; const Key: String; const Default: Boolean): Boolean;
var
  V: String;
begin
  if not FindValue(B, Key, V) then Exit(Default);
  Result := LowerCase(V) = 'true';
end;

{ Specials ------------------------------------------------------------------ }

function UdmfAcsSpecial(const Special: Integer): Boolean;
begin
  Result := (Special >= UdmfAcsExecute) and (Special <= UdmfAcsSuspend);
end;

function UdmfSpecialName(const Special: Integer): String;
begin
  case Special of
    UdmfFloorByValue: Result := 'floor by value';
    UdmfFloorToValue: Result := 'floor to value';
    UdmfCeilingByValue: Result := 'ceiling by value';
    UdmfCeilingToValue: Result := 'ceiling to value';
    UdmfLightToValue: Result := 'light to value';
    UdmfLightByValue: Result := 'light by value';
    UdmfScrollWall: Result := 'scrolling wall';
    UdmfAcsExecute: Result := 'ACS_Execute';
    UdmfAcsExecuteAlways: Result := 'ACS_ExecuteAlways';
    UdmfAcsExecuteWithResult: Result := 'ACS_ExecuteWithResult';
    UdmfAcsLockedExecute: Result := 'ACS_LockedExecute';
    UdmfAcsTerminate: Result := 'ACS_Terminate';
    UdmfAcsSuspend: Result := 'ACS_Suspend';
    else Result := Format('special %d', [Special]);
  end;
end;


const
  { Boom's generalized speeds in map units a tic, slow to turbo. }
  FloorSpeeds: array [0..3] of Single = (1, 2, 4, 8);
  DoorSpeeds: array [0..3] of Single = (2, 4, 8, 16);
  LiftSpeeds: array [0..3] of Single = (2, 4, 8, 16);
  StairSpeeds: array [0..3] of Single = (0.25, 0.5, 2, 4);
  DoorDelays: array [0..3] of Integer = (35, 150, 300, 30 * 35);
  LiftDelays: array [0..3] of Integer = (35, 3 * 35, 5 * 35, 10 * 35);
  StepSizes: array [0..3] of Integer = (4, 8, 16, 24);

{ The bucket nearest to Value (speeds compared by ratio). }
function NearestSpeed(const Speeds: array of Single; const Value: Single): Integer;
var
  I: Integer;
  Best, D: Single;
begin
  Result := 0;
  if Value <= 0 then Exit(1);
  Best := MaxSingle;
  for I := 0 to High(Speeds) do
  begin
    D := Abs(Ln(Value / Speeds[I]));
    if D < Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

function NearestInt(const Values: array of Integer; const Value: Integer): Integer;
var
  I, Best: Integer;
begin
  Result := 0;
  Best := MaxInt;
  for I := 0 to High(Values) do
    if Abs(Values[I] - Value) < Best then
    begin
      Best := Abs(Values[I] - Value);
      Result := I;
    end;
end;

function HexenActionName(const Special: Integer): String;
begin
  case Special of
    1..8: Result := 'Polyobj_*';
    9: Result := 'Line_Horizon';
    10: Result := 'Door_Close';
    11: Result := 'Door_Open';
    12: Result := 'Door_Raise';
    13: Result := 'Door_LockedRaise';
    20: Result := 'Floor_LowerByValue';
    21: Result := 'Floor_LowerToLowest';
    22: Result := 'Floor_LowerToNearest';
    23: Result := 'Floor_RaiseByValue';
    24: Result := 'Floor_RaiseToHighest';
    25: Result := 'Floor_RaiseToNearest';
    26: Result := 'Stairs_BuildDown';
    27: Result := 'Stairs_BuildUp';
    28: Result := 'Floor_RaiseAndCrush';
    29: Result := 'Pillar_Build';
    35: Result := 'Floor_RaiseByValueTimes8';
    36: Result := 'Floor_LowerByValueTimes8';
    37: Result := 'Floor_MoveToValue';
    40: Result := 'Ceiling_LowerByValue';
    41: Result := 'Ceiling_RaiseByValue';
    42: Result := 'Ceiling_CrushAndRaise';
    43: Result := 'Ceiling_LowerAndCrush';
    44: Result := 'Ceiling_CrushStop';
    45: Result := 'Ceiling_CrushRaiseAndStay';
    47: Result := 'Ceiling_MoveToValue';
    52: Result := 'Scroll_Wall';
    57: Result := 'Sector_SetPortal';
    60: Result := 'Plat_PerpetualRaise';
    61: Result := 'Plat_Stop';
    62: Result := 'Plat_DownWaitUpStay';
    66: Result := 'Floor_LowerInstant';
    67: Result := 'Floor_RaiseInstant';
    70: Result := 'Teleport';
    71: Result := 'Teleport_NoFog';
    74: Result := 'Teleport_NewMap';
    75: Result := 'Teleport_EndGame';
    80: Result := 'ACS_Execute';
    83: Result := 'ACS_LockedExecute';
    84: Result := 'ACS_ExecuteWithResult';
    85: Result := 'ACS_LockedExecuteDoor';
    100: Result := 'Scroll_Texture_Left';
    101: Result := 'Scroll_Texture_Right';
    102: Result := 'Scroll_Texture_Up';
    103: Result := 'Scroll_Texture_Down';
    110: Result := 'Light_RaiseByValue';
    111: Result := 'Light_LowerByValue';
    112: Result := 'Light_ChangeToValue';
    116: Result := 'Light_Strobe';
    121: Result := 'Line_SetIdentification';
    156: Result := 'Line_SetPortal';
    160: Result := 'Sector_Set3dFloor';
    181: Result := 'Plane_Align';
    182: Result := 'Line_Mirror';
    190: Result := 'Static_Init';
    192: Result := 'Ceiling_LowerToHighestFloor';
    195: Result := 'Ceiling_CrushRaiseAndStayA';
    196: Result := 'Ceiling_CrushAndRaiseA';
    197: Result := 'Ceiling_CrushAndRaiseSilentA';
    200: Result := 'Generic_Floor';
    201: Result := 'Generic_Ceiling';
    202: Result := 'Generic_Door';
    203: Result := 'Generic_Lift';
    204: Result := 'Generic_Stairs';
    205: Result := 'Generic_Crusher';
    206: Result := 'Plat_DownWaitUpStayLip';
    207: Result := 'Plat_PerpetualRaiseLip';
    208: Result := 'TranslucentLine';
    209: Result := 'Transfer_Heights';
    210: Result := 'Transfer_FloorLight';
    211: Result := 'Transfer_CeilingLight';
    212: Result := 'Sector_SetColor';
    213: Result := 'Sector_SetFade';
    215: Result := 'Teleport_Line';
    217: Result := 'Stairs_BuildUpDoom';
    218: Result := 'Sector_SetWind';
    219: Result := 'Sector_SetFriction';
    220: Result := 'Sector_SetCurrent';
    223: Result := 'Scroll_Floor';
    224: Result := 'Scroll_Ceiling';
    226: Result := 'ACS_ExecuteAlways';
    232: Result := 'Light_StrobeDoom';
    233: Result := 'Light_MinNeighbor';
    234: Result := 'Light_MaxNeighbor';
    238: Result := 'Floor_RaiseToLowestCeiling';
    240: Result := 'Floor_RaiseByTexture';
    241: Result := 'Floor_LowerToLowestTxTy';
    242: Result := 'Floor_LowerToHighest';
    243: Result := 'Exit_Normal';
    244: Result := 'Exit_Secret';
    245: Result := 'Elevator_RaiseToNearest';
    246: Result := 'Elevator_MoveToFloor';
    247: Result := 'Elevator_LowerToNearest';
    249: Result := 'Door_CloseWaitOpen';
    250: Result := 'Floor_Donut';
    252: Result := 'Ceiling_RaiseToNearest';
    253: Result := 'Ceiling_LowerToLowest';
    254: Result := 'Ceiling_LowerToFloor';
    else Result := Format('action %d', [Special]);
  end;
end;

function TranslateHexenLine(const Special: Integer; const Args: array of Integer;
  const Activation: Integer): THexenLine;
var
  A: array [0..4] of Integer;
  I, Trig: Integer;
  Cross, Use, Impact, Rep, Monster, Manual: Boolean;

  { One of four numbers by how the line is triggered: walk once / again,
    switch once / again (-1: no such type). }
  procedure Pick(const W1, WR, S1, SR: Integer; const G1: Integer = -1; const GR: Integer = -1);
  var
    S: Integer;
  begin
    if Impact then
    begin
      if Rep then S := GR else S := G1;
    end else
    if Use then
    begin
      if Rep then S := SR else S := S1;
    end else
    begin
      if Rep then S := WR else S := W1;
    end;
    if S < 0 then
      Result.Unsupported := HexenActionName(Special) + ' with this activation'
    else
      Result.Special := S;
  end;

  { Boom's trigger bits: W / S / G, once or again; D (use on the sector
    behind the line) when a used line has no tag. }
  function GenTrigger: Integer;
  begin
    if Impact then Result := 4
    else if Use then
    begin
      if Manual then Result := 6 else Result := 2;
    end else
      Result := 0;
    if Rep then Inc(Result);
  end;

  function Floor(const Speed: Single; const Up: Boolean; const Target: Integer;
    const Crush: Boolean = false; const Change: Integer = 0; const NumericModel: Boolean = false): Integer;
  begin
    Result := GenFloorBase + GenTrigger + NearestSpeed(FloorSpeeds, Speed) shl 3 + Target shl 7 +
      Change shl 10;
    if Change = 0 then
    begin
      if Monster then Result := Result + $20;
    end else
    if NumericModel then
      Result := Result + $20;
    if Up then Result := Result + $40;
    if Crush then Result := Result + $1000;
  end;

  function Ceiling(const Speed: Single; const Up: Boolean; const Target: Integer;
    const Crush: Boolean = false; const Change: Integer = 0; const NumericModel: Boolean = false): Integer;
  begin
    Result := Floor(Speed, Up, Target, Crush, Change, NumericModel) - GenFloorBase + GenCeilingBase;
  end;

  function Door(const Speed: Single; const Kind, Delay: Integer): Integer;
  begin
    Result := GenDoorBase + GenTrigger + NearestSpeed(DoorSpeeds, Speed) shl 3 + Kind shl 5 +
      NearestInt(DoorDelays, Delay) shl 8;
    if Monster then Result := Result + $80;
  end;

  { ZDoom's lock numbers (LOCKDEFS) as Boom's key bits, -1 for none. }
  function LockedDoor(const Speed: Single; const Stay: Boolean; const Lock: Integer): Integer;
  var
    Key: Integer;
    Either: Boolean;
  begin
    Either := false;
    case Lock of
      1..6: Key := Lock;
      100: Key := 0;
      101: Key := 7;
      129..131:
        begin
          Key := Lock - 128;
          Either := true;
        end;
      229:
        begin
          Key := 7;
          Either := true;
        end;
      else Exit(-1);
    end;
    Result := GenLockedBase + GenTrigger + NearestSpeed(DoorSpeeds, Speed) shl 3 + Key shl 6;
    if Stay then Result := Result + $20;
    if Either then Result := Result + $200;
  end;

  function Lift(const Speed: Single; const Delay, Target: Integer): Integer;
  begin
    Result := GenLiftBase + GenTrigger + NearestSpeed(LiftSpeeds, Speed) shl 3 +
      NearestInt(LiftDelays, Delay) shl 6 + Target shl 8;
    if Monster then Result := Result + $20;
  end;

  function Stairs(const Speed: Single; const Step: Integer; const Up, IgnoreTexture: Boolean): Integer;
  begin
    Result := GenStairsBase + GenTrigger + NearestSpeed(StairSpeeds, Speed) shl 3 +
      NearestInt(StepSizes, Step) shl 6;
    if Monster then Result := Result + $20;
    if Up then Result := Result + $100;
    if IgnoreTexture then Result := Result + $200;
  end;

  function Crusher(const Speed: Single; const Silent: Boolean): Integer;
  begin
    Result := GenCrusherBase + GenTrigger + NearestSpeed(FloorSpeeds, Speed) shl 3;
    if Monster then Result := Result + $20;
    if Silent then Result := Result + $40;
  end;

  { A move by a height: Boom's 24 / 32 targets when they fit, else the
    world's own type with the arguments. }
  procedure ByValue(const IsFloor: Boolean; const Speed: Single; const Height: Integer);
  begin
    if (Abs(Height) = 24) or (Abs(Height) = 32) then
    begin
      if IsFloor then
        Result.Special := Floor(Speed, Height > 0, IfThen(Abs(Height) = 24, 6, 7))
      else
        Result.Special := Ceiling(Speed, Height > 0, IfThen(Abs(Height) = 24, 6, 7));
      Exit;
    end;
    if IsFloor then Result.Special := UdmfFloorByValue else Result.Special := UdmfCeilingByValue;
    Result.Args[0] := A[0];
    Result.Args[1] := Round(Speed * 8);
    Result.Args[2] := Height;
  end;

  procedure ToValue(const IsFloor: Boolean; const Speed: Single; const Height: Integer);
  begin
    if IsFloor then Result.Special := UdmfFloorToValue else Result.Special := UdmfCeilingToValue;
    Result.Args[0] := A[0];
    Result.Args[1] := Round(Speed * 8);
    Result.Args[2] := Height;
  end;

  procedure LightTo(const Level: Integer);
  begin
    if Level = 35 then Pick(35, 79, 170, 139)
    else if Level = 255 then Pick(13, 81, 171, 138)
    else
    begin
      Result.Special := UdmfLightToValue;
      Result.Args[0] := A[0];
      Result.Args[1] := Level;
    end;
  end;

  { Generic_Floor / Generic_Ceiling's target and flags. }
  procedure Generic(const IsFloor: Boolean);
  const
    { Their targets 1..6 as Boom's. }
    Targets: array [1..6] of Integer = (0, 1, 2, 3, 4, 5);
  var
    Up, Crush, Numeric: Boolean;
    Change, Target: Integer;
    Speed: Single;
  begin
    Speed := A[1] / 8;
    Change := A[4] and 3;
    Numeric := (A[4] and 4) <> 0;
    Up := (A[4] and 8) <> 0;
    Crush := (A[4] and 16) <> 0;
    Target := A[3];
    if Target = 0 then
    begin
      if Up then ByValue(IsFloor, Speed, A[2]) else ByValue(IsFloor, Speed, -A[2]);
      Exit;
    end;
    if (Target < 1) or (Target > 6) then
    begin
      Result.Unsupported := HexenActionName(Special) + ' target ' + IntToStr(Target);
      Exit;
    end;
    if IsFloor then
      Result.Special := Floor(Speed, Up, Targets[Target], Crush, Change, Numeric)
    else
      Result.Special := Ceiling(Speed, Up, Targets[Target], Crush, Change, Numeric);
  end;

begin
  Result := Default(THexenLine);
  Result.Alpha := 1;
  for I := 0 to 4 do
    if I <= High(Args) then A[I] := Args[I] else A[I] := 0;
  Cross := (Activation and (UaPlayerCross or UaMonsterCross or UaMissileCross)) <> 0;
  Use := (Activation and (UaPlayerUse or UaMonsterUse or UaPlayerPush or UaMonsterPush)) <> 0;
  Impact := (Activation and UaImpact) <> 0;
  if Impact then Use := false;
  if Use then Cross := false;
  Rep := (Activation and UaRepeat) <> 0;
  Monster := (Activation and (UaMonsterCross or UaMonsterUse or UaMonsterPush)) <> 0;
  Manual := Use and (A[0] = 0);
  { Most actions work on the sectors tagged by their first argument. }
  Result.Tag := A[0];
  Trig := GenTrigger;
  Result.Trigger := Trig;
  if Monster then Result.Trigger := Result.Trigger + 8;
  if not (Cross or Use or Impact) and not (Special in [100..103, 121, 208..211]) then
  begin
    { No activation (only scripts could trigger it). }
    if Special <> 0 then
      Result.Unsupported := HexenActionName(Special) + ' without activation';
    Exit;
  end;

  case Special of
    0: ;
    { Doors }
    10: Result.Special := Door(A[1] / 8, 3, 150);
    11: Result.Special := Door(A[1] / 8, 1, 150);
    12:
      if A[2] = 0 then
        Result.Special := Door(A[1] / 8, 1, 150)
      else
        Result.Special := Door(A[1] / 8, 0, A[2]);
    249: Result.Special := Door(A[1] / 8, 2, A[2]);
    13:
      begin
        Result.Special := LockedDoor(A[1] / 8, A[2] = 0, A[3]);
        if Result.Special < 0 then
        begin
          Result.Special := 0;
          if A[3] = 0 then
          begin
            if A[2] = 0 then Result.Special := Door(A[1] / 8, 1, 150)
            else Result.Special := Door(A[1] / 8, 0, A[2]);
          end else
            Result.Unsupported := Format('Door_LockedRaise with lock %d', [A[3]]);
        end;
      end;
    202:
      if A[4] <> 0 then
      begin
        Result.Special := LockedDoor(A[1] / 8, (A[2] and 3) = 1, A[4]);
        if Result.Special < 0 then
        begin
          Result.Special := 0;
          Result.Unsupported := Format('Generic_Door with lock %d', [A[4]]);
        end;
      end else
        Result.Special := Door(A[1] / 8, A[2] and 3, A[3] * 35 div 8);
    { Floors }
    20: ByValue(true, A[1] / 8, -A[2]);
    23: ByValue(true, A[1] / 8, A[2]);
    35: ByValue(true, A[1] / 8, A[2] * 8);
    36: ByValue(true, A[1] / 8, -A[2] * 8);
    21: Result.Special := Floor(A[1] / 8, false, 1);
    22: Result.Special := Floor(A[1] / 8, false, 2);
    24: Result.Special := Floor(A[1] / 8, true, 0);
    25: Result.Special := Floor(A[1] / 8, true, 2);
    28: Result.Special := Floor(A[1] / 8, true, 4, true);
    37: if A[3] <> 0 then ToValue(true, A[1] / 8, -A[2]) else ToValue(true, A[1] / 8, A[2]);
    66: ByValue(true, 4096, -A[2] * 8);
    67: ByValue(true, 4096, A[2] * 8);
    238: Result.Special := Floor(A[1] / 8, true, 3);
    240: Result.Special := Floor(A[1] / 8, true, 5);
    241: Result.Special := Floor(A[1] / 8, false, 1, false, 2, true);
    242: Result.Special := Floor(A[1] / 8, false, 0);
    200: Generic(true);
    250: Pick(146, 155, 9, 191);
    { Stairs }
    26: Result.Special := Stairs(A[1] / 8, A[2], false, true);
    27: Result.Special := Stairs(A[1] / 8, A[2], true, true);
    217: Result.Special := Stairs(A[1] / 8, A[2], true, false);
    204: Result.Special := Stairs(A[1] / 8, A[2], (A[3] and 1) <> 0, (A[3] and 2) <> 0);
    { Ceilings and crushers }
    40: ByValue(false, A[1] / 8, -A[2]);
    41: ByValue(false, A[1] / 8, A[2]);
    47: if A[3] <> 0 then ToValue(false, A[1] / 8, -A[2]) else ToValue(false, A[1] / 8, A[2]);
    43: Result.Special := Ceiling(A[1] / 8, false, 4, true);
    192: Result.Special := Ceiling(A[1] / 8, false, 3);
    252: Result.Special := Ceiling(A[1] / 8, true, 2);
    253: Result.Special := Ceiling(A[1] / 8, false, 1);
    254: Result.Special := Ceiling(A[1] / 8, false, 4);
    201: Generic(false);
    42, 45, 195, 196: Result.Special := Crusher(A[1] / 8, false);
    197: Result.Special := Crusher(A[1] / 8, true);
    205: Result.Special := Crusher(A[1] / 8, A[3] <> 0);
    44: Pick(57, 74, 168, 188);
    { Lifts }
    62, 206: Result.Special := Lift(A[1] / 8, A[2], 0);
    60, 207: Result.Special := Lift(A[1] / 8, A[2], 3);
    61: Pick(54, 89, 163, 182);
    203:
      if (A[3] >= 1) and (A[3] <= 4) then
        Result.Special := Lift(A[1] / 8, A[2] * 35 div 8, A[3] - 1)
      else
        Result.Unsupported := Format('Generic_Lift type %d', [A[3]]);
    245: Pick(227, 228, 229, 230);
    247: Pick(231, 232, 233, 234);
    246: Pick(235, 236, 237, 238);
    { Exits }
    243, 74, 75:
      begin
        Pick(52, 52, 11, 11, 197, 197);
        Result.Tag := 0;
      end;
    244:
      begin
        Pick(124, 124, 51, 51, 198, 198);
        Result.Tag := 0;
      end;
    { Teleports: by sector tag, or by the destination's thing id. }
    70, 71:
      begin
        if Special = 70 then
        begin
          Result.Tag := A[1];
          if (Activation and (UaPlayerCross or UaPlayerUse)) = 0 then
            Pick(125, 126, -1, -1)
          else
            Pick(39, 97, 174, 195);
        end else
        begin
          Result.Tag := A[2];
          Pick(207, 208, 209, 210);
        end;
        if (Result.Tag = 0) and (A[0] <> 0) then
          Result.TeleportTid := A[0];
      end;
    215:
      begin
        if A[2] <> 0 then Pick(262, 263, -1, -1) else Pick(243, 244, -1, -1);
        Result.Tag := A[1];
        Result.LineTeleportId := A[1];
      end;
    { Lights }
    112: LightTo(A[1]);
    110, 111:
      begin
        Result.Special := UdmfLightByValue;
        Result.Args[0] := A[0];
        if Special = 110 then Result.Args[1] := A[1] else Result.Args[1] := -A[1];
      end;
    116, 232: Pick(17, 156, 172, 193);
    233: Pick(104, 157, 173, 194);
    234: Pick(12, 80, 169, 192);
    { Static: scrolling walls, transfers, translucency. }
    100, 101, 102, 103:
      begin
        Result.Special := UdmfScrollWall;
        Result.Tag := 0;
        case Special of
          100: Result.Args[0] := A[0];
          101: Result.Args[0] := -A[0];
          102: Result.Args[1] := A[0];
          else Result.Args[1] := -A[0];
        end;
      end;
    209: Result.Special := 242;
    210: Result.Special := 213;
    211: Result.Special := 261;
    208:
      begin
        Result.Tag := 0;
        Result.TranslucentId := A[0];
        Result.Alpha := A[1] / 255;
        { Line 0: this line, marked by -1. }
        if A[0] = 0 then Result.TranslucentId := -1;
      end;
    121: Result.Tag := 0;
    { Scripts: the arguments as they are. }
    80, 81, 82, 83, 84, 85, 226:
      begin
        case Special of
          80: Result.Special := UdmfAcsExecute;
          81: Result.Special := UdmfAcsTerminate;
          82: Result.Special := UdmfAcsSuspend;
          84: Result.Special := UdmfAcsExecuteWithResult;
          226: Result.Special := UdmfAcsExecuteAlways;
          else Result.Special := UdmfAcsLockedExecute;
        end;
        Result.Tag := 0;
        for I := 0 to 4 do Result.Args[I] := A[I];
      end;
    else
      begin
        Result.Tag := 0;
        Result.Unsupported := HexenActionName(Special);
      end;
  end;
  if Result.Unsupported <> '' then
  begin
    Result.Special := 0;
    Result.Tag := 0;
  end;
  if Result.Special >= UdmfSpecialBase then
    Result.Trigger := Trig + IfThen(Monster, 8, 0);
end;

function TranslateZDoomSectorSpecial(const Special: Integer): Integer;
var
  Low: Integer;
begin
  Low := Special and 255;
  if (Low >= 65) and (Low <= 81) then
    Result := Low - 64
  else
    Result := 0;
  { Doom's 9 (secret) is ZDoom's secret bit. }
  if Result = 9 then Result := 0;
  Result := Result or (((Special shr 8) and 3) shl 5);
  if (Special and 1024) <> 0 then Result := Result or 128;
  if (Special and 2048) <> 0 then Result := Result or 256;
  if (Special and 4096) <> 0 then Result := Result or 512;
end;

end.
