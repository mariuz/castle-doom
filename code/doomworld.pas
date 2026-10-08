{ The Doom game world on top of the map geometry: things, sector movers
  (doors, lifts, floors, ceilings, stairs), linedef specials (switches,
  walk-over triggers, teleports, exits), pickups, monster AI, projectiles,
  player weapons and damage.

  Everything runs at Doom's 35 tics per second, driven from the view's Update.
  Positions are kept in Doom units/coordinates; the CGE transforms are
  updated from them. }
unit DoomWorld;

interface

uses SysUtils, Classes, Generics.Collections, FpJson,
  CastleVectors, CastleTransform, CastleScene, CastleUtils,
  DoomWad, DoomGraphics, DoomMap, DoomGeometry, DoomThings, DoomActors, DoomSound, DoomDehacked, DoomLighting;

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
    { Doom's damagecount / bonuscount: the red and gold palette flashes
      (ST_doPaletteStuff), counting down one per tic. }
    DamageCount, BonusCount: Integer;
    Kills, Items, Secrets: Integer;
    TotalKills, TotalItems, TotalSecrets: Integer;
    BerserkTics, InvulnerableTics, InvisibleTics, RadSuitTics, LightAmpTics: Integer;
    { The god mode cheat (Doom's CF_GODMODE): no damage, but unlike the
      invulnerability sphere no inverted colormap. }
    GodMode: Boolean;
    { Feet position and facing (Doom coordinates / degrees). }
    X, Y, Z: Single;
    Angle: Single;
    Sector: Integer;
    { Weapon animation. }
    AttackTics: Integer;
    WeaponFrame: Char;
    FlashFrame: Char;
    { The gun flash's extra light (A_Light1 / A_Light2), 0..2 light steps. }
    ExtraLight: Integer;
    Refire: Boolean;
    { Weapon change (A_Lower / A_Raise): 0 ready, 1 lowering, 2 raising;
      the offset below WEAPONTOP in Doom pixels (0 up .. 96 out of view);
      the weapon that comes up once the old one is down. }
    WeaponSwitch: Integer;
    WeaponOffset: Single;
    PendingWeapon: TWeapon;
    { Status bar face: tics left for the "ouch" / "evil grin" expressions. }
    FaceTics: Integer;
    FaceState: Integer;
  end;

  TDoomWorld = class;

  { Projectiles and visual effects spawned by the world (not in THINGS). }
  TEffectKind = (ekPuff, ekBlood, ekTeleFog, ekBarrelExplosion,
    ekBal1, ekBal2, ekBal7, ekRocket, ekRevenantRocket, ekFatShot, ekArachPlasma,
    ekPlasmaBall, ekBfgBall, ekVileFire,
    { Icon of Sin: the spawn cube, its fire, the explosions when the brain dies. }
    ekSpawnShot, ekSpawnFire, ekBrainExplosion);

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
    { Time spent per stage (seconds), logged as "Perf:" every 10 s. }
    FPerf: array [0..7] of Double;
    FPerfTics, FPerfFrames: Integer;
    FPerfClock: Double;
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
    FBfgCountdown: Integer;
    { Icon of Sin: next spawn spot, A_BrainSpit's "easy" toggle, tics left
      until the dead brain ends the level, and where it was. }
    FBrainTargetIndex: Integer;
    FBrainEasy: Boolean;
    FBrainDeathTics: Integer;
    FBrainX, FBrainY: Single;
    { Sector heard the player fire (Doom's sector_t.soundtarget). }
    FSectorSound: array of Boolean;
    { Lines whose special monsters may trigger by walking over them. }
    FMonsterCrossLines: array of Integer;
    FDynamic: array of Boolean;
    procedure ComputeDynamicSectors;
    procedure SpawnThings;
    { LoadMap, optionally restoring a saved game (State <> nil). }
    procedure LoadMapCore(const MapName: String; const KeepInventory: Boolean; const State: TJSONObject);
    procedure RestoreMapState(const State: TJSONObject);
    procedure RestoreDynamicState(const State: TJSONObject);
    procedure RunTic;
    procedure TicActors;
    procedure TicMonster(const A: TDoomActor);
    procedure TicMissile(const A: TDoomActor);
    procedure TicMovers;
    procedure TicLights;
    procedure TicPlayer;
    procedure RevealAutomap;
    procedure TicButtons;
    procedure CheckPickups;
    procedure CheckCrossings;
    function TryMove2D(const A: TDoomActor; const NX, NY: Single; out BlockedByLine: Integer): Boolean;
    function LineBlocksMissile(const Line: Integer; const X, Y, Z: Single): Boolean;
    function SightClear(const X1, Y1, X2, Y2: Single): Boolean;
    { P_CheckSight: REJECT, then the 2D line plus the vertical window through
      every opening on the way, from an eye at EyeZ to a target from Z2 to
      Z2 + H2. }
    function CheckSight(const X1, Y1, EyeZ: Single; const S1: Integer;
      const X2, Y2, Z2, H2: Single; const S2: Integer): Boolean;
    { Monster A can see the player / its current target. }
    function SightToPlayer(const A: TDoomActor): Boolean;
    function SightToTarget(const A: TDoomActor): Boolean;
    { A_Look: True when an idle monster notices the player. }
    function MonsterLook(const A: TDoomActor; out Reason: String): Boolean;
    procedure MonsterAttack(const A: TDoomActor);
    procedure MonsterHitscan(const A: TDoomActor);
    { P_LineAttack in Doom units: from (X, Y, Z) along Angle (degrees) with
      Slope (height per unit of distance) up to Range. Returns the nearest
      body hit (a shootable actor, or the player when HitPlayer) or, when
      none comes first, the wall point (HitWall). Shooter is never hit. }
    procedure TraceLineAttack(const Shooter: TDoomActor; const X, Y, Z, Angle, Slope, Range: Single;
      out HitActor: TDoomActor; out HitPlayer, HitWall: Boolean; out HX, HY, HZ: Single);
    procedure SpawnPuff(const X, Y, Z: Single);
    procedure SpawnMissile(const A: TDoomActor);
    procedure SpawnPlayerMissile(const Kind: TEffectKind);
    procedure BfgSpray(const X, Y: Single);
    procedure ExplodeMissile(const A: TDoomActor; const X, Y, Z: Single);
    procedure KillActor(const A: TDoomActor; const Killer: TDoomActor = nil; const ByPlayer: Boolean = true);
    procedure BossDeath(const A: TDoomActor);
    procedure NightmareRespawn(const A: TDoomActor);
    procedure PerfLog;
    procedure BrainAwake(const A: TDoomActor);
    procedure TicBrainShooter(const A: TDoomActor);
    procedure BrainSpit(const A: TDoomActor);
    procedure TicSpawnCube(const A: TDoomActor);
    procedure StartBrainDeath(const A: TDoomActor);
    procedure TicBrainDeath;
    function SpawnEffectAt(const Kind: TEffectKind; const X, Y, Z: Single; const Tics: Integer): TDoomActor;
    function SpawnFog(const X, Y, Z: Single; const Sec: Integer): TDoomActor;
    function SpawnMonster(const TypeNum: Integer; const X, Y, Z: Single): TDoomActor;
    procedure StartSkullCharge(const A: TDoomActor);
    procedure StopSkullCharge(const A: TDoomActor);
    procedure TicCharge(const A: TDoomActor);
    procedure PainShootSkull(const A: TDoomActor; const AngleDeg: Single);
    function CanRaise(const Num: Integer): Boolean;
    function VileTryRaise(const A: TDoomActor): Boolean;
    procedure VileStartAttack(const A: TDoomActor);
    procedure VileAttack(const A: TDoomActor);
    procedure FollowVileFire(const F: TDoomActor);
    function SameSpecies(const A, B: TDoomActor): Boolean;
    function TargetAlive(const A: TDoomActor): Boolean;
    procedure TargetPosition(const A: TDoomActor; out TX, TY, TZ, TRadius: Single);
    function FloorRaiseToTexture(const Sec: Integer): Single;
    procedure ExplodeBarrel(const A: TDoomActor);
    procedure RadiusDamage(const X, Y, Z: Single; const Radius, Damage: Integer; const Source: TDoomActor);
    { A body bullets and autoaim can hit (MF_SHOOTABLE and alive). }
    function Shootable(const O: TDoomActor): Boolean;
    { P_AimLineAttack: from (X, Y, Z) along Angle up to Range, the first
      shootable body seen through the openings on the way, within the
      player's vertical view (slopes -100/160 .. 100/160). Returns the slope
      to the middle of its visible part; Target nil (and 0) if none. }
    function AimLineAttack(const Shooter: TDoomActor; const X, Y, Z, Angle, Range: Single;
      out Target: TDoomActor): Single;
    { The player's angle (degrees) and the camera's pitch as a slope. }
    procedure PlayerLook(out Angle, Slope: Single);
    { P_BulletSlope / P_SpawnPlayerMissile: autoaim straight ahead, then
      5.625 degrees to each side. Angle is the angle that found a target
      (the player's angle if none); without a target Slope follows the
      camera's pitch (0 without mouse look, like Doom). }
    function PlayerAim(const Range: Single; out Angle, Slope: Single): Boolean;
    { P_LineAttack for the player: trace, damage or puff, and shoot the
      gun-activated lines the shot crossed. Returns the body hit. }
    function PlayerLineAttack(const Angle, Slope, Range: Single; const Damage: Integer): TDoomActor;
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
    { EV_Teleport for a monster; false when there is no free destination. }
    function TeleportActor(const A: TDoomActor; const Line: Integer): Boolean;
    { P_CrossSpecialLine for a monster that moved from (OldX, OldY). }
    procedure MonsterCrossLines(const A: TDoomActor; const OldX, OldY: Single);
    procedure StopPlats(const Tag: Integer);
    function CheckKey(const Line: Integer; const Key: TDoomKey; const Skull: TDoomKey; const IsDoor: Boolean): Boolean;
    procedure ChangeLineButton(const Line: Integer; const Repeatable: Boolean);
  public
    { Log every player shot (aim, slope, what it hit): "Shot:" lines. }
    DebugShots: Boolean;
    Player: TPlayerState;
    { Set when the player should be moved by the view (teleport / spawn). }
    PlayerTeleported: Boolean;
    PlayerTeleportX, PlayerTeleportY, PlayerTeleportZ, PlayerTeleportAngle: Single;
    { Set when the player just took damage (view shakes/flashes). }
    LastDamage: Integer;
    { Upward distance the player still has to be thrown (Arch-vile blast);
      the view consumes it, gravity brings the player down. }
    PlayerKnockUp: Single;
    { Skill level, Doom's gameskill: 0 "I'm too young to die" .. 4 "Nightmare!".
      Set before LoadMap (things are spawned by it); saved with the game. }
    Skill: Integer;
    { The WAD's BEX strings (pickup and door messages); may be nil. Not owned. }
    Strings: TDoomStrings;

    constructor Create(const AWad: TDoomWad; const AGraphics: TDoomGraphics;
      const ASounds: TDoomSounds; const AItems: TCastleRootTransform);
    destructor Destroy; override;

    procedure LoadMap(const MapName: String; const KeepInventory: Boolean);
    { The whole level state as JSON (caller owns it); see doomworld_save.inc. }
    function SaveState: TJSONObject;
    { Rebuild the saved map and restore everything from SaveState's JSON. }
    procedure LoadState(const State: TJSONObject);
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
    { Start lowering the current weapon to bring up W (P_SetPsprite S_LOWER). }
    procedure ChangeWeapon(const W: TWeapon);
    procedure NextWeapon(const Delta: Integer);
    procedure ShowMessage(const Msg: String);
    { BEX string Key, or Default without one. }
    function Text(const Key, Default: String): String;
    procedure DamagePlayer(const Damage: Integer; const FromActor: TDoomActor);
    { Hurt a monster or barrel. ByPlayer: the player did it (monster turns on
      the player); otherwise Attacker (a monster) becomes its new target,
      nil Attacker means environmental damage (crusher, barrel) with no retarget. }
    procedure DamageActor(const A: TDoomActor; const Damage: Integer; const HitX, HitY, HitZ: Single;
      const Attacker: TDoomActor = nil; const ByPlayer: Boolean = true);
    { Debug: every awake monster turns on the nearest other monster. }
    procedure DebugInfight;
    { Debug: kill every monster (exercises boss-death triggers). }
    procedure DebugKillAll;
    { Debug: log the 2D and 3D line of sight from every monster within 2500
      units to the player. }
    procedure DebugSight;
    { Debug: god mode (no damage, Player.GodMode). }
    procedure DebugGod;
    { Debug: spawn an awake monster of this THINGS type Distance units in
      front of the player. }
    function DebugSpawn(const TypeNum: Integer; const Distance: Single): TDoomActor;
    procedure ResetPlayer;
    { Cheat for testing: all weapons, full ammo, keys. }
    procedure GiveAll;
    function AmmoFor(const W: TWeapon): TAmmoType;
    { ST_doPaletteStuff: which PLAYPAL palette the screen shows now (0 none,
      1..8 damage / berserk red, 9..12 bonus gold, 13 radiation suit). }
    function PaletteIndex: Integer;
    { R_SetupFrame's fixedcolormap: InverseColormap during invulnerability,
      colormap 1 with the light amplification visor (both blink in their
      last 4 seconds), NoFixedColormap otherwise. }
    function FixedColormap: Integer;
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

uses Math, CastleLog, CastleStringUtils, CastleBehaviors, CastleTimeUtils;

const
  DoorSpeed = 2;
  DoorWait = 150;
  PlatSpeed = 4;
  PlatWait = 105;
  FloorSpeed = 1;
  CeilSpeed = 1;
  ManualDoorSpecials: array [0..9] of Integer = (1, 26, 27, 28, 31, 32, 33, 34, 117, 118);
  { P_CrossSpecialLine: the walk-over specials a monster can set off (door
    raise, two lifts, teleporters and the monster-only teleporters). }
  MonsterCrossSpecials = [4, 10, 39, 88, 97, 125, 126];

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
  Effect(ekVileFire, 'FIRE', 'ABCDEFGH', 3);
  Effect(ekSpawnShot, 'BOSF', 'ABCD', 3);
  EffectInfos[ekSpawnShot].Speed := 10;
  EffectInfos[ekSpawnShot].Radius := 6;
  EffectInfos[ekSpawnShot].Height := 32;
  Effect(ekSpawnFire, 'FIRE', 'ABCDEFGH', 4);
  Effect(ekBrainExplosion, 'MISL', 'BCD', 10);
  Missile(ekBal1, 'BAL1', 6, 10, 3, 8, 'AB', 'CDE', 'BAL1', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekBal2, 'BAL2', 6, 10, 5, 8, 'AB', 'CDE', 'BAL2', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekBal7, 'BAL7', 6, 15, 8, 8, 'AB', 'CDE', 'BAL7', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekRocket, 'MISL', 11, 20, 20, 8, 'A', 'BCD', 'MISL', 'DSRLAUNC', 'DSBAREXP');
  Missile(ekRevenantRocket, 'FATB', 11, 10, 10, 8, 'AB', 'ABC', 'FBXP', 'DSSKEATK', 'DSBAREXP');
  Missile(ekFatShot, 'MANF', 6, 20, 8, 8, 'AB', 'BCD', 'MISL', 'DSFIRSHT', 'DSFIRXPL');
  Missile(ekArachPlasma, 'APLS', 13, 25, 5, 8, 'AB', 'ABCDE', 'APBX', 'DSPLASMA', 'DSFIRXPL');
  { The player's projectiles (info.c: MT_PLASMA, MT_BFG). }
  Missile(ekPlasmaBall, 'PLSS', 13, 25, 5, 8, 'AB', 'ABCDE', 'PLSE', 'DSPLASMA', 'DSFIRXPL');
  Missile(ekBfgBall, 'BFS1', 13, 25, 100, 8, 'AB', 'ABCDEF', 'BFE1', 'DSBFG', 'DSRXPLOD');
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
                World.DamageActor(A, 10, A.DoomX, A.DoomY, A.DoomZ + 32, nil, false);
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
  Skill := 2;
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

procedure TDoomWorld.GiveAll;
var
  A: TAmmoType;
begin
  Player.Weapons := [wpFist, wpChainsaw, wpPistol, wpShotgun, wpSuperShotgun, wpChaingun, wpMissile, wpPlasma, wpBfg];
  Player.MaxAmmo[amClip] := 400; Player.MaxAmmo[amShell] := 100;
  Player.MaxAmmo[amCell] := 600; Player.MaxAmmo[amMisl] := 100;
  for A := amClip to amMisl do Player.Ammo[A] := Player.MaxAmmo[A];
  Player.Keys := [keyBlue, keyYellow, keyRed, skullBlue, skullYellow, skullRed];
  Player.Health := 200;
  Player.Armor := 200;
  Player.ArmorType := 2;
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
  SkillFlag: Integer;
begin
  FHaveStart := false;
  N := 0;
  { G_InitNew / P_SpawnMapThing: which THINGS flag the skill uses. }
  case Skill of
    0, 1: SkillFlag := MTF_EASY;
    2: SkillFlag := MTF_NORMAL;
    else SkillFlag := MTF_HARD;
  end;
  Player.TotalKills := 0;
  Player.TotalItems := 0;
  Player.TotalSecrets := 0;
  for I := 0 to High(FMap.Sectors) do
    if FMap.Sectors[I].Special = 9 then Inc(Player.TotalSecrets);
  for I := 0 to High(FMap.Things) do
  begin
    T := FMap.Things[I];
    if (T.Flags and MTF_NOTSINGLE) <> 0 then Continue;
    if (T.Flags and SkillFlag) = 0 then Continue;
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
    A.SpawnX := T.X;
    A.SpawnY := T.Y;
    A.SpawnAngle := T.Angle;
    A.Sector := Sec;
    A.MapFlags := T.Flags;
    if Info^.Hanging then
      A.DoomZ := FMap.Sectors[Sec].CeilingHeight - Info^.Height
    else
      A.DoomZ := FMap.Sectors[Sec].FloorHeight;
    if Info^.Kind in [tkTeleportDest, tkBossSpot] then
      A.Scene.Exists := false;
    if Info^.Num = 2035 then
      A.Health := 20; { barrel }
    A.Bright := Info^.Pickup in [pkSoulsphere, pkMegasphere, pkInvulnerability, pkInvisibility, pkBerserk, pkRadSuit, pkComputerMap, pkLightAmp];
    A.SetLight(FMap.Sectors[Sec].LightLevel);
    A.UpdateTransform;
    FActors.Add(A);
    FItems.Add(A);
    { The boss brain has no MF_COUNTKILL. }
    if (Info^.Kind = tkMonster) and (Info^.Num <> 88) then Inc(Player.TotalKills);
    if (Info^.Kind = tkPickup) and (Info^.Pickup in [pkStimpack, pkMedikit, pkHealthBonus, pkArmorBonus,
      pkArmorGreen, pkArmorBlue, pkSoulsphere, pkMegasphere, pkBerserk, pkInvulnerability, pkInvisibility,
      pkRadSuit, pkComputerMap, pkLightAmp]) then Inc(Player.TotalItems);
    Inc(N);
  end;
  WritelnLog('Things', '%d things spawned, %d monsters', [N, Player.TotalKills]);
end;

procedure TDoomWorld.LoadMap(const MapName: String; const KeepInventory: Boolean);
begin
  LoadMapCore(MapName, KeepInventory, nil);
end;

procedure TDoomWorld.LoadMapCore(const MapName: String; const KeepInventory: Boolean; const State: TJSONObject);
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
  { Dynamic sectors come from the map's original specials (a saved game may
    have cleared some, but their sectors can still be moving). }
  ComputeDynamicSectors;
  if State <> nil then
    RestoreMapState(State);
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
  { P_SetupPsprites: the weapon comes up from below at the start of a level. }
  Player.PendingWeapon := Player.Weapon;
  Player.WeaponSwitch := 2;
  Player.WeaponOffset := 96;
  Player.AttackTics := 0;
  if State = nil then
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
  FBfgCountdown := 0;
  FBrainTargetIndex := 0;
  FBrainEasy := false;
  FBrainDeathTics := 0;
  SetLength(FSectorSound, 0);
  SetLength(FSectorSound, Length(FMap.Sectors));
  SetLength(FMonsterCrossLines, 0);
  for I := 0 to High(FMap.Linedefs) do
    if FMap.Linedefs[I].Special in MonsterCrossSpecials then
    begin
      SetLength(FMonsterCrossLines, Length(FMonsterCrossLines) + 1);
      FMonsterCrossLines[High(FMonsterCrossLines)] := I;
    end;
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
  if State <> nil then
    RestoreDynamicState(State);
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

function TDoomWorld.Text(const Key, Default: String): String;
begin
  if (Strings <> nil) and (Key <> '') then
    Result := Strings.Get(Key, Default)
  else
    Result := Default;
end;

procedure TDoomWorld.ShowMessage(const Msg: String);
begin
  Player.Message := Msg;
  Player.MessageTics := 4 * TicRate;
  WritelnLog('Message', Msg);
end;

function TDoomWorld.PaletteIndex: Integer;
var
  Cnt, Berserk: Integer;
begin
  Cnt := Player.DamageCount;
  if Player.BerserkTics > 0 then
  begin
    { The berserk red fades over the first 12 * 64 tics (powers[pw_strength]
      counts up in Doom; ours counts down from 60 s). }
    Berserk := 12 - (60 * TicRate - Player.BerserkTics) div 64;
    if Berserk > Cnt then Cnt := Berserk;
  end;
  if Cnt > 0 then
    Result := Min(8, (Cnt + 7) div 8)
  else if Player.BonusCount > 0 then
    Result := 8 + Min(4, (Player.BonusCount + 7) div 8)
  else if (Player.RadSuitTics > 4 * 32) or ((Player.RadSuitTics and 8) <> 0) then
    Result := 13
  else
    Result := 0;
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
  ChangeWeapon(W);
end;

procedure TDoomWorld.ChangeWeapon(const W: TWeapon);
begin
  if (W = Player.Weapon) and (Player.WeaponSwitch <> 1) then Exit;
  Player.PendingWeapon := W;
  Player.WeaponSwitch := 1;
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
  T: TTimerResult;
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
  T := Timer;
  FGeometry.Update(SecondsPassed, CameraPos);
  FGeometry.FlushDirty;
  FPerf[7] := FPerf[7] + TimerSeconds(Timer, T);
  Inc(FPerfFrames);
  FPerfClock := FPerfClock + SecondsPassed;
  if FPerfClock >= 10 then PerfLog;
end;

procedure TDoomWorld.PerfLog;
const
  Names: array [0..7] of String = ('anim', 'movers', 'lights', 'actors', 'pickups+lines', 'player', 'other', 'geometry');
var
  I: Integer;
  S: String;
begin
  S := '';
  for I := 0 to High(FPerf) do
  begin
    S := S + Format(' %s %.2f', [Names[I], FPerf[I] * 1000 / Max(1, FPerfTics)]);
    FPerf[I] := 0;
  end;
  WritelnLog('Perf', '%d tics, %d frames in %.1f s; ms per tic:%s (geometry per tic too)',
    [FPerfTics, FPerfFrames, FPerfClock, S]);
  FPerfTics := 0;
  FPerfFrames := 0;
  FPerfClock := 0;
end;

procedure TDoomWorld.RunTic;
var
  T: TTimerResult;

  procedure Lap(const Index: Integer);
  var
    Now: TTimerResult;
  begin
    Now := Timer;
    FPerf[Index] := FPerf[Index] + TimerSeconds(Now, T);
    T := Now;
  end;

begin
  T := Timer;
  Inc(FTic);
  Inc(FPerfTics);
  FGraphics.AnimationTic(FTic);
  Lap(0);
  TicMovers;
  Lap(1);
  TicLights;
  TicButtons;
  Lap(2);
  TicActors;
  if FBrainDeathTics > 0 then
    TicBrainDeath;
  Lap(3);
  if not Player.Dead then
  begin
    CheckPickups;
    CheckCrossings;
  end;
  Lap(4);
  TicPlayer;
  Lap(5);
  FOldPlayerX := Player.X;
  FOldPlayerY := Player.Y;
  Lap(6);
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
  if Player.DamageCount > 0 then Dec(Player.DamageCount);
  if Player.BonusCount > 0 then Dec(Player.BonusCount);
  if Player.InvulnerableTics > 0 then Dec(Player.InvulnerableTics);
  if Player.InvisibleTics > 0 then Dec(Player.InvisibleTics);
  if Player.RadSuitTics > 0 then Dec(Player.RadSuitTics);
  if Player.LightAmpTics > 0 then Dec(Player.LightAmpTics);
  UpdateWeaponAnimation;
  if FBfgCountdown > 0 then
  begin
    Dec(FBfgCountdown);
    if (FBfgCountdown = 0) and not Player.Dead then
      SpawnPlayerMissile(ekBfgBall);
  end;
  if Player.Dead then Exit;

  Sec := Player.Sector;
  if Sec < 0 then Exit;
  if FTic mod 8 = 0 then RevealAutomap;
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

{ Mark the linedefs of the player's sector and its neighbours as mapped
  (Doom marks the lines it actually rendered; this is a cheap stand-in). }
procedure TDoomWorld.RevealAutomap;
var
  Sec, L, O, L2: Integer;
begin
  Sec := Player.Sector;
  if Sec < 0 then Exit;
  for L in FMap.Sectors[Sec].Lines do
  begin
    FMap.Linedefs[L].Flags := FMap.Linedefs[L].Flags or ML_MAPPED;
    O := FMap.OtherSector(L, Sec);
    if O >= 0 then
      for L2 in FMap.Sectors[O].Lines do
        FMap.Linedefs[L2].Flags := FMap.Linedefs[L2].Flags or ML_MAPPED;
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
    Player.ExtraLight := 0;
    if (FlashFrames <> '') and (Elapsed < FlashTics * Length(FlashFrames)) then
    begin
      Player.FlashFrame := FlashFrames[1 + Elapsed div FlashTics];
      { A_Light1 on the first flash frame, A_Light2 on the later ones
        (the rocket launcher's second frame keeps A_Light1, the plasma
        gun's flash is A_Light1 only). }
      Player.ExtraLight := Min(2, 1 + Elapsed div FlashTics);
      if (Player.Weapon = wpPlasma) or
         ((Player.Weapon = wpMissile) and (Elapsed div FlashTics = 1)) then
        Player.ExtraLight := 1;
    end;
  end;

var
  Total, Elapsed: Integer;
begin
  if Player.AttackTics > 0 then
    Dec(Player.AttackTics);
  { A_Lower / A_Raise at 6 pixels per tic; the old weapon finishes its
    attack first. }
  case Player.WeaponSwitch of
    1:
      if Player.AttackTics <= 0 then
      begin
        Player.WeaponOffset := Player.WeaponOffset + 6;
        if Player.WeaponOffset >= 96 then
        begin
          Player.WeaponOffset := 96;
          Player.Weapon := Player.PendingWeapon;
          Player.WeaponFrame := 'A';
          Player.FlashFrame := #0;
          Player.WeaponSwitch := 2;
          if Player.Weapon = wpChainsaw then FSounds.Play('DSSAWUP');
        end;
      end;
    2:
      begin
        Player.WeaponOffset := Player.WeaponOffset - 6;
        if Player.WeaponOffset <= 0 then
        begin
          Player.WeaponOffset := 0;
          Player.WeaponSwitch := 0;
        end;
      end;
  end;
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
    Player.ExtraLight := 0;
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
  A, O: TDoomActor;
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
        begin
          if A.Charging then
            TicCharge(A)
          else
          begin
            { A_VileAttack happens on frame O of the Arch-vile's attack. }
            if (A.Info^.Num = 64) and (A.Frame = 'O') and not A.AttackFired then
            begin
              A.AttackFired := true;
              VileAttack(A);
            end;
            if A.SequenceDone then
            begin
              if A.Fire <> nil then
              begin
                A.Fire.Removed := true;
                A.Fire := nil;
              end;
              A.State := asChase;
              A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
              { A_Chase: on Nightmare monsters may attack again right away
                (MF_JUSTATTACKED does not make them walk first). }
              if Skill = 4 then A.ReactionTics := Random1(8) else A.ReactionTics := 20 + Random1(35);
            end;
          end;
        end;
      asMissile:
        if A.Info = @EffectInfos[ekSpawnShot] then
          TicSpawnCube(A)
        else
          TicMissile(A);
    end;
    if A.Info^.Num = 89 then
      TicBrainShooter(A);
    if A.Info = @EffectInfos[ekVileFire] then
      FollowVileFire(A);
    if (A.Info^.Kind = tkMonster) and (A.State in [asIdle, asChase, asAttack]) then
      TicMonster(A);
    if (A.Info^.Kind = tkMonster) and (A.State = asDead) and not A.Removed then
      NightmareRespawn(A)
    else
      A.DeadTics := 0;

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
      for O in FActors do
      begin
        if O.Target = A then O.Target := nil;
        if O.Shooter = A then O.Shooter := nil;
        if O.Fire = A then O.Fire := nil;
      end;
      if A.Parent <> nil then A.Parent.Remove(A);
      FActors.Delete(I);
    end;
  end;
end;

{ Doom keeps two slopes (height difference per whole distance, seen from
  the eye at sightzstart = z + 3/4 height): initially the target's top and
  bottom. Every two-sided line crossed at fraction T of the way narrows them
  to its opening (bottom = higher floor, top = lower ceiling, only where the
  floors / ceilings differ); a one-sided line, a closed opening or slopes
  that meet block the view. Lines may come in any order: min / max do not
  care, so no BSP walk is needed. }
function TDoomWorld.CheckSight(const X1, Y1, EyeZ: Single; const S1: Integer;
  const X2, Y2, Z2, H2: Single; const S2: Integer): Boolean;
var
  I, F, B: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  T, TopSlope, BottomSlope, OpenTop, OpenBottom, Slope: Single;
  MinX, MaxX, MinY, MaxY: Single;
begin
  if FMap.RejectBlocks(S1, S2) then Exit(false);
  TopSlope := (Z2 + H2) - EyeZ;
  BottomSlope := Z2 - EyeZ;
  MinX := Min(X1, X2); MaxX := Max(X1, X2);
  MinY := Min(Y1, Y2); MaxY := Max(Y1, Y2);
  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if (Max(V1.X, V2.X) < MinX) or (Min(V1.X, V2.X) > MaxX) or
       (Max(V1.Y, V2.Y) < MinY) or (Min(V1.Y, V2.Y) > MaxY) then Continue;
    if not SegmentsIntersect(X1, Y1, X2, Y2, V1.X, V1.Y, V2.X, V2.Y, T) then Continue;
    F := L.FrontSector;
    B := L.BackSector;
    if (F < 0) or (B < 0) then Exit(false);
    OpenTop := Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight);
    OpenBottom := Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight);
    if OpenTop <= OpenBottom then Exit(false);
    if T < 1e-4 then Continue; { the line under the viewer's feet }
    if FMap.Sectors[F].FloorHeight <> FMap.Sectors[B].FloorHeight then
    begin
      Slope := (OpenBottom - EyeZ) / T;
      if Slope > BottomSlope then BottomSlope := Slope;
    end;
    if FMap.Sectors[F].CeilingHeight <> FMap.Sectors[B].CeilingHeight then
    begin
      Slope := (OpenTop - EyeZ) / T;
      if Slope < TopSlope then TopSlope := Slope;
    end;
    if TopSlope <= BottomSlope then Exit(false);
  end;
  Result := true;
end;

procedure TDoomWorld.DebugSight;
var
  A: TDoomActor;
begin
  for A in FActors do
    if (A.Info^.Kind = tkMonster) and (A.State <> asDead) and
       (Sqr(A.DoomX - Player.X) + Sqr(A.DoomY - Player.Y) < Sqr(2500)) then
      WritelnLog('Sight', '%s at (%.0f, %.0f, z %.0f) sector %d: 2D %s, 3D %s, reject %s', [A.Info^.Sprite,
        A.DoomX, A.DoomY, A.DoomZ, A.Sector,
        BoolToStr(SightClear(A.DoomX, A.DoomY, Player.X, Player.Y), true),
        BoolToStr(SightToPlayer(A), true),
        BoolToStr(FMap.RejectBlocks(A.Sector, Player.Sector), true)]);
end;

function TDoomWorld.SightToPlayer(const A: TDoomActor): Boolean;
begin
  Result := CheckSight(A.DoomX, A.DoomY, A.DoomZ + A.Info^.Height * 0.75, A.Sector,
    Player.X, Player.Y, Player.Z, PlayerHeight, Player.Sector);
end;

function TDoomWorld.SightToTarget(const A: TDoomActor): Boolean;
begin
  if A.Target = nil then
    Result := SightToPlayer(A)
  else
    Result := CheckSight(A.DoomX, A.DoomY, A.DoomZ + A.Info^.Height * 0.75, A.Sector,
      A.Target.DoomX, A.Target.DoomY, A.Target.DoomZ, A.Target.Info^.Height, A.Target.Sector);
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

{ P_NoiseAlert / P_RecursiveSound: the shot floods from the player's sector
  through every two-sided line that is open (a closed door stops it); a line
  flagged ML_SOUNDBLOCK lets it through only if it has not crossed one yet.
  Sectors reached remember it; idle monsters there notice it in MonsterLook.
  Doom recurses; this walks a work list instead (same result, no deep
  recursion on big maps), revisiting a sector only with fewer blocks. }
procedure TDoomWorld.NoiseAlert;
var
  Traversed: array of Integer; { 0 = not reached, else sound blocks + 1 }
  StackSec, StackBlocks: array of Integer;
  Count, Sec, Blocks, L, Other, I, Reached, Fresh: Integer;
  Line: ^TDoomLinedef;
  A: TDoomActor;

  procedure Push(const S, B: Integer);
  begin
    if Count >= Length(StackSec) then
    begin
      SetLength(StackSec, Count * 2 + 16);
      SetLength(StackBlocks, Count * 2 + 16);
    end;
    StackSec[Count] := S;
    StackBlocks[Count] := B;
    Inc(Count);
  end;

begin
  if (Player.Sector < 0) or (Length(FSectorSound) <> Length(FMap.Sectors)) then Exit;
  SetLength(Traversed, Length(FMap.Sectors));
  Count := 0;
  Reached := 0;
  Fresh := 0;
  Push(Player.Sector, 0);
  while Count > 0 do
  begin
    Dec(Count);
    Sec := StackSec[Count];
    Blocks := StackBlocks[Count];
    if (Traversed[Sec] <> 0) and (Traversed[Sec] <= Blocks + 1) then Continue;
    if Traversed[Sec] = 0 then Inc(Reached);
    Traversed[Sec] := Blocks + 1;
    if not FSectorSound[Sec] then Inc(Fresh);
    FSectorSound[Sec] := true;
    for I := 0 to High(FMap.Sectors[Sec].Lines) do
    begin
      L := FMap.Sectors[Sec].Lines[I];
      Line := @FMap.Linedefs[L];
      if ((Line^.Flags and ML_TWOSIDED) = 0) or (Line^.FrontSector < 0) or (Line^.BackSector < 0) then
        Continue;
      { P_LineOpening: no gap between the two sides, no sound. }
      if Min(FMap.Sectors[Line^.FrontSector].CeilingHeight, FMap.Sectors[Line^.BackSector].CeilingHeight) -
         Max(FMap.Sectors[Line^.FrontSector].FloorHeight, FMap.Sectors[Line^.BackSector].FloorHeight) <= 0 then
        Continue;
      if Line^.FrontSector = Sec then Other := Line^.BackSector else Other := Line^.FrontSector;
      if (Line^.Flags and ML_SOUNDBLOCK) <> 0 then
      begin
        if Blocks = 0 then Push(Other, 1);
      end else
        Push(Other, Blocks);
    end;
  end;
  if Fresh > 0 then
    WritelnLog('Noise', 'Shot heard in %d sectors (%d new)', [Reached, Fresh]);
  { The Icon of Sin's shooter listens the same way. }
  for A in FActors do
    if (A.Info^.Num = 89) and not A.Awake and (A.Sector >= 0) and FSectorSound[A.Sector] then
      BrainAwake(A);
end;

{ A_Look: first the sector's sound (an ambush monster must also have a line
  of sight to the player), then P_LookForPlayers: the player must be in the
  front half circle (or within melee range) and in sight. }
function TDoomWorld.MonsterLook(const A: TDoomActor; out Reason: String): Boolean;
var
  DX, DY, Diff: Single;
begin
  Result := false;
  Reason := '';
  if Player.Dead then Exit;
  if (A.Sector >= 0) and (A.Sector < Length(FSectorSound)) and FSectorSound[A.Sector] then
  begin
    if (A.MapFlags and MTF_AMBUSH) = 0 then
    begin
      Reason := 'heard';
      Exit(true);
    end;
    if SightToPlayer(A) then
    begin
      Reason := 'heard and saw (ambush)';
      Exit(true);
    end;
  end;
  DX := Player.X - A.DoomX;
  DY := Player.Y - A.DoomY;
  if Sqr(DX) + Sqr(DY) > Sqr(64) then
  begin
    Diff := RadToDeg(ArcTan2(DY, DX)) - A.Angle;
    Diff := Diff - 360 * Round(Diff / 360);
    if Abs(Diff) > 90 then Exit; { behind it }
  end;
  if SightToPlayer(A) then
  begin
    Reason := 'saw';
    Result := true;
  end;
end;

function TDoomWorld.SameSpecies(const A, B: TDoomActor): Boolean;
begin
  if (A = nil) or (B = nil) then Exit(false);
  Result := (A.Info^.Num = B.Info^.Num) or
    (((A.Info^.Num = 3003) or (A.Info^.Num = 69)) and ((B.Info^.Num = 3003) or (B.Info^.Num = 69)));
end;

function TDoomWorld.TargetAlive(const A: TDoomActor): Boolean;
begin
  if A.Target = nil then
    Result := not Player.Dead
  else
    Result := (not A.Target.Removed) and (A.Target.State in [asIdle, asChase, asAttack, asPain]);
end;

procedure TDoomWorld.TargetPosition(const A: TDoomActor; out TX, TY, TZ, TRadius: Single);
begin
  if A.Target = nil then
  begin
    TX := Player.X; TY := Player.Y; TZ := Player.Z; TRadius := PlayerRadius;
  end else
  begin
    TX := A.Target.DoomX; TY := A.Target.DoomY; TZ := A.Target.DoomZ; TRadius := A.Target.Info^.Radius;
  end;
end;

procedure TDoomWorld.TicMonster(const A: TDoomActor);
var
  Reason: String;
  OldX, OldY: Single;
  DX, DY, Dist, Ang, Step, TX, TY, TZ, TR, RangeDist: Single;
  Blocked: Integer;
  Tries: Integer;
  Moved: Boolean;
begin
  { A dead target (monster corpse, or the player) sends the monster back to the player. }
  if (A.Target <> nil) and not TargetAlive(A) then A.Target := nil;
  if (A.Target = nil) and Player.Dead then Exit;
  TargetPosition(A, TX, TY, TZ, TR);
  DX := TX - A.DoomX;
  DY := TY - A.DoomY;
  Dist := Sqrt(DX * DX + DY * DY);

  if A.State = asIdle then
  begin
    if not A.Awake then
    begin
      { Look for the player a few times a second (spawn states last 10 tics). }
      if (FTic + A.MapFlags) mod 10 <> 0 then Exit;
      if MonsterLook(A, Reason) then
      begin
        WritelnLog('Wake', '%s at (%.0f, %.0f) %s', [A.Info^.Sprite, A.DoomX, A.DoomY, Reason]);
        A.Awake := true;
        { P_SpawnMobj: no reaction time on Nightmare. }
        if Skill = 4 then A.ReactionTics := 0 else A.ReactionTics := Random1(8);
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

  { A_VileChase: an Arch-vile touching a corpse raises it instead of moving. }
  if (A.Info^.Num = 64) and VileTryRaise(A) then Exit;

  { Face the target. }
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
    end else if SightToTarget(A) then
    begin
      { Doom's P_CheckMissileRange: more likely to shoot when close; lost
        souls, cyberdemons and spiders count half the distance; Arch-viles
        only attack within 14 * 64 units. }
      RangeDist := Dist;
      if (A.Info^.Num = 3006) or (A.Info^.Num = 16) or (A.Info^.Num = 7) then
        RangeDist := Dist / 2;
      if ((A.Info^.Num <> 64) or (Dist <= 14 * 64)) and
         (Random(256) >= Min(220, 40 + Trunc(RangeDist / 6))) then
      begin
        MonsterAttack(A);
        Exit;
      end;
    end;
    A.ReactionTics := 10 + Random1(12);
  end;

  { Move towards the target, trying other directions when blocked. }
  Step := A.Info^.Speed / MoveFrameTics(A.Info^.Num);
  if A.Info^.Floats then
    Step := Step * 1.2;
  { Nightmare halves the demons' walking frame tics: twice as fast. }
  if (Skill = 4) and ((A.Info^.Num = 3002) or (A.Info^.Num = 58)) then
    Step := Step * 2;
  Moved := false;
  Tries := 0;
  OldX := A.DoomX;
  OldY := A.DoomY;
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
  if Moved then
    MonsterCrossLines(A, OldX, OldY);
  if A.Info^.Floats then
  begin
    { Flyers drift towards the target's height. }
    if TZ + 32 > A.DoomZ + 8 then A.DoomZ := A.DoomZ + 2
    else if TZ + 32 < A.DoomZ - 8 then A.DoomZ := A.DoomZ - 2;
  end;
end;

function TDoomWorld.SpawnMonster(const TypeNum: Integer; const X, Y, Z: Single): TDoomActor;
var
  Info: PThingInfo;
  Sec: Integer;
begin
  Result := nil;
  Info := FindThingInfo(TypeNum);
  if Info = nil then Exit;
  Sec := FMap.SectorAt(X, Y);
  if Sec < 0 then Exit;
  Result := TDoomActor.Create(nil, FGraphics, Info);
  Result.DoomX := X;
  Result.DoomY := Y;
  Result.DoomZ := Z;
  Result.SpawnX := X;
  Result.SpawnY := Y;
  Result.Sector := Sec;
  Result.Awake := true;
  Result.SetLight(FMap.Sectors[Sec].LightLevel);
  Result.UpdateTransform;
  FActors.Add(Result);
  FItems.Add(Result);
end;

{ A_SkullAttack: fly at the target's middle at 20 units per tic. }
procedure TDoomWorld.StartSkullCharge(const A: TDoomActor);
const
  SkullSpeed = 20;
var
  TX, TY, TZ, TR, DX, DY, Dist: Single;
  TargetHeight: Single;
begin
  TargetPosition(A, TX, TY, TZ, TR);
  if A.Target = nil then TargetHeight := PlayerHeight else TargetHeight := A.Target.Info^.Height;
  DX := TX - A.DoomX;
  DY := TY - A.DoomY;
  Dist := Sqrt(DX * DX + DY * DY);
  if Dist < 1 then Dist := 1;
  A.Angle := RadToDeg(ArcTan2(DY, DX));
  A.VelX := DX / Dist * SkullSpeed;
  A.VelY := DY / Dist * SkullSpeed;
  A.VelZ := ((TZ + TargetHeight / 2) - A.DoomZ) / Max(1, Dist / SkullSpeed);
  A.Charging := true;
  A.ChargeTics := 3 * TicRate;
  A.State := asAttack;
  A.PlaySequence('CD', 4, true);
  if A.Info^.AttackSound <> '' then FSounds.PlayAt(A.Info^.AttackSound, A);
end;

procedure TDoomWorld.StopSkullCharge(const A: TDoomActor);
begin
  A.Charging := false;
  A.VelX := 0; A.VelY := 0; A.VelZ := 0;
  if A.State = asAttack then
  begin
    A.State := asChase;
    A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
  end;
  A.ReactionTics := 10 + Random1(20);
end;

procedure TDoomWorld.TicCharge(const A: TDoomActor);
var
  NX, NY, NZ, OldZ, R: Single;
  O: TDoomActor;
  Blocked, Sec: Integer;
begin
  Dec(A.ChargeTics);
  if A.ChargeTics <= 0 then
  begin
    StopSkullCharge(A);
    Exit;
  end;
  R := A.Info^.Radius;
  NX := A.DoomX + A.VelX;
  NY := A.DoomY + A.VelY;
  NZ := A.DoomZ + A.VelZ;

  { PIT_CheckThing with MF_SKULLFLY: slam into whatever is hit. }
  if (not Player.Dead) and (Abs(Player.X - NX) < PlayerRadius + R) and (Abs(Player.Y - NY) < PlayerRadius + R) and
     (NZ < Player.Z + PlayerHeight) and (NZ + A.Info^.Height > Player.Z) then
  begin
    DamagePlayer(Dice(A.Info^.DamageDice, A.Info^.DamageFaces), A);
    StopSkullCharge(A);
    Exit;
  end;
  for O in FActors do
    if (O <> A) and (not O.Removed) and O.Collides and (O.State in [asIdle, asChase, asAttack, asPain]) and
       ((O.Info^.Kind = tkMonster) or (O.Info^.Num = 2035)) and
       (Abs(O.DoomX - NX) < O.Info^.Radius + R) and (Abs(O.DoomY - NY) < O.Info^.Radius + R) and
       (NZ < O.DoomZ + O.Info^.Height) and (NZ + A.Info^.Height > O.DoomZ) then
    begin
      DamageActor(O, Dice(A.Info^.DamageDice, A.Info^.DamageFaces), NX, NY, NZ + 8, A, false);
      StopSkullCharge(A);
      Exit;
    end;

  { Walls stop it (P_TryMove fails: P_SlideMove is not used for skulls). }
  OldZ := A.DoomZ;
  A.DoomZ := NZ;
  if not TryMove2D(A, NX, NY, Blocked) then
  begin
    A.DoomZ := OldZ;
    StopSkullCharge(A);
    Exit;
  end;
  { Floors and ceilings: P_ZMovement bounces a flying skull. }
  Sec := A.Sector;
  if Sec >= 0 then
  begin
    if A.DoomZ < FMap.Sectors[Sec].FloorHeight then
    begin
      A.DoomZ := FMap.Sectors[Sec].FloorHeight;
      A.VelZ := -A.VelZ;
    end else if A.DoomZ + A.Info^.Height > FMap.Sectors[Sec].CeilingHeight then
    begin
      A.DoomZ := FMap.Sectors[Sec].CeilingHeight - A.Info^.Height;
      A.VelZ := -A.VelZ;
    end;
  end;
end;

{ A_PainShootSkull: spawn a lost soul in front and send it at the target. }
procedure TDoomWorld.PainShootSkull(const A: TDoomActor; const AngleDeg: Single);
var
  O, S: TDoomActor;
  Count, Blocked: Integer;
  Prestep, X, Y: Single;
  SkullInfo: PThingInfo;
begin
  { Doom refuses when more than 20 lost souls are on the level. }
  Count := 0;
  for O in FActors do
    if (O.Info^.Num = 3006) and (not O.Removed) and (O.State in [asIdle, asChase, asAttack, asPain]) then
      Inc(Count);
  if Count > 20 then Exit;
  SkullInfo := FindThingInfo(3006);
  if SkullInfo = nil then Exit;
  Prestep := 4 + 3 * (A.Info^.Radius + SkullInfo^.Radius) / 2;
  X := A.DoomX + Cos(DegToRad(AngleDeg)) * Prestep;
  Y := A.DoomY + Sin(DegToRad(AngleDeg)) * Prestep;
  { Vanilla can spawn souls through walls; we refuse instead. }
  if not SightClear(A.DoomX, A.DoomY, X, Y) then Exit;
  S := SpawnMonster(3006, A.DoomX, A.DoomY, A.DoomZ + 8);
  if S = nil then Exit;
  S.Target := A.Target;
  S.Angle := AngleDeg;
  if not TryMove2D(S, X, Y, Blocked) then
  begin
    { No room: the new soul dies at once, like P_DamageMobj(newmobj, 10000). }
    WritelnLog('PainSkull', 'lost soul spawned into a blocked spot, killed');
    DamageActor(S, 10000, S.DoomX, S.DoomY, S.DoomZ + 8, nil, false);
    Exit;
  end;
  S.DoomZ := A.DoomZ + 8;
  WritelnLog('PainSkull', 'Pain Elemental spits a lost soul (%d alive)', [Count + 1]);
  StartSkullCharge(S);
end;

function TDoomWorld.SpawnEffectAt(const Kind: TEffectKind; const X, Y, Z: Single; const Tics: Integer): TDoomActor;
begin
  Result := TDoomActor.Create(nil, FGraphics, @EffectInfos[Kind]);
  Result.State := asEffect;
  Result.Bright := true;
  Result.DoomX := X; Result.DoomY := Y; Result.DoomZ := Z;
  Result.Sector := FMap.SectorAt(X, Y);
  Result.Collides := false; Result.Pickable := false;
  Result.SetLight(255);
  Result.PlaySequence(EffectInfos[Kind].IdleFrames, Tics, false);
  Result.UpdateTransform;
  FActors.Add(Result);
  FItems.Add(Result);
end;

{ Icon of Sin (p_enemy.c A_BrainAwake / A_BrainSpit / A_SpawnFly /
  A_BrainScream / A_BrainDie). The shooter (89) and the spawn spots (87) are
  hidden actors. A woken shooter waits 181 tics, then every 150 tics spits a
  cube at the next spot in turn; the cube flies through walls and, when it
  arrives, becomes fire and a random monster that telefrags whatever stands
  there. Killing the brain (88) sets off explosions and ends the level. }
procedure TDoomWorld.BrainAwake(const A: TDoomActor);
var
  O: TDoomActor;
  N: Integer;
begin
  A.Awake := true;
  A.ReactionTics := 181;
  N := 0;
  for O in FActors do
    if O.Info^.Num = 87 then Inc(N);
  FSounds.Play('DSBOSSIT');
  WritelnLog('BrainAwake', 'Icon of Sin awake, %d spawn spots', [N]);
end;

procedure TDoomWorld.TicBrainShooter(const A: TDoomActor);
begin
  if not A.Awake then
  begin
    { A_Look: sight wakes it too. }
    if ((FTic + 5) mod 10 = 0) and not Player.Dead and SightToPlayer(A) then
      BrainAwake(A);
    Exit;
  end;
  if FBrainDeathTics > 0 then Exit;
  Dec(A.ReactionTics);
  if A.ReactionTics > 0 then Exit;
  A.ReactionTics := 150;
  BrainSpit(A);
end;

procedure TDoomWorld.BrainSpit(const A: TDoomActor);
var
  O, Targ, Cube: TDoomActor;
  Spots: array of TDoomActor;
  DX, DY, DZ, Dist, Speed: Single;
begin
  { On the two easy skills only every other spit happens. }
  FBrainEasy := not FBrainEasy;
  if (Skill <= 1) and not FBrainEasy then Exit;
  Spots := nil;
  for O in FActors do
    if O.Info^.Num = 87 then
    begin
      SetLength(Spots, Length(Spots) + 1);
      Spots[High(Spots)] := O;
    end;
  if Length(Spots) = 0 then Exit;
  Targ := Spots[FBrainTargetIndex mod Length(Spots)];
  FBrainTargetIndex := (FBrainTargetIndex + 1) mod Length(Spots);

  Cube := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekSpawnShot]);
  Cube.State := asMissile;
  Cube.Bright := true;
  Cube.Shooter := A;
  Cube.Target := Targ;
  Cube.DoomX := A.DoomX;
  Cube.DoomY := A.DoomY;
  Cube.DoomZ := A.DoomZ + 32;
  Cube.Sector := A.Sector;
  { P_SpawnMissile: full speed horizontally, the height difference spread
    over the flight. }
  DX := Targ.DoomX - Cube.DoomX;
  DY := Targ.DoomY - Cube.DoomY;
  DZ := Targ.DoomZ - Cube.DoomZ;
  Dist := Max(1, Sqrt(DX * DX + DY * DY));
  Speed := EffectInfos[ekSpawnShot].Speed;
  Cube.VelX := DX / Dist * Speed;
  Cube.VelY := DY / Dist * Speed;
  Cube.VelZ := DZ / Max(1, Dist / Speed);
  Cube.Angle := RadToDeg(ArcTan2(DY, DX));
  Cube.ReactionTics := Max(1, Round(Dist / Speed));
  Cube.Collides := false;
  Cube.Pickable := false;
  Cube.SetLight(255);
  Cube.PlaySequence('ABCD', 3, true);
  Cube.UpdateTransform;
  FActors.Add(Cube);
  FItems.Add(Cube);
  FSounds.Play('DSBOSPIT');
  WritelnLog('BrainSpit', 'Cube to (%f, %f), %d tics', [Targ.DoomX, Targ.DoomY, Cube.ReactionTics]);
end;

procedure TDoomWorld.TicSpawnCube(const A: TDoomActor);
var
  X, Y, Z: Single;
  R, TypeNum, Sec: Integer;
  M, O: TDoomActor;
begin
  { MF_NOCLIP: straight through walls. }
  A.DoomX := A.DoomX + A.VelX;
  A.DoomY := A.DoomY + A.VelY;
  A.DoomZ := A.DoomZ + A.VelZ;
  Sec := FMap.SectorAt(A.DoomX, A.DoomY);
  if Sec >= 0 then A.Sector := Sec;
  { A_SpawnSound every fourth frame. }
  if A.ReactionTics mod 12 = 0 then FSounds.PlayAt('DSBOSCUB', A);
  Dec(A.ReactionTics);
  if A.ReactionTics > 0 then Exit;

  if A.Target <> nil then
  begin
    X := A.Target.DoomX;
    Y := A.Target.DoomY;
  end else
  begin
    X := A.DoomX;
    Y := A.DoomY;
  end;
  A.Removed := true;
  Sec := FMap.SectorAt(X, Y);
  if Sec < 0 then Exit;
  Z := FMap.Sectors[Sec].FloorHeight;
  FSounds.PlayAt('DSTELEPT', SpawnEffectAt(ekSpawnFire, X, Y, Z, 4));

  { A_SpawnFly: the monster by P_Random. }
  R := Random(256);
  if R < 50 then TypeNum := 3001        { imp }
  else if R < 90 then TypeNum := 3002   { demon }
  else if R < 120 then TypeNum := 58    { spectre }
  else if R < 130 then TypeNum := 71    { pain elemental }
  else if R < 160 then TypeNum := 3005  { cacodemon }
  else if R < 162 then TypeNum := 64    { arch-vile }
  else if R < 172 then TypeNum := 66    { revenant }
  else if R < 192 then TypeNum := 68    { arachnotron }
  else if R < 222 then TypeNum := 67    { mancubus }
  else if R < 246 then TypeNum := 69    { hell knight }
  else TypeNum := 3003;                 { baron }
  M := SpawnMonster(TypeNum, X, Y, Z);
  if M = nil then Exit;
  M.Angle := RadToDeg(ArcTan2(Player.Y - Y, Player.X - X));
  M.UpdateTransform;
  { P_TeleportMove: on MAP30 monsters telefrag anything in the spot. }
  for O in FActors do
    if (O <> M) and (not O.Removed) and (O.Info^.Kind = tkMonster) and
       (O.State in [asIdle, asChase, asAttack, asPain]) and
       (Abs(O.DoomX - X) < O.Info^.Radius + M.Info^.Radius) and
       (Abs(O.DoomY - Y) < O.Info^.Radius + M.Info^.Radius) then
      DamageActor(O, 10000, O.DoomX, O.DoomY, O.DoomZ + 32, nil, false);
  if (not Player.Dead) and (Abs(Player.X - X) < PlayerRadius + M.Info^.Radius) and
     (Abs(Player.Y - Y) < PlayerRadius + M.Info^.Radius) then
    DamagePlayer(10000, M);
  WritelnLog('BrainSpawn', '%s at (%f, %f)', [M.Info^.Sprite, X, Y]);
end;

procedure TDoomWorld.StartBrainDeath(const A: TDoomActor);
var
  I: Integer;
begin
  { A_BrainScream: a row of explosions in front of the brain, the death
    scream at full volume; A_BrainDie (G_ExitLevel) 120 tics later. }
  FBrainX := A.DoomX;
  FBrainY := A.DoomY;
  FBrainDeathTics := 120;
  for I := 0 to (196 + 320) div 8 do
    SpawnEffectAt(ekBrainExplosion, FBrainX - 196 + I * 8, FBrainY - 320, 128 + Random(256) * 2, 4 + Random(10));
  FSounds.Play('DSBOSDTH');
  WritelnLog('BrainDeath', 'Icon of Sin killed, exit in %d tics', [FBrainDeathTics]);
end;

procedure TDoomWorld.TicBrainDeath;
begin
  { A_BrainExplode keeps the explosions coming. }
  if FTic mod 2 = 0 then
    SpawnEffectAt(ekBrainExplosion, FBrainX - 196 + Random(516), FBrainY - 320, 128 + Random(256) * 2, 10);
  Dec(FBrainDeathTics);
  if FBrainDeathTics = 0 then
  begin
    WritelnLog('BrainDeath', 'Level exit');
    FExitRequested := true;
  end;
end;

function TDoomWorld.SpawnFog(const X, Y, Z: Single; const Sec: Integer): TDoomActor;
begin
  Result := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekTeleFog]);
  Result.State := asEffect;
  Result.Bright := true;
  Result.DoomX := X; Result.DoomY := Y; Result.DoomZ := Z;
  Result.Sector := Sec;
  Result.Collides := false; Result.Pickable := false;
  Result.SetLight(255);
  Result.PlaySequence('ABABCDEFGHIJ', 6, false);
  Result.UpdateTransform;
  FActors.Add(Result);
  FItems.Add(Result);
  FSounds.PlayAt('DSTELEPT', Result);
end;

{ P_MobjThinker / P_NightmareRespawn: on Nightmare a corpse that has lain for
  12 seconds may come back at its map spot (teleport fog at both places),
  checked every 32 tics with a 4/256 chance. }
procedure TDoomWorld.NightmareRespawn(const A: TDoomActor);
var
  O, M: TDoomActor;
  Sec: Integer;
  Info: PThingInfo;
begin
  if Skill <> 4 then Exit;
  Inc(A.DeadTics);
  if A.DeadTics < 12 * TicRate then Exit;
  if (FTic and 31) <> 0 then Exit;
  if Random(256) > 4 then Exit;
  { Lost souls and Pain Elementals leave no corpse, the boss brain stays dead. }
  if (A.Info^.Num = 3006) or (A.Info^.Num = 71) or (A.Info^.Num = 88) then Exit;
  Info := A.Info;
  Sec := FMap.SectorAt(A.SpawnX, A.SpawnY);
  if Sec < 0 then Exit;
  { P_CheckPosition at the spawn spot. }
  for O in FActors do
    if (O <> A) and (not O.Removed) and O.Collides and
       (O.Info^.Kind in [tkMonster, tkDecoration]) and
       (Abs(O.DoomX - A.SpawnX) < O.Info^.Radius + Info^.Radius) and
       (Abs(O.DoomY - A.SpawnY) < O.Info^.Radius + Info^.Radius) then
      Exit;
  if (not Player.Dead) and (Abs(Player.X - A.SpawnX) < PlayerRadius + Info^.Radius) and
     (Abs(Player.Y - A.SpawnY) < PlayerRadius + Info^.Radius) then
    Exit;

  SpawnFog(A.DoomX, A.DoomY, A.DoomZ, A.Sector);
  SpawnFog(A.SpawnX, A.SpawnY, FMap.Sectors[Sec].FloorHeight, Sec);
  M := SpawnMonster(Info^.Num, A.SpawnX, A.SpawnY, FMap.Sectors[Sec].FloorHeight);
  if M = nil then Exit;
  M.Angle := A.SpawnAngle;
  M.SpawnAngle := A.SpawnAngle;
  M.MapFlags := A.MapFlags;
  { Like a freshly spawned monster: asleep until it sees the player. }
  M.Awake := false;
  M.ReactionTics := 0;
  M.UpdateTransform;
  A.Removed := true;
  WritelnLog('Respawn', '%s respawned at (%f, %f)', [Info^.Sprite, A.SpawnX, A.SpawnY]);
end;

function TDoomWorld.CanRaise(const Num: Integer): Boolean;
begin
  { Monsters without a raise state in info.c. }
  case Num of
    3006, 16, 7, 64, 72, 88: Result := false;
    else Result := true;
  end;
end;

{ A_VileChase: look for a corpse within reach whose spot is free. }
function TDoomWorld.VileTryRaise(const A: TDoomActor): Boolean;
var
  C, O: TDoomActor;
  Fits: Boolean;
  Reach: Single;
  Frames: String;
  I: Integer;
begin
  Result := false;
  for C in FActors do
  begin
    if (C.State <> asDead) or C.Removed or (C.Info^.Kind <> tkMonster) or not CanRaise(C.Info^.Num) then
      Continue;
    Reach := C.Info^.Radius + A.Info^.Radius + A.Info^.Speed;
    if (Abs(C.DoomX - A.DoomX) > Reach) or (Abs(C.DoomY - A.DoomY) > Reach) then Continue;
    { The corpse must fit where it lies (P_CheckPosition). }
    Fits := true;
    for O in FActors do
      if (O <> C) and (O <> A) and (not O.Removed) and O.Collides and
         (O.Info^.Kind in [tkMonster, tkDecoration]) and
         (Abs(O.DoomX - C.DoomX) < O.Info^.Radius + C.Info^.Radius) and
         (Abs(O.DoomY - C.DoomY) < O.Info^.Radius + C.Info^.Radius) then
      begin
        Fits := false;
        Break;
      end;
    if Fits and (not Player.Dead) and (Abs(Player.X - C.DoomX) < PlayerRadius + C.Info^.Radius) and
       (Abs(Player.Y - C.DoomY) < PlayerRadius + C.Info^.Radius) then
      Fits := false;
    if not Fits then Continue;

    { Heal: the vile faces the corpse and plays its healing frames. }
    A.Angle := RadToDeg(ArcTan2(C.DoomY - A.DoomY, C.DoomX - A.DoomX));
    A.State := asAttack;
    A.AttackFired := true; { no fire attack this time }
    A.PlaySequence('[\]', 10, false);
    FSounds.PlayAt('DSSLOP', C);
    { The corpse comes back: death frames in reverse, full health. }
    C.Health := C.Info^.Health;
    C.Collides := C.Info^.Solid;
    C.Pickable := true;
    C.Target := nil;
    C.Awake := true;
    C.State := asPain;
    Frames := '';
    for I := Length(C.Info^.DeathFrames) downto 1 do
      Frames := Frames + C.Info^.DeathFrames[I];
    C.PlaySequence(Frames, 5, false);
    WritelnLog('Raise', 'Arch-vile raised %s', [C.Info^.Sprite]);
    Exit(true);
  end;
end;

{ A_VileTarget: start the attack and light the fire on the target. }
procedure TDoomWorld.VileStartAttack(const A: TDoomActor);
var
  F: TDoomActor;
begin
  A.State := asAttack;
  A.PlaySequence(A.Info^.AttackFrames, 9, false);
  A.AttackFired := false;
  if A.Info^.AttackSound <> '' then FSounds.PlayAt(A.Info^.AttackSound, A);
  if A.Fire <> nil then A.Fire.Removed := true;
  F := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekVileFire]);
  F.State := asEffect;
  F.Bright := true;
  F.Shooter := A;
  F.Collides := false;
  F.Pickable := false;
  F.SetLight(255);
  F.PlaySequence('ABCDEFGH', 3, true);
  A.Fire := F;
  FollowVileFire(F);
  FActors.Add(F);
  FItems.Add(F);
  FSounds.PlayAt('DSFLAMST', F);
end;

{ A_Fire: keep the fire in front of the target while the vile attacks. }
procedure TDoomWorld.FollowVileFire(const F: TDoomActor);
var
  V: TDoomActor;
  TX, TY, TZ, TR, Facing: Single;
begin
  V := F.Shooter;
  if (V = nil) or V.Removed or (V.State <> asAttack) or (V.Fire <> F) then
  begin
    F.Removed := true;
    Exit;
  end;
  TargetPosition(V, TX, TY, TZ, TR);
  if V.Target = nil then Facing := Player.Angle else Facing := V.Target.Angle;
  F.DoomX := TX + Cos(DegToRad(Facing)) * 24;
  F.DoomY := TY + Sin(DegToRad(Facing)) * 24;
  F.DoomZ := TZ;
  F.Sector := FMap.SectorAt(F.DoomX, F.DoomY);
  F.UpdateTransform;
end;

{ A_VileAttack: if the vile still sees the target, blast it. }
procedure TDoomWorld.VileAttack(const A: TDoomActor);
var
  TX, TY, TZ, TR, FX, FY: Single;
begin
  if not TargetAlive(A) then Exit;
  TargetPosition(A, TX, TY, TZ, TR);
  if not SightToTarget(A) then Exit;
  FSounds.PlayAt('DSBAREXP', A);
  if A.Target = nil then
  begin
    DamagePlayer(20, A);
    { momz = 1000 / mass: the player flies up about 50 units. }
    PlayerKnockUp := PlayerKnockUp + 50;
  end else
    DamageActor(A.Target, 20, TX, TY, TZ + 32, A, false);
  { The fire moves between the vile and the target and explodes for 70. }
  FX := TX - Cos(DegToRad(A.Angle)) * 24;
  FY := TY - Sin(DegToRad(A.Angle)) * 24;
  if A.Fire <> nil then
  begin
    A.Fire.DoomX := FX;
    A.Fire.DoomY := FY;
    RadiusDamage(FX, FY, TZ, 70, 70, A.Fire);
  end else
    RadiusDamage(FX, FY, TZ, 70, 70, A);
  if A.Target = nil then
    WritelnLog('VileAttack', 'Arch-vile blast hits the player')
  else
    WritelnLog('VileAttack', 'Arch-vile blast hits %s', [A.Target.Info^.Sprite]);
end;

procedure TDoomWorld.DebugGod;
begin
  Player.GodMode := true;
end;

function TDoomWorld.FixedColormap: Integer;
begin
  Result := NoFixedColormap;
  if Player.InvulnerableTics > 0 then
  begin
    if (Player.InvulnerableTics > 4 * 32) or ((Player.InvulnerableTics and 8) <> 0) then
      Result := InverseColormap;
  end else
  if Player.LightAmpTics > 0 then
  begin
    if (Player.LightAmpTics > 4 * 32) or ((Player.LightAmpTics and 8) <> 0) then
      Result := 1;
  end;
end;

function TDoomWorld.DebugSpawn(const TypeNum: Integer; const Distance: Single): TDoomActor;
var
  X, Y: Single;
  Sec: Integer;
begin
  X := Player.X + Cos(DegToRad(Player.Angle)) * Distance;
  Y := Player.Y + Sin(DegToRad(Player.Angle)) * Distance;
  Sec := FMap.SectorAt(X, Y);
  if Sec < 0 then Exit(nil);
  Result := SpawnMonster(TypeNum, X, Y, FMap.Sectors[Sec].FloorHeight);
  if Result <> nil then
  begin
    Result.Angle := Player.Angle + 180;
    WritelnLog('Spawn', '%s at %.0f %.0f', [Result.Info^.Sprite, X, Y]);
  end;
end;

procedure TDoomWorld.MonsterAttack(const A: TDoomActor);
var
  TX, TY, TZ, TR: Single;
begin
  case A.Info^.Num of
    3006:
      begin
        StartSkullCharge(A);
        Exit;
      end;
    71:
      begin
        { A_PainAttack: spit a lost soul. }
        A.State := asAttack;
        A.PlaySequence(A.Info^.AttackFrames, 5, false);
        PainShootSkull(A, A.Angle);
        Exit;
      end;
    64:
      begin
        VileStartAttack(A);
        Exit;
      end;
  end;
  A.State := asAttack;
  A.PlaySequence(A.Info^.AttackFrames, 6, false);
  case A.Info^.Attack of
    akMelee:
      begin
        if A.Info^.AttackSound <> '' then FSounds.PlayAt(A.Info^.AttackSound, A);
        TargetPosition(A, TX, TY, TZ, TR);
        if (Sqrt(Sqr(TX - A.DoomX) + Sqr(TY - A.DoomY)) < 64 + A.Info^.Radius) and SightToTarget(A) then
        begin
          if A.Target = nil then
            DamagePlayer(Dice(A.Info^.DamageDice, A.Info^.DamageFaces), A)
          else
            DamageActor(A.Target, Dice(A.Info^.DamageDice, A.Info^.DamageFaces),
              TX, TY, TZ + 32, A, false);
        end;
      end;
    akHitscan: MonsterHitscan(A);
    akMissile: SpawnMissile(A);
  end;
end;

{ A_PosAttack / A_SPosAttack / A_CPosAttack: face the target (an invisible
  player makes the aim wander by up to 45 degrees), take the slope to it
  (P_AimLineAttack: to its middle when it is in sight, level otherwise),
  then every pellet is fired with Doom's +-22.4 degree spread and traced
  (P_LineAttack): the first wall or body on the way takes it, so a monster
  standing in the line of fire gets hit and fights back. }
procedure TDoomWorld.MonsterHitscan(const A: TDoomActor);
const
  Range = 2048; { MISSILERANGE }
var
  TX, TY, TZ, TR, TH, Dist, ShootZ, Slope, Aim, Ang, HX, HY, HZ: Single;
  Shots, I, Damage: Integer;
  HitActor: TDoomActor;
  HitPlayer, HitWall: Boolean;
begin
  if A.Info^.AttackSound <> '' then FSounds.PlayAt(A.Info^.AttackSound, A);
  TargetPosition(A, TX, TY, TZ, TR);
  if A.Target = nil then TH := PlayerHeight else TH := A.Target.Info^.Height;
  Aim := RadToDeg(ArcTan2(TY - A.DoomY, TX - A.DoomX));
  if (A.Target = nil) and (Player.InvisibleTics > 0) then
    Aim := Aim + (Random(256) - Random(256)) * 44.8 / 255;
  A.Angle := Aim;
  ShootZ := A.DoomZ + A.Info^.Height / 2 + 8;
  Dist := Max(1, Sqrt(Sqr(TX - A.DoomX) + Sqr(TY - A.DoomY)));
  if SightToTarget(A) then
    Slope := (TZ + TH / 2 - ShootZ) / Dist
  else
    Slope := 0;
  Shots := 1;
  if A.Info^.Num in [9, 7] then Shots := 3;
  for I := 1 to Shots do
  begin
    Ang := Aim + (Random(256) - Random(256)) * 22.4 / 255;
    TraceLineAttack(A, A.DoomX, A.DoomY, ShootZ, Ang, Slope, Range, HitActor, HitPlayer, HitWall, HX, HY, HZ);
    Damage := Dice(A.Info^.DamageDice, A.Info^.DamageFaces);
    if HitPlayer then
      DamagePlayer(Damage, A)
    else if HitActor <> nil then
      DamageActor(HitActor, Damage, HX, HY, HZ, A, false)
    else if HitWall then
      SpawnPuff(HX, HY, HZ);
  end;
end;

procedure TDoomWorld.TraceLineAttack(const Shooter: TDoomActor; const X, Y, Z, Angle, Slope, Range: Single;
  out HitActor: TDoomActor; out HitPlayer, HitWall: Boolean; out HX, HY, HZ: Single);
var
  DX, DY, EX, EY, T, Best, Along, Side, Zh, OpenTop, OpenBottom: Single;
  I, F, B: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  O: TDoomActor;
  MinX, MaxX, MinY, MaxY: Single;
begin
  HitActor := nil;
  HitPlayer := false;
  HitWall := false;
  DX := Cos(DegToRad(Angle));
  DY := Sin(DegToRad(Angle));
  EX := X + DX * Range;
  EY := Y + DY * Range;
  Best := Range; { distance to the nearest hit so far }

  { Walls: a one-sided line, or a two-sided one passed above or below its
    opening (PTR_ShootTraverse). }
  MinX := Min(X, EX); MaxX := Max(X, EX);
  MinY := Min(Y, EY); MaxY := Max(Y, EY);
  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if (Max(V1.X, V2.X) < MinX) or (Min(V1.X, V2.X) > MaxX) or
       (Max(V1.Y, V2.Y) < MinY) or (Min(V1.Y, V2.Y) > MaxY) then Continue;
    if not SegmentsIntersect(X, Y, EX, EY, V1.X, V1.Y, V2.X, V2.Y, T) then Continue;
    Along := T * Range;
    if Along >= Best then Continue;
    Zh := Z + Slope * Along;
    F := L.FrontSector;
    B := L.BackSector;
    if (F >= 0) and (B >= 0) then
    begin
      OpenTop := Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight);
      OpenBottom := Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight);
      if (Zh > OpenBottom) and (Zh < OpenTop) then Continue; { through the opening }
    end;
    Best := Along;
    HitWall := true;
  end;

  { Bodies: the nearest one whose box the 2D line crosses at a height
    inside it (PTR_ShootTraverse for things). }
  for O in FActors do
  begin
    if (O = Shooter) or not Shootable(O) then Continue;
    Along := (O.DoomX - X) * DX + (O.DoomY - Y) * DY;
    if (Along <= 0) or (Along >= Best) then Continue;
    Side := Abs((O.DoomX - X) * DY - (O.DoomY - Y) * DX);
    if Side > O.Info^.Radius then Continue;
    Zh := Z + Slope * Along;
    if (Zh < O.DoomZ) or (Zh > O.DoomZ + O.Info^.Height) then Continue;
    Best := Along;
    HitActor := O;
    HitWall := false;
  end;
  if (Shooter <> nil) and not Player.Dead then
  begin
    Along := (Player.X - X) * DX + (Player.Y - Y) * DY;
    Side := Abs((Player.X - X) * DY - (Player.Y - Y) * DX);
    Zh := Z + Slope * Along;
    if (Along > 0) and (Along < Best) and (Side <= PlayerRadius) and
       (Zh >= Player.Z) and (Zh <= Player.Z + PlayerHeight) then
    begin
      Best := Along;
      HitPlayer := true;
      HitActor := nil;
      HitWall := false;
    end;
  end;

  { The hit point; a wall puff a little in front of the wall. }
  if HitWall then Best := Max(0, Best - 4);
  HX := X + DX * Best;
  HY := Y + DY * Best;
  HZ := Z + Slope * Best;
end;

procedure TDoomWorld.SpawnMissile(const A: TDoomActor);
var
  K: TEffectKind;
  M: TDoomActor;
  DX, DY, DZ, Len, Speed, TX, TY, TZ, TR: Single;
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
  TargetPosition(A, TX, TY, TZ, TR);
  M := TDoomActor.Create(nil, FGraphics, @EffectInfos[K]);
  M.State := asMissile;
  M.Bright := true;
  M.Shooter := A;
  M.DoomX := A.DoomX + Cos(DegToRad(A.Angle)) * (A.Info^.Radius + 8);
  M.DoomY := A.DoomY + Sin(DegToRad(A.Angle)) * (A.Info^.Radius + 8);
  M.DoomZ := A.DoomZ + A.Info^.Height * 0.6;
  M.Sector := A.Sector;
  DX := TX - M.DoomX;
  DY := TY - M.DoomY;
  DZ := (TZ + 28) - M.DoomZ;
  Len := Sqrt(DX * DX + DY * DY + DZ * DZ);
  if Len < 1 then Len := 1;
  Speed := EffectInfos[K].Speed;
  { Nightmare / -fast: imp, cacodemon and baron balls fly at 20. }
  if (Skill = 4) and (K in [ekBal1, ekBal2, ekBal7]) then Speed := 20;
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
  O: TDoomActor;
begin
  if A.State <> asMissile then Exit;
  NX := A.DoomX + A.VelX;
  NY := A.DoomY + A.VelY;
  NZ := A.DoomZ + A.VelZ;
  Hit := false;

  if A.FromPlayer then
  begin
    { Monsters and barrels in the way. }
    for O in FActors do
      if (O <> A) and (not O.Removed) and O.Pickable and (O.State in [asIdle, asChase, asAttack, asPain]) and
         ((O.Info^.Kind = tkMonster) or (O.Info^.Num = 2035)) and
         (Abs(O.DoomX - NX) < O.Info^.Radius + A.Info^.Radius) and
         (Abs(O.DoomY - NY) < O.Info^.Radius + A.Info^.Radius) and
         (NZ > O.DoomZ - 8) and (NZ < O.DoomZ + O.Info^.Height + 8) then
      begin
        DamageActor(O, Dice(A.MissileDamageDice, A.MissileDamageFaces), NX, NY, NZ);
        Hit := true;
        Break;
      end;
  end else
  begin
    { Other monsters in the way take the hit (and turn on the shooter);
      monsters of the shooter's own species are passed through, like Doom. }
    for O in FActors do
      if (O <> A) and (O <> A.Shooter) and (not O.Removed) and O.Pickable and
         (O.State in [asIdle, asChase, asAttack, asPain]) and
         ((O.Info^.Kind = tkMonster) or (O.Info^.Num = 2035)) and
         not SameSpecies(O, A.Shooter) and
         (Abs(O.DoomX - NX) < O.Info^.Radius + A.Info^.Radius) and
         (Abs(O.DoomY - NY) < O.Info^.Radius + A.Info^.Radius) and
         (NZ > O.DoomZ - 8) and (NZ < O.DoomZ + O.Info^.Height + 8) then
      begin
        DamageActor(O, Dice(A.MissileDamageDice, A.MissileDamageFaces), NX, NY, NZ, A.Shooter, false);
        Hit := true;
        Break;
      end;
    { The player? }
    if (not Hit) and (not Player.Dead) and (Abs(Player.X - NX) < PlayerRadius + A.Info^.Radius) and
       (Abs(Player.Y - NY) < PlayerRadius + A.Info^.Radius) and
       (NZ > Player.Z - 8) and (NZ < Player.Z + PlayerHeight + 8) then
    begin
      DamagePlayer(Dice(A.MissileDamageDice, A.MissileDamageFaces), A);
      Hit := true;
    end;
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
    ExplodeMissile(A, NX, NY, NZ);
end;

procedure TDoomWorld.ExplodeMissile(const A: TDoomActor; const X, Y, Z: Single);
var
  DeathSprite: String;
begin
  A.State := asDying;
  DeathSprite := A.Info^.MoveFrames;
  if DeathSprite <> '' then A.SpritePrefix := DeathSprite;
  A.PlaySequence(A.Info^.DeathFrames, 6, false);
  if A.Info^.DeathSound <> '' then FSounds.PlayAt(A.Info^.DeathSound, A);
  if A.Info^.Sprite = 'MISL' then
    RadiusDamage(X, Y, Z, 128, 128, A);
  if A.Info = @EffectInfos[ekBfgBall] then
    BfgSpray(X, Y);
  A.VelX := 0; A.VelY := 0; A.VelZ := 0;
end;

procedure TDoomWorld.SpawnPlayerMissile(const Kind: TEffectKind);
var
  M: TDoomActor;
  Angle, Slope, CA, SA, Speed: Single;
begin
  if not FHaveRay then Exit;
  { P_SpawnPlayerMissile: autoaim (the missile turns to the angle that
    found a target), 32 units above the feet; the horizontal speed is the
    full speed and the slope adds the vertical one. Spawned 20 units ahead
    so it starts outside the player. }
  PlayerAim(1024, Angle, Slope);
  CA := Cos(DegToRad(Angle));
  SA := Sin(DegToRad(Angle));
  M := TDoomActor.Create(nil, FGraphics, @EffectInfos[Kind]);
  M.State := asMissile;
  M.FromPlayer := true;
  M.Bright := true;
  M.DoomX := Player.X + CA * 20;
  M.DoomY := Player.Y + SA * 20;
  M.DoomZ := Player.Z + 32 + Slope * 20;
  M.Sector := FMap.SectorAt(M.DoomX, M.DoomY);
  Speed := EffectInfos[Kind].Speed;
  M.VelX := CA * Speed;
  M.VelY := SA * Speed;
  M.VelZ := Slope * Speed;
  M.MissileDamageDice := EffectInfos[Kind].DamageDice;
  M.MissileDamageFaces := EffectInfos[Kind].DamageFaces;
  M.Angle := Angle;
  M.Collides := false;
  M.Pickable := false;
  M.SetLight(255);
  M.UpdateTransform;
  FActors.Add(M);
  FItems.Add(M);
  if EffectInfos[Kind].AttackSound <> '' then
    FSounds.Play(EffectInfos[Kind].AttackSound);
end;

procedure TDoomWorld.BfgSpray(const X, Y: Single);
const
  Tracers = 40;
  ConeDeg = 90;
var
  I: Integer;
  BaseAngle, Ang, Best, Dist, AngTo, Half: Single;
  O, Target: TDoomActor;
  Fx: TDoomActor;
begin
  { A_BFGSpray: 40 tracers fanned over 90 degrees from the player towards the
    explosion; each hits the first monster on its ray and deals 15d7. }
  BaseAngle := RadToDeg(ArcTan2(Y - Player.Y, X - Player.X));
  for I := 0 to Tracers - 1 do
  begin
    Ang := BaseAngle - ConeDeg / 2 + ConeDeg * I / (Tracers - 1);
    Target := nil;
    Best := 1024;
    for O in FActors do
      if (not O.Removed) and O.Pickable and (O.State in [asIdle, asChase, asAttack, asPain]) and
         ((O.Info^.Kind = tkMonster) or (O.Info^.Num = 2035)) then
      begin
        Dist := Sqrt(Sqr(O.DoomX - Player.X) + Sqr(O.DoomY - Player.Y));
        if (Dist >= Best) or (Dist < 1) then Continue;
        AngTo := RadToDeg(ArcTan2(O.DoomY - Player.Y, O.DoomX - Player.X));
        Half := RadToDeg(ArcTan2(O.Info^.Radius, Dist));
        AngTo := AngTo - Ang;
        AngTo := AngTo - 360 * Round(AngTo / 360);
        if Abs(AngTo) <= Half then
        begin
          Target := O;
          Best := Dist;
        end;
      end;
    if (Target <> nil) and CheckSight(Player.X, Player.Y, Player.Z + PlayerHeight * 0.75, Player.Sector,
       Target.DoomX, Target.DoomY, Target.DoomZ, Target.Info^.Height, Target.Sector) then
    begin
      DamageActor(Target, Dice(15, 7), Target.DoomX, Target.DoomY, Target.DoomZ + Target.Info^.Height / 2);
      { The green BFG "hit" flash on each sprayed target. }
      Fx := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekBarrelExplosion]);
      Fx.SpritePrefix := 'BFE2';
      Fx.State := asEffect;
      Fx.Bright := true;
      Fx.DoomX := Target.DoomX; Fx.DoomY := Target.DoomY; Fx.DoomZ := Target.DoomZ + Target.Info^.Height / 4;
      Fx.Sector := Target.Sector;
      Fx.Collides := false; Fx.Pickable := false;
      Fx.SetLight(255);
      Fx.PlaySequence('ABCD', 4, false);
      Fx.UpdateTransform;
      FActors.Add(Fx);
      FItems.Add(Fx);
    end;
  end;
end;

procedure TDoomWorld.DamagePlayer(const Damage: Integer; const FromActor: TDoomActor);
var
  Dmg, Saved: Integer;
begin
  if Player.Dead or (Damage <= 0) then Exit;
  if (Player.InvulnerableTics > 0) or Player.GodMode then Exit;
  Dmg := Damage;
  { P_DamageMobj: half damage for "I'm too young to die". }
  if Skill = 0 then Dmg := Max(1, Dmg div 2);
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
  { P_DamageMobj: damagecount grows by the damage after armour, up to 100. }
  Player.DamageCount := Min(100, Player.DamageCount + Dmg);
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

procedure TDoomWorld.DamageActor(const A: TDoomActor; const Damage: Integer; const HitX, HitY, HitZ: Single;
  const Attacker: TDoomActor; const ByPlayer: Boolean);
var
  Blood: TDoomActor;
begin
  if (A.State in [asDying, asDead, asEffect, asMissile]) or (Damage <= 0) then Exit;
  if not ((A.Info^.Kind = tkMonster) or (A.Info^.Num = 2035)) then Exit;
  if (Attacker = A) then Exit;
  A.Health := A.Health - Damage;
  if A.Charging then
  begin
    { P_DamageMobj: a hit stops a flying lost soul. }
    A.Charging := false;
    A.VelX := 0; A.VelY := 0; A.VelZ := 0;
  end;
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
    KillActor(A, Attacker, ByPlayer);
    Exit;
  end;
  { Getting shot wakes a monster up, and it turns on whoever hurt it
    (P_DamageMobj: the damage source becomes the new target). }
  if A.Info^.Kind = tkMonster then
  begin
    if ByPlayer then
      A.Target := nil
    else if (Attacker <> nil) and (Attacker.Info^.Kind = tkMonster) then
      A.Target := Attacker;
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
      if A.Info^.Num = 88 then
      begin
        { A_BrainPain: BBRN B for 36 tics, the scream at full volume. }
        A.PlaySequence(A.Info^.PainFrame, 36, false);
        FSounds.Play('DSBOSPN');
      end else
        A.PlaySequence(A.Info^.PainFrame, 6, false);
      if A.Info^.PainSound <> '' then FSounds.PlayAt(A.Info^.PainSound, A);
    end;
  end;
end;

procedure TDoomWorld.KillActor(const A: TDoomActor; const Killer: TDoomActor; const ByPlayer: Boolean);
var
  Drop: TDoomActor;
  Info: PThingInfo;
begin
  if A.Info^.Num = 2035 then
  begin
    ExplodeBarrel(A);
    Exit;
  end;
  if (not ByPlayer) and (Killer <> nil) and (Killer.Info^.Kind = tkMonster) then
    WritelnLog('Infight', '%s killed %s', [Killer.Info^.Sprite, A.Info^.Sprite]);
  A.State := asDying;
  A.Collides := false;
  A.Pickable := false;
  A.PlaySequence(A.Info^.DeathFrames, 5, false);
  if A.Info^.DeathSound <> '' then FSounds.PlayAt(A.Info^.DeathSound, A);
  if A.Info^.Num = 88 then
    StartBrainDeath(A)
  else
  if A.Info^.Kind = tkMonster then
  begin
    Inc(Player.Kills);
    if ByPlayer then
    begin
      Player.FaceState := 3; { evil grin }
      Player.FaceTics := 35;
    end;
    BossDeath(A);
    { A_PainDie: three lost souls at right angles. }
    if A.Info^.Num = 71 then
    begin
      PainShootSkull(A, A.Angle + 90);
      PainShootSkull(A, A.Angle + 180);
      PainShootSkull(A, A.Angle + 270);
    end;
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

function TDoomWorld.FloorRaiseToTexture(const Sec: Integer): Single;
var
  L, Side: Integer;
  Img: TDoomImage;
  MinH: Integer;
  Tex: String;
begin
  { EV_DoFloor raiseToTexture: raise by the shortest lower texture around. }
  MinH := 32000;
  for L in FMap.Sectors[Sec].Lines do
    if (FMap.Linedefs[L].Flags and ML_TWOSIDED) <> 0 then
      for Side := 0 to 1 do
        if FMap.Linedefs[L].Side[Side] >= 0 then
        begin
          Tex := FMap.Sidedefs[FMap.Linedefs[L].Side[Side]].LowerTex;
          if (Tex <> '') and (Tex <> '-') then
          begin
            Img := FGraphics.Texture(Tex);
            if (Img <> nil) and (Img.Height < MinH) then MinH := Img.Height;
          end;
        end;
  if MinH = 32000 then MinH := 0;
  Result := FMap.Sectors[Sec].FloorHeight + MinH;
end;

{ A_BossDeath: the last boss of a kind on special maps opens the way or ends the level. }
procedure TDoomWorld.BossDeath(const A: TDoomActor);
var
  O: TDoomActor;
  Num, S, Tag: Integer;
  MapName: String;
  Action: String;
begin
  Num := A.Info^.Num;
  MapName := FMap.Name;
  Action := '';
  Tag := 666;
  if FWad.IsDoom2 then
  begin
    if (MapName = 'MAP07') and (Num = 67) then Action := 'floorlower';
    if (MapName = 'MAP07') and (Num = 68) then begin Action := 'floortexture'; Tag := 667; end;
    if Num = 72 then Action := 'dooropen'; { Commander Keen, any map }
  end else
  begin
    if (MapName = 'E1M8') and (Num = 3003) then Action := 'floorlower';
    if (MapName = 'E2M8') and (Num = 16) then Action := 'exit';
    if (MapName = 'E3M8') and (Num = 7) then Action := 'exit';
    if (MapName = 'E4M6') and (Num = 16) then Action := 'doorblaze';
    if (MapName = 'E4M8') and (Num = 7) then Action := 'floorlower';
  end;
  if Action = '' then Exit;
  { Only when the last one of that kind dies. }
  for O in FActors do
    if (O <> A) and (not O.Removed) and (O.Info^.Num = Num) and
       (O.State in [asIdle, asChase, asAttack, asPain]) then
      Exit;
  WritelnLog('BossDeath', '%s: all %s dead, action %s on tag %d', [MapName, A.Info^.Sprite, Action, Tag]);
  if Action = 'exit' then
  begin
    FExitRequested := true;
    Exit;
  end;
  S := -1;
  repeat
    S := FMap.FindSectorFromTag(Tag, S);
    if S < 0 then Break;
    if Action = 'floorlower' then DoFloor(S, FMap.LowestFloorSurrounding(S), FloorSpeed)
    else if Action = 'floortexture' then DoFloor(S, FloorRaiseToTexture(S), FloorSpeed / 2)
    else if Action = 'dooropen' then DoDoor(S, true, false, false, 0)
    else if Action = 'doorblaze' then DoDoor(S, true, false, true, 0);
  until false;
end;

procedure TDoomWorld.DebugInfight;
var
  A, O, Best: TDoomActor;
  D, BestD: Single;
begin
  for A in FActors do
    if (A.Info^.Kind = tkMonster) and (A.State in [asIdle, asChase]) then
    begin
      Best := nil;
      BestD := 1e9;
      for O in FActors do
        if (O <> A) and (O.Info^.Kind = tkMonster) and (O.State in [asIdle, asChase, asAttack, asPain]) and
           not SameSpecies(A, O) then
        begin
          D := Sqr(O.DoomX - A.DoomX) + Sqr(O.DoomY - A.DoomY);
          if D < BestD then begin BestD := D; Best := O; end;
        end;
      if Best <> nil then
      begin
        A.Target := Best;
        A.Awake := true;
        A.ReactionTics := 0;
        if A.State = asIdle then
        begin
          A.State := asChase;
          A.PlaySequence(A.Info^.MoveFrames, MoveFrameTics(A.Info^.Num), true);
        end;
      end;
    end;
end;

procedure TDoomWorld.DebugKillAll;
var
  I: Integer;
  A: TDoomActor;
begin
  for I := FActors.Count - 1 downto 0 do
  begin
    A := FActors[I];
    if (A.Info^.Kind = tkMonster) and (A.State in [asIdle, asChase, asAttack, asPain]) then
      DamageActor(A, 100000, A.DoomX, A.DoomY, A.DoomZ + 32);
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
  O, Attacker: TDoomActor;
  D: Single;
  I: Integer;
  ByPlayer: Boolean;
begin
  { Who gets the blame: the player's rocket, a monster's rocket (its owner),
    or nobody (barrels, crushers). }
  Attacker := nil;
  ByPlayer := false;
  if Source = nil then ByPlayer := true
  else if Source.FromPlayer then ByPlayer := true
  else if Source.Shooter <> nil then Attacker := Source.Shooter;
  for I := FActors.Count - 1 downto 0 do
  begin
    O := FActors[I];
    if (O = Source) or O.Removed then Continue;
    if not ((O.Info^.Kind = tkMonster) or (O.Info^.Num = 2035)) then Continue;
    if O.State in [asDying, asDead] then Continue;
    { Cyberdemons and Spider Masterminds ignore splash damage (P_RadiusAttack). }
    if O.Info^.Num in [16, 7] then Continue;
    D := Max(Abs(O.DoomX - X), Abs(O.DoomY - Y)) - O.Info^.Radius;
    if D < 0 then D := 0;
    if D >= Radius then Continue;
    DamageActor(O, Damage - Trunc(D), O.DoomX, O.DoomY, O.DoomZ + 24, Attacker, ByPlayer);
  end;
  D := Max(Abs(Player.X - X), Abs(Player.Y - Y)) - PlayerRadius;
  if D < 0 then D := 0;
  if D < Radius then
    DamagePlayer(Damage - Trunc(D), Source);
end;

procedure TDoomWorld.SpawnPuff(const X, Y, Z: Single);
var
  Puff: TDoomActor;
begin
  Puff := TDoomActor.Create(nil, FGraphics, @EffectInfos[ekPuff]);
  Puff.State := asEffect;
  Puff.Bright := true;
  Puff.DoomX := X; Puff.DoomY := Y; Puff.DoomZ := Z - 4;
  Puff.Sector := FMap.SectorAt(X, Y);
  Puff.Collides := false; Puff.Pickable := false;
  Puff.SetLight(255);
  Puff.PlaySequence('ABCD', 4, false);
  Puff.UpdateTransform;
  FActors.Add(Puff);
  FItems.Add(Puff);
end;

function TDoomWorld.Shootable(const O: TDoomActor): Boolean;
begin
  Result := (not O.Removed) and O.Pickable and
    (O.State in [asIdle, asChase, asAttack, asPain]);
end;

function TDoomWorld.AimLineAttack(const Shooter: TDoomActor; const X, Y, Z, Angle, Range: Single;
  out Target: TDoomActor): Single;
type
  TIntercept = record
    Along: Single;
    Line: Integer;      { -1 for a body }
    Actor: TDoomActor;
  end;
var
  Intercepts: array of TIntercept;
  Count: Integer;

  procedure Add(const Along: Single; const Line: Integer; const Actor: TDoomActor);
  begin
    if Count = Length(Intercepts) then
      SetLength(Intercepts, Count * 2 + 16);
    Intercepts[Count].Along := Along;
    Intercepts[Count].Line := Line;
    Intercepts[Count].Actor := Actor;
    Inc(Count);
  end;

var
  DX, DY, EX, EY, T, Along, Side, TopSlope, BottomSlope, Slope,
    OpenTop, OpenBottom, ThingTop, ThingBottom: Single;
  MinX, MaxX, MinY, MaxY: Single;
  I, J, F, B: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  O: TDoomActor;
  Tmp: TIntercept;
begin
  Result := 0;
  Target := nil;
  DX := Cos(DegToRad(Angle));
  DY := Sin(DegToRad(Angle));
  EX := X + DX * Range;
  EY := Y + DY * Range;
  MinX := Min(X, EX); MaxX := Max(X, EX);
  MinY := Min(Y, EY); MaxY := Max(Y, EY);
  Count := 0;
  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if (Max(V1.X, V2.X) < MinX) or (Min(V1.X, V2.X) > MaxX) or
       (Max(V1.Y, V2.Y) < MinY) or (Min(V1.Y, V2.Y) > MaxY) then Continue;
    if SegmentsIntersect(X, Y, EX, EY, V1.X, V1.Y, V2.X, V2.Y, T) then
      Add(T * Range, I, nil);
  end;
  for O in FActors do
  begin
    if (O = Shooter) or not Shootable(O) then Continue;
    Along := (O.DoomX - X) * DX + (O.DoomY - Y) * DY;
    if (Along <= 0) or (Along >= Range) then Continue;
    Side := Abs((O.DoomX - X) * DY - (O.DoomY - Y) * DX);
    if Side > O.Info^.Radius then Continue;
    Add(Along, -1, O);
  end;
  { Nearest first (insertion sort: a few dozen intercepts). }
  for I := 1 to Count - 1 do
  begin
    Tmp := Intercepts[I];
    J := I - 1;
    while (J >= 0) and (Intercepts[J].Along > Tmp.Along) do
    begin
      Intercepts[J + 1] := Intercepts[J];
      Dec(J);
    end;
    Intercepts[J + 1] := Tmp;
  end;

  { PTR_AimTraverse. }
  TopSlope := 100 / 160;
  BottomSlope := -100 / 160;
  for I := 0 to Count - 1 do
  begin
    Along := Max(1, Intercepts[I].Along);
    if Intercepts[I].Line >= 0 then
    begin
      L := FMap.Linedefs[Intercepts[I].Line];
      F := L.FrontSector;
      B := L.BackSector;
      if (F < 0) or (B < 0) then Exit; { one-sided: stop }
      OpenTop := Min(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight);
      OpenBottom := Max(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight);
      if OpenBottom >= OpenTop then Exit; { closed door }
      if FMap.Sectors[F].FloorHeight <> FMap.Sectors[B].FloorHeight then
      begin
        Slope := (OpenBottom - Z) / Along;
        if Slope > BottomSlope then BottomSlope := Slope;
      end;
      if FMap.Sectors[F].CeilingHeight <> FMap.Sectors[B].CeilingHeight then
      begin
        Slope := (OpenTop - Z) / Along;
        if Slope < TopSlope then TopSlope := Slope;
      end;
      if TopSlope <= BottomSlope then Exit; { no view through }
    end else
    begin
      O := Intercepts[I].Actor;
      ThingTop := (O.DoomZ + O.Info^.Height - Z) / Along;
      if ThingTop < BottomSlope then Continue; { shot over the thing }
      ThingBottom := (O.DoomZ - Z) / Along;
      if ThingBottom > TopSlope then Continue; { shot under the thing }
      if ThingTop > TopSlope then ThingTop := TopSlope;
      if ThingBottom < BottomSlope then ThingBottom := BottomSlope;
      Target := O;
      Exit((ThingTop + ThingBottom) / 2);
    end;
  end;
end;

procedure TDoomWorld.PlayerLook(out Angle, Slope: Single);
var
  D: TVector3;
  H: Single;
begin
  D := CgeToDoom(FRayDir.Normalize);
  H := Sqrt(Sqr(D.X) + Sqr(D.Y));
  if H < 0.001 then
  begin
    Angle := Player.Angle;
    Slope := 0;
  end else
  begin
    Angle := RadToDeg(ArcTan2(D.Y, D.X));
    Slope := D.Z / H;
  end;
end;

function TDoomWorld.PlayerAim(const Range: Single; out Angle, Slope: Single): Boolean;
const
  AimStep = 5.625; { 1 << 26 of Doom's angle units }
var
  Base, CameraSlope, ShootZ: Single;
  Target: TDoomActor;
begin
  PlayerLook(Base, CameraSlope);
  ShootZ := Player.Z + PlayerHeight / 2 + 8;
  Angle := Base;
  Slope := AimLineAttack(nil, Player.X, Player.Y, ShootZ, Angle, Range, Target);
  if Target = nil then
  begin
    Angle := Base + AimStep;
    Slope := AimLineAttack(nil, Player.X, Player.Y, ShootZ, Angle, Range, Target);
  end;
  if Target = nil then
  begin
    Angle := Base - AimStep;
    Slope := AimLineAttack(nil, Player.X, Player.Y, ShootZ, Angle, Range, Target);
  end;
  Result := Target <> nil;
  if not Result then
  begin
    Angle := Base;
    Slope := CameraSlope;
  end;
end;

function TDoomWorld.PlayerLineAttack(const Angle, Slope, Range: Single; const Damage: Integer): TDoomActor;
var
  ShootZ, HX, HY, HZ, Dist, EX, EY, T: Single;
  HitPlayer, HitWall: Boolean;
  I: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  Shot: String;
begin
  ShootZ := Player.Z + PlayerHeight / 2 + 8;
  TraceLineAttack(nil, Player.X, Player.Y, ShootZ, Angle, Slope, Range, Result, HitPlayer, HitWall, HX, HY, HZ);

  { PTR_ShootTraverse calls P_ShootSpecialLine for every line the shot
    reaches, the wall that stops it included. }
  Dist := Sqrt(Sqr(HX - Player.X) + Sqr(HY - Player.Y));
  if HitWall then Dist := Dist + 5;
  EX := Player.X + Cos(DegToRad(Angle)) * Dist;
  EY := Player.Y + Sin(DegToRad(Angle)) * Dist;
  for I := 0 to High(FMap.Linedefs) do
  begin
    L := FMap.Linedefs[I];
    if not (L.Special in [24, 46, 47]) then Continue;
    V1 := FMap.Vertices[L.V1];
    V2 := FMap.Vertices[L.V2];
    if SegmentsIntersect(Player.X, Player.Y, EX, EY, V1.X, V1.Y, V2.X, V2.Y, T) then
      ShootSpecialLine(I);
  end;

  if Result <> nil then
    DamageActor(Result, Damage, HX, HY, HZ)
  else if HitWall then
    SpawnPuff(HX, HY, HZ);

  if DebugShots then
  begin
    if Result <> nil then
      Shot := Format('hit %s (%d health left)', [Result.Info^.Sprite, Result.Health])
    else if HitWall then
      Shot := Format('wall at (%.0f, %.0f, %.0f)', [HX, HY, HZ])
    else
      Shot := 'nothing';
    WritelnLog('Shot', Format('angle %.1f slope %.3f range %.0f: %s', [Angle, Slope, Range, Shot]));
  end;
end;

procedure TDoomWorld.FireWeapon;
var
  Ammo: TAmmoType;
  Cost, I, Dmg: Integer;
  Angle, Slope, LookAngle: Single;
  Target: TDoomActor;

  { P_Random() - P_Random() scaled to MaxDeg at the extremes. }
  function Spread(const MaxDeg: Single): Single;
  begin
    Result := (Random(256) - Random(256)) * MaxDeg / 255;
  end;

  { P_BulletSlope: bullets keep the player's angle, the slope comes from
    the autoaim (which may have found the target 5.625 degrees aside). }
  procedure BulletSlope;
  var
    AimAngle, CameraSlope: Single;
  begin
    PlayerAim(1024, AimAngle, Slope);
    PlayerLook(Angle, CameraSlope);
  end;

  { P_GunShot: 5, 10 or 15 damage; spread unless accurate (the first
    shot of the pistol or chaingun). }
  procedure GunShot(const Accurate: Boolean);
  var
    A: Single;
  begin
    A := Angle;
    if not Accurate then A := A + Spread(5.6);
    PlayerLineAttack(A, Slope, 2048, 5 * (Random(3) + 1));
  end;

begin
  if Player.Dead or (FMap = nil) or not FHaveRay then Exit;
  if Player.AttackTics > 0 then Exit;
  { A_WeaponReady only: no firing while the weapon goes down or up. }
  if Player.WeaponSwitch <> 0 then Exit;
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

  NoiseAlert;

  case Player.Weapon of
    wpFist, wpChainsaw:
      begin
        { A_Punch / A_Saw: 2..20 damage (punch x10 with berserk), aimed over
          the melee range (64, the saw 65) with a little spread. }
        Player.AttackTics := IfThen(Player.Weapon = wpFist, 20, 8);
        Dmg := 2 * (Random(10) + 1);
        if (Player.Weapon = wpFist) and (Player.BerserkTics > 0) then Dmg := Dmg * 10;
        PlayerLook(Angle, Slope);
        Angle := Angle + Spread(5.6);
        Slope := AimLineAttack(nil, Player.X, Player.Y, Player.Z + PlayerHeight / 2 + 8,
          Angle, IfThen(Player.Weapon = wpFist, 64, 65), Target);
        if Target = nil then PlayerLook(LookAngle, Slope);
        Target := PlayerLineAttack(Angle, Slope, IfThen(Player.Weapon = wpFist, 64, 65), Dmg);
        if Player.Weapon = wpChainsaw then
        begin
          if Target <> nil then FSounds.Play('DSSAWHIT') else FSounds.Play('DSSAWFUL');
        end else
        if Target <> nil then
          FSounds.Play('DSPUNCH');
      end;
    wpPistol:
      begin
        Player.AttackTics := 18;
        FSounds.Play('DSPISTOL');
        BulletSlope;
        GunShot(not Player.Refire);
      end;
    wpShotgun:
      begin
        Player.AttackTics := 36;
        FSounds.Play('DSSHOTGN');
        BulletSlope;
        for I := 1 to 7 do
          GunShot(false);
      end;
    wpSuperShotgun:
      begin
        { A_FireShotgun2: 20 pellets, wider spread and a vertical one. }
        Player.AttackTics := 56;
        FSounds.Play('DSDSHTGN');
        BulletSlope;
        for I := 1 to 20 do
          PlayerLineAttack(Angle + Spread(11.2),
            Slope + (Random(256) - Random(256)) * 32 / 65536, 2048, 5 * (Random(3) + 1));
      end;
    wpChaingun:
      begin
        Player.AttackTics := 8;
        FSounds.Play('DSPISTOL');
        BulletSlope;
        GunShot(not Player.Refire);
      end;
    wpMissile:
      begin
        Player.AttackTics := 32;
        SpawnPlayerMissile(ekRocket);
      end;
    wpPlasma:
      begin
        Player.AttackTics := 8;
        SpawnPlayerMissile(ekPlasmaBall);
      end;
    wpBfg:
      begin
        { Doom charges the BFG for 40 tics (sound at the trigger pull),
          then launches the ball. }
        Player.AttackTics := 60;
        FSounds.Play('DSBFG');
        FBfgCountdown := 40;
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
    { P_GiveAmmo: double ammo on the easiest and the Nightmare skill. }
    if Skill in [0, 4] then
      Player.Ammo[T] := Min(Player.MaxAmmo[T], Player.Ammo[T] + Amount * 2)
    else
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
      ChangeWeapon(W);
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
    Msg := Text(PickupMessageKey(P, Player.Health < 25), PickupMessage(P, Player.Health < 25));
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
      pkBerserk: begin Player.BerserkTics := 60 * TicRate; GiveHealth(100, 100); ChangeWeapon(wpFist); Sound := 'DSGETPOW'; end;
      pkInvulnerability: begin Player.InvulnerableTics := 30 * TicRate; Sound := 'DSGETPOW'; end;
      pkInvisibility: begin Player.InvisibleTics := 60 * TicRate; Sound := 'DSGETPOW'; end;
      pkRadSuit: begin Player.RadSuitTics := 60 * TicRate; Sound := 'DSGETPOW'; end;
      pkComputerMap: Sound := 'DSGETPOW';
      pkLightAmp: begin Player.LightAmpTics := 120 * TicRate; Sound := 'DSGETPOW'; end;
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
      Player.BonusCount := Player.BonusCount + 6; { BONUSADD }
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
  Color, What, KeyName: String;
begin
  Result := (Key in Player.Keys) or (Skull in Player.Keys);
  if Result then Exit;
  case Key of
    keyBlue: begin Color := 'blue'; KeyName := 'BLUE'; end;
    keyYellow: begin Color := 'yellow'; KeyName := 'YELLOW'; end;
    else begin Color := 'red'; KeyName := 'RED'; end;
  end;
  if IsDoor then What := 'open this door' else What := 'activate this object';
  { PD_BLUEK (doors) / PD_BLUEO (switches) like vanilla. }
  if IsDoor then KeyName := 'PD_' + KeyName + 'K' else KeyName := 'PD_' + KeyName + 'O';
  ShowMessage(Text(KeyName, Format('You need a %s key to %s', [Color, What])));
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

procedure TDoomWorld.MonsterCrossLines(const A: TDoomActor; const OldX, OldY: Single);
var
  I, L, Special: Integer;
  V1, V2: TDoomVertex;
  T: Single;
begin
  for I := 0 to High(FMonsterCrossLines) do
  begin
    L := FMonsterCrossLines[I];
    Special := FMap.Linedefs[L].Special;
    if not (Special in MonsterCrossSpecials) then Continue; { a W1 already used }
    V1 := FMap.Vertices[FMap.Linedefs[L].V1];
    V2 := FMap.Vertices[FMap.Linedefs[L].V2];
    if not SegmentsIntersect(OldX, OldY, A.DoomX, A.DoomY, V1.X, V1.Y, V2.X, V2.Y, T) then Continue;
    case Special of
      39, 97, 125, 126:
        { EV_Teleport: only from the front side. }
        if (FMap.PointOnLineSide(OldX, OldY, L) = 0) and TeleportActor(A, L) then
        begin
          if Special in [39, 125] then FMap.Linedefs[L].Special := 0;
          Exit; { it is somewhere else now }
        end;
      else
        ApplySpecial(L, acCross, true);
    end;
  end;
end;

function TDoomWorld.TeleportActor(const A: TDoomActor; const Line: Integer): Boolean;
var
  Tag, S: Integer;
  D, O: TDoomActor;
  Z: Single;
  TeleFrag: Boolean;
begin
  Result := false;
  Tag := FMap.Linedefs[Line].Tag;
  { P_TeleportMove: monsters only telefrag on MAP30. }
  TeleFrag := FMap.Name = 'MAP30';
  S := -1;
  repeat
    S := FMap.FindSectorFromTag(Tag, S);
    if S < 0 then Exit;
    for D in FActors do
      if (D.Info^.Kind = tkTeleportDest) and (D.Sector = S) then
      begin
        Z := FMap.Sectors[S].FloorHeight;
        for O in FActors do
          if (O <> A) and (not O.Removed) and O.Collides and
             (O.Info^.Kind in [tkMonster, tkDecoration, tkPickup]) and
             (O.State in [asIdle, asChase, asAttack, asPain]) and
             (Abs(O.DoomX - D.DoomX) < O.Info^.Radius + A.Info^.Radius) and
             (Abs(O.DoomY - D.DoomY) < O.Info^.Radius + A.Info^.Radius) then
          begin
            if not TeleFrag then Exit;
            DamageActor(O, 10000, O.DoomX, O.DoomY, O.DoomZ + 32, nil, false);
          end;
        if (not Player.Dead) and (Abs(Player.X - D.DoomX) < PlayerRadius + A.Info^.Radius) and
           (Abs(Player.Y - D.DoomY) < PlayerRadius + A.Info^.Radius) then
        begin
          if not TeleFrag then Exit;
          DamagePlayer(10000, A);
        end;
        SpawnFog(A.DoomX, A.DoomY, A.DoomZ, A.Sector);
        A.DoomX := D.DoomX;
        A.DoomY := D.DoomY;
        A.DoomZ := Z;
        A.Sector := S;
        A.Angle := D.Angle;
        A.VelX := 0; A.VelY := 0; A.VelZ := 0;
        A.UpdateTransform;
        SpawnFog(D.DoomX + Cos(DegToRad(D.Angle)) * 20, D.DoomY + Sin(DegToRad(D.Angle)) * 20, Z, S);
        WritelnLog('Teleport', '%s teleported to (%.0f, %.0f) by line %d', [A.Info^.Sprite, D.DoomX, D.DoomY, Line]);
        Exit(true);
      end;
  until false;
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
  if ByMonster and not (Special in [1, 117, 2, 4, 108, 90, 105, 86, 106, 10, 88, 39, 97, 125, 126]) then Exit;

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

{$I doomworld_save.inc}

initialization
  InitEffectInfos;
end.
