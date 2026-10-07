{ The "playing" view: a TCastleViewport showing the Doom level, walk
  navigation with gravity and collisions, weapon/status bar HUD, and the
  input handling that drives TDoomWorld. }
unit GameViewPlay;

interface

uses Classes, SysUtils,
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse,
  CastleViewport, CastleScene, CastleCameras, CastleTransform, CastleColors,
  DoomWad, DoomGraphics, DoomSound, DoomWorld, DoomHud, DoomMusic, DoomAutomap;

type
  TViewPlay = class(TCastleView)
  strict private
    FViewport: TCastleViewport;
    FNavigation: TCastleWalkNavigation;
    FFog: TCastleFog;
    FFogEnabled: Boolean;
    FWorld: TDoomWorld;
    FStatusBar: TDoomStatusBar;
    FWeaponImage, FFlashImage: TCastleImageControl;
    FWeaponImageName, FFlashImageName: String;
    FDamageFlash, FBonusFlash: TCastleRectangleControl;
    FMessageLabel, FInfoLabel, FHelpLabel, FIntermissionLabel: TCastleLabel;
    FIntermissionBack: TCastleRectangleControl;
    FCrosshair: TCastleCrosshair;
    FAutomap: TDoomAutomap;
    FMapName: String;
    FIntermission: Boolean;
    FIntermissionTime: Single;
    FBobPhase: Single;
    FLastCameraPos: TVector3;
    FHelpVisible: Boolean;
    FLevelTime: Single;
    FAutoTestTime: Single;
    FAutoTestShots: Integer;
    FDemoSteps: TStringList;
    FDemoStep: Integer;
    FDemoTime: Single;
    FPendingMap: String;
    FPendingKeepInventory: Boolean;
    procedure RunDemo(const SecondsPassed: Single);
    procedure LoadPendingMap(Sender: TObject);
    procedure CreateUi;
    procedure SetupNavigation;
    procedure PlacePlayer(const DoomX, DoomY, DoomZ, AngleDeg: Single);
    procedure UpdateWeaponSprite(const SecondsPassed: Single);
    procedure StartMap(const MapName: String; const KeepInventory: Boolean);
    procedure StartIntermission;
    procedure FinishIntermission;
    function DoomAngleFromCamera: Single;
  public
    { Set before starting the view. }
    Wad: TDoomWad;
    Graphics: TDoomGraphics;
    Sounds: TDoomSounds;
    Music: TDoomMusic;
    StartMapName: String;
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewPlay: TViewPlay;

implementation

uses Math,
  CastleLog, CastleUtils, CastleStringUtils, CastleWindow, CastleSoundEngine, CastleRenderOptions,
  CastleUriUtils, X3DNodes,
  DoomGeometry, DoomMap,
  GameViewMenu;

constructor TViewPlay.Create(AOwner: TComponent);
begin
  inherited;
  FFogEnabled := true;
end;

procedure TViewPlay.CreateUi;
var
  Camera: TCastleCamera;
begin
  FViewport := TCastleViewport.Create(FreeAtStop);
  FViewport.FullSize := true;
  Camera := TCastleCamera.Create(FViewport);
  Camera.ProjectionNear := 4;
  Camera.ProjectionFar := 0; { automatic / infinite }
  Camera.Perspective.FieldOfViewAxis := faHorizontal;
  Camera.Perspective.FieldOfView := DegToRad(90);
  FViewport.Items.Add(Camera);
  FViewport.Camera := Camera;
  FViewport.BackgroundColor := Black;
  { Many small sector scenes: let CGE merge them into fewer draw calls. }
  FViewport.DynamicBatching := true;
  InsertFront(FViewport);

  { Doom's "light diminishing": things fade to black with distance. }
  FFog := TCastleFog.Create(FreeAtStop);
  FFog.Color := Vector3(0, 0, 0);
  FFog.FogType := ftExponential;
  FFog.VisibilityRange := 4500;
  FViewport.Fog := FFog;

  FNavigation := TCastleWalkNavigation.Create(FreeAtStop);
  FViewport.InsertFront(FNavigation);
  SetupNavigation;

  { Automap, drawn over the 3D view and under the HUD. }
  FAutomap := TDoomAutomap.Create(FreeAtStop);
  FAutomap.Exists := false;
  InsertFront(FAutomap);

  { Screen flashes. }
  FDamageFlash := TCastleRectangleControl.Create(FreeAtStop);
  FDamageFlash.FullSize := true;
  FDamageFlash.Color := Vector4(1, 0, 0, 0);
  InsertFront(FDamageFlash);
  FBonusFlash := TCastleRectangleControl.Create(FreeAtStop);
  FBonusFlash.FullSize := true;
  FBonusFlash.Color := Vector4(1, 0.9, 0.3, 0);
  InsertFront(FBonusFlash);

  { Weapon sprite and muzzle flash. }
  FWeaponImage := TCastleImageControl.Create(FreeAtStop);
  FWeaponImage.SmoothScaling := false;
  FWeaponImage.Stretch := true;
  InsertFront(FWeaponImage);
  FFlashImage := TCastleImageControl.Create(FreeAtStop);
  FFlashImage.SmoothScaling := false;
  FFlashImage.Stretch := true;
  InsertFront(FFlashImage);

  FStatusBar := TDoomStatusBar.Create(FreeAtStop, Graphics);
  InsertFront(FStatusBar);

  FCrosshair := TCastleCrosshair.Create(FreeAtStop);
  InsertFront(FCrosshair);

  FMessageLabel := TCastleLabel.Create(FreeAtStop);
  FMessageLabel.Color := Vector4(1, 0.25, 0.1, 1);
  FMessageLabel.FontSize := 28;
  FMessageLabel.Anchor(hpLeft, 16);
  FMessageLabel.Anchor(vpTop, -12);
  FMessageLabel.Caption := '';
  InsertFront(FMessageLabel);

  FInfoLabel := TCastleLabel.Create(FreeAtStop);
  FInfoLabel.Color := Vector4(1, 1, 0.6, 0.9);
  FInfoLabel.FontSize := 18;
  FInfoLabel.Anchor(hpRight, -16);
  FInfoLabel.Anchor(vpTop, -12);
  InsertFront(FInfoLabel);

  FHelpLabel := TCastleLabel.Create(FreeAtStop);
  FHelpLabel.Color := Vector4(0.9, 0.9, 0.9, 0.9);
  FHelpLabel.FontSize := 18;
  FHelpLabel.Frame := true;
  FHelpLabel.Anchor(hpRight, -16);
  FHelpLabel.Anchor(vpTop, -44);
  FHelpLabel.Caption :=
    'WASD / arrows: move   Shift: run' + NL +
    'Mouse: look   LMB / Ctrl: fire' + NL +
    'E / Space: use (doors, switches)' + NL +
    '1-7, wheel: weapons' + NL +
    'Tab: automap   + / -: zoom   G: grid   I: reveal map' + NL +
    'F: fog (light diminishing)   M: mouse look' + NL +
    'N / P: next / previous map   J: music on/off' + NL +
    'F5: screenshot' + NL +
    'F8: Castle Game Engine inspector' + NL +
    'H: hide this help   Esc: menu';
  InsertFront(FHelpLabel);
  FHelpVisible := true;

  FIntermissionBack := TCastleRectangleControl.Create(FreeAtStop);
  FIntermissionBack.FullSize := true;
  FIntermissionBack.Color := Vector4(0, 0, 0, 0.75);
  FIntermissionBack.Exists := false;
  InsertFront(FIntermissionBack);
  FIntermissionLabel := TCastleLabel.Create(FreeAtStop);
  FIntermissionLabel.Color := Vector4(1, 0.3, 0.15, 1);
  FIntermissionLabel.FontSize := 36;
  FIntermissionLabel.Alignment := hpMiddle;
  FIntermissionLabel.Anchor(hpMiddle);
  FIntermissionLabel.Anchor(vpMiddle);
  FIntermissionLabel.Exists := false;
  InsertFront(FIntermissionLabel);
end;

procedure TViewPlay.SetupNavigation;
begin
  FNavigation.Gravity := true;
  FNavigation.PreferredHeight := PlayerViewHeight;
  FNavigation.Radius := 14;
  FNavigation.ClimbHeight := 24;
  { Doom: ~290 units/s walking, double when running (Shift). }
  FNavigation.MoveSpeed := 290;
  FNavigation.MoveHorizontalSpeed := 1;
  FNavigation.MoveVerticalSpeed := 1;
  FNavigation.HeadBobbing := 0.03;
  FNavigation.HeadBobbingTime := 0.45;
  FNavigation.FallSpeedStart := 180;
  FNavigation.FallSpeedIncrease := 12;
  FNavigation.GrowSpeed := 350;
  FNavigation.MouseLook := true;
  FNavigation.MouseLookHorizontalSensitivity := 0.15;
  FNavigation.MouseLookVerticalSensitivity := 0.15;
  FNavigation.MinAngleFromGravityUp := DegToRad(20);
  { No jumping / crouching / flying in Doom. }
  FNavigation.Input_Jump.MakeClear;
  FNavigation.Input_Crouch.MakeClear;
  FNavigation.Input_IncreasePreferredHeight.MakeClear;
  FNavigation.Input_DecreasePreferredHeight.MakeClear;
  FNavigation.Input_GravityUp.MakeClear;
  FNavigation.Input_MoveSpeedInc.MakeClear;
  FNavigation.Input_MoveSpeedDec.MakeClear;
  { WASD in addition to arrows. }
  FNavigation.Input_Forward.Assign(keyW, keyArrowUp);
  FNavigation.Input_Backward.Assign(keyS, keyArrowDown);
  FNavigation.Input_LeftStrafe.Assign(keyA, keyNone);
  FNavigation.Input_RightStrafe.Assign(keyD, keyNone);
  FNavigation.Input_LeftRotate.Assign(keyArrowLeft, keyNone);
  FNavigation.Input_RightRotate.Assign(keyArrowRight, keyNone);
  FNavigation.Input_Run.Assign(keyShift, keyNone);
end;

procedure TViewPlay.Start;
begin
  inherited;
  CreateUi;
  FWorld := TDoomWorld.Create(Wad, Graphics, Sounds, FViewport.Items);
  FAutomap.World := FWorld;
  if StartMapName = '' then
  begin
    if Wad.MapNames.Count > 0 then StartMapName := Wad.MapNames[0] else StartMapName := 'E1M1';
  end;
  StartMap(StartMapName, false);
end;

procedure TViewPlay.Stop;
begin
  FreeAndNil(FDemoSteps);
  FreeAndNil(FWorld);
  inherited;
end;

{ Scripted actions for automated testing (--demo "F:2,T:90,U,X,S,W:1").
  F:sec forward, B:sec backward, L:sec strafe left, R:sec strafe right,
  T:deg turn, A:deg absolute angle, G:x:y go to Doom map position,
  U use, X fire, S screenshot, W:sec wait, Q quit, E exit level, N next map,
  K give all weapons/ammo/keys, C:n select weapon n (1-9). }
procedure TViewPlay.RunDemo(const SecondsPassed: Single);
var
  Step, Cmd, Rest, KeyStr: String;
  Arg, Arg2: Single;
  P, Sec: Integer;
  K: TKey;
begin
  if FDemoSteps = nil then
  begin
    FDemoSteps := TStringList.Create;
    FDemoSteps.Delimiter := ',';
    FDemoSteps.StrictDelimiter := true;
    FDemoSteps.DelimitedText := AutoTestDemo;
    FDemoStep := 0;
    FDemoTime := 0;
  end;
  FNavigation.MouseLook := false;
  if FPendingMap <> '' then Exit;
  if FDemoStep >= FDemoSteps.Count then
  begin
    Application.Terminate;
    Exit;
  end;
  Step := Trim(FDemoSteps[FDemoStep]);
  P := Pos(':', Step);
  Arg2 := 0;
  if P > 0 then
  begin
    Cmd := UpperCase(Copy(Step, 1, P - 1));
    Rest := Copy(Step, P + 1, MaxInt);
    P := Pos(':', Rest);
    if P > 0 then
    begin
      Arg := StrToFloatDef(Copy(Rest, 1, P - 1), 0);
      Arg2 := StrToFloatDef(Copy(Rest, P + 1, MaxInt), 0);
    end else
      Arg := StrToFloatDef(Rest, 1);
  end else
  begin
    Cmd := UpperCase(Step);
    Arg := 0;
  end;
  if (Cmd = 'F') or (Cmd = 'B') or (Cmd = 'W') or (Cmd = 'L') or (Cmd = 'R') then
  begin
    { Simulate holding the movement key, so the real navigation
      (collisions, gravity) is exercised. }
    if Cmd = 'F' then K := keyW
    else if Cmd = 'B' then K := keyS
    else if Cmd = 'L' then K := keyA
    else if Cmd = 'R' then K := keyD
    else K := keyNone;
    if (K <> keyNone) and (FDemoTime = 0) then
      Container.Pressed.KeyDown(K, '');
    FDemoTime := FDemoTime + SecondsPassed;
    if FDemoTime >= Arg then
    begin
      if K <> keyNone then
        Container.Pressed.KeyUp(K, KeyStr);
      Inc(FDemoStep);
      FDemoTime := 0;
    end;
    Exit;
  end;
  FDemoTime := FDemoTime + SecondsPassed;
  if Cmd = 'T' then
    PlacePlayer(FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Z, DoomAngleFromCamera + Arg)
  else if Cmd = 'A' then
    PlacePlayer(FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Z, Arg)
  else if Cmd = 'G' then
  begin
    Sec := FWorld.Map.SectorAt(Arg, Arg2);
    if Sec >= 0 then
      PlacePlayer(Arg, Arg2, FWorld.Map.Sectors[Sec].FloorHeight, DoomAngleFromCamera);
  end
  else if Cmd = 'M' then
    FAutomap.Exists := not FAutomap.Exists
  else if Cmd = 'I' then
    FAutomap.ShowAll := not FAutomap.ShowAll
  else if Cmd = 'Z' then
    FAutomap.ZoomBy(Arg)
  else if Cmd = 'K' then
    FWorld.GiveAll
  else if Cmd = 'C' then
  begin
    case Round(Arg) of
      1: FWorld.SelectWeapon(wpFist);
      2: FWorld.SelectWeapon(wpPistol);
      3: FWorld.SelectWeapon(wpShotgun);
      4: FWorld.SelectWeapon(wpChaingun);
      5: FWorld.SelectWeapon(wpMissile);
      6: FWorld.SelectWeapon(wpPlasma);
      7: FWorld.SelectWeapon(wpBfg);
      8: FWorld.SelectWeapon(wpChainsaw);
      9: FWorld.SelectWeapon(wpSuperShotgun);
    end;
  end
  else if Cmd = 'U' then
  begin
    if FIntermission then FinishIntermission else FWorld.UseInFront;
  end
  else if Cmd = 'E' then
    FWorld.ExitRequested := true
  else if Cmd = 'N' then
  begin
    Sec := Wad.MapNames.IndexOf(FMapName) + 1;
    if Sec >= Wad.MapNames.Count then Sec := 0;
    StartMap(Wad.MapNames[Sec], true);
  end
  else if Cmd = 'X' then
    FWorld.FireWeapon
  else if Cmd = 'S' then
  begin
    Inc(FAutoTestShots);
    Application.MainWindow.SaveScreen(Format('%s_%d.png', [AutoTestPrefix, FAutoTestShots]));
    WritelnLog('AutoTest', 'Saved screenshot %d at %s (player %f %f %f)', [FAutoTestShots, FMapName,
      FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Z]);
  end else if Cmd = 'Q' then
    Application.Terminate;
  Inc(FDemoStep);
  FDemoTime := 0;
end;

procedure TViewPlay.StartMap(const MapName: String; const KeepInventory: Boolean);
begin
  { Show "Loading" for one frame before the (synchronous, possibly slow) load. }
  FPendingMap := MapName;
  FPendingKeepInventory := KeepInventory;
  FIntermission := true; { pauses Update until the map is in }
  FIntermissionBack.Exists := true;
  FIntermissionLabel.Exists := true;
  FIntermissionLabel.Caption := 'Loading ' + MapName + '...';
  if Music <> nil then Music.Stop;
  WaitForRenderAndCall({$ifdef FPC}@{$endif} LoadPendingMap);
end;

procedure TViewPlay.LoadPendingMap(Sender: TObject);
var
  MapName: String;
  KeepInventory: Boolean;
begin
  MapName := FPendingMap;
  KeepInventory := FPendingKeepInventory;
  FPendingMap := '';
  FMapName := MapName;
  FWorld.LoadMap(MapName, KeepInventory);
  PlacePlayer(FWorld.StartX, FWorld.StartY, FWorld.Player.Z, FWorld.StartAngle);
  FIntermission := false;
  FIntermissionBack.Exists := false;
  FIntermissionLabel.Exists := false;
  FLevelTime := 0;
  FWorld.ShowMessage(Format('%s  (%s)', [MapName, Wad.Description]));
  if Music <> nil then
    Music.Play(Music.LumpForMap(MapName));
end;

procedure TViewPlay.PlacePlayer(const DoomX, DoomY, DoomZ, AngleDeg: Single);
var
  Pos, Dir: TVector3;
begin
  Pos := DoomToCge(DoomX, DoomY, DoomZ + PlayerViewHeight);
  Dir := DoomToCge(Cos(DegToRad(AngleDeg)), Sin(DegToRad(AngleDeg)), 0);
  FViewport.Camera.SetView(Pos, Dir, Vector3(0, 1, 0));
  FLastCameraPos := Pos;
end;

function TViewPlay.DoomAngleFromCamera: Single;
var
  D: TVector3;
begin
  D := FViewport.Camera.Direction;
  Result := RadToDeg(ArcTan2(-D.Z, D.X));
end;

procedure TViewPlay.UpdateWeaponSprite(const SecondsPassed: Single);
var
  P: TPlayerState;
  SpriteName, FlashName: String;
  Img: TDoomImage;
  S, Speed, Bob, BobX, BobY: Single;
  W, H: Single;
  CamPos: TVector3;
begin
  P := FWorld.Player;
  W := FViewport.EffectiveWidth;
  H := FViewport.EffectiveHeight;
  S := H / 200;

  { Weapon bobbing from the horizontal camera speed. }
  CamPos := FViewport.Camera.Translation;
  if SecondsPassed > 0 then
    Speed := Sqrt(Sqr(CamPos.X - FLastCameraPos.X) + Sqr(CamPos.Z - FLastCameraPos.Z)) / SecondsPassed
  else
    Speed := 0;
  FLastCameraPos := CamPos;
  Bob := Min(16, Speed / 25);
  if P.AttackTics > 0 then Bob := 0;
  FBobPhase := FBobPhase + SecondsPassed * (2 * Pi / 1.8);
  BobX := Bob * Cos(FBobPhase);
  BobY := Bob * Abs(Sin(FBobPhase));

  SpriteName := FWorld.WeaponSprite(P.Weapon) + P.WeaponFrame + '0';
  Img := Graphics.Patch(SpriteName);
  if (Img <> nil) and not P.Dead then
  begin
    if SpriteName <> FWeaponImageName then
    begin
      FWeaponImage.Image := Img.Image.MakeCopy;
      FWeaponImageName := SpriteName;
    end;
    FWeaponImage.Exists := true;
    FWeaponImage.Width := Img.Width * S;
    FWeaponImage.Height := Img.Height * S;
    { Doom draws the weapon at screen x=160 (center), y=32 (WEAPONTOP) minus the offsets. }
    { Doom: x1 = centerx + (sx - 160 - leftoffset) * scale, with sx = 1. }
    FWeaponImage.Translation := Vector2(
      W / 2 + (1 - 160 - Img.LeftOffset + BobX) * S,
      H - (32 - Img.TopOffset + BobY) * S - Img.Height * S);
  end else
    FWeaponImage.Exists := false;

  FlashName := '';
  if (P.FlashFrame <> #0) and (FWorld.FlashSprite(P.Weapon) <> '') then
    FlashName := FWorld.FlashSprite(P.Weapon) + P.FlashFrame + '0';
  Img := nil;
  if FlashName <> '' then Img := Graphics.Patch(FlashName);
  if (Img <> nil) and not P.Dead then
  begin
    if FlashName <> FFlashImageName then
    begin
      FFlashImage.Image := Img.Image.MakeCopy;
      FFlashImageName := FlashName;
    end;
    FFlashImage.Exists := true;
    FFlashImage.Width := Img.Width * S;
    FFlashImage.Height := Img.Height * S;
    FFlashImage.Translation := Vector2(
      W / 2 + (1 - 160 - Img.LeftOffset + BobX) * S,
      H - (32 - Img.TopOffset + BobY) * S - Img.Height * S);
  end else
    FFlashImage.Exists := false;
end;

procedure TViewPlay.StartIntermission;
var
  P: TPlayerState;
begin
  FIntermission := true;
  FIntermissionTime := 0;
  P := FWorld.Player;
  FIntermissionBack.Exists := true;
  FIntermissionLabel.Exists := true;
  if Music <> nil then
    Music.Play(Music.IntermissionLump);
  FIntermissionLabel.Caption := Format(
    '%s FINISHED' + NL + NL +
    'KILLS  %d / %d' + NL +
    'ITEMS  %d / %d' + NL +
    'SECRETS  %d / %d' + NL +
    'TIME  %d:%2.2d' + NL + NL +
    'Press USE or fire to continue', [
    FMapName, P.Kills, P.TotalKills, P.Items, P.TotalItems, P.Secrets, P.TotalSecrets,
    Trunc(FLevelTime) div 60, Trunc(FLevelTime) mod 60]);
  FWorld.ExitRequested := false;
end;

procedure TViewPlay.FinishIntermission;
var
  Next: String;
begin
  Next := NextMapName(FMapName, FWorld.SecretExit, Wad.IsDoom2);
  if not Wad.HasLump(Next) then
    Next := Wad.MapNames[0];
  StartMap(Next, true);
end;

procedure TViewPlay.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  CamPos, CamDir: TVector3;
  Feet: TVector3;
  P: TPlayerState;
begin
  inherited;
  if FWorld = nil then Exit;

  if AutoTestDemo <> '' then
  begin
    RunDemo(SecondsPassed);
    FWorld.Player.Refire := false;
    if FWorld = nil then Exit;
  end;
  if FIntermission then
  begin
    FIntermissionTime := FIntermissionTime + SecondsPassed;
    FNavigation.Exists := false;
    Exit;
  end;
  FNavigation.Exists := not FWorld.Player.Dead;
  FLevelTime := FLevelTime + SecondsPassed;

  if AutoTestDemo <> '' then
  begin
    { handled above }
  end else
  if AutoTestPrefix <> '' then
  begin
    FNavigation.MouseLook := false;
    FAutoTestTime := FAutoTestTime + SecondsPassed;
    if FAutoTestTime > 1.5 then
    begin
      Inc(FAutoTestShots);
      Application.MainWindow.SaveScreen(Format('%s_%d.png', [AutoTestPrefix, FAutoTestShots]));
      WritelnLog('AutoTest', 'Saved screenshot %d at %s', [FAutoTestShots, FMapName]);
      FAutoTestTime := 0;
      if FAutoTestShots >= 4 then
      begin
        Application.Terminate;
        Exit;
      end;
      { Turn 90 degrees for the next shot. }
      PlacePlayer(FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Z, DoomAngleFromCamera + 90);
    end;
  end;

  CamPos := FViewport.Camera.Translation;
  CamDir := FViewport.Camera.Direction;
  Feet := CgeToDoom(CamPos);
  Feet.Z := Feet.Z - PlayerViewHeight;
  FWorld.Update(SecondsPassed, Feet.X, Feet.Y, Feet.Z, DoomAngleFromCamera, CamPos, CamDir);

  if FWorld.PlayerTeleported then
  begin
    FWorld.PlayerTeleported := false;
    PlacePlayer(FWorld.PlayerTeleportX, FWorld.PlayerTeleportY, FWorld.PlayerTeleportZ, FWorld.PlayerTeleportAngle);
  end;

  { Hold the fire button for automatic weapons. }
  if (buttonLeft in Container.MousePressed) or Container.Pressed.Items[keyCtrl] then
    FWorld.FireWeapon
  else
    FWorld.Player.Refire := false;

  P := FWorld.Player;
  FDamageFlash.Color := Vector4(1, 0, 0, P.DamageFlash * 0.55);
  FBonusFlash.Color := Vector4(1, 0.9, 0.3, P.BonusFlash * 0.25);
  if P.MessageTics > 0 then FMessageLabel.Caption := P.Message else FMessageLabel.Caption := '';
  FInfoLabel.Caption := Format('%s   FPS %s   %d things   fog %s', [
    FMapName, Container.Fps.ToString, FWorld.Actors.Count, BoolToStr(FFogEnabled, 'on', 'off')]);
  FStatusBar.Width := FViewport.EffectiveWidth;
  FStatusBar.Height := FViewport.EffectiveWidth / 10;
  FStatusBar.Refresh(FWorld, SecondsPassed);
  UpdateWeaponSprite(SecondsPassed);
  FCrosshair.Exists := FNavigation.MouseLook and not P.Dead and not FAutomap.Exists;

  if FWorld.ExitRequested then
    StartIntermission;
end;

function TViewPlay.Press(const Event: TInputPressRelease): Boolean;
var
  Idx: Integer;
  K: TKey;
begin
  Result := inherited;
  if Result then Exit;
  if FWorld = nil then Exit;

  if FIntermission then
  begin
    if FPendingMap <> '' then Exit;
    if (FIntermissionTime > 1) and (Event.IsKey(keyE) or Event.IsKey(keySpace) or
       Event.IsKey(keyEnter) or Event.IsMouseButton(buttonLeft)) then
    begin
      FinishIntermission;
      Exit(true);
    end;
    if Event.IsKey(keyEscape) then
    begin
      Container.View := ViewMenu;
      Exit(true);
    end;
    Exit;
  end;

  if Event.IsKey(keyE) or Event.IsKey(keySpace) then
  begin
    FWorld.UseInFront;
    Exit(true);
  end;
  if Event.IsMouseButton(buttonLeft) or Event.IsKey(keyCtrl) then
  begin
    FWorld.FireWeapon;
    Exit(true);
  end;
  if Event.EventType = itMouseWheel then
  begin
    if Event.MouseWheelScroll > 0 then FWorld.NextWeapon(1) else FWorld.NextWeapon(-1);
    Exit(true);
  end;
  for Idx := 1 to 7 do
  begin
    K := TKey(Ord(key0) + Idx);
    if Event.IsKey(K) then
    begin
      case Idx of
        1: if (wpChainsaw in FWorld.Player.Weapons) and (FWorld.Player.Weapon <> wpChainsaw) then
             FWorld.SelectWeapon(wpChainsaw) else FWorld.SelectWeapon(wpFist);
        2: FWorld.SelectWeapon(wpPistol);
        3: if (wpSuperShotgun in FWorld.Player.Weapons) and (FWorld.Player.Weapon = wpShotgun) then
             FWorld.SelectWeapon(wpSuperShotgun) else
           if wpShotgun in FWorld.Player.Weapons then FWorld.SelectWeapon(wpShotgun)
           else FWorld.SelectWeapon(wpSuperShotgun);
        4: FWorld.SelectWeapon(wpChaingun);
        5: FWorld.SelectWeapon(wpMissile);
        6: FWorld.SelectWeapon(wpPlasma);
        7: FWorld.SelectWeapon(wpBfg);
      end;
      Exit(true);
    end;
  end;
  if Event.IsKey(keyTab) then
  begin
    FAutomap.Exists := not FAutomap.Exists;
    Exit(true);
  end;
  if FAutomap.Exists then
  begin
    if Event.IsKey(keyPlus) or Event.IsKey(keyNumpadPlus) or (Event.IsKey(keyEqual)) then
    begin
      FAutomap.ZoomBy(1.25);
      Exit(true);
    end;
    if Event.IsKey(keyMinus) or Event.IsKey(keyNumpadMinus) then
    begin
      FAutomap.ZoomBy(1 / 1.25);
      Exit(true);
    end;
    if Event.IsKey(keyG) then
    begin
      FAutomap.Grid := not FAutomap.Grid;
      Exit(true);
    end;
    if Event.IsKey(keyI) then
    begin
      FAutomap.ShowAll := not FAutomap.ShowAll;
      Exit(true);
    end;
    if Event.EventType = itMouseWheel then
    begin
      if Event.MouseWheelScroll > 0 then FAutomap.ZoomBy(1.25) else FAutomap.ZoomBy(1 / 1.25);
      Exit(true);
    end;
  end;
  if Event.IsKey(keyF) then
  begin
    FFogEnabled := not FFogEnabled;
    if FFogEnabled then FViewport.Fog := FFog else FViewport.Fog := nil;
    Exit(true);
  end;
  if Event.IsKey(keyM) then
  begin
    FNavigation.MouseLook := not FNavigation.MouseLook;
    Exit(true);
  end;
  if Event.IsKey(keyJ) and (Music <> nil) then
  begin
    Music.Enabled := not Music.Enabled;
    FWorld.ShowMessage('Music ' + BoolToStr(Music.Enabled, 'on', 'off'));
    Exit(true);
  end;
  if Event.IsKey(keyH) then
  begin
    FHelpVisible := not FHelpVisible;
    FHelpLabel.Exists := FHelpVisible;
    Exit(true);
  end;
  if Event.IsKey(keyN) or Event.IsKey(keyP) then
  begin
    Idx := Wad.MapNames.IndexOf(FMapName);
    if Event.IsKey(keyN) then Inc(Idx) else Dec(Idx);
    if Idx < 0 then Idx := Wad.MapNames.Count - 1;
    if Idx >= Wad.MapNames.Count then Idx := 0;
    StartMap(Wad.MapNames[Idx], true);
    Exit(true);
  end;
  if Event.IsKey(keyF5) then
  begin
    FWorld.ShowMessage('Screenshot saved: ' + Container.SaveScreenToDefaultFile);
    Exit(true);
  end;
  if Event.IsKey(keyEscape) then
  begin
    Container.View := ViewMenu;
    Exit(true);
  end;
end;

end.
