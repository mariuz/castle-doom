{ Title screen: pick a WAD (Freedoom Phase 1 = Doom 1 style episodes,
  Freedoom Phase 2 = Doom 2 style MAPxx) and a starting map. }
unit GameViewMenu;

interface

uses Classes, SysUtils,
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
    FWadUrl: String;
    FMapIndex: Integer;
    procedure LoadWad(const Url: String);
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

implementation

uses Math, CastleLog, CastleColors, CastleUtils, CastleWindow,
  GameViewPlay;

constructor TViewMenu.Create(AOwner: TComponent);
begin
  inherited;
end;

procedure TViewMenu.Start;
var
  Back: TCastleRectangleControl;
  B: TCastleButton;
  Row: TCastleHorizontalGroup;
  Header: TCastleLabel;
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

  FStatus := TCastleLabel.Create(FreeAtStop);
  FStatus.Color := Vector4(0.8, 0.8, 0.8, 1);
  FStatus.FontSize := 16;
  FStatus.Anchor(hpMiddle);
  FStatus.Anchor(vpBottom, 16);
  FStatus.Alignment := hpMiddle;
  FStatus.Caption := 'Freedoom (BSD licence) by the Freedoom project. Castle Game Engine https://castle-engine.io';
  InsertFront(FStatus);

  if AutoTestMap = 'MENU' then
  begin
    LoadWad('castle-data:/wads/freedoom1.wad');
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoScreenshot);
    Exit;
  end;
  if AutoTestMap <> '' then
  begin
    if Copy(AutoTestMap, 1, 3) = 'MAP' then
      LoadWad('castle-data:/wads/freedoom2.wad')
    else
      LoadWad('castle-data:/wads/freedoom1.wad');
    FMapIndex := Max(0, FWad.MapNames.IndexOf(AutoTestMap));
    { Cannot change the view inside Start; do it after the first render. }
    WaitForRenderAndCall({$ifdef FPC}@{$endif} AutoStart);
    Exit;
  end;
  if FWad = nil then
    LoadWad('castle-data:/wads/freedoom1.wad')
  else
  begin
    UpdateMapLabel;
    FMusic.Play(FMusic.TitleLump);
  end;
end;

procedure TViewMenu.Stop;
begin
  inherited;
end;

procedure TViewMenu.LoadWad(const Url: String);
var
  Img: TDoomImage;
begin
  if (FWad <> nil) and (FWadUrl = Url) then Exit;
  { The play view may still reference the old objects; it is stopped when
    this view is active, so it is safe to replace them. }
  FreeAndNil(FMusic);
  FreeAndNil(FSounds);
  FreeAndNil(FGraphics);
  FreeAndNil(FWad);
  FWadUrl := Url;
  FWad := TDoomWad.Create(Url);
  FGraphics := TDoomGraphics.Create(FWad);
  FSounds := TDoomSounds.Create(FWad);
  FMusic := TDoomMusic.Create(FWad);
  if AutoTestMap = '' then
    FMusic.Play(FMusic.TitleLump);
  FMapIndex := 0;
  Img := FGraphics.Patch('TITLEPIC');
  if Img <> nil then
    FTitle.Image := Img.Image.MakeCopy;
  UpdateMapLabel;
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
  LoadWad('castle-data:/wads/freedoom1.wad');
end;

procedure TViewMenu.ClickPhase2(Sender: TObject);
begin
  LoadWad('castle-data:/wads/freedoom2.wad');
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

end.
