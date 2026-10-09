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
  DoomWad, DoomGraphics, DoomSound, DoomMusic, DoomMenu, DoomDehacked;

type
  TViewMenu = class(TCastleView)
  strict private
    FDoomMenu: TDoomMenuScreen;
    FOptions: TCastleRectangleControl;
    FButtons: TCastleVerticalGroup;
    FMapLabel: TCastleLabel;
    FSkillLabel: TCastleLabel;
    FSfxLabel, FMusicLabel: TCastleLabel;
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
    { Load the IWAD and PWADs (title music, menus follow). False when they
      did not load, or when Freedoom Phase 2 is being downloaded first. }
    function LoadWads(const Iwad: String; const Pwads: TStrings): Boolean;
    function NeedsFetch(const Iwad: String): Boolean;
    procedure StartFetch(const Pwads: TStrings);
    procedure FetchFinished(const Sender: TCastleDownload; var FreeSender: Boolean);
    { The command-line part of Start (map, warp, autotest), also run when a
      download it waited for arrives. }
    procedure StartFromCommandLine;
    procedure SetupDoomMenu;
    procedure RefreshSlots;
    procedure DoomMenuAction(const Action: TDoomMenuAction);
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
    procedure UpdateMapLabel;
    procedure UpdateSkillLabel;
    procedure StartGame;
    procedure AutoStart(Sender: TObject);
    procedure AutoTestMenu;
    procedure AutoScreenshot;
    procedure NextMenuKey;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMenu: TViewMenu;
  { Set from the command line (--autotest MAP PREFIX): start this map at once.
    MAP = MENU, MENUEPISODE, MENUSKILL, MENUNIGHTMARE, MENUQUIT, MENULOAD, MENUOPTIONS
    or MENUDOOM2 takes a screenshot of that menu page instead. }
  AutoTestMap: String;
  AutoTestPrefix: String;
  AutoTestDemo: String;
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

uses Math, CastleLog, CastleColors, CastleUtils, CastleWindow, CastleConfig, CastleUriUtils,
  CastleStringUtils,
  CastleFilesUtils,
  GameViewPlay, GameSettings, GameSaveBundle, GameSaveStorage;

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
end;

procedure TViewMenu.Start;
var
  Back: TCastleRectangleControl;
  B: TCastleButton;
  Row: TCastleHorizontalGroup;
  Header: TCastleLabel;
begin
  inherited;
  if CmdSkill >= 0 then FSkill := CmdSkill;

  Back := TCastleRectangleControl.Create(FreeAtStop);
  Back.FullSize := true;
  Back.Color := Black;
  InsertFront(Back);

  { Doom's menu over TITLEPIC, 320x200 shown 4:3 (sized in Update). }
  FDoomMenu := TDoomMenuScreen.Create(FreeAtStop);
  FDoomMenu.Anchor(hpMiddle);
  FDoomMenu.Anchor(vpMiddle);
  FDoomMenu.OnAction := {$ifdef FPC}@{$endif} DoomMenuAction;
  InsertFront(FDoomMenu);

  { Options: the WAD / map / skill picker. }
  FOptions := TCastleRectangleControl.Create(FreeAtStop);
  FOptions.FullSize := true;
  FOptions.Color := Vector4(0.05, 0.02, 0.02, 0.92);
  FOptions.Exists := false;
  InsertFront(FOptions);

  FButtons := TCastleVerticalGroup.Create(FreeAtStop);
  FButtons.Anchor(hpMiddle);
  FButtons.Anchor(vpMiddle);
  FButtons.Spacing := 10;
  FButtons.Alignment := hpMiddle;
  FOptions.InsertFront(FButtons);

  Header := TCastleLabel.Create(FreeAtStop);
  Header.Caption := 'CASTLE DOOM  -  Doom levels in Castle Game Engine';
  Header.Color := Vector4(1, 0.3, 0.15, 1);
  Header.FontSize := 30;
  FButtons.InsertFront(Header);

  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);

  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Freedoom Phase 1 (Doom 1 episodes)';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickPhase1;
  Row.InsertFront(B);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Freedoom Phase 2 (Doom 2 maps)';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickPhase2;
  Row.InsertFront(B);

  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '<';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickPrevMap;
  Row.InsertFront(B);
  FMapLabel := TCastleLabel.Create(FreeAtStop);
  FMapLabel.Color := White;
  FMapLabel.FontSize := 22;
  FMapLabel.Caption := 'E1M1';
  Row.InsertFront(FMapLabel);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '>';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickNextMap;
  Row.InsertFront(B);

  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '<';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickPrevSkill;
  Row.InsertFront(B);
  FSkillLabel := TCastleLabel.Create(FreeAtStop);
  FSkillLabel.Color := White;
  FSkillLabel.FontSize := 22;
  Row.InsertFront(FSkillLabel);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '>';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickNextSkill;
  Row.InsertFront(B);

  { Volumes, the same settings as the F4 menu in the game. }
  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '<';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickSfxDown;
  Row.InsertFront(B);
  FSfxLabel := TCastleLabel.Create(FreeAtStop);
  FSfxLabel.Color := White;
  FSfxLabel.FontSize := 22;
  Row.InsertFront(FSfxLabel);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '>';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickSfxUp;
  Row.InsertFront(B);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '<';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickMusicDown;
  Row.InsertFront(B);
  FMusicLabel := TCastleLabel.Create(FreeAtStop);
  FMusicLabel.Color := White;
  FMusicLabel.FontSize := 22;
  Row.InsertFront(FMusicLabel);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := '>';
  B.FontSize := 22;
  B.OnClick := {$ifdef FPC}@{$endif} ClickMusicUp;
  Row.InsertFront(B);
  UpdateVolumeLabels;

  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'START  (Enter)';
  B.FontSize := 26;
  B.OnClick := {$ifdef FPC}@{$endif} ClickStart;
  Row.InsertFront(B);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Back  (Esc)';
  B.FontSize := 26;
  B.OnClick := {$ifdef FPC}@{$endif} ClickBack;
  Row.InsertFront(B);

  { Your own WADs (desktop only: needs a native file dialog). }
  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Open IWAD...';
  B.FontSize := 18;
  B.OnClick := {$ifdef FPC}@{$endif} ClickOpenIwad;
  Row.InsertFront(B);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Add PWAD...';
  B.FontSize := 18;
  B.OnClick := {$ifdef FPC}@{$endif} ClickAddPwad;
  Row.InsertFront(B);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Last WADs';
  B.FontSize := 18;
  B.OnClick := {$ifdef FPC}@{$endif} ClickLastWads;
  B.Exists := UserConfig.GetValue('wads/iwad', '') <> '';
  Row.InsertFront(B);
  FContinueButton := TCastleButton.Create(FreeAtStop);
  FContinueButton.Caption := 'Continue (quick save)';
  FContinueButton.FontSize := 18;
  FContinueButton.OnClick := {$ifdef FPC}@{$endif} ClickContinue;
  Row.InsertFront(FContinueButton);

  { Moving saves between computers / the web build (GameSaveBundle). }
  Row := TCastleHorizontalGroup.Create(FreeAtStop);
  Row.Spacing := 10;
  FButtons.InsertFront(Row);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Export saves...';
  B.FontSize := 18;
  B.OnClick := {$ifdef FPC}@{$endif} ClickExportSaves;
  Row.InsertFront(B);
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Import saves...';
  B.FontSize := 18;
  B.OnClick := {$ifdef FPC}@{$endif} ClickImportSaves;
  Row.InsertFront(B);

  FWadsLabel := TCastleLabel.Create(FreeAtStop);
  FWadsLabel.Color := Vector4(0.8, 0.8, 0.8, 1);
  FWadsLabel.FontSize := 16;
  FWadsLabel.Alignment := hpMiddle;
  FButtons.InsertFront(FWadsLabel);

  FStatus := TCastleLabel.Create(FreeAtStop);
  FStatus.Color := Vector4(0.8, 0.8, 0.8, 1);
  FStatus.FontSize := 16;
  FStatus.Anchor(hpMiddle);
  FStatus.Anchor(vpBottom, 16);
  FStatus.Alignment := hpMiddle;
  FStatus.Caption := 'Freedoom (BSD licence) by the Freedoom project. Castle Game Engine https://castle-engine.io';
  FOptions.InsertFront(FStatus);
  UpdateSkillLabel;

  { Download progress of Freedoom Phase 2 (web), over the menu and Options. }
  FFetchLabel := TCastleLabel.Create(FreeAtStop);
  FFetchLabel.Color := Vector4(1, 0.8, 0.3, 1);
  FFetchLabel.FontSize := 22;
  FFetchLabel.Anchor(hpMiddle);
  FFetchLabel.Anchor(vpBottom, 48);
  FFetchLabel.Exists := false;
  InsertFront(FFetchLabel);

  if CmdLoadSlot >= 0 then
  begin
    { Cannot change the view inside Start; do it after the first render. }
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoContinue);
    Exit;
  end;
  if Copy(AutoTestMap, 1, 4) = 'MENU' then
  begin
    if AutoTestMap = 'MENUDOOM2' then
      LoadWads(Freedoom2, nil)
    else
      LoadWads(Freedoom1, nil);
    AutoTestMenu;
    Exit;
  end;
  if (AutoTestMap <> '') or (CmdIwad <> '') or (CmdPwads.Count > 0) or (CmdWarp <> '') then
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
    SetupDoomMenu;
    UpdateMapLabel;
    UpdateWadsLabel;
    FMusic.Play(FMusic.TitleLump);
  end;
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
    if (AutoTestMap <> '') or (CmdWarp <> '') then
    begin
      { Cannot change the view inside Start; do it after the first render. }
      WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoStart);
      Exit;
    end;
    FMusic.Play(FMusic.TitleLump);
  end;
end;

procedure TViewMenu.Stop;
begin
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

procedure TViewMenu.DoomMenuAction(const Action: TDoomMenuAction);
var
  MapName: String;
  I: Integer;
begin
  case Action of
    maNewGame:
      begin
        FSkill := FDoomMenu.Skill;
        UpdateSkillLabel;
        { G_DeferedInitNew: ExM1 for the chosen episode, else the first map. }
        if FDoomMenu.Episode > 0 then
          MapName := Format('E%dM1', [FDoomMenu.Episode])
        else
          MapName := 'MAP01';
        I := FWad.MapNames.IndexOf(MapName);
        if I < 0 then I := 0;
        FMapIndex := I;
        StartGame;
      end;
    maLoadSlot: ContinueFromSlot(FDoomMenu.Slot);
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
begin
  { Only remember user files, not the bundled Freedoom. }
  if (FIwadUrl <> Freedoom1) and (FIwadUrl <> Freedoom2) or (FPwads.Count > 0) then
  begin
    UserConfig.SetValue('wads/iwad', FIwadUrl);
    UserConfig.SetValue('wads/pwads', FPwads.DelimitedText);
    UserConfig.Save;
  end;
end;

const
  NoDialogInBrowser = 'In the browser, export and import saves on the Castle DOOM home page ("Your saves")';

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
  if Application.MainWindow.FileDialog('Open Doom IWAD', Url, true,
      'Doom WAD files (*.wad)|*.wad|All files (*)|*') then
    LoadWads(Url, nil)
  else
    FWadsLabel.Caption := 'No file chosen (file dialogs are not available in the browser)';
end;

procedure TViewMenu.ClickAddPwad(Sender: TObject);
var
  Url: String;
  Pwads: TStringList;
begin
  Url := UserConfig.GetValue('wads/lastpwad', '');
  if Application.MainWindow.FileDialog('Add Doom PWAD (-file)', Url, true,
      'Doom WAD files (*.wad)|*.wad|All files (*)|*') then
  begin
    UserConfig.SetValue('wads/lastpwad', Url);
    Pwads := TStringList.Create;
    try
      Pwads.Assign(FPwads);
      Pwads.Add(Url);
      LoadWads(FIwadUrl, Pwads);
    finally
      FreeAndNil(Pwads);
    end;
  end else
    FWadsLabel.Caption := 'No file chosen (file dialogs are not available in the browser)';
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
  StartGame;
end;

{ --autotest MENU... : open the requested page, then screenshot a few tics
  later (from Update, so the image is composed and rendered). }
procedure TViewMenu.AutoTestMenu;
begin
  FDoomMenu.MouseEnabled := false;
  if (AutoTestMap = 'MENUEPISODE') then
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
  else Exit;
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
begin
  Result := inherited;
  if Result then Exit;
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
