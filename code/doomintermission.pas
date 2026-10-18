{ Doom's intermission screen (wi_stuff.c, single player): the episode map
  or INTERPIC background, the level name graphic, "FINISHED", kills / items /
  secrets percentages and time counting up with sounds, par time, then the
  "ENTERING <next level>" screen. Composed into a 320x200 image each tic and
  shown pixel-perfect by a TCastleImageControl. }
unit DoomIntermission;

interface

uses Classes,
  CastleControls, CastleImages,
  DoomGraphics, DoomSound, DoomWiScript;

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
    { Intermission scripts (DoomWiScript) behind the statistics and the
      "Entering" screen; nil for a plain picture. }
    FExitScript, FEnterScript: TWiScript;
    procedure LoadScripts;
    function LoadScript(const LumpName: String): TWiScript;
    { The script's background, animations and, on the "Entering" screen,
      the visited levels' splats and the blinking pointer. }
    procedure DrawScript(const Img: TRGBAlphaImage; const Script: TWiScript; const Entering: Boolean);
    procedure Compose;
    procedure DrawNumber(const Img: TRGBAlphaImage; const RightX, Y, Value: Integer);
    procedure DrawPercent(const Img: TRGBAlphaImage; const RightX, Y, Value: Integer);
    procedure DrawTime(const Img: TRGBAlphaImage; const RightX, Y, Seconds: Integer);
    procedure DrawCentered(const Img: TRGBAlphaImage; const Patch: TDoomImage; const Y: Integer);
    function LevelNamePatch(const MapName: String): TDoomImage;
    function DrawLevelName(const Img: TRGBAlphaImage; const MapName: String; const Y: Integer): Integer;
    procedure SetStage(const S: TIntermissionStage);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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

uses SysUtils, Math, CastleLog, DoomMapInfo,
  CastleVectors, CastleUIControls,
  DoomHud, DoomFont, DoomDehacked, CastleComponentSerialize;

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
  Info: TMapInfoEntry;
begin
  { UMAPINFO's partime, then a DeHackEd [PARS] section (Freedoom has its
    own times). }
  Info := MapInfoFor(MapName);
  if (Info <> nil) and Info.ParTimeSet then Exit(Info.ParTime);
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

destructor TDoomIntermission.Destroy;
begin
  FreeAndNil(FExitScript);
  FreeAndNil(FEnterScript);
  inherited;
end;

function TDoomIntermission.LoadScript(const LumpName: String): TWiScript;
var
  Lump: Integer;
  Bytes: TBytes;
  Text: String;
begin
  Result := nil;
  if (FGraphics = nil) or (FGraphics.Wad = nil) then Exit;
  Lump := FGraphics.Wad.FindLump(LumpName);
  if Lump < 0 then Exit;
  Bytes := FGraphics.Wad.LumpBytes(Lump);
  SetLength(Text, Length(Bytes));
  if Length(Bytes) > 0 then
    Move(Bytes[0], Text[1], Length(Bytes));
  Result := ParseWiScript(Text);
end;

procedure TDoomIntermission.LoadScripts;
var
  Info: TMapInfoEntry;
  E: Integer;
  Vanilla: String;
begin
  FreeAndNil(FExitScript);
  FreeAndNil(FEnterScript);
  { Doom's episode maps (when no MAPINFO picture replaces them). }
  Vanilla := '';
  if not FIsDoom2 then
  begin
    E := StrToIntDef(Copy(FMapName, 2, 1), 0);
    if FGraphics.Patch(Format('WIMAP%d', [E - 1])) <> nil then
      Vanilla := VanillaWiScript(E);
  end;
  Info := MapInfoFor(FMapName);
  if (Info <> nil) and (Info.ExitScript <> '') then
    FExitScript := LoadScript(Info.ExitScript)
  else if ((Info = nil) or (Info.ExitPic = '')) and (Vanilla <> '') then
    FExitScript := ParseWiScript(Vanilla);
  Info := MapInfoFor(FNextMap);
  if (Info <> nil) and (Info.EnterScript <> '') then
    FEnterScript := LoadScript(Info.EnterScript)
  else if ((Info = nil) or (Info.EnterPic = '')) and (Vanilla <> '') then
    FEnterScript := ParseWiScript(Vanilla);
  if FExitScript <> nil then
    WritelnLog('Intermission', '%s: exit script with %d spots, %d animations', [FMapName,
      FExitScript.SpotNames.Count, FExitScript.Animations.Count]);
  if FEnterScript <> nil then
    WritelnLog('Intermission', '%s: enter script with %d spots, %d animations', [FNextMap,
      FEnterScript.SpotNames.Count, FEnterScript.Animations.Count]);
end;

procedure TDoomIntermission.DrawScript(const Img: TRGBAlphaImage; const Script: TWiScript;
  const Entering: Boolean);
var
  Finished, Next, I, Frame: Integer;
  A: TWiAnimation;
  P: TDoomImage;
  Shown: Boolean;

  { A patch at X, Y with its offsets (V_DrawPatch). }
  procedure DrawAt(const Patch: TDoomImage; const X, Y: Integer);
  begin
    if Patch <> nil then
      BlitDoomImage(Img, Patch, X - Patch.LeftOffset, Y - Patch.TopOffset);
  end;

  function Fits(const Patch: TDoomImage; const X, Y: Integer): Boolean;
  var
    L, T: Integer;
  begin
    L := X - Patch.LeftOffset;
    T := Y - Patch.TopOffset;
    Result := (L >= 0) and (L + Patch.Width < 320) and (T >= 0) and (T + Patch.Height < 200);
  end;

  { Visited: the levels up to the finished one in the spots' order
    (vanilla's "levels done" of a linear episode). }
  function Visited(const MapName: String): Boolean;
  var
    Index: Integer;
  begin
    Index := Script.SpotIndex(MapName);
    Result := (Index >= 0) and (Finished >= 0) and (Index <= Finished);
  end;

begin
  Finished := Script.SpotIndex(FMapName);
  Next := Script.SpotIndex(FNextMap);
  for A in Script.Animations do
  begin
    case A.Condition of
      wcEntering: Shown := SameText(FNextMap, A.ConditionMap);
      wcNotEntering: Shown := not SameText(FNextMap, A.ConditionMap);
      wcLeaving: Shown := SameText(FMapName, A.ConditionMap);
      wcNotLeaving: Shown := not SameText(FMapName, A.ConditionMap);
      wcVisited: Shown := Visited(A.ConditionMap);
      wcNotVisited: Shown := not Visited(A.ConditionMap);
      else Shown := true;
    end;
    if (not Shown) or (A.Frames.Count = 0) then Continue;
    Frame := FTic div Max(1, A.Period);
    if A.Condition = wcAlways then
      Frame := Frame mod A.Frames.Count
    else
      Frame := Min(Frame, A.Frames.Count - 1);
    DrawAt(FGraphics.Patch(A.Frames[Frame]), A.X, A.Y);
  end;
  if not Entering then Exit;
  P := FGraphics.Patch(Script.Splat);
  if P <> nil then
    for I := 0 to Script.SpotNames.Count - 1 do
      if Visited(Script.SpotNames[I]) then
        DrawAt(P, Script.SpotX[I], Script.SpotY[I]);
  { "You are here", blinking like vanilla's (FTic and 31) < 20. }
  if (Next >= 0) and ((FTic and 31) < 20) then
    for I := 0 to 1 do
    begin
      P := FGraphics.Patch(Script.Pointers[I]);
      if (P <> nil) and Fits(P, Script.SpotX[Next], Script.SpotY[Next]) then
      begin
        DrawAt(P, Script.SpotX[Next], Script.SpotY[Next]);
        Break;
      end;
    end;
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
  LoadScripts;
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
  Info: TMapInfoEntry;
begin
  { UMAPINFO: its levelpic; a renamed level without one shows no picture
    (the vanilla one would name another level; DrawLevelName writes the
    name as text instead). }
  Info := MapInfoFor(MapName);
  if Info <> nil then
  begin
    if Info.LevelPic <> '' then Exit(FGraphics.Patch(Info.LevelPic));
    if Info.LevelName <> '' then Exit(nil);
  end;
  if FIsDoom2 then
    Result := FGraphics.Patch(Format('CWILV%2.2d', [StrToIntDef(Copy(MapName, 4, 2), 1) - 1]))
  else
  begin
    E := StrToIntDef(Copy(MapName, 2, 1), 1);
    M := StrToIntDef(Copy(MapName, 4, 1), 1);
    Result := FGraphics.Patch(Format('WILV%d%d', [E - 1, M - 1]));
  end;
end;

function TDoomIntermission.DrawLevelName(const Img: TRGBAlphaImage; const MapName: String;
  const Y: Integer): Integer;
const
  TextHeight = 8;
var
  Patch: TDoomImage;
  Info: TMapInfoEntry;
  S: String;
begin
  { The picture, or (UMAPINFO without a levelpic) the levelname in the
    HU font, like Boom ports do. Result: the height drawn, 0 for nothing. }
  Patch := LevelNamePatch(MapName);
  if Patch <> nil then
  begin
    DrawCentered(Img, Patch, Y);
    Exit(Patch.Height);
  end;
  Info := MapInfoFor(MapName);
  if (Info = nil) or (Info.LevelName = '') then Exit(0);
  S := UpperCase(Info.LevelName);
  DrawDoomText(FGraphics, Img, (320 - DoomTextWidth(FGraphics, S)) div 2, Y, S);
  Result := TextHeight;
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
  Back, P: TDoomImage;
  E, LineH, NameH: Integer;
  Info: TMapInfoEntry;
  Script: TWiScript;
begin
  if FGraphics = nil then Exit;
  Img := TRGBAlphaImage.Create(320, 200);
  Img.Clear(Vector4Byte(0, 0, 0, 255));

  { Background: UMAPINFO's / MAPINFO's exit picture of the finished map
    (enter picture of the next one while "Entering"), else the episode
    map (Doom 1) or INTERPIC. }
  Back := nil;
  if FStage in [isEntering, isDone] then
    Info := MapInfoFor(FNextMap)
  else
    Info := MapInfoFor(FMapName);
  if Info <> nil then
  begin
    if FStage in [isEntering, isDone] then
    begin
      if Info.EnterPic <> '' then Back := FGraphics.Patch(Info.EnterPic);
    end else
    if Info.ExitPic <> '' then
      Back := FGraphics.Patch(Info.ExitPic);
  end;
  if FStage in [isEntering, isDone] then
    Script := FEnterScript
  else
    Script := FExitScript;
  if (Back = nil) and (Script <> nil) then
    Back := FGraphics.Patch(Script.Background);
  if (Back = nil) and not FIsDoom2 then
  begin
    E := StrToIntDef(Copy(FMapName, 2, 1), 1);
    Back := FGraphics.Patch(Format('WIMAP%d', [E - 1]));
  end;
  if Back = nil then Back := FGraphics.Patch('INTERPIC');
  if Back <> nil then BlitDoomImage(Img, Back, 0, 0);
  if Script <> nil then
    DrawScript(Img, Script, FStage in [isEntering, isDone]);

  P := FGraphics.Patch('WINUM0');
  if P <> nil then LineH := (3 * P.Height) div 2 else LineH := 22;

  if FStage in [isEntering, isDone] then
  begin
    { "ENTERING" + next level name. }
    P := FGraphics.Patch('WIENTER');
    DrawCentered(Img, P, 2);
    if P <> nil then DrawLevelName(Img, FNextMap, 2 + (5 * P.Height) div 4)
    else DrawLevelName(Img, FNextMap, 20);
  end else
  begin
    { Level name + "FINISHED", then the stats. }
    NameH := DrawLevelName(Img, FMapName, 2);
    P := FGraphics.Patch('WIF');
    if NameH > 0 then DrawCentered(Img, P, 2 + (5 * NameH) div 4)
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

initialization
  RegisterSerializableComponent(TDoomIntermission, 'Doom Intermission');
end.
