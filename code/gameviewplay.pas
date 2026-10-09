{ The "playing" view: a TCastleViewport showing the Doom level, walk
  navigation with gravity and collisions, weapon/status bar HUD, and the
  input handling that drives TDoomWorld. }
unit GameViewPlay;

interface

uses Classes, SysUtils, FpJson,
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse,
  CastleViewport, CastleScene, CastleCameras, CastleTransform, CastleColors, CastleImages, CastleGLImages,
  DoomWad, DoomGraphics, DoomSound, DoomWorld, DoomHud, DoomMusic, DoomAutomap, DoomFont,
  DoomIntermission, DoomFinale, DoomDehacked, DoomWipe, DoomMenu;

type
  TViewPlay = class(TCastleView)
  strict private
    FViewport: TCastleViewport;
    FNavigation: TCastleWalkNavigation;
    FWorld: TDoomWorld;
    FStatusBar: TDoomStatusBar;
    FWeaponImage, FFlashImage: TCastleImageControl;
    FWeaponImageName, FFlashImageName: String;
    { The PLAYPAL palette shifts as a full-screen tint (see PaletteTint). }
    FPaletteFlash: TCastleRectangleControl;
    FPaletteTints: array [0..13] of TVector4;
    FInfoLabel, FHelpLabel: TCastleLabel;
    FMessageText, FLoadingText, FAutomapTitle: TDoomFontText;
    FIntermissionBack: TCastleRectangleControl;
    FIntermissionScreen: TDoomIntermission;
    FFinaleScreen: TDoomFinale;
    FWipe: TDoomWipe;
    FWipeTicAccum: Single;
    { The first frame after a melt starts (the level load, or a slow first
      frame in the browser) does not advance it. }
    FWipeSkipFrame: Boolean;
    { Old screen captured by StartMap, melted once the new map is in. }
    FPendingWipe: TDrawableImage;
    { Frame time spent in the world update, the status bar and the weapon
      sprite, logged as "PerfView:" every 10 s (see also TDoomWorld "Perf:"). }
    FPerfWorld, FPerfStatusBar, FPerfWeapon, FPerfClock: Double;
    FPerfFrames: Integer;
    FStrings: TDoomStrings;
    FIntermissionTicAccum: Single;
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
    { Saved game waiting to be applied by LoadPendingMap. }
    FPendingSave: TJSONObject;
    { Doom's menu over the game, and which key opened it (SlotMenu*:
      Esc / pointer lock lost = the main menu, F2 save, F3 load, F4 sound). }
    FSlotMenu: Integer;
    { The click that resumed or re-locked the mouse must not fire. }
    FSuppressFire: Boolean;
    FSlotMenuBack: TCastleRectangleControl;
    FSlotScreen: TDoomMenuScreen;
    FSlotTicAccum: Single;
    { The "Messages ON / OFF" message shows even with messages off. }
    FMessageAlways: Boolean;
    procedure SlotScreenAction(const Action: TDoomMenuAction);
    { Description: shown on the load page ('' = the map, kills
      and time). }
    procedure SaveGame(const Slot: Integer; const Description: String = '');
    function AutoSaveName: String;
    procedure LoadGame(const Slot: Integer);
    function LoadGameUrl(const Url: String): Boolean;
    procedure RestoreViewState(const State: TJSONObject);
    procedure OpenSlotMenu(const Mode: Integer);
    procedure OpenSoundMenu;
    { Change the sound (Row 0) or music (Row 1) volume by Delta steps. }
    procedure ChangeVolume(const Row, Delta: Integer);
    procedure CloseSlotMenu;
    procedure OpenPauseMenu;
    { Leave the pause menu and take the mouse again. On the web this must
      run inside a click or key event (a user gesture), or the browser
      refuses the pointer lock. }
    procedure ResumeFromPause;
    { The user ended the pointer lock (on the web: Esc, which the browser
      keeps for itself): pause like Doom's Esc menu would. }
    procedure PointerLockUserCancelled(Sender: TObject);
    procedure RunDemo(const SecondsPassed: Single);
    procedure LoadPendingMap(Sender: TObject);
    procedure CreateUi;
    procedure SetupNavigation;
    procedure PlacePlayer(const DoomX, DoomY, DoomZ, AngleDeg: Single);
    procedure UpdateWeaponSprite(const SecondsPassed: Single);
    procedure StartMap(const MapName: String; const KeepInventory: Boolean);
    procedure StartIntermission;
    procedure FinishIntermission;
    { Show the finale after FMapName; false when the map has none. }
    function StartFinale: Boolean;
    procedure FinishFinale;
    { The screen shown between levels (intermission or finale) was clicked. }
    procedure AccelerateScreen;
    { Capture what is on screen now (for the melt). }
    function CaptureScreen: TDrawableImage;
    procedure BeginWipe;
    function DoomAngleFromCamera: Single;
  public
    { Set before starting the view. }
    Wad: TDoomWad;
    Graphics: TDoomGraphics;
    Sounds: TDoomSounds;
    Music: TDoomMusic;
    { Set by the menu: load this saved game instead of StartMapName. }
    PendingSaveUrl: String;
    StartMapName: String;
    { Skill for a new game, 0..4 (Doom's sk_baby .. sk_nightmare). }
    Skill: Integer;
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    function Press(const Event: TInputPressRelease): Boolean; override;
  end;

var
  ViewPlay: TViewPlay;

{ Saved game location: slot 0 is the quick save, 1..6 the F2/F3 slots.
  castle-config: is the user config directory on desktop (next to the log);
  in the browser GameSaveStorage keeps the text in localStorage under this URL. }
function SaveSlotUrl(const Slot: Integer): String;
{ Read a saved game, nil when missing or unreadable. Caller owns the result. }
function ReadSaveFile(const Url: String): TJSONObject;

implementation

uses Math, JsonParser,
  CastleLog, CastleUtils, CastleStringUtils, CastleWindow, CastleSoundEngine, CastleRenderOptions,
  CastleDownload, DoomActors,
  CastleUriUtils, X3DNodes, CastleRectangles, CastleTimeUtils, CastleRenderContext,
  DoomGeometry, DoomMap, DoomLighting,
  GameViewMenu, GameSaveStorage, GameSettings;

type
  { Opens TCastleNavigation.Move (protected) to push the player. }
  TWalkNavigationAccess = class(TCastleWalkNavigation);

const
  SlotMenuNone = 0;
  SlotMenuSave = 1;
  SlotMenuLoad = 2;
  { F4: Doom's sound volume menu (sound effects, music). }
  SlotMenuSound = 3;
  { Esc, or the browser cancelling pointer lock (its Esc): the game waits
    for a click / Enter (resume) or another Esc (title menu). }
  SlotMenuPause = 4;
  SaveSlots = 6;

function SaveSlotUrl(const Slot: Integer): String;
begin
  if Slot <= 0 then
    Result := 'castle-config:/quicksave.json'
  else
    Result := Format('castle-config:/save%d.json', [Slot]);
end;

function ReadSaveFile(const Url: String): TJSONObject;
var
  Text: String;
  D: TJSONData;
begin
  Result := nil;
  if not SaveStorageRead(Url, Text) then Exit; { no such save }
  try
    D := GetJSON(Text);
    if D is TJSONObject then
      Result := TJSONObject(D)
    else
      FreeAndNil(D);
  except
    on E: Exception do
      WritelnWarning('Save', 'Cannot read %s: %s', [Url, E.Message]);
  end;
end;

procedure WriteSaveFile(const Url: String; const J: TJSONObject);
begin
  { Without whitespace: about 15% smaller (matters for localStorage). }
  SaveStorageWrite(Url, J.FormatJSON(AsCompressedJSON));
end;

constructor TViewPlay.Create(AOwner: TComponent);
begin
  inherited;
  Skill := 2;
end;

procedure TViewPlay.CreateUi;
var
  Camera: TCastleCamera;
  I: Integer;
  Tint: TVector3;
  TintAmount: Single;
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

  { The subclass only opens Move for the knockback. }
  FNavigation := TWalkNavigationAccess.Create(FreeAtStop);
  FViewport.InsertFront(FNavigation);
  SetupNavigation;

  { Automap, drawn over the 3D view and under the HUD. }
  FAutomap := TDoomAutomap.Create(FreeAtStop);
  FAutomap.Exists := false;
  InsertFront(FAutomap);

  { Screen flashes. }
  FPaletteFlash := TCastleRectangleControl.Create(FreeAtStop);
  FPaletteFlash.FullSize := true;
  FPaletteFlash.Color := Vector4(0, 0, 0, 0);
  InsertFront(FPaletteFlash);
  { Every PLAYPAL palette is palette 0 blended towards one colour, so an
    alpha-blended rectangle of that colour reproduces it exactly. }
  for I := 0 to High(FPaletteTints) do
    if (I = 0) or not Wad.PaletteTint(I, Tint, TintAmount) then
      FPaletteTints[I] := Vector4(0, 0, 0, 0)
    else
      FPaletteTints[I] := Vector4(Tint, TintAmount);

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

  { Player messages in Doom's own STCFN font. }
  FMessageText := TDoomFontText.Create(FreeAtStop);
  FMessageText.Graphics := Graphics;
  FMessageText.Anchor(hpLeft, 8);
  FMessageText.Anchor(vpTop, -8);
  FMessageText.Exists := false;
  InsertFront(FMessageText);

  { The level title at the bottom left of the automap (AM_drawTitle). }
  FAutomapTitle := TDoomFontText.Create(FreeAtStop);
  FAutomapTitle.Graphics := Graphics;
  FAutomapTitle.Anchor(hpLeft, 8);
  FAutomapTitle.Exists := false;
  InsertFront(FAutomapTitle);

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
    'F: light diminishing on/off   M: mouse look' + NL +
    'N / P: next / previous map   J: music on/off   F4: volume' + NL +
    'F2 / F3: save / load   F6 / F9: quick save / load' + NL +
    'F5: screenshot   F1: Read This! (title menu)' + NL +
    'F8: Castle Game Engine inspector' + NL +
    'H: hide this help   Esc: menu (pauses; Esc again resumes)';
  InsertFront(FHelpLabel);
  FHelpVisible := true;

  FIntermissionBack := TCastleRectangleControl.Create(FreeAtStop);
  FIntermissionBack.FullSize := true;
  FIntermissionBack.Color := Vector4(0, 0, 0, 1);
  FIntermissionBack.Exists := false;
  InsertFront(FIntermissionBack);
  { The real Doom intermission screen (320x200, kept 4:3 and centred). }
  FIntermissionScreen := TDoomIntermission.Create(FreeAtStop);
  FIntermissionScreen.Anchor(hpMiddle);
  FIntermissionScreen.Anchor(vpMiddle);
  FIntermissionScreen.Exists := false;
  InsertFront(FIntermissionScreen);

  FFinaleScreen := TDoomFinale.Create(FreeAtStop);
  FFinaleScreen.Anchor(hpMiddle);
  FFinaleScreen.Anchor(vpMiddle);
  FFinaleScreen.Exists := false;
  InsertFront(FFinaleScreen);
  FLoadingText := TDoomFontText.Create(FreeAtStop);
  FLoadingText.Graphics := Graphics;
  FLoadingText.Anchor(hpMiddle);
  FLoadingText.Anchor(vpMiddle);
  FLoadingText.Exists := false;
  InsertFront(FLoadingText);

  { Doom's menu over the game (Esc, F2, F3, F4) on a dark panel. }
  FSlotMenuBack := TCastleRectangleControl.Create(FreeAtStop);
  FSlotMenuBack.FullSize := true;
  FSlotMenuBack.Color := Vector4(0, 0, 0, 0.7);
  FSlotMenuBack.Exists := false;
  InsertFront(FSlotMenuBack);
  FSlotScreen := TDoomMenuScreen.Create(FreeAtStop);
  FSlotScreen.Overlay := true;
  FSlotScreen.Anchor(hpMiddle);
  FSlotScreen.Anchor(vpMiddle);
  FSlotScreen.OnAction := {$ifdef FPC}@{$endif} SlotScreenAction;
  FSlotScreen.MouseEnabled := AutoTestPrefix = '';
  FSlotScreen.Exists := false;
  InsertFront(FSlotScreen);

  { The screen melt, above everything. }
  FWipe := TDoomWipe.Create(FreeAtStop);
  FWipe.Exists := false;
  InsertFront(FWipe);
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
  FNavigation.MouseLook := Settings.MouseLook;
  FNavigation.MouseLookHorizontalSensitivity := MouseLookSensitivity;
  FNavigation.MouseLookVerticalSensitivity := MouseLookSensitivity;
  WritelnLog('MouseLook', 'Sensitivity %d: %.4f degrees a pixel', [
    Settings.MouseSensitivity, RadToDeg(MouseLookSensitivity)]);
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
var
  Url: String;
begin
  inherited;
  CreateUi;
  Container.PointerLock.AddUserCancelledListener({$ifdef FPC}@{$endif} PointerLockUserCancelled);
  FWorld := TDoomWorld.Create(Wad, Graphics, Sounds, FViewport.Items);
  FWorld.Skill := Skill;
  FreeAndNil(FStrings);
  FStrings := TDoomStrings.Create(Wad);
  FWorld.Strings := FStrings;
  WritelnLog('Skill', 'Skill %d', [Skill + 1]);
  FAutomap.World := FWorld;
  if StartMapName = '' then
  begin
    if Wad.MapNames.Count > 0 then StartMapName := Wad.MapNames[0] else StartMapName := 'E1M1';
  end;
  if PendingSaveUrl <> '' then
  begin
    Url := PendingSaveUrl;
    PendingSaveUrl := '';
    if LoadGameUrl(Url) then Exit;
  end;
  StartMap(StartMapName, false);
end;

procedure TViewPlay.Stop;
begin
  Container.PointerLock.RemoveUserCancelledListener({$ifdef FPC}@{$endif} PointerLockUserCancelled);
  FreeAndNil(FPendingSave);
  FSlotMenu := SlotMenuNone;
  FreeAndNil(FDemoSteps);
  FreeAndNil(FWorld);
  FreeAndNil(FStrings);
  FreeAndNil(FPendingWipe);
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
  Arg, Arg2, LookAngle, LookPitch: Single;
  P, Sec: Integer;
  K: TKey;
  SpawnedActor: TDoomActor;
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
  else if Cmd = 'LOOK' then
  begin
    { Pitch the view by Arg degrees (positive up), keeping the angle. }
    LookAngle := DegToRad(DoomAngleFromCamera);
    LookPitch := DegToRad(Arg);
    FViewport.Camera.SetView(FViewport.Camera.Translation,
      DoomToCge(Cos(LookAngle) * Cos(LookPitch), Sin(LookAngle) * Cos(LookPitch), Sin(LookPitch)),
      DoomToCge(-Cos(LookAngle) * Sin(LookPitch), -Sin(LookAngle) * Sin(LookPitch), Cos(LookPitch)));
  end
  else if Cmd = 'VOL' then
  begin
    { VOL:sfx:music sets both volumes (0..15) like the F4 menu. }
    ChangeVolume(0, Round(Arg) - Settings.SfxVolume);
    ChangeVolume(1, Round(Arg2) - Settings.MusicVolume);
  end
  else if Cmd = 'SOUNDMENU' then
    OpenSoundMenu
  else if Cmd = 'LINE' then
    FWorld.DebugActivateLine(Round(Arg), Round(Arg2))
  else if Cmd = 'SHOTS' then
    FWorld.DebugShots := true
  else if Cmd = 'SIGHT' then
    FWorld.DebugSight
  else if Cmd = 'INVIS' then
    FWorld.Player.InvisibleTics := 60 * 35
  else if Cmd = 'INVUL' then
    FWorld.Player.InvulnerableTics := Iff(Arg > 0, Round(Arg), 30 * 35)
  else if Cmd = 'AMP' then
    FWorld.Player.LightAmpTics := Iff(Arg > 0, Round(Arg), 120 * 35)
  else if Cmd = 'DIM' then
    DoomLightingInstance.Diminish := not DoomLightingInstance.Diminish
  else if Cmd = 'PALMAP' then
    DoomLightingInstance.PaletteMapped := not DoomLightingInstance.PaletteMapped
  else if Cmd = 'K' then
    FWorld.GiveAll
  else if Cmd = 'MENU' then
  begin
    if Round(Arg) = 0 then CloseSlotMenu else OpenSlotMenu(Round(Arg));
  end
  else if Cmd = 'SAVE' then
    SaveGame(Round(Arg))
  else if Cmd = 'LOAD' then
    LoadGame(Round(Arg))
  else if Cmd = 'Y' then
    FWorld.DebugGod
  else if Cmd = 'P' then
    FWorld.DebugSpawn(Round(Arg), Arg2)
  else if Cmd = 'CORPSE' then
  begin
    { CORPSE:type:dist spawns a monster and kills it in the same frame (a
      corpse exactly there; P then D lets it walk a few tics first). }
    SpawnedActor := FWorld.DebugSpawn(Round(Arg), Arg2);
    if SpawnedActor <> nil then
      FWorld.DamageActor(SpawnedActor, 100000, SpawnedActor.DoomX, SpawnedActor.DoomY, SpawnedActor.DoomZ + 32);
  end
  else if Cmd = 'V' then
    FWorld.DebugInfight
  else if Cmd = 'D' then
    FWorld.DebugKillAll
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
    if FIntermission then
      AccelerateScreen
    else
      FWorld.UseInFront;
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
  else if Cmd = 'TYPE' then
  begin
    { TYPE:text types characters (a save name); ',' cannot be in it. }
    for P := 1 to Length(Rest) do
      Press(InputKey(TVector2.Zero, keyNone, Rest[P], []));
  end
  else if Cmd = 'KEY' then
  begin
    { KEY:name presses a key through Press like the keyboard would
      (menus: UP, DOWN, LEFT, RIGHT, ENTER, ESCAPE, F1..F4). }
    Rest := UpperCase(Rest);
    if Rest = 'UP' then K := keyArrowUp
    else if Rest = 'DOWN' then K := keyArrowDown
    else if Rest = 'LEFT' then K := keyArrowLeft
    else if Rest = 'RIGHT' then K := keyArrowRight
    else if Rest = 'ENTER' then K := keyEnter
    else if Rest = 'ESCAPE' then K := keyEscape
    else if Rest = 'BACKSPACE' then K := keyBackSpace
    else if Rest = 'F1' then K := keyF1
    else if Rest = 'F2' then K := keyF2
    else if Rest = 'F3' then K := keyF3
    else if Rest = 'F4' then K := keyF4
    else K := keyNone;
    if K <> keyNone then
      Press(InputKey(TVector2.Zero, K, '', []));
  end
  else if Cmd = 'UNLOCK' then
    { What the browser's Esc does: the pointer lock is cancelled. }
    PointerLockUserCancelled(nil)
  else if Cmd = 'RESUME' then
    ResumeFromPause
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
  { The melt goes from what is on screen now (intermission, finale text) to
    the new level; not on the first map of the session (nothing to melt). }
  FreeAndNil(FPendingWipe);
  if (FWorld <> nil) and FWorld.MapLoaded then
    FPendingWipe := CaptureScreen;
  { Show "Loading" for one frame before the (synchronous, possibly slow) load. }
  FPendingMap := MapName;
  FPendingKeepInventory := KeepInventory;
  FIntermission := true; { pauses Update until the map is in }
  FIntermissionBack.Exists := true;
  FIntermissionScreen.Exists := false;
  FFinaleScreen.Exists := false;
  FLoadingText.SetScale(Max(1, EffectiveHeight / 200));
  FLoadingText.SetText('LOADING ' + MapName + '...');
  if Music <> nil then Music.Stop;
  WaitForRenderAndCall({$ifdef FPC}@{$endif} LoadPendingMap);
end;

procedure TViewPlay.LoadPendingMap(Sender: TObject);
var
  MapName: String;
  KeepInventory, Restored: Boolean;
begin
  MapName := FPendingMap;
  KeepInventory := FPendingKeepInventory;
  FPendingMap := '';
  FMapName := MapName;
  Restored := false;
  if FPendingSave <> nil then
  begin
    FWorld.LoadState(FPendingSave);
    RestoreViewState(FPendingSave);
    FreeAndNil(FPendingSave);
    Restored := true;
  end else
  begin
    FWorld.LoadMap(MapName, KeepInventory);
    PlacePlayer(FWorld.StartX, FWorld.StartY, FWorld.Player.Z, FWorld.StartAngle);
    FLevelTime := 0;
  end;
  FIntermission := false;
  FIntermissionBack.Exists := false;
  FIntermissionScreen.Exists := false;
  FFinaleScreen.Exists := false;
  FLoadingText.Exists := false;
  if FPendingWipe <> nil then
  begin
    FWipe.Start(FPendingWipe); { the wipe owns it now }
    FPendingWipe := nil;
    FWipeTicAccum := 0;
    FWipeSkipFrame := true;
  end;
  if Restored then
    FWorld.ShowMessage('Game loaded.')
  else
    FWorld.ShowMessage(FStrings.LevelName(MapName, Wad.IsDoom2));
  if Music <> nil then
    Music.Play(Music.LumpForMap(MapName));
end;

procedure TViewPlay.RestoreViewState(const State: TJSONObject);
var
  D: TJSONData;
  C: TJSONArray;
  Pos, Dir, Up: TVector3;
begin
  FLevelTime := State.Get('levelTime', 0.0);
  D := State.Find('camera');
  if (D is TJSONArray) and (TJSONArray(D).Count = 9) then
  begin
    C := TJSONArray(D);
    Pos := Vector3(C.Floats[0], C.Floats[1], C.Floats[2]);
    Dir := Vector3(C.Floats[3], C.Floats[4], C.Floats[5]);
    Up := Vector3(C.Floats[6], C.Floats[7], C.Floats[8]);
    FViewport.Camera.SetView(Pos, Dir, Up);
    FLastCameraPos := Pos;
  end else
    PlacePlayer(FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Z, FWorld.Player.Angle);
end;

function TViewPlay.AutoSaveName: String;
var
  P: TPlayerState;
begin
  P := FWorld.Player;
  Result := Format('%s  %d/%d  %d:%2.2d', [FMapName, P.Kills, P.TotalKills,
    Trunc(FLevelTime) div 60, Trunc(FLevelTime) mod 60]);
end;

procedure TViewPlay.SaveGame(const Slot: Integer; const Description: String);
var
  J: TJSONObject;
  C, Wads: TJSONArray;
  Pos, Dir, Up: TVector3;
  I: Integer;
  P: TPlayerState;
begin
  if (FWorld = nil) or (not FWorld.MapLoaded) or FIntermission or FWorld.Player.Dead or (FPendingMap <> '') then
  begin
    if FWorld <> nil then FWorld.ShowMessage('You can''t save now.');
    Exit;
  end;
  J := FWorld.SaveState;
  try
    FViewport.Camera.GetView(Pos, Dir, Up);
    C := TJSONArray.Create;
    for I := 0 to 2 do C.Add(Double(Pos[I]));
    for I := 0 to 2 do C.Add(Double(Dir[I]));
    for I := 0 to 2 do C.Add(Double(Up[I]));
    J.Add('camera', C);
    J.Add('levelTime', Double(FLevelTime));
    Wads := TJSONArray.Create;
    for I := 0 to Wad.FileUrls.Count - 1 do
      Wads.Add(Wad.FileUrls[I]);
    J.Add('wads', Wads);
    if Description <> '' then
      J.Add('description', Description)
    else
      J.Add('description', AutoSaveName);
    J.Add('saved', FormatDateTime('yyyy-mm-dd hh:nn', Now));
    try
      WriteSaveFile(SaveSlotUrl(Slot), J);
      WritelnLog('Save', 'Saved %s to %s (%s)', [FMapName, SaveSlotUrl(Slot), SaveStorageName]);
      FWorld.ShowMessage('Game saved.');
    except
      on E: Exception do
      begin
        WritelnWarning('Save', 'Saving failed: %s', [E.Message]);
        FWorld.ShowMessage('Save failed.');
      end;
    end;
  finally
    FreeAndNil(J);
  end;
end;

procedure TViewPlay.LoadGame(const Slot: Integer);
begin
  if FPendingMap <> '' then Exit;
  if not LoadGameUrl(SaveSlotUrl(Slot)) then
    if (FWorld <> nil) and FWorld.MapLoaded and (FWorld.Player.Message = '') then
      FWorld.ShowMessage('No saved game there.');
end;

function TViewPlay.LoadGameUrl(const Url: String): Boolean;
var
  J: TJSONObject;
  D: TJSONData;
  Saved: TStringList;
  I: Integer;
begin
  Result := false;
  J := ReadSaveFile(Url);
  if J = nil then Exit;
  { A save only makes sense with the same IWAD + PWADs. }
  Saved := TStringList.Create;
  try
    D := J.Find('wads');
    if D is TJSONArray then
      for I := 0 to TJSONArray(D).Count - 1 do
        Saved.Add(TJSONArray(D).Strings[I]);
    if Saved.Text <> Wad.FileUrls.Text then
    begin
      WritelnWarning('Save', '%s was saved with %s, current WADs are %s', [Url, Saved.CommaText, Wad.FileUrls.CommaText]);
      if (FWorld <> nil) and FWorld.MapLoaded then
        FWorld.ShowMessage('That save uses other WADs.');
      FreeAndNil(J);
      Exit;
    end;
  finally
    FreeAndNil(Saved);
  end;
  FreeAndNil(FPendingSave);
  FPendingSave := J;
  WritelnLog('Save', 'Loading %s (%s)', [Url, J.Get('description', '')]);
  StartMap(J.Get('map', ''), false);
  Result := true;
end;

procedure TViewPlay.OpenSlotMenu(const Mode: Integer);
var
  I, E, Episodes: Integer;
  J: TJSONObject;
begin
  if (FWorld = nil) or not FWorld.MapLoaded or FIntermission then Exit;
  FSlotMenu := Mode;
  { Doom's menu over the game, opened on the page for the key: Esc the
    main menu, F2 / F3 the save / load slots (with their descriptions and
    the time), F4 the sound volume. }
  FSlotScreen.InGame := true;
  { Episodes like the title menu: ExM1 maps with an M_EPIx picture. }
  Episodes := 0;
  for E := 1 to 4 do
    if (Wad.MapNames.IndexOf(Format('E%dM1', [E])) >= 0) and (Graphics.Patch(Format('M_EPI%d', [E])) <> nil) then
      Episodes := E;
  FSlotScreen.Setup(Graphics, Sounds, Episodes, FStrings);
  FSlotScreen.SfxVolume := Settings.SfxVolume;
  FSlotScreen.MusicVolume := Settings.MusicVolume;
  FSlotScreen.MouseSensitivity := Settings.MouseSensitivity;
  FSlotScreen.MessagesOn := Settings.ShowMessages;
  FSlotScreen.Skill := Skill;
  FSlotScreen.DefaultSaveName := AutoSaveName;
  for I := 1 to SaveSlots do
  begin
    J := ReadSaveFile(SaveSlotUrl(I));
    if J = nil then
      FSlotScreen.SetSlot(I, '')
    else
    begin
      { The time of day after the description ("2026-10-09 17:26"). }
      FSlotScreen.SetSlot(I, J.Get('description', '?') + ' ' + Copy(J.Get('saved', ''), 12, 5),
        J.Get('description', '?'));
      FreeAndNil(J);
    end;
  end;
  FSlotScreen.SetMenuActive(true);
  case Mode of
    SlotMenuSave: FSlotScreen.EntryPage := mpSave;
    SlotMenuLoad: FSlotScreen.EntryPage := mpLoad;
    SlotMenuSound: FSlotScreen.EntryPage := mpSound;
    else FSlotScreen.EntryPage := mpMain;
  end;
  FSlotScreen.OpenPage(FSlotScreen.EntryPage);
  if Sounds <> nil then Sounds.Play('DSSWTCHN');
  FSlotScreen.Exists := true;
  FSlotMenuBack.Exists := true;
end;

procedure TViewPlay.SlotScreenAction(const Action: TDoomMenuAction);
var
  Slot: Integer;
  WasOn: Boolean;
begin
  Slot := FSlotScreen.Slot;
  case Action of
    maSaveSlot:
      begin
        ResumeFromPause;
        SaveGame(Slot, FSlotScreen.SaveName);
      end;
    maLoadSlot:
      begin
        ResumeFromPause;
        LoadGame(Slot);
      end;
    maClose:
      ResumeFromPause;
    maSettings:
      begin
        { The options and sound pages' sliders and toggle, applied at once
          and remembered. }
        WasOn := Settings.ShowMessages;
        if FSlotScreen.SfxVolume <> Settings.SfxVolume then
          ChangeVolume(0, FSlotScreen.SfxVolume - Settings.SfxVolume);
        if FSlotScreen.MusicVolume <> Settings.MusicVolume then
          ChangeVolume(1, FSlotScreen.MusicVolume - Settings.MusicVolume);
        Settings.MouseSensitivity := FSlotScreen.MouseSensitivity;
        FNavigation.MouseLookHorizontalSensitivity := MouseLookSensitivity;
        FNavigation.MouseLookVerticalSensitivity := MouseLookSensitivity;
        Settings.ShowMessages := FSlotScreen.MessagesOn;
        SaveSettings;
        if Settings.ShowMessages <> WasOn then
        begin
          { M_ChangeMessages: this one shows even when turning them off. }
          if Settings.ShowMessages then
            FWorld.ShowMessage(FWorld.Text('MSGON', 'Messages ON'))
          else
            FWorld.ShowMessage(FWorld.Text('MSGOFF', 'Messages OFF'));
          FMessageAlways := true;
        end;
      end;
    maEndGame:
      { M_EndGame: back to the title. }
      Container.View := ViewMenu;
    maQuit:
      { M_QuitDOOM; in the browser there is nothing to quit to, so the
        title instead of a blank page. }
      {$ifdef WASI}
      Container.View := ViewMenu;
      {$else}
      Application.Terminate;
      {$endif}
    maNewGame:
      begin
        ViewMenu.RequestNewGame(FSlotScreen.Episode, FSlotScreen.Skill);
        Container.View := ViewMenu;
      end;
    else ;
  end;
end;

procedure TViewPlay.OpenSoundMenu;
begin
  OpenSlotMenu(SlotMenuSound);
end;

procedure TViewPlay.ChangeVolume(const Row, Delta: Integer);
begin
  if Row = 0 then
  begin
    Settings.SfxVolume := Clamped(Settings.SfxVolume + Delta, 0, MaxVolume);
    if Sounds <> nil then Sounds.Volume := SfxGain;
    { Doom plays a sound so you hear the new level. }
    if Sounds <> nil then Sounds.Play('DSPISTOL');
  end else
  begin
    Settings.MusicVolume := Clamped(Settings.MusicVolume + Delta, 0, MaxVolume);
    if Music <> nil then Music.Volume := MusicGain;
  end;
  SaveSettings;
end;

procedure TViewPlay.OpenPauseMenu;
begin
  { Doom's Esc: the main menu over the paused game. }
  OpenSlotMenu(SlotMenuPause);
end;

procedure TViewPlay.ResumeFromPause;
begin
  CloseSlotMenu;
  FNavigation.Exists := not FWorld.Player.Dead;
  if AutoTestPrefix = '' then
    FNavigation.MouseLook := Settings.MouseLook;
  FSuppressFire := true;
end;

procedure TViewPlay.PointerLockUserCancelled(Sender: TObject);
begin
  WritelnLog('PointerLock', 'Cancelled by the user, pausing');
  if (Container.View = Self) and (FSlotMenu = SlotMenuNone) then
    OpenPauseMenu;
end;

procedure TViewPlay.CloseSlotMenu;
begin
  FSlotMenu := SlotMenuNone;
  FSlotMenuBack.Exists := false;
  FSlotScreen.Exists := false;
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

{ A copy of a weapon sprite in Doom's inverted invulnerability colormap:
  the same grey 1 - luma as the world's shader (DoomLighting). }
function InvertedCopy(const Source: TCastleImage): TCastleImage;
var
  X, Y: Integer;
  C: TCastleColor;
  G: Single;
begin
  Result := Source.MakeCopy;
  for Y := 0 to Result.Height - 1 do
    for X := 0 to Result.Width - 1 do
    begin
      C := Result.Colors[X, Y, 0];
      G := 1 - (C.X * 0.299 + C.Y * 0.587 + C.Z * 0.114);
      Result.Colors[X, Y, 0] := Vector4(G, G, G, C.W);
    end;
end;

{ Where the fuzz pattern starts in a tic: Doom's fuzzpos never resets, so
  each frame starts somewhere else. }
function FuzzPhaseOfTic(const Tic: Int64): Integer;
begin
  Result := (Tic * 23) mod Length(FuzzOffsets);
end;

{ R_DrawFuzzColumn for the player's weapon (partial invisibility): every
  opaque pixel becomes black, more or less opaque by Doom's fuzzoffset
  pattern, column after column from the top like fuzzpos. }
function FuzzCopy(const Source: TCastleImage; const Phase: Integer): TCastleImage;
var
  X, Y, I: Integer;
  C: TCastleColor;
  A: Single;
begin
  Result := Source.MakeCopy;
  I := Phase;
  for X := 0 to Result.Width - 1 do
    for Y := Result.Height - 1 downto 0 do
    begin
      C := Result.Colors[X, Y, 0];
      if C.W > 0.5 then
      begin
        if FuzzOffsets[I] > 0 then A := FuzzAlphaPlus else A := FuzzAlphaMinus;
        I := (I + 1) mod Length(FuzzOffsets);
      end else
        A := 0;
      Result.Colors[X, Y, 0] := Vector4(0, 0, 0, A);
    end;
end;

procedure TViewPlay.UpdateWeaponSprite(const SecondsPassed: Single);
var
  P: TPlayerState;
  SpriteName, FlashName: String;
  Img: TDoomImage;
  S, Speed, Bob, BobX, BobY: Single;
  W, H, Bright: Single;
  Inverted, Fuzzy, Mapped: Boolean;
  WeaponSuffix, FlashSuffix: String;
  WeaponLevel, FlashLevel: Integer;
  CamPos: TVector3;
  Sec, Light: Integer;
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
  if (P.AttackTics > 0) or (P.WeaponSwitch <> 0) then Bob := 0;
  FBobPhase := FBobPhase + SecondsPassed * (2 * Pi / 1.8);
  BobX := Bob * Cos(FBobPhase);
  BobY := Bob * Abs(Sin(FBobPhase));

  { Partial invisibility: the weapon is drawn as fuzz too, blinking back to
    normal in the last seconds (st_stuff / r_things: > 4*32 tics or bit 8). }
  Fuzzy := (P.InvisibleTics > 4 * 32) or ((P.InvisibleTics and 8) <> 0);
  { R_DrawPSprite: the weapon is lit like a sprite at the nearest scale
    (spritelights[MAXLIGHTSCALE - 1]) of the player's sector, the flash is
    full bright; a fixed colormap (invulnerability's inverted row 32, the
    visor's row 1) applies to both. Fuzz wins over the fixed colormap. }
  Sec := FWorld.Map.SectorAt(P.X, P.Y);
  if Sec >= 0 then
    Light := FWorld.Map.Sectors[Sec].LightLevel
  else
    Light := 255;
  if FWorld.FixedColormap >= 0 then
  begin
    WeaponLevel := FWorld.FixedColormap;
    FlashLevel := FWorld.FixedColormap;
  end else
  begin
    WeaponLevel := DoomLightingInstance.WeaponColormap(Light);
    FlashLevel := 0;
  end;
  Mapped := DoomLightingInstance.PaletteMapped and not Fuzzy;
  if Fuzzy or Mapped then
  begin
    { The colours are in the image (fuzz specks or COLORMAP rows). }
    FWeaponImage.Color := White;
    FFlashImage.Color := White;
  end else
  begin
    { Without the palette mapping: a colour multiplier, and inverted
      copies for invulnerability (not a multiplier). }
    if WeaponLevel = InverseColormap then
      Bright := 1
    else
      Bright := TDoomLighting.ColormapBrightness(WeaponLevel);
    FWeaponImage.Color := Vector4(Bright, Bright, Bright, 1);
    if FlashLevel = InverseColormap then
      Bright := 1
    else
      Bright := TDoomLighting.ColormapBrightness(FlashLevel);
    FFlashImage.Color := Vector4(Bright, Bright, Bright, 1);
  end;
  Inverted := (FWorld.FixedColormap = InverseColormap) and not Fuzzy and not Mapped;
  if Fuzzy then
  begin
    WeaponSuffix := '/fuzz' + IntToStr(FuzzPhaseOfTic(FWorld.Tic));
    FlashSuffix := WeaponSuffix;
  end else
  if Mapped then
  begin
    WeaponSuffix := '/colormap' + IntToStr(WeaponLevel);
    FlashSuffix := '/colormap' + IntToStr(FlashLevel);
  end else
  if Inverted then
  begin
    WeaponSuffix := '/inverse';
    FlashSuffix := WeaponSuffix;
  end else
  begin
    WeaponSuffix := '';
    FlashSuffix := '';
  end;

  SpriteName := FWorld.WeaponSprite(P.Weapon) + P.WeaponFrame + '0';
  Img := Graphics.Patch(SpriteName);
  if (Img <> nil) and not P.Dead and not FAutomap.Exists then
  begin
    if SpriteName + WeaponSuffix <> FWeaponImageName then
    begin
      if Fuzzy then
        FWeaponImage.Image := FuzzCopy(Img.Image, FuzzPhaseOfTic(FWorld.Tic))
      else if Mapped then
        FWeaponImage.Image := Graphics.ColormapCopy(Img.Image, WeaponLevel)
      else if Inverted then
        FWeaponImage.Image := InvertedCopy(Img.Image)
      else
        FWeaponImage.Image := Img.Image.MakeCopy;
      FWeaponImageName := SpriteName + WeaponSuffix;
    end;
    FWeaponImage.Exists := true;
    FWeaponImage.Width := Img.Width * S;
    FWeaponImage.Height := Img.Height * S;
    { Doom draws the weapon at screen x=160 (center), y=32 (WEAPONTOP) minus the offsets. }
    { Doom: x1 = centerx + (sx - 160 - leftoffset) * scale, with sx = 1. }
    FWeaponImage.Translation := Vector2(
      W / 2 + (1 - 160 - Img.LeftOffset + BobX) * S,
      H - (32 + P.WeaponOffset - Img.TopOffset + BobY) * S - Img.Height * S);
  end else
    FWeaponImage.Exists := false;

  FlashName := '';
  if (P.FlashFrame <> #0) and (FWorld.FlashSprite(P.Weapon) <> '') then
    FlashName := FWorld.FlashSprite(P.Weapon) + P.FlashFrame + '0';
  Img := nil;
  if FlashName <> '' then Img := Graphics.Patch(FlashName);
  if (Img <> nil) and not P.Dead and not FAutomap.Exists then
  begin
    if FlashName + FlashSuffix <> FFlashImageName then
    begin
      if Fuzzy then
        FFlashImage.Image := FuzzCopy(Img.Image, FuzzPhaseOfTic(FWorld.Tic))
      else if Mapped then
        FFlashImage.Image := Graphics.ColormapCopy(Img.Image, FlashLevel)
      else if Inverted then
        FFlashImage.Image := InvertedCopy(Img.Image)
      else
        FFlashImage.Image := Img.Image.MakeCopy;
      FFlashImageName := FlashName + FlashSuffix;
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
  Next: String;
begin
  BeginWipe;
  FIntermission := true;
  FIntermissionTime := 0;
  FIntermissionTicAccum := 0;
  P := FWorld.Player;
  Next := NextMapName(FMapName, FWorld.SecretExit, Wad.IsDoom2);
  FIntermissionBack.Exists := true;
  FLoadingText.Exists := false;
  if Music <> nil then
    Music.Play(Music.IntermissionLump);
  FIntermissionScreen.Start(Graphics, Sounds, Wad.IsDoom2, FMapName, Next,
    P.Kills, P.TotalKills, P.Items, P.TotalItems, P.Secrets, P.TotalSecrets, Trunc(FLevelTime));
  FWorld.ExitRequested := false;
end;

procedure TViewPlay.FinishIntermission;
var
  Next: String;
begin
  { The intermission stays visible until StartMap / StartFinale has
    captured it for the melt. }
  { Doom 2 (G_WorldDone): the story text comes after the intermission. }
  if Wad.IsDoom2 and StartFinale then Exit;
  Next := NextMapName(FMapName, FWorld.SecretExit, Wad.IsDoom2);
  if not Wad.HasLump(Next) then
    Next := Wad.MapNames[0];
  StartMap(Next, true);
end;

function TViewPlay.StartFinale: Boolean;
begin
  if not HasFinale(FMapName, Wad.IsDoom2, FWorld.SecretExit) then Exit(false);
  BeginWipe;
  Result := FFinaleScreen.Start(Graphics, Sounds, Music, FStrings, Wad.IsDoom2, FMapName, FWorld.SecretExit);
  if not Result then Exit;
  WritelnLog('Finale', 'Finale after %s (stage %d)', [FMapName, Ord(FFinaleScreen.Stage)]);
  FIntermission := true;
  FIntermissionTime := 0;
  FIntermissionTicAccum := 0;
  FIntermissionBack.Exists := true;
  FIntermissionScreen.Exists := false;
  FLoadingText.Exists := false;
  FFinaleScreen.Exists := true;
  FWorld.ExitRequested := false;
  if FFinaleScreen.Done then FinishFinale;
end;

procedure TViewPlay.FinishFinale;
var
  Next: String;
begin
  if FFinaleScreen.Continues then
  begin
    Next := NextMapName(FMapName, FWorld.SecretExit, Wad.IsDoom2);
    if not Wad.HasLump(Next) then
      Next := Wad.MapNames[0];
    StartMap(Next, true);
  end else
  begin
    FFinaleScreen.Exists := false;
    WritelnLog('Finale', 'The end');
    Container.View := ViewMenu;
  end;
end;

{ Render the whole view into a GPU texture (TDrawableImage.RenderToImageBegin:
  an FBO with the texture as colour and a depth renderbuffer, so the 3D view
  renders correctly) and keep it there: the melt draws that texture, nothing
  is read back. Reading pixels back is not implemented for WebGL in CGE
  (SaveScreen_NoFlush gives an empty image there), and an FBO with a colour
  renderbuffer raised an exception in the browser, which aborts the
  WebAssembly program; this path is the one CGE's own screen effects use. }
function TViewPlay.CaptureScreen: TDrawableImage;
var
  R: TRectangle;
begin
  Result := nil;
  R := Container.PixelsRect;
  if (R.Width <= 0) or (R.Height <= 0) then Exit;
  if FWipe.Active then FWipe.Stop; { do not capture a half-melted screen }
  Result := TDrawableImage.Create(R.Width, R.Height, TRGBImage, false);
  Result.RenderToImageBegin;
  try
    RenderContext.Clear([cbColor, cbDepth], Black);
    Container.RenderControl(Self, Rectangle(0, 0, R.Width, R.Height));
  finally
    Result.RenderToImageEnd;
  end;
end;

procedure TViewPlay.BeginWipe;
begin
  FWipe.Start(CaptureScreen);
  FWipeTicAccum := 0;
  FWipeSkipFrame := true;
end;

procedure TViewPlay.AccelerateScreen;
begin
  if FFinaleScreen.Exists then
  begin
    FFinaleScreen.Accelerate;
    if FFinaleScreen.Done then FinishFinale;
  end else
  if FIntermissionScreen.Exists then
  begin
    FIntermissionScreen.Accelerate;
    if FIntermissionScreen.Done then FinishIntermission;
  end;
end;

procedure TViewPlay.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  Lift, MaxEye: Single;
  Sec: Integer;
  CamPos, CamDir, TurnPos, TurnDir, TurnUp: TVector3;
  Feet: TVector3;
  P: TPlayerState;
  PerfT: TTimerResult;
begin
  inherited;
  if FWorld = nil then Exit;
  { Songs are rendered a slice per frame (no freeze at a level start). }
  if Music <> nil then Music.Update;

  if FWipe.Active then
  begin
    { Skip the frame that started it (it may contain a whole level load),
      then follow real time, at most 8 tics per frame. }
    if FWipeSkipFrame then
      FWipeSkipFrame := false
    else
      FWipeTicAccum := Min(FWipeTicAccum + SecondsPassed, 8 * TicSeconds);
    while FWipe.Active and (FWipeTicAccum >= TicSeconds) do
    begin
      FWipeTicAccum := FWipeTicAccum - TicSeconds;
      FWipe.Tic;
    end;
  end;

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
    FStatusBar.Exists := false;
    FWeaponImage.Exists := false;
    FFlashImage.Exists := false;
    FCrosshair.Exists := false;
    FMessageText.Exists := false;
    if FIntermissionScreen.Exists then
    begin
      { 320x200 shown 4:3, as tall as the viewport. }
      FIntermissionScreen.Height := EffectiveHeight;
      FIntermissionScreen.Width := EffectiveHeight * 4 / 3;
      FIntermissionTicAccum := FIntermissionTicAccum + SecondsPassed;
      while FIntermissionTicAccum >= TicSeconds do
      begin
        FIntermissionTicAccum := FIntermissionTicAccum - TicSeconds;
        FIntermissionScreen.Tic;
      end;
      if FIntermissionScreen.Done then
        FinishIntermission;
    end else
    if FFinaleScreen.Exists then
    begin
      FFinaleScreen.Height := EffectiveHeight;
      FFinaleScreen.Width := EffectiveHeight * 4 / 3;
      FIntermissionTicAccum := FIntermissionTicAccum + SecondsPassed;
      while FIntermissionTicAccum >= TicSeconds do
      begin
        FIntermissionTicAccum := FIntermissionTicAccum - TicSeconds;
        FFinaleScreen.Tic;
      end;
      if FFinaleScreen.Done then
        FinishFinale;
    end;
    Exit;
  end;
  if FSlotMenu <> SlotMenuNone then
  begin
    { The game is paused while picking a slot, like Doom's menus. }
    FNavigation.Exists := false;
    if FSlotScreen.Exists then
    begin
      { 320x200 shown 4:3 like the title menu; the skull blinks. }
      FSlotScreen.Height := Min(EffectiveHeight, EffectiveWidth * 3 / 4);
      FSlotScreen.Width := FSlotScreen.Height * 4 / 3;
      FSlotTicAccum := FSlotTicAccum + SecondsPassed;
      while FSlotTicAccum >= TicSeconds do
      begin
        FSlotTicAccum := FSlotTicAccum - TicSeconds;
        FSlotScreen.Tic;
      end;
    end;
    Exit;
  end;
  FStatusBar.Exists := true;
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
  PerfT := Timer;
  FWorld.Update(SecondsPassed, Feet.X, Feet.Y, Feet.Z, DoomAngleFromCamera, CamPos, CamDir);
  FPerfWorld := FPerfWorld + TimerSeconds(Timer, PerfT);

  if FWorld.PlayerTeleported then
  begin
    FWorld.PlayerTeleported := false;
    PlacePlayer(FWorld.PlayerTeleportX, FWorld.PlayerTeleportY, FWorld.PlayerTeleportZ, FWorld.PlayerTeleportAngle);
  end;

  { Knockback: move the camera by the world's push with the navigation's
    collisions (walls slide it); stop the push when nothing moved. }
  if (FWorld.PlayerPushDX <> 0) or (FWorld.PlayerPushDY <> 0) then
  begin
    if not TWalkNavigationAccess(FNavigation).Move(
      DoomToCge(FWorld.PlayerPushDX, FWorld.PlayerPushDY, 0), false, true) then
    begin
      FWorld.PlayerPushVX := 0;
      FWorld.PlayerPushVY := 0;
    end;
    FWorld.PlayerPushDX := 0;
    FWorld.PlayerPushDY := 0;
  end;

  { Melee attacks turn the player (A_Punch / A_Saw): rotate the view
    around the vertical axis, keeping the pitch. }
  if FWorld.PlayerTurn <> 0 then
  begin
    FViewport.Camera.GetView(TurnPos, TurnDir, TurnUp);
    TurnDir := RotatePointAroundAxisRad(DegToRad(FWorld.PlayerTurn), TurnDir, Vector3(0, 1, 0));
    TurnUp := RotatePointAroundAxisRad(DegToRad(FWorld.PlayerTurn), TurnUp, Vector3(0, 1, 0));
    FViewport.Camera.SetView(TurnPos, TurnDir, TurnUp);
    FWorld.PlayerTurn := 0;
  end;

  { Arch-vile blast: throw the camera up (under the ceiling); the walk
    navigation's gravity brings it back down. }
  if FWorld.PlayerKnockUp > 0 then
  begin
    Lift := Min(FWorld.PlayerKnockUp, 400 * SecondsPassed);
    FWorld.PlayerKnockUp := FWorld.PlayerKnockUp - Lift;
    CamPos := FViewport.Camera.Translation;
    Sec := FWorld.Map.SectorAt(FWorld.Player.X, FWorld.Player.Y);
    MaxEye := CamPos.Y + Lift;
    if Sec >= 0 then
      MaxEye := Min(MaxEye, FWorld.Map.Sectors[Sec].CeilingHeight - (PlayerHeight - PlayerViewHeight) - 1);
    if MaxEye > CamPos.Y then
      FViewport.Camera.Translation := Vector3(CamPos.X, MaxEye, CamPos.Z)
    else
      FWorld.PlayerKnockUp := 0;
  end;

  { Hold the fire button for automatic weapons (not the click that just
    resumed the game or took the mouse back). }
  if FSuppressFire and not (buttonLeft in Container.MousePressed) then
    FSuppressFire := false;
  if ((buttonLeft in Container.MousePressed) and not FSuppressFire) or Container.Pressed.Items[keyCtrl] then
    FWorld.FireWeapon
  else
    FWorld.Player.Refire := false;

  P := FWorld.Player;
  FPaletteFlash.Color := FPaletteTints[FWorld.PaletteIndex];
  { Doom's colormaps: the gun flash lights the room, invulnerability and
    the light amplification visor fix the colormap (DoomLighting). }
  DoomLightingInstance.ExtraLight := FWorld.Player.ExtraLight;
  DoomLightingInstance.FixedColormap := FWorld.FixedColormap;
  { Spectre fuzz in Doom's pixels, a new pattern start every tic. }
  DoomLightingInstance.FuzzScale := Max(1, FViewport.EffectiveHeight / 200);
  DoomLightingInstance.FuzzPhase := FuzzPhaseOfTic(FWorld.Tic);
  FMessageText.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
  FAutomapTitle.Exists := FAutomap.Exists;
  if FAutomap.Exists then
  begin
    FAutomapTitle.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
    FAutomapTitle.SetText(UpperCase(FStrings.LevelName(FMapName, Wad.IsDoom2)));
    FAutomapTitle.Anchor(vpBottom, FStatusBar.Height + 4);
  end;
  if P.MessageTics = 0 then FMessageAlways := false;
  { Options -> Messages OFF hides the player messages (not this one). }
  if (P.MessageTics > 0) and (Settings.ShowMessages or FMessageAlways) then
    FMessageText.SetText(UpperCase(P.Message))
  else
    FMessageText.SetText('');
  FInfoLabel.Caption := Format('%s   FPS %s   %d things   light diminishing %s', [
    FMapName, Container.Fps.ToString, FWorld.Actors.Count, BoolToStr(DoomLightingInstance.Diminish, 'on', 'off')]);
  FStatusBar.Width := FViewport.EffectiveWidth;
  FStatusBar.Height := FViewport.EffectiveWidth / 10;
  PerfT := Timer;
  FStatusBar.Refresh(FWorld, SecondsPassed);
  FPerfStatusBar := FPerfStatusBar + TimerSeconds(Timer, PerfT);
  PerfT := Timer;
  UpdateWeaponSprite(SecondsPassed);
  FPerfWeapon := FPerfWeapon + TimerSeconds(Timer, PerfT);
  Inc(FPerfFrames);
  FPerfClock := FPerfClock + SecondsPassed;
  if FPerfClock >= 10 then
  begin
    WritelnLog('PerfView', '%d frames in %.1f s; ms per frame: world %.2f, status bar %.2f, weapon %.2f',
      [FPerfFrames, FPerfClock, FPerfWorld * 1000 / FPerfFrames, FPerfStatusBar * 1000 / FPerfFrames,
       FPerfWeapon * 1000 / FPerfFrames]);
    FPerfWorld := 0; FPerfStatusBar := 0; FPerfWeapon := 0; FPerfClock := 0; FPerfFrames := 0;
  end;
  FCrosshair.Exists := FNavigation.MouseLook and not P.Dead and not FAutomap.Exists;

  if FWorld.ExitRequested then
  begin
    { Doom 1 (G_DoCompleted): ExM8 goes straight to the finale. }
    if Wad.IsDoom2 or not StartFinale then
      StartIntermission;
  end;
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
    if (FIntermissionTime > 0.3) and (Event.IsKey(keyE) or Event.IsKey(keySpace) or
       Event.IsKey(keyEnter) or Event.IsMouseButton(buttonLeft) or Event.IsKey(keyCtrl)) then
    begin
      AccelerateScreen;
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
  { Mouse look wanted but the pointer is free (the browser dropped the
    lock, e.g. after the intermission): the click takes the mouse back
    (a user gesture, so the browser allows it) instead of firing. }
  if Event.IsMouseButton(buttonLeft) and Settings.MouseLook and
     not FNavigation.MouseLook and (AutoTestPrefix = '') then
  begin
    FNavigation.MouseLook := true;
    FSuppressFire := true;
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
  if FSlotMenu <> SlotMenuNone then
  begin
    for Idx := 1 to SaveSlots do
    begin
      K := TKey(Ord(key0) + Idx);
      { 1-6 on Doom's save / load page picks that slot directly. }
      if Event.IsKey(K) and (FSlotScreen.Page in [mpSave, mpLoad]) and not FSlotScreen.Editing then
      begin
        if FSlotScreen.Page = mpSave then
        begin
          ResumeFromPause;
          SaveGame(Idx);
        end else
        begin
          ResumeFromPause;
          LoadGame(Idx);
        end;
        Exit(true);
      end;
    end;
    { Arrows, Enter, Esc like Doom's menu (the mouse goes to it directly). }
    FSlotScreen.HandleKey(Event);
    Exit(true); { the menu swallows other input }
  end;
  if Event.IsKey(keyF2) then
  begin
    OpenSlotMenu(SlotMenuSave);
    Exit(true);
  end;
  if Event.IsKey(keyF4) then
  begin
    OpenSoundMenu;
    Exit(true);
  end;
  if Event.IsKey(keyF3) then
  begin
    OpenSlotMenu(SlotMenuLoad);
    Exit(true);
  end;
  if Event.IsKey(keyF6) then
  begin
    SaveGame(0);
    Exit(true);
  end;
  if Event.IsKey(keyF9) then
  begin
    LoadGame(0);
    Exit(true);
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
      if FAutomap.Grid then
        FWorld.ShowMessage(FWorld.Text('AMSTR_GRIDON', 'Grid ON'))
      else
        FWorld.ShowMessage(FWorld.Text('AMSTR_GRIDOFF', 'Grid OFF'));
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
  { The toggles are remembered (GameSettings). }
  if Event.IsKey(keyF) then
  begin
    DoomLightingInstance.Diminish := not DoomLightingInstance.Diminish;
    Settings.Diminish := DoomLightingInstance.Diminish;
    SaveSettings;
    Exit(true);
  end;
  if Event.IsKey(keyM) then
  begin
    FNavigation.MouseLook := not FNavigation.MouseLook;
    Settings.MouseLook := FNavigation.MouseLook;
    SaveSettings;
    Exit(true);
  end;
  if Event.IsKey(keyJ) and (Music <> nil) then
  begin
    Music.Enabled := not Music.Enabled;
    Settings.MusicOn := Music.Enabled;
    SaveSettings;
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
    OpenPauseMenu;
    Exit(true);
  end;
end;

end.
