{ Doom's status bar (STBAR + STTNUM digits, face, keys, arms) composed
  into one 320x32 image and shown with a pixel-perfect TCastleImageControl. }
unit DoomHud;

interface

uses SysUtils, Classes,
  CastleImages, CastleVectors, CastleControls, CastleUIControls,
  DoomGraphics, DoomWorld;

type
  TDoomStatusBar = class(TCastleImageControl)
  strict private
    FGraphics: TDoomGraphics;
    FSignature: String;
    FFaceTimer: Single;
    FFaceVariant: Integer;
    procedure Blit(const Dest: TRGBAlphaImage; const Img: TDoomImage; const X, Y: Integer);
    procedure DrawNumber(const Dest: TRGBAlphaImage; const Value, RightX, Y: Integer;
      const Prefix: String; const Digits: Integer; const Percent: Boolean);
    function FaceName(const Player: TPlayerState): String;
  public
    constructor Create(AOwner: TComponent; const AGraphics: TDoomGraphics); reintroduce;
    { Rebuild the bar if the shown values changed. }
    procedure Refresh(const World: TDoomWorld; const SecondsPassed: Single);
  end;

{ Copy a decoded Doom graphic onto a CGE image at Doom coordinates
  (X, Y from the top-left), honouring transparency. }
procedure BlitDoomImage(const Dest: TRGBAlphaImage; const Img: TDoomImage; const X, Y: Integer);

implementation

uses Math, CastleUtils, CastleColors,
  DoomThings;

procedure BlitDoomImage(const Dest: TRGBAlphaImage; const Img: TDoomImage; const X, Y: Integer);
var
  SX, SY, DX, DY: Integer;
  Src, Dst: PVector4Byte;
begin
  if Img = nil then Exit;
  for SY := 0 to Img.Height - 1 do
  begin
    DY := Y + SY;
    if (DY < 0) or (DY >= Integer(Dest.Height)) then Continue;
    for SX := 0 to Img.Width - 1 do
    begin
      DX := X + SX;
      if (DX < 0) or (DX >= Integer(Dest.Width)) then Continue;
      Src := PVector4Byte(Img.Image.PixelPtr(SX, Img.Height - 1 - SY));
      if Src^.W = 0 then Continue;
      Dst := PVector4Byte(Dest.PixelPtr(DX, Dest.Height - 1 - DY));
      Dst^ := Src^;
    end;
  end;
end;

{ TDoomStatusBar ------------------------------------------------------------- }

constructor TDoomStatusBar.Create(AOwner: TComponent; const AGraphics: TDoomGraphics);
begin
  inherited Create(AOwner);
  FGraphics := AGraphics;
  SmoothScaling := false;
  Stretch := true;
  Anchor(hpMiddle);
  Anchor(vpBottom);
end;

procedure TDoomStatusBar.Blit(const Dest: TRGBAlphaImage; const Img: TDoomImage; const X, Y: Integer);
begin
  BlitDoomImage(Dest, Img, X, Y);
end;

procedure TDoomStatusBar.DrawNumber(const Dest: TRGBAlphaImage; const Value, RightX, Y: Integer;
  const Prefix: String; const Digits: Integer; const Percent: Boolean);
var
  S: String;
  I, X, W: Integer;
  D: TDoomImage;
begin
  D := FGraphics.Patch(Prefix + '0');
  if D = nil then Exit;
  W := D.Width;
  S := IntToStr(Max(0, Value));
  if Length(S) > Digits then S := Copy(S, Length(S) - Digits + 1, Digits);
  X := RightX;
  for I := Length(S) downto 1 do
  begin
    X := X - W;
    Blit(Dest, FGraphics.Patch(Prefix + S[I]), X, Y);
  end;
  if Percent then
    Blit(Dest, FGraphics.Patch('STTPRCNT'), RightX, Y);
end;

function TDoomStatusBar.FaceName(const Player: TPlayerState): String;
var
  Level: Integer;
begin
  if Player.Dead then Exit('STFDEAD0');
  if Player.InvulnerableTics > 0 then Exit('STFGOD0');
  Level := Clamped((100 - Player.Health) div 20, 0, 4);
  case Player.FaceState of
    1: Result := Format('STFKILL%d', [Level]);
    2: Result := Format('STFOUCH%d', [Level]);
    3: Result := Format('STFEVL%d', [Level]);
    else Result := Format('STFST%d%d', [Level, FFaceVariant]);
  end;
end;

procedure TDoomStatusBar.Refresh(const World: TDoomWorld; const SecondsPassed: Single);
var
  P: TPlayerState;
  Sig: String;
  Img: TRGBAlphaImage;
  I, Row, Col: Integer;
  W: TWeapon;
  Owned: Boolean;
  KeysBits: Integer;
  K: TDoomKey;
const
  ArmsWeapons: array [0..5] of TWeapon = (wpPistol, wpShotgun, wpChaingun, wpMissile, wpPlasma, wpBfg);
  AmmoY: array [TAmmoType] of Integer = (173, 179, 185, 191, 0);
begin
  P := World.Player;
  FFaceTimer := FFaceTimer - SecondsPassed;
  if FFaceTimer <= 0 then
  begin
    FFaceTimer := 0.5 + Random * 1.5;
    FFaceVariant := Random(3);
  end;
  KeysBits := 0;
  for K := Low(TDoomKey) to High(TDoomKey) do
    if K in P.Keys then KeysBits := KeysBits or (1 shl Ord(K));
  Sig := Format('%d|%d|%d|%d|%d|%d|%d|%d|%s|%d', [
    P.Health, P.Armor, Ord(P.Weapon), P.Ammo[amClip], P.Ammo[amShell], P.Ammo[amCell], P.Ammo[amMisl],
    KeysBits, FaceName(P), Integer(P.MaxAmmo[amClip])]);
  for W := Low(TWeapon) to High(TWeapon) do
    if W in P.Weapons then Sig := Sig + 'w' + IntToStr(Ord(W));
  if Sig = FSignature then Exit;
  FSignature := Sig;

  Img := TRGBAlphaImage.Create(320, 32);
  Img.Clear(Vector4Byte(0, 0, 0, 255));
  Blit(Img, FGraphics.Patch('STBAR'), 0, 0);
  Blit(Img, FGraphics.Patch('STARMS'), 104, 0);

  { Current ammo (none for fist/chainsaw). }
  if World.AmmoFor(P.Weapon) <> amNoAmmo then
    DrawNumber(Img, P.Ammo[World.AmmoFor(P.Weapon)], 44, 3, 'STTNUM', 3, false);
  DrawNumber(Img, P.Health, 90, 3, 'STTNUM', 3, true);
  DrawNumber(Img, P.Armor, 221, 3, 'STTNUM', 3, true);

  { Arms: weapons 2..7 }
  for I := 0 to 5 do
  begin
    Owned := ArmsWeapons[I] in P.Weapons;
    if (I = 1) and (wpSuperShotgun in P.Weapons) then Owned := true;
    Col := I mod 3;
    Row := I div 3;
    if Owned then
      Blit(Img, FGraphics.Patch('STYSNUM' + IntToStr(I + 2)), 111 + Col * 12, 4 + Row * 10)
    else
      Blit(Img, FGraphics.Patch('STGNUM' + IntToStr(I + 2)), 111 + Col * 12, 4 + Row * 10);
  end;

  { Face }
  Blit(Img, FGraphics.Patch(FaceName(P)), 143, 0);

  { Keys }
  if skullBlue in P.Keys then Blit(Img, FGraphics.Patch('STKEYS3'), 239, 3)
  else if keyBlue in P.Keys then Blit(Img, FGraphics.Patch('STKEYS0'), 239, 3);
  if skullYellow in P.Keys then Blit(Img, FGraphics.Patch('STKEYS4'), 239, 13)
  else if keyYellow in P.Keys then Blit(Img, FGraphics.Patch('STKEYS1'), 239, 13);
  if skullRed in P.Keys then Blit(Img, FGraphics.Patch('STKEYS5'), 239, 23)
  else if keyRed in P.Keys then Blit(Img, FGraphics.Patch('STKEYS2'), 239, 23);

  { Ammo table: current / max, small yellow digits. }
  DrawNumber(Img, P.Ammo[amClip], 288, AmmoY[amClip] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.Ammo[amShell], 288, AmmoY[amShell] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.Ammo[amMisl], 288, AmmoY[amMisl] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.Ammo[amCell], 288, AmmoY[amCell] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.MaxAmmo[amClip], 314, AmmoY[amClip] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.MaxAmmo[amShell], 314, AmmoY[amShell] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.MaxAmmo[amMisl], 314, AmmoY[amMisl] - 168, 'STYSNUM', 3, false);
  DrawNumber(Img, P.MaxAmmo[amCell], 314, AmmoY[amCell] - 168, 'STYSNUM', 3, false);

  Image := Img; { the control owns and frees it }
end;

end.
