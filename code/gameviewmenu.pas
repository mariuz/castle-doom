{ Title screen: Doom's own menu (New Game, episode, skill, Load Game) drawn
  from the WAD's M_* graphics by TDoomMenuScreen, and an Options panel made of
  CGE buttons to pick a WAD (Freedoom Phase 1 = Doom 1 style episodes,
  Freedoom Phase 2 = Doom 2 style MAPxx, or your own IWAD / PWADs), a
  starting map and the skill. }
unit GameViewMenu;

interface

uses Classes, SysUtils, FpJson,
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse, CastleImages,
  CastleDownload, CastleZip,
  DoomWad, DoomGraphics, DoomSound, DoomMusic, DoomMenu, DoomDehacked, DoomMapInfo, DoomRandomMap, DoomDemo, GameSettings, GameTouch;

type
  TViewMenu = class(TCastleView)
  strict private
    FDoomMenu: TDoomMenuScreen;
    FOptions: TCastleRectangleControl;
    FButtons: TCastleVerticalGroup;
    FMapLabel: TCastleLabel;
    FSkillLabel: TCastleLabel;
    FSfxLabel, FMusicLabel: TCastleLabel;
    FFovLabel, FUiScaleLabel, FRenderScaleLabel, FFrameCapLabel: TCastleLabel;
    FVSyncButton: TCastleButton;
    FDynamicLightsButton: TCastleButton;
    FFullscreenButton: TCastleButton;
    { The Controls page: a button per action and slot; the one waiting
      for a key (FWaitSlot -1: none). }
    FControls: TCastleRectangleControl;
    FKeyButtons: array [TGameAction, 0..1] of TCastleButton;
    { The mouse column (FWaitSlot 2 waits for a mouse button or wheel). }
    FMouseButtons: array [TGameAction] of TCastleButton;
    { The keyboard half's pages (GameSettings.ControlsPageNames). }
    FControlsPage: Integer;
    FControlsPageGroups: array [0..ControlsPageCount - 1] of TCastleVerticalGroup;
    FWaitAction: TGameAction;
    FWaitSlot: Integer;
    { The page's gamepad half: its rows, the action waiting for a button. }
    FPadMode: Boolean;
    { The page's touch half (after the gamepad's): layout and size. }
    FTouchMode: Boolean;
    FTouchHandButton, FTouchSizeButton, FTouchOpacityButton: TCastleButton;
    { The touch layout editor: the controls over a dark backdrop, a finger
      (the mouse) drags the buttons. }
    FTouchEditor: TCastleRectangleControl;
    FTouchEditControls: TDoomTouchControls;
    FPadButtons: array [TPadAction, 0..1] of TCastleButton;
    FWaitPadAction: TPadAction;
    FStatus: TCastleLabel;
    FWad: TDoomWad;
    FGraphics: TDoomGraphics;
    FSounds: TDoomSounds;
    FMusic: TDoomMusic;
    FStrings: TDoomStrings;
    FIwadUrl: String;
    FPwads: TStringList;
    FWadsLabel: TCastleLabel;
    FContinueButton: TCastleButton;
    FMapIndex: Integer;
    FSkill: Integer;
    FTicAccum: Single;
    FAutoTestTics: Integer;
    { MENUTOUCHEDIT: drag FIRE once the editor has its size. }
    FTouchEditDrag: Boolean;
    FMenuKeys: TStringList;
    FMenuKeyTics, FMenuShots: Integer;
    { Freedoom Phase 2 downloaded on demand (the web build ships only Phase
      1 in its data): the download in progress, then the zip, mounted as
      freedoom2-zip:. What to do once it arrives: FFetchPwads load, then
      FFetchSlot (a saved game) or FFetchCommandLine (the command line's map). }
    FFetch: TCastleDownload;
    FFetchZip: TCastleZip;
    FFetchPwads: TStringList;
    FFetchSlot: Integer;
    FFetchCommandLine: Boolean;
    FFetchLabel: TCastleLabel;
    FNewGameRequested: Boolean;
    { The Doom menu's custom game page is open (reopened after the WADs
      reload, which sets the menu up anew). }
    FCustomOpen: Boolean;
    FPwadsOpen: Boolean;
    FNewGameEpisode, FNewGameSkill: Integer;
    { Load the IWAD and PWADs (title music, menus follow). False when they
      did not load, or when Freedoom Phase 2 is being downloaded first. }
    function LoadWads(const Iwad: String; const Pwads: TStrings): Boolean;
    function NeedsFetch(const Iwad: String): Boolean;
    procedure StartFetch(const Pwads: TStrings);
    procedure FetchFinished(const Sender: TCastleDownload; var FreeSender: Boolean);
    { The command-line part of Start (map, warp, autotest), also run when a
      download it waited for arrives. }
    procedure StartFromCommandLine;
    procedure StartRequestedNewGame(Sender: TObject);
    { The map editor on the chosen map (--edit, the custom game page). }
    procedure StartEditor;
    procedure SetupDoomMenu;
    procedure RefreshSlots;
    { A menu starts or stops typing: the on-screen keyboard (GameTouch). }
    procedure MenuEditingChange(Sender: TObject);
    procedure DoomMenuAction(const Action: TDoomMenuAction);
    procedure StartRandomGame;
    { The custom game page (DoomMenu mpCustom): its requests, its values. }
    procedure CustomGameAction;
    procedure ShowCustomPage;
    { The custom page's PWADs page (DoomMenu mpPwads), reopened like the
      custom page after the WADs reload. }
    procedure ShowPwadsPage;
    { Load these PWADs on the current IWAD (the PWADs page's changes). }
    procedure LoadPwads(const Pwads: TStrings);
    procedure CycleRecent(const Delta: Integer);
    { The browser's file picker for an IWAD or a PWAD (OPENIWAD,
      PWADADD); the file arrives in a later Update (PollPickedFile). }
    procedure PickBrowserFile(const Kind: String);
    procedure PollPickedFile;
    procedure UseFile(const Url: String; const Iwad: Boolean);
    procedure AutoPlayDemo(Sender: TObject);
    procedure ClickRecordDemo(Sender: TObject);
    procedure ClickPlayDemo(Sender: TObject);
    procedure ShowOptions(const Value: Boolean);
    procedure ClickOpenIwad(Sender: TObject);
    procedure ClickAddPwad(Sender: TObject);
    procedure ClickLastWads(Sender: TObject);
    procedure ClickContinue(Sender: TObject);
    procedure ClickExportSaves(Sender: TObject);
    procedure ClickImportSaves(Sender: TObject);
    procedure ClickBack(Sender: TObject);
    procedure ContinueFromSlot(const Slot: Integer);
    procedure AutoContinue(Sender: TObject);
    procedure AutoDesign(Sender: TObject);
    procedure UpdateWadsLabel;
    procedure RememberWads;
    procedure ClickPhase1(Sender: TObject);
    procedure ClickPhase2(Sender: TObject);
    procedure ClickStart(Sender: TObject);
    procedure ClickPrevMap(Sender: TObject);
    procedure ClickNextMap(Sender: TObject);
    procedure ClickPrevSkill(Sender: TObject);
    procedure ClickNextSkill(Sender: TObject);
    procedure ClickSfxDown(Sender: TObject);
    procedure ClickSfxUp(Sender: TObject);
    procedure ClickMusicDown(Sender: TObject);
    procedure ClickMusicUp(Sender: TObject);
    { Apply and remember a volume change (0 sound effects, 1 music). }
    procedure ChangeVolume(const Which, Delta: Integer);
    procedure UpdateVolumeLabels;
    { The video options (GameSettings): 0 field of view, 1 UI scale,
      2 render scale, by Delta steps; applied and saved. }
    procedure ChangeVideo(const Which, Delta: Integer);
    procedure UpdateVideoLabels;
    procedure ClickFovDown(Sender: TObject);
    procedure ClickFovUp(Sender: TObject);
    procedure ClickUiScaleDown(Sender: TObject);
    procedure ClickUiScaleUp(Sender: TObject);
    procedure ClickRenderScaleDown(Sender: TObject);
    procedure ClickRenderScaleUp(Sender: TObject);
    procedure ClickFullscreen(Sender: TObject);
    procedure ClickVSync(Sender: TObject);
    procedure ClickDynamicLights(Sender: TObject);
    procedure ClickFrameCapDown(Sender: TObject);
    procedure ClickFrameCapUp(Sender: TObject);
    procedure ClickControls(Sender: TObject);
    procedure ClickControlsBack(Sender: TObject);
    procedure ClickKeysDefaults(Sender: TObject);
    procedure ClickKeyButton(Sender: TObject);
    procedure ClickPadButton(Sender: TObject);
    { Switch the Controls page between the keys and the gamepad. }
    procedure ClickControlsPad(Sender: TObject);
    procedure ClickControlsPage(Sender: TObject);
    procedure ClickMouseButton(Sender: TObject);
    procedure ShowTouchEditor(const Show: Boolean);
    procedure TouchButtonMoved(const Button: TTouchButton; const Position: TVector2);
    procedure DragTouchFire;
    procedure ClickTouchHand(Sender: TObject);
    procedure ClickTouchSize(Sender: TObject);
    procedure ClickTouchOpacity(Sender: TObject);
    procedure ClickTouchEdit(Sender: TObject);
    procedure ClickTouchEditDone(Sender: TObject);
    procedure ClickTouchResetPlaces(Sender: TObject);
    procedure ShowControlsMode;
    { Bind the gamepad button the page waits for (pbNone clears). }
    procedure BindWaitingPad(const B: TPadButton);
    procedure BuildControlsRows;
    procedure UpdateKeyButtons;
    { The key press the Controls page waits for (Escape cancels,
      BackSpace clears the slot). }
    function ControlsKey(const Event: TInputPressRelease): Boolean;
    procedure UpdateMapLabel;
    procedure UpdateSkillLabel;
    procedure StartGame;
    procedure AutoStart(Sender: TObject);
    procedure AutoTestMenu;
    procedure AutoScreenshot;
    procedure NextMenuKey;
  public
    { New Game chosen in the in-game menu: the title view starts it (the
      episode 0 means the first map, Doom 2). }
    procedure RequestNewGame(const Episode, Skill: Integer);
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
    { The Controls page waiting for a mouse button takes the next click
      or wheel step before the buttons under the pointer see it. }
    function PreviewPress(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMenu: TViewMenu;
  { Set from the command line (--autotest MAP PREFIX): start this map at once.
    MAP = MENU, MENUEPISODE, MENUSKILL, MENUNIGHTMARE, MENUQUIT, MENULOAD, MENUOPTIONS, MENUCONTROLS,
    MENUCONTROLSPAD, MENUCONTROLSHOTKEYS, MENUCONTROLSTOUCH, MENUTOUCHEDIT,
    MENUDOOM2, MENUTITLE (title pages, menu closed) or MENUREADTHIS takes a
    screenshot of that menu page instead. }
  AutoTestMap: String;
  AutoTestPrefix: String;
  AutoTestDemo: String;
  { --fixed-step: every frame advances exactly one Doom tic (1/35 s) and
    each map starts with the same random seed, so autotest screenshots of
    moving scenes come out the same on every run (golden screenshots). }
  AutoTestFixedStep: Boolean;
  { --autotest MENUKEYS PREFIX --menukeys "D,D,E,...": drive the Doom menu
    (U up, D down, E enter, X escape, Y / N, S screenshot); a started game
    then runs --demo. }
  AutoTestMenuKeys: String;
  { Set from the command line: -iwad FILE, -file PWAD..., -warp MAP. }
  CmdIwad: String;
  CmdPwads: TStringList;
  CmdWarp: String;
  { --wad-base-url URL: fetch Freedoom Phase 2 as URL + freedoom2.zip even
    when the WAD is in the data (tests the browser's on-demand download on
    the desktop). In the browser the page's directory is used. }
  WadBaseUrl: String;
  { -loadgame N: start from saved game slot N (0 = quick save). }
  CmdLoadSlot: Integer = -1;
  { -skill N (Doom's 1..5) stored as 0..4; -1 when not given. }
  CmdSkill: Integer = -1;

implementation

uses Math, CastleLog, CastleColors, CastleUtils, CastleWindow, CastleConfig, CastleUriUtils, CastleRectangles,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  CastleStringUtils,
  CastleFilesUtils,
  GameViewPlay, GameSaveBundle, GameSaveStorage, GameGamepad, GameViewDesign, GameViewEdit;

const
  Freedoom1 = 'castle-data:/wads/freedoom1.wad';
  Freedoom2 = 'castle-data:/wads/freedoom2.wad';
  TicSeconds = 1 / 35;

constructor TViewMenu.Create(AOwner: TComponent);
begin
  inherited;
  FPwads := TStringList.Create;
  FMenuKeys := TStringList.Create;
  FFetchPwads := TStringList.Create;
  FFetchSlot := -1;
  FSkill := 2;
  DesignUrl := 'castle-data:/menu.castle-user-interface';
end;

procedure TViewMenu.Start;

  procedure Click(const ButtonName: String; const Handler: TNotifyEvent);
  begin
    (DesignedComponent(ButtonName) as TCastleButton).OnClick := Handler;
  end;

begin
  inherited;
  if CmdSkill >= 0 then FSkill := CmdSkill;
  { Back from the map editor's play-test: without its PWAD (the editor
  key in a later game opens the editor anew). }
  RemoveEditedWads(FWad);
  ViewEdit.PlayTesting := false;

  { The whole screen is data/menu.castle-user-interface (a CGE editor
    design): the black background, Doom's menu over TITLEPIC (320x200
    shown 4:3, sized in Update), the Options panel (the WAD / map / skill
    / volume picker, your own WADs, the save transfer, the WAD and
    licence lines) and the Phase 2 download line. Only the handlers and
    the run-time texts are set here. }
  FDoomMenu := DesignedComponent('DoomMenu') as TDoomMenuScreen;
  FDoomMenu.OnAction := {$ifdef FPC}@{$endif} DoomMenuAction;
  FDoomMenu.OnEditingChange := {$ifdef FPC}@{$endif} MenuEditingChange;
  FOptions := DesignedComponent('OptionsPanel') as TCastleRectangleControl;
  FButtons := DesignedComponent('OptionsButtons') as TCastleVerticalGroup;
  Click('ButtonPhase1', {$ifdef FPC}@{$endif} ClickPhase1);
  Click('ButtonPhase2', {$ifdef FPC}@{$endif} ClickPhase2);
  Click('ButtonPrevMap', {$ifdef FPC}@{$endif} ClickPrevMap);
  Click('ButtonNextMap', {$ifdef FPC}@{$endif} ClickNextMap);
  FMapLabel := DesignedComponent('MapLabel') as TCastleLabel;
  Click('ButtonPrevSkill', {$ifdef FPC}@{$endif} ClickPrevSkill);
  Click('ButtonNextSkill', {$ifdef FPC}@{$endif} ClickNextSkill);
  FSkillLabel := DesignedComponent('SkillLabel') as TCastleLabel;
  { Volumes, the same settings as the F4 menu in the game. }
  Click('ButtonSfxDown', {$ifdef FPC}@{$endif} ClickSfxDown);
  Click('ButtonSfxUp', {$ifdef FPC}@{$endif} ClickSfxUp);
  FSfxLabel := DesignedComponent('SfxLabel') as TCastleLabel;
  Click('ButtonMusicDown', {$ifdef FPC}@{$endif} ClickMusicDown);
  Click('ButtonMusicUp', {$ifdef FPC}@{$endif} ClickMusicUp);
  FMusicLabel := DesignedComponent('MusicLabel') as TCastleLabel;
  UpdateVolumeLabels;
  { Video: field of view, UI scale, fullscreen (desktop; the page has its
    own button) and the render resolution (browser only). }
  Click('ButtonFovDown', {$ifdef FPC}@{$endif} ClickFovDown);
  Click('ButtonFovUp', {$ifdef FPC}@{$endif} ClickFovUp);
  FFovLabel := DesignedComponent('FovLabel') as TCastleLabel;
  Click('ButtonUiScaleDown', {$ifdef FPC}@{$endif} ClickUiScaleDown);
  Click('ButtonUiScaleUp', {$ifdef FPC}@{$endif} ClickUiScaleUp);
  FUiScaleLabel := DesignedComponent('UiScaleLabel') as TCastleLabel;
  Click('ButtonRenderScaleDown', {$ifdef FPC}@{$endif} ClickRenderScaleDown);
  Click('ButtonRenderScaleUp', {$ifdef FPC}@{$endif} ClickRenderScaleUp);
  FRenderScaleLabel := DesignedComponent('RenderScaleLabel') as TCastleLabel;
  FFullscreenButton := DesignedComponent('ButtonFullscreen') as TCastleButton;
  FFullscreenButton.OnClick := {$ifdef FPC}@{$endif} ClickFullscreen;
  { V-sync and the frame rate cap (desktop: the browser draws on its own
    refresh). }
  FVSyncButton := DesignedComponent('ButtonVSync') as TCastleButton;
  FVSyncButton.OnClick := {$ifdef FPC}@{$endif} ClickVSync;
  FDynamicLightsButton := DesignedComponent('ButtonDynamicLights') as TCastleButton;
  FDynamicLightsButton.OnClick := {$ifdef FPC}@{$endif} ClickDynamicLights;
  Click('ButtonFrameCapDown', {$ifdef FPC}@{$endif} ClickFrameCapDown);
  Click('ButtonFrameCapUp', {$ifdef FPC}@{$endif} ClickFrameCapUp);
  FFrameCapLabel := DesignedComponent('FrameCapLabel') as TCastleLabel;
  {$ifdef WASI}
  FFullscreenButton.Exists := false;
  (DesignedComponent('RowVideo3') as TCastleHorizontalGroup).Exists := false;
  {$else}
  (DesignedComponent('ButtonRenderScaleDown') as TCastleButton).Exists := false;
  (DesignedComponent('ButtonRenderScaleUp') as TCastleButton).Exists := false;
  FRenderScaleLabel.Exists := false;
  {$endif}
  UpdateVideoLabels;
  { Controls: key bindings (GameSettings.Keys). }
  Click('ButtonControls', {$ifdef FPC}@{$endif} ClickControls);
  Click('ButtonControlsBack', {$ifdef FPC}@{$endif} ClickControlsBack);
  Click('ButtonKeysDefaults', {$ifdef FPC}@{$endif} ClickKeysDefaults);
  Click('ButtonControlsPad', {$ifdef FPC}@{$endif} ClickControlsPad);
  Click('ButtonControlsPage', {$ifdef FPC}@{$endif} ClickControlsPage);
  FControls := DesignedComponent('ControlsPanel') as TCastleRectangleControl;
  FWaitSlot := -1;
  BuildControlsRows;
  Click('ButtonStart', {$ifdef FPC}@{$endif} ClickStart);
  Click('ButtonBack', {$ifdef FPC}@{$endif} ClickBack);
  { Your own WADs (desktop only: needs a native file dialog). }
  Click('ButtonOpenIwad', {$ifdef FPC}@{$endif} ClickOpenIwad);
  Click('ButtonAddPwad', {$ifdef FPC}@{$endif} ClickAddPwad);
  Click('ButtonLastWads', {$ifdef FPC}@{$endif} ClickLastWads);
  (DesignedComponent('ButtonLastWads') as TCastleButton).Exists := UserConfig.GetValue('wads/iwad', '') <> '';
  FContinueButton := DesignedComponent('ButtonContinue') as TCastleButton;
  FContinueButton.OnClick := {$ifdef FPC}@{$endif} ClickContinue;
  { Moving saves between computers / the web build (GameSaveBundle). }
  Click('ButtonExportSaves', {$ifdef FPC}@{$endif} ClickExportSaves);
  Click('ButtonImportSaves', {$ifdef FPC}@{$endif} ClickImportSaves);
  Click('ButtonRecordDemo', {$ifdef FPC}@{$endif} ClickRecordDemo);
  Click('ButtonPlayDemo', {$ifdef FPC}@{$endif} ClickPlayDemo);
  FWadsLabel := DesignedComponent('WadsLabel') as TCastleLabel;
  FStatus := DesignedComponent('StatusLabel') as TCastleLabel;
  UpdateSkillLabel;
  { Download progress of Freedoom Phase 2 (web), over the menu and Options. }
  FFetchLabel := DesignedComponent('FetchLabel') as TCastleLabel;

  if FNewGameRequested and (FWad <> nil) then
  begin
    { New Game from the in-game menu (before the command line, which would
      start its own map). Cannot change the view inside Start. }
    SetupDoomMenu;
    FDoomMenu.SetMenuActive(true);
    WaitForRenderAndCall({$ifdef FPC}@{$endif} StartRequestedNewGame);
    Exit;
  end;
  if CmdLoadSlot >= 0 then
  begin
    { Cannot change the view inside Start; do it after the first render. }
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoContinue);
    Exit;
  end;
  if AutoTestMap = 'MAPCOMPONENT' then
  begin
    { The design with the Doom map component (GameViewDesign); the view
      cannot change inside Start. }
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoDesign);
    Exit;
  end;
  if DemoPlayFile <> '' then
  begin
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoPlayDemo);
    Exit;
  end;
  if Copy(AutoTestMap, 1, 4) = 'MENU' then
  begin
    { -file PWADs too (a UMAPINFO's episodes in MENUEPISODE / MENUKEYS),
      and -iwad. }
    if CmdIwad <> '' then
      LoadWads(CmdIwad, CmdPwads)
    else if AutoTestMap = 'MENUDOOM2' then
      LoadWads(Freedoom2, CmdPwads)
    else
      LoadWads(Freedoom1, CmdPwads);
    AutoTestMenu;
    Exit;
  end;
  if (AutoTestMap <> '') or (CmdIwad <> '') or (CmdPwads.Count > 0) or (CmdWarp <> '') or CmdEdit then
  begin
    { Command line: explicit IWAD, or Freedoom matching the map names. }
    if CmdIwad <> '' then
      LoadWads(CmdIwad, CmdPwads)
    else if (Copy(AutoTestMap, 1, 3) = 'MAP') or (Copy(CmdWarp, 1, 3) = 'MAP') then
      LoadWads(Freedoom2, CmdPwads)
    else
      LoadWads(Freedoom1, CmdPwads);
    if FFetch <> nil then
    begin
      FFetchCommandLine := true;
      Exit;
    end;
    StartFromCommandLine;
    Exit;
  end;
  if FWad = nil then
    LoadWads(Freedoom1, nil)
  else
  begin
    { Back from a game: the menu is open already (no attract pages first). }
    SetupDoomMenu;
    FDoomMenu.SetMenuActive(true);
    UpdateMapLabel;
    UpdateWadsLabel;
    FMusic.Play(FMusic.TitleLump);
  end;
end;

procedure TViewMenu.RequestNewGame(const Episode, Skill: Integer);
begin
  FNewGameRequested := true;
  FNewGameEpisode := Episode;
  FNewGameSkill := Skill;
end;

procedure TViewMenu.StartRequestedNewGame(Sender: TObject);
begin
  FNewGameRequested := false;
  FDoomMenu.Episode := FNewGameEpisode;
  FDoomMenu.Skill := FNewGameSkill;
  DoomMenuAction(maNewGame);
end;

procedure TViewMenu.StartFromCommandLine;
begin
  begin
    if FWad = nil then Exit;
    if AutoTestMap <> '' then
      FMapIndex := Max(0, FWad.MapNames.IndexOf(AutoTestMap))
    else if CmdWarp <> '' then
      FMapIndex := Max(0, FWad.MapNames.IndexOf(CmdWarp));
    UpdateMapLabel;
    if (AutoTestMap <> '') or (CmdWarp <> '') or CmdEdit then
    begin
      { Cannot change the view inside Start; do it after the first render. }
      WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoStart);
      Exit;
    end;
    FMusic.Play(FMusic.TitleLump);
  end;
end;

procedure TViewMenu.MenuEditingChange(Sender: TObject);
begin
  if FDoomMenu.Editing then
    ShowTextKeyboard(FDoomMenu.EditText)
  else
    HideTextKeyboard;
end;

procedure TViewMenu.Stop;
begin
  HideTextKeyboard;
  { A download still running would replace the WAD under the game: drop
    it (choosing Phase 2 again starts it anew). }
  FreeAndNil(FFetch);
  FFetchSlot := -1;
  FFetchCommandLine := false;
  FFetchLabel := nil; { freed with the view's other controls }
  inherited;
end;

destructor TViewMenu.Destroy;
begin
  FreeAndNil(FFetchZip);
  FreeAndNil(FFetchPwads);
  FreeAndNil(FPwads);
  FreeAndNil(FMenuKeys);
  FreeAndNil(FStrings);
  inherited;
end;

function TViewMenu.NeedsFetch(const Iwad: String): Boolean;
begin
  { Android packages carry both Freedoom WADs. }
  {$ifdef ANDROID}
  Exit(false);
  {$endif}
  Result := (Iwad = Freedoom2) and (FFetchZip = nil) and
    ((WadBaseUrl <> '') or (UriExists(Freedoom2) <> ueFile));
end;

procedure TViewMenu.StartFetch(const Pwads: TStrings);
var
  Base: String;
begin
  FFetchPwads.Clear;
  if Pwads <> nil then FFetchPwads.Assign(Pwads);
  if FFetch <> nil then Exit; { already on its way }
  Base := WadBaseUrl;
  if Base = '' then Base := PageDirectoryUrl;
  if Base = '' then
  begin
    FWadsLabel.Caption := 'Freedoom Phase 2 (freedoom2.wad) is not installed';
    Exit;
  end;
  FFetch := TCastleDownload.Create(Self);
  FFetch.Url := Base + 'freedoom2.zip';
  FFetch.Options := [soForceMemoryStream];
  FFetch.OnFinish := {$ifdef FPC}@{$endif} FetchFinished;
  WritelnLog('WAD', 'Downloading %s', [FFetch.Url]);
  FFetch.Start;
  FFetchLabel.Exists := true;
end;

procedure TViewMenu.FetchFinished(const Sender: TCastleDownload; var FreeSender: Boolean);
var
  Slot: Integer;
begin
  FreeSender := true;
  FFetch := nil;
  if FFetchLabel <> nil then FFetchLabel.Exists := false;
  if Sender.Status <> dsSuccess then
  begin
    WritelnWarning('WAD', 'Cannot download %s: %s', [Sender.Url, Sender.ErrorMessage]);
    FWadsLabel.Caption := 'Could not download Freedoom Phase 2: ' + Sender.ErrorMessage;
    FFetchSlot := -1;
    FFetchCommandLine := false;
    Exit;
  end;
  WritelnLog('WAD', 'Downloaded %s (%d bytes)', [Sender.Url, Sender.Contents.Size]);
  Sender.OwnsContents := false;
  FFetchZip := TCastleZip.Create;
  FFetchZip.Open(Sender.Contents, true);
  FFetchZip.RegisterUrlProtocol('freedoom2-zip');
  LoadWads(Freedoom2, FFetchPwads);
  if FCustomOpen then
    ShowCustomPage;
  if FFetchSlot >= 0 then
  begin
    Slot := FFetchSlot;
    FFetchSlot := -1;
    ContinueFromSlot(Slot);
  end else
  if FFetchCommandLine then
  begin
    FFetchCommandLine := false;
    StartFromCommandLine;
  end;
end;

function TViewMenu.LoadWads(const Iwad: String; const Pwads: TStrings): Boolean;
var
  I: Integer;
  NewPwads: TStringList;
  ReadUrl: String;
begin
  Result := false;
  if NeedsFetch(Iwad) then
  begin
    StartFetch(Pwads);
    Exit;
  end;
  { The saves keep naming castle-data:/wads/freedoom2.wad; only reading
    goes to the downloaded copy. }
  ReadUrl := Iwad;
  if (Iwad = Freedoom2) and (FFetchZip <> nil) then
    ReadUrl := 'freedoom2-zip:/freedoom2.wad';
  NewPwads := TStringList.Create;
  try
    if Pwads <> nil then NewPwads.Assign(Pwads);
    if (FWad <> nil) and (FIwadUrl = Iwad) and (NewPwads.Text = FPwads.Text) then Exit(true);
    { Files picked in the browser are gone after a reload: say so instead
      of an exception (which would stop the web build). }
    if not WadUrlAvailable(Iwad) then
    begin
      FWadsLabel.Caption := Format('%s: choose the file again', [ExtractUriName(Iwad)]);
      WritelnWarning('WAD', '%s is not loaded any more', [Iwad]);
      Exit;
    end;
    for I := NewPwads.Count - 1 downto 0 do
      if not WadUrlAvailable(NewPwads[I]) then
      begin
        WritelnWarning('WAD', '%s is not loaded any more, left out', [NewPwads[I]]);
        NewPwads.Delete(I);
      end;
    { The play view may still reference the old objects; it is stopped when
      this view is active, so it is safe to replace them. }
    FreeAndNil(FMusic);
    FreeAndNil(FSounds);
    FreeAndNil(FGraphics);
    FreeAndNil(FWad);
    try
      FWad := TDoomWad.Create(ReadUrl);
      for I := 0 to NewPwads.Count - 1 do
        FWad.AddFile(NewPwads[I]);
      FGraphics := TDoomGraphics.Create(FWad);
      FSounds := TDoomSounds.Create(FWad);
      FMusic := TDoomMusic.Create(FWad);
      FSounds.Volume := SfxGain;
      FMusic.Volume := MusicGain;
      FMusic.Enabled := Settings.MusicOn;
    except
      on E: Exception do
      begin
        WritelnWarning('WAD', 'Cannot load WADs: %s', [E.Message]);
        FreeAndNil(FMusic);
        FreeAndNil(FSounds);
        FreeAndNil(FGraphics);
        FreeAndNil(FWad);
        if Iwad <> Freedoom1 then
        begin
          LoadWads(Freedoom1, nil);
          FWadsLabel.Caption := 'Could not load: ' + E.Message;
        end else
          raise;
        Exit;
      end;
    end;
    FIwadUrl := Iwad;
    FPwads.Assign(NewPwads);
    if (AutoTestMap = '') and (CmdWarp = '') then
      FMusic.Play(FMusic.TitleLump);
    FMapIndex := 0;
    SetupDoomMenu;
    UpdateMapLabel;
    UpdateWadsLabel;
    RememberWads;
    Result := true;
  finally
    FreeAndNil(NewPwads);
  end;
end;

{ Hand the current WAD to the Doom menu: episodes are offered for ExMy WADs
  that have both the map and its M_EPIn graphic (Doom 2 goes straight from
  New Game to the skill page). }
procedure TViewMenu.SetupDoomMenu;
var
  Episodes, E: Integer;
begin
  if (FDoomMenu = nil) or (FWad = nil) then Exit;
  Episodes := 0;
  for E := 1 to 4 do
    if (FWad.MapNames.IndexOf(Format('E%dM1', [E])) >= 0) and (FGraphics.Patch(Format('M_EPI%d', [E])) <> nil) then
      Episodes := E;
  FreeAndNil(FStrings);
  FStrings := TDoomStrings.Create(FWad);
  { UMAPINFO episodes join the menu (DoomMenu.SetupEpisodes). }
  LoadMapInfo(FWad);
  FDoomMenu.Setup(FGraphics, FSounds, Episodes, FStrings);
  FDoomMenu.Skill := FSkill;
  RefreshSlots;
end;

procedure TViewMenu.RefreshSlots;
var
  I: Integer;
  Save: TJSONObject;
begin
  if FDoomMenu = nil then Exit;
  for I := 1 to 6 do
  begin
    Save := ReadSaveFile(SaveSlotUrl(I));
    if Save <> nil then
      FDoomMenu.SetSlot(I, Save.Get('description', '?'))
    else
      FDoomMenu.SetSlot(I, '');
    FreeAndNil(Save);
  end;
  if FContinueButton <> nil then
  begin
    Save := ReadSaveFile(SaveSlotUrl(0));
    FContinueButton.Exists := Save <> nil;
    FreeAndNil(Save);
  end;
end;

{ Pwads without random maps (random:/SEED); the caller frees the list. }
function WithoutRandomPwads(const Pwads: TStrings): TStringList;
var
  I: Integer;
  Seed: Cardinal;
begin
  Result := TStringList.Create;
  for I := 0 to Pwads.Count - 1 do
    if not IsRandomWadUrl(Pwads[I], Seed) then
      Result.Add(Pwads[I]);
end;

{ New Game -> Random maps: the current WADs with a new seed's maps on top
  (instead of earlier random maps), from their first map. }
procedure TViewMenu.StartRandomGame;
var
  Pwads: TStringList;
begin
  Pwads := WithoutRandomPwads(FPwads);
  try
    Pwads.Add(RandomWadUrl(NewRandomSeed));
    if not LoadWads(FIwadUrl, Pwads) then Exit;
  finally
    FreeAndNil(Pwads);
  end;
  if FWad = nil then Exit;
  FMapIndex := Max(0, FWad.MapNames.IndexOf(RandomMapName(1, FWad.IsDoom2)));
  StartGame;
end;

{ The IWADs the custom game page goes through: both Freedoom phases and
  the last IWAD opened from a file. }
function CustomIwads: TStringList;
var
  Last: String;
begin
  Result := TStringList.Create;
  Result.Add(Freedoom1);
  Result.Add(Freedoom2);
  Last := UserConfig.GetValue('wads/iwad', '');
  if (Last <> '') and (Result.IndexOf(Last) < 0) then
    Result.Add(Last);
end;

const
  MaxRecentWads = 8;

{ A WAD set as one line: the IWAD and the PWADs, '|' between them. }
function WadSetText(const Iwad: String; const Pwads: TStrings): String;
var
  I: Integer;
begin
  Result := Iwad;
  for I := 0 to Pwads.Count - 1 do
    Result := Result + '|' + Pwads[I];
end;

{ The recent WAD sets (the user config's wads/recent0...), newest first. }
function RecentWadSets: TStringList;
var
  I: Integer;
  S: String;
begin
  Result := TStringList.Create;
  for I := 0 to MaxRecentWads - 1 do
  begin
    S := UserConfig.GetValue(Format('wads/recent%d', [I]), '');
    if S <> '' then Result.Add(S);
  end;
end;

procedure SaveRecentWadSets(const Sets: TStrings);
var
  I: Integer;
begin
  for I := 0 to MaxRecentWads - 1 do
    if I < Sets.Count then
      UserConfig.SetValue(Format('wads/recent%d', [I]), Sets[I])
    else
      UserConfig.DeleteValue(Format('wads/recent%d', [I]));
end;

{ "freedoom1.wad + a.wad + b.wad" of a WadSetText. }
function WadSetDescription(const SetText: String): String;
var
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '|';
    Parts.StrictDelimiter := true;
    Parts.DelimitedText := SetText;
    Result := '';
    for I := 0 to Parts.Count - 1 do
    begin
      if I > 0 then Result := Result + ' + ';
      Result := Result + ExtractUriName(Parts[I]);
    end;
  finally
    FreeAndNil(Parts);
  end;
end;

procedure TViewMenu.ShowCustomPage;
var
  Pwads, Recent: TStringList;
  I: Integer;
  S: String;
begin
  if (FDoomMenu = nil) or (FWad = nil) then Exit;
  if FPwadsOpen then
  begin
    ShowPwadsPage;
    Exit;
  end;
  FCustomOpen := true;
  if FDoomMenu.Page <> mpCustom then
  begin
    FDoomMenu.SetMenuActive(true);
    FDoomMenu.OpenPage(mpCustom);
  end;
  if FIwadUrl = Freedoom1 then
    FDoomMenu.CustomGame := 'Freedoom: Phase 1'
  else if FIwadUrl = Freedoom2 then
    FDoomMenu.CustomGame := 'Freedoom: Phase 2'
  else
    FDoomMenu.CustomGame := ExtractUriName(FIwadUrl);
  Pwads := WithoutRandomPwads(FPwads);
  try
    S := '';
    for I := 0 to Pwads.Count - 1 do
    begin
      if S <> '' then S := S + ' ';
      S := S + ExtractUriName(Pwads[I]);
    end;
  finally
    FreeAndNil(Pwads);
  end;
  if S = '' then S := 'none';
  if Length(S) > 22 then S := Copy(S, 1, 19) + '...';
  FDoomMenu.CustomPwads := S;
  Recent := RecentWadSets;
  try
    Pwads := WithoutRandomPwads(FPwads);
    try
      I := Recent.IndexOf(WadSetText(FIwadUrl, Pwads));
    finally
      FreeAndNil(Pwads);
    end;
    if Recent.Count = 0 then
      FDoomMenu.CustomRecent := 'none'
    else if I < 0 then
      FDoomMenu.CustomRecent := Format('-/%d', [Recent.Count])
    else
      FDoomMenu.CustomRecent := Format('%d/%d', [I + 1, Recent.Count]);
  finally
    FreeAndNil(Recent);
  end;
  if FWad.MapNames.Count > 0 then
  begin
    FMapIndex := Clamped(FMapIndex, 0, FWad.MapNames.Count - 1);
    FDoomMenu.CustomMap := Format('%s (%d/%d)', [FWad.MapNames[FMapIndex], FMapIndex + 1, FWad.MapNames.Count]);
  end else
    FDoomMenu.CustomMap := 'no maps';
  FDoomMenu.Refresh;
end;

procedure TViewMenu.ShowPwadsPage;
var
  Pwads: TStringList;
  I: Integer;
begin
  if (FDoomMenu = nil) or (FWad = nil) then Exit;
  FCustomOpen := true;
  FPwadsOpen := true;
  FDoomMenu.CustomPwadNames.Clear;
  Pwads := WithoutRandomPwads(FPwads);
  try
    for I := 0 to Pwads.Count - 1 do
      FDoomMenu.CustomPwadNames.Add(ExtractUriName(Pwads[I]));
  finally
    FreeAndNil(Pwads);
  end;
  FDoomMenu.SetMenuActive(true);
  FDoomMenu.OpenPage(mpPwads);
  FDoomMenu.Refresh;
end;

procedure TViewMenu.LoadPwads(const Pwads: TStrings);
var
  Names: String;
  I: Integer;
begin
  Names := '';
  for I := 0 to Pwads.Count - 1 do
  begin
    if Names <> '' then Names := Names + ', ';
    Names := Names + ExtractUriName(Pwads[I]);
  end;
  if Names = '' then Names := 'none';
  WritelnLog('Menu', 'PWADs: %s', [Names]);
  LoadWads(FIwadUrl, Pwads);
end;

procedure TViewMenu.CycleRecent(const Delta: Integer);
var
  Recent, Pwads, Parts: TStringList;
  I: Integer;
begin
  Recent := RecentWadSets;
  Parts := TStringList.Create;
  Pwads := WithoutRandomPwads(FPwads);
  try
    if Recent.Count = 0 then
    begin
      FWadsLabel.Caption := 'No recent WADs yet (PWADs or your own IWAD are remembered)';
      Exit;
    end;
    I := Recent.IndexOf(WadSetText(FIwadUrl, Pwads));
    if I < 0 then
    begin
      if Delta > 0 then I := 0 else I := Recent.Count - 1;
    end else
      I := (I + Delta + Recent.Count) mod Recent.Count;
    Parts.Delimiter := '|';
    Parts.StrictDelimiter := true;
    Parts.DelimitedText := Recent[I];
    WritelnLog('Menu', 'Recent WADs %d/%d: %s', [I + 1, Recent.Count, WadSetDescription(Recent[I])]);
    Pwads.Clear;
    while Parts.Count > 1 do
    begin
      Pwads.Add(Parts[1]);
      Parts.Delete(1);
    end;
    FMapIndex := 0;
    LoadWads(Parts[0], Pwads);
  finally
    FreeAndNil(Parts);
    FreeAndNil(Pwads);
    FreeAndNil(Recent);
  end;
end;

procedure TViewMenu.CustomGameAction;
var
  Item, MapName: String;
  Iwads, Pwads: TStringList;
  I: Integer;
  Seed: Int64;
begin
  if FWad = nil then Exit;
  Item := FDoomMenu.CustomItem;
  { Reloading WADs sets the menu up again with FSkill. }
  FSkill := FDoomMenu.Skill;
  UpdateSkillLabel;
  if Item = 'GAME' then
  begin
    Iwads := CustomIwads;
    try
      I := Iwads.IndexOf(FIwadUrl);
      I := (I + FDoomMenu.CustomDelta + Iwads.Count) mod Iwads.Count;
      FMapIndex := 0;
      { Another game: its PWADs would not fit. }
      LoadWads(Iwads[I], nil);
    finally
      FreeAndNil(Iwads);
    end;
  end else
  if Item = 'OPEN' then
    FPwadsOpen := false
  else if Item = 'OPENIWAD' then
    ClickOpenIwad(nil)
  else if Item = 'PWADS' then
  begin
    ShowPwadsPage;
    Exit;
  end else
  if Item = 'RECENT' then
    CycleRecent(FDoomMenu.CustomDelta)
  else if (Item = 'PWADMOVE') or (Item = 'PWADREMOVE') then
  begin
    Pwads := WithoutRandomPwads(FPwads);
    try
      I := FDoomMenu.CustomIndex;
      if (I >= 0) and (I < Pwads.Count) then
      begin
        if Item = 'PWADREMOVE' then
        begin
          WritelnLog('Menu', 'PWADs: %s removed', [ExtractUriName(Pwads[I])]);
          Pwads.Delete(I);
        end else
        if (I + FDoomMenu.CustomDelta >= 0) and (I + FDoomMenu.CustomDelta < Pwads.Count) then
          Pwads.Exchange(I, I + FDoomMenu.CustomDelta);
        LoadPwads(Pwads);
      end;
    finally
      FreeAndNil(Pwads);
    end;
  end else
  if Item = 'PWADADD' then
    ClickAddPwad(nil)
  else if Item = 'CLEAR' then
    LoadWads(FIwadUrl, nil)
  else if Item = 'MAP' then
  begin
    if FDoomMenu.CustomDelta < 0 then ClickPrevMap(nil) else ClickNextMap(nil);
  end else
  if (Item = 'START') or (Item = 'EDIT') then
  begin
    MapName := '';
    if FWad.MapNames.Count > 0 then
      MapName := FWad.MapNames[Clamped(FMapIndex, 0, FWad.MapNames.Count - 1)];
    Seed := StrToInt64Def(FDoomMenu.CustomSeed, -1);
    WritelnLog('Menu', 'Custom game%s: %s, PWADs %s, map %s, skill %d, random seed %s', [
      Iff(Item = 'EDIT', ' (map editor)', ''), ExtractUriName(FIwadUrl), FDoomMenu.CustomPwads, MapName, FDoomMenu.Skill + 1,
      Iff(Seed >= 0, IntToStr(Seed), 'none')]);
    Pwads := WithoutRandomPwads(FPwads);
    try
      if Seed >= 0 then
        Pwads.Add(RandomWadUrl(Cardinal(Seed)));
      if not LoadWads(FIwadUrl, Pwads) then Exit;
    finally
      FreeAndNil(Pwads);
    end;
    if FWad = nil then Exit;
    FMapIndex := Max(0, FWad.MapNames.IndexOf(MapName));
    FCustomOpen := false;
    if Item = 'EDIT' then StartEditor else StartGame;
    Exit;
  end;
  ShowCustomPage;
end;

procedure TViewMenu.DoomMenuAction(const Action: TDoomMenuAction);
var
  MapName: String;
  I: Integer;
  Plain: TStringList;
begin
  if Action <> maCustom then
  begin
    FCustomOpen := false;
    FPwadsOpen := false;
  end;
  case Action of
    maNewGame:
      begin
        FSkill := FDoomMenu.Skill;
        UpdateSkillLabel;
        { G_DeferedInitNew: the chosen episode's first map (ExM1, or a
          UMAPINFO episode's), else MAP01. }
        MapName := FDoomMenu.EpisodeMap;
        if MapName = RandomEpisodeMap then
        begin
          StartRandomGame;
          Exit;
        end;
        { Another episode: without random maps loaded before. }
        Plain := WithoutRandomPwads(FPwads);
        try
          if (Plain.Count <> FPwads.Count) and not LoadWads(FIwadUrl, Plain) then Exit;
        finally
          FreeAndNil(Plain);
        end;
        if MapName = '' then
          MapName := 'MAP01';
        I := FWad.MapNames.IndexOf(MapName);
        if I < 0 then I := 0;
        FMapIndex := I;
        StartGame;
      end;
    maLoadSlot: ContinueFromSlot(FDoomMenu.Slot);
    maCustom: CustomGameAction;
    maOptions: ShowOptions(true);
    maQuit: Application.Terminate;
  end;
end;

procedure TViewMenu.ShowOptions(const Value: Boolean);
begin
  FOptions.Exists := Value;
  FDoomMenu.Exists := not Value;
  if Value then
  begin
    UpdateMapLabel;
    UpdateSkillLabel;
    UpdateWadsLabel;
  end;
end;

procedure TViewMenu.ClickBack(Sender: TObject);
begin
  ShowOptions(false);
end;

procedure TViewMenu.UpdateWadsLabel;
begin
  if FWadsLabel = nil then Exit;
  if FWad <> nil then
    FWadsLabel.Caption := 'Loaded: ' + FWad.Description
  else
    FWadsLabel.Caption := '';
end;

procedure TViewMenu.RememberWads;
var
  Pwads, Recent: TStringList;
  SetText: String;
  I: Integer;
begin
  { Only remember user files, not the bundled Freedoom. }
  if (FIwadUrl <> Freedoom1) and (FIwadUrl <> Freedoom2) or (FPwads.Count > 0) then
  begin
    UserConfig.SetValue('wads/iwad', FIwadUrl);
    UserConfig.SetValue('wads/pwads', FPwads.DelimitedText);
    { The recent sets (the custom page's RECENT): newest first, without
      random maps; files picked in the browser are gone after a reload. }
    Pwads := WithoutRandomPwads(FPwads);
    Recent := RecentWadSets;
    try
      if ((FIwadUrl <> Freedoom1) and (FIwadUrl <> Freedoom2) or (Pwads.Count > 0)) and
         not IsUploadUrl(FIwadUrl) then
      begin
        for I := Pwads.Count - 1 downto 0 do
          if IsUploadUrl(Pwads[I]) then Pwads.Delete(I);
        SetText := WadSetText(FIwadUrl, Pwads);
        I := Recent.IndexOf(SetText);
        if I >= 0 then Recent.Delete(I);
        Recent.Insert(0, SetText);
        while Recent.Count > MaxRecentWads do Recent.Delete(Recent.Count - 1);
        SaveRecentWadSets(Recent);
      end;
    finally
      FreeAndNil(Recent);
      FreeAndNil(Pwads);
    end;
    UserConfig.Save;
  end;
end;

const
  {$ifdef ANDROID}
  NoDialogInBrowser = 'File dialogs are not available on Android';
  {$else}
  NoDialogInBrowser = 'In the browser, export and import saves on the Castle DOOM home page ("Your saves")';
  {$endif}
  NoDemoDialog = 'Demos need the desktop version (file dialogs)';

procedure TViewMenu.ClickExportSaves(Sender: TObject);
var
  Url: String;
  Count: Integer;
begin
  Url := 'castle-doom-saves.json';
  if Application.MainWindow.FileDialog('Export saves', Url, false,
      'Castle DOOM saves (*.json)|*.json|All files (*)|*') then
  begin
    StringToFile(Url, ExportSaveBundle(Count));
    FWadsLabel.Caption := Format('Exported %d files to %s', [Count, UriDisplay(Url)]);
  end else
    FWadsLabel.Caption := NoDialogInBrowser;
end;

{ Record demo...: the next game started (New Game, a loaded game) is
  recorded to the chosen file, level after level. }
procedure TViewMenu.ClickRecordDemo(Sender: TObject);
var
  Url: String;
begin
  {$ifdef WASI}
  { No save dialog: the recording stays in the browser (Play demo... ->
    the last one) and downloads when the game ends. }
  DemoRecordFile := LastDemoUrl;
  FWadsLabel.Caption := 'The next game is recorded; it downloads when the game ends';
  Exit;
  {$endif}
  Url := 'castle-doom.cdemo';
  if Application.MainWindow.FileDialog('Record a demo of the next game', Url, false,
      'Castle DOOM demos (*.cdemo)|*.cdemo|All files (*)|*') then
  begin
    DemoRecordFile := UriToFilenameSafe(Url);
    FWadsLabel.Caption := 'The next game is recorded to ' + UriDisplay(Url);
  end else
    FWadsLabel.Caption := NoDemoDialog;
end;

procedure TViewMenu.ClickPlayDemo(Sender: TObject);
var
  Url: String;
begin
  {$ifdef WASI}
  PickBrowserFile('demo');
  Exit;
  {$endif}
  Url := '';
  if Application.MainWindow.FileDialog('Play a demo', Url, true,
      'Castle DOOM demos (*.cdemo)|*.cdemo|All files (*)|*') then
  begin
    DemoPlayFile := UriToFilenameSafe(Url);
    AutoPlayDemo(nil);
  end else
    FWadsLabel.Caption := NoDemoDialog;
end;

procedure TViewMenu.ClickImportSaves(Sender: TObject);
var
  Url: String;
  Count: Integer;
begin
  Url := '';
  if Application.MainWindow.FileDialog('Import saves', Url, true,
      'Castle DOOM saves (*.json)|*.json|All files (*)|*') then
  begin
    if ImportSaveBundle(FileToString(Url), Count) then
    begin
      FWadsLabel.Caption := Format('Imported %d files from %s', [Count, UriDisplay(Url)]);
      { The settings may have come along. }
      LoadSettings;
      UpdateVolumeLabels;
      UpdateVideoLabels;
      ApplyWindowSettings;
      if FSounds <> nil then FSounds.Volume := SfxGain;
      if FMusic <> nil then FMusic.Volume := MusicGain;
    end else
      FWadsLabel.Caption := UriDisplay(Url) + ' is not a Castle DOOM save bundle';
  end else
    FWadsLabel.Caption := NoDialogInBrowser;
end;

procedure TViewMenu.ClickOpenIwad(Sender: TObject);
var
  Url: String;
begin
  Url := UserConfig.GetValue('wads/iwad', '');
  {$ifdef WASI}
  PickBrowserFile('iwad');
  Exit;
  {$endif}
  if Application.MainWindow.FileDialog('Open Doom IWAD', Url, true,
      'Doom WAD files (*.wad)|*.wad|All files (*)|*') then
    UseFile(Url, true)
  else
    FWadsLabel.Caption := 'No file chosen';
end;

procedure TViewMenu.ClickAddPwad(Sender: TObject);
var
  Url: String;
  Pwads: TStringList;
begin
  {$ifdef WASI}
  PickBrowserFile('pwad');
  Exit;
  {$endif}
  Url := UserConfig.GetValue('wads/lastpwad', '');
  if Application.MainWindow.FileDialog('Add Doom PWAD (-file)', Url, true,
      'Doom WAD files (*.wad)|*.wad|All files (*)|*') then
  begin
    UserConfig.SetValue('wads/lastpwad', Url);
    UseFile(Url, false);
  end else
    FWadsLabel.Caption := 'No file chosen';
end;

{ An IWAD (another game: its PWADs would not fit) or one more PWAD from a
  file the user chose; the custom page shows the result. }
procedure TViewMenu.UseFile(const Url: String; const Iwad: Boolean);
var
  Pwads: TStringList;
begin
  WritelnLog('Menu', 'Chosen %s: %s', [Iff(Iwad, 'IWAD', 'PWAD'), Url]);
  if Iwad then
  begin
    FMapIndex := 0;
    LoadWads(Url, nil);
  end else
  begin
    Pwads := TStringList.Create;
    try
      Pwads.Assign(FPwads);
      Pwads.Add(Url);
      LoadWads(FIwadUrl, Pwads);
    finally
      FreeAndNil(Pwads);
    end;
  end;
  if FCustomOpen then ShowCustomPage;
end;

{$ifdef WASI}
{ A JavaScript function of this name exists on the window (the patched
  page's, tools/patch_web_page.py). }
function PageHasFunction(const Name: String): Boolean;
var
  V: TJOB_JSValue;
begin
  V := JSWindow.ReadJSPropertyValue(Name);
  Result := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
end;

{ A string the page returns ('' for its null). }
function PageString(const Name: String): UnicodeString;
var
  V: TJOB_JSValue;
begin
  Result := '';
  V := JSWindow.InvokeJSValueResult(Name, []);
  try
    if V is TJOB_String then Result := TJOB_String(V).Value;
  finally
    FreeAndNil(V);
  end;
end;
{$endif}

procedure TViewMenu.PickBrowserFile(const Kind: String);
begin
  {$ifdef WASI}
  if not PageHasFunction('castleDoomOpenFile') then
  begin
    FWadsLabel.Caption := 'This page cannot open files';
    Exit;
  end;
  JSWindow.InvokeJSNoResult('castleDoomOpenFile', [UTF8Decode(Kind)]);
  if Kind = 'demo' then
    FWadsLabel.Caption := 'Choose a demo (.cdemo)...'
  else
    FWadsLabel.Caption := 'Choose a WAD file...';
  {$endif}
end;

{ The page's file picker gives the chosen file as its kind and name, then
  its bytes as a "binary string" (one character per byte). }
procedure TViewMenu.PollPickedFile;
{$ifdef WASI}
var
  Head, Bytes: UnicodeString;
  Kind, PickedName: String;
  P: Integer;
  Data: TMemoryStream;
  B: Byte;
{$endif}
begin
  {$ifdef WASI}
  if not PageHasFunction('castleDoomTakeFile') then Exit;
  Head := PageString('castleDoomTakeFile');
  if Head = '' then Exit;
  P := Pos('|', Head);
  Kind := UTF8Encode(Copy(Head, 1, P - 1));
  PickedName := UTF8Encode(Copy(Head, P + 1, MaxInt));
  Bytes := PageString('castleDoomTakeFileBytes');
  Data := TMemoryStream.Create;
  try
    Data.Size := Length(Bytes);
    for P := 1 to Length(Bytes) do
    begin
      B := Ord(Bytes[P]) and $FF;
      PByte(Data.Memory)[P - 1] := B;
    end;
    if Kind = 'demo' then
    begin
      DemoPlayFile := RegisterUpload(PickedName, Data);
      AutoPlayDemo(nil);
    end else
      UseFile(RegisterUpload(PickedName, Data), Kind = 'iwad');
  finally
    FreeAndNil(Data);
  end;
  {$endif}
end;

procedure TViewMenu.ClickContinue(Sender: TObject);
begin
  ContinueFromSlot(0);
end;

procedure TViewMenu.AutoContinue(Sender: TObject);
var
  Slot: Integer;
begin
  Slot := CmdLoadSlot;
  CmdLoadSlot := -1;
  ContinueFromSlot(Slot);
end;

{ Load a saved game: first its WADs, then the play view restores the level. }
procedure TViewMenu.ContinueFromSlot(const Slot: Integer);
var
  Save: TJSONObject;
  D: TJSONData;
  Pwads: TStringList;
  Iwad: String;
  I: Integer;
begin
  Save := ReadSaveFile(SaveSlotUrl(Slot));
  if Save = nil then
  begin
    FWadsLabel.Caption := 'No saved game in that slot';
    Exit;
  end;
  Pwads := TStringList.Create;
  try
    Iwad := Freedoom1;
    D := Save.Find('wads');
    if (D is TJSONArray) and (TJSONArray(D).Count > 0) then
    begin
      Iwad := TJSONArray(D).Strings[0];
      for I := 1 to TJSONArray(D).Count - 1 do
        Pwads.Add(TJSONArray(D).Strings[I]);
    end;
    if not LoadWads(Iwad, Pwads) then
    begin
      { Freedoom Phase 2 first: continue when it has arrived. }
      if FFetch <> nil then FFetchSlot := Slot;
      Exit;
    end;
  finally
    FreeAndNil(Pwads);
    FreeAndNil(Save);
  end;
  if FWad = nil then Exit;
  ViewPlay.PendingSaveUrl := SaveSlotUrl(Slot);
  StartGame;
end;

procedure TViewMenu.ClickLastWads(Sender: TObject);
var
  Pwads: TStringList;
begin
  Pwads := TStringList.Create;
  try
    Pwads.DelimitedText := UserConfig.GetValue('wads/pwads', '');
    LoadWads(UserConfig.GetValue('wads/iwad', Freedoom1), Pwads);
  finally
    FreeAndNil(Pwads);
  end;
end;

procedure TViewMenu.UpdateMapLabel;
begin
  if FMapLabel = nil then Exit;
  if (FWad <> nil) and (FWad.MapNames.Count > 0) then
  begin
    FMapIndex := Clamped(FMapIndex, 0, FWad.MapNames.Count - 1);
    FMapLabel.Caption := Format('  %s  (%d/%d)  ', [FWad.MapNames[FMapIndex], FMapIndex + 1, FWad.MapNames.Count]);
  end else
    FMapLabel.Caption := '  no maps  ';
end;

procedure TViewMenu.UpdateSkillLabel;
begin
  if FSkillLabel <> nil then
    FSkillLabel.Caption := Format('  Skill %d: %s  ', [FSkill + 1, SkillNames[FSkill]]);
end;

procedure TViewMenu.ClickPhase1(Sender: TObject);
begin
  LoadWads(Freedoom1, nil);
end;

procedure TViewMenu.ClickPhase2(Sender: TObject);
begin
  LoadWads(Freedoom2, nil);
end;

procedure TViewMenu.ClickPrevMap(Sender: TObject);
begin
  if FWad = nil then Exit;
  Dec(FMapIndex);
  if FMapIndex < 0 then FMapIndex := FWad.MapNames.Count - 1;
  UpdateMapLabel;
end;

procedure TViewMenu.ClickNextMap(Sender: TObject);
begin
  if FWad = nil then Exit;
  Inc(FMapIndex);
  if FMapIndex >= FWad.MapNames.Count then FMapIndex := 0;
  UpdateMapLabel;
end;

procedure TViewMenu.ClickPrevSkill(Sender: TObject);
begin
  FSkill := (FSkill + 4) mod 5;
  FDoomMenu.Skill := FSkill;
  UpdateSkillLabel;
end;

procedure TViewMenu.UpdateVolumeLabels;
begin
  FSfxLabel.Caption := Format('Sound volume %d', [Settings.SfxVolume]);
  FMusicLabel.Caption := Format('Music volume %d', [Settings.MusicVolume]);
end;

procedure TViewMenu.UpdateVideoLabels;
begin
  FFovLabel.Caption := Format('Field of view %d', [Settings.FieldOfView]);
  FUiScaleLabel.Caption := Format('UI scale %d%%', [Settings.UiScale]);
  FRenderScaleLabel.Caption := Format('Resolution %d%%', [Settings.RenderScale]);
  FFullscreenButton.Caption := 'Fullscreen: ' + BoolToStr(Settings.Fullscreen, 'on', 'off');
  FVSyncButton.Caption := 'V-sync: ' + BoolToStr(Settings.VSync, 'on', 'off');
  FDynamicLightsButton.Caption := 'Dynamic lights: ' + BoolToStr(Settings.DynamicLights, 'on', 'off');
  if Settings.FrameCap > 0 then
    FFrameCapLabel.Caption := Format('Frame rate cap %d', [Settings.FrameCap])
  else
    FFrameCapLabel.Caption := 'No frame rate cap';
end;

procedure TViewMenu.ChangeVideo(const Which, Delta: Integer);
begin
  case Which of
    0: Settings.FieldOfView := Clamped(Settings.FieldOfView + 5 * Delta, MinFieldOfView, MaxFieldOfView);
    1: Settings.UiScale := Clamped(Settings.UiScale + 10 * Delta, MinUiScale, MaxUiScale);
    2: Settings.RenderScale := Clamped(Settings.RenderScale + 25 * Delta, MinRenderScale, MaxRenderScale);
  end;
  SaveSettings;
  ApplyWindowSettings;
  UpdateVideoLabels;
  WritelnLog('Settings', VideoSummary);
end;

procedure TViewMenu.ClickFovDown(Sender: TObject);
begin
  ChangeVideo(0, -1);
end;

procedure TViewMenu.ClickFovUp(Sender: TObject);
begin
  ChangeVideo(0, 1);
end;

procedure TViewMenu.ClickUiScaleDown(Sender: TObject);
begin
  ChangeVideo(1, -1);
end;

procedure TViewMenu.ClickUiScaleUp(Sender: TObject);
begin
  ChangeVideo(1, 1);
end;

procedure TViewMenu.ClickRenderScaleDown(Sender: TObject);
begin
  ChangeVideo(2, -1);
end;

procedure TViewMenu.ClickRenderScaleUp(Sender: TObject);
begin
  ChangeVideo(2, 1);
end;

procedure TViewMenu.ClickDynamicLights(Sender: TObject);
begin
  Settings.DynamicLights := not Settings.DynamicLights;
  SaveSettings;
  WritelnLog('Settings', 'Dynamic lights %s', [BoolToStr(Settings.DynamicLights, 'on', 'off')]);
  UpdateVideoLabels;
end;

procedure TViewMenu.ClickVSync(Sender: TObject);
begin
  Settings.VSync := not Settings.VSync;
  ChangeVideo(-1, 0);
end;

procedure TViewMenu.ClickFrameCapDown(Sender: TObject);
begin
  Settings.FrameCap := NextFrameCap(Settings.FrameCap, -1);
  ChangeVideo(-1, 0);
end;

procedure TViewMenu.ClickFrameCapUp(Sender: TObject);
begin
  Settings.FrameCap := NextFrameCap(Settings.FrameCap, 1);
  ChangeVideo(-1, 0);
end;

procedure TViewMenu.ClickFullscreen(Sender: TObject);
begin
  Settings.Fullscreen := not Settings.Fullscreen;
  ChangeVideo(-1, 0);
end;

procedure TViewMenu.BuildControlsRows;
var
  List: TCastleVerticalGroup;
  Row: TCastleHorizontalGroup;
  Lab: TCastleLabel;
  B: TCastleButton;
  A: TGameAction;
  P: TPadAction;
  I, Page: Integer;
begin
  List := DesignedComponent('ControlsList') as TCastleVerticalGroup;
  for Page := 0 to ControlsPageCount - 1 do
  begin
    FControlsPageGroups[Page] := TCastleVerticalGroup.Create(FreeAtStop);
    FControlsPageGroups[Page].Spacing := List.Spacing;
    FControlsPageGroups[Page].Alignment := List.Alignment;
    List.InsertFront(FControlsPageGroups[Page]);
  end;
  for A := Low(TGameAction) to High(TGameAction) do
  begin
    Row := TCastleHorizontalGroup.Create(FreeAtStop);
    Row.Spacing := 10;
    Lab := TCastleLabel.Create(FreeAtStop);
    Lab.Caption := ActionNames[A];
    Lab.FontSize := 22;
    Lab.Color := White;
    Row.InsertFront(Lab);
    for I := 0 to 1 do
    begin
      B := TCastleButton.Create(FreeAtStop);
      B.FontSize := 22;
      B.AutoSizeWidth := false;
      B.Width := 200;
      B.Tag := Ord(A) * 2 + I;
      B.OnClick := {$ifdef FPC}@{$endif} ClickKeyButton;
      FKeyButtons[A, I] := B;
      Row.InsertFront(B);
    end;
    B := TCastleButton.Create(FreeAtStop);
    B.FontSize := 22;
    B.AutoSizeWidth := false;
    B.Width := 200;
    B.Tag := Ord(A);
    B.OnClick := {$ifdef FPC}@{$endif} ClickMouseButton;
    FMouseButtons[A] := B;
    Row.InsertFront(B);
    for Page := 0 to ControlsPageCount - 1 do
      if (A >= ControlsPageFirst[Page]) and (A <= ControlsPageLast[Page]) then
        FControlsPageGroups[Page].InsertFront(Row);
  end;
  List := DesignedComponent('PadList') as TCastleVerticalGroup;
  for P := Low(TPadAction) to High(TPadAction) do
  begin
    Row := TCastleHorizontalGroup.Create(FreeAtStop);
    Row.Spacing := 10;
    Lab := TCastleLabel.Create(FreeAtStop);
    Lab.Caption := PadActionNames[P];
    Lab.FontSize := 22;
    Lab.Color := White;
    Row.InsertFront(Lab);
    for I := 0 to 1 do
    begin
      B := TCastleButton.Create(FreeAtStop);
      B.FontSize := 22;
      B.AutoSizeWidth := false;
      B.Width := 200;
      B.Tag := Ord(P) * 2 + I;
      B.OnClick := {$ifdef FPC}@{$endif} ClickPadButton;
      FPadButtons[P, I] := B;
      Row.InsertFront(B);
    end;
    List.InsertFront(Row);
  end;
  List := DesignedComponent('TouchList') as TCastleVerticalGroup;
  for I := 0 to 3 do
  begin
    Row := TCastleHorizontalGroup.Create(FreeAtStop);
    Row.Spacing := 10;
    Lab := TCastleLabel.Create(FreeAtStop);
    case I of
      0: Lab.Caption := 'Layout';
      1: Lab.Caption := 'Size';
      2: Lab.Caption := 'Opacity';
      else Lab.Caption := 'Button places';
    end;
    Lab.FontSize := 22;
    Lab.Color := White;
    Row.InsertFront(Lab);
    B := TCastleButton.Create(FreeAtStop);
    B.FontSize := 22;
    B.AutoSizeWidth := false;
    B.Width := 300;
    case I of
      0: begin B.OnClick := {$ifdef FPC}@{$endif} ClickTouchHand; FTouchHandButton := B; end;
      1: begin B.OnClick := {$ifdef FPC}@{$endif} ClickTouchSize; FTouchSizeButton := B; end;
      2: begin B.OnClick := {$ifdef FPC}@{$endif} ClickTouchOpacity; FTouchOpacityButton := B; end;
      else begin B.OnClick := {$ifdef FPC}@{$endif} ClickTouchEdit; B.Caption := 'Edit...'; end;
    end;
    Row.InsertFront(B);
    if I = 3 then
    begin
      B := TCastleButton.Create(FreeAtStop);
      B.FontSize := 22;
      B.Caption := 'Reset';
      B.OnClick := {$ifdef FPC}@{$endif} ClickTouchResetPlaces;
      Row.InsertFront(B);
    end;
    List.InsertFront(Row);
  end;
  UpdateKeyButtons;
end;

procedure TViewMenu.UpdateKeyButtons;
var
  A: TGameAction;
  P: TPadAction;
  I: Integer;
begin
  for A := Low(TGameAction) to High(TGameAction) do
    for I := 0 to 1 do
      if (not FPadMode) and (FWaitSlot = I) and (FWaitAction = A) then
        FKeyButtons[A, I].Caption := 'press a key...'
      else
        FKeyButtons[A, I].Caption := KeyName(Settings.Keys[A, I]);
  for A := Low(TGameAction) to High(TGameAction) do
    if (not FPadMode) and (FWaitSlot = 2) and (FWaitAction = A) then
      FMouseButtons[A].Caption := 'click...'
    else
      FMouseButtons[A].Caption := MouseBindNames[Settings.Mouse[A]];
  for P := Low(TPadAction) to High(TPadAction) do
    for I := 0 to 1 do
      if FPadMode and (FWaitSlot = I) and (FWaitPadAction = P) then
        FPadButtons[P, I].Caption := 'press a button...'
      else
        FPadButtons[P, I].Caption := PadButtonNames[Settings.Pad[P, I]];
  if FTouchHandButton <> nil then
  begin
    FTouchHandButton.Caption := BoolToStr(Settings.TouchLeftHanded, 'Left-handed', 'Right-handed');
    FTouchSizeButton.Caption := IntToStr(Settings.TouchSize) + '%';
    FTouchOpacityButton.Caption := IntToStr(Settings.TouchOpacity) + '%';
  end;
end;

procedure TViewMenu.ShowControlsMode;
var
  Page: Integer;
  PageButton: TCastleButton;
  Header, Hint: TCastleLabel;
  KeysShown: Boolean;
begin
  KeysShown := not (FPadMode or FTouchMode);
  (DesignedComponent('ControlsList') as TCastleUserInterface).Exists := KeysShown;
  (DesignedComponent('PadList') as TCastleUserInterface).Exists := FPadMode;
  (DesignedComponent('TouchList') as TCastleUserInterface).Exists := FTouchMode;
  for Page := 0 to ControlsPageCount - 1 do
    FControlsPageGroups[Page].Exists := Page = FControlsPage;
  PageButton := DesignedComponent('ButtonControlsPage') as TCastleButton;
  PageButton.Exists := KeysShown;
  PageButton.Caption := ControlsPageNames[(FControlsPage + 1) mod ControlsPageCount] + ' >';
  Header := DesignedComponent('ControlsHeader') as TCastleLabel;
  Hint := DesignedComponent('ControlsHint') as TCastleLabel;
  { The mode button names the next mode: keyboard, gamepad, touch. }
  if FPadMode then
  begin
    Header.Caption := 'Controls: Gamepad';
    Hint.Caption := 'Click an action, then press the gamepad button (Backspace clears it, Esc or Start cancels)';
    (DesignedComponent('ButtonControlsPad') as TCastleButton).Caption := 'Touch';
  end else
  if FTouchMode then
  begin
    Header.Caption := 'Controls: Touch';
    Hint.Caption := 'The touch controls show on touch screens (desktop: --touch)';
    (DesignedComponent('ButtonControlsPad') as TCastleButton).Caption := 'Keyboard';
  end else
  begin
    Header.Caption := 'Controls: ' + ControlsPageNames[FControlsPage];
    Hint.Caption := 'Click a key or mouse slot, then press the new key or mouse button (Backspace clears, Esc cancels)';
    (DesignedComponent('ButtonControlsPad') as TCastleButton).Caption := 'Gamepad';
  end;
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickTouchHand(Sender: TObject);
begin
  Settings.TouchLeftHanded := not Settings.TouchLeftHanded;
  SaveSettings;
  WritelnLog('Settings', TouchSummary);
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickTouchOpacity(Sender: TObject);
begin
  Settings.TouchOpacity := NextTouchOpacity(Settings.TouchOpacity);
  SaveSettings;
  WritelnLog('Settings', TouchSummary);
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickTouchResetPlaces(Sender: TObject);
begin
  ResetTouchPlaces;
  SaveSettings;
  WritelnLog('Settings', TouchSummary);
end;

procedure TViewMenu.ClickTouchEdit(Sender: TObject);
begin
  ShowTouchEditor(true);
end;

procedure TViewMenu.ClickTouchEditDone(Sender: TObject);
begin
  ShowTouchEditor(false);
end;

procedure TViewMenu.TouchButtonMoved(const Button: TTouchButton; const Position: TVector2);
begin
  Settings.TouchPlaces[Ord(Button) - 1] := Position;
  SaveSettings;
  WritelnLog('Settings', TouchSummary);
end;

procedure TViewMenu.DragTouchFire;
var
  Middle: TVector2;
  Radius: Single;
  R: TFloatRectangle;
begin
  R := FTouchEditControls.RenderRect;
  FTouchEditControls.ButtonCircle(tbFire, Middle, Radius);
  FTouchEditControls.TouchDown(1, Middle + Vector2(10, 10));
  FTouchEditControls.TouchMove(1, Vector2(R.Width * 0.5, R.Height * 0.5) + Vector2(10, 10));
  FTouchEditControls.TouchUp(1);
end;

procedure TViewMenu.ShowTouchEditor(const Show: Boolean);
var
  Hint: TCastleLabel;
  Done: TCastleButton;
  I: Integer;
begin
  if FTouchEditor = nil then
  begin
    FTouchEditor := TCastleRectangleControl.Create(FreeAtStop);
    FTouchEditor.Name := 'TouchEditor';
    FTouchEditor.FullSize := true;
    FTouchEditor.Color := Vector4(0.08, 0.02, 0.02, 1);
    FTouchEditControls := TDoomTouchControls.Create(FreeAtStop);
    FTouchEditControls.Name := 'TouchEditControls';
    FTouchEditControls.Graphics := FGraphics;
    FTouchEditControls.Editing := true;
    FTouchEditControls.OnButtonMoved := {$ifdef FPC}@{$endif} TouchButtonMoved;
    FTouchEditor.InsertFront(FTouchEditControls);
    Hint := TCastleLabel.Create(FreeAtStop);
    Hint.Caption := 'Drag the buttons where your thumbs want them';
    Hint.FontSize := 22;
    Hint.Color := White;
    Hint.Anchor(hpMiddle);
    Hint.Anchor(vpTop, -20);
    FTouchEditor.InsertFront(Hint);
    Done := TCastleButton.Create(FreeAtStop);
    Done.Caption := 'Done';
    Done.FontSize := 22;
    Done.Anchor(hpMiddle);
    Done.Anchor(vpTop, -60);
    Done.OnClick := {$ifdef FPC}@{$endif} ClickTouchEditDone;
    FTouchEditor.InsertFront(Done);
    InsertFront(FTouchEditor);
  end;
  FTouchEditControls.LeftHanded := Settings.TouchLeftHanded;
  FTouchEditControls.SizePercent := Settings.TouchSize;
  FTouchEditControls.Opacity := Max(0.5, Settings.TouchOpacity / 100);
  for I := 0 to High(Settings.TouchPlaces) do
    FTouchEditControls.SetButtonPlace(TTouchButton(I + 1), Settings.TouchPlaces[I]);
  FTouchEditControls.ReleaseAll;
  FTouchEditor.Exists := Show;
end;

procedure TViewMenu.ClickTouchSize(Sender: TObject);
begin
  Settings.TouchSize := NextTouchSize(Settings.TouchSize);
  SaveSettings;
  WritelnLog('Settings', TouchSummary);
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickMouseButton(Sender: TObject);
begin
  FWaitAction := TGameAction((Sender as TCastleButton).Tag);
  FWaitSlot := 2;
  UpdateKeyButtons;
end;

function TViewMenu.PreviewPress(const Event: TInputPressRelease): Boolean;
var
  B: TMouseBind;
begin
  Result := inherited;
  if Result then Exit;
  if (FControls = nil) or not FControls.Exists or FPadMode or (FWaitSlot <> 2) then Exit;
  Result := true;
  if Event.IsKey(keyEscape) then
    FWaitSlot := -1
  else
  begin
    if Event.IsKey(keyBackSpace) then
      B := mbNone
    else
    begin
      B := MouseBindOfEvent(Event);
      if B = mbNone then Exit; { another key: keep waiting }
    end;
    BindMouse(FWaitAction, B);
    SaveSettings;
    WritelnLog('Settings', MouseSummary);
    FWaitSlot := -1;
  end;
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickControlsPage(Sender: TObject);
begin
  FControlsPage := (FControlsPage + 1) mod ControlsPageCount;
  FWaitSlot := -1;
  ShowControlsMode;
end;

procedure TViewMenu.ClickControlsPad(Sender: TObject);
begin
  { Keyboard and mouse -> gamepad -> touch -> keyboard and mouse. }
  if FPadMode then
  begin
    FPadMode := false;
    FTouchMode := true;
  end else
  if FTouchMode then
    FTouchMode := false
  else
    FPadMode := true;
  FWaitSlot := -1;
  ShowControlsMode;
end;

procedure TViewMenu.ClickPadButton(Sender: TObject);
begin
  FWaitPadAction := TPadAction((Sender as TCastleButton).Tag div 2);
  FWaitSlot := (Sender as TCastleButton).Tag mod 2;
  UpdateKeyButtons;
end;

procedure TViewMenu.BindWaitingPad(const B: TPadButton);
begin
  BindPad(FWaitPadAction, FWaitSlot, B);
  SaveSettings;
  WritelnLog('Settings', PadSummary);
  FWaitSlot := -1;
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickControls(Sender: TObject);
begin
  FOptions.Exists := false;
  FControls.Exists := true;
  FWaitSlot := -1;
  ShowControlsMode;
end;

procedure TViewMenu.ClickControlsBack(Sender: TObject);
begin
  FWaitSlot := -1;
  FControls.Exists := false;
  ShowOptions(true);
end;

procedure TViewMenu.ClickKeysDefaults(Sender: TObject);
begin
  FWaitSlot := -1;
  if FPadMode then
  begin
    ResetPad;
    WritelnLog('Settings', PadSummary);
  end else
  if FTouchMode then
  begin
    Settings.TouchLeftHanded := false;
    Settings.TouchSize := 100;
    Settings.TouchOpacity := 100;
    ResetTouchPlaces;
    WritelnLog('Settings', TouchSummary);
  end else
  begin
    ResetKeys;
    ResetMouse;
    WritelnLog('Settings', KeysSummary);
    WritelnLog('Settings', MouseSummary);
  end;
  SaveSettings;
  UpdateKeyButtons;
end;

procedure TViewMenu.ClickKeyButton(Sender: TObject);
begin
  FWaitAction := TGameAction((Sender as TCastleButton).Tag div 2);
  FWaitSlot := (Sender as TCastleButton).Tag mod 2;
  UpdateKeyButtons;
end;

function TViewMenu.ControlsKey(const Event: TInputPressRelease): Boolean;
begin
  Result := false;
  if FPadMode and (FWaitSlot >= 0) then
  begin
    { Waiting for a gamepad button: Start or Esc cancels, Backspace
      clears; the triggers are found in Update. }
    if Event.IsController(gbMenu) or Event.IsKey(keyEscape) then
    begin
      FWaitSlot := -1;
      UpdateKeyButtons;
      Exit(true);
    end;
    if Event.IsKey(keyBackSpace) then
    begin
      BindWaitingPad(pbNone);
      Exit(true);
    end;
    if PadButtonOfEvent(Event) <> pbNone then
    begin
      BindWaitingPad(PadButtonOfEvent(Event));
      Exit(true);
    end;
    Exit;
  end;
  { Start or B on the page leaves it, like Esc. }
  if Event.IsController(gbMenu) or Event.IsController(gbEast) then
  begin
    ClickControlsBack(nil);
    Exit(true);
  end;
  if Event.EventType <> itKey then Exit;
  if FWaitSlot < 0 then
  begin
    if Event.IsKey(keyEscape) then
    begin
      ClickControlsBack(nil);
      Result := true;
    end;
    Exit;
  end;
  Result := true;
  if not Event.IsKey(keyEscape) then
  begin
    if Event.IsKey(keyBackSpace) then
      BindKey(FWaitAction, FWaitSlot, keyNone)
    else if not BindKey(FWaitAction, FWaitSlot, Event.Key) then
      Exit; { a function key: keep waiting }
    SaveSettings;
    WritelnLog('Settings', KeysSummary);
  end;
  FWaitSlot := -1;
  UpdateKeyButtons;
end;

procedure TViewMenu.ChangeVolume(const Which, Delta: Integer);
begin
  if Which = 0 then
  begin
    Settings.SfxVolume := Clamped(Settings.SfxVolume + Delta, 0, MaxVolume);
    if FSounds <> nil then
    begin
      FSounds.Volume := SfxGain;
      FSounds.Play('DSPISTOL');
    end;
  end else
  begin
    Settings.MusicVolume := Clamped(Settings.MusicVolume + Delta, 0, MaxVolume);
    if FMusic <> nil then FMusic.Volume := MusicGain;
  end;
  SaveSettings;
  UpdateVolumeLabels;
end;

procedure TViewMenu.ClickSfxDown(Sender: TObject);
begin
  ChangeVolume(0, -1);
end;

procedure TViewMenu.ClickSfxUp(Sender: TObject);
begin
  ChangeVolume(0, 1);
end;

procedure TViewMenu.ClickMusicDown(Sender: TObject);
begin
  ChangeVolume(1, -1);
end;

procedure TViewMenu.ClickMusicUp(Sender: TObject);
begin
  ChangeVolume(1, 1);
end;

procedure TViewMenu.ClickNextSkill(Sender: TObject);
begin
  FSkill := (FSkill + 1) mod 5;
  FDoomMenu.Skill := FSkill;
  UpdateSkillLabel;
end;

procedure TViewMenu.StartGame;
begin
  if (FWad = nil) or (FWad.MapNames.Count = 0) then Exit;
  ViewPlay.Wad := FWad;
  ViewPlay.Graphics := FGraphics;
  ViewPlay.Sounds := FSounds;
  ViewPlay.Music := FMusic;
  ViewPlay.StartMapName := FWad.MapNames[FMapIndex];
  ViewPlay.Skill := FSkill;
  Container.View := ViewPlay;
end;

procedure TViewMenu.AutoStart(Sender: TObject);
begin
  if CmdEdit then
  begin
    { --edit: once (back in the menu, the command line is done). }
    CmdEdit := false;
    StartEditor;
    if AutoTestPrefix = '' then
    begin
      CmdWarp := '';
      CmdIwad := '';
      CmdPwads.Clear;
    end;
  end else
    StartGame;
end;

procedure TViewMenu.StartEditor;
begin
  if (FWad = nil) or (FWad.MapNames.Count = 0) then Exit;
  ViewEdit.Wad := FWad;
  ViewEdit.Graphics := FGraphics;
  ViewEdit.Sounds := FSounds;
  ViewEdit.Music := FMusic;
  ViewEdit.MapName := FWad.MapNames[FMapIndex];
  ViewEdit.Skill := FSkill;
  ViewEdit.Fresh := true;
  Container.View := ViewEdit;
end;

{ --playdemo FILE: the demo's WADs, then the play view plays it. }
procedure TViewMenu.AutoPlayDemo(Sender: TObject);
var
  Demo: TDemoPlayer;
  D: TJSONData;
  Iwad: String;
  Pwads: TStringList;
  I: Integer;
begin
  Demo := OpenDemo(DemoPlayFile);
  if Demo = nil then
  begin
    if FWadsLabel <> nil then
      FWadsLabel.Caption := 'Not a Castle DOOM demo: ' + UriDisplay(DemoPlayFile);
    DemoPlayFile := '';
    {$ifndef WASI}
    { An autotest would wait on the title screen for ever. }
    if AutoTestMap <> '' then Application.Terminate;
    {$endif}
    Exit;
  end;
  Pwads := TStringList.Create;
  try
    Iwad := Freedoom1;
    D := Demo.State.Find('wads');
    if (D is TJSONArray) and (TJSONArray(D).Count > 0) then
    begin
      Iwad := TJSONArray(D).Strings[0];
      for I := 1 to TJSONArray(D).Count - 1 do
        Pwads.Add(TJSONArray(D).Strings[I]);
    end;
    if not LoadWads(Iwad, Pwads) then Exit;
  finally
    FreeAndNil(Pwads);
    FreeAndNil(Demo);
  end;
  StartGame;
end;

procedure TViewMenu.AutoDesign(Sender: TObject);
begin
  Container.View := ViewDesign;
end;

{ --autotest MENU... : open the requested page, then screenshot a few tics
  later (from Update, so the image is composed and rendered). }
procedure TViewMenu.AutoTestMenu;
var
  Event: TInputPressRelease;
begin
  FDoomMenu.MouseEnabled := false;
  { The title pages alone (MENUTITLE), otherwise the menu is open like
    after the first key. }
  if AutoTestMap <> 'MENUTITLE' then
    FDoomMenu.SetMenuActive(true);
  if AutoTestMap = 'MENUREADTHIS' then
    FDoomMenu.HandleKey(InputKey(TVector2.Zero, keyF1, '', []))
  else if (AutoTestMap = 'MENUEPISODE') then
    FDoomMenu.OpenPage(mpEpisode)
  else if (AutoTestMap = 'MENUSKILL') or (AutoTestMap = 'MENUDOOM2') then
    FDoomMenu.OpenPage(mpSkill)
  else if AutoTestMap = 'MENUNIGHTMARE' then
  begin
    { Hurt me plenty, down twice to Nightmare!, Enter: the confirmation. }
    FDoomMenu.Skill := 2;
    FDoomMenu.OpenPage(mpSkill);
    FDoomMenu.HandleKey(InputKey(TVector2.Zero, keyArrowDown, '', []));
    FDoomMenu.HandleKey(InputKey(TVector2.Zero, keyArrowDown, '', []));
    FDoomMenu.HandleKey(InputKey(TVector2.Zero, keyEnter, '', []));
  end
  else if AutoTestMap = 'MENUQUIT' then
  begin
    { Up from New Game wraps to Quit Game, Enter: the quit question. }
    FDoomMenu.HandleKey(InputKey(TVector2.Zero, keyArrowUp, '', []));
    FDoomMenu.HandleKey(InputKey(TVector2.Zero, keyEnter, '', []));
  end
  else if AutoTestMap = 'MENULOAD' then
    FDoomMenu.OpenPage(mpLoad)
  else if AutoTestMap = 'MENUOPTIONS' then
    ShowOptions(true)
  else if AutoTestMap = 'MENUDLIGHTS' then
  begin
    { The Options panel after a click on "Dynamic lights". }
    ShowOptions(true);
    ClickDynamicLights(nil);
  end
  else if AutoTestMap = 'MENUCONTROLS' then
  begin
    { The Controls page, after binding Q to "Use" like a click on its
      first key and a key press would. }
    ShowOptions(true);
    ClickControls(nil);
    ClickKeyButton(FKeyButtons[gaUse, 0]);
    ControlsKey(InputKey(TVector2.Zero, keyQ, 'q', []));
    { And the right mouse button to "Use", like a click on its mouse slot
      and a right click. }
    ClickMouseButton(FMouseButtons[gaUse]);
    PreviewPress(InputMouseButton(TVector2.Zero, buttonRight, 0, []));
  end
  else if AutoTestMap = 'MENUCONTROLSHOTKEYS' then
  begin
    { The Controls page's hotkeys, after binding K to light diminishing. }
    ShowOptions(true);
    ClickControls(nil);
    ClickControlsPage(nil);
    ClickControlsPage(nil);
    ClickKeyButton(FKeyButtons[gaLightDiminish, 0]);
    ControlsKey(InputKey(TVector2.Zero, keyK, 'k', []));
  end
  else if AutoTestMap = 'MENUCONTROLSTOUCH' then
  begin
    { The Controls page's touch half, after switching to the left hand and
      the next size (125%). }
    ShowOptions(true);
    ClickControls(nil);
    ClickControlsPad(nil);
    ClickControlsPad(nil);
    ClickTouchHand(nil);
    ClickTouchSize(nil);
  end
  else if AutoTestMap = 'MENUTOUCHEDIT' then
  begin
    { The touch layout editor, after dragging FIRE to the middle of the
      screen like a finger would, and the opacity set to 50%. }
    ShowOptions(true);
    ClickControls(nil);
    ClickControlsPad(nil);
    ClickControlsPad(nil);
    ClickTouchOpacity(nil);
    ClickTouchOpacity(nil);
    ClickTouchEdit(nil);
    FTouchEditDrag := true;
  end
  else if AutoTestMap = 'MENUCONTROLSPAD' then
  begin
    { The Controls page's gamepad half, after binding Y to the second
      fire slot like a click and a button press would. }
    ShowOptions(true);
    ClickControls(nil);
    ClickControlsPad(nil);
    ClickPadButton(FPadButtons[gpaFire, 1]);
    if PadButtonEvent(pbY, Event) then
      ControlsKey(Event);
  end
  else if AutoTestMap = 'MENUKEYS' then
  begin
    FMenuKeys.DelimitedText := AutoTestMenuKeys;
    FMenuKeyTics := 10;
    Exit;
  end;
  FAutoTestTics := 10;
end;

procedure TViewMenu.NextMenuKey;
var
  K: String;
  Key: TKey;
begin
  if FMenuKeys.Count = 0 then Exit;
  K := UpperCase(FMenuKeys[0]);
  FMenuKeys.Delete(0);
  FMenuKeyTics := 6;
  WritelnLog('AutoTest', 'Menu key %s', [K]);
  if K = 'Q' then
  begin
    Application.Terminate;
    Exit;
  end;
  if K = 'S' then
  begin
    Inc(FMenuShots);
    Application.MainWindow.SaveScreen(Format('%s_menu%d.png', [AutoTestPrefix, FMenuShots]));
    Exit;
  end;
  if K = 'U' then Key := keyArrowUp
  else if K = 'D' then Key := keyArrowDown
  else if K = 'E' then Key := keyEnter
  else if K = 'X' then Key := keyEscape
  else if K = 'Y' then Key := keyY
  else if K = 'N' then Key := keyN
  else if K = 'L' then Key := keyArrowLeft
  else if K = 'R' then Key := keyArrowRight
  else if K = 'B' then Key := keyBackSpace
  else if (Length(K) = 1) and (K[1] in ['0'..'9']) then
  begin
    { A digit typed (the custom game page's random seed). }
    Press(InputKey(TVector2.Zero, keyNone, K, []));
    Exit;
  end else
    Exit;
  Press(InputKey(TVector2.Zero, Key, '', []));
end;

procedure TViewMenu.AutoScreenshot;
begin
  Application.MainWindow.SaveScreen(AutoTestPrefix + '_' + LowerCase(AutoTestMap) + '.png');
  WritelnLog('AutoTest', 'Menu screenshot %s', [AutoTestMap]);
  Application.Terminate;
end;

procedure TViewMenu.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  inherited;
  if FFetch <> nil then
  begin
    if FFetch.TotalBytes > 0 then
      FFetchLabel.Caption := Format('Downloading Freedoom Phase 2: %d / %d MB', [
        FFetch.DownloadedBytes div (1024 * 1024), FFetch.TotalBytes div (1024 * 1024)])
    else
      FFetchLabel.Caption := Format('Downloading Freedoom Phase 2: %d MB', [
        FFetch.DownloadedBytes div (1024 * 1024)]);
  end;
  { The title music is rendered a slice per frame. }
  if FMusic <> nil then FMusic.Update;
  { A file the browser's picker delivered. }
  PollPickedFile;
  { The Controls page waiting for a gamepad button: the triggers are
    axes, without press events. }
  if (FControls <> nil) and FControls.Exists and FPadMode and (FWaitSlot >= 0) then
  begin
    if PadButtonHeld(pbRightTrigger) then
      BindWaitingPad(pbRightTrigger)
    else if PadButtonHeld(pbLeftTrigger) then
      BindWaitingPad(pbLeftTrigger);
  end;
  if FDoomMenu = nil then Exit;
  { 320x200 shown 4:3, as tall as the window (or as wide, if narrower). }
  FDoomMenu.Height := Min(EffectiveHeight, EffectiveWidth * 3 / 4);
  FDoomMenu.Width := FDoomMenu.Height * 4 / 3;
  FTicAccum := FTicAccum + SecondsPassed;
  while FTicAccum >= TicSeconds do
  begin
    FTicAccum := FTicAccum - TicSeconds;
    FDoomMenu.Tic;
    if FMenuKeyTics > 0 then
    begin
      Dec(FMenuKeyTics);
      if FMenuKeyTics = 0 then
      begin
        NextMenuKey;
        { The menu may have started the game (this view is stopped). }
        if Application.MainWindow.Container.View <> Self then Exit;
      end;
    end;
    if FAutoTestTics > 0 then
    begin
      Dec(FAutoTestTics);
      if FTouchEditDrag and (FAutoTestTics = 5) then
        DragTouchFire;
      if FAutoTestTics = 0 then
      begin
        AutoScreenshot;
        Exit;
      end;
    end;
  end;
end;

procedure TViewMenu.ClickStart(Sender: TObject);
begin
  StartGame;
end;

function TViewMenu.Press(const Event: TInputPressRelease): Boolean;
var
  K: TKey;
begin
  Result := inherited;
  if Result then Exit;
  { The touch layout editor: Esc (or Start, B) closes it. }
  if (FTouchEditor <> nil) and FTouchEditor.Exists then
  begin
    if Event.IsKey(keyEscape) or Event.IsController(gbMenu) or Event.IsController(gbEast) then
      ShowTouchEditor(false);
    Exit(true);
  end;
  { Gamepad: the D-pad and A / B drive the menu like the arrows, Enter, Esc. }
  if FControls.Exists then
    Exit(ControlsKey(Event));
  if GamepadKey(Event, true, K) then
    Exit(Press(InputKey(Container.MousePosition, K, '', [])));
  if FOptions.Exists then
  begin
    if Event.IsKey(keyEnter) then
    begin
      StartGame;
      Exit(true);
    end;
    if Event.IsKey(keyArrowLeft) then begin ClickPrevMap(nil); Exit(true); end;
    if Event.IsKey(keyArrowRight) then begin ClickNextMap(nil); Exit(true); end;
    if Event.IsKey(keyEscape) then
    begin
      ShowOptions(false);
      Exit(true);
    end;
    Exit;
  end;
  if FDoomMenu.HandleKey(Event) then
    Exit(true);
end;

initialization
  CmdPwads := TStringList.Create;
finalization
  FreeAndNil(CmdPwads);
end.
