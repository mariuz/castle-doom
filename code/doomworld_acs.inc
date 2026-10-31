{%MainUnit doomworld.pas}
{ ACS scripts of UDMF maps (DoomAcs): the map's BEHAVIOR lump runs in a
  TAcsVM, a tic at a time in RunTic. What a script does to the world
  comes back through TWorldAcsHost: Hexen's actions are translated like a
  UDMF line's (DoomUdmf's TranslateHexenLine, walk-over-repeatable) and
  applied on a line borrowed for the call (the activating line, else line
  0), whose fields are put back afterwards. }

type
  TWorldAcsHost = class(TAcsHost)
  strict private
    FWorld: TDoomWorld;
  public
    constructor Create(const AWorld: TDoomWorld);
    function Random(const N: Integer): Integer; override;
    function LineSpecial(const Inst: TAcsInstance; const Special: Integer; const Args: TAcsArgs): Integer; override;
    procedure Print(const Inst: TAcsInstance; const Text: String; const Kind: TAcsPrintKind); override;
    function TagBusy(const Tag: Integer): Boolean; override;
    function ThingCount(const SpawnNum, Tid: Integer): Integer; override;
    function ThingCountName(const Name: String; const Tid: Integer): Integer; override;
    procedure ChangeFlat(const Tag: Integer; const Name: String; const Ceiling: Boolean); override;
    procedure ClearLineSpecial(const Line: Integer); override;
    procedure SetLineTexture(const LineId, Side, Position: Integer; const Name: String); override;
    procedure SetLineBlocking(const LineId, Mode: Integer); override;
    procedure SetLineMonsterBlocking(const LineId: Integer; const Block: Boolean); override;
    procedure SetLineSpecial(const LineId, Special: Integer; const Args: TAcsArgs); override;
    procedure SetMusic(const Name: String); override;
    procedure PlaySound(const Inst: TAcsInstance; const Name: String; const Volume, Where: Integer); override;
    function GameSkill: Integer; override;
    function LevelTime: Integer; override;
    function PlayerHealth: Integer; override;
    function PlayerArmor: Integer; override;
    function PlayerHasKey(const Index: Integer): Boolean; override;
    function ActorValue(const Inst: TAcsInstance; const Tid, What: Integer): Integer; override;
    function SectorValue(const Tag, What: Integer): Integer; override;
    function Localize(const Name: String): String; override;
    function ThisMap(const N: Integer): Boolean; override;
  end;

  TAcsThingName = record
    Name: String;
    SpawnNum, DoomNum: Integer;
  end;

const
  { ZDoom's class names and spawn numbers (zdefs.acs's T_*) of Doom's
    monsters and the barrel. }
  AcsThingNames: array [0..18] of TAcsThingName = (
    (Name: 'ZombieMan'; SpawnNum: 4; DoomNum: 3004),
    (Name: 'ShotgunGuy'; SpawnNum: 1; DoomNum: 9),
    (Name: 'ChaingunGuy'; SpawnNum: 2; DoomNum: 65),
    (Name: 'DoomImp'; SpawnNum: 5; DoomNum: 3001),
    (Name: 'Demon'; SpawnNum: 8; DoomNum: 3002),
    (Name: 'Spectre'; SpawnNum: 9; DoomNum: 58),
    (Name: 'LostSoul'; SpawnNum: 110; DoomNum: 3006),
    (Name: 'Cacodemon'; SpawnNum: 19; DoomNum: 3005),
    (Name: 'HellKnight'; SpawnNum: 113; DoomNum: 69),
    (Name: 'BaronOfHell'; SpawnNum: 3; DoomNum: 3003),
    (Name: 'Arachnotron'; SpawnNum: 6; DoomNum: 68),
    (Name: 'PainElemental'; SpawnNum: 115; DoomNum: 71),
    (Name: 'Revenant'; SpawnNum: 20; DoomNum: 66),
    (Name: 'Fatso'; SpawnNum: 112; DoomNum: 67),
    (Name: 'Archvile'; SpawnNum: 111; DoomNum: 64),
    (Name: 'Cyberdemon'; SpawnNum: 114; DoomNum: 16),
    (Name: 'SpiderMastermind'; SpawnNum: 7; DoomNum: 7),
    (Name: 'WolfensteinSS'; SpawnNum: 116; DoomNum: 84),
    (Name: 'ExplosiveBarrel'; SpawnNum: 125; DoomNum: 2035)
  );

constructor TWorldAcsHost.Create(const AWorld: TDoomWorld);
begin
  inherited Create;
  FWorld := AWorld;
end;

function TWorldAcsHost.Random(const N: Integer): Integer;
begin
  Result := FWorld.AcsRandom(N);
end;

function TWorldAcsHost.LineSpecial(const Inst: TAcsInstance; const Special: Integer; const Args: TAcsArgs): Integer;
begin
  Result := FWorld.AcsLineSpecial(Inst, Special, Args);
end;

procedure TWorldAcsHost.Print(const Inst: TAcsInstance; const Text: String; const Kind: TAcsPrintKind);
var
  S: String;
begin
  S := Trim(StringReplace(Text, #10, ' ', [rfReplaceAll]));
  WritelnLog('Acs', 'script %d prints "%s"', [Inst.Number, S]);
  if (Kind <> apLog) and (S <> '') then
    FWorld.ShowMessage(S);
end;

function TWorldAcsHost.TagBusy(const Tag: Integer): Boolean;
begin
  Result := FWorld.AcsTagBusy(Tag);
end;

function TWorldAcsHost.ThingCount(const SpawnNum, Tid: Integer): Integer;
var
  I: Integer;
begin
  if SpawnNum = 0 then Exit(FWorld.AcsThingCount(0, Tid));
  for I := 0 to High(AcsThingNames) do
    if AcsThingNames[I].SpawnNum = SpawnNum then
      Exit(FWorld.AcsThingCount(AcsThingNames[I].DoomNum, Tid));
  FWorld.AcsLogOnce(Format('ThingCount of spawn number %d', [SpawnNum]));
  Result := 0;
end;

function TWorldAcsHost.ThingCountName(const Name: String; const Tid: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AcsThingNames) do
    if SameText(AcsThingNames[I].Name, Name) then
      Exit(FWorld.AcsThingCount(AcsThingNames[I].DoomNum, Tid));
  FWorld.AcsLogOnce(Format('ThingCountName of "%s"', [Name]));
  Result := 0;
end;

procedure TWorldAcsHost.ChangeFlat(const Tag: Integer; const Name: String; const Ceiling: Boolean);
begin
  FWorld.AcsChangeFlat(Tag, Name, Ceiling);
end;

procedure TWorldAcsHost.ClearLineSpecial(const Line: Integer);
begin
  FWorld.AcsClearLineSpecial(Line);
end;

procedure TWorldAcsHost.SetLineTexture(const LineId, Side, Position: Integer; const Name: String);
begin
  FWorld.AcsSetLineTexture(LineId, Side, Position, Name);
end;

procedure TWorldAcsHost.SetLineBlocking(const LineId, Mode: Integer);
begin
  FWorld.AcsSetLineFlag(LineId, ML_BLOCKING, Mode <> 0);
end;

procedure TWorldAcsHost.SetLineMonsterBlocking(const LineId: Integer; const Block: Boolean);
begin
  FWorld.AcsSetLineFlag(LineId, ML_BLOCKMONSTERS, Block);
end;

procedure TWorldAcsHost.SetLineSpecial(const LineId, Special: Integer; const Args: TAcsArgs);
begin
  FWorld.AcsSetLineSpecial(LineId, Special, Args);
end;

procedure TWorldAcsHost.SetMusic(const Name: String);
begin
  WritelnLog('Acs', 'music %s', [UpperCase(Name)]);
  FWorld.MusicRequest := UpperCase(Name);
end;

procedure TWorldAcsHost.PlaySound(const Inst: TAcsInstance; const Name: String; const Volume, Where: Integer);
begin
  FWorld.AcsPlaySound(Name);
end;

function TWorldAcsHost.GameSkill: Integer;
begin
  Result := FWorld.Skill;
end;

function TWorldAcsHost.LevelTime: Integer;
begin
  Result := FWorld.Tic;
end;

function TWorldAcsHost.PlayerHealth: Integer;
begin
  Result := FWorld.Player.Health;
end;

function TWorldAcsHost.PlayerArmor: Integer;
begin
  Result := FWorld.Player.Armor;
end;

function TWorldAcsHost.PlayerHasKey(const Index: Integer): Boolean;
begin
  { PLAYERBLUESKULL, RED, YELLOW, MASTER, then the cards. }
  case Index of
    0: Result := skullBlue in FWorld.Player.Keys;
    1: Result := skullRed in FWorld.Player.Keys;
    2: Result := skullYellow in FWorld.Player.Keys;
    4: Result := keyBlue in FWorld.Player.Keys;
    5: Result := keyRed in FWorld.Player.Keys;
    6: Result := keyYellow in FWorld.Player.Keys;
    else Result := false;
  end;
end;

function TWorldAcsHost.ActorValue(const Inst: TAcsInstance; const Tid, What: Integer): Integer;
begin
  Result := FWorld.AcsActorValue(Inst, Tid, What);
end;

function TWorldAcsHost.SectorValue(const Tag, What: Integer): Integer;
begin
  Result := FWorld.AcsSectorValue(Tag, What);
end;

function TWorldAcsHost.Localize(const Name: String): String;
begin
  Result := FWorld.Text(Name, Name);
end;

function TWorldAcsHost.ThisMap(const N: Integer): Boolean;
begin
  Result := FWorld.AcsThisMap(N);
end;

{ TDoomWorld's side ------------------------------------------------------------- }

function TDoomWorld.AcsRandom(const N: Integer): Integer;
begin
  Result := Random(N);
end;

function TDoomWorld.NewAcsHost: TAcsHost;
begin
  Result := TWorldAcsHost.Create(Self);
end;

procedure TDoomWorld.LoadScripts;
var
  M: TAcsModule;
begin
  FreeAndNil(FAcs);
  if Length(FMap.Behavior) = 0 then Exit;
  M := TAcsModule.Create(FMap.Behavior);
  if M.Error <> '' then
  begin
    WritelnLog('Acs', '%s: BEHAVIOR not loaded: %s', [FMap.Name, M.Error]);
    FreeAndNil(M);
    Exit;
  end;
  FAcs := TAcsVM.Create(M, FAcsHost, FAcsGlobals);
  WritelnLog('Acs', '%s: BEHAVIOR in the %s format: %d scripts, %d functions, %d strings', [
    FMap.Name, M.FormatName, Length(M.Scripts), Length(M.Functions), Length(M.Strings)]);
end;

procedure TDoomWorld.AcsLogOnce(const What: String);
begin
  if FAcsLogged = nil then
  begin
    FAcsLogged := TStringList.Create;
    FAcsLogged.Sorted := true;
  end;
  if FAcsLogged.IndexOf(What) >= 0 then Exit;
  FAcsLogged.Add(What);
  WritelnLog('Acs', '%s not supported, skipped', [What]);
end;

function TDoomWorld.AcsLineSpecial(const Inst: TAcsInstance; const Special: Integer; const Args: TAcsArgs): Integer;
var
  H: THexenLine;
  Line, DestSec, OldSecTag, T: Integer;
  Saved: TDoomLinedef;
  A: TDoomActor;
begin
  Result := 0;
  if Length(FMap.Linedefs) = 0 then Exit;
  H := TranslateHexenLine(Special, Args, UaPlayerCross or UaRepeat);
  if H.Unsupported <> '' then
  begin
    AcsLogOnce('Script action ' + H.Unsupported);
    Exit;
  end;
  if (H.Special = 0) or UdmfAcsSpecial(H.Special) then Exit;
  Line := Inst.Line;
  if (Line < 0) or (Line > High(FMap.Linedefs)) then Line := 0;
  Saved := FMap.Linedefs[Line];
  FMap.Linedefs[Line].Special := H.Special;
  FMap.Linedefs[Line].Tag := H.Tag;
  FMap.Linedefs[Line].Args := H.Args;
  FMap.Linedefs[Line].Trigger := H.Trigger;
  { A teleport to a thing id: the sector its destination stands in,
    tagged for the call when it has no tag. }
  DestSec := -1;
  OldSecTag := 0;
  if (H.Tag = 0) and (H.TeleportTid <> 0) then
    for A in FActors do
      if (A.Info^.Kind = tkTeleportDest) and (A.Tid = H.TeleportTid) and (A.Sector >= 0) then
      begin
        DestSec := A.Sector;
        OldSecTag := FMap.Sectors[DestSec].Tag;
        T := OldSecTag;
        if T = 0 then
        begin
          T := 32000;
          FMap.Sectors[DestSec].Tag := T;
        end;
        FMap.Linedefs[Line].Tag := T;
        Break;
      end;
  WritelnLog('Acs', 'script %d: %s (%d, %d, %d, %d, %d)', [Inst.Number, HexenActionName(Special), Args[0], Args[1],
    Args[2], Args[3], Args[4]]);
  { As a player's action: monsters may only set off doors themselves, a
    script they started may do anything. }
  Result := Ord(ApplySpecial(Line, acCross, false));
  if (Line >= 0) and (Line <= High(FMap.Linedefs)) then
    FMap.Linedefs[Line] := Saved;
  if DestSec >= 0 then
    FMap.Sectors[DestSec].Tag := OldSecTag;
end;

function TDoomWorld.AcsTagBusy(const Tag: Integer): Boolean;
var
  S: Integer;
begin
  S := -1;
  repeat
    S := FMap.FindSectorFromTag(Tag, S);
    if S < 0 then Exit(false);
  until FMap.Sectors[S].Mover <> nil;
  Result := true;
end;

function TDoomWorld.AcsThingCount(const DoomNum, Tid: Integer): Integer;
var
  A: TDoomActor;
begin
  Result := 0;
  for A in FActors do
  begin
    if A.Removed then Continue;
    if (Tid <> 0) and (A.Tid <> Tid) then Continue;
    if (DoomNum <> 0) and (A.Info^.Num <> DoomNum) then Continue;
    if (DoomNum = 0) and (Tid = 0) and (A.Info^.Kind <> tkMonster) then Continue;
    { Monsters count while they live; other things while they are there. }
    if (A.Info^.Kind = tkMonster) and ((A.Health <= 0) or (A.State in [asDying, asDead])) then Continue;
    if not (A.Info^.Kind in [tkMonster, tkDecoration, tkPickup, tkTeleportDest]) then Continue;
    Inc(Result);
  end;
end;

procedure TDoomWorld.AcsChangeFlat(const Tag: Integer; const Name: String; const Ceiling: Boolean);
var
  S: Integer;
begin
  S := -1;
  repeat
    S := FMap.FindSectorFromTag(Tag, S);
    if S < 0 then Break;
    if Ceiling then
      FMap.Sectors[S].CeilingTex := UpperCase(Name)
    else
      FMap.Sectors[S].FloorTex := UpperCase(Name);
    FGeometry.SectorChanged(S);
  until false;
end;

procedure TDoomWorld.AcsClearLineSpecial(const Line: Integer);
begin
  if (Line >= 0) and (Line <= High(FMap.Linedefs)) then
    FMap.Linedefs[Line].Special := 0;
end;

procedure TDoomWorld.AcsSetLineTexture(const LineId, Side, Position: Integer; const Name: String);
var
  L, Sd: Integer;
  Tex: String;
begin
  Tex := UpperCase(Name);
  for L := 0 to High(FMap.Linedefs) do
  begin
    if FMap.Linedefs[L].Id <> LineId then Continue;
    if (Side < 0) or (Side > 1) then Continue;
    Sd := FMap.Linedefs[L].Side[Side];
    if Sd < 0 then Continue;
    case Position of
      0: FMap.Sidedefs[Sd].UpperTex := Tex;
      1: FMap.Sidedefs[Sd].MiddleTex := Tex;
      else FMap.Sidedefs[Sd].LowerTex := Tex;
    end;
    FGeometry.SectorChanged(FMap.Linedefs[L].FrontSector);
    FGeometry.SectorChanged(FMap.Linedefs[L].BackSector);
    WritelnLog('Acs', 'line %d (id %d) side %d texture %d: %s', [L, LineId, Side, Position, Tex]);
  end;
end;

procedure TDoomWorld.AcsSetLineFlag(const LineId, Flag: Integer; const Value: Boolean);
var
  L: Integer;
begin
  for L := 0 to High(FMap.Linedefs) do
    if FMap.Linedefs[L].Id = LineId then
    begin
      if Value then
        FMap.Linedefs[L].Flags := FMap.Linedefs[L].Flags or Flag
      else
        FMap.Linedefs[L].Flags := FMap.Linedefs[L].Flags and not Flag;
    end;
end;

procedure TDoomWorld.AcsSetLineSpecial(const LineId, Special: Integer; const Args: TAcsArgs);
var
  L, Act: Integer;
  H: THexenLine;
begin
  for L := 0 to High(FMap.Linedefs) do
    if FMap.Linedefs[L].Id = LineId then
    begin
      Act := FMap.Linedefs[L].Activation;
      if Act = 0 then Act := UaPlayerUse;
      H := TranslateHexenLine(Special, Args, Act);
      if H.Unsupported <> '' then
        AcsLogOnce('SetLineSpecial ' + H.Unsupported);
      FMap.Linedefs[L].Special := H.Special;
      FMap.Linedefs[L].Tag := H.Tag;
      FMap.Linedefs[L].Args := H.Args;
      FMap.Linedefs[L].Trigger := H.Trigger;
      WritelnLog('Acs', 'line %d (id %d) special %s', [L, LineId, HexenActionName(Special)]);
    end;
end;

procedure TDoomWorld.AcsPlaySound(const Name: String);
var
  Lump: String;
begin
  Lump := UpperCase(Name);
  if (Length(Lump) <= 8) and (FWad.FindLump(Lump) >= 0) then
    FSounds.PlayAt(Lump, FPlayerEmitter)
  else
    AcsLogOnce(Format('Sound "%s"', [Name]));
end;

function TDoomWorld.AcsActorValue(const Inst: TAcsInstance; const Tid, What: Integer): Integer;
var
  X, Y, Z, Angle: Single;
  Sec: Integer;
  A, Found: TDoomActor;
begin
  Found := nil;
  if Tid = 0 then
  begin
    if Inst.Activator <> aaPlayer then Exit(0);
    X := Player.X;
    Y := Player.Y;
    Z := Player.Z;
    Angle := Player.Angle;
    Sec := Player.Sector;
  end else
  begin
    for A in FActors do
      if (A.Tid = Tid) and not A.Removed then
      begin
        Found := A;
        Break;
      end;
    if Found = nil then Exit(0);
    X := Found.DoomX;
    Y := Found.DoomY;
    Z := Found.DoomZ;
    Angle := Found.Angle;
    Sec := Found.Sector;
  end;
  case What of
    0: Result := Round(X * 65536);
    1: Result := Round(Y * 65536);
    2: Result := Round(Z * 65536);
    3: Result := Round(Angle / 360 * 65536) and $FFFF;
    4, 5, 6:
      begin
        if Sec < 0 then Exit(0);
        case What of
          4: Result := Round(FMap.Sectors[Sec].FloorHeight * 65536);
          5: Result := Round(FMap.Sectors[Sec].CeilingHeight * 65536);
          else Result := FMap.Sectors[Sec].LightLevel;
        end;
      end;
    else Result := 0;
  end;
end;

function TDoomWorld.AcsSectorValue(const Tag, What: Integer): Integer;
var
  S: Integer;
begin
  S := FMap.FindSectorFromTag(Tag, -1);
  if S < 0 then Exit(0);
  case What of
    0: Result := Round(FMap.Sectors[S].FloorHeight * 65536);
    1: Result := Round(FMap.Sectors[S].CeilingHeight * 65536);
    else Result := FMap.Sectors[S].LightLevel;
  end;
end;

{ ZDoom's lock numbers: 1..3 the cards, 4..6 the skulls, 129..131 either
  of a colour, 100 any key, 101 all six; 0 none. }
function TDoomWorld.AcsCheckLock(const Line, Lock: Integer): Boolean;
begin
  case Lock of
    0: Result := true;
    1, 4, 129: Result := CheckKey(Line, keyRed, skullRed, false);
    2, 5, 130: Result := CheckKey(Line, keyBlue, skullBlue, false);
    3, 6, 131: Result := CheckKey(Line, keyYellow, skullYellow, false);
    100:
      begin
        Result := Player.Keys <> [];
        if not Result then
        begin
          ShowMessage('You need a key to activate this object');
          FSounds.Play('DSOOF');
        end;
      end;
    101, 229:
      begin
        Result := [keyBlue, keyYellow, keyRed, skullBlue, skullYellow, skullRed] <= Player.Keys;
        if not Result then
        begin
          ShowMessage('You need all six keys to activate this object');
          FSounds.Play('DSOOF');
        end;
      end;
    else
      begin
        AcsLogOnce(Format('Lock %d', [Lock]));
        Result := true;
      end;
  end;
end;

{ ACS_Execute's map argument: 0, or this map's number (MAPxx's xx, ExMy's
  y or ZDoom's (x - 1) * 10 + y). }
function TDoomWorld.AcsThisMap(const N: Integer): Boolean;
var
  Name: String;
  E, M: Integer;
begin
  if N = 0 then Exit(true);
  Name := UpperCase(FMap.Name);
  if (Length(Name) = 5) and (Copy(Name, 1, 3) = 'MAP') and TryStrToInt(Copy(Name, 4, 2), M) then
    Exit(M = N);
  if (Length(Name) = 4) and (Name[1] = 'E') and (Name[3] = 'M') and TryStrToInt(Name[2], E) and
     TryStrToInt(Name[4], M) then
    Exit((N = M) or (N = (E - 1) * 10 + M));
  Result := false;
end;

{ A line with one of DoomUdmf's UdmfAcs* types, set off. }
function TDoomWorld.AcsLineAction(const Line: Integer; const ByMonster: Boolean): Boolean;
var
  L: TDoomLinedef;
  Act: TAcsActivator;
  Inst: TAcsInstance;
begin
  Result := false;
  L := FMap.Linedefs[Line];
  if FAcs = nil then
  begin
    AcsLogOnce('ACS line without a BEHAVIOR lump');
    Exit;
  end;
  if ByMonster then Act := aaMonster else Act := aaPlayer;
  if (L.Special <> UdmfAcsExecuteWithResult) and not AcsThisMap(L.Args[1]) then
  begin
    AcsLogOnce('ACS line for another map');
    Exit;
  end;
  case L.Special of
    UdmfAcsExecute, UdmfAcsExecuteAlways, UdmfAcsLockedExecute:
      begin
        if (L.Special = UdmfAcsLockedExecute) and not AcsCheckLock(Line, L.Args[4]) then Exit;
        if L.Special = UdmfAcsLockedExecute then
          Inst := FAcs.StartScript(L.Args[0], [L.Args[2], L.Args[3]], Act, Line, FActivationSide = 1, false)
        else
          Inst := FAcs.StartScript(L.Args[0], [L.Args[2], L.Args[3], L.Args[4]], Act, Line, FActivationSide = 1,
            L.Special = UdmfAcsExecuteAlways);
        Result := Inst <> nil;
      end;
    UdmfAcsExecuteWithResult:
      Result := FAcs.StartScript(L.Args[0], [L.Args[1], L.Args[2], L.Args[3], L.Args[4]], Act, Line,
        FActivationSide = 1, true) <> nil;
    UdmfAcsTerminate:
      begin
        FAcs.TerminateScript(L.Args[0]);
        Result := true;
      end;
    UdmfAcsSuspend:
      begin
        FAcs.SuspendScript(L.Args[0]);
        Result := true;
      end;
  end;
  if Result then
    WritelnLog('Acs', 'line %d: %s %d', [Line, UdmfSpecialName(L.Special), L.Args[0]]);
end;

{ Sectors scripts can move or re-texture (their constant calls), for
  ComputeDynamicSectors. }
procedure TDoomWorld.AcsMarkDynamic;
var
  Calls: TAcsConstCalls;
  C: TAcsConstCall;
  H: THexenLine;
  L: Integer;

  procedure MarkTag(const T: Integer);
  var
    J: Integer;
  begin
    if T = 0 then Exit;
    for J := 0 to High(FMap.Sectors) do
      if FMap.Sectors[J].Tag = T then
        FDynamic[J] := true;
  end;

begin
  if FAcs = nil then Exit;
  Calls := FAcs.Module.ConstCalls;
  for C in Calls do
    case C.Special of
      AcsCallChangeFloor, AcsCallChangeCeiling: MarkTag(C.Args[0]);
      AcsCallSetLineTexture:
        for L := 0 to High(FMap.Linedefs) do
          if FMap.Linedefs[L].Id = C.Args[0] then
          begin
            if FMap.Linedefs[L].FrontSector >= 0 then FDynamic[FMap.Linedefs[L].FrontSector] := true;
            if FMap.Linedefs[L].BackSector >= 0 then FDynamic[FMap.Linedefs[L].BackSector] := true;
          end;
      else
        begin
          H := TranslateHexenLine(C.Special, C.Args, UaPlayerCross or UaRepeat);
          if (H.Special <> 0) and not UdmfAcsSpecial(H.Special) then
            MarkTag(H.Tag);
        end;
    end;
  WritelnLog('Acs', '%s: %d constant line specials in the scripts', [FMap.Name, Length(Calls)]);
end;
