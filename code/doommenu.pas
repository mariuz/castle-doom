{ Doom's menu (m_menu.c) drawn from the WAD's own graphics over TITLEPIC:
  main menu, episode select (Doom 1), skill select with the Nightmare
  confirmation, and the load-game slots. The 320x200 screen is composed into
  one image (like the status bar and the intermission) and shown
  pixel-perfect by a TCastleImageControl. Keyboard input is passed in by the
  owning view (HandleKey); the mouse is handled here (hover and click). }
unit DoomMenu;

interface

uses Classes,
  CastleControls, CastleImages, CastleKeysMouse, CastleUIControls, CastleVectors,
  DoomGraphics, DoomSound, DoomDehacked;

type
  TDoomMenuPage = (mpMain, mpEpisode, mpSkill, mpLoad);
  TDoomMenuAction = (maNone, maNewGame, maLoadSlot, maOptions, maQuit);

  TDoomMenuEvent = procedure (const Action: TDoomMenuAction) of object;

  TDoomMenuScreen = class(TCastleImageControl)
  strict private
    FGraphics: TDoomGraphics;
    FSounds: TDoomSounds;
    FPage: TDoomMenuPage;
    FItemOn: array [TDoomMenuPage] of Integer;
    FTic: Integer;
    { M_StartMessage: a question over the menu (Nightmare, quit); Y does
      FPromptAction. }
    FPrompt: Boolean;
    FPromptText: String;
    FPromptAction: TDoomMenuAction;
    FStrings: TDoomStrings;
    FEpisodes: Integer;
    FSlots: array [1..6] of String;
    FDirty: Boolean;
    FLastSkull: Integer;
    procedure Compose;
    function ItemCount(const Page: TDoomMenuPage): Integer;
    function ItemPatch(const Page: TDoomMenuPage; const Index: Integer): String;
    procedure PageOrigin(const Page: TDoomMenuPage; out X, Y: Integer);
    procedure Activate;
    procedure StartQuitPrompt;
    procedure StartPrompt(const Text: String; const Action: TDoomMenuAction);
    procedure Move(const Delta: Integer);
    procedure Back;
    function DoomPoint(const ScreenPos: TVector2; out DX, DY: Single): Boolean;
    function ItemAt(const DX, DY: Single): Integer;
  public
    { Results of the last action. }
    Episode: Integer; { 1..4, 0 for Doom 2 (no episode menu) }
    Skill: Integer;   { 0..4 }
    Slot: Integer;    { 1..6 }
    OnAction: TDoomMenuEvent;
    { Mouse hover and clicks (off for scripted tests: the real cursor over
      the window would move the selection). }
    MouseEnabled: Boolean;
    constructor Create(AOwner: TComponent); override;
    { Set up for a WAD: graphics, sounds, how many episodes (0 = Doom 2). }
    procedure Setup(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds; const AEpisodes: Integer;
      const AStrings: TDoomStrings);
    { Descriptions shown on the load page ('' = empty slot). }
    procedure SetSlot(const Index: Integer; const Description: String);
    procedure OpenPage(const Page: TDoomMenuPage);
    { Arrow keys, Enter, Escape, Y / N. True when used. }
    function HandleKey(const Event: TInputPressRelease): Boolean;
    { Advance one Doom tic (skull blinking). }
    procedure Tic;
    function Press(const Event: TInputPressRelease): Boolean; override;
    function Motion(const Event: TInputMotion): Boolean; override;
    property Page: TDoomMenuPage read FPage;
    property Prompting: Boolean read FPrompt;
  end;

const
  SkillNames: array [0..4] of String = (
    'I''m too young to die', 'Hey, not too rough', 'Hurt me plenty', 'Ultra-Violence', 'Nightmare!');

implementation

uses SysUtils, Math,
  CastleRectangles, CastleUtils,
  DoomHud, DoomFont;

const
  LineHeight = 16;
  { Used when the WAD has no DEHACKED strings. }
  NightmarePrompt = 'Are you sure? This skill level' + #10 + 'isn''t even remotely fair.' + #10#10 + 'Press Y or N.';
  QuitPrompt = 'Are you sure you want to quit?';
  QuitPromptKey = '(Press Y to quit.)';
  SkullXOff = -32;
  SkullYOff = -5;

constructor TDoomMenuScreen.Create(AOwner: TComponent);
begin
  inherited;
  SmoothScaling := false;
  Stretch := true;
  FItemOn[mpSkill] := 2; { Hurt me plenty, like Doom }
  MouseEnabled := true;
  Skill := 2;
  FDirty := true;
end;

procedure TDoomMenuScreen.Setup(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds; const AEpisodes: Integer;
  const AStrings: TDoomStrings);
begin
  FStrings := AStrings;
  FGraphics := AGraphics;
  FSounds := ASounds;
  FEpisodes := AEpisodes;
  FPage := mpMain;
  FPrompt := false;
  FDirty := true;
  Compose;
end;

procedure TDoomMenuScreen.SetSlot(const Index: Integer; const Description: String);
begin
  if (Index >= Low(FSlots)) and (Index <= High(FSlots)) then
    FSlots[Index] := Description;
  FDirty := true;
end;

function TDoomMenuScreen.ItemCount(const Page: TDoomMenuPage): Integer;
begin
  case Page of
    mpMain: Result := 4;
    mpEpisode: Result := Max(1, FEpisodes);
    mpSkill: Result := 5;
    mpLoad: Result := 6;
    else Result := 0;
  end;
end;

function TDoomMenuScreen.ItemPatch(const Page: TDoomMenuPage; const Index: Integer): String;
const
  MainItems: array [0..3] of String = ('M_NGAME', 'M_OPTION', 'M_LOADG', 'M_QUITG');
  SkillItems: array [0..4] of String = ('M_JKILL', 'M_ROUGH', 'M_HURT', 'M_ULTRA', 'M_NMARE');
begin
  case Page of
    mpMain: Result := MainItems[Index];
    mpEpisode: Result := 'M_EPI' + IntToStr(Index + 1);
    mpSkill: Result := SkillItems[Index];
    else Result := '';
  end;
end;

procedure TDoomMenuScreen.PageOrigin(const Page: TDoomMenuPage; out X, Y: Integer);
begin
  { MainDef, EpiDef, NewDef, LoadDef positions from m_menu.c }
  case Page of
    mpMain: begin X := 97; Y := 64; end;
    mpEpisode, mpSkill: begin X := 48; Y := 63; end;
    mpLoad: begin X := 80; Y := 54; end;
  end;
end;

procedure TDoomMenuScreen.OpenPage(const Page: TDoomMenuPage);
begin
  FPage := Page;
  FPrompt := false;
  { The skill page starts at the current skill (Hurt me plenty by default). }
  if Page = mpSkill then FItemOn[Page] := Skill;
  FItemOn[Page] := Clamped(FItemOn[Page], 0, ItemCount(Page) - 1);
  FDirty := true;
  Compose;
end;

procedure TDoomMenuScreen.Move(const Delta: Integer);
var
  N: Integer;
begin
  N := ItemCount(FPage);
  FItemOn[FPage] := (FItemOn[FPage] + Delta + N) mod N;
  if FSounds <> nil then FSounds.Play('DSPSTOP');
  FDirty := true;
  Compose;
end;

procedure TDoomMenuScreen.Back;
begin
  if FSounds <> nil then FSounds.Play('DSSWTCHX');
  case FPage of
    mpEpisode, mpLoad: OpenPage(mpMain);
    mpSkill:
      if FEpisodes > 0 then OpenPage(mpEpisode) else OpenPage(mpMain);
    mpMain: ;
  end;
end;

procedure TDoomMenuScreen.Activate;
var
  Item: Integer;
begin
  Item := FItemOn[FPage];
  if FSounds <> nil then FSounds.Play('DSPISTOL');
  case FPage of
    mpMain:
      case Item of
        0: if FEpisodes > 0 then OpenPage(mpEpisode) else
           begin
             Episode := 0;
             OpenPage(mpSkill);
           end;
        1: if Assigned(OnAction) then OnAction(maOptions);
        2: OpenPage(mpLoad);
        3: StartQuitPrompt;
      end;
    mpEpisode:
      begin
        Episode := Item + 1;
        OpenPage(mpSkill);
      end;
    mpSkill:
      begin
        Skill := Item;
        if Item = 4 then
        begin
          { M_ChooseSkill: Nightmare asks first. }
          if FStrings <> nil then
            StartPrompt(FStrings.Get('NIGHTMARE', NightmarePrompt), maNewGame)
          else
            StartPrompt(NightmarePrompt, maNewGame);
        end else
        if Assigned(OnAction) then OnAction(maNewGame);
      end;
    mpLoad:
      begin
        Slot := Item + 1;
        if (FSlots[Slot] <> '') and Assigned(OnAction) then OnAction(maLoadSlot);
      end;
  end;
end;

procedure TDoomMenuScreen.StartPrompt(const Text: String; const Action: TDoomMenuAction);
begin
  FPrompt := true;
  FPromptText := Text;
  FPromptAction := Action;
  FDirty := true;
  Compose;
end;

{ M_QuitDOOM: one of the quit messages plus DOSY, Y quits. }
procedure TDoomMenuScreen.StartQuitPrompt;
var
  Msgs: TStringList;
  I: Integer;
  Key: String;
begin
  Msgs := TStringList.Create;
  try
    if FStrings <> nil then
      for I := 0 to 30 do
      begin
        if I = 0 then Key := 'QUITMSG' else Key := 'QUITMSG' + IntToStr(I);
        if FStrings.Has(Key) then Msgs.Add(FStrings.Get(Key));
      end;
    if Msgs.Count = 0 then Msgs.Add(QuitPrompt);
    if FStrings <> nil then
      StartPrompt(Msgs[Random(Msgs.Count)] + #10#10 + FStrings.Get('DOSY', QuitPromptKey), maQuit)
    else
      StartPrompt(Msgs[Random(Msgs.Count)] + #10#10 + QuitPromptKey, maQuit);
  finally
    FreeAndNil(Msgs);
  end;
end;

function TDoomMenuScreen.HandleKey(const Event: TInputPressRelease): Boolean;
begin
  Result := true;
  if FPrompt then
  begin
    if Event.IsKey(keyY) or Event.IsKey(keyEnter) then
    begin
      FPrompt := false;
      FDirty := true;
      Compose;
      if Assigned(OnAction) then OnAction(FPromptAction);
    end else
    if Event.IsKey(keyN) or Event.IsKey(keyEscape) or Event.IsKey(keyBackSpace) then
    begin
      FPrompt := false;
      if FSounds <> nil then FSounds.Play('DSSWTCHX');
      FDirty := true;
      Compose;
    end;
    Exit;
  end;
  if Event.IsKey(keyArrowUp) then Move(-1)
  else if Event.IsKey(keyArrowDown) then Move(1)
  else if Event.IsKey(keyEnter) or Event.IsKey(keySpace) then Activate
  else if Event.IsKey(keyEscape) or Event.IsKey(keyBackSpace) then Back
  else Result := false;
end;

function TDoomMenuScreen.DoomPoint(const ScreenPos: TVector2; out DX, DY: Single): Boolean;
var
  R: TFloatRectangle;
begin
  R := RenderRect;
  Result := (R.Width > 0) and (R.Height > 0) and R.Contains(ScreenPos);
  if not Result then Exit;
  DX := (ScreenPos.X - R.Left) / R.Width * 320;
  DY := 200 - (ScreenPos.Y - R.Bottom) / R.Height * 200;
end;

function TDoomMenuScreen.ItemAt(const DX, DY: Single): Integer;
var
  X, Y: Integer;
begin
  PageOrigin(FPage, X, Y);
  Result := Floor((DY - Y) / LineHeight);
  if (Result < 0) or (Result >= ItemCount(FPage)) or (DX < X + SkullXOff) then
    Result := -1;
end;

function TDoomMenuScreen.Motion(const Event: TInputMotion): Boolean;
var
  DX, DY: Single;
  Item: Integer;
begin
  Result := inherited;
  if Result or FPrompt or not MouseEnabled then Exit;
  if DoomPoint(Event.Position, DX, DY) then
  begin
    Item := ItemAt(DX, DY);
    if (Item >= 0) and (Item <> FItemOn[FPage]) then
    begin
      FItemOn[FPage] := Item;
      FDirty := true;
      Compose;
    end;
  end;
end;

function TDoomMenuScreen.Press(const Event: TInputPressRelease): Boolean;
var
  DX, DY: Single;
  Item: Integer;
begin
  Result := inherited;
  if Result or not MouseEnabled then Exit;
  if Event.IsMouseButton(buttonLeft) and DoomPoint(Event.Position, DX, DY) then
  begin
    if FPrompt then Exit(true);
    Item := ItemAt(DX, DY);
    if Item >= 0 then
    begin
      FItemOn[FPage] := Item;
      Activate;
      Exit(true);
    end;
  end;
  if Event.IsMouseButton(buttonRight) then
  begin
    Back;
    Exit(true);
  end;
end;

procedure TDoomMenuScreen.Tic;
var
  Skull: Integer;
begin
  Inc(FTic);
  { The skull blinks every 8 tics. }
  Skull := (FTic div 8) mod 2;
  if Skull <> FLastSkull then
  begin
    FLastSkull := Skull;
    FDirty := true;
  end;
  if FDirty then Compose;
end;

procedure TDoomMenuScreen.Compose;
var
  Img: TRGBAlphaImage;
  X, Y, I, K, LineY: Integer;
  Lines: TStringList;
  Text: String;
  Pix: PVector4Byte;

  { V_DrawPatch: the patch's offsets move it. }
  procedure DrawPatch(const Name: String; const PX, PY: Integer);
  var
    P: TDoomImage;
  begin
    P := FGraphics.Patch(Name);
    if P <> nil then
      BlitDoomImage(Img, P, PX - P.LeftOffset, PY - P.TopOffset);
  end;

begin
  if FGraphics = nil then Exit;
  FDirty := false;
  Img := TRGBAlphaImage.Create(320, 200);
  Img.Clear(Vector4Byte(0, 0, 0, 255));
  BlitDoomImage(Img, FGraphics.Patch('TITLEPIC'), 0, 0);
  { Dim the title picture so the menu reads well over it (Freedoom's
    TITLEPIC has its own logo where M_DOOM goes). }
  Pix := PVector4Byte(Img.RawPixels);
  for I := 0 to 320 * 200 - 1 do
  begin
    Pix^.X := Pix^.X div 2;
    Pix^.Y := Pix^.Y div 2;
    Pix^.Z := Pix^.Z div 2;
    Inc(Pix);
  end;
  PageOrigin(FPage, X, Y);

  if FPrompt then
  begin
    { M_StartMessage: only the message, centred line by line, in the HU font. }
    Lines := TStringList.Create;
    try
      Lines.Text := UpperCase(FPromptText);
      LineY := 100 - (Lines.Count * 8) div 2;
      for I := 0 to Lines.Count - 1 do
      begin
        DrawDoomText(FGraphics, Img, 160 - DoomTextWidth(FGraphics, Lines[I]) div 2, LineY, Lines[I]);
        Inc(LineY, 8);
      end;
    finally
      FreeAndNil(Lines);
    end;
    Image := Img;
    Exit;
  end;

  case FPage of
    mpMain:
      DrawPatch('M_DOOM', 94, 2);
    mpEpisode:
      DrawPatch('M_EPISOD', 54, 38);
    mpSkill:
      begin
        DrawPatch('M_NEWG', 96, 14);
        DrawPatch('M_SKILL', 54, 38);
      end;
    mpLoad:
      DrawPatch('M_LOADG', 72, 28);
  end;

  if FPage = mpLoad then
  begin
    { M_DrawSaveLoadBorder + M_WriteText of each slot. }
    for I := 0 to 5 do
    begin
      LineY := Y + LineHeight * I;
      DrawPatch('M_LSLEFT', X - 8, LineY + 7);
      for K := 0 to 23 do
        DrawPatch('M_LSCNTR', X + K * 8, LineY + 7);
      DrawPatch('M_LSRGHT', X + 24 * 8, LineY + 7);
      if FSlots[I + 1] <> '' then Text := FSlots[I + 1] else Text := 'EMPTY SLOT';
      DrawDoomText(FGraphics, Img, X, LineY, UpperCase(Text));
    end;
  end else
    for I := 0 to ItemCount(FPage) - 1 do
      DrawPatch(ItemPatch(FPage, I), X, Y + LineHeight * I);

  { Skull cursor }
  if FLastSkull = 0 then Text := 'M_SKULL1' else Text := 'M_SKULL2';
  DrawPatch(Text, X + SkullXOff, Y + SkullYOff + FItemOn[FPage] * LineHeight);
  Image := Img;
end;

end.
