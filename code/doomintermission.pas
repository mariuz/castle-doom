{ Doom's intermission screen (wi_stuff.c, single player): the episode map
  or INTERPIC background, the level name graphic, "FINISHED", kills / items /
  secrets percentages and time counting up with sounds, par time, then the
  "ENTERING <next level>" screen. Composed into a 320x200 image each tic and
  shown pixel-perfect by a TCastleImageControl. }
unit DoomIntermission;

interface

uses Classes,
  CastleControls, CastleImages,
  DoomGraphics, DoomSound;

type
  TIntermissionStage = (isNone, isKills, isItems, isSecrets, isTime, isStatsDone, isEntering, isDone);

  TDoomIntermission = class(TCastleImageControl)
  strict private
    FGraphics: TDoomGraphics;
    FSounds: TDoomSounds;
    FIsDoom2: Boolean;
    FMapName, FNextMap: String;
    FKillsPct, FItemsPct, FSecretsPct, FTimeSec, FParSec: Integer;
    FCntKills, FCntItems, FCntSecrets, FCntTime: Integer;
    FStage: TIntermissionStage;
    FPause: Integer;
    FTic: Integer;
    procedure Compose;
    procedure DrawNumber(const Img: TRGBAlphaImage; const RightX, Y, Value: Integer);
    procedure DrawPercent(const Img: TRGBAlphaImage; const RightX, Y, Value: Integer);
    procedure DrawTime(const Img: TRGBAlphaImage; const RightX, Y, Seconds: Integer);
    procedure DrawCentered(const Img: TRGBAlphaImage; const Patch: TDoomImage; const Y: Integer);
    function LevelNamePatch(const MapName: String): TDoomImage;
    procedure SetStage(const S: TIntermissionStage);
  public
    constructor Create(AOwner: TComponent); override;
    { Begin the intermission for a finished map. }
    procedure Start(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds;
      const AIsDoom2: Boolean; const AMapName, ANextMap: String;
      const Kills, TotalKills, Items, TotalItems, Secrets, TotalSecrets, TimeSec: Integer);
    { Advance one Doom tic (35 Hz). }
    procedure Tic;
    { The player pressed use/fire: skip the count-up, or go to the next stage. }
    procedure Accelerate;
    property Stage: TIntermissionStage read FStage;
    function Done: Boolean;
  end;

{ Doom's par time in seconds for a map, 0 when unknown. }
function ParTime(const MapName: String; const IsDoom2: Boolean): Integer;

implementation

uses SysUtils, Math,
  CastleVectors, CastleUIControls,
  DoomHud, DoomDehacked;

const
  Doom1Pars: array [1..3, 1..9] of Integer = (
    (30, 75, 120, 90, 165, 180, 180, 30, 165),
    (90, 90, 90, 120, 90, 360, 240, 30, 170),
    (90, 45, 90, 150, 90, 90, 165, 30, 135));
  Doom2Pars: array [1..32] of Integer = (
    30, 90, 120, 120, 90, 150, 120, 120, 270, 90, 210, 150, 150, 150, 210, 150,
    420, 150, 210, 150, 240, 150, 180, 150, 150, 300, 330, 420, 300, 180, 120, 30);

function ParTime(const MapName: String; const IsDoom2: Boolean): Integer;
var
  E, M: Integer;
begin
  { A DeHackEd [PARS] section (Freedoom has its own times) wins. }
  if DehackedParTime(MapName, Result) then Exit;
  Result := 0;
  if IsDoom2 then
  begin
    M := StrToIntDef(Copy(MapName, 4, 2), 0);
    if (M >= 1) and (M <= 32) then Result := Doom2Pars[M];
  end else
  begin
    E := StrToIntDef(Copy(MapName, 2, 1), 0);
    M := StrToIntDef(Copy(MapName, 4, 1), 0);
    if (E >= 1) and (E <= 3) and (M >= 1) and (M <= 9) then Result := Doom1Pars[E, M];
  end;
end;

{ TDoomIntermission ---------------------------------------------------------- }

constructor TDoomIntermission.Create(AOwner: TComponent);
begin
  inherited;
  SmoothScaling := false;
  Stretch := true;
end;

function TDoomIntermission.Done: Boolean;
begin
  Result := FStage = isDone;
end;

procedure TDoomIntermission.Start(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds;
  const AIsDoom2: Boolean; const AMapName, ANextMap: String;
  const Kills, TotalKills, Items, TotalItems, Secrets, TotalSecrets, TimeSec: Integer);

  function Pct(const A, B: Integer): Integer;
  begin
    if B <= 0 then Result := 100 else Result := (A * 100) div B;
  end;

begin
  FGraphics := AGraphics;
  FSounds := ASounds;
  FIsDoom2 := AIsDoom2;
  FMapName := AMapName;
  FNextMap := ANextMap;
  FKillsPct := Pct(Kills, TotalKills);
  FItemsPct := Pct(Items, TotalItems);
  FSecretsPct := Pct(Secrets, TotalSecrets);
  FTimeSec := TimeSec;
  FParSec := ParTime(AMapName, AIsDoom2);
  FCntKills := 0;
  FCntItems := 0;
  FCntSecrets := 0;
  FCntTime := 0;
  FTic := 0;
  FPause := 35;
  FStage := isNone;
  Exists := true;
  Compose;
end;

procedure TDoomIntermission.SetStage(const S: TIntermissionStage);
begin
  FStage := S;
  FPause := 35;
end;

procedure TDoomIntermission.Tic;

  { Count towards Target by Step; true when reached (plays the sounds). }
  function Count(var Value: Integer; const Target, Step: Integer): Boolean;
  begin
    Result := false;
    if Value >= Target then Exit(true);
    Value := Value + Step;
    if (FTic and 3) = 0 then FSounds.Play('DSPISTOL');
    if Value >= Target then
    begin
      Value := Target;
      FSounds.Play('DSBAREXP');
      Result := true;
    end;
  end;

begin
  Inc(FTic);
  case FStage of
    isNone:
      begin
        Dec(FPause);
        if FPause <= 0 then SetStage(isKills);
      end;
    isKills: if Count(FCntKills, FKillsPct, 2) then SetStage(isItems);
    isItems: if Count(FCntItems, FItemsPct, 2) then SetStage(isSecrets);
    isSecrets: if Count(FCntSecrets, FSecretsPct, 2) then SetStage(isTime);
    isTime: if Count(FCntTime, FTimeSec, 3) then SetStage(isStatsDone);
    isStatsDone, isEntering, isDone: ;
  end;
  Compose;
end;

procedure TDoomIntermission.Accelerate;
begin
  case FStage of
    isNone, isKills, isItems, isSecrets, isTime:
      begin
        { Skip the count-up. }
        FCntKills := FKillsPct;
        FCntItems := FItemsPct;
        FCntSecrets := FSecretsPct;
        FCntTime := FTimeSec;
        FSounds.Play('DSBAREXP');
        SetStage(isStatsDone);
      end;
    isStatsDone:
      begin
        FSounds.Play('DSSGCOCK');
        SetStage(isEntering);
      end;
    isEntering:
      begin
        FSounds.Play('DSSGCOCK');
        SetStage(isDone);
      end;
    isDone: ;
  end;
  Compose;
end;

function TDoomIntermission.LevelNamePatch(const MapName: String): TDoomImage;
var
  E, M: Integer;
begin
  if FIsDoom2 then
    Result := FGraphics.Patch(Format('CWILV%2.2d', [StrToIntDef(Copy(MapName, 4, 2), 1) - 1]))
  else
  begin
    E := StrToIntDef(Copy(MapName, 2, 1), 1);
    M := StrToIntDef(Copy(MapName, 4, 1), 1);
    Result := FGraphics.Patch(Format('WILV%d%d', [E - 1, M - 1]));
  end;
end;

procedure TDoomIntermission.DrawCentered(const Img: TRGBAlphaImage; const Patch: TDoomImage; const Y: Integer);
begin
  if Patch <> nil then
    BlitDoomImage(Img, Patch, (320 - Patch.Width) div 2, Y);
end;

procedure TDoomIntermission.DrawNumber(const Img: TRGBAlphaImage; const RightX, Y, Value: Integer);
var
  S: String;
  I, X: Integer;
  D: TDoomImage;
begin
  S := IntToStr(Abs(Value));
  X := RightX;
  for I := Length(S) downto 1 do
  begin
    D := FGraphics.Patch('WINUM' + S[I]);
    if D = nil then Continue;
    X := X - D.Width;
    BlitDoomImage(Img, D, X, Y);
  end;
  if Value < 0 then
  begin
    D := FGraphics.Patch('WIMINUS');
    if D <> nil then BlitDoomImage(Img, D, X - D.Width, Y);
  end;
end;

procedure TDoomIntermission.DrawPercent(const Img: TRGBAlphaImage; const RightX, Y, Value: Integer);
var
  P: TDoomImage;
begin
  P := FGraphics.Patch('WIPCNT');
  if P <> nil then BlitDoomImage(Img, P, RightX, Y);
  DrawNumber(Img, RightX, Y, Value);
end;

procedure TDoomIntermission.DrawTime(const Img: TRGBAlphaImage; const RightX, Y, Seconds: Integer);
var
  S: String;
  I, X: Integer;
  D: TDoomImage;
begin
  if Seconds div 60 > 99 then
  begin
    DrawCentered(Img, FGraphics.Patch('WISUCKS'), Y);
    Exit;
  end;
  { Draw "M:SS" right to left, each glyph with its own width (Freedoom's
    WINUM digits are not all the same width). }
  S := Format('%d:%2.2d', [Seconds div 60, Seconds mod 60]);
  X := RightX;
  for I := Length(S) downto 1 do
  begin
    if S[I] = ':' then D := FGraphics.Patch('WICOLON') else D := FGraphics.Patch('WINUM' + S[I]);
    if D = nil then Continue;
    X := X - D.Width;
    BlitDoomImage(Img, D, X, Y);
  end;
end;

procedure TDoomIntermission.Compose;
const
  StatsX = 50;
  StatsY = 50;
  TimeX = 16;
  TimeY = 168;
var
  Img: TRGBAlphaImage;
  Back, LevelName, P: TDoomImage;
  E, LineH: Integer;
begin
  if FGraphics = nil then Exit;
  Img := TRGBAlphaImage.Create(320, 200);
  Img.Clear(Vector4Byte(0, 0, 0, 255));

  { Background: the episode map (Doom 1) or INTERPIC. }
  Back := nil;
  if not FIsDoom2 then
  begin
    E := StrToIntDef(Copy(FMapName, 2, 1), 1);
    Back := FGraphics.Patch(Format('WIMAP%d', [E - 1]));
  end;
  if Back = nil then Back := FGraphics.Patch('INTERPIC');
  if Back <> nil then BlitDoomImage(Img, Back, 0, 0);

  P := FGraphics.Patch('WINUM0');
  if P <> nil then LineH := (3 * P.Height) div 2 else LineH := 22;

  if FStage in [isEntering, isDone] then
  begin
    { "ENTERING" + next level name. }
    P := FGraphics.Patch('WIENTER');
    DrawCentered(Img, P, 2);
    LevelName := LevelNamePatch(FNextMap);
    if (P <> nil) then DrawCentered(Img, LevelName, 2 + (5 * P.Height) div 4)
    else DrawCentered(Img, LevelName, 20);
  end else
  begin
    { Level name + "FINISHED", then the stats. }
    LevelName := LevelNamePatch(FMapName);
    DrawCentered(Img, LevelName, 2);
    P := FGraphics.Patch('WIF');
    if LevelName <> nil then DrawCentered(Img, P, 2 + (5 * LevelName.Height) div 4)
    else DrawCentered(Img, P, 20);

    BlitDoomImage(Img, FGraphics.Patch('WIOSTK'), StatsX, StatsY);
    if FStage >= isKills then DrawPercent(Img, 320 - StatsX, StatsY, FCntKills);
    BlitDoomImage(Img, FGraphics.Patch('WIOSTI'), StatsX, StatsY + LineH * 2);
    if FStage >= isItems then DrawPercent(Img, 320 - StatsX, StatsY + LineH * 2, FCntItems);
    BlitDoomImage(Img, FGraphics.Patch('WIOSTS'), StatsX, StatsY + LineH * 4);
    if FStage >= isSecrets then DrawPercent(Img, 320 - StatsX, StatsY + LineH * 4, FCntSecrets);
    BlitDoomImage(Img, FGraphics.Patch('WITIME'), TimeX, TimeY);
    if FStage >= isTime then DrawTime(Img, 160 - TimeX, TimeY, FCntTime);
    if FParSec > 0 then
    begin
      BlitDoomImage(Img, FGraphics.Patch('WIPAR'), 160 + TimeX, TimeY);
      if FStage >= isTime then DrawTime(Img, 320 - TimeX, TimeY, FParSec);
    end;
  end;
  Image := Img;
end;

end.
