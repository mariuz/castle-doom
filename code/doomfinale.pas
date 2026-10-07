{ Doom's finale (f_finale.c): the story text typed over a flat after an
  episode (Doom 1) or after MAP06 / 11 / 20 / 30 and the secret exits
  (Doom 2), then the end picture (CREDIT, VICTORY2, ENDPIC), the bunny
  scroller with "THE END" after E3M8, or Doom 2's cast call after MAP30.
  Texts, flats and cast names come from the WAD's DEHACKED strings
  (TDoomStrings); a text that is missing is skipped. Like the intermission,
  the 320x200 screen is composed into one image each tic. }
unit DoomFinale;

interface

uses Classes,
  CastleControls, CastleImages,
  DoomGraphics, DoomSound, DoomMusic, DoomDehacked;

type
  TFinaleStage = (fsText, fsPicture, fsBunny, fsCast, fsDone);
  TCastPhase = (cpWalk, cpAttack, cpDeath);

  TDoomFinale = class(TCastleImageControl)
  strict private
    FGraphics: TDoomGraphics;
    FSounds: TDoomSounds;
    FMusic: TDoomMusic;
    FIsDoom2: Boolean;
    FStage: TFinaleStage;
    FTic: Integer;
    FText, FFlat, FPicture: String;
    FAfterText: TFinaleStage;
    FContinues: Boolean;
    FEndStage: Integer;
    { Cast call }
    FCastIndex: Integer;
    FCastPhase: TCastPhase;
    FCastFrame, FCastFrameTics, FCastWalked: Integer;
    FCastNames: array of String;
    procedure Compose;
    procedure SetStage(const S: TFinaleStage);
    procedure StartCastMember;
    procedure TicCast;
    function CastFrames: String;
    function TextComplete: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    { Begin the finale after MapName (Secret: left by the secret exit).
      Returns false when this map has no finale. }
    function Start(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds;
      const AMusic: TDoomMusic; const AStrings: TDoomStrings;
      const AIsDoom2: Boolean; const AMapName: String; const Secret: Boolean): Boolean;
    procedure Tic;
    { A key was pressed: finish the typing, go on, or kill the cast member. }
    procedure Accelerate;
    function Done: Boolean;
    property Stage: TFinaleStage read FStage;
    { True when the game goes on to the next map after this finale (Doom 2
      texts before MAP30); false when it ends (back to the title). }
    property Continues: Boolean read FContinues;
  end;

{ Does leaving this map show a finale? Doom 1: E?M8. Doom 2: MAP06, 11, 20,
  30, and MAP15 / MAP31 by their secret exits. }
function HasFinale(const MapName: String; const IsDoom2, Secret: Boolean): Boolean;

implementation

uses SysUtils, Math,
  CastleVectors, CastleUtils,
  DoomHud, DoomFont, DoomThings;

const
  TextSpeed = 3;   { tics per character }
  TextWait = 250;  { tics after the text before Doom 1 moves on }

type
  TCastMember = record
    Num: Integer;      { THINGS type, 0 = the player }
    NameKey: String;   { BEX string }
    DefaultName: String;
  end;

const
  Cast: array [0..16] of TCastMember = (
    (Num: 3004; NameKey: 'CC_ZOMBIE'; DefaultName: 'ZOMBIEMAN'),
    (Num: 9; NameKey: 'CC_SHOTGUN'; DefaultName: 'SHOTGUN GUY'),
    (Num: 65; NameKey: 'CC_HEAVY'; DefaultName: 'HEAVY WEAPON DUDE'),
    (Num: 3001; NameKey: 'CC_IMP'; DefaultName: 'IMP'),
    (Num: 3002; NameKey: 'CC_DEMON'; DefaultName: 'DEMON'),
    (Num: 3006; NameKey: 'CC_LOST'; DefaultName: 'LOST SOUL'),
    (Num: 3005; NameKey: 'CC_CACO'; DefaultName: 'CACODEMON'),
    (Num: 69; NameKey: 'CC_HELL'; DefaultName: 'HELL KNIGHT'),
    (Num: 3003; NameKey: 'CC_BARON'; DefaultName: 'BARON OF HELL'),
    (Num: 68; NameKey: 'CC_ARACH'; DefaultName: 'ARACHNOTRON'),
    (Num: 71; NameKey: 'CC_PAIN'; DefaultName: 'PAIN ELEMENTAL'),
    (Num: 66; NameKey: 'CC_REVEN'; DefaultName: 'REVENANT'),
    (Num: 67; NameKey: 'CC_MANCU'; DefaultName: 'MANCUBUS'),
    (Num: 64; NameKey: 'CC_ARCH'; DefaultName: 'ARCH-VILE'),
    (Num: 7; NameKey: 'CC_SPIDER'; DefaultName: 'THE SPIDER MASTERMIND'),
    (Num: 16; NameKey: 'CC_CYBER'; DefaultName: 'THE CYBERDEMON'),
    (Num: 0; NameKey: 'CC_HERO'; DefaultName: 'OUR HERO')
  );

function MapNumbers(const MapName: String; out E, M: Integer): Boolean;
begin
  E := 0;
  M := 0;
  if Copy(MapName, 1, 3) = 'MAP' then
    M := StrToIntDef(Copy(MapName, 4, 2), 0)
  else if (Length(MapName) = 4) and (MapName[1] = 'E') and (MapName[3] = 'M') then
  begin
    E := StrToIntDef(MapName[2], 0);
    M := StrToIntDef(MapName[4], 0);
  end;
  Result := M > 0;
end;

function HasFinale(const MapName: String; const IsDoom2, Secret: Boolean): Boolean;
var
  E, M: Integer;
begin
  Result := false;
  if not MapNumbers(MapName, E, M) then Exit;
  if IsDoom2 then
    Result := (M in [6, 11, 20, 30]) or ((M in [15, 31]) and Secret)
  else
    Result := (E > 0) and (M = 8);
end;

constructor TDoomFinale.Create(AOwner: TComponent);
begin
  inherited;
  SmoothScaling := false;
  Stretch := true;
  FStage := fsDone;
end;

function TDoomFinale.Start(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds;
  const AMusic: TDoomMusic; const AStrings: TDoomStrings;
  const AIsDoom2: Boolean; const AMapName: String; const Secret: Boolean): Boolean;
const
  Doom1Flats: array [1..4] of String = ('FLOOR4_8', 'SFLR6_1', 'MFLR8_4', 'MFLR8_3');
var
  E, M, I, Key: Integer;
begin
  Result := HasFinale(AMapName, AIsDoom2, Secret);
  if not Result then Exit;
  FGraphics := AGraphics;
  FSounds := ASounds;
  FMusic := AMusic;
  FIsDoom2 := AIsDoom2;
  MapNumbers(AMapName, E, M);
  FText := '';
  FPicture := '';
  SetLength(FCastNames, Length(Cast));
  for I := 0 to High(Cast) do
    FCastNames[I] := UpperCase(AStrings.Get(Cast[I].NameKey, Cast[I].DefaultName));

  if AIsDoom2 then
  begin
    { F_StartFinale: C1TEXT after MAP06 ... C6TEXT after MAP31's secret exit. }
    case M of
      6: Key := 1;
      11: Key := 2;
      20: Key := 3;
      30: Key := 4;
      15: Key := 5;
      else Key := 6;
    end;
    FText := AStrings.Get(Format('C%dTEXT', [Key]));
    case Key of
      1: FFlat := AStrings.Get('BGFLAT06', 'SLIME16');
      2: FFlat := AStrings.Get('BGFLAT11', 'RROCK14');
      3: FFlat := AStrings.Get('BGFLAT20', 'RROCK07');
      4: FFlat := AStrings.Get('BGFLAT30', 'RROCK17');
      5: FFlat := AStrings.Get('BGFLAT15', 'RROCK13');
      else FFlat := AStrings.Get('BGFLAT31', 'RROCK19');
    end;
    if M = 30 then FAfterText := fsCast else FAfterText := fsDone;
    FContinues := M <> 30;
    if FMusic <> nil then FMusic.Play('D_READ_M');
  end else
  begin
    E := Clamped(E, 1, 4);
    FText := AStrings.Get(Format('E%dTEXT', [E]));
    FFlat := AStrings.Get(Format('BGFLATE%d', [E]), Doom1Flats[E]);
    case E of
      1: if FGraphics.Patch('CREDIT') <> nil then FPicture := 'CREDIT' else FPicture := 'HELP2';
      2: FPicture := 'VICTORY2';
      4: FPicture := 'ENDPIC';
    end;
    if E = 3 then FAfterText := fsBunny else FAfterText := fsPicture;
    FContinues := false;
    if FMusic <> nil then FMusic.Play('D_VICTOR');
  end;
  if FText <> '' then
    SetStage(fsText)
  else
    SetStage(FAfterText);
end;

procedure TDoomFinale.SetStage(const S: TFinaleStage);
begin
  FStage := S;
  FTic := 0;
  FEndStage := -1;
  case S of
    fsBunny:
      if FMusic <> nil then FMusic.Play('D_BUNNY');
    fsCast:
      begin
        if FMusic <> nil then FMusic.Play('D_EVIL');
        FCastIndex := 0;
        StartCastMember;
      end;
  end;
  if S <> fsDone then Compose;
end;

function TDoomFinale.TextComplete: Boolean;
begin
  Result := (FTic - 10) div TextSpeed >= Length(FText);
end;

function TDoomFinale.CastFrames: String;
var
  Info: PThingInfo;
begin
  Result := '';
  if Cast[FCastIndex].Num = 0 then
  begin
    { The player: walking, firing, dying (S_PLAY_RUN, S_PLAY_ATK, S_PLAY_DIE). }
    case FCastPhase of
      cpWalk: Result := 'ABCD';
      cpAttack: Result := 'EF';
      cpDeath: Result := 'HIJKLMN';
    end;
    Exit;
  end;
  Info := FindThingInfo(Cast[FCastIndex].Num);
  if Info = nil then Exit;
  case FCastPhase of
    cpWalk: Result := Info^.MoveFrames;
    cpAttack: Result := Info^.AttackFrames;
    cpDeath: Result := Info^.DeathFrames;
  end;
  if Result = '' then Result := Info^.IdleFrames;
end;

procedure TDoomFinale.StartCastMember;
var
  Info: PThingInfo;
begin
  FCastPhase := cpWalk;
  FCastFrame := 1;
  FCastFrameTics := 6;
  FCastWalked := 0;
  Info := FindThingInfo(Cast[FCastIndex].Num);
  if (Info <> nil) and (Cast[FCastIndex].Num <> 0) and (Info^.SeeSound <> '') and (FSounds <> nil) then
    FSounds.Play(Info^.SeeSound);
end;

{ F_CastTicker: walk, now and then attack, and after a key the death frames,
  then the next member (the list loops). }
procedure TDoomFinale.TicCast;
var
  Frames: String;
  Info: PThingInfo;
begin
  Dec(FCastFrameTics);
  if FCastFrameTics > 0 then Exit;
  Frames := CastFrames;
  Inc(FCastFrame);
  case FCastPhase of
    cpWalk:
      begin
        FCastFrameTics := 6;
        if FCastFrame > Length(Frames) then FCastFrame := 1;
        Inc(FCastWalked);
        if FCastWalked >= 12 then
        begin
          { castattacking: show the attack once. }
          FCastPhase := cpAttack;
          FCastFrame := 1;
          FCastFrameTics := 8;
          Info := FindThingInfo(Cast[FCastIndex].Num);
          if FSounds <> nil then
          begin
            if Cast[FCastIndex].Num = 0 then
              FSounds.Play('DSDSHTGN')
            else if (Info <> nil) and (Info^.AttackSound <> '') then
              FSounds.Play(Info^.AttackSound);
          end;
        end;
      end;
    cpAttack:
      begin
        FCastFrameTics := 8;
        if FCastFrame > Length(Frames) then
        begin
          FCastPhase := cpWalk;
          FCastFrame := 1;
          FCastFrameTics := 6;
          FCastWalked := 0;
        end;
      end;
    cpDeath:
      begin
        FCastFrameTics := 6;
        if FCastFrame > Length(Frames) then
        begin
          { Hold the last frame a moment, then the next member. }
          if FCastFrame > Length(Frames) + 3 then
          begin
            FCastIndex := (FCastIndex + 1) mod Length(Cast);
            StartCastMember;
          end;
        end;
      end;
  end;
end;

procedure TDoomFinale.Tic;
begin
  if FStage = fsDone then Exit;
  Inc(FTic);
  case FStage of
    fsText:
      { Doom 1 moves on by itself; Doom 2 waits for a key. }
      if (not FIsDoom2) and TextComplete and (FTic - 10 > Length(FText) * TextSpeed + TextWait) then
      begin
        SetStage(FAfterText);
        Exit;
      end;
    fsCast:
      TicCast;
  end;
  Compose;
end;

procedure TDoomFinale.Accelerate;
var
  Info: PThingInfo;
begin
  case FStage of
    fsText:
      if not TextComplete then
        FTic := 10 + Length(FText) * TextSpeed
      else
        SetStage(FAfterText);
    fsPicture, fsBunny:
      SetStage(fsDone);
    fsCast:
      if FCastPhase <> cpDeath then
      begin
        { F_CastResponder: the member dies. }
        FCastPhase := cpDeath;
        FCastFrame := 1;
        FCastFrameTics := 6;
        if FSounds <> nil then
        begin
          Info := FindThingInfo(Cast[FCastIndex].Num);
          if Cast[FCastIndex].Num = 0 then
            FSounds.Play('DSPLDETH')
          else if (Info <> nil) and (Info^.DeathSound <> '') then
            FSounds.Play(Info^.DeathSound);
        end;
      end;
  end;
  if FStage <> fsDone then Compose;
end;

function TDoomFinale.Done: Boolean;
begin
  Result := FStage = fsDone;
end;

procedure TDoomFinale.Compose;
var
  Img: TRGBAlphaImage;
  F, P: TDoomImage;
  X, Y, I, Count, Scrolled, S: Integer;
  Lines: TStringList;
  Line, CastName, Frames: String;
  Mirror: Boolean;

  procedure DrawPatch(const Patch: TDoomImage; const PX, PY: Integer);
  begin
    if Patch <> nil then
      BlitDoomImage(Img, Patch, PX - Patch.LeftOffset, PY - Patch.TopOffset);
  end;

begin
  if FGraphics = nil then Exit;
  Img := TRGBAlphaImage.Create(320, 200);
  Img.Clear(Vector4Byte(0, 0, 0, 255));
  case FStage of
    fsText:
      begin
        { F_TextWrite: the flat tiled, the text typed from (10, 10). }
        F := FGraphics.Flat(FFlat);
        if F <> nil then
          for Y := 0 to 200 div 64 do
            for X := 0 to 320 div 64 do
              BlitDoomImage(Img, F, X * 64, Y * 64);
        Count := Max(0, (FTic - 10) div TextSpeed);
        Lines := TStringList.Create;
        try
          Lines.Text := Copy(FText, 1, Count);
          Y := 10;
          for I := 0 to Lines.Count - 1 do
          begin
            Line := Lines[I];
            DrawDoomText(FGraphics, Img, 10, Y, Line);
            Inc(Y, 11);
          end;
        finally
          FreeAndNil(Lines);
        end;
      end;
    fsPicture:
      DrawPatch(FGraphics.Patch(FPicture), 0, 0);
    fsBunny:
      begin
        { F_BunnyScroll: PFUB2 slides left to reveal PFUB1, then THE END. }
        Scrolled := Clamped(320 - (FTic - 230) div 2, 0, 320);
        BlitDoomImage(Img, FGraphics.Patch('PFUB2'), -Scrolled, 0);
        BlitDoomImage(Img, FGraphics.Patch('PFUB1'), 320 - Scrolled, 0);
        if FTic >= 1130 then
        begin
          if FTic < 1180 then S := 0 else S := Min(6, (FTic - 1180) div 5);
          if S <> FEndStage then
          begin
            FEndStage := S;
            if FSounds <> nil then FSounds.Play('DSPISTOL');
          end;
          DrawPatch(FGraphics.Patch(Format('END%d', [S])), (320 - 13 * 8) div 2, (200 - 8 * 8) div 2);
        end;
      end;
    fsCast:
      begin
        DrawPatch(FGraphics.Patch('BOSSBACK'), 0, 0);
        Frames := CastFrames;
        if Frames <> '' then
        begin
          I := Min(FCastFrame, Length(Frames));
          if Cast[FCastIndex].Num = 0 then Line := 'PLAY'
          else Line := FindThingInfo(Cast[FCastIndex].Num)^.Sprite;
          P := FGraphics.Sprite(Line, Frames[I], 1, Mirror);
          DrawPatch(P, 160, 170);
        end;
        CastName := FCastNames[FCastIndex];
        DrawDoomText(FGraphics, Img, 160 - DoomTextWidth(FGraphics, CastName) div 2, 180, CastName);
      end;
  end;
  Image := Img;
end;

end.
