{ Doom thing types (the "mobjinfo" table from info.c, reduced to what this
  port needs): which sprite a map thing uses, its size, whether it blocks,
  what picking it up does, and a few monster parameters. }
unit DoomThings;

interface

type
  TThingKind = (
    tkNone,
    tkMonster,
    tkDecoration,
    tkPickup,
    tkPlayerStart,
    tkTeleportDest,
    tkInvisible,
    { Kept as hidden actors: Icon of Sin spawn spots (87) and shooter (89). }
    tkBossSpot
  );

  TPickupKind = (
    pkNone,
    pkStimpack, pkMedikit, pkHealthBonus, pkArmorBonus, pkArmorGreen, pkArmorBlue,
    pkSoulsphere, pkMegasphere, pkBerserk, pkInvulnerability, pkInvisibility,
    pkRadSuit, pkComputerMap, pkLightAmp,
    pkKeyBlue, pkKeyYellow, pkKeyRed, pkSkullBlue, pkSkullYellow, pkSkullRed,
    pkClip, pkClipBox, pkShells, pkShellBox, pkRocket, pkRocketBox, pkCell, pkCellPack, pkBackpack,
    pkShotgun, pkSuperShotgun, pkChaingun, pkRocketLauncher, pkPlasma, pkBFG, pkChainsaw
  );

  TAttackKind = (akNone, akMelee, akHitscan, akMissile);

  TThingInfo = record
    Num: Integer;
    Sprite: String;
    Kind: TThingKind;
    Radius, Height: Integer;
    Solid: Boolean;
    { Spawns attached to the ceiling (hanging bodies, Keen). }
    Hanging: Boolean;
    { Flying monsters (cacodemon, lost soul, pain elemental). }
    Floats: Boolean;
    { Frames cycled while idle, and tics per frame. }
    IdleFrames: String;
    IdleTics: Integer;
    MoveFrames: String;
    AttackFrames: String;
    PainFrame: Char;
    DeathFrames: String;
    Health: Integer;
    Speed: Integer;
    PainChance: Integer;
    Attack: TAttackKind;
    { Damage = Dice * (1..DamageFaces) like Doom's P_Random() % n + 1. }
    DamageDice, DamageFaces: Integer;
    Pickup: TPickupKind;
    SeeSound, AttackSound, PainSound, DeathSound: String;
    { Thing type dropped on death (clip, shotgun...), 0 for none. }
    Drop: Integer;
  end;
  PThingInfo = ^TThingInfo;

{ Lookup by the THINGS lump type number. Returns nil for unknown types. }
function FindThingInfo(const Num: Integer): PThingInfo;

{ Doom's pickup messages. }
function PickupMessage(const Pickup: TPickupKind; const LowHealth: Boolean): String;

implementation

uses SysUtils, Generics.Collections;

var
  Infos: array of TThingInfo;
  Index: {$ifdef FPC}specialize{$endif} TDictionary<Integer, Integer>;

function BaseInfo(const Num: Integer; const Sprite: String; const Kind: TThingKind;
  const Radius, Height: Integer): TThingInfo;
begin
  Result := Default(TThingInfo);
  Result.Num := Num;
  Result.Sprite := Sprite;
  Result.Kind := Kind;
  Result.Radius := Radius;
  Result.Height := Height;
  Result.IdleFrames := 'A';
  Result.IdleTics := 6;
  Result.PainFrame := #0;
end;

procedure Add(const Info: TThingInfo);
begin
  SetLength(Infos, Length(Infos) + 1);
  Infos[High(Infos)] := Info;
  Index.AddOrSetValue(Info.Num, High(Infos));
end;

procedure Monster(const Num: Integer; const Sprite: String;
  const Radius, Height, Health, Speed, PainChance: Integer;
  const Idle, Move, AttackFr: String; const Pain: Char; const Death: String;
  const Attack: TAttackKind; const DamageDice, DamageFaces: Integer;
  const SeeSnd, AttackSnd, PainSnd, DeathSnd: String; const Drop: Integer = 0;
  const Floats: Boolean = false);
var
  I: TThingInfo;
begin
  I := BaseInfo(Num, Sprite, tkMonster, Radius, Height);
  I.Solid := true;
  I.Health := Health;
  I.Speed := Speed;
  I.PainChance := PainChance;
  I.IdleFrames := Idle;
  I.IdleTics := 10;
  I.MoveFrames := Move;
  I.AttackFrames := AttackFr;
  I.PainFrame := Pain;
  I.DeathFrames := Death;
  I.Attack := Attack;
  I.DamageDice := DamageDice;
  I.DamageFaces := DamageFaces;
  I.SeeSound := SeeSnd;
  I.AttackSound := AttackSnd;
  I.PainSound := PainSnd;
  I.DeathSound := DeathSnd;
  I.Drop := Drop;
  I.Floats := Floats;
  Add(I);
end;

procedure Decor(const Num: Integer; const Sprite: String; const Solid: Boolean;
  const Radius, Height: Integer; const Frames: String = 'A'; const Hanging: Boolean = false);
var
  I: TThingInfo;
begin
  I := BaseInfo(Num, Sprite, tkDecoration, Radius, Height);
  I.Solid := Solid;
  I.Hanging := Hanging;
  I.IdleFrames := Frames;
  I.IdleTics := 6;
  Add(I);
end;

procedure Pickup(const Num: Integer; const Sprite: String; const Kind: TPickupKind;
  const Frames: String = 'A');
var
  I: TThingInfo;
begin
  I := BaseInfo(Num, Sprite, tkPickup, 20, 16);
  I.Pickup := Kind;
  I.IdleFrames := Frames;
  I.IdleTics := 6;
  Add(I);
end;

procedure Special(const Num: Integer; const Kind: TThingKind);
begin
  Add(BaseInfo(Num, '', Kind, 16, 56));
end;

procedure BuildTable;
begin
  Index := {$ifdef FPC}specialize{$endif} TDictionary<Integer, Integer>.Create;

  { Player starts, deathmatch starts, teleport destination. }
  Special(1, tkPlayerStart);
  Special(2, tkPlayerStart);
  Special(3, tkPlayerStart);
  Special(4, tkPlayerStart);
  Special(11, tkInvisible);
  Special(14, tkTeleportDest);
  Special(87, tkBossSpot); { boss spawn spot (MT_BOSSTARGET) }
  Special(89, tkBossSpot); { boss brain shooter (MT_BOSSSPIT) }

  { Monsters: num, sprite, radius, height, hp, speed, pain chance,
    idle, move, attack, pain, death frames, attack kind, damage, sounds, drop }
  Monster(3004, 'POSS', 20, 56, 20, 8, 200, 'AB', 'ABCD', 'EF', 'G', 'HIJKL', akHitscan, 3, 5, 'DSPOSIT1', 'DSPISTOL', 'DSPOPAIN', 'DSPODTH1', 2007);
  Monster(9, 'SPOS', 20, 56, 30, 8, 170, 'AB', 'ABCD', 'EF', 'G', 'HIJKL', akHitscan, 3, 5, 'DSPOSIT2', 'DSSHOTGN', 'DSPOPAIN', 'DSPODTH2', 2001);
  Monster(65, 'CPOS', 20, 56, 70, 8, 170, 'AB', 'ABCD', 'EF', 'G', 'HIJKLMN', akHitscan, 3, 5, 'DSPOSIT2', 'DSSHOTGN', 'DSPOPAIN', 'DSPODTH2', 2002);
  Monster(3001, 'TROO', 20, 56, 60, 8, 200, 'AB', 'ABCD', 'EFG', 'H', 'IJKLM', akMissile, 3, 8, 'DSBGSIT1', 'DSFIRSHT', 'DSDMPAIN', 'DSBGDTH1');
  Monster(3002, 'SARG', 30, 56, 150, 10, 180, 'AB', 'ABCD', 'EFG', 'H', 'IJKLMN', akMelee, 4, 10, 'DSSGTSIT', 'DSSGTATK', 'DSDMPAIN', 'DSSGTDTH');
  Monster(58, 'SARG', 30, 56, 150, 10, 180, 'AB', 'ABCD', 'EFG', 'H', 'IJKLMN', akMelee, 4, 10, 'DSSGTSIT', 'DSSGTATK', 'DSDMPAIN', 'DSSGTDTH');
  Monster(3006, 'SKUL', 16, 56, 100, 8, 256, 'AB', 'AB', 'CD', 'E', 'FGHIJK', akMissile, 3, 8, '', 'DSSKLATK', 'DSDMPAIN', 'DSFIRXPL', 0, true);
  Monster(3005, 'HEAD', 31, 56, 400, 8, 128, 'A', 'A', 'BCD', 'E', 'GHIJKL', akMissile, 5, 8, 'DSCACSIT', 'DSFIRSHT', 'DSDMPAIN', 'DSCACDTH', 0, true);
  Monster(3003, 'BOSS', 24, 64, 1000, 8, 50, 'AB', 'ABCD', 'EFG', 'H', 'IJKLMNO', akMissile, 8, 8, 'DSBRSSIT', 'DSFIRSHT', 'DSDMPAIN', 'DSBRSDTH');
  Monster(69, 'BOS2', 24, 64, 500, 8, 50, 'AB', 'ABCD', 'EFG', 'H', 'IJKLMNO', akMissile, 8, 8, 'DSBRSSIT', 'DSFIRSHT', 'DSDMPAIN', 'DSBRSDTH');
  Monster(16, 'CYBR', 40, 110, 4000, 16, 20, 'AB', 'ABCD', 'EF', 'G', 'HIJKLMNOP', akMissile, 20, 8, 'DSCYBSIT', 'DSRLAUNC', 'DSDMPAIN', 'DSCYBDTH');
  Monster(7, 'SPID', 128, 100, 3000, 12, 40, 'AB', 'ABCDEF', 'GH', 'I', 'JKLMNOPQRS', akHitscan, 3, 5, 'DSSPISIT', 'DSSHOTGN', 'DSDMPAIN', 'DSSPIDTH');
  Monster(64, 'VILE', 20, 56, 700, 15, 10, 'AB', 'ABCDEF', 'GHIJKLMNOP', 'Q', 'QRSTUVWXYZ', akHitscan, 8, 8, 'DSVILSIT', 'DSVILATK', 'DSVIPAIN', 'DSVILDTH');
  Monster(66, 'SKEL', 20, 56, 300, 10, 100, 'AB', 'ABCDEF', 'GHIJK', 'L', 'LMNOP', akMissile, 10, 6, 'DSSKESIT', 'DSSKEATK', 'DSPOPAIN', 'DSSKEDTH');
  Monster(67, 'FATT', 48, 64, 600, 8, 80, 'AB', 'ABCDEF', 'GHI', 'J', 'KLMNOPQRST', akMissile, 8, 8, 'DSMANSIT', 'DSMANATK', 'DSMNPAIN', 'DSMANDTH');
  Monster(68, 'BSPI', 64, 64, 500, 12, 128, 'AB', 'ABCDEF', 'GH', 'I', 'JKLMNOP', akMissile, 5, 8, 'DSBSPSIT', 'DSPLASMA', 'DSDMPAIN', 'DSBSPDTH');
  Monster(71, 'PAIN', 31, 56, 400, 8, 128, 'AB', 'ABC', 'DEF', 'G', 'HIJKLM', akMissile, 3, 8, 'DSPESIT', 'DSSKLATK', 'DSPEPAIN', 'DSPEDTH', 0, true);
  Monster(84, 'SSWV', 20, 56, 50, 8, 170, 'AB', 'ABCD', 'EFG', 'H', 'IJKLM', akHitscan, 3, 5, 'DSSSSIT', 'DSPISTOL', 'DSPOPAIN', 'DSSSDTH', 2007);
  Monster(72, 'KEEN', 16, 72, 100, 0, 256, 'A', 'A', '', 'M', 'BCDEFGHIJKL', akNone, 0, 0, '', '', 'DSKEENPN', 'DSKEENDT');
  { Boss brain: its pain and death sounds play at full volume from DoomWorld. }
  Monster(88, 'BBRN', 16, 16, 250, 0, 255, 'A', 'A', '', 'B', 'A', akNone, 0, 0, '', '', '', '');
  Infos[High(Infos) - 1].Hanging := true; { Keen hangs from the ceiling }

  { Weapons }
  Pickup(2001, 'SHOT', pkShotgun);
  Pickup(82, 'SGN2', pkSuperShotgun);
  Pickup(2002, 'MGUN', pkChaingun);
  Pickup(2003, 'LAUN', pkRocketLauncher);
  Pickup(2004, 'PLAS', pkPlasma);
  Pickup(2005, 'CSAW', pkChainsaw);
  Pickup(2006, 'BFUG', pkBFG);

  { Ammo }
  Pickup(2007, 'CLIP', pkClip);
  Pickup(2048, 'AMMO', pkClipBox);
  Pickup(2008, 'SHEL', pkShells);
  Pickup(2049, 'SBOX', pkShellBox);
  Pickup(2010, 'ROCK', pkRocket);
  Pickup(2046, 'BROK', pkRocketBox);
  Pickup(2047, 'CELL', pkCell);
  Pickup(17, 'CELP', pkCellPack);
  Pickup(8, 'BPAK', pkBackpack);

  { Health, armor, powerups }
  Pickup(2011, 'STIM', pkStimpack);
  Pickup(2012, 'MEDI', pkMedikit);
  Pickup(2014, 'BON1', pkHealthBonus, 'ABCDCB');
  Pickup(2015, 'BON2', pkArmorBonus, 'ABCDCB');
  Pickup(2018, 'ARM1', pkArmorGreen, 'AB');
  Pickup(2019, 'ARM2', pkArmorBlue, 'AB');
  Pickup(2013, 'SOUL', pkSoulsphere, 'ABCDCB');
  Pickup(83, 'MEGA', pkMegasphere, 'ABCD');
  Pickup(2022, 'PINV', pkInvulnerability, 'ABCD');
  Pickup(2023, 'PSTR', pkBerserk);
  Pickup(2024, 'PINS', pkInvisibility, 'ABCD');
  Pickup(2025, 'SUIT', pkRadSuit);
  Pickup(2026, 'PMAP', pkComputerMap, 'ABCDCB');
  Pickup(2045, 'PVIS', pkLightAmp, 'AB');

  { Keys }
  Pickup(5, 'BKEY', pkKeyBlue, 'AB');
  Pickup(6, 'YKEY', pkKeyYellow, 'AB');
  Pickup(13, 'RKEY', pkKeyRed, 'AB');
  Pickup(40, 'BSKU', pkSkullBlue, 'AB');
  Pickup(39, 'YSKU', pkSkullYellow, 'AB');
  Pickup(38, 'RSKU', pkSkullRed, 'AB');

  { Decorations: num, sprite, solid, radius, height, frames, hanging }
  Decor(2035, 'BAR1', true, 10, 42, 'AB');
  Decor(2028, 'COLU', true, 16, 48);
  Decor(30, 'COL1', true, 16, 48);
  Decor(31, 'COL2', true, 16, 40);
  Decor(32, 'COL3', true, 16, 48);
  Decor(33, 'COL4', true, 16, 40);
  Decor(36, 'COL5', true, 16, 40, 'AB');
  Decor(37, 'COL6', true, 16, 40);
  Decor(41, 'CEYE', true, 16, 54, 'ABCB');
  Decor(42, 'FSKU', true, 16, 48, 'ABC');
  Decor(43, 'TRE1', true, 16, 56);
  Decor(54, 'TRE2', true, 32, 108);
  Decor(44, 'TBLU', true, 16, 68, 'ABCD');
  Decor(45, 'TGRN', true, 16, 68, 'ABCD');
  Decor(46, 'TRED', true, 16, 68, 'ABCD');
  Decor(55, 'SMBT', true, 16, 37, 'ABCD');
  Decor(56, 'SMGT', true, 16, 37, 'ABCD');
  Decor(57, 'SMRT', true, 16, 37, 'ABCD');
  Decor(47, 'SMIT', true, 16, 40);
  Decor(48, 'ELEC', true, 16, 128);
  Decor(34, 'CAND', false, 20, 16);
  Decor(35, 'CBRA', true, 16, 60);
  Decor(85, 'TLMP', true, 16, 80, 'ABCD');
  Decor(86, 'TLP2', true, 16, 60, 'ABCD');
  Decor(70, 'FCAN', true, 10, 42, 'ABC');
  Decor(49, 'GOR1', true, 16, 68, 'ABCB', true);
  Decor(50, 'GOR2', true, 16, 84, 'A', true);
  Decor(51, 'GOR3', true, 16, 84, 'A', true);
  Decor(52, 'GOR4', true, 16, 68, 'A', true);
  Decor(53, 'GOR5', true, 16, 52, 'A', true);
  Decor(59, 'GOR2', false, 20, 84, 'A', true);
  Decor(60, 'GOR4', false, 20, 68, 'A', true);
  Decor(61, 'GOR3', false, 20, 52, 'A', true);
  Decor(62, 'GOR5', false, 20, 52, 'A', true);
  Decor(63, 'GOR1', false, 20, 68, 'ABCB', true);
  Decor(73, 'HDB1', true, 16, 88, 'A', true);
  Decor(74, 'HDB2', true, 16, 88, 'A', true);
  Decor(75, 'HDB3', true, 16, 64, 'A', true);
  Decor(76, 'HDB4', true, 16, 64, 'A', true);
  Decor(77, 'HDB5', true, 16, 64, 'A', true);
  Decor(78, 'HDB6', true, 16, 64, 'A', true);
  Decor(25, 'POL1', true, 16, 64);
  Decor(26, 'POL6', true, 16, 64, 'AB');
  Decor(27, 'POL4', true, 16, 64);
  Decor(28, 'POL2', true, 16, 64);
  Decor(29, 'POL3', true, 16, 64, 'AB');
  Decor(24, 'POL5', false, 20, 16);
  Decor(79, 'POB1', false, 20, 16);
  Decor(80, 'POB2', false, 20, 16);
  Decor(81, 'BRS1', false, 20, 16);
  Decor(10, 'PLAY', false, 20, 16, 'W');
  Decor(12, 'PLAY', false, 20, 16, 'W');
  Decor(15, 'PLAY', false, 20, 16, 'N');
  Decor(18, 'POSS', false, 20, 16, 'L');
  Decor(19, 'SPOS', false, 20, 16, 'L');
  Decor(20, 'TROO', false, 20, 16, 'M');
  Decor(21, 'SARG', false, 20, 16, 'N');
  Decor(22, 'HEAD', false, 20, 16, 'L');
  Decor(23, 'SKUL', false, 20, 16, 'K');
end;

function FindThingInfo(const Num: Integer): PThingInfo;
var
  I: Integer;
begin
  if Index.TryGetValue(Num, I) then
    Result := @Infos[I]
  else
    Result := nil;
end;

function PickupMessage(const Pickup: TPickupKind; const LowHealth: Boolean): String;
begin
  case Pickup of
    pkStimpack: Result := 'Picked up a stimpack.';
    pkMedikit:
      if LowHealth then
        Result := 'Picked up a medikit that you REALLY need!'
      else
        Result := 'Picked up a medikit.';
    pkHealthBonus: Result := 'Picked up a health bonus.';
    pkArmorBonus: Result := 'Picked up an armor bonus.';
    pkArmorGreen: Result := 'Picked up the armor.';
    pkArmorBlue: Result := 'Picked up the MegaArmor!';
    pkSoulsphere: Result := 'Supercharge!';
    pkMegasphere: Result := 'MegaSphere!';
    pkBerserk: Result := 'Berserk!';
    pkInvulnerability: Result := 'Invulnerability!';
    pkInvisibility: Result := 'Partial Invisibility';
    pkRadSuit: Result := 'Radiation Shielding Suit';
    pkComputerMap: Result := 'Computer Area Map';
    pkLightAmp: Result := 'Light Amplification Visor';
    pkKeyBlue: Result := 'Picked up a blue keycard.';
    pkKeyYellow: Result := 'Picked up a yellow keycard.';
    pkKeyRed: Result := 'Picked up a red keycard.';
    pkSkullBlue: Result := 'Picked up a blue skull key.';
    pkSkullYellow: Result := 'Picked up a yellow skull key.';
    pkSkullRed: Result := 'Picked up a red skull key.';
    pkClip: Result := 'Picked up a clip.';
    pkClipBox: Result := 'Picked up a box of bullets.';
    pkShells: Result := 'Picked up 4 shotgun shells.';
    pkShellBox: Result := 'Picked up a box of shotgun shells.';
    pkRocket: Result := 'Picked up a rocket.';
    pkRocketBox: Result := 'Picked up a box of rockets.';
    pkCell: Result := 'Picked up an energy cell.';
    pkCellPack: Result := 'Picked up an energy cell pack.';
    pkBackpack: Result := 'Picked up a backpack full of ammo!';
    pkShotgun: Result := 'You got the shotgun!';
    pkSuperShotgun: Result := 'You got the super shotgun!';
    pkChaingun: Result := 'You got the chaingun!';
    pkRocketLauncher: Result := 'You got the rocket launcher!';
    pkPlasma: Result := 'You got the plasma gun!';
    pkBFG: Result := 'You got the BFG9000!  Oh, yes.';
    pkChainsaw: Result := 'A chainsaw!  Find some meat!';
    else Result := '';
  end;
end;

initialization
  BuildTable;
finalization
  FreeAndNil(Index);
end.
