{ Doom's menu (m_menu.c) drawn from the WAD's own graphics over the title
  pages: main menu, episode select (Doom 1), skill select with the Nightmare
  confirmation, the load-game slots and Read This! (HELP pages). Behind it
  runs Doom's attract loop without the demos (D_PageTicker / D_DoAdvanceDemo:
  TITLEPIC, CREDIT, HELP2 or TITLEPIC again); the menu itself appears with
  the first key, like Doom's. The 320x200 screen is composed into
  one image (like the status bar and the intermission) and shown
  pixel-perfect by a TCastleImageControl. Keyboard input is passed in by the
  owning view (HandleKey); the mouse is handled here (hover and click). }
unit DoomMenu;

interface

uses Classes,
  CastleControls, CastleImages, CastleKeysMouse, CastleUIControls, CastleVectors,
  DoomGraphics, DoomSound, DoomDehacked;

type
  TDoomMenuPage = (mpMain, mpEpisode, mpSkill, mpLoad, mpReadThis1, mpReadThis2, mpSave,
    mpOptions, mpSound);
  { maClose: an overlay's page was left with Esc (the game takes over).
    maEndGame: Options -> End Game, confirmed. maSettings: a slider or
    toggle changed (SfxVolume, MusicVolume, MouseSensitivity, MessagesOn). }
  TDoomMenuAction = (maNone, maNewGame, maLoadSlot, maOptions, maQuit, maSaveSlot, maClose,
    maEndGame, maSettings);

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
    { The saves' own names (FSlots may show more, like the time). }
    FSlotNames: array [1..6] of String;
    { M_SaveSelect: typing the name of save slot Slot. }
    FEditing: Boolean;
    FEditText: String;
    FDirty: Boolean;
    FLastSkull: Integer;
    { Main menu items (M_RDTHIS only in Doom 1, like m_menu.c). }
    FMainItems: array of String;
    { The menu is on screen (menuactive); otherwise only the pages show. }
    FMenuActive: Boolean;
    { Attract loop: the pages, how long each stays, the one shown now. }
    FPages: array of String;
    FPageTics: array of Integer;
    FPageIndex, FPageLeft: Integer;
    { Read This! pages: HELP1 / HELP2 in Doom 1, HELP in Doom 2. }
    FHelp1, FHelp2: String;
    procedure DrawThermo(const Img: TRGBAlphaImage; const X, Y, Steps, Value: Integer);
    procedure ChangeSlider(const Delta: Integer);
    function ItemName: String;
    function Selectable(const Item: Integer): Boolean;
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
    { Drawn over the running game (the in-game F2 / F3 save and load
      pages): no title page behind, transparent elsewhere, Esc closes. }
    Overlay: Boolean;
    { The in-game menu (set before Setup): Save Game in the main menu, and
      Options opens Doom's options page instead of maOptions. }
    InGame: Boolean;
    { In an overlay, backing out of this page closes the menu (maClose). }
    EntryPage: TDoomMenuPage;
    { What the options and sound pages show and change (maSettings). }
    SfxVolume, MusicVolume: Integer; { 0..15 }
    MouseSensitivity: Integer;       { 0..9 }
    MessagesOn: Boolean;
    { The save page: the name a new save starts with, and the one typed
      (read it on maSaveSlot). }
    DefaultSaveName: String;
    SaveName: String;
    constructor Create(AOwner: TComponent); override;
    { Set up for a WAD: graphics, sounds, how many episodes (0 = Doom 2). }
    procedure Setup(const AGraphics: TDoomGraphics; const ASounds: TDoomSounds; const AEpisodes: Integer;
      const AStrings: TDoomStrings);
    { Descriptions shown on the load page ('' = empty slot). }
    { SlotName is the save's own description (what the save page lets you
      edit); Description may add more for display. }
    procedure SetSlot(const Index: Integer; const Description: String; const SlotName: String = '');
    procedure OpenPage(const Page: TDoomMenuPage);
    { Show or hide the menu over the title pages. }
    procedure SetMenuActive(const Value: Boolean);
    property MenuActive: Boolean read FMenuActive;
    { The attract loop's page shown now (TITLEPIC, CREDIT...). }
    function CurrentTitlePage: String;
    { Arrow keys, Enter, Escape, Y / N. True when used. }
    function HandleKey(const Event: TInputPressRelease): Boolean;
    { Advance one Doom tic (skull blinking). }
    procedure Tic;
    function Press(const Event: TInputPressRelease): Boolean; override;
    function Motion(const Event: TInputMotion): Boolean; override;
    property Page: TDoomMenuPage read FPage;
    property Prompting: Boolean read FPrompt;
    { A save name is being typed (keys go to it). }
    property Editing: Boolean read FEditing;
  end;

const
  SkillNames: array [0..4] of String = (
    'I''m too young to die', 'Hey, not too rough', 'Hurt me plenty', 'Ultra-Violence', 'Nightmare!');

implementation

uses SysUtils, Math,
  CastleRectangles, CastleUtils,
  DoomHud, DoomFont, CastleComponentSerialize;

const
  LineHeight = 16;
  { Used when the WAD has no DEHACKED strings. }
  NightmarePrompt = 'Are you sure? This skill level' + #10 + 'isn''t even remotely fair.' + #10#10 + 'Press Y or N.';
  QuitPrompt = 'Are you sure you want to quit?';
 { SAVESTRINGSIZE - 1 characters (the border holds 24 with the cursor). }
  SaveNameLength = 23;
  EndGamePrompt = 'Are you sure you want to end the game?' + #10#10 + 'Press Y or N.';
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
  { m_menu.c: Doom 2 has no Read This! in the main menu (F1 still works). }
  FMainItems := nil;
  SetLength(FMainItems, 3);
  FMainItems[0] := 'M_NGAME';
  FMainItems[1] := 'M_OPTION';
  FMainItems[2] := 'M_LOADG';
  if InGame then
  begin
    SetLength(FMainItems, Length(FMainItems) + 1);
    FMainItems[High(FMainItems)] := 'M_SAVEG';
  end;
  if (AEpisodes > 0) and (FGraphics.Patch('M_RDTHIS') <> nil) then
  begin
    SetLength(FMainItems, Length(FMainItems) + 1);
    FMainItems[High(FMainItems)] := 'M_RDTHIS';
  end;
  SetLength(FMainItems, Length(FMainItems) + 1);
  FMainItems[High(FMainItems)] := 'M_QUITG';
  { D_DoAdvanceDemo without the demos: Doom 2 shows TITLEPIC for 11 s,
    Doom 1 for 170 tics and then HELP2 too. }
  if AEpisodes > 0 then
  begin
    FPages := ['TITLEPIC', 'CREDIT', 'HELP2'];
    FPageTics := [170, 200, 200];
    FHelp1 := 'HELP1';
    FHelp2 := 'HELP2';
  end else
  begin
    FPages := ['TITLEPIC', 'CREDIT'];
    FPageTics := [35 * 11, 200];
    FHelp1 := 'HELP';
    FHelp2 := '';
  end;
  FPageIndex := 0;
  FPageLeft := FPageTics[0];
  FDirty := true;
  Compose;
end;

function TDoomMenuScreen.ItemName: String;
begin
  Result := ItemPatch(FPage, FItemOn[FPage]);
end;

function TDoomMenuScreen.Selectable(const Item: Integer): Boolean;
begin
  Result := (Item >= 0) and (Item < ItemCount(FPage)) and
    ((FPage in [mpLoad, mpSave]) or (ItemPatch(FPage, Item) <> ''));
end;

{ The sliders' routines (M_SfxVol, M_MusicVol, M_ChangeSensitivity) and
  M_ChangeMessages. }
procedure TDoomMenuScreen.ChangeSlider(const Delta: Integer);
var
  Item: String;
begin
  Item := ItemName;
  if Item = 'M_SFXVOL' then
    SfxVolume := Max(0, Min(15, SfxVolume + Delta))
  else if Item = 'M_MUSVOL' then
    MusicVolume := Max(0, Min(15, MusicVolume + Delta))
  else if Item = 'M_MSENS' then
    MouseSensitivity := Max(0, Min(9, MouseSensitivity + Delta))
  else if Item = 'M_MESSG' then
    MessagesOn := not MessagesOn
  else
    Exit;
  if FSounds <> nil then FSounds.Play('DSSTNMOV');
  FDirty := true;
  Compose;
  if Assigned(OnAction) then OnAction(maSettings);
end;

{ M_DrawThermo: the left end, Steps middle pieces, the right end, and the
  knob on step Value. }
procedure TDoomMenuScreen.DrawThermo(const Img: TRGBAlphaImage; const X, Y, Steps, Value: Integer);
var
  I: Integer;

  procedure Draw(const PatchName: String; const PX: Integer);
  var
    P: TDoomImage;
  begin
    P := FGraphics.Patch(PatchName);
    if P <> nil then
      BlitDoomImage(Img, P, PX - P.LeftOffset, Y - P.TopOffset);
  end;

begin
  Draw('M_THERML', X);
  for I := 0 to Steps - 1 do
    Draw('M_THERMM', X + 8 + I * 8);
  Draw('M_THERMR', X + 8 + Steps * 8);
  Draw('M_THERMO', X + 8 + Value * 8);
end;

function TDoomMenuScreen.CurrentTitlePage: String;
begin
  if Length(FPages) = 0 then Exit('TITLEPIC');
  Result := FPages[FPageIndex];
end;

procedure TDoomMenuScreen.SetMenuActive(const Value: Boolean);
begin
  if FMenuActive = Value then Exit;
  FMenuActive := Value;
  FPrompt := false;
  if Value then FPage := mpMain;
  FDirty := true;
  Compose;
end;

procedure TDoomMenuScreen.SetSlot(const Index: Integer; const Description: String; const SlotName: String);
begin
  if (Index >= Low(FSlots)) and (Index <= High(FSlots)) then
  begin
    FSlots[Index] := Description;
    if SlotName <> '' then FSlotNames[Index] := SlotName else FSlotNames[Index] := Description;
  end;
  FDirty := true;
end;

function TDoomMenuScreen.ItemCount(const Page: TDoomMenuPage): Integer;
begin
  case Page of
    mpMain: Result := Length(FMainItems);
    mpReadThis1, mpReadThis2: Result := 1;
    mpOptions: Result := 5;
    mpSound: Result := 4;
    mpEpisode: Result := Max(1, FEpisodes);
    mpSkill: Result := 5;
    mpLoad, mpSave: Result := 6;
    else Result := 0;
  end;
end;

function TDoomMenuScreen.ItemPatch(const Page: TDoomMenuPage; const Index: Integer): String;
const
  SkillItems: array [0..4] of String = ('M_JKILL', 'M_ROUGH', 'M_HURT', 'M_ULTRA', 'M_NMARE');
  { m_menu.c's OptionsDef without detail and screen size; '' rows are the
    thermometers' (not selectable). }
  OptionItems: array [0..4] of String = ('M_ENDGAM', 'M_MESSG', 'M_MSENS', '', 'M_SVOL');
  SoundItems: array [0..3] of String = ('M_SFXVOL', '', 'M_MUSVOL', '');
begin
  case Page of
    mpMain: Result := FMainItems[Index];
    mpEpisode: Result := 'M_EPI' + IntToStr(Index + 1);
    mpSkill: Result := SkillItems[Index];
    mpOptions: Result := OptionItems[Index];
    mpSound: Result := SoundItems[Index];
    else Result := '';
  end;
end;

procedure TDoomMenuScreen.PageOrigin(const Page: TDoomMenuPage; out X, Y: Integer);
begin
  { MainDef, EpiDef, NewDef, LoadDef positions from m_menu.c }
  case Page of
    mpMain: begin X := 97; Y := 64; end;
    mpEpisode, mpSkill: begin X := 48; Y := 63; end;
    mpLoad, mpSave: begin X := 80; Y := 54; end;
    mpOptions: begin X := 60; Y := 37; end;
    mpSound: begin X := 80; Y := 64; end;
    { m_menu.c puts the Read This! skull off the 320x200 screen. }
    mpReadThis1, mpReadThis2: begin X := 330; Y := 165; end;
  end;
end;

procedure TDoomMenuScreen.OpenPage(const Page: TDoomMenuPage);
begin
  FPage := Page;
  FPrompt := false;
  FEditing := false;
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
  { Thermometer rows are not items (status -1 in m_menu.c). }
  repeat
    FItemOn[FPage] := (FItemOn[FPage] + Delta + N) mod N;
  until Selectable(FItemOn[FPage]);
  if FSounds <> nil then FSounds.Play('DSPSTOP');
  FDirty := true;
  Compose;
end;

procedure TDoomMenuScreen.Back;
begin
  if FSounds <> nil then FSounds.Play('DSSWTCHX');
  case FPage of
    mpLoad, mpSave, mpEpisode, mpReadThis1, mpReadThis2, mpOptions:
      if Overlay and (FPage = EntryPage) then
      begin
        if Assigned(OnAction) then OnAction(maClose);
      end else
        OpenPage(mpMain);
    mpSound:
      if Overlay and (FPage = EntryPage) then
      begin
        if Assigned(OnAction) then OnAction(maClose);
      end else
        OpenPage(mpOptions);
    mpSkill:
      if FEpisodes > 0 then OpenPage(mpEpisode) else OpenPage(mpMain);
    { M_ClearMenus: Esc on the main menu shows the title pages again, or
      gives the game back. }
    mpMain:
      if Overlay then
      begin
        if Assigned(OnAction) then OnAction(maClose);
      end else
        SetMenuActive(false);
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
      if FMainItems[Item] = 'M_NGAME' then
      begin
        if FEpisodes > 0 then OpenPage(mpEpisode) else
        begin
          Episode := 0;
          OpenPage(mpSkill);
        end;
      end else
      if FMainItems[Item] = 'M_OPTION' then
      begin
        if InGame then
          OpenPage(mpOptions)
        else
        if Assigned(OnAction) then OnAction(maOptions);
      end else
      if FMainItems[Item] = 'M_LOADG' then
        OpenPage(mpLoad)
      else if FMainItems[Item] = 'M_SAVEG' then
        OpenPage(mpSave)
      else if FMainItems[Item] = 'M_RDTHIS' then
        OpenPage(mpReadThis1)
      else if FMainItems[Item] = 'M_QUITG' then
        StartQuitPrompt;
    { M_ReadThis / M_ReadThis2 / M_FinishReadThis: any key turns the page. }
    mpReadThis1:
      if (FHelp2 <> '') and (FGraphics.Patch(FHelp2) <> nil) then
        OpenPage(mpReadThis2)
      else
        OpenPage(mpMain);
    mpReadThis2:
      OpenPage(mpMain);
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
    mpSave:
      begin
        { M_SaveSelect: edit the slot's name (a new save starts with the
          map, kills and time), Enter saves. }
        Slot := Item + 1;
        FEditing := true;
        if FSlots[Slot] <> '' then FEditText := FSlotNames[Slot] else FEditText := DefaultSaveName;
        FEditText := Copy(UpperCase(FEditText), 1, SaveNameLength);
        FDirty := true;
        Compose;
      end;
    mpOptions:
      if ItemName = 'M_ENDGAM' then
      begin
        { M_EndGame: ENDGAME asks first. }
        if FStrings <> nil then
          StartPrompt(FStrings.Get('ENDGAME', EndGamePrompt), maEndGame)
        else
          StartPrompt(EndGamePrompt, maEndGame);
      end else
      if ItemName = 'M_MESSG' then
        ChangeSlider(1)
      else if ItemName = 'M_SVOL' then
        OpenPage(mpSound);
    mpSound: ;
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
var
  C: Char;
begin
  Result := true;
  if FEditing then
  begin
    { M_Responder with saveStringEnter: type, Backspace, Enter, Esc. }
    if Event.IsKey(keyEnter) then
    begin
      if FEditText <> '' then
      begin
        FEditing := false;
        SaveName := FEditText;
        FDirty := true;
        if Assigned(OnAction) then OnAction(maSaveSlot);
      end;
    end else
    if Event.IsKey(keyEscape) then
    begin
      FEditing := false;
      FDirty := true;
      Compose;
    end else
    if Event.IsKey(keyBackSpace) then
    begin
      if FEditText <> '' then SetLength(FEditText, Length(FEditText) - 1);
      FDirty := true;
      Compose;
    end else
    if (Length(Event.KeyString) = 1) and (Event.KeyString[1] >= ' ') and (Event.KeyString[1] <= '~') then
    begin
      C := UpCase(Event.KeyString[1]);
      if Length(FEditText) < SaveNameLength then
      begin
        FEditText := FEditText + C;
        FDirty := true;
        Compose;
      end;
    end;
    Exit;
  end;
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
  if Event.IsKey(keyF1) then
  begin
    { Doom's help key works with or without the menu. }
    if not FMenuActive then
    begin
      FMenuActive := true;
      if FSounds <> nil then FSounds.Play('DSSWTCHN');
    end;
    OpenPage(mpReadThis1);
    Exit;
  end;
  if not FMenuActive then
  begin
    { The title pages: any key brings the menu (G_Responder during demos). }
    if Event.EventType <> itKey then Exit(false);
    if FSounds <> nil then FSounds.Play('DSSWTCHN');
    SetMenuActive(true);
    Exit;
  end;
  if (FPage in [mpReadThis1, mpReadThis2]) and not (Event.IsKey(keyEscape) or Event.IsKey(keyBackSpace)) then
  begin
    Activate;
    Exit;
  end;
  if Event.IsKey(keyArrowLeft) or Event.IsKey(keyArrowRight) then
  begin
    if Event.IsKey(keyArrowLeft) then ChangeSlider(-1) else ChangeSlider(1);
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
  if Result or FPrompt or not MouseEnabled or not FMenuActive then Exit;
  if FPage in [mpReadThis1, mpReadThis2] then Exit;
  if DoomPoint(Event.Position, DX, DY) then
  begin
    Item := ItemAt(DX, DY);
    if Selectable(Item) and (Item <> FItemOn[FPage]) then
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
  { Typing a save name: the mouse waits (Enter / Esc end it). }
  if FEditing then Exit(true);
  if not FMenuActive then
  begin
    if Event.IsMouseButton(buttonLeft) then
    begin
      if FSounds <> nil then FSounds.Play('DSSWTCHN');
      SetMenuActive(true);
      Exit(true);
    end;
    Exit;
  end;
  if Event.IsMouseButton(buttonLeft) and (FPage in [mpReadThis1, mpReadThis2]) then
  begin
    Activate;
    Exit(true);
  end;
  if Event.IsMouseButton(buttonLeft) and DoomPoint(Event.Position, DX, DY) then
  begin
    if FPrompt then Exit(true);
    Item := ItemAt(DX, DY);
    if Selectable(Item) then
    begin
      FItemOn[FPage] := Item;
      Activate;
      Exit(true);
    end;
  end;
  { Over the game, a click beside the items of the first page closes the
    menu (the game takes the mouse back). }
  if Overlay and Event.IsMouseButton(buttonLeft) and (FPage = EntryPage) and not FPrompt then
  begin
    if Assigned(OnAction) then OnAction(maClose);
    Exit(true);
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
  { D_PageTicker: the next title page when this one's time is up. }
  if Length(FPages) > 0 then
  begin
    Dec(FPageLeft);
    if FPageLeft <= 0 then
    begin
      FPageIndex := (FPageIndex + 1) mod Length(FPages);
      FPageLeft := FPageTics[FPageIndex];
      if FGraphics.Patch(FPages[FPageIndex]) = nil then FPageLeft := 1; { missing: skip }
      FDirty := true;
    end;
  end;
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
  if Overlay then
    Img.Clear(Vector4Byte(0, 0, 0, 0))
  else
    Img.Clear(Vector4Byte(0, 0, 0, 255));
  if FMenuActive and (FPage in [mpReadThis1, mpReadThis2]) and not FPrompt then
  begin
    { M_DrawReadThis1 / 2: the help page over the whole screen. }
    if FPage = mpReadThis1 then Text := FHelp1 else Text := FHelp2;
    if FGraphics.Patch(Text) <> nil then
      BlitDoomImage(Img, FGraphics.Patch(Text), 0, 0);
    Image := Img;
    Exit;
  end;
  if not Overlay then
  begin
    if FGraphics.Patch(CurrentTitlePage) <> nil then
      BlitDoomImage(Img, FGraphics.Patch(CurrentTitlePage), 0, 0)
    else
      BlitDoomImage(Img, FGraphics.Patch('TITLEPIC'), 0, 0);
  end;
  if not FMenuActive then
  begin
    Image := Img;
    Exit;
  end;
  { Dim the page so the menu reads well over it (Freedoom's TITLEPIC has
    its own logo where M_DOOM goes). }
  if not Overlay then
  begin
    Pix := PVector4Byte(Img.RawPixels);
    for I := 0 to 320 * 200 - 1 do
    begin
      Pix^.X := Pix^.X div 2;
      Pix^.Y := Pix^.Y div 2;
      Pix^.Z := Pix^.Z div 2;
      Inc(Pix);
    end;
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
    mpSave:
      DrawPatch('M_SAVEG', 72, 28);
    mpOptions:
      begin
        DrawPatch('M_OPTTTL', 108, 15);
        { M_DrawOptions: messages on / off, the sensitivity thermometer. }
        if MessagesOn then DrawPatch('M_MSGON', X + 175, Y + LineHeight * 1)
        else DrawPatch('M_MSGOFF', X + 175, Y + LineHeight * 1);
        DrawThermo(Img, X, Y + LineHeight * 3, 10, MouseSensitivity);
      end;
    mpSound:
      begin
        { M_DrawSound }
        DrawPatch('M_SVOL', 60, 38);
        DrawThermo(Img, X, Y + LineHeight * 1, 16, SfxVolume);
        DrawThermo(Img, X, Y + LineHeight * 3, 16, MusicVolume);
      end;
  end;

  if FPage in [mpLoad, mpSave] then
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
      { The name being typed, with Doom's "_" cursor. }
      if FEditing and (FPage = mpSave) and (Slot = I + 1) then Text := FEditText + '_';
      { SAVESTRINGSIZE: the border holds 24 characters. }
      DrawDoomText(FGraphics, Img, X, LineY, UpperCase(Copy(Text, 1, 24)));
    end;
  end else
    for I := 0 to ItemCount(FPage) - 1 do
      if ItemPatch(FPage, I) <> '' then
        DrawPatch(ItemPatch(FPage, I), X, Y + LineHeight * I);

  { Skull cursor }
  if FLastSkull = 0 then Text := 'M_SKULL1' else Text := 'M_SKULL2';
  DrawPatch(Text, X + SkullXOff, Y + SkullYOff + FItemOn[FPage] * LineHeight);
  Image := Img;
end;

initialization
  RegisterSerializableComponent(TDoomMenuScreen, 'Doom Menu Screen');
end.
