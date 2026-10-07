{ The Doom game world on top of the map geometry: things, sector movers
  (doors, lifts, floors, ceilings, stairs), linedef specials (switches,
  walk-over triggers, teleports, exits), pickups, monster AI, projectiles,
  player weapons and damage.

  Everything runs at Doom's 35 tics per second, driven from the view's Update.
  Positions are kept in Doom units/coordinates; the CGE transforms are
  updated from them. }
unit DoomWorld;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleVectors, CastleTransform, CastleScene, CastleUtils,
  DoomWad, DoomGraphics, DoomMap, DoomGeometry, DoomThings, DoomActors, DoomSound;

const
  TicRate = 35;
  TicSeconds = 1 / TicRate;
  PlayerRadius = 16;
  PlayerHeight = 56;
  PlayerViewHeight = 41;

type
  TAmmoType = (amClip, amShell, amCell, amMisl, amNoAmmo);
  TWeapon = (wpFist, wpPistol, wpShotgun, wpChaingun, wpMissile, wpPlasma, wpBfg, wpChainsaw, wpSuperShotgun);
  TWeapons = set of TWeapon;
  TDoomKey = (keyBlue, keyYellow, keyRed, skullBlue, skullYellow, skullRed);
  TKeys = set of TDoomKey;

  TPlayerState = record
    Health, Armor, ArmorType: Integer;
    Ammo, MaxAmmo: array [TAmmoType] of Integer;
    Weapons: TWeapons;
    Weapon: TWeapon;
    Keys: TKeys;
    Dead: Boolean;
    Message: String;
    MessageTics: Integer;
    { 0..1, red/yellow screen flashes for the view. }
    DamageFlash, BonusFlash: Single;
    Kills, Items, Secrets: Integer;
    TotalKills, TotalItems, TotalSecrets: Integer;
    BerserkTics, InvulnerableTics, InvisibleTics, RadSuitTics, LightAmpTics: Integer;
    { Feet position and facing (Doom coordinates / degrees). }
    X, Y, Z: Single;
    Angle: Single;
    Sector: Integer;
    { Weapon animation. }
    AttackTics: Integer;
    WeaponFrame: Char;
    FlashFrame: Char;
    Refire: Boolean;
    { Status bar face: tics left for the "ouch" / "evil grin" expressions. }
    FaceTics: Integer;
    FaceState: Integer;
  end;

  TDoomWorld = class;

  TMoverKind = (mkDoor, mkLift, mkFloor, mkCeiling, mkCrusher);
  TMoverPhase = (mpMoving, mpWaiting, mpDone);

  TSectorMover = class
  public
    World: TDoomWorld;
    Sector: Integer;
    Kind: TMoverKind;
    MovesCeiling: Boolean;
    Target: Single;
    Speed: Single; { units per tic }
    Direction: Integer;
    WaitTics: Integer; { how long to wait at Target before returning }
    WaitLeft: Integer;
    HasReturn: Boolean;
    ReturnTarget: Single;
    Perpetual: Boolean;
    Phase: TMoverPhase;
    StartSound, StopSound, MoveSound: String;
    Emitter: TCastleTransform;
    { Floor texture to apply when done (numeric/trigger change types). }
    NewFloorTex: String;
    constructor Create(const AWorld: TDoomWorld; const ASector: Integer; const AKind: TMoverKind);
    destructor Destroy; override;
    procedure Start;
    procedure Tic;
    function Height: Single;
    procedure SetHeight(const H: Single);
  end;
  TSectorMoverList = {$ifdef FPC}specialize{$endif} TObjectList<TSectorMover>;

  TButtonTimer = record
    Line: Integer;
    TicsLeft: Integer;
  end;

  TActivation = (acUse, acCross, acShoot);

  TDoomWorld = class
  strict private
    FWad: TDoomWad;
    FGraphics: TDoomGraphics;
    FSounds: TDoomSounds;
    FMap: TDoomMap;
    FGeometry: TDoomGeometry;
    FItems: TCastleRootTransform;
    FActors: TDoomActorList;
    FMovers: TSectorMoverList;
    FButtons: array of TButtonTimer;
    FTic: Int64;
    FTicAccum: Single;
    FExitRequested: Boolean;
    FSecretExit: Boolean;
    FLightSectors: array of Integer;
    FLightTimers: array of Integer;
    FLightPhase: array of Integer;
    FPlayerEmitter: TCastleTransform;
    FOldPlayerX, FOldPlayerY: Single;
    FRayOrigin, FRayDir: TVector3;
    FHaveRay: Boolean;
    FDoomStartX, FDoomStartY, FDoomStartAngle: Single;
    FHaveStart: Boolean;
    FDynamic: array of Boolean;
    procedure ComputeDynamicSectors;
    procedure SpawnThings;
    procedure RunTic;
    procedure TicActors;
    procedure TicMonster(const A: TDoomActor);
    procedure TicMissile(const A: TDoomActor);
    procedure TicMovers;
    procedure TicLights;
    procedure TicPlayer;
    procedure TicButtons;
    procedure CheckPickups;
    procedure CheckCrossings;
    function TryMove2D(const A: TDoomActor; const NX, NY: Single; out BlockedByLine: Integer): Boolean;
    function LineBlocksMissile(const Line: Integer; const X, Y, Z: Single): Boolean;
    function SightClear(const X1, Y1, X2, Y2: Single): Boolean;
    procedure MonsterAttack(const A: TDoomActor);
    procedure MonsterHitscan(const A: TDoomActor);
    procedure SpawnMissile(const A: TDoomActor);
    procedure KillActor(const A: TDoomActor);
    procedure ExplodeBarrel(const A: TDoomActor);
    procedure RadiusDamage(const X, Y, Z: Single; const Radius, Damage: Integer; const Source: TDoomActor);
    procedure HitscanAttack(const Origin, Dir: TVector3; const Damage: Integer; const Splash: Integer);
    function RayHit(const Origin, Dir: TVector3; out HitPoint: TVector3; out Actor: TDoomActor; out Dist: Single): Boolean;
    procedure UpdateWeaponAnimation;
    function Random1(const N: Integer): Integer;
    function Dice(const Count, Faces: Integer): Integer;
    procedure NoiseAlert;
    { Specials }
    function UseSpecialLine(const Line, Side: Integer; const ByMonster: Boolean): Boolean;
    function CrossSpecialLine(const Line, Side: Integer): Boolean;
    function ShootSpecialLine(const Line: Integer): Boolean;
    function ApplySpecial(const Line: Integer; const Activation: TActivation; const ByMonster: Boolean): Boolean;
    procedure DoDoor(const Sec: Integer; const Open, Close, Blaze: Boolean; const WaitTics: Integer);
    procedure DoLift(const Sec: Integer; const Blaze: Boolean; const Perpetual: Boolean);
    procedure DoFloor(const Sec: Integer; const Target: Single; const Speed: Single; const ChangeTexFrom: Integer = -1);
    procedure DoCeiling(const Sec: Integer; const Target: Single; const Speed: Single; const Crusher: Boolean);
    procedure DoStairs(const Line: Integer; const StepSize: Integer; const Speed: Single);
    procedure DoLight(const Sec: Integer; const Level: Integer);
    procedure DoTeleport(const Line: Integer);
    procedure StopPlats(const Tag: Integer);
    function CheckKey(const Line: Integer; const Key: TDoomKey; const Skull: TDoomKey; const IsDoor: Boolean): Boolean;
    procedure ChangeLineButton(const Line: Integer; const Repeatable: Boolean);
  public
    Player: TPlayerState;
    { Set when the player should be moved by the view (teleport / spawn). }
    PlayerTeleported: Boolean;
    PlayerTeleportX, PlayerTeleportY, PlayerTeleportZ, PlayerTeleportAngle: Single;
    { Set when the player just took damage (view shakes/flashes). }
    LastDamage: Integer;

    constructor Create(const AWad: TDoomWad; const AGraphics: TDoomGraphics;
      const ASounds: TDoomSounds; const AItems: TCastleRootTransform);
    destructor Destroy; override;

    procedure LoadMap(const MapName: String; const KeepInventory: Boolean);
    procedure UnloadMap;
    function MapLoaded: Boolean;

    { Call every frame from the view. PlayerFeet in Doom coordinates. }
    procedure Update(const SecondsPassed: Single; const PlayerFeetX, PlayerFeetY, PlayerFeetZ: Single;
      const PlayerAngleDeg: Single; const CameraPos, CameraDir: TVector3);
    { The player presses "use" (open doors, switches). }
    procedure UseInFront;
    { The player fires the current weapon. }
    procedure FireWeapon;
    procedure SelectWeapon(const W: TWeapon);
    procedure NextWeapon(const Delta: Integer);
    procedure ShowMessage(const Msg: String);
    procedure DamagePlayer(const Damage: Integer; const FromActor: TDoomActor);
    procedure DamageActor(const A: TDoomActor; const Damage: Integer; const HitX, HitY, HitZ: Single);
    procedure ResetPlayer;
    function AmmoFor(const W: TWeapon): TAmmoType;
    function WeaponSprite(const W: TWeapon): String;
    function FlashSprite(const W: TWeapon): String;

    property Map: TDoomMap read FMap;
    property Geometry: TDoomGeometry read FGeometry;
    property Graphics: TDoomGraphics read FGraphics;
    property Sounds: TDoomSounds read FSounds;
    property Actors: TDoomActorList read FActors;
    property Tic: Int64 read FTic;
    property ExitRequested: Boolean read FExitRequested write FExitRequested;
    property SecretExit: Boolean read FSecretExit;
    property StartX: Single read FDoomStartX;
    property StartY: Single read FDoomStartY;
    property StartAngle: Single read FDoomStartAngle;
    property Items: TCastleRootTransform read FItems;
  end;

{ Next map after Current (Doom 1 / Doom 2 progression, with secret levels). }
function NextMapName(const Current: String; const Secret: Boolean; const IsDoom2: Boolean): String;

implementation

uses Math, CastleLog, CastleStringUtils, CastleBehaviors;

const
  DoorSpeed = 2;
  DoorWait = 150;
  PlatSpeed = 4;
  PlatWait = 105;
  FloorSpeed = 1;
  CeilSpeed = 1;
  ManualDoorSpecials: array [0..9] of Integer = (1, 26, 27, 28, 31, 32, 33, 34, 117, 118);

type
  TEffectKind = (ekPuff, ekBlood, ekTeleFog, ekBarrelExplosion,
    ekBal1, ekBal2, ekBal7, ekRocket, ekRevenantRocket, ekFatShot, ekArachPlasma);

var
  EffectInfos: array [TEffectKind] of TThingInfo;

procedure InitEffectInfos;

  procedure Effect(const K: TEffectKind; const Sprite, Frames: String; const Tics: Integer);
  begin
    EffectInfos[K] := Default(TThingInfo);
    EffectInfos[K].Num := -1;
    EffectInfos[K].Sprite := Sprite;
    EffectInfos[K].Kind := tkNone;
    EffectInfos[K].Radius := 1;
    EffectInfos[K].Height := 1;
    EffectInfos[K].IdleFrames := Frames;
    EffectInfos[K].IdleTics := Tics;
    EffectInfos[K].PainFrame := #0;
  end;

  procedure Missile(const K: TEffectKind; const Sprite: String; const Radius, Speed, Dice, Faces: Integer;
    const Fly, Death: String; const DeathSprite: String; const LaunchSnd, HitSnd: String);
  begin
    Effect(K, Sprite, Fly, 4);
    EffectInfos[K].Radius := Radius;
    EffectInfos[K].Height := 8;
    EffectInfos[K].Speed := Speed;
    EffectInfos[K].DamageDice := Dice;
    EffectInfos[K].DamageFaces := Faces;
    EffectInfos[K].DeathFrames := Death;
    EffectInfos[K].AttackSound := LaunchSnd;
    EffectInfos[K].DeathSound := HitSnd;
    { MoveFrames stores the explosion sprite name (may differ from flight sprite). }
    EffectInfos[K].MoveFrames := DeathSprite;
  end;

begin
  Effect(ekPuff, 'PUFF', 'ABCD', 4);
  Effect(ekBlood, 'BLUD', 'CBA', 8);
  Effect(ekTeleFog, 'TFOG', 'ABABCDEFGHIJ', 6);
  Effect(ekBarrelExplosion, 'BEXP', 'ABCDE', 6);
  Missile(ekBal1, 'BAL1', 6, 10, 3, 8, 'AB', 'CDE', 'BAL1', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekBal2, 'BAL2', 6, 10, 5, 8, 'AB', 'CDE', 'BAL2', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekBal7, 'BAL7', 6, 15, 8, 8, 'AB', 'CDE', 'BAL7', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekRocket, 'MISL', 11, 20, 20, 8, 'A', 'BCD', 'MISL', 'DSRLAUNC', 'DSBAREXP');
  Missile(ekRevenantRocket, 'FATB', 11, 10, 10, 8, 'AB', 'ABC', 'FBXP', 'DSSKEATK', 'DSBAREXP');
  Missile(ekFatShot, 'MANF', 6, 20, 8, 8, 'AB', 'BCD', 'MISL', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekArachPlasma, 'APLS', 13, 25, 5, 8, 'AB', 'ABCDE', 'APBX', 'DSPLASMA', 'DSFIRXPL');
end;

function NextMapName(const Current: String; const Secret: Boolean; const IsDoom2: Boolean): String;
var
  E, M, N: Integer;
begin
  if IsDoom2 then
  begin
    N := StrToIntDef(Copy(Current, 4, 2), 1);
    if Secret then
    begin
      if N = 31 then N := 32 else N := 31;
    end else
    begin
      if (N = 31) or (N = 32) then N := 16
      else if N >= 30 then N := 1
      else Inc(N);
    end;
    Result := Format('MAP%2.2d', [N]);
  end else
  begin
    E := StrToIntDef(Copy(Current, 2, 1), 1);
    M := StrToIntDef(Copy(Current, 4, 1), 1);
    if Secret then
      M := 9
    else if M = 9 then
    begin
      case E of
        1: M := 4;
        2: M := 6;
        3: M := 7;
        else M := 3;
      end;
    end else if M >= 8 then
    begin
      Inc(E);
      M := 1;
      if E > 4 then E := 1;
    end else
      Inc(M);
    Result := Format('E%dM%d', [E, M]);
  end;
end;

function MoveFrameTics(const Num: Integer): Integer;
begin
  case Num of
    3004: Result := 4;
    3002, 58, 64, 66: Result := 2;
    67: Result := 4;
    3006: Result := 6;
    else Result := 3;
  end;
end;

function SegmentsIntersect(const AX, AY, BX, BY, CX, CY, DX, DY: Single; out T: Single): Boolean;
var
  D, U: Single;
begin
  Result := false;
  T := 0;
  D := (BX - AX) * (DY - CY) - (BY - AY) * (DX - CX);
  if Abs(D) < 1e-6 then Exit;
  T := ((CX - AX) * (DY - CY) - (CY - AY) * (DX - CX)) / D;
  U := ((CX - AX) * (BY - AY) - (CY - AY) * (BX - AX)) / D;
  Result := (T >= 0) and (T <= 1) and (U >= 0) and (U <= 1);
end;

{ TSectorMover --------------------------------------------------------------- }

constructor TSectorMover.Create(const AWorld: TDoomWorld; const ASector: Integer; const AKind: TMoverKind);
var
  Sub: Integer;
  CX, CY: Single;
  N, I: Integer;
begin
  inherited Create;
  World := AWorld;
  Sector := ASector;
  Kind := AKind;
  Direction := 0;
  Phase := mpMoving;
  { A sound emitter in the middle of the sector. }
  Emitter := TCastleTransform.Create(nil);
  CX := 0; CY := 0; N := 0;
  for Sub in World.Map.Sectors[Sector].Subsectors do
    for I := 0 to High(World.Map.Subsectors[Sub].Poly) do
    begin
      CX := CX + World.Map.Subsectors[Sub].Poly[I].X;
      CY := CY + World.Map.Subsectors[Sub].Poly[I].Y;
      Inc(N);
    end;
  if N > 0 then
  begin
    CX := CX / N;
    CY := CY / N;
  end;
  Emitter.Translation := DoomToCge(CX, CY,
    (World.Map.Sectors[Sector].FloorHeight + World.Map.Sectors[Sector].CeilingHeight) / 2);
  World.Items.Add(Emitter);
end;

destructor TSectorMover.Destroy;
begin
  if (World <> nil) and (World.Map <> nil) and (Sector >= 0) and (Sector <= High(World.Map.Sectors)) and
     (World.Map.Sectors[Sector].Mover = Self) then
    World.Map.Sectors[Sector].Mover := nil;
  FreeAndNil(Emitter);
  inherited;
end;

function TSectorMover.Height: Single;
begin
  if MovesCeiling then
    Result := World.Map.Sectors[Sector].CeilingHeight
  else
    Result := World.Map.Sectors[Sector].FloorHeight;
end;

procedure TSectorMover.SetHeight(const H: Single);
begin
  if MovesCeiling then
    World.Map.Sectors[Sector].CeilingHeight := H
  else
    World.Map.Sectors[Sector].FloorHeight := H;
  World.Geometry.SectorChanged(Sector);
end;

procedure TSectorMover.Start;
begin
  World.Map.Sectors[Sector].Mover := Self;
  if Target > Height then Direction := 1
  else if Target < Height then Direction := -1
  else Direction := 0;
  if StartSound <> '' then
    World.Sounds.PlayAt(StartSound, Emitter);
end;

procedure TSectorMover.Tic;
var
  H, NewH, Limit: Single;
  A: TDoomActor;
  Blocked: Boolean;
begin
  case Phase of
    mpMoving:
      begin
        H := Height;
        NewH := H + Direction * Speed;
        if ((Direction > 0) and (NewH >= Target)) or ((Direction < 0) and (NewH <= Target)) or (Direction = 0) then
          NewH := Target;

        { A ceiling coming down on something: doors go back up, crushers hurt. }
        if MovesCeiling and (Direction < 0) then
        begin
          Blocked := false;
          Limit := World.Map.Sectors[Sector].FloorHeight;
          if (World.Player.Sector = Sector) and not World.Player.Dead then
            if NewH < World.Player.Z + PlayerHeight then
            begin
              Blocked := true;
              if Kind = mkCrusher then
                World.DamagePlayer(10, nil);
            end;
          for A in World.Actors do
            if (A.Sector = Sector) and (A.Info^.Kind = tkMonster) and (A.State <> asDead) and
               (NewH < A.DoomZ + A.Info^.Height) then
            begin
              Blocked := true;
              if Kind = mkCrusher then
                World.DamageActor(A, 10, A.DoomX, A.DoomY, A.DoomZ + 32);
            end;
          if Blocked and (Kind = mkDoor) then
          begin
            { Reverse: reopen. }
            Direction := 1;
            if HasReturn then Target := ReturnTarget;
            HasReturn := true;
            ReturnTarget := Limit;
            Exit;
          end;
          if Blocked and (Kind <> mkCrusher) then
            Exit;
        end;

        SetHeight(NewH);
        if (MoveSound <> '') and (World.Tic mod 8 = 0) then
          World.Sounds.PlayAt(MoveSound, Emitter);

        if NewH = Target then
        begin
          if HasReturn or Perpetual then
          begin
            Phase := mpWaiting;
            WaitLeft := WaitTics;
            if (Kind = mkLift) and (StopSound <> '') then
              World.Sounds.PlayAt(StopSound, Emitter);
          end else
          begin
            Phase := mpDone;
            if StopSound <> '' then
              World.Sounds.PlayAt(StopSound, Emitter);
            if NewFloorTex <> '' then
            begin
              World.Map.Sectors[Sector].FloorTex := NewFloorTex;
              World.Geometry.SectorChanged(Sector);
            end;
          end;
        end;
      end;
    mpWaiting:
      begin
        Dec(WaitLeft);
        if WaitLeft <= 0 then
        begin
          if Perpetual then
          begin
            H := Target;
            Target := ReturnTarget;
            ReturnTarget := H;
          end else
          begin
            Target := ReturnTarget;
            HasReturn := false;
          end;
          Phase := mpMoving;
          if Target > Height then Direction := 1 else Direction := -1;
          if StartSound <> '' then
            World.Sounds.PlayAt(StartSound, Emitter);
        end;
      end;
    mpDone: ;
  end;
end;

{ TDoomWorld ----------------------------------------------------------------- }

constructor TDoomWorld.Create(const AWad: TDoomWad; const AGraphics: TDoomGraphics;
  const ASounds: TDoomSounds; const AItems: TCastleRootTransform);
begin
  inherited Create;
  FWad := AWad;
  FGraphics := AGraphics;
  FSounds := ASounds;
  FItems := AItems;
  FActors := TDoomActorList.Create(true);
  FMovers := TSectorMoverList.Create(true);
  FPlayerEmitter := TCastleTransform.Create(nil);
  ResetPlayer;
end;

destructor TDoomWorld.Destroy;
begin
  UnloadMap;
  FreeAndNil(FPlayerEmitter);
  FreeAndNil(FMovers);
  FreeAndNil(FActors);
  inherited;
end;

procedure TDoomWorld.ResetPlayer;
var
  A: TAmmoType;
begin
  Player := Default(TPlayerState);
  Player.Health := 100;
  Player.Weapons := [wpFist, wpPistol];
  Player.Weapon := wpPistol;
  for A := Low(TAmmoType) to High(TAmmoType) do Player.Ammo[A] := 0;
  Player.MaxAmmo[amClip] := 200;
  Player.MaxAmmo[amShell] := 50;
  Player.MaxAmmo[amCell] := 300;
  Player.MaxAmmo[amMisl] := 50;
  Player.Ammo[amClip] := 50;
  Player.WeaponFrame := 'A';
  Player.FlashFrame := #0;
end;

function TDoomWorld.MapLoaded: Boolean;
begin
  Result := FMap <> nil;
end;

procedure TDoomWorld.UnloadMap;
var
  A: TDoomActor;
begin
  FMovers.Clear;
  for A in FActors do
    if A.Parent <> nil then
      A.Parent.Remove(A);
  FActors.Clear;
  if FPlayerEmitter.Parent <> nil then
    FPlayerEmitter.Parent.Remove(FPlayerEmitter);
  FreeAndNil(FGeometry);
  FreeAndNil(FMap);
  SetLength(FButtons, 0);
  SetLength(FLightSectors, 0);
end;

procedure TDoomWorld.ComputeDynamicSectors;
var
  I, S, Sec, Back, Next, L, Guard: Integer;
  Special, Tag: Integer;
  IsManualDoor: Boolean;
  M: Integer;

  procedure MarkTag(const T: Integer);
  var
    J: Integer;
  begin
    if T = 0 then Exit;
    for J := 0 to High(FMap.Sectors) do
      if FMap.Sectors[J].Tag = T then
        FDynamic[J] := true;
  end;

  procedure MarkNeighbours(const Sec: Integer);
  var
    LL, O: Integer;
  begin
    for LL in FMap.Sectors[Sec].Lines do
    begin
      O := FMap.OtherSector(LL, Sec);
      if O >= 0 then FDynamic[O] := true;
    end;
  end;

begin
  SetLength(FDynamic, Length(FMap.Sectors));
  for I := 0 to High(FDynamic) do
    FDynamic[I] := FMap.Sectors[I].Special in [1, 2, 3, 4, 8, 12, 13, 17];
  for I := 0 to High(FMap.Linedefs) do
  begin
    Special := FMap.Linedefs[I].Special;
    Tag := FMap.Linedefs[I].Tag;
    if Special = 0 then Continue;
    IsManualDoor := false;
    for M := 0 to High(ManualDoorSpecials) do
      if ManualDoorSpecials[M] = Special then IsManualDoor := true;
    if IsManualDoor then
    begin
      Back := FMap.Linedefs[I].BackSector;
      if Back >= 0 then FDynamic[Back] := true;
      Continue;
    end;
    if Special in [11, 51, 52, 124, 48, 39, 97, 125, 126] then Continue;
    MarkTag(Tag);
    { Stairs climb through neighbours sharing the floor texture. }
    if Special in [7, 8, 100, 127] then
    begin
      S := -1;
      repeat
        S := FMap.FindSectorFromTag(Tag, S);
        if S < 0 then Break;
        Sec := S;
        Guard := 0;
        repeat
          Next := -1;
          for L in FMap.Sectors[Sec].Lines do
            if ((FMap.Linedefs[L].Flags and ML_TWOSIDED) <> 0) and (FMap.Linedefs[L].FrontSector = Sec) then
            begin
              Back := FMap.Linedefs[L].BackSector;
              if (Back >= 0) and (FMap.Sectors[Back].FloorTex = FMap.Sectors[S].FloorTex) and not FDynamic[Back] then
              begin
                Next := Back;
                Break;
              end;
            end;
          if Next >= 0 then
          begin
            FDynamic[Next] := true;
            Sec := Next;
          end;
          Inc(Guard);
        until (Next < 0) or (Guard > 200);
      until false;
    end;
    { Donut: the tagged sector, its neighbour and the neighbour's neighbours. }
    if Special = 9 then
    begin
      S := -1;
      repeat
        S := FMap.FindSectorFromTag(Tag, S);
        if S < 0 then Break;
        MarkNeighbours(S);
        for L in FMap.Sectors[S].Lines do
        begin
          Back := FMap.OtherSector(L, S);
          if Back >= 0 then MarkNeighbours(Back);
        end;
      until false;
    end;
  end;
end;

procedure TDoomWorld.SpawnThings;
var
  I, N: Integer;
  T: TDoomThing;
  Info: PThingInfo;
  A: TDoomActor;
  Sec: Integer;
begin
  FHaveStart := false;
  N := 0;
  Player.TotalKills := 0;
  Player.TotalItems := 0;
  Player.TotalSecrets := 0;
  for I := 0 to High(FMap.Sectors) do
    if FMap.Sectors[I].Special = 9 then Inc(Player.TotalSecrets);
  for I := 0 to High(FMap.Things) do
  begin
    T := FMap.Things[I];
    if (T.Flags and MTF_NOTSINGLE) <> 0 then Continue;
    { Skill "hurt me plenty". }
    if (T.Flags and MTF_NORMAL) = 0 then Continue;
    Info := FindThingInfo(T.TypeNum);
    if Info = nil then
    begin
      WritelnWarning('Things', 'Unknown thing type %d at (%f, %f)', [T.TypeNum, T.X, T.Y]);
      Continue;
    end;
    if Info^.Kind = tkPlayerStart then
    begin
      if (T.TypeNum = 1) and not FHaveStart then
      begin
        FDoomStartX := T.X;
        FDoomStartY := T.Y;
        FDoomStartAngle := T.Angle;
        FHaveStart := true;
      end;
      Continue;
    end;
    if Info^.Kind = tkInvisible then Continue;
    Sec := FMap.SectorAt(T.X, T.Y);
    if Sec < 0 then Continue;
    A := TDoomActor.Create(nil, FGraphics, Info);
    A.DoomX := T.X;
    A.DoomY := T.Y;
    A.Angle := T.Angle;
    A.Sector := Sec;
    A.MapFlags := T.Flags;
    if Info^.Hanging then
      A.DoomZ := FMap.Sectors[Sec].CeilingHeight - Info^.Height
    else
      A.DoomZ := FMap.Sectors[Sec].FloorHeight;
    if Info^.Kind = tkTeleportDest then
      A.Scene.Exists := false;
    if Info^.Num = 2035 then
      A.Health := 20; { barrel }
    A.Bright := Info^.Pickup in [pkSoulsphere, pkMegasphere, pkInvulnerability, pkInvisibility, pkBerserk, pkRadSuit, pkComputerMap, pkLightAmp];
    A.SetLight(FMap.Sectors[Sec].LightLevel);
    A.UpdateTransform;
    FActors.Add(A);
    FItems.Add(A);
    if Info^.Kind = tkMonster then Inc(Player.TotalKills);
    if (Info^.Kind = tkPickup) and (Info^.Pickup in [pkStimpack, pkMedikit, pkHealthBonus, pkArmorBonus,
      pkArmorGreen, pkArmorBlue, pkSoulsphere, pkMegasphere, pkBerserk, pkInvulnerability, pkInvisibility,
      pkRadSuit, pkComputerMap, pkLightAmp]) then Inc(Player.TotalItems);
    Inc(N);
  end;
  WritelnLog('Things', '%d things spawned, %d monsters', [N, Player.TotalKills]);
end;

procedure TDoomWorld.LoadMap(const MapName: String; const KeepInventory: Boolean);
var
  I: Integer;
  Saved: TPlayerState;
  T0: TDateTime;

  function Ms: Integer;
  begin
    Result := Round((Now - T0) * 24 * 3600 * 1000);
  end;

begin
  UnloadMap;
  Saved := Player;
  T0 := Now;
  FMap := TDoomMap.Create(FWad, MapName);
  ComputeDynamicSectors;
  WritelnLog('Load', '%s: map parsed in %d ms', [MapName, Ms]);
  FGeometry := TDoomGeometry.Create(FMap, FGraphics, FDynamic, FGraphics.SkyTextureName(MapName));
  FGeometry.AddToWorld(FItems);
  WritelnLog('Load', '%s: geometry built in %d ms', [MapName, Ms]);
  FItems.Add(FPlayerEmitter);
  if KeepInventory and not Saved.Dead then
  begin
    ResetPlayer;
    Player.Health := Saved.Health;
    Player.Armor := Saved.Armor;
    Player.ArmorType := Saved.ArmorType;
    Player.Ammo := Saved.Ammo;
    Player.MaxAmmo := Saved.MaxAmmo;
    Player.Weapons := Saved.Weapons;
    Player.Weapon := Saved.Weapon;
  end else
    ResetPlayer;
  Player.Keys := [];
  SpawnThings;
  WritelnLog('Load', '%s: things spawned in %d ms', [MapName, Ms]);
  if not FHaveStart then
  begin
    FDoomStartX := FMap.Vertices[0].X;
    FDoomStartY := FMap.Vertices[0].Y;
    FDoomStartAngle := 0;
  end;
  Player.X := FDoomStartX;
  Player.Y := FDoomStartY;
  Player.Angle := FDoomStartAngle;
  Player.Sector := FMap.SectorAt(Player.X, Player.Y);
  if Player.Sector >= 0 then
    Player.Z := FMap.Sectors[Player.Sector].FloorHeight;
  FOldPlayerX := Player.X;
  FOldPlayerY := Player.Y;
  FExitRequested := false;
  FSecretExit := false;
  FTic := 0;
  FTicAccum := 0;
  { Light effect sectors. }
  SetLength(FLightSectors, 0);
  for I := 0 to High(FMap.Sectors) do
    if FMap.Sectors[I].Special in [1, 2, 3, 4, 8, 12, 13, 17] then
    begin
      SetLength(FLightSectors, Length(FLightSectors) + 1);
      FLightSectors[High(FLightSectors)] := I;
    end;
  SetLength(FLightTimers, Length(FLightSectors));
  SetLength(FLightPhase, Length(FLightSectors));
  for I := 0 to High(FLightTimers) do
  begin
    FLightTimers[I] := Random1(8);
    FLightPhase[I] := 0;
  end;
  PlayerTeleported := false;
end;

function TDoomWorld.Random1(const N: Integer): Integer;
begin
  if N <= 1 then Exit(1);
  Result := Random(N) + 1;
end;

function TDoomWorld.Dice(const Count, Faces: Integer): Integer;
begin
  Result := Count * Random1(Faces);
end;

procedure TDoomWorld.ShowMessage(const Msg: String);
begin
  Player.Message := Msg;
  Player.MessageTics := 4 * TicRate;
end;

function TDoomWorld.AmmoFor(const W: TWeapon): TAmmoType;
begin
  case W of
    wpPistol, wpChaingun: Result := amClip;
    wpShotgun, wpSuperShotgun: Result := amShell;
    wpPlasma, wpBfg: Result := amCell;
    wpMissile: Result := amMisl;
    else Result := amNoAmmo;
  end;
end;

function TDoomWorld.WeaponSprite(const W: TWeapon): String;
begin
  case W of
    wpFist: Result := 'PUNG';
    wpPistol: Result := 'PISG';
    wpShotgun: Result := 'SHTG';
    wpChaingun: Result := 'CHGG';
    wpMissile: Result := 'MISG';
    wpPlasma: Result := 'PLSG';
    wpBfg: Result := 'BFGG';
    wpChainsaw: Result := 'SAWG';
    wpSuperShotgun: Result := 'SHT2';
    else Result := 'PISG';
  end;
end;

function TDoomWorld.FlashSprite(const W: TWeapon): String;
begin
  case W of
    wpPistol: Result := 'PISF';
    wpShotgun: Result := 'SHTF';
    wpChaingun: Result := 'CHGF';
    wpMissile: Result := 'MISF';
    wpPlasma: Result := 'PLSF';
    wpBfg: Result := 'BFGF';
    wpSuperShotgun: Result := 'SHT2';
    else Result := '';
  end;
end;

procedure TDoomWorld.SelectWeapon(const W: TWeapon);
begin
  if not (W in Player.Weapons) then Exit;
  if (AmmoFor(W) <> amNoAmmo) and (Player.Ammo[AmmoFor(W)] <= 0) and (W <> Player.Weapon) then
  begin
    ShowMessage('No ammo for that weapon.');
    Exit;
  end;
  if W <> Player.Weapon then
  begin
    Player.Weapon := W;
    Player.AttackTics := 0;
    Player.WeaponFrame := 'A';
    Player.FlashFrame := #0;
  end;
end;

procedure TDoomWorld.NextWeapon(const Delta: Integer);
const
  Order: array [0..8] of TWeapon = (wpFist, wpChainsaw, wpPistol, wpShotgun, wpSuperShotgun, wpChaingun, wpMissile, wpPlasma, wpBfg);
var
  I, Start, Idx: Integer;
begin
  Start := 0;
  for I := 0 to 8 do
    if Order[I] = Player.Weapon then Start := I;
  Idx := Start;
  for I := 1 to 8 do
  begin
    Idx := (Idx + Delta + 9) mod 9;
    if (Order[Idx] in Player.Weapons) and
       ((AmmoFor(Order[Idx]) = amNoAmmo) or (Player.Ammo[AmmoFor(Order[Idx])] > 0)) then
    begin
      SelectWeapon(Order[Idx]);
      Exit;
    end;
  end;
end;

procedure TDoomWorld.Update(const SecondsPassed: Single; const PlayerFeetX, PlayerFeetY, PlayerFeetZ: Single;
  const PlayerAngleDeg: Single; const CameraPos, CameraDir: TVector3);
var
  Steps: Integer;
begin
  if FMap = nil then Exit;
  Player.X := PlayerFeetX;
  Player.Y := PlayerFeetY;
  Player.Z := PlayerFeetZ;
  Player.Angle := PlayerAngleDeg;
  Player.Sector := FMap.SectorAt(Player.X, Player.Y);
  FRayOrigin := CameraPos;
  FRayDir := CameraDir;
  FHaveRay := true;
  FPlayerEmitter.Translation := CameraPos;

  FTicAccum := FTicAccum + Min(SecondsPassed, 0.25);
  Steps := 0;
  while (FTicAccum >= TicSeconds) and (Steps < 10) do
  begin
    FTicAccum := FTicAccum - TicSeconds;
    RunTic;
    Inc(Steps);
  end;
  FGeometry.Update(SecondsPassed, CameraPos);
  FGeometry.FlushDirty;
  Player.DamageFlash := Max(0, Player.DamageFlash - SecondsPassed * 1.5);
  Player.BonusFlash := Max(0, Player.BonusFlash - SecondsPassed * 2);
end;

procedure TDoomWorld.RunTic;
begin
  Inc(FTic);
  FGraphics.AnimationTic(FTic);
  TicMovers;
  TicLights;
  TicButtons;
  TicActors;
  if not Player.Dead then
  begin
    CheckPickups;
    CheckCrossings;
  end;
  TicPlayer;
  FOldPlayerX := Player.X;
  FOldPlayerY := Player.Y;
end;

procedure TDoomWorld.TicMovers;
var
  I: Integer;
begin
  for I := FMovers.Count - 1 downto 0 do
  begin
    FMovers[I].Tic;
    if FMovers[I].Phase = mpDone then
      FMovers.Delete(I);
  end;
end;

procedure TDoomWorld.TicLights;
var
  I, Sec, MinL, MaxL, NewL: Integer;
begin
  for I := 0 to High(FLightSectors) do
  begin
    Sec := FLightSectors[I];
    MaxL := FMap.Sectors[Sec].OrigLight;
    MinL := FMap.MinSurroundingLight(Sec, MaxL);
    NewL := FMap.Sectors[Sec].LightLevel;
    case FMap.Sectors[Sec].Special of
      1, 17: { random blink / fire flicker }
        begin
          Dec(FLightTimers[I]);
          if FLightTimers[I] <= 0 then
          begin
            if NewL = MaxL then
            begin
              if MinL = MaxL then MinL := 0;
              NewL := MinL;
              FLightTimers[I] := Random1(7);
            end else
            begin
              NewL := MaxL;
              if FMap.Sectors[Sec].Special = 17 then
                FLightTimers[I] := Random1(4)
              else
                FLightTimers[I] := Random1(64);
            end;
          end;
        end;
      2, 3, 4, 12, 13: { strobe }
        begin
          Dec(FLightTimers[I]);
          if FLightTimers[I] <= 0 then
          begin
            if NewL = MinL then
            begin
              NewL := MaxL;
              FLightTimers[I] := 5;
            end else
            begin
              if MinL = MaxL then MinL := 0;
              NewL := MinL;
              if FMap.Sectors[Sec].Special in [3, 12] then
                FLightTimers[I] := 35
              else
                FLightTimers[I] := 15;
            end;
          end;
        end;
      8: { glow }
        begin
          if FLightPhase[I] = 0 then
          begin
            NewL := NewL - 8;
            if NewL <= MinL then
            begin
              NewL := MinL;
              FLightPhase[I] := 1;
            end;
          end else
          begin
            NewL := NewL + 8;
            if NewL >= MaxL then
            begin
              NewL := MaxL;
              FLightPhase[I] := 0;
            end;
          end;
        end;
    end;
    if NewL <> FMap.Sectors[Sec].LightLevel then
    begin
      FMap.Sectors[Sec].LightLevel := NewL;
      FGeometry.SectorChanged(Sec);
    end;
  end;
end;

procedure TDoomWorld.TicButtons;
var
  I: Integer;
begin
  for I := High(FButtons) downto 0 do
  begin
    Dec(FButtons[I].TicsLeft);
    if FButtons[I].TicsLeft <= 0 then
    begin
      FGeometry.FlipSwitch(FButtons[I].Line);
      FButtons[I] := FButtons[High(FButtons)];
      SetLength(FButtons, Length(FButtons) - 1);
    end;
  end;
end;

procedure TDoomWorld.TicPlayer;
var
  Sec, Special: Integer;
begin
  if Player.MessageTics > 0 then Dec(Player.MessageTics);
  if Player.FaceTics > 0 then Dec(Player.FaceTics) else Player.FaceState := 0;
  if Player.BerserkTics > 0 then Dec(Player.BerserkTics);
  if Player.InvulnerableTics > 0 then Dec(Player.InvulnerableTics);
  if Player.InvisibleTics > 0 then Dec(Player.InvisibleTics);
  if Player.RadSuitTics > 0 then Dec(Player.RadSuitTics);
  if Player.LightAmpTics > 0 then Dec(Player.LightAmpTics);
  UpdateWeaponAnimation;
  if Player.Dead then Exit;

  Sec := Player.Sector;
  if Sec < 0 then Exit;
  Special := FMap.Sectors[Sec].Special;
  if Special = 9 then
  begin
    FMap.Sectors[Sec].Special := 0;
    Inc(Player.Secrets);
    ShowMessage('A secret is revealed!');
    FSounds.Play('DSITEMUP');
  end;
  { Damaging floors, only when standing on them. }
  if (Player.Z <= FMap.Sectors[Sec].FloorHeight + 1) and (FTic mod 32 = 0) and (Player.RadSuitTics = 0) then
    case Special of
      7: DamagePlayer(5, nil);
      5: DamagePlayer(10, nil);
      16, 4: DamagePlayer(20, nil);
      11:
        begin
          DamagePlayer(20, nil);
          if Player.Health <= 10 then
          begin
            FExitRequested := true;
            Player.Health := Max(Player.Health, 1);
          end;
        end;
    end;
end;

procedure TDoomWorld.UpdateWeaponAnimation;

  { Doom weapon state tables, reduced: frame letters and durations. }
  procedure Seq(const Frames: String; const Tics: array of Integer; const FlashFrames: String;
    const FlashTics: Integer; const Elapsed: Integer);
  var
    I, T: Integer;
  begin
    T := 0;
    Player.WeaponFrame := 'A';
    for I := 1 to Length(Frames) do
    begin
      if Elapsed < T + Tics[I - 1] then
      begin
        Player.WeaponFrame := Frames[I];
        Break;
      end;
      T := T + Tics[I - 1];
    end;
    Player.FlashFrame := #0;
    if (FlashFrames <> '') and (Elapsed < FlashTics * Length(FlashFrames)) then
      Player.FlashFrame := FlashFrames[1 + Elapsed div FlashTics];
  end;

var
  Total, Elapsed: Integer;
begin
  if Player.AttackTics > 0 then
    Dec(Player.AttackTics);
  case Player.Weapon of
    wpPistol: Total := 18;
    wpShotgun: Total := 36;
    wpChaingun: Total := 8;
    wpMissile: Total := 32;
    wpPlasma: Total := 8;
    wpBfg: Total := 60;
    wpFist: Total := 20;
    wpChainsaw: Total := 8;
    wpSuperShotgun: Total := 56;
    else Total := 18;
  end;
  if Player.AttackTics <= 0 then
  begin
    Player.WeaponFrame := 'A';
    Player.FlashFrame := #0;
    if (Player.Weapon = wpChainsaw) and ((FTic div 4) mod 2 = 1) then
      Player.WeaponFrame := 'B';
    Exit;
  end;
  Elapsed := Total - Player.AttackTics;
  case Player.Weapon of
    wpPistol: Seq('BCBA', [4, 6, 4, 4], 'A', 7, Elapsed);
    wpShotgun: Seq('BCDCBA', [3, 7, 5, 5, 4, 12], 'AB', 4, Elapsed);
    wpChaingun: Seq('AB', [4, 4], 'A', 4, Elapsed);
    wpMissile: Seq('BCBA', [8, 12, 6, 6], 'ABCD', 3, Elapsed);
    wpPlasma: Seq('BA', [4, 4], 'A', 4, Elapsed);
    wpBfg: Seq('ABCDA', [20, 10, 10, 10, 10], 'AB', 8, Elapsed);
    wpFist: Seq('BCDCBA', [4, 4, 5, 4, 3, 0], '', 0, Elapsed);
    wpChainsaw: Seq('CD', [4, 4], '', 0, Elapsed);
    wpSuperShotgun: Seq('BCDEFGHA', [7, 7, 7, 7, 7, 6, 6, 9], 'IJ', 5, Elapsed);
  end;
end;

procedure TDoomWorld.TicActors;
var
  I: Integer;
  A: TDoomActor;
  Sec: Integer;
begin
  for I := FActors.Count - 1 downto 0 do
  begin
    A := FActors[I];
    A.AnimateTic;
    case A.State of
      asEffect:
        if A.SequenceDone then A.Removed := true;
      asDying:
        if A.SequenceDone then
        begin
          if A.Info^.Num = -1 then
            A.Removed := true { exploded missile }
          else
            A.State := asDead;
        end;
      asPain:
        if A.SequenceDone then
        begin
          A.State := asChase;
          A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
        end;
      asAttack:
        if A.SequenceDone then
        begin
          A.State := asChase;
          A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
          A.ReactionTics := 20 + Random1(35);
        end;
      asMissile: TicMissile(A);
    end;
    if (A.Info^.Kind = tkMonster) and (A.State in [asIdle, asChase, asAttack]) then
      TicMonster(A);

    { Follow moving floors. }
    if not A.Removed then
    begin
      Sec := A.Sector;
      if (Sec >= 0) and not (A.State in [asMissile, asEffect]) then
      begin
        if A.Info^.Hanging then
          A.DoomZ := FMap.Sectors[Sec].CeilingHeight - A.Info^.Height
        else if A.Info^.Floats and (A.State in [asChase, asAttack]) then
          A.DoomZ := Clamped(A.DoomZ, FMap.Sectors[Sec].FloorHeight,
            Max(FMap.Sectors[Sec].FloorHeight, FMap.Sectors[Sec].CeilingHeight - A.Info^.Height))
        else
          A.DoomZ := FMap.Sectors[Sec].FloorHeight;
        A.SetLight(FMap.Sectors[Sec].LightLevel);
      end;
      A.UpdateRotation(Player.X, Player.Y);
      A.UpdateTransform;
    end;

    if A.Removed then
    begin
      if A.Parent <> nil then A.Parent.Remove(A);
      FActors.Delete(I);
    end;
  end;
end;

function TDoomWorld.SightClear(const X1, Y1, X2, Y2: Single): Boolean;
var
  I, F, B: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  T: Single;
  MinX, MaxX, MinY, MaxY: Single;
begin
  MinX := Min(X1, X2); MaxX := Max(X1, X2);
  MinY := Min(Y1, Y2); MaxY := Max(Y1, Y2);
  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if (Max(V1.X, V2.X) < MinX) or (Min(V1.X, V2.X) > MaxX) or
       (Max(V1.Y, V2.Y) < MinY) or (Min(V1.Y, V2.Y) > MaxY) then Continue;
    F := L.FrontSector;
    B := L.BackSector;
    if (F >= 0) and (B >= 0) then
    begin
      { Open two-sided line: see through unless the gap is closed. }
      if Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight) >
         Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight) then Continue;
    end;
    if SegmentsIntersect(X1, Y1, X2, Y2, V1.X, V1.Y, V2.X, V2.Y, T) then
      Exit(false);
  end;
  Result := true;
end;

function TDoomWorld.TryMove2D(const A: TDoomActor; const NX, NY: Single; out BlockedByLine: Integer): Boolean;
var
  R, Z, H: Single;
  I, F, B, Sec: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  OpenTop, OpenBottom, LowFloor, FloorZ: Single;
  Corners: array [0..3] of Single;
  O: TDoomActor;

  function BoxIntersectsLine: Boolean;
  var
    S0, S1, S2, S3: Single;
  begin
    { Quick reject by bounding boxes. }
    if (Max(V1.X, V2.X) < NX - R) or (Min(V1.X, V2.X) > NX + R) or
       (Max(V1.Y, V2.Y) < NY - R) or (Min(V1.Y, V2.Y) > NY + R) then Exit(false);
    { All four box corners on the same side of the line = no crossing. }
    S0 := (NX - R - V1.X) * (V2.Y - V1.Y) - (NY - R - V1.Y) * (V2.X - V1.X);
    S1 := (NX + R - V1.X) * (V2.Y - V1.Y) - (NY - R - V1.Y) * (V2.X - V1.X);
    S2 := (NX + R - V1.X) * (V2.Y - V1.Y) - (NY + R - V1.Y) * (V2.X - V1.X);
    S3 := (NX - R - V1.X) * (V2.Y - V1.Y) - (NY + R - V1.Y) * (V2.X - V1.X);
    Result := not (((S0 > 0) and (S1 > 0) and (S2 > 0) and (S3 > 0)) or
                   ((S0 < 0) and (S1 < 0) and (S2 < 0) and (S3 < 0)));
  end;

begin
  Result := false;
  BlockedByLine := -1;
  R := A.Info^.Radius;
  Z := A.DoomZ;
  H := A.Info^.Height;
  Corners[0] := 0; { silence warnings }
  Sec := FMap.SectorAt(NX, NY);
  if Sec < 0 then Exit;
  FloorZ := FMap.Sectors[Sec].FloorHeight;

  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if not BoxIntersectsLine then Continue;
    F := L.FrontSector;
    B := L.BackSector;
    if (F < 0) or (B < 0) then
    begin
      BlockedByLine := I;
      Exit;
    end;
    if (L.Flags and (ML_BLOCKING or ML_BLOCKMONSTERS)) <> 0 then
    begin
      BlockedByLine := I;
      Exit;
    end;
    OpenTop := Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight);
    OpenBottom := Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight);
    LowFloor := Min(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight);
    if OpenTop - OpenBottom < H then
    begin
      BlockedByLine := I;
      Exit;
    end;
    if OpenBottom - Z > 24 then
    begin
      BlockedByLine := I;
      Exit;
    end;
    if (not A.Info^.Floats) and (OpenBottom - LowFloor > 24) and (LowFloor < Z - 24) then
    begin
      BlockedByLine := I;
      Exit;
    end;
    if OpenBottom > FloorZ then FloorZ := OpenBottom;
  end;

  { Other solid things. }
  for O in FActors do
    if (O <> A) and O.Collides and (O.State <> asDead) and not O.Removed and
       (O.Info^.Kind in [tkMonster, tkDecoration]) then
      if (Abs(O.DoomX - NX) < O.Info^.Radius + R) and (Abs(O.DoomY - NY) < O.Info^.Radius + R) then
        Exit;
  { The player. }
  if (not Player.Dead) and (Abs(Player.X - NX) < PlayerRadius + R) and (Abs(Player.Y - NY) < PlayerRadius + R) then
    Exit;

  A.DoomX := NX;
  A.DoomY := NY;
  A.Sector := Sec;
  if not A.Info^.Floats then
    A.DoomZ := FloorZ;
  Result := true;
end;

procedure TDoomWorld.NoiseAlert;
var
  A: TDoomActor;
  D: Single;
begin
  for A in FActors do
    if (A.Info^.Kind = tkMonster) and (A.State = asIdle) and not A.Awake then
    begin
      D := Sqrt(Sqr(A.DoomX - Player.X) + Sqr(A.DoomY - Player.Y));
      if (D < 1200) and SightClear(A.DoomX, A.DoomY, Player.X, Player.Y) then
      begin
        A.Awake := true;
        A.ReactionTics := Random1(8);
      end;
    end;
end;

procedure TDoomWorld.TicMonster(const A: TDoomActor);
var
  DX, DY, Dist, Ang, Step: Single;
  Blocked: Integer;
  Tries: Integer;
  Moved: Boolean;
begin
  if Player.Dead then Exit;
  DX := Player.X - A.DoomX;
  DY := Player.Y - A.DoomY;
  Dist := Sqrt(DX * DX + DY * DY);

  if A.State = asIdle then
  begin
    if not A.Awake then
    begin
      { Look for the player a few times a second. }
      if (FTic + A.MapFlags) mod 10 <> 0 then Exit;
      if (Dist < 3000) and SightClear(A.DoomX, A.DoomY, Player.X, Player.Y) then
      begin
        { Ambush monsters wait until they see you move into view; others also
          react to being in front. Keep it simple: sight wakes everyone. }
        A.Awake := true;
        A.ReactionTics := Random1(8);
      end else
        Exit;
    end;
    if A.ReactionTics > 0 then
    begin
      Dec(A.ReactionTics);
      Exit;
    end;
    A.State := asChase;
    A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
    if A.Info^.SeeSound <> '' then
      FSounds.PlayAt(A.Info^.SeeSound, A);
    A.ReactionTics := 10 + Random1(20);
    Exit;
  end;

  if A.State <> asChase then Exit;
  if A.Info^.Speed = 0 then Exit;

  { Face the player (with a little lag). }
  Ang := RadToDeg(ArcTan2(DY, DX));
  A.Angle := Ang;

  { Attack? }
  if A.ReactionTics > 0 then
    Dec(A.ReactionTics)
  else
  begin
    if (A.Info^.Attack = akMelee) or (Dist < 64 + A.Info^.Radius) then
    begin
      if Dist < 64 + A.Info^.Radius then
      begin
        MonsterAttack(A);
        Exit;
      end;
    end else if SightClear(A.DoomX, A.DoomY, Player.X, Player.Y) then
    begin
      { Doom's P_CheckMissileRange: more likely to shoot when close. }
      if Random(256) >= Min(220, 40 + Trunc(Dist / 6)) then
      begin
        MonsterAttack(A);
        Exit;
      end;
    end;
    A.ReactionTics := 10 + Random1(12);
  end;

  { Move towards the player, trying other directions when blocked. }
  Step := A.Info^.Speed / MoveFrameTics(A.Info^.Num);
  if A.Info^.Floats then
    Step := Step * 1.2;
  Moved := false;
  Tries := 0;
  while (not Moved) and (Tries < 4) do
  begin
    case Tries of
      0: ;
      1: Ang := Ang + 45 * (1 - 2 * Random(2));
      2: Ang := Ang - 90 * (1 - 2 * Random(2));
      3: Ang := Ang + 180;
    end;
    Moved := TryMove2D(A, A.DoomX + Cos(DegToRad(Ang)) * Step, A.DoomY + Sin(DegToRad(Ang)) * Step, Blocked);
    if (not Moved) and (Blocked >= 0) and (Tries = 0) then
    begin
      { Monsters open doors in their way. }
      if FMap.Linedefs[Blocked].Special in [1, 117, 2, 4, 108, 90, 105, 86, 106] then
        UseSpecialLine(Blocked, FMap.PointOnLineSide(A.DoomX, A.DoomY, Blocked), true);
    end;
    Inc(Tries);
  end;
  if A.Info^.Floats then
  begin
    { Flyers drift towards the player's eye height. }
    if Player.Z + 32 > A.DoomZ + 8 then A.DoomZ := A.DoomZ + 2
    else if Player.Z + 32 < A.DoomZ - 8 then A.DoomZ := A.DoomZ - 2;
  end;
end;

procedure TDoomWorld.MonsterAttack(const A: TDoomActor);
begin
  A.State := asAttack;
  A.PlaySequence(A.Info^.AttackFrames, 6, false);
  case A.Info^.Attack of
    akMelee:
      begin
        if A.Info^.AttackSound <> '' then FSounds.PlayAt(A.Info^.AttackSound, A);
        if Sqrt(Sqr(Player.X - A.DoomX) + Sqr(Player.Y - A.DoomY)) < 64 + A.Info^.Radius then
          DamagePlayer(Dice(A.Info^.DamageDice, A.Info^.DamageFaces), A);
      end;
    akHitscan: MonsterHitscan(A);
    akMissile: SpawnMissile(A);
  end;
end;

procedure TDoomWorld.MonsterHitscan(const A: TDoomActor);
var
  Dist, Chance: Single;
  Shots, I: Integer;
begin
  if A.Info^.AttackSound <> '' then FSounds.PlayAt(A.Info^.AttackSound, A);
  Dist := Sqrt(Sqr(Player.X - A.DoomX) + Sqr(Player.Y - A.DoomY));
  Chance := Clamped(0.55 - Dist / 2000, 0.1, 0.55);
  if Player.InvisibleTics > 0 then Chance := Chance * 0.4;
  Shots := 1;
  if A.Info^.Num in [9, 7] then Shots := 3;
  for I := 1 to Shots do
    if Random < Chance then
      DamagePlayer(Dice(A.Info^.DamageDice, A.Info^.DamageFaces), A);
end;

procedure TDoomWorld.SpawnMissile(const A: TDoomActor);
var
  K: TEffectKind;
  M: TDoomActor;
  DX, DY, DZ, Len, Speed: Single;
begin
  case A.Info^.Num of
    3001: K := ekBal1;
    3005, 71: K := ekBal2;
    3003, 69: K := ekBal7;
    16: K := ekRocket;
    66: K := ekRevenantRocket;
    67: K := ekFatShot;
    68: K := ekArachPlasma;
    else K := ekBal1;
  end;
  M := TDoomActor.Create(nil, FGraphics, @EffectInfos[K]);
  M.State := asMissile;
  M.Bright := true;
  M.DoomX := A.DoomX + Cos(DegToRad(A.Angle)) * (A.Info^.Radius + 8);
  M.DoomY := A.DoomY + Sin(DegToRad(A.Angle)) * (A.Info^.Radius + 8);
  M.DoomZ := A.DoomZ + A.Info^.Height * 0.6;
  M.Sector := A.Sector;
  DX := Player.X - M.DoomX;
  DY := Player.Y - M.DoomY;
  DZ := (Player.Z + 28) - M.DoomZ;
  Len := Sqrt(DX * DX + DY * DY + DZ * DZ);
  if Len < 1 then Len := 1;
  Speed := EffectInfos[K].Speed;
  M.VelX := DX / Len * Speed;
  M.VelY := DY / Len * Speed;
  M.VelZ := DZ / Len * Speed;
  M.MissileDamageDice := EffectInfos[K].DamageDice;
  M.MissileDamageFaces := EffectInfos[K].DamageFaces;
  M.Angle := RadToDeg(ArcTan2(DY, DX));
  M.Collides := false;
  M.Pickable := false;
  M.SetLight(255);
  M.UpdateTransform;
  FActors.Add(M);
  FItems.Add(M);
  if EffectInfos[K].AttackSound <> '' then
    FSounds.PlayAt(EffectInfos[K].AttackSound, A);
end;

function TDoomWorld.LineBlocksMissile(const Line: Integer; const X, Y, Z: Single): Boolean;
var
  L: TDoomLinedef;
  F, B: Integer;
begin
  L := FMap.Linedefs[Line];
  F := L.FrontSector;
  B := L.BackSector;
  if (F < 0) or (B < 0) then Exit(true);
  Result := (Z < Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight)) or
            (Z > Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight));
end;

procedure TDoomWorld.TicMissile(const A: TDoomActor);
var
  NX, NY, NZ, T: Single;
  I, Sec: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  Hit: Boolean;
  DeathSprite: String;
begin
  if A.State <> asMissile then Exit;
  NX := A.DoomX + A.VelX;
  NY := A.DoomY + A.VelY;
  NZ := A.DoomZ + A.VelZ;
  Hit := false;

  { The player? }
  if (not Player.Dead) and (Abs(Player.X - NX) < PlayerRadius + A.Info^.Radius) and
     (Abs(Player.Y - NY) < PlayerRadius + A.Info^.Radius) and
     (NZ > Player.Z - 8) and (NZ < Player.Z + PlayerHeight + 8) then
  begin
    DamagePlayer(Dice(A.MissileDamageDice, A.MissileDamageFaces), A);
    Hit := true;
  end;

  { Walls / closed openings / floor / ceiling. }
  if not Hit then
    for I := 0 to High(FMap.Linedefs) do
    begin
      L := FMap.Linedefs[I];
      V1 := FMap.Vertices[L.V1];
      V2 := FMap.Vertices[L.V2];
      if (Max(V1.X, V2.X) < Min(A.DoomX, NX) - 1) or (Min(V1.X, V2.X) > Max(A.DoomX, NX) + 1) or
         (Max(V1.Y, V2.Y) < Min(A.DoomY, NY) - 1) or (Min(V1.Y, V2.Y) > Max(A.DoomY, NY) + 1) then Continue;
      if SegmentsIntersect(A.DoomX, A.DoomY, NX, NY, V1.X, V1.Y, V2.X, V2.Y, T) then
        if LineBlocksMissile(I, NX, NY, NZ) then
        begin
          Hit := true;
          NX := A.DoomX + A.VelX * Max(0, T - 0.1);
          NY := A.DoomY + A.VelY * Max(0, T - 0.1);
          { Shooting a gun-activated line. }
          if L.Special in [24, 46, 47] then ShootSpecialLine(I);
          Break;
        end;
    end;
  if not Hit then
  begin
    Sec := FMap.SectorAt(NX, NY);
    if Sec >= 0 then
    begin
      if NZ <= FMap.Sectors[Sec].FloorHeight then
      begin
        Hit := true;
        NZ := FMap.Sectors[Sec].FloorHeight + 2;
      end else if NZ + A.Info^.Height >= FMap.Sectors[Sec].CeilingHeight then
      begin
        Hit := true;
        NZ := FMap.Sectors[Sec].CeilingHeight - A.Info^.Height - 2;
      end;
      A.Sector := Sec;
    end;
  end;

  A.DoomX := NX;
  A.DoomY := NY;
  A.DoomZ := NZ;
  if Hit then
  begin
    A.State := asDying;
    DeathSprite := A.Info^.MoveFrames;
    if DeathSprite <> '' then A.SpritePrefix := DeathSprite;
    A.PlaySequence(A.Info^.DeathFrames, 6, false);
    if A.Info^.DeathSound <> '' then FSounds.PlayAt(A.Info^.DeathSound, A);
    if A.Info^.Sprite = 'MISL' then
      RadiusDamage(NX, NY, NZ, 128, 128, A);
    A.VelX := 0; A.VelY := 0; A.VelZ := 0;
  end;
end;

procedure TDoomWorld.DamagePlayer(const Damage: Integer; const FromActor: TDoomActor);
var
  Dmg, Saved: Integer;
begin
  if Player.Dead or (Damage <= 0) then Exit;
  if Player.InvulnerableTics > 0 then Exit;
  Dmg := Damage;
  if Player.Armor > 0 then
  begin
    if Player.ArmorType = 2 then Saved := Dmg div 2 else Saved := Dmg div 3;
    if Player.Armor <= Saved then
    begin
      Saved := Player.Armor;
      Player.ArmorType := 0;
    end;
    Player.Armor := Player.Armor - Saved;
    Dmg := Dmg - Saved;
  end;
  Player.Health := Player.Health - Dmg;
  Player.DamageFlash := Min(1, Player.DamageFlash + Dmg / 40);
  LastDamage := Dmg;
  if Dmg >= 20 then
  begin
    Player.FaceState := 2; { ouch }
    Player.FaceTics := 35;
  end else
  begin
    Player.FaceState := 1; { pain }
    Player.FaceTics := 20;
  end;
  if Player.Health <= 0 then
  begin
    Player.Health := 0;
    Player.Dead := true;
    FSounds.Play('DSPLDETH');
    ShowMessage('You died. Press USE to try again.');
  end else
    FSounds.Play('DSPLPAIN');
end;

procedure TDoomWorld.DamageActor(const A: TDoomActor; const Damage: Integer; const HitX, HitY, HitZ: Single);
var
  Blood: TDoomActor;
begin
  if (A.State in [asDying, asDead, asEffect, asMissile]) or (Damage <= 0) then Exit;
  if not ((A.Info^.Kind = tkMonster) or (A.Info^.Num = 2035)) then Exit;
  A.Health := A.Health - Damage;
  if A.Info^.Num <> 2035 then
  begin
    Blood := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekBlood]);
    Blood.State := asEffect;
    Blood.DoomX := HitX; Blood.DoomY := HitY; Blood.DoomZ := HitZ - 8;
    Blood.Sector := A.Sector;
    Blood.Collides := false; Blood.Pickable := false;
    Blood.SetLight(FMap.Sectors[Max(0, A.Sector)].LightLevel);
    Blood.PlaySequence('CBA', 8, false);
    Blood.UpdateTransform;
    FActors.Add(Blood);
    FItems.Add(Blood);
  end;
  if A.Health <= 0 then
  begin
    KillActor(A);
    Exit;
  end;
  { Getting shot wakes a monster up. }
  if A.Info^.Kind = tkMonster then
  begin
    if not A.Awake then
    begin
      A.Awake := true;
      A.ReactionTics := 0;
    end;
    if A.State = asIdle then
    begin
      A.State := asChase;
      A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
    end;
    if (A.Info^.PainFrame <> #0) and (Random(256) < A.Info^.PainChance) then
    begin
      A.State := asPain;
      A.PlaySequence(A.Info^.PainFrame, 6, false);
      if A.Info^.PainSound <> '' then FSounds.PlayAt(A.Info^.PainSound, A);
    end;
  end;
end;

procedure TDoomWorld.KillActor(const A: TDoomActor);
var
  Drop: TDoomActor;
  Info: PThingInfo;
begin
  if A.Info^.Num = 2035 then
  begin
    ExplodeBarrel(A);
    Exit;
  end;
  A.State := asDying;
  A.Collides := false;
  A.Pickable := false;
  A.PlaySequence(A.Info^.DeathFrames, 5, false);
  if A.Info^.DeathSound <> '' then FSounds.PlayAt(A.Info^.DeathSound, A);
  if A.Info^.Kind = tkMonster then
  begin
    Inc(Player.Kills);
    Player.FaceState := 3; { evil grin }
    Player.FaceTics := 35;
  end;
  if A.Info^.Drop <> 0 then
  begin
    Info := FindThingInfo(A.Info^.Drop);
    if Info <> nil then
    begin
      Drop := TDoomActor.Create(nil, FGraphics, Info);
      Drop.DoomX := A.DoomX; Drop.DoomY := A.DoomY; Drop.DoomZ := A.DoomZ;
      Drop.Sector := A.Sector;
      Drop.SetLight(FMap.Sectors[Max(0, A.Sector)].LightLevel);
      Drop.UpdateTransform;
      FActors.Add(Drop);
      FItems.Add(Drop);
    end;
  end;
end;

procedure TDoomWorld.ExplodeBarrel(const A: TDoomActor);
begin
  A.State := asDying;
  A.Collides := false;
  A.Pickable := false;
  A.Bright := true;
  A.SpritePrefix := 'BEXP';
  A.PlaySequence('ABCDE', 5, false);
  A.SetLight(255);
  FSounds.PlayAt('DSBAREXP', A);
  RadiusDamage(A.DoomX, A.DoomY, A.DoomZ + 20, 128, 128, A);
end;

procedure TDoomWorld.RadiusDamage(const X, Y, Z: Single; const Radius, Damage: Integer; const Source: TDoomActor);
var
  O: TDoomActor;
  D: Single;
  I: Integer;
begin
  for I := FActors.Count - 1 downto 0 do
  begin
    O := FActors[I];
    if (O = Source) or O.Removed then Continue;
    if not ((O.Info^.Kind = tkMonster) or (O.Info^.Num = 2035)) then Continue;
    if O.State in [asDying, asDead] then Continue;
    D := Max(Abs(O.DoomX - X), Abs(O.DoomY - Y)) - O.Info^.Radius;
    if D < 0 then D := 0;
    if D >= Radius then Continue;
    if (O.Info^.Num = 2035) and (Source <> nil) and (Source.Info^.Num = 2035) then
    begin
      { Chain reaction with a little delay: just damage it now. }
    end;
    DamageActor(O, Damage - Trunc(D), O.DoomX, O.DoomY, O.DoomZ + 24);
  end;
  D := Max(Abs(Player.X - X), Abs(Player.Y - Y)) - PlayerRadius;
  if D < 0 then D := 0;
  if D < Radius then
    DamagePlayer(Damage - Trunc(D), Source);
end;

function TDoomWorld.RayHit(const Origin, Dir: TVector3; out HitPoint: TVector3;
  out Actor: TDoomActor; out Dist: Single): Boolean;
var
  RC: TRayCollision;
  I: Integer;
begin
  Result := false;
  Actor := nil;
  HitPoint := Origin;
  Dist := 0;
  RC := FItems.WorldRay(Origin, Dir);
  if RC = nil then Exit;
  try
    Dist := RC.Distance;
    HitPoint := Origin + Dir.Normalize * Dist;
    for I := 0 to RC.Count - 1 do
      if RC[I].Item is TDoomActor then
      begin
        Actor := TDoomActor(RC[I].Item);
        Break;
      end;
    Result := true;
  finally
    FreeAndNil(RC);
  end;
end;

procedure TDoomWorld.HitscanAttack(const Origin, Dir: TVector3; const Damage: Integer; const Splash: Integer);
var
  HitPoint, Back: TVector3;
  Actor, Puff: TDoomActor;
  Dist: Single;
  D: TVector3;
  I: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  PX, PY: Single;
  Best, BestD, LineD: Single;
  BestLine: Integer;
begin
  if not RayHit(Origin, Dir, HitPoint, Actor, Dist) then Exit;
  D := CgeToDoom(HitPoint);
  if Actor <> nil then
  begin
    DamageActor(Actor, Damage, D.X, D.Y, D.Z);
  end else
  begin
    { Bullet puff slightly in front of the wall. }
    Back := HitPoint - Dir.Normalize * 4;
    Puff := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekPuff]);
    Puff.State := asEffect;
    Puff.Bright := true;
    D := CgeToDoom(Back);
    Puff.DoomX := D.X; Puff.DoomY := D.Y; Puff.DoomZ := D.Z - 4;
    Puff.Sector := FMap.SectorAt(D.X, D.Y);
    Puff.Collides := false; Puff.Pickable := false;
    Puff.SetLight(255);
    Puff.PlaySequence('ABCD', 4, false);
    Puff.UpdateTransform;
    FActors.Add(Puff);
    FItems.Add(Puff);

    { Gun-activated lines near the hit point. }
    PX := D.X; PY := D.Y;
    BestLine := -1;
    BestD := 4;
    for I := 0 to High(FMap.Linedefs) do
    begin
      L := FMap.Linedefs[I];
      if not (L.Special in [24, 46, 47]) then Continue;
      V1 := FMap.Vertices[L.V1];
      V2 := FMap.Vertices[L.V2];
      { Distance from point to segment. }
      Best := ((PX - V1.X) * (V2.X - V1.X) + (PY - V1.Y) * (V2.Y - V1.Y)) / Max(1, Sqr(L.Length));
      Best := Clamped(Best, 0, 1);
      LineD := Sqrt(Sqr(PX - (V1.X + (V2.X - V1.X) * Best)) + Sqr(PY - (V1.Y + (V2.Y - V1.Y) * Best)));
      if LineD < BestD then
      begin
        BestD := LineD;
        BestLine := I;
      end;
    end;
    if BestLine >= 0 then ShootSpecialLine(BestLine);
  end;
  if Splash > 0 then
    RadiusDamage(D.X, D.Y, D.Z, Splash, Splash, nil);
end;

procedure TDoomWorld.FireWeapon;
var
  Ammo: TAmmoType;
  Cost, I, Pellets, Dmg: Integer;
  Dir, Right, Up: TVector3;
  Spread, SpreadV: Single;
  HitPoint: TVector3;
  Actor: TDoomActor;
  Dist: Single;
  D: TVector3;
begin
  if Player.Dead or (FMap = nil) or not FHaveRay then Exit;
  if Player.AttackTics > 0 then Exit;
  Ammo := AmmoFor(Player.Weapon);
  Cost := 1;
  if Player.Weapon = wpBfg then Cost := 40;
  if Player.Weapon = wpSuperShotgun then Cost := 2;
  if (Ammo <> amNoAmmo) and (Player.Ammo[Ammo] < Cost) then
  begin
    NextWeapon(-1);
    Exit;
  end;
  if Ammo <> amNoAmmo then
    Player.Ammo[Ammo] := Player.Ammo[Ammo] - Cost;

  Dir := FRayDir.Normalize;
  Right := TVector3.CrossProduct(Dir, Vector3(0, 1, 0)).Normalize;
  Up := TVector3.CrossProduct(Right, Dir).Normalize;
  NoiseAlert;

  case Player.Weapon of
    wpFist, wpChainsaw:
      begin
        Player.AttackTics := IfThen(Player.Weapon = wpFist, 20, 8);
        if Player.Weapon = wpChainsaw then FSounds.Play('DSSAWFUL');
        if RayHit(FRayOrigin, Dir, HitPoint, Actor, Dist) and (Dist < 64 + 16) and (Actor <> nil) then
        begin
          Dmg := Dice(2, 10);
          if (Player.Weapon = wpFist) and (Player.BerserkTics > 0) then Dmg := Dmg * 10;
          if Player.Weapon = wpChainsaw then FSounds.Play('DSSAWHIT') else FSounds.Play('DSPUNCH');
          D := CgeToDoom(HitPoint);
          DamageActor(Actor, Dmg, D.X, D.Y, D.Z);
        end;
      end;
    wpPistol:
      begin
        Player.AttackTics := 18;
        FSounds.Play('DSPISTOL');
        Spread := 0;
        if Player.Refire then Spread := (Random - 0.5) * 5.6;
        HitscanAttack(FRayOrigin, (Dir + Right * Sin(DegToRad(Spread))).Normalize, Dice(5, 3), 0);
      end;
    wpShotgun, wpSuperShotgun:
      begin
        if Player.Weapon = wpShotgun then
        begin
          Player.AttackTics := 36;
          Pellets := 7;
          FSounds.Play('DSSHOTGN');
        end else
        begin
          Player.AttackTics := 56;
          Pellets := 20;
          FSounds.Play('DSDSHTGN');
        end;
        for I := 1 to Pellets do
        begin
          Spread := (Random - 0.5) * 11.2;
          SpreadV := 0;
          if Player.Weapon = wpSuperShotgun then SpreadV := (Random - 0.5) * 7;
          HitscanAttack(FRayOrigin,
            (Dir + Right * Sin(DegToRad(Spread)) + Up * Sin(DegToRad(SpreadV))).Normalize, Dice(5, 3), 0);
        end;
      end;
    wpChaingun:
      begin
        Player.AttackTics := 8;
        FSounds.Play('DSPISTOL');
        Spread := (Random - 0.5) * 5.6;
        HitscanAttack(FRayOrigin, (Dir + Right * Sin(DegToRad(Spread))).Normalize, Dice(5, 3), 0);
      end;
    wpMissile:
      begin
        Player.AttackTics := 32;
        FSounds.Play('DSRLAUNC');
        FSounds.Play('DSBAREXP');
        HitscanAttack(FRayOrigin, Dir, Dice(20, 8), 128);
      end;
    wpPlasma:
      begin
        Player.AttackTics := 8;
        FSounds.Play('DSPLASMA');
        HitscanAttack(FRayOrigin, Dir, Dice(5, 8), 0);
      end;
    wpBfg:
      begin
        Player.AttackTics := 60;
        FSounds.Play('DSBFG');
        FSounds.Play('DSRXPLOD');
        HitscanAttack(FRayOrigin, Dir, Dice(100, 8), 300);
      end;
  end;
  Player.Refire := true;
end;

procedure TDoomWorld.CheckPickups;
var
  I: Integer;
  A: TDoomActor;
  P: TPickupKind;
  Picked: Boolean;
  Sound: String;
  Msg: String;

  function GiveAmmo(const T: TAmmoType; const Amount: Integer): Boolean;
  begin
    if Player.Ammo[T] >= Player.MaxAmmo[T] then Exit(false);
    Player.Ammo[T] := Min(Player.MaxAmmo[T], Player.Ammo[T] + Amount);
    Result := true;
  end;

  function GiveHealth(const Amount, MaxH: Integer): Boolean;
  begin
    if Player.Health >= MaxH then Exit(false);
    Player.Health := Min(MaxH, Player.Health + Amount);
    Result := true;
  end;

  function GiveWeapon(const W: TWeapon; const T: TAmmoType; const Amount: Integer): Boolean;
  var
    HadWeapon: Boolean;
  begin
    HadWeapon := W in Player.Weapons;
    Include(Player.Weapons, W);
    if T <> amNoAmmo then GiveAmmo(T, Amount);
    if not HadWeapon then
    begin
      Player.Weapon := W;
      Player.AttackTics := 0;
    end;
    Result := true;
  end;

begin
  for I := FActors.Count - 1 downto 0 do
  begin
    A := FActors[I];
    if (A.Info^.Kind <> tkPickup) or A.Removed then Continue;
    if (Abs(A.DoomX - Player.X) >= A.Info^.Radius + PlayerRadius) or
       (Abs(A.DoomY - Player.Y) >= A.Info^.Radius + PlayerRadius) then Continue;
    if (A.DoomZ > Player.Z + PlayerHeight) or (A.DoomZ + A.Info^.Height < Player.Z - 24) then Continue;
    P := A.Info^.Pickup;
    Picked := true;
    Sound := 'DSITEMUP';
    Msg := PickupMessage(P, Player.Health < 25);
    case P of
      pkStimpack: Picked := GiveHealth(10, 100);
      pkMedikit: Picked := GiveHealth(25, 100);
      pkHealthBonus: begin GiveHealth(1, 200); Picked := true; end;
      pkArmorBonus: begin Player.Armor := Min(200, Player.Armor + 1); if Player.ArmorType = 0 then Player.ArmorType := 1; end;
      pkArmorGreen:
        if Player.Armor >= 100 then Picked := false
        else begin Player.Armor := 100; Player.ArmorType := 1; end;
      pkArmorBlue: begin Player.Armor := 200; Player.ArmorType := 2; end;
      pkSoulsphere: begin Player.Health := Min(200, Player.Health + 100); Sound := 'DSGETPOW'; end;
      pkMegasphere: begin Player.Health := 200; Player.Armor := 200; Player.ArmorType := 2; Sound := 'DSGETPOW'; end;
      pkBerserk: begin Player.BerserkTics := 60 * TicRate; GiveHealth(100, 100); Player.Weapon := wpFist; Sound := 'DSGETPOW'; end;
      pkInvulnerability: begin Player.InvulnerableTics := 30 * TicRate; Sound := 'DSGETPOW'; end;
      pkInvisibility: begin Player.InvisibleTics := 60 * TicRate; Sound := 'DSGETPOW'; end;
      pkRadSuit: begin Player.RadSuitTics := 60 * TicRate; Sound := 'DSGETPOW'; end;
      pkComputerMap, pkLightAmp: Sound := 'DSGETPOW';
      pkKeyBlue: Include(Player.Keys, keyBlue);
      pkKeyYellow: Include(Player.Keys, keyYellow);
      pkKeyRed: Include(Player.Keys, keyRed);
      pkSkullBlue: Include(Player.Keys, skullBlue);
      pkSkullYellow: Include(Player.Keys, skullYellow);
      pkSkullRed: Include(Player.Keys, skullRed);
      pkClip: Picked := GiveAmmo(amClip, 10);
      pkClipBox: Picked := GiveAmmo(amClip, 50);
      pkShells: Picked := GiveAmmo(amShell, 4);
      pkShellBox: Picked := GiveAmmo(amShell, 20);
      pkRocket: Picked := GiveAmmo(amMisl, 1);
      pkRocketBox: Picked := GiveAmmo(amMisl, 5);
      pkCell: Picked := GiveAmmo(amCell, 20);
      pkCellPack: Picked := GiveAmmo(amCell, 100);
      pkBackpack:
        begin
          Player.MaxAmmo[amClip] := 400; Player.MaxAmmo[amShell] := 100;
          Player.MaxAmmo[amCell] := 600; Player.MaxAmmo[amMisl] := 100;
          GiveAmmo(amClip, 10); GiveAmmo(amShell, 4); GiveAmmo(amCell, 20); GiveAmmo(amMisl, 1);
        end;
      pkShotgun: begin GiveWeapon(wpShotgun, amShell, 8); Sound := 'DSWPNUP'; end;
      pkSuperShotgun: begin GiveWeapon(wpSuperShotgun, amShell, 8); Sound := 'DSWPNUP'; end;
      pkChaingun: begin GiveWeapon(wpChaingun, amClip, 20); Sound := 'DSWPNUP'; end;
      pkRocketLauncher: begin GiveWeapon(wpMissile, amMisl, 2); Sound := 'DSWPNUP'; end;
      pkPlasma: begin GiveWeapon(wpPlasma, amCell, 40); Sound := 'DSWPNUP'; end;
      pkBFG: begin GiveWeapon(wpBfg, amCell, 40); Sound := 'DSWPNUP'; end;
      pkChainsaw: begin GiveWeapon(wpChainsaw, amNoAmmo, 0); Sound := 'DSWPNUP'; end;
      else Picked := false;
    end;
    if Picked then
    begin
      if P in [pkStimpack, pkMedikit, pkHealthBonus, pkArmorBonus, pkArmorGreen, pkArmorBlue, pkSoulsphere,
        pkMegasphere, pkBerserk, pkInvulnerability, pkInvisibility, pkRadSuit, pkComputerMap, pkLightAmp] then
        Inc(Player.Items);
      ShowMessage(Msg);
      FSounds.Play(Sound);
      Player.BonusFlash := Min(1, Player.BonusFlash + 0.5);
      A.Removed := true;
    end;
  end;
end;

procedure TDoomWorld.CheckCrossings;
var
  I: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  T: Single;
  OldSide: Integer;
begin
  if (FOldPlayerX = Player.X) and (FOldPlayerY = Player.Y) then Exit;
  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    if L.Special = 0 then Continue;
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if SegmentsIntersect(FOldPlayerX, FOldPlayerY, Player.X, Player.Y, V1.X, V1.Y, V2.X, V2.Y, T) then
    begin
      OldSide := FMap.PointOnLineSide(FOldPlayerX, FOldPlayerY, I);
      CrossSpecialLine(I, OldSide);
    end;
  end;
end;

procedure TDoomWorld.UseInFront;
var
  I, Best, Side, F, B: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  EX, EY, T, BestT: Single;
  Used: Boolean;
begin
  if FMap = nil then Exit;
  if Player.Dead then
  begin
    { Restart the level. }
    Player.Dead := false;
    LoadMap(FMap.Name, false);
    PlayerTeleported := true;
    PlayerTeleportX := FDoomStartX;
    PlayerTeleportY := FDoomStartY;
    PlayerTeleportZ := Player.Z;
    PlayerTeleportAngle := FDoomStartAngle;
    Exit;
  end;
  EX := Player.X + Cos(DegToRad(Player.Angle)) * 64;
  EY := Player.Y + Sin(DegToRad(Player.Angle)) * 64;
  Used := false;
  repeat
    Best := -1;
    BestT := 2;
    for I := 0 to High(FMap.Linedefs) do
    begin
      L := FMap.Linedefs[I];
      if L.Used then Continue;
      V1 := FMap.Vertices[L.V1];
      V2 := FMap.Vertices[L.V2];
      if SegmentsIntersect(Player.X, Player.Y, EX, EY, V1.X, V1.Y, V2.X, V2.Y, T) then
        if T < BestT then
        begin
          BestT := T;
          Best := I;
        end;
    end;
    if Best < 0 then Break;
    L := FMap.Linedefs[Best];
    Side := FMap.PointOnLineSide(Player.X, Player.Y, Best);
    if L.Special <> 0 then
    begin
      UseSpecialLine(Best, Side, false);
      Used := true;
      Break;
    end;
    F := L.FrontSector;
    B := L.BackSector;
    if (F < 0) or (B < 0) or
       (Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight) <=
        Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight)) then
    begin
      FSounds.Play('DSNOWAY');
      Used := true;
      Break;
    end;
    { Passable line without special: look further, marking it visited. }
    FMap.Linedefs[Best].Used := true;
  until false;
  for I := 0 to High(FMap.Linedefs) do
    FMap.Linedefs[I].Used := false;
  if not Used then
    FSounds.Play('DSNOWAY');
end;

function TDoomWorld.CheckKey(const Line: Integer; const Key: TDoomKey; const Skull: TDoomKey; const IsDoor: Boolean): Boolean;
var
  Color, What: String;
begin
  Result := (Key in Player.Keys) or (Skull in Player.Keys);
  if Result then Exit;
  case Key of
    keyBlue: Color := 'blue';
    keyYellow: Color := 'yellow';
    else Color := 'red';
  end;
  if IsDoor then What := 'open this door' else What := 'activate this object';
  ShowMessage(Format('You need a %s key to %s', [Color, What]));
  FSounds.Play('DSOOF');
end;

procedure TDoomWorld.ChangeLineButton(const Line: Integer; const Repeatable: Boolean);
var
  N: Integer;
begin
  FGeometry.FlipSwitch(Line);
  if Repeatable then
  begin
    N := Length(FButtons);
    SetLength(FButtons, N + 1);
    FButtons[N].Line := Line;
    FButtons[N].TicsLeft := 35;
  end;
end;

function TDoomWorld.UseSpecialLine(const Line, Side: Integer; const ByMonster: Boolean): Boolean;
begin
  Result := false;
  if (Side <> 0) and not ByMonster then Exit;
  Result := ApplySpecial(Line, acUse, ByMonster);
end;

function TDoomWorld.CrossSpecialLine(const Line, Side: Integer): Boolean;
begin
  { Teleporters only work from the front side. }
  if (FMap.Linedefs[Line].Special in [39, 97]) and (Side <> 0) then Exit(false);
  Result := ApplySpecial(Line, acCross, false);
end;

function TDoomWorld.ShootSpecialLine(const Line: Integer): Boolean;
begin
  Result := ApplySpecial(Line, acShoot, false);
end;

procedure TDoomWorld.DoDoor(const Sec: Integer; const Open, Close, Blaze: Boolean; const WaitTics: Integer);
var
  M: TSectorMover;
  Existing: TSectorMover;
begin
  Existing := FMap.Sectors[Sec].Mover as TSectorMover;
  if Existing <> nil then
  begin
    if (Existing.Kind = mkDoor) and Open and Close then
    begin
      { Using a moving door reverses it (vanilla behaviour). }
      if Existing.Direction < 0 then
      begin
        Existing.Direction := 1;
        Existing.Target := FMap.LowestCeilingSurrounding(Sec) - 4;
        Existing.HasReturn := true;
        Existing.ReturnTarget := FMap.Sectors[Sec].FloorHeight;
        Existing.Phase := mpMoving;
      end else if Existing.Phase = mpWaiting then
      begin
        Existing.WaitLeft := 0;
      end;
    end;
    Exit;
  end;
  M := TSectorMover.Create(Self, Sec, mkDoor);
  M.MovesCeiling := true;
  if Blaze then M.Speed := DoorSpeed * 4 else M.Speed := DoorSpeed;
  if Open then
  begin
    M.Target := FMap.LowestCeilingSurrounding(Sec) - 4;
    if Blaze then M.StartSound := 'DSBDOPN' else M.StartSound := 'DSDOROPN';
    if Close then
    begin
      M.HasReturn := true;
      M.ReturnTarget := FMap.Sectors[Sec].FloorHeight;
      M.WaitTics := WaitTics;
    end;
  end else
  begin
    M.Target := FMap.Sectors[Sec].FloorHeight;
    if Blaze then M.StartSound := 'DSBDCLS' else M.StartSound := 'DSDORCLS';
    if Close and (WaitTics > 0) then
    begin
      { Close, wait, reopen (type 16 / 76). }
      M.HasReturn := true;
      M.ReturnTarget := FMap.Sectors[Sec].CeilingHeight;
      M.WaitTics := WaitTics;
    end;
  end;
  if M.Target = FMap.Sectors[Sec].CeilingHeight then
  begin
    FreeAndNil(M);
    Exit;
  end;
  FMovers.Add(M);
  M.Start;
end;

procedure TDoomWorld.DoLift(const Sec: Integer; const Blaze: Boolean; const Perpetual: Boolean);
var
  M: TSectorMover;
  Low: Single;
begin
  if FMap.Sectors[Sec].Mover <> nil then Exit;
  Low := FMap.LowestFloorSurrounding(Sec);
  if Low > FMap.Sectors[Sec].FloorHeight then Low := FMap.Sectors[Sec].FloorHeight;
  M := TSectorMover.Create(Self, Sec, mkLift);
  M.MovesCeiling := false;
  if Blaze then M.Speed := PlatSpeed * 2 else M.Speed := PlatSpeed;
  M.Target := Low;
  M.HasReturn := true;
  M.ReturnTarget := FMap.Sectors[Sec].FloorHeight;
  M.WaitTics := PlatWait;
  M.Perpetual := Perpetual;
  if Perpetual then
  begin
    M.Target := Low;
    M.ReturnTarget := FMap.HighestFloorSurrounding(Sec);
    if M.ReturnTarget > FMap.Sectors[Sec].CeilingHeight then M.ReturnTarget := FMap.Sectors[Sec].CeilingHeight;
  end;
  M.StartSound := 'DSPSTART';
  M.StopSound := 'DSPSTOP';
  if (M.Target = FMap.Sectors[Sec].FloorHeight) and not Perpetual then
  begin
    FreeAndNil(M);
    Exit;
  end;
  FMovers.Add(M);
  M.Start;
end;

procedure TDoomWorld.DoFloor(const Sec: Integer; const Target: Single; const Speed: Single;
  const ChangeTexFrom: Integer);
var
  M: TSectorMover;
begin
  if FMap.Sectors[Sec].Mover <> nil then Exit;
  if Target = FMap.Sectors[Sec].FloorHeight then
  begin
    if ChangeTexFrom >= 0 then
    begin
      FMap.Sectors[Sec].FloorTex := FMap.Sectors[ChangeTexFrom].FloorTex;
      FGeometry.SectorChanged(Sec);
    end;
    Exit;
  end;
  M := TSectorMover.Create(Self, Sec, mkFloor);
  M.MovesCeiling := false;
  M.Speed := Speed;
  M.Target := Target;
  M.MoveSound := 'DSSTNMOV';
  M.StopSound := 'DSPSTOP';
  if ChangeTexFrom >= 0 then
    M.NewFloorTex := FMap.Sectors[ChangeTexFrom].FloorTex;
  FMovers.Add(M);
  M.Start;
end;

procedure TDoomWorld.DoCeiling(const Sec: Integer; const Target: Single; const Speed: Single; const Crusher: Boolean);
var
  M: TSectorMover;
begin
  if FMap.Sectors[Sec].Mover <> nil then Exit;
  if (Target = FMap.Sectors[Sec].CeilingHeight) and not Crusher then Exit;
  if Crusher then
    M := TSectorMover.Create(Self, Sec, mkCrusher)
  else
    M := TSectorMover.Create(Self, Sec, mkCeiling);
  M.MovesCeiling := true;
  M.Speed := Speed;
  M.Target := Target;
  M.MoveSound := 'DSSTNMOV';
  M.StopSound := 'DSPSTOP';
  if Crusher then
  begin
    M.Perpetual := true;
    M.HasReturn := true;
    M.ReturnTarget := FMap.Sectors[Sec].CeilingHeight;
    M.WaitTics := 1;
  end;
  FMovers.Add(M);
  M.Start;
end;

procedure TDoomWorld.DoStairs(const Line: Integer; const StepSize: Integer; const Speed: Single);
var
  Tag, S, Sec, Next, L, Back, Guard: Integer;
  Height: Single;
  Tex: String;
begin
  Tag := FMap.Linedefs[Line].Tag;
  S := -1;
  repeat
    S := FMap.FindSectorFromTag(Tag, S);
    if S < 0 then Break;
    if FMap.Sectors[S].Mover <> nil then Continue;
    Tex := FMap.Sectors[S].FloorTex;
    Height := FMap.Sectors[S].FloorHeight + StepSize;
    DoFloor(S, Height, Speed);
    Sec := S;
    Guard := 0;
    repeat
      Next := -1;
      for L in FMap.Sectors[Sec].Lines do
        if ((FMap.Linedefs[L].Flags and ML_TWOSIDED) <> 0) and (FMap.Linedefs[L].FrontSector = Sec) then
        begin
          Back := FMap.Linedefs[L].BackSector;
          if (Back >= 0) and (FMap.Sectors[Back].FloorTex = Tex) and (FMap.Sectors[Back].Mover = nil) then
          begin
            Next := Back;
            Break;
          end;
        end;
      if Next >= 0 then
      begin
        Height := Height + StepSize;
        DoFloor(Next, Height, Speed);
        Sec := Next;
      end;
      Inc(Guard);
    until (Next < 0) or (Guard > 200);
  until false;
end;

procedure TDoomWorld.DoLight(const Sec: Integer; const Level: Integer);
begin
  if FMap.Sectors[Sec].LightLevel <> Level then
  begin
    FMap.Sectors[Sec].LightLevel := Level;
    FMap.Sectors[Sec].OrigLight := Level;
    FGeometry.SectorChanged(Sec);
  end;
end;

procedure TDoomWorld.StopPlats(const Tag: Integer);
var
  M: TSectorMover;
begin
  for M in FMovers do
    if (M.Kind in [mkLift, mkCrusher]) and (FMap.Sectors[M.Sector].Tag = Tag) then
      M.Phase := mpDone;
end;

procedure TDoomWorld.DoTeleport(const Line: Integer);
var
  Tag, S: Integer;
  A, Fog: TDoomActor;
begin
  Tag := FMap.Linedefs[Line].Tag;
  S := -1;
  repeat
    S := FMap.FindSectorFromTag(Tag, S);
    if S < 0 then Break;
    for A in FActors do
      if (A.Info^.Kind = tkTeleportDest) and (A.Sector = S) then
      begin
        { Fog at the departure point. }
        Fog := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekTeleFog]);
        Fog.State := asEffect;
        Fog.Bright := true;
        Fog.DoomX := Player.X; Fog.DoomY := Player.Y; Fog.DoomZ := Player.Z;
        Fog.Sector := Player.Sector;
        Fog.Collides := false; Fog.Pickable := false;
        Fog.SetLight(255);
        Fog.PlaySequence('ABABCDEFGHIJ', 6, false);
        Fog.UpdateTransform;
        FActors.Add(Fog);
        FItems.Add(Fog);
        FSounds.PlayAt('DSTELEPT', Fog);

        PlayerTeleported := true;
        PlayerTeleportX := A.DoomX;
        PlayerTeleportY := A.DoomY;
        PlayerTeleportZ := FMap.Sectors[S].FloorHeight;
        PlayerTeleportAngle := A.Angle;
        Player.X := A.DoomX;
        Player.Y := A.DoomY;
        Player.Z := PlayerTeleportZ;
        Player.Sector := S;
        FOldPlayerX := Player.X;
        FOldPlayerY := Player.Y;

        Fog := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekTeleFog]);
        Fog.State := asEffect;
        Fog.Bright := true;
        Fog.DoomX := A.DoomX + Cos(DegToRad(A.Angle)) * 20;
        Fog.DoomY := A.DoomY + Sin(DegToRad(A.Angle)) * 20;
        Fog.DoomZ := PlayerTeleportZ;
        Fog.Sector := S;
        Fog.Collides := false; Fog.Pickable := false;
        Fog.SetLight(255);
        Fog.PlaySequence('ABABCDEFGHIJ', 6, false);
        Fog.UpdateTransform;
        FActors.Add(Fog);
        FItems.Add(Fog);
        FSounds.Play('DSTELEPT');
        Exit;
      end;
  until false;
end;

function TDoomWorld.ApplySpecial(const Line: Integer; const Activation: TActivation; const ByMonster: Boolean): Boolean;
var
  Special, Tag, Back, Front, S: Integer;
  Repeatable, Done: Boolean;

  { Iterate tagged sectors: returns next or -1. }
  function NextTagged(var Iter: Integer): Boolean;
  begin
    Iter := FMap.FindSectorFromTag(Tag, Iter);
    Result := Iter >= 0;
  end;

  procedure TaggedDoors(const Open, Close, Blaze: Boolean; const Wait: Integer);
  var
    I: Integer;
  begin
    I := -1;
    while NextTagged(I) do DoDoor(I, Open, Close, Blaze, Wait);
  end;

  procedure TaggedLifts(const Blaze, Perpetual: Boolean);
  var
    I: Integer;
  begin
    I := -1;
    while NextTagged(I) do DoLift(I, Blaze, Perpetual);
  end;

  procedure SwitchSound;
  begin
    if (Activation = acUse) and not ByMonster then
      FSounds.PlayAt('DSSWTCHN', FPlayerEmitter);
  end;

  function ManualDoor(const Blaze, StayOpen: Boolean): Boolean;
  begin
    Result := false;
    if Back < 0 then Exit;
    DoDoor(Back, true, not StayOpen, Blaze, DoorWait);
    Result := true;
  end;

begin
  Result := false;
  Special := FMap.Linedefs[Line].Special;
  Tag := FMap.Linedefs[Line].Tag;
  Back := FMap.Linedefs[Line].BackSector;
  Front := FMap.Linedefs[Line].FrontSector;
  if Special = 0 then Exit;
  Done := false;
  Repeatable := false;

  { Monsters only open plain doors. }
  if ByMonster and not (Special in [1, 117, 2, 4, 108, 90, 105, 86, 106, 39, 97, 125, 126]) then Exit;

  case Activation of
    acUse:
      case Special of
        1: Done := ManualDoor(false, false);
        117: Done := ManualDoor(true, false);
        31: begin Done := ManualDoor(false, true); if Done then FMap.Linedefs[Line].Special := 0; end;
        118: begin Done := ManualDoor(true, true); if Done then FMap.Linedefs[Line].Special := 0; end;
        26: if CheckKey(Line, keyBlue, skullBlue, true) then Done := ManualDoor(false, false) else Exit(true);
        27: if CheckKey(Line, keyYellow, skullYellow, true) then Done := ManualDoor(false, false) else Exit(true);
        28: if CheckKey(Line, keyRed, skullRed, true) then Done := ManualDoor(false, false) else Exit(true);
        32: if CheckKey(Line, keyBlue, skullBlue, true) then begin Done := ManualDoor(false, true); FMap.Linedefs[Line].Special := 0; end else Exit(true);
        33: if CheckKey(Line, keyRed, skullRed, true) then begin Done := ManualDoor(false, true); FMap.Linedefs[Line].Special := 0; end else Exit(true);
        34: if CheckKey(Line, keyYellow, skullYellow, true) then begin Done := ManualDoor(false, true); FMap.Linedefs[Line].Special := 0; end else Exit(true);

        { S1 }
        29: begin TaggedDoors(true, true, false, DoorWait); Done := true; end;
        50: begin TaggedDoors(false, false, false, 0); Done := true; end;
        103: begin TaggedDoors(true, false, false, 0); Done := true; end;
        111: begin TaggedDoors(true, true, true, DoorWait); Done := true; end;
        112: begin TaggedDoors(true, false, true, 0); Done := true; end;
        113: begin TaggedDoors(false, false, true, 0); Done := true; end;
        133: if CheckKey(Line, keyBlue, skullBlue, false) then begin TaggedDoors(true, false, true, 0); Done := true; end else Exit(true);
        135: if CheckKey(Line, keyRed, skullRed, false) then begin TaggedDoors(true, false, true, 0); Done := true; end else Exit(true);
        137: if CheckKey(Line, keyYellow, skullYellow, false) then begin TaggedDoors(true, false, true, 0); Done := true; end else Exit(true);
        { SR }
        63: begin TaggedDoors(true, true, false, DoorWait); Done := true; Repeatable := true; end;
        42: begin TaggedDoors(false, false, false, 0); Done := true; Repeatable := true; end;
        61: begin TaggedDoors(true, false, false, 0); Done := true; Repeatable := true; end;
        114: begin TaggedDoors(true, true, true, DoorWait); Done := true; Repeatable := true; end;
        115: begin TaggedDoors(true, false, true, 0); Done := true; Repeatable := true; end;
        116: begin TaggedDoors(false, false, true, 0); Done := true; Repeatable := true; end;
        99: if CheckKey(Line, keyBlue, skullBlue, false) then begin TaggedDoors(true, false, true, 0); Done := true; Repeatable := true; end else Exit(true);
        134: if CheckKey(Line, keyRed, skullRed, false) then begin TaggedDoors(true, false, true, 0); Done := true; Repeatable := true; end else Exit(true);
        136: if CheckKey(Line, keyYellow, skullYellow, false) then begin TaggedDoors(true, false, true, 0); Done := true; Repeatable := true; end else Exit(true);

        { Lifts }
        21: begin TaggedLifts(false, false); Done := true; end;
        62: begin TaggedLifts(false, false); Done := true; Repeatable := true; end;
        122: begin TaggedLifts(true, false); Done := true; end;
        123: begin TaggedLifts(true, false); Done := true; Repeatable := true; end;

        { Floors S1 }
        18: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed); Done := true; end;
        23: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed); Done := true; end;
        71: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S) + 8, FloorSpeed * 4); Done := true; end;
        55: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S) - 8, FloorSpeed); Done := true; end;
        101: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S), FloorSpeed); Done := true; end;
        102: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S), FloorSpeed); Done := true; end;
        131: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed * 4); Done := true; end;
        140: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 512, FloorSpeed); Done := true; end;
        14: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 32, FloorSpeed / 2, Front); Done := true; end;
        15: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 24, FloorSpeed / 2, Front); Done := true; end;
        20: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed / 2, Front); Done := true; end;
        { Floors SR }
        60: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed); Done := true; Repeatable := true; end;
        64: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S), FloorSpeed); Done := true; Repeatable := true; end;
        65: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S) - 8, FloorSpeed); Done := true; Repeatable := true; end;
        69: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed); Done := true; Repeatable := true; end;
        70: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S) + 8, FloorSpeed * 4); Done := true; Repeatable := true; end;
        132: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed * 4); Done := true; Repeatable := true; end;
        45: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S), FloorSpeed); Done := true; Repeatable := true; end;
        66: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 24, FloorSpeed / 2, Front); Done := true; Repeatable := true; end;
        67: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 32, FloorSpeed / 2, Front); Done := true; Repeatable := true; end;
        68: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed / 2, Front); Done := true; Repeatable := true; end;

        { Ceilings }
        41: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight, CeilSpeed, false); Done := true; end;
        43: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight, CeilSpeed, false); Done := true; Repeatable := true; end;
        49: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight + 8, CeilSpeed, true); Done := true; end;

        { Stairs }
        7: begin DoStairs(Line, 8, FloorSpeed / 4); Done := true; end;
        127: begin DoStairs(Line, 16, FloorSpeed * 4); Done := true; end;

        { Lights }
        138: begin S := -1; while NextTagged(S) do DoLight(S, 255); Done := true; Repeatable := true; end;
        139: begin S := -1; while NextTagged(S) do DoLight(S, 35); Done := true; Repeatable := true; end;

        { Exits }
        11: begin FSounds.Play('DSSWTCHX'); FExitRequested := true; FSecretExit := false; Exit(true); end;
        51: begin FSounds.Play('DSSWTCHX'); FExitRequested := true; FSecretExit := true; Exit(true); end;

        { Donut: approximate as lowering the tagged pillar to the surrounding floor. }
        9: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed / 2); Done := true; end;
      end;

    acCross:
      case Special of
        2: begin TaggedDoors(true, false, false, 0); Done := true; end;
        3: begin TaggedDoors(false, false, false, 0); Done := true; end;
        4: begin TaggedDoors(true, true, false, DoorWait); Done := true; end;
        16: begin TaggedDoors(false, true, false, 30 * TicRate); Done := true; end;
        108: begin TaggedDoors(true, true, true, DoorWait); Done := true; end;
        109: begin TaggedDoors(true, false, true, 0); Done := true; end;
        110: begin TaggedDoors(false, false, true, 0); Done := true; end;
        75: begin TaggedDoors(false, false, false, 0); Done := true; Repeatable := true; end;
        76: begin TaggedDoors(false, true, false, 30 * TicRate); Done := true; Repeatable := true; end;
        86: begin TaggedDoors(true, false, false, 0); Done := true; Repeatable := true; end;
        90: begin TaggedDoors(true, true, false, DoorWait); Done := true; Repeatable := true; end;
        105: begin TaggedDoors(true, true, true, DoorWait); Done := true; Repeatable := true; end;
        106: begin TaggedDoors(true, false, true, 0); Done := true; Repeatable := true; end;
        107: begin TaggedDoors(false, false, true, 0); Done := true; Repeatable := true; end;

        10: begin TaggedLifts(false, false); Done := true; end;
        121: begin TaggedLifts(true, false); Done := true; end;
        88: begin TaggedLifts(false, false); Done := true; Repeatable := true; end;
        120: begin TaggedLifts(true, false); Done := true; Repeatable := true; end;
        53: begin TaggedLifts(false, true); Done := true; end;
        87: begin TaggedLifts(false, true); Done := true; Repeatable := true; end;
        54: begin StopPlats(Tag); Done := true; end;
        89: begin StopPlats(Tag); Done := true; Repeatable := true; end;

        5: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S), FloorSpeed); Done := true; end;
        19: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S), FloorSpeed); Done := true; end;
        22: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed / 2, Front); Done := true; end;
        30, 96: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 64, FloorSpeed); Done := true; Repeatable := Special = 96; end;
        36: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S) + 8, FloorSpeed * 4); Done := true; end;
        37: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed, Front); Done := true; end;
        38: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed); Done := true; end;
        56: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S) - 8, FloorSpeed); Done := true; end;
        58: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 24, FloorSpeed); Done := true; end;
        59: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 24, FloorSpeed, Front); Done := true; end;
        119: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed); Done := true; end;
        130: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed * 4); Done := true; end;
        82: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed); Done := true; Repeatable := true; end;
        83: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S), FloorSpeed); Done := true; Repeatable := true; end;
        84: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed, Front); Done := true; Repeatable := true; end;
        91: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S), FloorSpeed); Done := true; Repeatable := true; end;
        92: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 24, FloorSpeed); Done := true; Repeatable := true; end;
        93: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.Sectors[S].FloorHeight + 24, FloorSpeed, Front); Done := true; Repeatable := true; end;
        94: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S) - 8, FloorSpeed); Done := true; Repeatable := true; end;
        95: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed / 2, Front); Done := true; Repeatable := true; end;
        98: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.HighestFloorSurrounding(S) + 8, FloorSpeed * 4); Done := true; Repeatable := true; end;
        128: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed); Done := true; Repeatable := true; end;
        129: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed * 4); Done := true; Repeatable := true; end;

        40: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.HighestCeilingSurrounding(S), CeilSpeed, false); Done := true; end;
        44: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight + 8, CeilSpeed, false); Done := true; end;
        72: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight + 8, CeilSpeed, false); Done := true; Repeatable := true; end;
        6, 25, 141: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight + 8, CeilSpeed * IfThen(Special = 6, 2, 1), true); Done := true; end;
        73, 77: begin S := -1; while NextTagged(S) do DoCeiling(S, FMap.Sectors[S].FloorHeight + 8, CeilSpeed * IfThen(Special = 77, 2, 1), true); Done := true; Repeatable := true; end;
        74: begin StopPlats(Tag); Done := true; Repeatable := true; end;

        8: begin DoStairs(Line, 8, FloorSpeed / 4); Done := true; end;
        100: begin DoStairs(Line, 16, FloorSpeed * 4); Done := true; end;

        12: begin S := -1; while NextTagged(S) do DoLight(S, FMap.MaxSurroundingLight(S, 0)); Done := true; end;
        13: begin S := -1; while NextTagged(S) do DoLight(S, 255); Done := true; end;
        35: begin S := -1; while NextTagged(S) do DoLight(S, 35); Done := true; end;
        104: begin S := -1; while NextTagged(S) do DoLight(S, FMap.MinSurroundingLight(S, 255)); Done := true; end;
        79: begin S := -1; while NextTagged(S) do DoLight(S, 35); Done := true; Repeatable := true; end;
        80: begin S := -1; while NextTagged(S) do DoLight(S, FMap.MaxSurroundingLight(S, 0)); Done := true; Repeatable := true; end;
        81: begin S := -1; while NextTagged(S) do DoLight(S, 255); Done := true; Repeatable := true; end;
        17: begin S := -1; while NextTagged(S) do FMap.Sectors[S].Special := 2; Done := true; end;

        39: begin if not ByMonster then DoTeleport(Line); Done := true; end;
        97: begin if not ByMonster then DoTeleport(Line); Done := true; Repeatable := true; end;
        125, 126: Exit(false);

        52: begin FExitRequested := true; FSecretExit := false; Exit(true); end;
        124: begin FExitRequested := true; FSecretExit := true; Exit(true); end;
      end;

    acShoot:
      case Special of
        24: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.LowestCeilingSurrounding(S), FloorSpeed); Done := true; end;
        46: begin TaggedDoors(true, false, false, 0); Done := true; Repeatable := true; end;
        47: begin S := -1; while NextTagged(S) do DoFloor(S, FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight), FloorSpeed / 2, Front); Done := true; end;
      end;
  end;

  if not Done then Exit(false);
  Result := true;
  if Activation = acUse then
  begin
    if not (Special in [1, 26, 27, 28, 31, 32, 33, 34, 117, 118]) then
    begin
      SwitchSound;
      ChangeLineButton(Line, Repeatable);
    end;
  end else if Activation = acShoot then
    ChangeLineButton(Line, Repeatable);
  if not Repeatable then
    FMap.Linedefs[Line].Special := 0;
end;

initialization
  InitEffectInfos;
end.
