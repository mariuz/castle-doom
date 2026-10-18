{ Closed captions: a short line for each sound the player would hear
  ("Imp sees you, left"), for players who cannot hear the game.

  Doors, lifts, switches, explosions and the like have a caption per
  sound lump (CaptionForLump); a monster's sight, attack, pain and death
  sounds are captioned with its name (the cast call's CC_* strings, so
  Freedoom's names) and the slot the sound plays from, which keeps
  DeHackEd-changed sounds right. CaptionDirection says where the sound
  came from relative to the player's facing. TCaptionList keeps the last
  few lines for a few seconds of game time. GameViewPlay feeds it from
  TDoomSounds.OnPlay and draws it under the messages. }
unit DoomCaptions;

interface

uses SysUtils, Generics.Collections;

const
  { Lines shown at once and how long one stays (tics, 35 a second). }
  MaxCaptions = 3;
  CaptionTics = 3 * 35;
  { Sounds further away are not heard (s_sound.c's S_CLIPPING_DIST). }
  CaptionMaxDistance = 1200;
  { Closer than this, no direction is given. }
  CaptionNearDistance = 64;

type
  TCaptionSlot = (csSee, csAttack, csPain, csDeath, csOther);

{ The caption for a sound lump of a door, lift, explosion...; Global means
  a sound played without a position (only the Icon of Sin's count then).
  '' when the lump has none. }
function CaptionForLump(const LumpName: String; const Global: Boolean): String;

{ Which of a monster's sounds Lump is ('' slots never match). }
function CaptionSlot(const Lump, See, Attack, Pain, Death: String): TCaptionSlot;

{ "Imp sees you", "Imp dies"...; '' for csOther. }
function MonsterCaption(const Name: String; const Slot: TCaptionSlot): String;

{ The cast call's string for a thing type (CC_IMP...) and its vanilla
  text; False when the thing is no monster of the cast. }
function MonsterNameKey(const Num: Integer; out Key, DefaultName: String): Boolean;

{ "ahead", "left", "right" or "behind" from the player at (PX, PY)
  facing PAngle (degrees, counter-clockwise from east) to (SX, SY); ''
  when the source is nearby. }
function CaptionDirection(const PX, PY, PAngle, SX, SY: Single): String;

type
  TCaptionList = class
  strict private
    type
      TCaption = record
        Text, Direction: String;
        Tic: Int64;
      end;
    var
      FItems: {$ifdef FPC}specialize{$endif} TList<TCaption>;
  public
    constructor Create;
    destructor Destroy; override;
    { A new line at game tic Tic; the same caption already shown moves to
      the bottom with the new direction. }
    procedure Add(const Text, Direction: String; const Tic: Int64);
    { The lines still shown at Tic (oldest first, #10 between them). }
    function Text(const Tic: Int64): String;
    procedure Clear;
  end;

implementation

uses Math;

type
  TLumpCaption = record
    Lump, Text: String;
    Global: Boolean;
  end;

const
  LumpCaptions: array [0..23] of TLumpCaption = (
    (Lump: 'DSDOROPN'; Text: 'Door opens'; Global: false),
    (Lump: 'DSDORCLS'; Text: 'Door closes'; Global: false),
    (Lump: 'DSBDOPN'; Text: 'Door opens'; Global: false),
    (Lump: 'DSBDCLS'; Text: 'Door closes'; Global: false),
    (Lump: 'DSPSTART'; Text: 'Lift moves'; Global: false),
    (Lump: 'DSPSTOP'; Text: 'Lift stops'; Global: false),
    (Lump: 'DSSTNMOV'; Text: 'Stone grinds'; Global: false),
    (Lump: 'DSSWTCHN'; Text: 'Switch clicks'; Global: false),
    (Lump: 'DSSWTCHX'; Text: 'Switch clicks'; Global: false),
    (Lump: 'DSTELEPT'; Text: 'Teleport'; Global: false),
    (Lump: 'DSBAREXP'; Text: 'Explosion'; Global: false),
    (Lump: 'DSRXPLOD'; Text: 'Explosion'; Global: false),
    (Lump: 'DSFIRXPL'; Text: 'Fireball explodes'; Global: false),
    (Lump: 'DSFIRSHT'; Text: 'Fireball flies'; Global: false),
    (Lump: 'DSRLAUNC'; Text: 'Rocket flies'; Global: false),
    (Lump: 'DSSLOP'; Text: 'Squelch'; Global: false),
    (Lump: 'DSFLAMST'; Text: 'Flames rise'; Global: false),
    (Lump: 'DSBOSCUB'; Text: 'Spawn cube flies'; Global: false),
    (Lump: 'DSITMBK'; Text: 'Item respawns'; Global: false),
    (Lump: 'DSMETAL'; Text: 'Heavy footsteps'; Global: false),
    (Lump: 'DSBOSSIT'; Text: 'Icon of Sin roars'; Global: true),
    (Lump: 'DSBOSPIT'; Text: 'Icon of Sin spits a cube'; Global: true),
    (Lump: 'DSBOSPN'; Text: 'Icon of Sin screams'; Global: true),
    (Lump: 'DSBOSDTH'; Text: 'Icon of Sin dies'; Global: true)
  );

type
  TMonsterName = record
    Num: Integer;
    Key, DefaultName: String;
  end;

const
  MonsterNames: array [0..19] of TMonsterName = (
    (Num: 3004; Key: 'CC_ZOMBIE'; DefaultName: 'Zombieman'),
    (Num: 9; Key: 'CC_SHOTGUN'; DefaultName: 'Shotgun guy'),
    (Num: 65; Key: 'CC_HEAVY'; DefaultName: 'Heavy weapon dude'),
    (Num: 3001; Key: 'CC_IMP'; DefaultName: 'Imp'),
    (Num: 3002; Key: 'CC_DEMON'; DefaultName: 'Demon'),
    (Num: 58; Key: ''; DefaultName: 'Spectre'),
    (Num: 3006; Key: 'CC_LOST'; DefaultName: 'Lost soul'),
    (Num: 3005; Key: 'CC_CACO'; DefaultName: 'Cacodemon'),
    (Num: 69; Key: 'CC_HELL'; DefaultName: 'Hell knight'),
    (Num: 3003; Key: 'CC_BARON'; DefaultName: 'Baron of Hell'),
    (Num: 68; Key: 'CC_ARACH'; DefaultName: 'Arachnotron'),
    (Num: 71; Key: 'CC_PAIN'; DefaultName: 'Pain elemental'),
    (Num: 66; Key: 'CC_REVEN'; DefaultName: 'Revenant'),
    (Num: 67; Key: 'CC_MANCU'; DefaultName: 'Mancubus'),
    (Num: 64; Key: 'CC_ARCH'; DefaultName: 'Arch-vile'),
    (Num: 7; Key: 'CC_SPIDER'; DefaultName: 'Spider mastermind'),
    (Num: 16; Key: 'CC_CYBER'; DefaultName: 'Cyberdemon'),
    (Num: 84; Key: ''; DefaultName: 'SS'),
    (Num: 72; Key: ''; DefaultName: 'Commander Keen'),
    (Num: 2035; Key: ''; DefaultName: 'Barrel')
  );

function CaptionForLump(const LumpName: String; const Global: Boolean): String;
var
  I: Integer;
  U: String;
begin
  Result := '';
  U := UpperCase(LumpName);
  for I := Low(LumpCaptions) to High(LumpCaptions) do
    if LumpCaptions[I].Lump = U then
    begin
      if LumpCaptions[I].Global or not Global then
        Result := LumpCaptions[I].Text;
      Exit;
    end;
end;

function CaptionSlot(const Lump, See, Attack, Pain, Death: String): TCaptionSlot;
begin
  if Lump = '' then Exit(csOther);
  if SameText(Lump, See) then Exit(csSee);
  if SameText(Lump, Attack) then Exit(csAttack);
  if SameText(Lump, Pain) then Exit(csPain);
  if SameText(Lump, Death) then Exit(csDeath);
  Result := csOther;
end;

function MonsterCaption(const Name: String; const Slot: TCaptionSlot): String;
const
  Verbs: array [TCaptionSlot] of String = ('sees you', 'attacks', 'is hurt', 'dies', '');
begin
  if (Slot = csOther) or (Name = '') then Exit('');
  { Freedoom's cast names are lower case, vanilla's upper case. }
  Result := UpperCase(Copy(Name, 1, 1)) + LowerCase(Copy(Name, 2, MaxInt)) + ' ' + Verbs[Slot];
end;

function MonsterNameKey(const Num: Integer; out Key, DefaultName: String): Boolean;
var
  I: Integer;
begin
  for I := Low(MonsterNames) to High(MonsterNames) do
    if MonsterNames[I].Num = Num then
    begin
      Key := MonsterNames[I].Key;
      DefaultName := MonsterNames[I].DefaultName;
      Exit(true);
    end;
  Key := '';
  DefaultName := '';
  Result := false;
end;

function CaptionDirection(const PX, PY, PAngle, SX, SY: Single): String;
var
  DX, DY, Rel: Single;
begin
  DX := SX - PX;
  DY := SY - PY;
  if Sqr(DX) + Sqr(DY) < Sqr(CaptionNearDistance) then Exit('');
  Rel := RadToDeg(ArcTan2(DY, DX)) - PAngle;
  Rel := Rel - 360 * Floor((Rel + 180) / 360);
  { Rel is now in [-180, 180). }
  if Abs(Rel) <= 45 then
    Result := 'ahead'
  else if (Rel > 45) and (Rel <= 135) then
    Result := 'left'
  else if (Rel < -45) and (Rel >= -135) then
    Result := 'right'
  else
    Result := 'behind';
end;

{ TCaptionList --------------------------------------------------------------- }

constructor TCaptionList.Create;
begin
  inherited;
  FItems := {$ifdef FPC}specialize{$endif} TList<TCaption>.Create;
end;

destructor TCaptionList.Destroy;
begin
  FreeAndNil(FItems);
  inherited;
end;

procedure TCaptionList.Add(const Text, Direction: String; const Tic: Int64);
var
  I: Integer;
  C: TCaption;
begin
  if Text = '' then Exit;
  for I := FItems.Count - 1 downto 0 do
    if FItems[I].Text = Text then
      FItems.Delete(I);
  C.Text := Text;
  C.Direction := Direction;
  C.Tic := Tic;
  FItems.Add(C);
  while FItems.Count > MaxCaptions do
    FItems.Delete(0);
end;

function TCaptionList.Text(const Tic: Int64): String;
var
  I: Integer;
  Line: String;
begin
  Result := '';
  for I := FItems.Count - 1 downto 0 do
    if (Tic - FItems[I].Tic >= CaptionTics) or (Tic < FItems[I].Tic) then
      FItems.Delete(I);
  for I := 0 to FItems.Count - 1 do
  begin
    Line := FItems[I].Text;
    if FItems[I].Direction <> '' then
      Line := Line + ', ' + FItems[I].Direction;
    if Result <> '' then Result := Result + #10;
    Result := Result + Line;
  end;
end;

procedure TCaptionList.Clear;
begin
  FItems.Clear;
end;

end.
