{ Boom's generalized linedef types (boomref.txt, p_genlin.c): line
  specials 0x2F80..0x7FFF whose bit fields say what moves, how fast, how
  far, how the line is triggered and whether monsters may trigger it.
  This unit only decodes them; TDoomWorld.ApplyGeneralized
  (doomworld_generalized.inc) runs them with the vanilla movers. }
unit DoomGeneralized;

interface

const
  GenCrusherBase = $2F80;
  GenStairsBase = $3000;
  GenLiftBase = $3400;
  GenLockedBase = $3800;
  GenDoorBase = $3C00;
  GenCeilingBase = $4000;
  GenFloorBase = $6000;
  GenEnd = $8000;

type
  TGenKind = (gkNone, gkCrusher, gkStairs, gkLift, gkLockedDoor, gkDoor, gkCeiling, gkFloor);
  { W = walk over, S = switch (use), G = gun (shoot), D = door style
    (use, acting on the sector behind the line, no tag). }
  TGenTrigger = (gtW1, gtWR, gtS1, gtSR, gtG1, gtGR, gtD1, gtDR);
  TGenSpeed = (gsSlow, gsNormal, gsFast, gsTurbo);
  { Floor targets: highest / lowest / next neighbour floor, lowest
    neighbour ceiling, own ceiling, shortest lower texture, 24, 32.
    Ceilings use the same numbers with floors and ceilings swapped. }
  TGenTarget = (gtHighestNeighbour, gtLowestNeighbour, gtNextNeighbour, gtLowestOther,
    gtOwnOther, gtShortestTexture, gtBy24, gtBy32);
  { Texture (and special) change: none, texture and special zeroed,
    texture only, texture and special. }
  TGenChange = (gcNone, gcZeroSpecial, gcTexture, gcTextureAndSpecial);
  { Doors: open-wait-close, open, close-wait-open, close. }
  TGenDoorKind = (gdOpenWaitClose, gdOpen, gdCloseWaitOpen, gdClose);
  { Locked doors: any key, red / blue / yellow card, red / blue / yellow
    skull, all six. }
  TGenKey = (gkyAny, gkyRedCard, gkyBlueCard, gkyYellowCard, gkyRedSkull, gkyBlueSkull,
    gkyYellowSkull, gkyAll);
  { Lifts: down to the lowest / next lower neighbour floor, to the lowest
    neighbour ceiling, or up and down between the lowest and highest
    neighbour floors for ever. }
  TGenLiftTarget = (glLowestFloor, glNextFloor, glLowestCeiling, glPerpetual);

  TGenLine = record
    Kind: TGenKind;
    Trigger: TGenTrigger;
    Speed: TGenSpeed;
    { Monsters may trigger it (never for locked doors). }
    Monster: Boolean;
    { Floors and ceilings. }
    Up: Boolean;
    Target: TGenTarget;
    Change: TGenChange;
    { The texture comes from the sector at the destination height (true)
      or from the line's front sector (false). }
    NumericModel: Boolean;
    Crush: Boolean;
    { Doors. }
    DoorKind: TGenDoorKind;
    DelayTics: Integer;
    { Locked doors. }
    Key: TGenKey;
    { A skull opens a card's door and the other way round. }
    SkullIsCard: Boolean;
    { Lifts. }
    LiftTarget: TGenLiftTarget;
    { Stairs. }
    StepSize: Integer;
    IgnoreTexture: Boolean;
    { Crushers. }
    Silent: Boolean;
  end;

function IsGeneralized(const Special: Integer): Boolean;
{ Kind = gkNone when Special is not a generalized type. }
function DecodeGeneralized(const Special: Integer): TGenLine;
{ Repeatable (WR, SR, GR, DR). }
function GenRepeatable(const G: TGenLine): Boolean;
{ Manual (D1, DR): acts on the sector behind the line, needs no tag. }
function GenManual(const G: TGenLine): Boolean;
{ A monster may trigger this special by walking over it (Walk) or by
  bumping into it (use: S and D triggers). }
function GenMonsterTrigger(const Special: Integer; const Walk: Boolean): Boolean;
{ A short description for the log, e.g. "floor down to lowest neighbour
  floor, fast, S1". }
function GenDescription(const G: TGenLine): String;

implementation

uses SysUtils;

const
  TriggerNames: array [TGenTrigger] of String = ('W1', 'WR', 'S1', 'SR', 'G1', 'GR', 'D1', 'DR');
  SpeedNames: array [TGenSpeed] of String = ('slow', 'normal', 'fast', 'turbo');
  FloorTargetNames: array [TGenTarget] of String = ('highest neighbour floor',
    'lowest neighbour floor', 'next neighbour floor', 'lowest neighbour ceiling', 'ceiling',
    'shortest lower texture', '24', '32');
  CeilingTargetNames: array [TGenTarget] of String = ('highest neighbour ceiling',
    'lowest neighbour ceiling', 'next neighbour ceiling', 'highest neighbour floor', 'floor',
    'shortest upper texture', '24', '32');
  DoorNames: array [TGenDoorKind] of String = ('open, wait, close', 'open', 'close, wait, open', 'close');
  KeyNames: array [TGenKey] of String = ('any key', 'red card', 'blue card', 'yellow card',
    'red skull', 'blue skull', 'yellow skull', 'all keys');
  LiftNames: array [TGenLiftTarget] of String = ('lowest neighbour floor', 'next lower floor',
    'lowest neighbour ceiling', 'perpetual');
  ChangeNames: array [TGenChange] of String = ('', ', change texture, zero special',
    ', change texture', ', change texture and special');
  StepSizes: array [0..3] of Integer = (4, 8, 16, 24);
  DoorDelays: array [0..3] of Integer = (35, 150, 300, 30 * 35);
  LiftDelays: array [0..3] of Integer = (35, 3 * 35, 5 * 35, 10 * 35);

function IsGeneralized(const Special: Integer): Boolean;
begin
  Result := (Special >= GenCrusherBase) and (Special < GenEnd);
end;

function DecodeGeneralized(const Special: Integer): TGenLine;
begin
  Result := Default(TGenLine);
  if not IsGeneralized(Special) then Exit;
  Result.Trigger := TGenTrigger(Special and 7);
  Result.Speed := TGenSpeed((Special shr 3) and 3);
  if Special >= GenFloorBase then
  begin
    Result.Kind := gkFloor;
    Result.Change := TGenChange((Special shr 10) and 3);
    { Bit 5 is the model with a change, else the monster flag. }
    if Result.Change = gcNone then
      Result.Monster := (Special and $20) <> 0
    else
      Result.NumericModel := (Special and $20) <> 0;
    Result.Up := (Special and $40) <> 0;
    Result.Target := TGenTarget((Special shr 7) and 7);
    Result.Crush := (Special and $1000) <> 0;
  end else
  if Special >= GenCeilingBase then
  begin
    Result.Kind := gkCeiling;
    Result.Change := TGenChange((Special shr 10) and 3);
    if Result.Change = gcNone then
      Result.Monster := (Special and $20) <> 0
    else
      Result.NumericModel := (Special and $20) <> 0;
    Result.Up := (Special and $40) <> 0;
    Result.Target := TGenTarget((Special shr 7) and 7);
    Result.Crush := (Special and $1000) <> 0;
  end else
  if Special >= GenDoorBase then
  begin
    Result.Kind := gkDoor;
    Result.DoorKind := TGenDoorKind((Special shr 5) and 3);
    Result.Monster := (Special and $80) <> 0;
    Result.DelayTics := DoorDelays[(Special shr 8) and 3];
  end else
  if Special >= GenLockedBase then
  begin
    Result.Kind := gkLockedDoor;
    if (Special and $20) <> 0 then
      Result.DoorKind := gdOpen
    else
      Result.DoorKind := gdOpenWaitClose;
    Result.Key := TGenKey((Special shr 6) and 7);
    Result.SkullIsCard := (Special and $200) <> 0;
    Result.DelayTics := 150;
  end else
  if Special >= GenLiftBase then
  begin
    Result.Kind := gkLift;
    Result.Monster := (Special and $20) <> 0;
    Result.DelayTics := LiftDelays[(Special shr 6) and 3];
    Result.LiftTarget := TGenLiftTarget((Special shr 8) and 3);
  end else
  if Special >= GenStairsBase then
  begin
    Result.Kind := gkStairs;
    Result.Monster := (Special and $20) <> 0;
    Result.StepSize := StepSizes[(Special shr 6) and 3];
    Result.Up := (Special and $100) <> 0;
    Result.IgnoreTexture := (Special and $200) <> 0;
  end else
  begin
    Result.Kind := gkCrusher;
    Result.Monster := (Special and $20) <> 0;
    Result.Silent := (Special and $40) <> 0;
  end;
end;

function GenRepeatable(const G: TGenLine): Boolean;
begin
  Result := Odd(Ord(G.Trigger));
end;

function GenManual(const G: TGenLine): Boolean;
begin
  Result := G.Trigger in [gtD1, gtDR];
end;

function GenMonsterTrigger(const Special: Integer; const Walk: Boolean): Boolean;
var
  G: TGenLine;
begin
  if not IsGeneralized(Special) then Exit(false);
  G := DecodeGeneralized(Special);
  if not G.Monster then Exit(false);
  if Walk then
    Result := G.Trigger in [gtW1, gtWR]
  else
    Result := G.Trigger in [gtS1, gtSR, gtD1, gtDR];
end;

function GenDescription(const G: TGenLine): String;
const
  UpDown: array [Boolean] of String = ('down', 'up');
begin
  case G.Kind of
    gkFloor:
      if G.Target in [gtBy24, gtBy32, gtShortestTexture] then
        Result := Format('floor %s by %s', [UpDown[G.Up], FloorTargetNames[G.Target]])
      else
        Result := Format('floor %s to %s', [UpDown[G.Up], FloorTargetNames[G.Target]]);
    gkCeiling:
      if G.Target in [gtBy24, gtBy32, gtShortestTexture] then
        Result := Format('ceiling %s by %s', [UpDown[G.Up], CeilingTargetNames[G.Target]])
      else
        Result := Format('ceiling %s to %s', [UpDown[G.Up], CeilingTargetNames[G.Target]]);
    gkDoor: Result := Format('door %s, delay %d tics', [DoorNames[G.DoorKind], G.DelayTics]);
    gkLockedDoor: Result := Format('locked door (%s%s) %s', [KeyNames[G.Key],
      BoolToStr(G.SkullIsCard, ', skull = card', ''), DoorNames[G.DoorKind]]);
    gkLift: Result := Format('lift to %s, delay %d tics', [LiftNames[G.LiftTarget], G.DelayTics]);
    gkStairs: Result := Format('stairs %s by %d%s', [UpDown[G.Up], G.StepSize,
      BoolToStr(G.IgnoreTexture, ', any texture', '')]);
    gkCrusher: Result := 'crusher' + BoolToStr(G.Silent, ', silent', '');
    else Exit('not generalized');
  end;
  if G.Kind in [gkFloor, gkCeiling] then
  begin
    Result := Result + ChangeNames[G.Change];
    if G.Change <> gcNone then
      Result := Result + BoolToStr(G.NumericModel, ' (numeric model)', ' (trigger model)');
    if G.Crush then Result := Result + ', crush';
  end;
  Result := Result + ', ' + SpeedNames[G.Speed] + ', ' + TriggerNames[G.Trigger];
  if G.Monster then Result := Result + ', monsters too';
end;

end.
