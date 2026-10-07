{ Title screen: pick a WAD (Freedoom Phase 1 = Doom 1 style episodes,
  Freedoom Phase 2 = Doom 2 style MAPxx) and a starting map. }
unit GameViewMenu;

interface

uses Classes, SysUtils, FpJson,
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse, CastleImages,
  DoomWad, DoomGraphics, DoomSound, DoomMusic;

type
  TViewMenu = class(TCastleView)
  strict private
    FTitle: TCastleImageControl;
    FButtons: TCastleVerticalGroup;
    FMapLabel: TCastleLabel;
    FStatus: TCastleLabel;
    FWad: TDoomWad;
    FGraphics: TDoomGraphics;
    FSounds: TDoomSounds;
    FMusic: TDoomMusic;
    FIwadUrl: String;
    FPwads: TStringList;
    FWadsLabel: TCastleLabel;
    FMapIndex: Integer;
    procedure LoadWads(const Iwad: String; const Pwads: TStrings);
    procedure ClickOpenIwad(Sender: TObject);
    procedure ClickAddPwad(Sender: TObject);
    procedure ClickLastWads(Sender: TObject);
    procedure ClickContinue(Sender: TObject);
    procedure ContinueFromSlot(const Slot: Integer);
    procedure AutoContinue(Sender: TObject);
    procedure UpdateWadsLabel;
    procedure RememberWads;
    procedure ClickPhase1(Sender: TObject);
    procedure ClickPhase2(Sender: TObject);
    procedure ClickStart(Sender: TObject);
    procedure ClickPrevMap(Sender: TObject);
    procedure ClickNextMap(Sender: TObject);
    procedure UpdateMapLabel;
    procedure StartGame;
    procedure AutoStart(Sender: TObject);
    procedure AutoScreenshot(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start; override;
    procedure Stop; override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewMenu: TViewMenu;
  { Set from the command line (--autotest MAP PREFIX): start this map at once. }
  AutoTestMap: String;
  AutoTestPrefix: String;
  AutoTestDemo: String;
  { Set from the command line: -iwad FILE, -file PWAD..., -warp MAP. }
  CmdIwad: String;
  CmdPwads: TStringList;
  CmdWarp: String;
  { -loadgame N: start from saved game slot N (0 = quick save). }
  CmdLoadSlot: Integer = -1;

implementation

uses Math, CastleLog, CastleColors, CastleUtils, CastleWindow, CastleConfig, CastleUriUtils,
  CastleStringUtils,
  GameViewPlay;

const
  Freedoom1 = 'castle-data:/wads/freedoom1.wad';
  Freedoom2 = 'castle-data:/wads/freedoom2.wad';

constructor TViewMenu.Create(AOwner: TComponent);
begin
  inherited;
  FPwads := TStringList.Create;
end;

procedure TViewMenu.Start;
var
  Back: TCastleRectangleControl;
  B: TCastleButton;
  Row: TCastleHorizontalGroup;
  Header: TCastleLabel;
  Save: TJSONObject;
begin
  inherited;
  Back := TCastleRectangleControl.Create(FreeAtStop);
  Back.FullSize := true;
  Back.Color := Vector4(0.05, 0.02, 0.02, 1);
  InsertFront(Back);

  FTitle := TCastleImageControl.Create(FreeAtStop);
  FTitle.SmoothScaling := false;
  FTitle.Stretch := true;
  FTitle.Anchor(hpMiddle);
  FTitle.Anchor(vpTop, -20);
  FTitle.Width := 640;
  FTitle.Height := 400;
  InsertFront(FTitle);

  Header := TCastleLabel.Create(FreeAtStop);
  Header.Caption := 'CASTLE DOOM  -  Doom levels in Castle Game Engine';
  Header.Color := Vector4(1, 0.3, 0.15, 1);
  Header.FontSize := 30;
  Header.Anchor(hpMiddle);
  Header.Anchor(vpTop, -430);
  InsertFront(Header);

  FButtons := TCastleVerticalGroup.Create(FreeAtStop);
  FButtons.Anchor(hpMiddle);
  FButtons.Anchor(vpTop, -480);
  FButtons.Spacing := 10;
  FButtons.Alignment := hpMiddle;
  InsertFront(FButtons);

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

  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'START  (Enter)';
  B.FontSize := 26;
  B.OnClick := {$ifdef FPC}@{$endif} ClickStart;
  FButtons.InsertFront(B);

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
  B := TCastleButton.Create(FreeAtStop);
  B.Caption := 'Continue (quick save)';
  B.FontSize := 18;
  B.OnClick := {$ifdef FPC}@{$endif} ClickContinue;
  Save := ReadSaveFile(SaveSlotUrl(0));
  B.Exists := Save <> nil;
  FreeAndNil(Save);
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
  InsertFront(FStatus);

  if CmdLoadSlot >= 0 then
  begin
    { Cannot change the view inside Start; do it after the first render. }
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoContinue);
    Exit;
  end;
  if AutoTestMap = 'MENU' then
  begin
    LoadWads(Freedoom1, nil);
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoScreenshot);
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
    Exit;
  end;
  if FWad = nil then
    LoadWads(Freedoom1, nil)
  else
  begin
    UpdateMapLabel;
    UpdateWadsLabel;
    FMusic.Play(FMusic.TitleLump);
  end;
end;

procedure TViewMenu.Stop;
begin
  inherited;
end;

destructor TViewMenu.Destroy;
begin
  FreeAndNil(FPwads);
  inherited;
end;

procedure TViewMenu.LoadWads(const Iwad: String; const Pwads: TStrings);
var
  Img: TDoomImage;
  I: Integer;
  NewPwads: TStringList;
begin
  NewPwads := TStringList.Create;
  try
    if Pwads <> nil then NewPwads.Assign(Pwads);
    if (FWad <> nil) and (FIwadUrl = Iwad) and (NewPwads.Text = FPwads.Text) then Exit;
    { The play view may still reference the old objects; it is stopped when
      this view is active, so it is safe to replace them. }
    FreeAndNil(FMusic);
    FreeAndNil(FSounds);
    FreeAndNil(FGraphics);
    FreeAndNil(FWad);
    try
      FWad := TDoomWad.Create(Iwad);
      for I := 0 to NewPwads.Count - 1 do
        FWad.AddFile(NewPwads[I]);
      FGraphics := TDoomGraphics.Create(FWad);
      FSounds := TDoomSounds.Create(FWad);
      FMusic := TDoomMusic.Create(FWad);
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
    Img := FGraphics.Patch('TITLEPIC');
    if Img <> nil then
      FTitle.Image := Img.Image.MakeCopy;
    UpdateMapLabel;
    UpdateWadsLabel;
    RememberWads;
  finally
    FreeAndNil(NewPwads);
  end;
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
    LoadWads(Iwad, Pwads);
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
  if (FWad <> nil) and (FWad.MapNames.Count > 0) then
  begin
    FMapIndex := Clamped(FMapIndex, 0, FWad.MapNames.Count - 1);
    FMapLabel.Caption := Format('  %s  (%d/%d)  ', [FWad.MapNames[FMapIndex], FMapIndex + 1, FWad.MapNames.Count]);
  end else
    FMapLabel.Caption := '  no maps  ';
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
  Dec(FMapIndex);
  if FMapIndex < 0 then FMapIndex := FWad.MapNames.Count - 1;
  UpdateMapLabel;
end;

procedure TViewMenu.ClickNextMap(Sender: TObject);
begin
  Inc(FMapIndex);
  if FMapIndex >= FWad.MapNames.Count then FMapIndex := 0;
  UpdateMapLabel;
end;

procedure TViewMenu.StartGame;
begin
  if (FWad = nil) or (FWad.MapNames.Count = 0) then Exit;
  ViewPlay.Wad := FWad;
  ViewPlay.Graphics := FGraphics;
  ViewPlay.Sounds := FSounds;
  ViewPlay.Music := FMusic;
  ViewPlay.StartMapName := FWad.MapNames[FMapIndex];
  Container.View := ViewPlay;
end;

procedure TViewMenu.AutoStart(Sender: TObject);
begin
  StartGame;
end;

procedure TViewMenu.AutoScreenshot(Sender: TObject);
begin
  Application.MainWindow.SaveScreen(AutoTestPrefix + '_menu.png');
  Application.Terminate;
end;

procedure TViewMenu.ClickStart(Sender: TObject);
begin
  StartGame;
end;

function TViewMenu.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  if Event.IsKey(keyEnter) then
  begin
    StartGame;
    Exit(true);
  end;
  if Event.IsKey(keyArrowLeft) then begin ClickPrevMap(nil); Exit(true); end;
  if Event.IsKey(keyArrowRight) then begin ClickNextMap(nil); Exit(true); end;
  if Event.IsKey(keyEscape) then
  begin
    Application.Terminate;
    Exit(true);
  end;
end;

initialization
  CmdPwads := TStringList.Create;
finalization
  FreeAndNil(CmdPwads);
end.
