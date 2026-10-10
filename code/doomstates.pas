{ Vanilla Doom's state table (info.c): every animation frame of every thing
  and weapon with its sprite, frame letter, duration, action (code
  pointer) and successor, and the state and sound fields of the thing
  types (mobjinfo). The tables are generated into doomstates_table.inc by
  tools/make_states.py; the live copies here are what DeHackEd patches
  edit ("Frame N", "Pointer N", "[CODEPTR]", a thing's "Initial frame"...)
  and what DoomThings walks to build each thing's frame sequences. }
unit DoomStates;

interface

{$I doomstates_table.inc}

type
  { A frame sequence walked out of the state table: one entry per state,
    in play order. Tics are at least 1 (a state's -1, "stay forever",
    ends the walk with Forever set). }
  TFrameSeq = record
    { Frame letters ('A'..), one per entry. }
    Frames: String;
    Sprites: array of String;
    Tics: array of Integer;
    Bright: array of Boolean;
    Actions: array of TStateAction;
    { The chain came back to a state already in the sequence (an idle or
      walking loop) / ended on a state that lasts forever (a corpse). }
    Loop, Forever: Boolean;
  end;

type
  { d_items.c's weaponinfo: the ammo (0 clip, 1 shell, 2 cell, 3 rocket,
    5 none) and the entry states of each weapon, in the port's TWeapon
    order (fist, pistol, shotgun, chaingun, rocket launcher, plasma, BFG,
    chainsaw, super shotgun). DeHackEd's "Weapon N". }
  TWeaponDef = record
    Ammo, Up, Down, Ready, Attack, Flash: Integer;
  end;

var
  { The live tables (vanilla after ResetStates, then DeHackEd's edits). }
  Weapons: array [0..8] of TWeaponDef;
  Sprites: array of String;
  States: array of TStateDef;
  Mobjs: array of TMobjDef;
  Sounds: array of String;

{ Back to vanilla. }
procedure ResetStates;

{ Walk the chain from state Start (0 = S_NULL gives an empty sequence):
  until S_NULL, a state already visited, one of Stop (another entry state
  of the same thing: the attack ends where the walk would re-enter the
  walking frames), a forever state, or MaxLen states. Zero-tic states
  contribute their action to the next frame and no frame of their own. }
function WalkStates(const Start: Integer; const Stop: array of Integer;
  const MaxLen: Integer = 64): TFrameSeq;

{ The mobjinfo row with this THINGS type number, -1 if none. }
function MobjIndexOf(const DoomedNum: Integer): Integer;

{ The action with this name (A_PosAttack; case-insensitive, a missing
  "A_" prefix is fine; NULL or '' is saNone). }
function ActionByName(const Name: String; out Action: TStateAction): Boolean;

{ The sprite index with this four-letter name, -1 if none. }
function SpriteIndexOf(const Name: String): Integer;

{ The sound's lump name (DSPISTOL), '' for 0 or out of range. }
function SoundName(const Index: Integer): String;

{ Whether an action attacks (the ones DoomWorld dispatches on). }
function IsAttackAction(const Action: TStateAction): Boolean;

{ The state with this name (PISTOL1 or S_PISTOL1), -1 if none. }
function StateByName(const Name: String): Integer;

implementation

uses SysUtils;

const
  VanillaWeaponStates: array [0..8, 0..4] of String = (
    ('PUNCHUP', 'PUNCHDOWN', 'PUNCH', 'PUNCH1', 'NULL'),
    ('PISTOLUP', 'PISTOLDOWN', 'PISTOL', 'PISTOL1', 'PISTOLFLASH'),
    ('SGUNUP', 'SGUNDOWN', 'SGUN', 'SGUN1', 'SGUNFLASH1'),
    ('CHAINUP', 'CHAINDOWN', 'CHAIN', 'CHAIN1', 'CHAINFLASH1'),
    ('MISSILEUP', 'MISSILEDOWN', 'MISSILE', 'MISSILE1', 'MISSILEFLASH1'),
    ('PLASMAUP', 'PLASMADOWN', 'PLASMA', 'PLASMA1', 'PLASMAFLASH1'),
    ('BFGUP', 'BFGDOWN', 'BFG', 'BFG1', 'BFGFLASH1'),
    ('SAWUP', 'SAWDOWN', 'SAW', 'SAW1', 'NULL'),
    ('DSGUNUP', 'DSGUNDOWN', 'DSGUN', 'DSGUN1', 'DSGUNFLASH1'));
  VanillaWeaponAmmo: array [0..8] of Integer = (5, 0, 1, 0, 3, 2, 2, 5, 1);

function StateByName(const Name: String): Integer;
var
  I: Integer;
  N: String;
begin
  N := UpperCase(Name);
  if Copy(N, 1, 2) = 'S_' then N := Copy(N, 3, MaxInt);
  for I := 0 to VanillaStateCount - 1 do
    if VanillaStateNames[I] = N then
      Exit(I);
  Result := -1;
end;

procedure ResetStates;
var
  I: Integer;
begin
  for I := 0 to 8 do
  begin
    Weapons[I].Ammo := VanillaWeaponAmmo[I];
    Weapons[I].Up := StateByName(VanillaWeaponStates[I, 0]);
    Weapons[I].Down := StateByName(VanillaWeaponStates[I, 1]);
    Weapons[I].Ready := StateByName(VanillaWeaponStates[I, 2]);
    Weapons[I].Attack := StateByName(VanillaWeaponStates[I, 3]);
    Weapons[I].Flash := StateByName(VanillaWeaponStates[I, 4]);
  end;
  SetLength(Sprites, VanillaSpriteCount);
  for I := 0 to VanillaSpriteCount - 1 do
    Sprites[I] := VanillaSprites[I];
  SetLength(States, VanillaStateCount);
  for I := 0 to VanillaStateCount - 1 do
    States[I] := VanillaStates[I];
  SetLength(Mobjs, VanillaMobjCount);
  for I := 0 to VanillaMobjCount - 1 do
    Mobjs[I] := VanillaMobjs[I];
  SetLength(Sounds, VanillaSoundCount);
  for I := 0 to VanillaSoundCount - 1 do
    Sounds[I] := VanillaSounds[I];
end;

function WalkStates(const Start: Integer; const Stop: array of Integer;
  const MaxLen: Integer): TFrameSeq;
var
  Visited: array of Integer;
  S, I, N: Integer;
  PendingAction: TStateAction;
  IsStop, Seen: Boolean;
begin
  Result := Default(TFrameSeq);
  S := Start;
  PendingAction := saNone;
  N := 0;
  while (S > 0) and (S < Length(States)) and (N < MaxLen) do
  begin
    Seen := false;
    for I := 0 to High(Visited) do
      if Visited[I] = S then
      begin
        Seen := true;
        Break;
      end;
    if Seen then
    begin
      Result.Loop := true;
      Break;
    end;
    if S <> Start then
    begin
      IsStop := false;
      for I := 0 to High(Stop) do
        if Stop[I] = S then
        begin
          IsStop := true;
          Break;
        end;
      if IsStop then Break;
    end;
    SetLength(Visited, Length(Visited) + 1);
    Visited[High(Visited)] := S;
    if States[S].Tics = 0 then
    begin
      { An instant state: its action goes with the next frame. }
      if States[S].Action <> saNone then PendingAction := States[S].Action;
      S := States[S].Next;
      Continue;
    end;
    SetLength(Result.Sprites, N + 1);
    SetLength(Result.Tics, N + 1);
    SetLength(Result.Bright, N + 1);
    SetLength(Result.Actions, N + 1);
    if (States[S].Sprite >= 0) and (States[S].Sprite < Length(Sprites)) then
      Result.Sprites[N] := Sprites[States[S].Sprite]
    else
      Result.Sprites[N] := 'TROO';
    Result.Frames := Result.Frames + Chr(Ord('A') + (States[S].Frame and $7FFF) mod 32);
    Result.Bright[N] := (States[S].Frame and $8000) <> 0;
    if States[S].Action <> saNone then
      Result.Actions[N] := States[S].Action
    else
      Result.Actions[N] := PendingAction;
    PendingAction := saNone;
    if States[S].Tics < 0 then
    begin
      Result.Tics[N] := 1;
      Result.Forever := true;
      Inc(N);
      Break;
    end;
    Result.Tics[N] := States[S].Tics;
    Inc(N);
    S := States[S].Next;
  end;
end;

function MobjIndexOf(const DoomedNum: Integer): Integer;
var
  I: Integer;
begin
  if DoomedNum > 0 then
    for I := 0 to High(Mobjs) do
      if Mobjs[I].DoomedNum = DoomedNum then
        Exit(I);
  Result := -1;
end;

function ActionByName(const Name: String; out Action: TStateAction): Boolean;
var
  A: TStateAction;
  N: String;
begin
  N := Trim(Name);
  if (N = '') or SameText(N, 'NULL') then
  begin
    Action := saNone;
    Exit(true);
  end;
  if not SameText(Copy(N, 1, 2), 'A_') then N := 'A_' + N;
  for A := Low(TStateAction) to High(TStateAction) do
    if SameText(ActionNames[A], N) then
    begin
      Action := A;
      Exit(true);
    end;
  Action := saNone;
  Result := false;
end;

function SpriteIndexOf(const Name: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Sprites) do
    if SameText(Sprites[I], Name) then
      Exit(I);
  Result := -1;
end;

function SoundName(const Index: Integer): String;
begin
  if (Index > 0) and (Index < Length(Sounds)) then
    Result := Sounds[Index]
  else
    Result := '';
end;

function IsAttackAction(const Action: TStateAction): Boolean;
begin
  Result := Action in [saPosAttack, saSPosAttack, saCPosAttack, saTroopAttack,
    saSargAttack, saHeadAttack, saBruisAttack, saSkullAttack, saCyberAttack,
    saFatAttack1, saFatAttack2, saFatAttack3, saBspiAttack, saSkelMissile,
    saSkelFist, saVileAttack, saPainAttack, saBrainSpit];
end;

initialization
  ResetStates;
end.
