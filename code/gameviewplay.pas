{ The "playing" view: a TCastleViewport showing the Doom level, walk
  navigation with gravity and collisions, weapon/status bar HUD, and the
  input handling that drives TDoomWorld. }
unit GameViewPlay;

interface

uses Classes, SysUtils, FpJson,
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse, CastleTimeUtils,
  CastleViewport, CastleScene, CastleCameras, CastleTransform, CastleColors, CastleImages, CastleGLImages,
  DoomWad, DoomGraphics, DoomSound, DoomWorld, DoomHud, DoomMusic, DoomAutomap, DoomFont, DoomCaptions, DoomLighting,
  DoomIntermission, DoomFinale, DoomDehacked, DoomWipe, DoomMenu, DoomWorldStatus, GameSettings,
  GameTouch, GameDebugDraw, DoomDemo;

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
    { Boom's deep water colormaps as a tint of the 3D view and the weapon. }
    FColormapTint: TCastleRectangleControl;
    FPaletteTints: array [0..13] of TVector4;
    FInfoLabel, FHelpLabel: TCastleLabel;
    FWorldStatus: TDoomWorldStatus;
    FMessageText, FLoadingText, FAutomapTitle: TDoomFontText;
    { The level statistics overlay (gaStats, Settings.ShowStats). }
    FStatsText: TDoomFontText;
    { Closed captions under the messages (Settings.Captions, DoomCaptions). }
    FCaptionText: TDoomFontText;
    FCaptions: TCaptionList;
    { Photo mode (gaPhoto): a free camera over the paused world, no HUD;
      the camera's place and what the HUD showed, to go back to. }
    FPhoto: Boolean;
    FPhotoPos, FPhotoDir, FPhotoUp: TVector3;
    FPhotoAutomap, FPhotoInfo: Boolean;
    FPhotoHintTime: Single;
    { The world keeps running behind the free camera (the player stands
      where photo mode began); the camera's field of view and tilt. }
    FPhotoRunning: Boolean;
    FPhotoFov, FPhotoTilt: Single;
    { Dynamic lights picked this frame (nearest first) and their distances
      to the camera; FDynLogTime throttles the log line. }
    FDynLights: array [0..MaxDynamicLights - 1] of TDynamicLight;
    FDynDist: array [0..MaxDynamicLights - 1] of Single;
    FDynLamp: array [0..MaxDynamicLights - 1] of Boolean;
    FDynCount: Integer;
    FDynLogged, FDynLampsLogged: Integer;
    { "Click to look around" while mouse look is wanted but the browser
      released the pointer (Esc, another window). }
    FClickPrompt: TDoomFontText;
    { Demo command CLICKPROMPT: show the prompt in an autotest. }
    FForceClickPrompt: Boolean;
    { Phones and tablets: stick, look area and buttons (GameTouch). }
    FTouch: TDoomTouchControls;
    { The triggers last frame (they are axes, without press events). }
    FTriggerHeld: array [Boolean] of Boolean;
    { Demo command NOSPRITES: the things are hidden (profiling). }
    FNoSprites: Boolean;
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
    { The feet last frame and the push applied since, to measure the
      walking speed (Boom ice); FWalkKnown is false after a jump. }
    FPrevFeet: TVector3;
    FPushedX, FPushedY: Single;
    FWalkKnown: Boolean;
    { --fixed-step: when the last frame began. }
    FFixedStepLast: TTimerResult;
    FFixedStepStarted: Boolean;
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
    { The engine's inspector (F8) is shown; mouse look was on when it
      opened (it is off while the inspector's panels take the mouse). }
    FInspectorShown, FInspectorFreedMouse: Boolean;
    { Wireframes of the simulation (GameDebugDraw), under Items. }
    FDebugDraw: TDebugDraw;
    FSlotMenuBack: TCastleRectangleControl;
    FSlotScreen: TDoomMenuScreen;
    FSlotTicAccum: Single;
    { The "Messages ON / OFF" message shows even with messages off. }
    FMessageAlways: Boolean;
    FRecorder: TDemoRecorder;
    FDemoPlayer: TDemoPlayer;
    FDemoStarted: Boolean;
    { Between two levels of a demo; FDemoAdvance moves a played demo's
      intermission on by itself. }
    FDemoNextLevel: Boolean;
    FDemoAdvance: Single;
    FGhostTracks: TGhostTracks;
    FGhostRead: Boolean;
    { A menu starts or stops typing: the on-screen keyboard (GameTouch). }
    procedure MenuEditingChange(Sender: TObject);
    procedure SlotScreenAction(const Action: TDoomMenuAction);
    { Description: shown on the load page ('' = the map, kills
      and time). }
    procedure SaveGame(const Slot: Integer; const Description: String = '');
    function AutoSaveName: String;
    procedure LoadGame(const Slot: Integer);
    function LoadGameUrl(const Url: String): Boolean;
    function LoadGameJson(J: TJSONObject; const Url: String): Boolean;
    function SaveJson(const Description: String): TJSONObject;
    procedure RestoreViewState(const State: TJSONObject);
    { Demos (DoomDemo): start recording here (the level reloaded from its
      saved state, so a playback starts alike), and end a recording or a
      playback (a level's end, another map, leaving the view). }
    procedure StartDemoRecording;
    procedure KeepDemo(const Ends: Boolean);
    { ToNextLevel: the level ended (intermission), the demo goes on in the
      next one; otherwise it ends. }
    procedure StopDemos(const ToNextLevel: Boolean);
    { The next level after an intermission: record on, or play its part. }
    procedure ContinueDemo;
    { --ghost: the ghost of this level, if the demo has one. }
    procedure StartGhost;
    { At the level's end: the time against the ghost's. }
    procedure LogGhostResult;
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
    procedure PerfLog;
    { The camera's horizontal field of view from the settings. }
    procedure ApplyFieldOfView;
    { Sets, applies and saves the gamma level (0..MaxGamma) and shows
      Doom's message for it. }
    procedure SetGamma(const Level: Integer);
    { TDoomSounds.OnPlay: a closed caption for the sound. }
    procedure SoundPlayed(const LumpName: String; const Emitter: TCastleTransform);
    procedure SetCaptions(const On: Boolean);
    { Dynamic lights: the nearest missiles, explosions and muzzle flashes
      to the shader (Settings.DynamicLights), or none. }
    procedure UpdateDynamicLights;
    { Rank: the distance it competes with (lamps rank further away than
      they are, so shots and flashes win the slots). }
    procedure ConsiderLight(const Eye: TVector3; const X, Y, Z, Radius, Penalty: Single; const Color: TVector3);
    procedure SetDynamicLightsOn(const On: Boolean);
    { The map editor (gaEditor, demo command EDIT): back to it from its
      play-test, else on this map. }
    procedure OpenEditor;
    { Photo mode on / off (gaPhoto, demo command PHOTO). }
    procedure SetPhotoMode(const On: Boolean);
    procedure UpdatePhoto(const SecondsPassed: Single);
    { Photo mode's own controls: the world running or not, zoom (field of
      view, Steps of 5 degrees narrower) and tilt (Steps of 5 degrees). }
    procedure TogglePhotoRunning;
    procedure PhotoZoom(const Steps: Integer);
    procedure PhotoTilt(const Steps: Integer);
    { The navigation's keys from Settings.Keys, and the help panel's
      lines for them. }
    procedure ApplyKeyBindings;
    procedure DemoBind(const Spec: String);
    { TDOWN:id:x:y, TMOVE:id:x:y, TUP:id (x, y fractions of the window). }
    procedure DemoTouch(const Cmd, Spec: String);
    procedure TouchButton(const Button: TTouchButton);
    { A gamepad button went down in the game: run its bound actions (fire
      is held, see Update). False when nothing is bound to it. }
    function PadPressed(const B: TPadButton): Boolean;
    { The triggers have no events: find their presses every frame. }
    procedure CheckPadTriggers;
    { PADDOWN:button / PADUP:button / PADBIND:action:button. }
    procedure DemoPad(const Cmd, Spec: String);
    { Move and turn by the touch controls' stick and look fingers. }
    procedure ApplyTouch(const SecondsPassed: Single);
    { The first key bound to Action (the second if the first is unset). }
    function BoundKey(const Action: TGameAction): TKey;
    { The mouse button B is held (wheel directions never are). }
    function MouseHeld(const B: TMouseBind): Boolean;
    procedure DemoMouse(const Cmd, Spec: String);
    procedure DemoTouchPlace(const Spec: String);
    procedure ApplyTouchSettings;
    procedure CheckInspector;
    { Select a thing in the engine's inspector (opening it): by name, or
      the one under the crosshair when Name is ''. }
    procedure SelectInInspector(const ThingName: String);
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
  { --record FILE: record the next level started; --playdemo FILE: play
    a demo (the menu loads its WADs first). Both are used once. }
  DemoRecordFile, DemoPlayFile: String;
  { --ghost FILE: a demo whose run of each level is drawn as a
    see-through player to race (read once, at the first level). }
  DemoGhostFile: String;

const
  { The browser's demo (Options -> Record demo... there, or ?record=1):
    recorded in memory, kept in the save storage (localStorage) under
    this URL and downloaded by the page when the recording ends. On the
    desktop --record / --playdemo take this URL too. }
  LastDemoUrl = 'castle-config:/last-demo.cdemo';

{ A demo from a file, an upload:/ URL (the browser's file picker) or a
  castle-config: URL (the save storage); nil and a warning when it is
  missing or not a demo. No exceptions on the web. }
function OpenDemo(const Url: String): TDemoPlayer;

{ Saved game location: slot 0 is the quick save, 1..6 the F2/F3 slots.
  castle-config: is the user config directory on desktop (next to the log);
  in the browser GameSaveStorage keeps the text in localStorage under this URL. }
function SaveSlotUrl(const Slot: Integer): String;
{ Read a saved game, nil when missing or unreadable. Caller owns the result. }
function ReadSaveFile(const Url: String): TJSONObject;

implementation

uses Math, JsonParser,
  CastleLog, CastleUtils, CastleStringUtils, CastleWindow, CastleSoundEngine, CastleRenderOptions,
  CastleDownload, DoomActors, CastleInternalInspector,
  CastleUriUtils, X3DNodes, CastleRectangles, CastleRenderContext,
  DoomGeometry, DoomMap, DoomThings,
  GameViewMenu, GameSaveStorage, GameGamepad, CastleInputs, DoomMapInfo, GameViewEdit;

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

function IsStorageUrl(const Url: String): Boolean;
begin
  Result := SameText(Copy(Url, 1, Length('castle-config:')), 'castle-config:');
end;

function OpenDemo(const Url: String): TDemoPlayer;
var
  Text: String;
  Found: Boolean;
  Lines: TStringList;
begin
  Result := nil;
  if IsUploadUrl(Url) then
    Found := UploadText(Url, Text)
  else if IsStorageUrl(Url) then
    Found := SaveStorageRead(Url, Text)
  else
  begin
    { A file (the desktop's dialog or --playdemo). }
    Found := FileExists(Url);
    if Found then
    begin
      Lines := TStringList.Create;
      try
        try
          Lines.LoadFromFile(Url);
        except
          on E: Exception do
          begin
            WritelnWarning('Demo', 'Cannot read %s: %s', [Url, E.Message]);
            Exit;
          end;
        end;
        Text := Lines.Text;
      finally
        FreeAndNil(Lines);
      end;
    end;
  end;
  if not Found then
  begin
    WritelnWarning('Demo', 'Cannot play %s: no such demo', [Url]);
    Exit;
  end;
  Result := TDemoPlayer.CreateFromText(Url, Text);
  if not Result.Valid then
  begin
    WritelnWarning('Demo', 'Cannot play %s: %s', [Url, Result.Error]);
    FreeAndNil(Result);
  end;
end;

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
  { The 2D layer (automap, weapon, status bar, messages, help, the
    intermission and finale screens, Doom's menu, the melt) is a design
    editable in the CGE editor; CreateUi takes its controls by name and
    puts the viewport behind it. }
  DesignUrl := 'castle-data:/play.castle-user-interface';
end;

procedure TViewPlay.CreateUi;
var
  Camera: TCastleCamera;
  I: Integer;
  Tint: TVector3;
  TintAmount: Single;
begin
  FViewport := TCastleViewport.Create(FreeAtStop);
  FViewport.Name := 'Viewport';
  FViewport.FullSize := true;
  Camera := TCastleCamera.Create(FViewport);
  Camera.Name := 'Camera';
  Camera.ProjectionNear := 4;
  Camera.ProjectionFar := 0; { automatic / infinite }
  Camera.Perspective.FieldOfViewAxis := faHorizontal;
  Camera.Perspective.FieldOfView := DegToRad(Settings.FieldOfView);
  FViewport.Items.Add(Camera);
  FViewport.Camera := Camera;
  FViewport.BackgroundColor := Black;
  { CGE still merges what the atlas and the sprite batches leave: E1M1's
    door spot draws 56 shapes with it, 67 without (docs/ROADMAP.md). }
  FViewport.DynamicBatching := true;
  { Behind the design's 2D layer (loaded before Start). }
  InsertBack(FViewport);

  { The subclass only opens Move for the knockback. }
  FNavigation := TWalkNavigationAccess.Create(FreeAtStop);
  FNavigation.Name := 'Navigation';
  FViewport.InsertFront(FNavigation);
  SetupNavigation;

  { The 2D controls from data/play.castle-user-interface, in its order:
    automap over the 3D view and under the HUD, flashes, weapon, status
    bar, crosshair, texts, labels, the full-screen screens, the melt. }
  FAutomap := DesignedComponent('Automap') as TDoomAutomap;
  FPaletteFlash := DesignedComponent('PaletteFlash') as TCastleRectangleControl;
  FColormapTint := DesignedComponent('ColormapTint') as TCastleRectangleControl;
  { Every PLAYPAL palette is palette 0 blended towards one colour, so an
    alpha-blended rectangle of that colour reproduces it exactly. }
  for I := 0 to High(FPaletteTints) do
    if (I = 0) or not Wad.PaletteTint(I, Tint, TintAmount) then
      FPaletteTints[I] := Vector4(0, 0, 0, 0)
    else
      FPaletteTints[I] := Vector4(Tint, TintAmount);
  FWeaponImage := DesignedComponent('WeaponImage') as TCastleImageControl;
  FFlashImage := DesignedComponent('WeaponFlash') as TCastleImageControl;
  FStatusBar := DesignedComponent('StatusBar') as TDoomStatusBar;
  FStatusBar.Graphics := Graphics;
  FCrosshair := DesignedComponent('Crosshair') as TCastleCrosshair;
  { Player messages in Doom's own STCFN font. }
  FMessageText := DesignedComponent('MessageText') as TDoomFontText;
  FMessageText.Graphics := Graphics;
  FClickPrompt := DesignedComponent('ClickPrompt') as TDoomFontText;
  FClickPrompt.Graphics := Graphics;
  FClickPrompt.SetText('CLICK TO LOOK AROUND WITH THE MOUSE');
  FClickPrompt.Exists := false;
  { The level title at the bottom left of the automap (AM_drawTitle). }
  FAutomapTitle := DesignedComponent('AutomapTitle') as TDoomFontText;
  FAutomapTitle.Graphics := Graphics;
  FStatsText := DesignedComponent('StatsText') as TDoomFontText;
  FStatsText.Graphics := Graphics;
  FCaptionText := DesignedComponent('CaptionText') as TDoomFontText;
  FCaptionText.Graphics := Graphics;
  FInfoLabel := DesignedComponent('InfoLabel') as TCastleLabel;
  FWorldStatus := DesignedComponent('DoomWorldStatus') as TDoomWorldStatus;
  FHelpLabel := DesignedComponent('HelpLabel') as TCastleLabel;
  FHelpVisible := true;
  FIntermissionBack := DesignedComponent('IntermissionBack') as TCastleRectangleControl;
  { The real Doom intermission screen (320x200, kept 4:3 and centred). }
  FIntermissionScreen := DesignedComponent('Intermission') as TDoomIntermission;
  FFinaleScreen := DesignedComponent('Finale') as TDoomFinale;
  FLoadingText := DesignedComponent('LoadingText') as TDoomFontText;
  FLoadingText.Graphics := Graphics;
  { Doom's menu over the game (Esc, F2, F3, F4) on a dark panel. }
  FSlotMenuBack := DesignedComponent('SlotMenuBack') as TCastleRectangleControl;
  FSlotScreen := DesignedComponent('SlotMenu') as TDoomMenuScreen;
  FSlotScreen.Overlay := true;
  FSlotScreen.OnAction := {$ifdef FPC}@{$endif} SlotScreenAction;
  FSlotScreen.OnEditingChange := {$ifdef FPC}@{$endif} MenuEditingChange;
  FSlotScreen.MouseEnabled := AutoTestPrefix = '';
  { The screen melt, above everything. }
  FWipe := DesignedComponent('Wipe') as TDoomWipe;
  FTouch := DesignedComponent('TouchControls') as TDoomTouchControls;
  FTouch.Graphics := Graphics;
  FTouch.OnButton := {$ifdef FPC}@{$endif} TouchButton;
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
  { CGE turns the view during long falls; Doom does not. }
  FNavigation.FallingEffect := false;
  FNavigation.MouseLook := Settings.MouseLook;
  FNavigation.MouseLookHorizontalSensitivity := MouseLookSensitivity;
  FNavigation.MouseLookVerticalSensitivity := MouseLookSensitivity;
  WritelnLog('MouseLook', 'Sensitivity %d: %.4f degrees a pixel', [
    Settings.MouseSensitivity, RadToDeg(MouseLookSensitivity)]);
  FNavigation.MinAngleFromGravityUp := DegToRad(20);
  { Gamepad sticks: move / strafe and turn / look (GameGamepad); the
    jump / crouch bindings it adds are cleared below. }
  FNavigation.UseGameController;
  { No jumping / crouching / flying in Doom. }
  FNavigation.Input_Jump.MakeClear;
  FNavigation.Input_Crouch.MakeClear;
  FNavigation.Input_IncreasePreferredHeight.MakeClear;
  FNavigation.Input_DecreasePreferredHeight.MakeClear;
  FNavigation.Input_GravityUp.MakeClear;
  FNavigation.Input_MoveSpeedInc.MakeClear;
  FNavigation.Input_MoveSpeedDec.MakeClear;
  { WASD in addition to arrows. }
  ApplyKeyBindings;
end;

procedure TViewPlay.Start;
var
  Url: String;
begin
  inherited;
  FGhostRead := false;
  FGhostTracks := nil;
  CreateUi;
  Container.PointerLock.AddUserCancelledListener({$ifdef FPC}@{$endif} PointerLockUserCancelled);
  { DeHackEd patches (the WADs' DEHACKED lumps, -deh files) before any
    thing is spawned: they change the thing table in place. }
  ApplyDehacked(Wad);
  { A PWAD's UMAPINFO: level names, music, sky, par times, progression. }
  LoadMapInfo(Wad);
  FWorld := TDoomWorld.Create(Wad, Graphics, Sounds, FViewport.Items);
  FCaptions := TCaptionList.Create;
  if Sounds <> nil then
    Sounds.OnPlay := {$ifdef FPC}@{$endif} SoundPlayed;
  FDebugDraw := TDebugDraw.Create(FreeAtStop);
  FViewport.Items.Add(FDebugDraw);
  FWorld.Skill := Skill;
  FWorldStatus.World := FWorld;
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
  if DemoPlayFile <> '' then
  begin
    FDemoPlayer := OpenDemo(DemoPlayFile);
    DemoPlayFile := '';
    if (FDemoPlayer <> nil) and LoadGameJson(FDemoPlayer.State.Clone as TJSONObject, FDemoPlayer.FileName) then
      Exit;
    FreeAndNil(FDemoPlayer);
  end;
  StartMap(StartMapName, false);
end;

procedure TViewPlay.OpenEditor;
var
  I: Integer;
begin
  WritelnLog('Editor', 'Opened from the game on %s', [FMapName]);
  { A demo script goes on in the editor after this step. }
  if FDemoSteps <> nil then
  begin
    AutoTestDemo := '';
    for I := FDemoStep + 1 to FDemoSteps.Count - 1 do
    begin
      if AutoTestDemo <> '' then AutoTestDemo := AutoTestDemo + ',';
      AutoTestDemo := AutoTestDemo + FDemoSteps[I];
    end;
    if AutoTestDemo = '' then AutoTestDemo := 'Q';
  end;
  if not ViewEdit.PlayTesting then
  begin
    ViewEdit.Wad := Wad;
    ViewEdit.Graphics := Graphics;
    ViewEdit.Sounds := Sounds;
    ViewEdit.Music := Music;
    ViewEdit.MapName := FMapName;
    ViewEdit.Skill := Skill;
    ViewEdit.Fresh := true;
  end;
  Container.View := ViewEdit;
end;

procedure TViewPlay.MenuEditingChange(Sender: TObject);
begin
  if FSlotScreen.Editing then
    ShowTextKeyboard(FSlotScreen.EditText)
  else
    HideTextKeyboard;
end;

procedure TViewPlay.Stop;
begin
  HideTextKeyboard;
  SetPhotoMode(false);
  DoomLightingInstance.SetDynamicLights([], TMatrix4.Identity);
  FDynLogged := 0;
  FDynLampsLogged := 0;
  StopDemos(false);
  FreeAndNil(FDemoPlayer);
  { The page must stop keeping fingers from the engine (the menus). }
  PollTouches(nil);
  Container.PointerLock.RemoveUserCancelledListener({$ifdef FPC}@{$endif} PointerLockUserCancelled);
  FreeAndNil(FPendingSave);
  FSlotMenu := SlotMenuNone;
  FreeAndNil(FDemoSteps);
  FWorldStatus.World := nil;
  if Sounds <> nil then
    Sounds.OnPlay := nil;
  FreeAndNil(FCaptions);
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
{ A demo step's number, Default when the text is not one (KEY:F4,
  BIND:use:Q). The text is checked first: in the web build a failed
  conversion inside StrToFloatDef raised and caught an exception, and
  WebAssembly cannot catch, so KEY and BIND stopped the program. }
function DemoNumber(const S: String; const Default: Single): Single;
var
  I: Integer;
begin
  if S = '' then Exit(Default);
  for I := 1 to Length(S) do
    if not (S[I] in ['0'..'9', '.', '-', '+']) then
      Exit(Default);
  Result := StrToFloatDef(S, Default);
end;

procedure TViewPlay.RunDemo(const SecondsPassed: Single);
var
  Step, Cmd, Rest, KeyStr: String;
  Arg, Arg2, LookAngle, LookPitch: Single;
  P, Sec: Integer;
  K, K2: TKey;
  FDemoKeys: TStringList;
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
      Arg := DemoNumber(Copy(Rest, 1, P - 1), 0);
      Arg2 := DemoNumber(Copy(Rest, P + 1, MaxInt), 0);
    end else
      Arg := DemoNumber(Rest, 1);
  end else
  begin
    Cmd := UpperCase(Step);
    Arg := 0;
  end;
  if (Cmd = 'F') or (Cmd = 'B') or (Cmd = 'W') or (Cmd = 'L') or (Cmd = 'R') then
  begin
    { Simulate holding the movement key, so the real navigation
      (collisions, gravity) is exercised. }
    if Cmd = 'F' then K := BoundKey(gaForward)
    else if Cmd = 'B' then K := BoundKey(gaBackward)
    else if Cmd = 'L' then K := BoundKey(gaStrafeLeft)
    else if Cmd = 'R' then K := BoundKey(gaStrafeRight)
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
    { A scripted jump lands exactly: no momentum (knockback, a line
      teleport's kept speed) carries over. }
    FWorld.StopPush;
    FWalkKnown := false;
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
  else if (Cmd = 'FOV') or (Cmd = 'UISCALE') or (Cmd = 'RENDERSCALE') or (Cmd = 'FULLSCREEN') or
    (Cmd = 'VSYNC') or (Cmd = 'FPSCAP') then
  begin
    { The video options like the title screen's Options panel (saved):
      FOV:deg, UISCALE:percent, RENDERSCALE:percent (the browser's
      canvas), FULLSCREEN toggles. }
    if Cmd = 'FOV' then
      Settings.FieldOfView := Clamped(Round(Arg), MinFieldOfView, MaxFieldOfView)
    else if Cmd = 'UISCALE' then
      Settings.UiScale := Clamped(Round(Arg), MinUiScale, MaxUiScale)
    else if Cmd = 'RENDERSCALE' then
      Settings.RenderScale := Clamped(Round(Arg), MinRenderScale, MaxRenderScale)
    else if Cmd = 'VSYNC' then
      Settings.VSync := not Settings.VSync
    else if Cmd = 'FPSCAP' then
      Settings.FrameCap := Max(0, Round(Arg))
    else
      Settings.Fullscreen := not Settings.Fullscreen;
    SaveSettings;
    ApplyWindowSettings;
    ApplyFieldOfView;
    WritelnLog('Settings', VideoSummary);
  end
  else if Cmd = 'BIND' then
    { BIND:action:key binds a key like the Controls page (action as in
      settings.json: forward, use...; key as KeyToStr names it: F, Space,
      Up; None clears the first slot); RESETKEYS restores the defaults. }
    DemoBind(Rest)
  else if Cmd = 'CRASH' then
    { A test exception for the crash report (GameCrash; in the browser
      the page's own report). }
    raise Exception.Create('Test crash from the CRASH demo command')
  else if Cmd = 'RESETKEYS' then
  begin
    ResetKeys;
    SaveSettings;
    ApplyKeyBindings;
  end
  else if Cmd = 'SOUNDMENU' then
    OpenSoundMenu
  else if TDoomWorld.IsCheat(Cmd) then
    { K, Y, P, CORPSE, D, V, INVIS, INVUL, AMP, LINE: through the world,
      which records them in a demo. }
    FWorld.Cheat(Cmd, Arg, Arg2)
  else if Cmd = 'SHOTS' then
    FWorld.DebugShots := true
  else if Cmd = 'SIGHT' then
    FWorld.DebugSight
  else if Cmd = 'DLIGHTS' then
    SetDynamicLightsOn(not Settings.DynamicLights)
  else if Cmd = 'PHOTO' then
    SetPhotoMode(not FPhoto)
  else if Cmd = 'EDIT' then
  begin
    OpenEditor;
    Exit;
  end
  else if Cmd = 'CAPTIONS' then
    SetCaptions(not Settings.Captions)
  else if Cmd = 'DIM' then
    DoomLightingInstance.Diminish := not DoomLightingInstance.Diminish
  else if Cmd = 'CLICKPROMPT' then
    FForceClickPrompt := true
  else if Cmd = 'TOUCH' then
  begin
    { The touch controls, as if the game ran with --touch. }
    TouchForced := true;
    TouchMode := true;
  end
  else if Cmd = 'TOUCHOPACITY' then
  begin
    { TOUCHOPACITY:percent and TOUCHPOS:button:x:y (fractions of the
      window, y up; TOUCHPOS:button:reset) like the Controls page. }
    Settings.TouchOpacity := EnsureRange(Round(Arg), TouchOpacities[0], 100);
    SaveSettings;
    WritelnLog('Settings', TouchSummary);
  end
  else if Cmd = 'TOUCHPOS' then
    DemoTouchPlace(Rest)
  else if (Cmd = 'TOUCHLAYOUT') or (Cmd = 'TOUCHSIZE') then
  begin
    { TOUCHLAYOUT:left|right and TOUCHSIZE:percent like the Controls
      page's Touch mode (saved). }
    if Cmd = 'TOUCHLAYOUT' then
      Settings.TouchLeftHanded := SameText(Rest, 'left')
    else
      Settings.TouchSize := EnsureRange(Round(Arg), TouchSizes[0], TouchSizes[High(TouchSizes)]);
    SaveSettings;
    WritelnLog('Settings', TouchSummary);
  end
  else if (Cmd = 'TDOWN') or (Cmd = 'TMOVE') or (Cmd = 'TUP') then
    DemoTouch(Cmd, Rest)
  else if (Cmd = 'PADDOWN') or (Cmd = 'PADUP') or (Cmd = 'PADBIND') then
    DemoPad(Cmd, Rest)
  else if Cmd = 'PALMAP' then
    DoomLightingInstance.PaletteMapped := not DoomLightingInstance.PaletteMapped
  else if Cmd = 'MENU' then
  begin
    if Round(Arg) = 0 then CloseSlotMenu else OpenSlotMenu(Round(Arg));
  end
  else if Cmd = 'SAVE' then
    SaveGame(Round(Arg))
  else if Cmd = 'LOAD' then
    LoadGame(Round(Arg))
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
    else
    begin
      { Any other key by its KeyToStr name (F, SPACE, CTRL...). }
      K := keyNone;
      for K2 := Low(TKey) to High(TKey) do
        if SameText(KeyToStr(K2), Rest) then
        begin
          K := K2;
          Break;
        end;
    end;
    if K <> keyNone then
      Press(InputKey(TVector2.Zero, K, '', []));
  end
  else if Cmd = 'DEBUG' then
  begin
    { DEBUG:subsectors|blocking|actors|shots|all|off: the wireframes. }
    if FWorld.Map <> nil then
      FDebugDraw.BuildMap(FWorld.Map);
    FDebugDraw.Toggle(Rest);
    FDebugDraw.UpdateWorld(FWorld);
  end
  else if (Cmd = 'MOUSE') or (Cmd = 'MBIND') then
    DemoMouse(Cmd, Rest)
  else if Cmd = 'UNLOCK' then
    { What the browser's Esc does: the pointer lock is cancelled. }
    PointerLockUserCancelled(nil)
  else if Cmd = 'RESUME' then
    ResumeFromPause
  else if Cmd = 'S' then
  begin
    Inc(FAutoTestShots);
    { No colour read-back and no files in the browser: just the log line. }
    {$ifndef WASI}
    Application.MainWindow.SaveScreen(Format('%s_%d.png', [AutoTestPrefix, FAutoTestShots]));
    {$endif}
    WritelnLog('AutoTest', 'Saved screenshot %d at %s (player %f %f %f)', [FAutoTestShots, FMapName,
      FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Z]);
  end else if Cmd = 'INSPECTOR' then
  begin
    { The engine's inspector (F8): the hierarchy under the viewport is
      grouped and named (Map, Things, Sprites), the things and the
      DoomWorldStatus control publish their state. }
    Container.EventPress(InputKey(Container.MousePosition, keyF8, '', []));
    WritelnLog('AutoTest', 'Inspector toggled');
  end else if Cmd = 'SELECT' then
    { SELECT selects the thing under the crosshair in the inspector (what
      its F9 auto-select does with the mouse), SELECT:name one by name. }
    SelectInInspector(Rest)
  else if Cmd = 'PROFILE' then
    { CGE's profiler summary (--profile turns the profiler on). }
    WritelnLog('Profile', Profiler.Summary)
  else if Cmd = 'PERF' then
    { Log the render statistics and the frame rate now (the 10 s lines too). }
    PerfLog
  else if Cmd = 'NOSPRITES' then
  begin
    { Profiling: hide every thing (the batch scenes with the quads) to see
      what they cost. }
    FNoSprites := not FNoSprites;
    FWorld.SpriteBatch.SetVisible(not FNoSprites);
  end else if Cmd = 'SPRITESTATS' then
  begin
    { How many draw calls the sprites would need if merged per texture
      within one scene per light group and kind. }
    FDemoKeys := TStringList.Create;
    try
      FDemoKeys.Sorted := true;
      FDemoKeys.Duplicates := dupIgnore;
      Sec := 0;
      for P := 0 to FWorld.Actors.Count - 1 do
        if FWorld.Actors[P].RenderKey <> '' then
        begin
          Inc(Sec);
          FDemoKeys.Add(FWorld.Actors[P].RenderKey);
        end;
      KeyStr := '';
      for P := 0 to FDemoKeys.Count - 1 do
        KeyStr := KeyStr + Copy(FDemoKeys[P], Pos('|', FDemoKeys[P]), MaxInt) + ' ';
      WritelnLog('SpriteStats', '%d sprites shown, %d distinct texture|light|kind; groups: %s', [Sec, FDemoKeys.Count, KeyStr]);
    finally
      FreeAndNil(FDemoKeys);
    end;
  end else if Cmd = 'NOMAP' then
    FWorld.Geometry.Visible := not FWorld.Geometry.Visible
  else if Cmd = 'Q' then
  begin
    {$ifdef WASI}
    WritelnLog('AutoTest', 'Demo finished (no quit in the browser)');
    {$else}
    Application.Terminate;
    {$endif}
  end;
  Inc(FDemoStep);
  FDemoTime := 0;
end;

{ "PerfView:" line: our own per-frame costs, CGE's frame rate (FPS, and
  "only render" = without waiting for the display) and the last frame's
  render statistics (shapes, scenes, draw calls). }
procedure TViewPlay.ApplyKeyBindings;

  { Two keys and the mouse binding: a button held, or a wheel step. }
  procedure AssignInput(const Input: TInputShortcut; const Action: TGameAction);
  const
    Buttons: array [mbLeft..mbButton5] of TCastleMouseButton = (
      buttonLeft, buttonMiddle, buttonRight, buttonExtra1, buttonExtra2);
  var
    B: TMouseBind;
  begin
    B := Settings.Mouse[Action];
    if B in [mbLeft..mbButton5] then
      Input.Assign(Settings.Keys[Action, 0], Settings.Keys[Action, 1], '', true, Buttons[B])
    else if B = mbWheelUp then
      Input.Assign(Settings.Keys[Action, 0], Settings.Keys[Action, 1], '', false, buttonLeft, mwUp)
    else if B = mbWheelDown then
      Input.Assign(Settings.Keys[Action, 0], Settings.Keys[Action, 1], '', false, buttonLeft, mwDown)
    else
      Input.Assign(Settings.Keys[Action, 0], Settings.Keys[Action, 1]);
  end;

  { "G: grid" for a bound action, '' when it has no key. }
  function Hot(const Action: TGameAction; const Text: String): String;
  begin
    if (Settings.Keys[Action, 0] = keyNone) and (Settings.Keys[Action, 1] = keyNone) and
       (Settings.Mouse[Action] = mbNone) then
      Result := ''
    else
      Result := ActionInputText(Action) + ': ' + Text;
  end;

  { Weapon keys: "1-7" when they are the default ones in a row. }
  function WeaponKeysText: String;
  var
    A: TGameAction;
    Run: Boolean;
  begin
    Run := true;
    for A := gaWeapon1 to gaWeapon7 do
      if (Settings.Keys[A, 0] <> DefaultKeys[A, 0]) or (Settings.Keys[A, 1] <> keyNone) then
        Run := false;
    if Run then Exit('1-7');
    Result := '';
    for A := gaWeapon1 to gaWeapon7 do
      if Settings.Keys[A, 0] <> keyNone then
        Result := Result + KeyName(Settings.Keys[A, 0]) + ' ';
    Result := Trim(Result);
  end;

  function SameAsDefaults: Boolean;
  var
    A: TGameAction;
  begin
    for A := Low(TGameAction) to High(TGameAction) do
      if (Settings.Keys[A, 0] <> DefaultKeys[A, 0]) or (Settings.Keys[A, 1] <> DefaultKeys[A, 1]) or
         (Settings.Mouse[A] <> DefaultMouse[A]) then
        Exit(false);
    Result := true;
  end;

  function PadSameAsDefaults: Boolean;
  var
    A: TPadAction;
  begin
    for A := Low(TPadAction) to High(TPadAction) do
      if (Settings.Pad[A, 0] <> DefaultPad[A, 0]) or (Settings.Pad[A, 1] <> DefaultPad[A, 1]) then
        Exit(false);
    Result := true;
  end;

begin
  AssignInput(FNavigation.Input_Forward, gaForward);
  AssignInput(FNavigation.Input_Backward, gaBackward);
  AssignInput(FNavigation.Input_LeftStrafe, gaStrafeLeft);
  AssignInput(FNavigation.Input_RightStrafe, gaStrafeRight);
  AssignInput(FNavigation.Input_LeftRotate, gaTurnLeft);
  AssignInput(FNavigation.Input_RightRotate, gaTurnRight);
  AssignInput(FNavigation.Input_Run, gaRun);
  { The design's help text describes the default keys; rebound ones
    replace its first lines. }
  if (FHelpLabel <> nil) and not SameAsDefaults and (FHelpLabel.Text.Count >= 5) then
  begin
    FHelpLabel.Text[0] := Format('Move: %s, %s   Strafe: %s, %s   Run: %s', [
      ActionInputText(gaForward), ActionInputText(gaBackward), ActionInputText(gaStrafeLeft),
      ActionInputText(gaStrafeRight), ActionInputText(gaRun)]);
    FHelpLabel.Text[1] := Format('Mouse: look   Turn: %s, %s   %s: fire', [
      ActionInputText(gaTurnLeft), ActionInputText(gaTurnRight), ActionInputText(gaFire)]);
    FHelpLabel.Text[2] := ActionInputText(gaUse) + ': use (doors, switches)';
    if (Hot(gaPrevWeapon, '') <> '') or (Hot(gaNextWeapon, '') <> '') then
      FHelpLabel.Text[3] := Format('%s, %s / %s: weapons', [WeaponKeysText,
        ActionInputText(gaPrevWeapon), ActionInputText(gaNextWeapon)])
    else
      FHelpLabel.Text[3] := WeaponKeysText + ': weapons';
    FHelpLabel.Text[4] := Trim(Hot(gaAutomap, 'automap   ') + '+ / -: zoom   ' + Hot(gaGrid, 'grid   ') +
      Hot(gaRevealMap, 'reveal map'));
    FHelpLabel.Text[5] := Trim(Hot(gaLightDiminish, 'light diminishing on/off   ') + Hot(gaMouseLook, 'mouse look   ') +
      Hot(gaGamma, 'gamma'));
    FHelpLabel.Text[6] := Trim(Hot(gaNextMap, 'next map   ') + Hot(gaPrevMap, 'previous map   ') +
      Hot(gaMusic, 'music on/off   ') + 'F4: volume');
    FHelpLabel.Text[7] := Trim('F2 / F3: save / load   ' + Hot(gaQuickSave, 'quick save   ') + Hot(gaQuickLoad, 'quick load   ') +
      Hot(gaStats, 'stats'));
    if FHelpLabel.Text.Count >= 11 then
    begin
      FHelpLabel.Text[8] := Trim(Hot(gaScreenshot, 'screenshot   ') + Hot(gaPhoto, 'photo mode   ') +
        'F1: Read This! (title menu)');
      FHelpLabel.Text[9] := Hot(gaEditor, 'map editor   ') + 'F8: Castle Game Engine inspector';
      FHelpLabel.Text[10] := Hot(gaHelp, 'hide this help   ') + 'Esc: menu (pauses; Esc again resumes)';
    end;
  end;
  if (FHelpLabel <> nil) and not PadSameAsDefaults and (FHelpLabel.Text.Count >= 13) then
  begin
    FHelpLabel.Text[11] := Format('Gamepad: sticks move / look, %s fire, %s use, %s / %s weapons,', [
      PadActionText(gpaFire), PadActionText(gpaUse), PadActionText(gpaPrevWeapon),
      PadActionText(gpaNextWeapon)]);
    FHelpLabel.Text[12] := Format('  %s automap, Menu menu (D-pad, A, B in menus)', [PadActionText(gpaAutomap)]);
  end;
  WritelnLog('Settings', KeysSummary);
end;

procedure TViewPlay.DemoTouch(const Cmd, Spec: String);
var
  Parts: TStringList;
  Id: Integer;
  Pos: TVector2;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := true;
    Parts.DelimitedText := Spec;
    if Parts.Count < 1 then Exit;
    Id := Round(DemoNumber(Parts[0], 0));
    if Cmd = 'TUP' then
    begin
      FTouch.TouchUp(Id);
      WritelnLog('Touch', 'Finger %d up', [Id]);
      Exit;
    end;
    if Parts.Count < 3 then Exit;
    Pos := Vector2(DemoNumber(Parts[1], 0) * FTouch.RenderRect.Width,
      DemoNumber(Parts[2], 0) * FTouch.RenderRect.Height);
    if Cmd = 'TDOWN' then
    begin
      FTouch.TouchDown(Id, Pos);
      WritelnLog('Touch', 'Finger %d down at %.0f, %.0f', [Id, Pos.X, Pos.Y]);
    end else
      FTouch.TouchMove(Id, Pos);
  finally
    FreeAndNil(Parts);
  end;
end;

procedure TViewPlay.TouchButton(const Button: TTouchButton);
begin
  if FWorld = nil then Exit;
  WritelnLog('Touch', 'Button %s', [TouchButtonNames[Button]]);
  if FPhoto then
  begin
    case Button of
      tbPhoto, tbMenu: SetPhotoMode(false);
      tbUse: TogglePhotoRunning;
      tbNextWeapon: PhotoZoom(1);
      tbPrevWeapon: PhotoZoom(-1);
      else ;
    end;
    Exit;
  end;
  case Button of
    tbPhoto: SetPhotoMode(true);
    tbUse: FWorld.UseInFront;
    tbPrevWeapon: FWorld.NextWeapon(-1);
    tbNextWeapon: FWorld.NextWeapon(1);
    tbAutomap: FAutomap.Exists := not FAutomap.Exists;
    tbMenu: OpenPauseMenu;
    else ;
  end;
end;

function TViewPlay.PadPressed(const B: TPadButton): Boolean;
var
  A: TPadAction;
begin
  Result := false;
  if B = pbNone then Exit;
  for A := Low(TPadAction) to High(TPadAction) do
    if PadIs(B, A) then
    begin
      Result := true;
      WritelnLog('Gamepad', '%s: %s', [PadButtonNames[B], PadActionIds[A]]);
      { Photo mode: the photo button leaves, use runs / pauses the game,
        the weapon buttons zoom; nothing else. }
      if FPhoto then
      begin
        case A of
          gpaPhoto: SetPhotoMode(false);
          gpaUse: TogglePhotoRunning;
          gpaNextWeapon: PhotoZoom(1);
          gpaPrevWeapon: PhotoZoom(-1);
          else ;
        end;
        Exit;
      end;
      case A of
        gpaPhoto: SetPhotoMode(true);
        gpaFire: FWorld.FireWeapon;
        gpaUse: FWorld.UseInFront;
        gpaAutomap: FAutomap.Exists := not FAutomap.Exists;
        gpaNextWeapon: FWorld.NextWeapon(1);
        gpaPrevWeapon: FWorld.NextWeapon(-1);
      end;
    end;
end;

procedure TViewPlay.CheckPadTriggers;
var
  Right, Held: Boolean;
  B: TPadButton;
begin
  for Right := false to true do
  begin
    if Right then B := pbRightTrigger else B := pbLeftTrigger;
    Held := PadButtonHeld(B);
    if Held and not FTriggerHeld[Right] then
      PadPressed(B);
    FTriggerHeld[Right] := Held;
  end;
end;

procedure TViewPlay.DemoPad(const Cmd, Spec: String);
var
  Parts: TStringList;
  B: TPadButton;
  A: TPadAction;
  Event: TInputPressRelease;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := true;
    Parts.DelimitedText := Spec;
    if Parts.Count < 1 then Exit;
    if Cmd = 'PADBIND' then
    begin
      { PADBIND:action:button like the Controls page (- clears slot 1). }
      if Parts.Count < 2 then Exit;
      for A := Low(TPadAction) to High(TPadAction) do
        if SameText(Parts[0], PadActionIds[A]) then
        begin
          BindPad(A, 0, StrToPadButton(Parts[1]));
          SaveSettings;
          ApplyKeyBindings;
          WritelnLog('Settings', PadSummary);
        end;
      Exit;
    end;
    B := StrToPadButton(Parts[0]);
    if B = pbNone then Exit;
    if Cmd = 'PADDOWN' then
    begin
      Include(SimulatedPadHeld, B);
      if PadButtonEvent(B, Event) then
        Press(Event);
    end else
      Exclude(SimulatedPadHeld, B);
  finally
    FreeAndNil(Parts);
  end;
end;

procedure TViewPlay.ApplyTouch(const SecondsPassed: Single);
var
  Look, Stick: TVector2;
  Dir, Forward, Right: TVector3;
  Speed: Single;
begin
  { No pointer lock with fingers: the look finger turns instead. }
  FNavigation.MouseLook := false;
  Look := FTouch.TakeLook;
  if FWorld.Player.Dead then Exit;
  if not Look.IsPerfectlyZero then
    TWalkNavigationAccess(FNavigation).ProcessMouseLookDelta(
      Vector2(DegToRad(Look.X), DegToRad(Look.Y)));
  Stick := FTouch.MoveVector;
  if Stick.IsPerfectlyZero then Exit;
  Dir := FViewport.Camera.Direction;
  Forward := Vector3(Dir.X, 0, Dir.Z);
  if Forward.Length < 0.001 then Exit;
  Forward := Forward.Normalize;
  Right := Vector3(-Forward.Z, 0, Forward.X);
  { Photo mode flies where the camera looks. }
  if FPhoto then
    Forward := Dir.Normalize;
  { Doom's running speed at the stick's edge, walking half way. }
  Speed := 2 * 290 * FWorld.PlayerMoveFactor * Stick.Length;
  TWalkNavigationAccess(FNavigation).Move(
    (Forward * Stick.Y + Right * Stick.X).Normalize * (Speed * SecondsPassed), false, true);
end;

procedure TViewPlay.DemoBind(const Spec: String);
var
  P: Integer;
  ActionId, KeyText: String;
  A: TGameAction;
  K: TKey;
begin
  P := Pos(':', Spec);
  if P = 0 then Exit;
  ActionId := Copy(Spec, 1, P - 1);
  KeyText := Copy(Spec, P + 1, MaxInt);
  K := StrToKey(KeyText, keyNone);
  for A := Low(TGameAction) to High(TGameAction) do
    if SameText(ActionIds[A], ActionId) then
    begin
      if (K = keyNone) and not SameText(KeyText, 'None') then
        WritelnWarning('Settings', 'Unknown key name "%s"', [KeyText])
      else if BindKey(A, 0, K) then
      begin
        SaveSettings;
        ApplyKeyBindings;
      end;
      Exit;
    end;
  WritelnWarning('Settings', 'Unknown action "%s"', [ActionId]);
end;

{ MOUSE:button clicks a mouse button or turns the wheel through Press
  (settings.json's names: Left, Right, Middle, Button4, Button5, WheelUp,
  WheelDown); MBIND:action:button binds it like the Controls page's mouse
  column (None clears the action's). }
{ The touch layout from the settings (they change on the Controls page and
  through the demo commands). }
{ The inspector's panels need the pointer: mouse look (the browser's
  pointer lock) is off while it is open. Closing it gives the mouse back
  on the desktop; the browser may lock the pointer again only in a user
  gesture, so there the next click does it (Press). }
procedure TViewPlay.CheckInspector;
var
  I: Integer;
  Shown: Boolean;
begin
  Shown := false;
  for I := 0 to Container.Controls.Count - 1 do
    if Container.Controls[I].ClassName = 'TCastleInspector' then
      Shown := true;
  if Shown = FInspectorShown then Exit;
  FInspectorShown := Shown;
  if Shown then
  begin
    FInspectorFreedMouse := FNavigation.MouseLook;
    FNavigation.MouseLook := false;
    WritelnLog('Inspector', 'Opened (mouse look %s)', [BoolToStr(FInspectorFreedMouse, 'paused', 'was off')]);
  end else
  begin
    {$ifndef WASI}
    if FInspectorFreedMouse then
      FNavigation.MouseLook := Settings.MouseLook;
    {$endif}
    FInspectorFreedMouse := false;
    WritelnLog('Inspector', 'Closed');
  end;
end;

procedure TViewPlay.ApplyTouchSettings;
var
  I: Integer;
begin
  FTouch.LeftHanded := Settings.TouchLeftHanded;
  FTouch.SizePercent := Settings.TouchSize;
  FTouch.Opacity := Settings.TouchOpacity / 100;
  for I := 0 to High(Settings.TouchPlaces) do
    FTouch.SetButtonPlace(TTouchButton(I + 1), Settings.TouchPlaces[I]);
end;

procedure TViewPlay.DemoTouchPlace(const Spec: String);
var
  Parts: TStringList;
  I: Integer;
begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := true;
    Parts.DelimitedText := Spec;
    if Parts.Count < 2 then Exit;
    for I := 0 to High(TouchButtonIds) do
      if SameText(TouchButtonIds[I], Parts[0]) then
      begin
        if SameText(Parts[1], 'reset') or (Parts.Count < 3) then
          Settings.TouchPlaces[I] := Vector2(-1, -1)
        else
          Settings.TouchPlaces[I] := Vector2(StrToFloatDefDot(Parts[1], 0.5), StrToFloatDefDot(Parts[2], 0.5));
        SaveSettings;
        WritelnLog('Settings', TouchSummary);
        Exit;
      end;
    WritelnWarning('Settings', 'Unknown touch button "%s"', [Parts[0]]);
  finally
    FreeAndNil(Parts);
  end;
end;

procedure TViewPlay.DemoMouse(const Cmd, Spec: String);
const
  Buttons: array [mbLeft..mbButton5] of TCastleMouseButton = (
    buttonLeft, buttonMiddle, buttonRight, buttonExtra1, buttonExtra2);
var
  P: Integer;
  A: TGameAction;
  B: TMouseBind;
  ButtonText: String;
begin
  if Cmd = 'MBIND' then
  begin
    P := Pos(':', Spec);
    if P = 0 then Exit;
    ButtonText := Copy(Spec, P + 1, MaxInt);
    B := StrToMouseBind(ButtonText);
    if (B = mbNone) and not SameText(ButtonText, 'None') then
    begin
      WritelnWarning('Settings', 'Unknown mouse button "%s"', [ButtonText]);
      Exit;
    end;
    for A := Low(TGameAction) to High(TGameAction) do
      if SameText(ActionIds[A], Copy(Spec, 1, P - 1)) then
      begin
        BindMouse(A, B);
        SaveSettings;
        WritelnLog('Settings', MouseSummary);
        ApplyKeyBindings;
        Exit;
      end;
    WritelnWarning('Settings', 'Unknown action "%s"', [Copy(Spec, 1, P - 1)]);
    Exit;
  end;
  B := StrToMouseBind(Spec);
  case B of
    mbLeft..mbButton5:
      begin
        Press(InputMouseButton(TVector2.Zero, Buttons[B], 0, []));
        Release(InputMouseButton(TVector2.Zero, Buttons[B], 0, []));
      end;
    mbWheelUp: Press(InputMouseWheel(TVector2.Zero, 1, true, []));
    mbWheelDown: Press(InputMouseWheel(TVector2.Zero, -1, true, []));
    else WritelnWarning('AutoTest', 'Unknown mouse button "%s"', [Spec]);
  end;
end;

function TViewPlay.MouseHeld(const B: TMouseBind): Boolean;
begin
  case B of
    mbLeft: Result := buttonLeft in Container.MousePressed;
    mbMiddle: Result := buttonMiddle in Container.MousePressed;
    mbRight: Result := buttonRight in Container.MousePressed;
    mbButton4: Result := buttonExtra1 in Container.MousePressed;
    mbButton5: Result := buttonExtra2 in Container.MousePressed;
    else Result := false;
  end;
end;

function TViewPlay.BoundKey(const Action: TGameAction): TKey;
begin
  Result := Settings.Keys[Action, 0];
  if Result = keyNone then
    Result := Settings.Keys[Action, 1];
end;

procedure TViewPlay.ApplyFieldOfView;
begin
  FViewport.Camera.Perspective.FieldOfView := DegToRad(Settings.FieldOfView);
end;

procedure TViewPlay.SetGamma(const Level: Integer);
const
  Defaults: array [0..MaxGamma] of String = ('Gamma correction OFF',
    'Gamma correction level 1', 'Gamma correction level 2',
    'Gamma correction level 3', 'Gamma correction level 4');
var
  L: Integer;
begin
  L := Max(0, Min(MaxGamma, Level));
  Settings.Gamma := L;
  DoomLightingInstance.Gamma := L;
  SaveSettings;
  if FWorld <> nil then
    FWorld.ShowMessage(FWorld.Text('GAMMALVL' + IntToStr(L), Defaults[L]));
  WritelnLog('Settings', 'Gamma %d (exponent %.3f)', [L, DoomLightingInstance.GammaExponent]);
end;

procedure TViewPlay.SetPhotoMode(const On: Boolean);
var
  Feet: TVector3;
begin
  if FPhoto = On then Exit;
  if On and ((FWorld = nil) or (not FWorld.MapLoaded) or FWorld.Player.Dead or
     FIntermission or (FSlotMenu <> SlotMenuNone) or FWorld.Replaying) then
    Exit;
  FPhoto := On;
  if On then
  begin
    FViewport.Camera.GetView(FPhotoPos, FPhotoDir, FPhotoUp);
    FPhotoAutomap := FAutomap.Exists;
    FPhotoInfo := FInfoLabel.Exists;
    FAutomap.Exists := false;
    { Fly where the camera looks, through walls, nothing falls. }
    FNavigation.Gravity := false;
    FNavigation.CheckCollisions := false;
    FNavigation.PreferGravityUpForMoving := false;
    FNavigation.HeadBobbing := 0;
    FNavigation.MoveSpeed := 290;
    { Mouse look keeps a tilted camera tilted. }
    FNavigation.PreferGravityUpForRotations := false;
    FPhotoRunning := false;
    FPhotoFov := Settings.FieldOfView;
    FPhotoTilt := 0;
    FPhotoHintTime := 3;
    Feet := CgeToDoom(FPhotoPos);
    WritelnLog('Photo', 'Photo mode on at (%.0f, %.0f, %.0f), the game is paused', [Feet.X, Feet.Y, Feet.Z]);
  end else
  begin
    FViewport.Camera.SetView(FPhotoPos, FPhotoDir, FPhotoUp);
    FNavigation.Gravity := true;
    FNavigation.CheckCollisions := true;
    FNavigation.PreferGravityUpForMoving := true;
    FNavigation.HeadBobbing := 0.03;
    FNavigation.PreferGravityUpForRotations := true;
    FNavigation.CancelFalling;
    FPhotoRunning := false;
    ApplyFieldOfView;
    FAutomap.Exists := FPhotoAutomap;
    FInfoLabel.Exists := FPhotoInfo;
    FPaletteFlash.Exists := true;
    FMessageText.SetText('');
    { The flight is no walk of the player's. }
    FWalkKnown := false;
    WritelnLog('Photo', 'Photo mode off, back at the player');
  end;
end;

procedure TViewPlay.TogglePhotoRunning;
begin
  FPhotoRunning := not FPhotoRunning;
  WritelnLog('Photo', 'The game %s', [Iff(FPhotoRunning, 'runs', 'is paused')]);
end;

procedure TViewPlay.PhotoZoom(const Steps: Integer);
begin
  FPhotoFov := Max(10, Min(MaxFieldOfView, FPhotoFov - 5 * Steps));
  FViewport.Camera.Perspective.FieldOfView := DegToRad(FPhotoFov);
  WritelnLog('Photo', 'Field of view %.0f', [FPhotoFov]);
end;

procedure TViewPlay.PhotoTilt(const Steps: Integer);
var
  Pos, Dir, Up: TVector3;
begin
  FPhotoTilt := FPhotoTilt + 5 * Steps;
  FViewport.Camera.GetView(Pos, Dir, Up);
  Up := RotatePointAroundAxisRad(DegToRad(5 * Steps), Up, Dir);
  FViewport.Camera.SetView(Pos, Dir, Up);
  WritelnLog('Photo', 'Tilt %.0f', [FPhotoTilt]);
end;

{ Photo mode's frame: the world stands still (or runs, the player
  standing where photo mode began), the HUD is hidden and only a hint
  shows for the first seconds. }
procedure TViewPlay.UpdatePhoto(const SecondsPassed: Single);
var
  Feet: TVector3;
  Angle: Single;
begin
  if FPhotoRunning then
  begin
    Feet := CgeToDoom(FPhotoPos);
    Feet.Z := Feet.Z - PlayerViewHeight;
    Angle := RadToDeg(ArcTan2(-FPhotoDir.Z, FPhotoDir.X));
    FWorld.PlayerWalkVX := 0;
    FWorld.PlayerWalkVY := 0;
    FLevelTime := FLevelTime + SecondsPassed;
    FWorld.Update(SecondsPassed, Feet.X, Feet.Y, Feet.Z, Angle, FPhotoPos, FPhotoDir);
    { What the world does to the player waits, or is dropped: a push
      stops, a teleport moves the place photo mode returns to. }
    if (FWorld.PlayerPushDX <> 0) or (FWorld.PlayerPushDY <> 0) then
    begin
      FWorld.StopPush;
      FWorld.PlayerPushDX := 0;
      FWorld.PlayerPushDY := 0;
    end;
    FWorld.PlayerTurn := 0;
    FWorld.PlayerKnockUp := 0;
    if FWorld.PlayerTeleported then
    begin
      FWorld.PlayerTeleported := false;
      FPhotoPos := DoomToCge(FWorld.PlayerTeleportX, FWorld.PlayerTeleportY,
        FWorld.PlayerTeleportZ + PlayerViewHeight);
    end;
    if FWorld.Player.Dead then
    begin
      SetPhotoMode(false);
      Exit;
    end;
  end;
  FNavigation.Exists := true;
  FStatusBar.Exists := false;
  FWeaponImage.Exists := false;
  FFlashImage.Exists := false;
  FCrosshair.Exists := false;
  FStatsText.Exists := false;
  FCaptionText.SetText('');
  FInfoLabel.Exists := false;
  FHelpLabel.Exists := false;
  FPaletteFlash.Exists := false;
  FClickPrompt.Exists := false;
  FAutomapTitle.Exists := false;
  if FPhotoHintTime > 0 then
  begin
    FPhotoHintTime := FPhotoHintTime - SecondsPassed;
    FMessageText.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
    FMessageText.SetText(UpperCase(Format('Photo mode: %s or Esc returns, %s saves a screenshot' + #10 +
      '%s runs or pauses the game, + / - zoom, [ / ] tilt', [
      ActionInputText(gaPhoto), ActionInputText(gaScreenshot), ActionInputText(gaUse)])));
  end else
    FMessageText.SetText('');
end;

procedure TViewPlay.ConsiderLight(const Eye: TVector3; const X, Y, Z, Radius, Penalty: Single; const Color: TVector3);
var
  D: Single;
  I, Slot: Integer;
begin
  D := Sqrt(Sqr(X - Eye.X) + Sqr(Y - Eye.Y) + Sqr(Z - Eye.Z));
  if D > 1500 + Radius then Exit;
  D := D + Penalty;
  if FDynCount < MaxDynamicLights then
  begin
    Slot := FDynCount;
    Inc(FDynCount);
  end else
  begin
    { Replace the farthest one if this is nearer. }
    Slot := 0;
    for I := 1 to MaxDynamicLights - 1 do
      if FDynDist[I] > FDynDist[Slot] then Slot := I;
    if D >= FDynDist[Slot] then Exit;
  end;
  FDynDist[Slot] := D;
  FDynLights[Slot].Position := DoomToCge(X, Y, Z);
  FDynLamp[Slot] := Penalty > 0;
  FDynLights[Slot].Radius := Radius;
  FDynLights[Slot].Color := Color;
end;

procedure TViewPlay.UpdateDynamicLights;
var
  A: TDoomActor;
  Eye, Color, Fwd: TVector3;
  Radius, LampHeight: Single;
  I, Lamps: Integer;
begin
  FDynCount := 0;
  if Settings.DynamicLights and (FWorld <> nil) and FWorld.MapLoaded then
  begin
    Eye := CgeToDoom(FViewport.Camera.Translation);
    for A in FWorld.Actors do
    begin
      if A.Removed then Continue;
      if A.State = asMissile then
      begin
        if SpriteDynamicLight(A.SpritePrefix, Radius, Color) then
          ConsiderLight(Eye, A.DoomX, A.DoomY, A.DoomZ + 16, Radius, 0, Color);
      end else
      if (A.State in [asEffect, asDying]) and A.Bright and not A.SequenceDone then
      begin
        { An explosion: shrinks and dims over its frames. }
        if SpriteDynamicLight(A.SpritePrefix, Radius, Color) then
          ConsiderLight(Eye, A.DoomX, A.DoomY, A.DoomZ + 16, Radius * (1 - 0.6 * A.SequenceProgress), 0,
            Color * (1 - 0.5 * A.SequenceProgress));
      end else
      { A monster's muzzle flash: its attack frame is full bright. }
      if (A.State = asAttack) and A.FrameBright then
        ConsiderLight(Eye, A.DoomX, A.DoomY, A.DoomZ + 40, 192, 0, Vector3(1.0, 0.75, 0.4))
      else
      { Lamps, torches and candles. }
      if (A.Info <> nil) and (A.Info^.Kind = tkDecoration) and
         LampDynamicLight(A.SpritePrefix, Radius, LampHeight, Color) then
        ConsiderLight(Eye, A.DoomX, A.DoomY, A.DoomZ + LampHeight, Radius, 400, Color);
    end;
    { The player's gun flash, a little in front of the eye. }
    if (FWorld.Player.FlashFrame <> #0) and not FWorld.Player.Dead then
    begin
      Fwd := Vector3(Cos(DegToRad(FWorld.Player.Angle)), Sin(DegToRad(FWorld.Player.Angle)), 0);
      ConsiderLight(Eye, FWorld.Player.X + Fwd.X * 24, FWorld.Player.Y + Fwd.Y * 24,
        FWorld.Player.Z + PlayerViewHeight, 320, 0, Vector3(1.0, 0.85, 0.6));
    end;
  end;
  DoomLightingInstance.SetDynamicLights(Slice(FDynLights, FDynCount), FViewport.Camera.WorldInverseTransform);
  Lamps := 0;
  for I := 0 to FDynCount - 1 do
    if FDynLamp[I] then Inc(Lamps);
  if (FDynCount <> FDynLogged) or (Lamps <> FDynLampsLogged) then
  begin
    if FDynCount > 0 then
      WritelnLog('Lights', '%d dynamic lights: %d lamps, %d shots, explosions and flashes', [
        FDynCount, Lamps, FDynCount - Lamps])
    else
      WritelnLog('Lights', 'No dynamic lights');
    FDynLogged := FDynCount;
    FDynLampsLogged := Lamps;
  end;
end;

procedure TViewPlay.SetDynamicLightsOn(const On: Boolean);
begin
  Settings.DynamicLights := On;
  SaveSettings;
  WritelnLog('Settings', 'Dynamic lights %s', [Iff(On, 'on', 'off')]);
end;

procedure TViewPlay.SetCaptions(const On: Boolean);
begin
  Settings.Captions := On;
  SaveSettings;
  if FCaptions <> nil then FCaptions.Clear;
  WritelnLog('Settings', 'Captions %s', [Iff(On, 'on', 'off')]);
end;

procedure TViewPlay.SoundPlayed(const LumpName: String; const Emitter: TCastleTransform);
var
  Text, Dir, Key, MonsterName: String;
  A: TDoomActor;
  P: TVector3;
  SX, SY: Single;
begin
  if (not Settings.Captions) or (FWorld = nil) or (FCaptions = nil) or
     (not FWorld.MapLoaded) or FIntermission then
    Exit;
  Dir := '';
  if Emitter = nil then
    Text := CaptionForLump(LumpName, true)
  else
  begin
    Text := CaptionForLump(LumpName, false);
    if Emitter is TDoomActor then
    begin
      A := TDoomActor(Emitter);
      SX := A.DoomX;
      SY := A.DoomY;
      if (Text = '') and (A.Info <> nil) and MonsterNameKey(A.Info^.Num, Key, MonsterName) then
      begin
        if Key <> '' then
          MonsterName := FWorld.Text(Key, MonsterName);
        Text := MonsterCaption(MonsterName, CaptionSlot(LumpName, A.Info^.SeeSound,
          A.Info^.AttackSound, A.Info^.PainSound, A.Info^.DeathSound));
      end;
    end else
    begin
      P := CgeToDoom(Emitter.WorldTranslation);
      SX := P.X;
      SY := P.Y;
    end;
    if Text = '' then Exit;
    if Sqr(SX - FWorld.Player.X) + Sqr(SY - FWorld.Player.Y) > Sqr(CaptionMaxDistance) then Exit;
    Dir := CaptionDirection(FWorld.Player.X, FWorld.Player.Y, FWorld.Player.Angle, SX, SY);
  end;
  if Text = '' then Exit;
  FCaptions.Add(Text, Dir, FWorld.Tic);
  if Dir <> '' then
    WritelnLog('Caption', '%s, %s (%s)', [Text, Dir, LumpName])
  else
    WritelnLog('Caption', '%s (%s)', [Text, LumpName]);
end;

procedure TViewPlay.SelectInInspector(const ThingName: String);
var
  Found: TDoomActor;
  A: TDoomActor;
  Pos, Dir, Up: TVector3;
  Hit: TRayCollision;
  I: Integer;
  Inspector: TCastleInspector;
begin
  Found := nil;
  if ThingName <> '' then
  begin
    for A in FWorld.Actors do
      if SameText(A.Name, ThingName) then
      begin
        Found := A;
        Break;
      end;
  end else
  begin
    { The same ray as the inspector's F9 auto-select from the screen's
      centre: monsters and barrels are pickable (their invisible
      collision quad, transient so the actor itself is what is found). }
    FViewport.Camera.GetWorldView(Pos, Dir, Up);
    Hit := FViewport.Items.WorldRay(Pos, Dir);
    try
      if Hit <> nil then
        for I := 0 to Hit.Count - 1 do
          if Hit[I].Item is TDoomActor then
          begin
            Found := TDoomActor(Hit[I].Item);
            Break;
          end;
    finally
      FreeAndNil(Hit);
    end;
  end;
  if Found = nil then
  begin
    WritelnLog('Select', 'Nothing to select (%s)', [ThingName]);
    Exit;
  end;
  Inspector := nil;
  for I := 0 to Container.Controls.Count - 1 do
    if Container.Controls[I] is TCastleInspector then
      Inspector := TCastleInspector(Container.Controls[I]);
  if Inspector = nil then
  begin
    Container.EventPress(InputKey(Container.MousePosition, keyF8, '', []));
    for I := 0 to Container.Controls.Count - 1 do
      if Container.Controls[I] is TCastleInspector then
        Inspector := TCastleInspector(Container.Controls[I]);
  end;
  if Inspector <> nil then
    Inspector.SelectedComponent := Found;
  WritelnLog('Select', '%s: %s, state %s, %d health, action %s, %d tics left, target %s', [Found.Name,
    Found.SpriteName, Found.ActorState, Found.Health, Found.ActionName, Found.TicsLeft, Found.TargetName]);
end;

procedure TViewPlay.PerfLog;
begin
  WritelnLog('PerfView', '%d frames in %.1f s; ms per frame: world %.2f, status bar %.2f, weapon %.2f; %s; %s',
    [FPerfFrames, FPerfClock, FPerfWorld * 1000 / Max(1, FPerfFrames), FPerfStatusBar * 1000 / Max(1, FPerfFrames),
     FPerfWeapon * 1000 / Max(1, FPerfFrames), Container.Fps.ToString, FViewport.Statistics.ToString]);
  FPerfWorld := 0; FPerfStatusBar := 0; FPerfWeapon := 0; FPerfClock := 0; FPerfFrames := 0;
end;

procedure TViewPlay.StartMap(const MapName: String; const KeepInventory: Boolean);
begin
  { The next level after an intermission keeps a demo going; any other
    map change (a load, a restart after death, a warp) ends it. }
  SetPhotoMode(false);
  if not FDemoNextLevel then
    StopDemos(false);
  if FCaptions <> nil then FCaptions.Clear;
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
  FWorldStatus.MapName := MapName;
  Restored := false;
  if FPendingSave <> nil then
  begin
    FWorld.LoadState(FPendingSave);
    RestoreViewState(FPendingSave);
    FreeAndNil(FPendingSave);
    Restored := true;
  end else
  begin
    { --fixed-step: the same random numbers on every run. }
    if AutoTestFixedStep then RandSeed := 1;
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
  begin
    Music.Play(Music.LumpForMap(MapName));
    { The next map's song renders while this one plays (after the
      intermission's), so the next level starts without synthesis. }
    Music.Prefetch(Music.LumpForMap(NextMapName(MapName, false, Wad.IsDoom2)));
  end;
  if FDemoNextLevel then
    ContinueDemo
  else
  if (FDemoPlayer <> nil) and not FDemoStarted and Restored then
  begin
    FDemoStarted := true;
    FWorld.StartReplay(FDemoPlayer);
  end else
  if (DemoRecordFile <> '') and (FRecorder = nil) and (FDemoPlayer = nil) then
    StartDemoRecording;
  StartGhost;
end;

procedure TViewPlay.StartGhost;
var
  Demo: TDemoPlayer;
  Track: TGhostTrack;
begin
  if not FGhostRead then
  begin
    if DemoGhostFile = '' then Exit;
    FGhostRead := true;
    { Read whole now: a recording to the same URL replaces it later. }
    Demo := OpenDemo(DemoGhostFile);
    if Demo = nil then Exit;
    try
      FGhostTracks := ReadGhostTracks(Demo);
      WritelnLog('Ghost', 'Ghost of %s: %d levels', [Demo.FileName, Length(FGhostTracks)]);
    finally
      FreeAndNil(Demo);
    end;
  end;
  if Length(FGhostTracks) = 0 then Exit;
  if FindGhostTrack(FGhostTracks, FMapName, Track) then
    FWorld.SetGhost(Track)
  else
    WritelnLog('Ghost', 'The ghost has no run of %s', [FMapName]);
end;

procedure TViewPlay.LogGhostResult;
var
  Ghost, Mine: Integer;
  Diff: Single;
  Msg: String;
begin
  if FWorld.Ghost = nil then Exit;
  Ghost := FWorld.GhostTrack.FinishTic;
  Mine := FWorld.Tic;
  if Ghost < 0 then
    Msg := Format('you finished at tic %d, the ghost did not finish', [Mine])
  else
  begin
    Diff := Abs(Mine - Ghost) / 35;
    if Mine < Ghost then
      Msg := Format('you finished at tic %d, the ghost at tic %d: %.2f s ahead', [Mine, Ghost, Diff])
    else if Mine > Ghost then
      Msg := Format('you finished at tic %d, the ghost at tic %d: %.2f s behind', [Mine, Ghost, Diff])
    else
      Msg := Format('you and the ghost finished at tic %d', [Mine]);
  end;
  WritelnLog('Ghost', '%s: %s', [FMapName, Msg]);
end;

procedure TViewPlay.StartDemoRecording;
var
  J: TJSONObject;
begin
  J := SaveJson('demo');
  try
    { The recording starts from this state loaded, like its playback. }
    FWorld.LoadState(J);
    RestoreViewState(J);
    if IsStorageUrl(DemoRecordFile) then
      FRecorder := TDemoRecorder.CreateInMemory(DemoRecordFile, 1, J)
    else
    try
      FRecorder := TDemoRecorder.Create(DemoRecordFile, 1, J);
    except
      on E: Exception do
        WritelnWarning('Demo', 'Cannot record to %s: %s', [DemoRecordFile, E.Message]);
    end;
  finally
    FreeAndNil(J);
  end;
  DemoRecordFile := '';
  if FRecorder <> nil then
    FWorld.StartRecording(FRecorder);
end;

{ An in-memory recording (the browser's) goes to the save storage after
  each level; when it ends the page also downloads it. }
procedure TViewPlay.KeepDemo(const Ends: Boolean);
const
  { localStorage holds about 5 million characters per page (saves too);
    an exception for a full one would stop the WebAssembly program. }
  MaxStoredDemo = 3000000;
var
  T: String;
begin
  if (FRecorder = nil) or not FRecorder.InMemory then Exit;
  T := FRecorder.Text;
  {$ifdef WASI}
  if Length(T) > MaxStoredDemo then
    WritelnWarning('Demo', '%s is too long to keep in the browser (%d KB)', [FRecorder.FileName, Length(T) div 1024])
  else
  {$endif}
  begin
    SaveStorageWrite(FRecorder.FileName, T);
    WritelnLog('Demo', 'Kept %s in %s (%d KB)', [FRecorder.FileName, SaveStorageName, (Length(T) + 1023) div 1024]);
  end;
  if Ends and PageDownload('castle-doom.cdemo', T, 'application/octet-stream') then
    WritelnLog('Demo', 'Downloading %s as castle-doom.cdemo', [FRecorder.FileName]);
end;

procedure TViewPlay.StopDemos(const ToNextLevel: Boolean);
begin
  if FRecorder <> nil then
  begin
    if (FWorld <> nil) and not FRecorder.Finished then FWorld.StopRecording;
    KeepDemo(not ToNextLevel);
    if not ToNextLevel then FreeAndNil(FRecorder);
  end;
  if FDemoStarted then
  begin
    if FWorld <> nil then FWorld.FinishReplay;
    FDemoStarted := false;
    if not ToNextLevel then FreeAndNil(FDemoPlayer);
  end;
  FDemoNextLevel := ToNextLevel and ((FRecorder <> nil) or (FDemoPlayer <> nil));
  FDemoAdvance := 0;
end;

procedure TViewPlay.ContinueDemo;
var
  J: TJSONObject;
begin
  FDemoNextLevel := false;
  if FRecorder <> nil then
  begin
    J := SaveJson('demo');
    try
      FWorld.LoadState(J);
      RestoreViewState(J);
      FRecorder.NextLevel(J);
    finally
      FreeAndNil(J);
    end;
    FWorld.StartRecording(FRecorder);
  end else
  if FDemoPlayer <> nil then
  begin
    J := FDemoPlayer.NextLevelState;
    if J = nil then
    begin
      WritelnLog('Demo', 'Played every level of %s', [FDemoPlayer.FileName]);
      FreeAndNil(FDemoPlayer);
      Exit;
    end;
    try
      FWorld.LoadState(J);
      RestoreViewState(J);
    finally
      FreeAndNil(J);
    end;
    FDemoStarted := true;
    FWorld.StartReplay(FDemoPlayer);
  end;
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

{ The world's state with the view's (camera, level time) and the WADs:
  a save game, also a demo's start. }
function TViewPlay.SaveJson(const Description: String): TJSONObject;
var
  C, Wads: TJSONArray;
  Pos, Dir, Up: TVector3;
  I: Integer;
begin
  Result := FWorld.SaveState;
  FViewport.Camera.GetView(Pos, Dir, Up);
  C := TJSONArray.Create;
  for I := 0 to 2 do C.Add(Double(Pos[I]));
  for I := 0 to 2 do C.Add(Double(Dir[I]));
  for I := 0 to 2 do C.Add(Double(Up[I]));
  Result.Add('camera', C);
  Result.Add('levelTime', Double(FLevelTime));
  Wads := TJSONArray.Create;
  for I := 0 to Wad.FileUrls.Count - 1 do
    Wads.Add(Wad.FileUrls[I]);
  Result.Add('wads', Wads);
  if Description <> '' then
    Result.Add('description', Description)
  else
    Result.Add('description', AutoSaveName);
  Result.Add('saved', FormatDateTime('yyyy-mm-dd hh:nn', Now));
end;

procedure TViewPlay.SaveGame(const Slot: Integer; const Description: String);
var
  J: TJSONObject;
begin
  if (FWorld = nil) or (not FWorld.MapLoaded) or FIntermission or FWorld.Player.Dead or (FPendingMap <> '') then
  begin
    if FWorld <> nil then FWorld.ShowMessage('You can''t save now.');
    Exit;
  end;
  J := SaveJson(Description);
  try
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
begin
  J := ReadSaveFile(Url);
  Result := (J <> nil) and LoadGameJson(J, Url);
end;

{ Load a save (taking J); False when it needs other WADs. }
function TViewPlay.LoadGameJson(J: TJSONObject; const Url: String): Boolean;
var
  D: TJSONData;
  Saved: TStringList;
  I: Integer;
begin
  Result := false;
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
  FSlotScreen.Gamma := Settings.Gamma;
  FSlotScreen.MessagesOn := Settings.ShowMessages;
  FSlotScreen.CaptionsOn := Settings.Captions;
  FSlotScreen.VideoDynamicLights := Settings.DynamicLights;
  FSlotScreen.VideoFieldOfView := Settings.FieldOfView;
  FSlotScreen.VideoUiScale := Settings.UiScale;
  FSlotScreen.VideoRenderScale := Settings.RenderScale;
  FSlotScreen.VideoFullscreen := Settings.Fullscreen;
  FSlotScreen.VideoVSync := Settings.VSync;
  FSlotScreen.VideoFrameCap := Settings.FrameCap;
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
        if FSlotScreen.CaptionsOn <> Settings.Captions then
          SetCaptions(FSlotScreen.CaptionsOn);
        if FSlotScreen.VideoDynamicLights <> Settings.DynamicLights then
          SetDynamicLightsOn(FSlotScreen.VideoDynamicLights);
        if FSlotScreen.Gamma <> Settings.Gamma then
          SetGamma(FSlotScreen.Gamma);
        { The Video page (field of view, UI scale, fullscreen / resolution). }
        if (FSlotScreen.VideoFieldOfView <> Settings.FieldOfView) or (FSlotScreen.VideoUiScale <> Settings.UiScale) or
           (FSlotScreen.VideoRenderScale <> Settings.RenderScale) or (FSlotScreen.VideoFullscreen <> Settings.Fullscreen) or
           (FSlotScreen.VideoVSync <> Settings.VSync) or (FSlotScreen.VideoFrameCap <> Settings.FrameCap) then
        begin
          Settings.FieldOfView := FSlotScreen.VideoFieldOfView;
          Settings.UiScale := FSlotScreen.VideoUiScale;
          Settings.RenderScale := FSlotScreen.VideoRenderScale;
          Settings.Fullscreen := FSlotScreen.VideoFullscreen;
          Settings.VSync := FSlotScreen.VideoVSync;
          Settings.FrameCap := FSlotScreen.VideoFrameCap;
          ApplyWindowSettings;
          ApplyFieldOfView;
          WritelnLog('Settings', VideoSummary);
        end;
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
  if (AutoTestPrefix = '') and not TouchMode then
    FNavigation.MouseLook := Settings.MouseLook;
  FSuppressFire := true;
end;

procedure TViewPlay.PointerLockUserCancelled(Sender: TObject);
begin
  WritelnLog('PointerLock', 'Cancelled by the user, pausing');
  SetPhotoMode(false);
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
  FWalkKnown := false;
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
  { Gamma correction: the 2D weapon gets the world's curve at mid grey. }
  if DoomLightingInstance.Gamma > 0 then
  begin
    Bright := Power(0.4, DoomLightingInstance.GammaExponent) / 0.4;
    FWeaponImage.Color := Vector4(FWeaponImage.Color.XYZ * Bright, 1);
    FFlashImage.Color := Vector4(FFlashImage.Color.XYZ * Bright, 1);
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

  if P.WeaponSprite <> '' then
    SpriteName := P.WeaponSprite + P.WeaponFrame + '0'
  else
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
  if (P.FlashFrame <> #0) and (P.FlashSprite <> '') then
    FlashName := P.FlashSprite + P.FlashFrame + '0'
  else
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
  Next, Key: String;
  Best, T: Integer;
  NewBest, Replayed: Boolean;
begin
  Replayed := FDemoStarted;
  LogGhostResult;
  StopDemos(true);
  { The level's best time (not from a demo's playback). }
  T := Trunc(FLevelTime);
  Key := BestTimeKey(Wad.Description, FMapName, Skill);
  Best := BestTime(Key);
  NewBest := (not Replayed) and ((Best < 0) or (T < Best));
  if NewBest then
  begin
    SetBestTime(Key, T);
    SaveSettings;
  end;
  if NewBest then
    WritelnLog('Stats', '%s: time %d:%2.2d, a new best', [Key, T div 60, T mod 60])
  else
    WritelnLog('Stats', '%s: time %d:%2.2d, best %d:%2.2d', [Key, T div 60, T mod 60, Best div 60, Best mod 60]);
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
    P.Kills, P.TotalKills, P.Items, P.TotalItems, P.Secrets, P.TotalSecrets, Trunc(FLevelTime), Best, NewBest);
  FWorld.ExitRequested := false;
end;

procedure TViewPlay.FinishIntermission;
var
  Next: String;
begin
  { The intermission stays visible until StartMap / StartFinale has
    captured it for the melt. }
  { Doom 2 (G_WorldDone): the story text comes after the intermission. }
  if (Wad.IsDoom2 or MapInfoDecidesFinale(FMapName, FWorld.SecretExit)) and StartFinale then Exit;
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
  Info: TMapInfoEntry;
  Lift, MaxEye: Single;
  Sec: Integer;
  CamPos, CamDir, TurnPos, TurnDir, TurnUp: TVector3;
  Feet: TVector3;
  P: TPlayerState;
  PerfT: TTimerResult;
  Elapsed: Double;
  TouchPlaying, TouchShown: Boolean;
begin
  inherited;
  if AutoTestFixedStep then
  begin
    { --fixed-step: frames last at least a tic, so CGE's capped
      SecondsPassed (MaxSensibleSecondsPassed, GameInitialize) is always
      exactly 1/35 s. }
    if FFixedStepStarted then
    begin
      Elapsed := TimerSeconds(Timer, FFixedStepLast);
      if Elapsed < 1 / 35 then
        Sleep(Ceil((1 / 35 - Elapsed) * 1000) + 1);
    end;
    FFixedStepLast := Timer;
    FFixedStepStarted := true;
  end;
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
    if FWorld <> nil then FWorld.ReleaseFire;
    if FWorld = nil then Exit;
  end;
  { Touch controls while the game is played (the browser's fingers are
    read here; the menus and the intermission take taps as clicks). }
  TouchPlaying := (not FIntermission) and (FSlotMenu = SlotMenuNone) and (FPendingMap = '');
  ApplyTouchSettings;
  if TouchPlaying then PollTouches(FTouch) else PollTouches(nil);
  TouchShown := TouchMode and TouchPlaying;
  if FTouch.Exists <> TouchShown then
  begin
    FTouch.Exists := TouchShown;
    FTouch.ReleaseAll;
  end;
  if FIntermission then
  begin
    FIntermissionTime := FIntermissionTime + SecondsPassed;
    { A played demo goes through the intermission by itself. }
    if FDemoNextLevel and (FDemoPlayer <> nil) and not FWipe.Active then
    begin
      FDemoAdvance := FDemoAdvance + SecondsPassed;
      if FDemoAdvance > 1.5 then
      begin
        FDemoAdvance := 0;
        AccelerateScreen;
        if FWorld = nil then Exit;
      end;
    end;
    FNavigation.Exists := false;
    FStatusBar.Exists := false;
    FWeaponImage.Exists := false;
    FFlashImage.Exists := false;
    FCrosshair.Exists := false;
    FMessageText.Exists := false;
    FStatsText.Exists := false;
    FCaptionText.SetText('');
    FColormapTint.Exists := false;
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
  if FPhoto then
  begin
    CheckPadTriggers;
    if FTouch.Exists then
      ApplyTouch(SecondsPassed);
    UpdatePhoto(SecondsPassed);
    if FPhoto then
      UpdateDynamicLights;
    Exit;
  end;
  FStatusBar.Exists := true;
  FNavigation.Exists := not FWorld.Player.Dead;
  FLevelTime := FLevelTime + SecondsPassed;
  CheckInspector;
  if FWorld.Map <> nil then
    FDebugDraw.BuildMap(FWorld.Map);
  FDebugDraw.UpdateWorld(FWorld);
  FHelpLabel.Exists := FHelpVisible and not TouchMode;
  CheckPadTriggers;
  if FTouch.Exists then
    ApplyTouch(SecondsPassed);

  if AutoTestDemo <> '' then
  begin
    { handled above }
  end else
  { The browser cannot write the screenshots (and has no demo-less
    autotests: a page URL's map without a demo is a plain game). }
  if (AutoTestPrefix <> '') {$ifdef WASI} and false {$endif} then
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
  { Doom never lets the player sink below the floor; the walk navigation
    can (a long frame on a slow machine steps the fall through it, after
    which nothing stops it and the fall speed grows without bound: CI once
    logged a Z of -1e23 and NaN transforms). Put the feet back on the
    floor and stop the fall. }
  Sec := FWorld.Map.SectorAt(Feet.X, Feet.Y);
  if (Sec >= 0) and (Feet.Z < FWorld.Map.Sectors[Sec].FloorHeight - 4) then
  begin
    Feet.Z := FWorld.Map.Sectors[Sec].FloorHeight;
    CamPos := DoomToCge(Feet.X, Feet.Y, Feet.Z + PlayerViewHeight);
    FViewport.Camera.Translation := CamPos;
    FNavigation.CancelFalling;
    WritelnLog('Player', 'Below the floor of sector %d, put back on it', [Sec]);
  end;
  { The walk since last frame, in Doom units a tic (Boom ice turns part of
    it into momentum), and the floor's walking speed (Boom mud and ice). }
  if FWalkKnown and (SecondsPassed > 0) then
  begin
    FWorld.PlayerWalkVX := Clamped((Feet.X - FPrevFeet.X - FPushedX) / (SecondsPassed * 35), -30, 30);
    FWorld.PlayerWalkVY := Clamped((Feet.Y - FPrevFeet.Y - FPushedY) / (SecondsPassed * 35), -30, 30);
  end else
  begin
    FWorld.PlayerWalkVX := 0;
    FWorld.PlayerWalkVY := 0;
  end;
  FPrevFeet := Feet;
  FPushedX := 0;
  FPushedY := 0;
  FWalkKnown := true;
  FNavigation.MoveSpeed := 290 * FWorld.PlayerMoveFactor;

  PerfT := Timer;
  FWorld.Update(SecondsPassed, Feet.X, Feet.Y, Feet.Z, DoomAngleFromCamera, CamPos, CamDir);
  FPerfWorld := FPerfWorld + TimerSeconds(Timer, PerfT);
  { A demo plays: the view is its camera. }
  if FWorld.Replaying then
    FViewport.Camera.SetView(FWorld.ReplayCameraPos, FWorld.ReplayCameraDir, Vector3(0, 1, 0));

  if FWorld.PlayerTeleported then
  begin
    FWorld.PlayerTeleported := false;
    PlacePlayer(FWorld.PlayerTeleportX, FWorld.PlayerTeleportY, FWorld.PlayerTeleportZ, FWorld.PlayerTeleportAngle);
  end;

  { Knockback: move the camera by the world's push with the navigation's
    collisions (walls slide it); stop the push when nothing moved. }
  if (FWorld.PlayerPushDX <> 0) or (FWorld.PlayerPushDY <> 0) then
  begin
    if TWalkNavigationAccess(FNavigation).Move(
      DoomToCge(FWorld.PlayerPushDX, FWorld.PlayerPushDY, 0), false, true) then
    begin
      FPushedX := FPushedX + FWorld.PlayerPushDX;
      FPushedY := FPushedY + FWorld.PlayerPushDY;
    end else
      FWorld.StopPush;
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
  if (MouseHeld(Settings.Mouse[gaFire]) and not FSuppressFire) or
     ((Settings.Keys[gaFire, 0] <> keyNone) and Container.Pressed.Items[Settings.Keys[gaFire, 0]]) or
     ((Settings.Keys[gaFire, 1] <> keyNone) and Container.Pressed.Items[Settings.Keys[gaFire, 1]]) or
     GamepadFireHeld or (FTouch.Exists and FTouch.FireHeld) then
    FWorld.FireWeapon
  else
    FWorld.ReleaseFire;

  P := FWorld.Player;
  FPaletteFlash.Color := FPaletteTints[FWorld.PaletteIndex];
  FColormapTint.Color := FWorld.ColormapTint;
  FColormapTint.Exists := (FWorld.ColormapTint.W > 0) and not FAutomap.Exists;
  { Doom's colormaps: the gun flash lights the room, invulnerability and
    the light amplification visor fix the colormap (DoomLighting). }
  DoomLightingInstance.ExtraLight := FWorld.Player.ExtraLight;
  DoomLightingInstance.FixedColormap := FWorld.FixedColormap;
  { Spectre fuzz in Doom's pixels, a new pattern start every tic. }
  DoomLightingInstance.FuzzScale := Max(1, FViewport.EffectiveHeight / 200);
  DoomLightingInstance.FuzzPhase := FuzzPhaseOfTic(FWorld.Tic);
  FMessageText.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
  { The browser only locks the pointer after a click or key press (and drops
    it on Esc or another window): say so instead of a dead mouse. }
  FClickPrompt.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
  FClickPrompt.Exists := (FSlotMenu = SlotMenuNone) and not FIntermission and
    not FWorld.Player.Dead and not TouchMode and
    (FForceClickPrompt or ((AutoTestPrefix = '') and Settings.MouseLook and
     not (FNavigation.MouseLook and Container.PointerLock.Active)));
  FAutomapTitle.Exists := FAutomap.Exists;
  if FAutomap.Exists then
  begin
    FAutomapTitle.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
    FAutomapTitle.SetText(UpperCase(FStrings.LevelName(FMapName, Wad.IsDoom2)));
    FAutomapTitle.Anchor(vpBottom, FStatusBar.Height + 4);
  end;
  { Kills, items, secrets and the level time, above the automap's title. }
  FStatsText.Exists := Settings.ShowStats;
  if FStatsText.Exists then
  begin
    FStatsText.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
    FStatsText.SetText(Format('K %d/%d  I %d/%d  S %d/%d  %d:%2.2d', [P.Kills, P.TotalKills,
      P.Items, P.TotalItems, P.Secrets, P.TotalSecrets, Trunc(FLevelTime) div 60, Trunc(FLevelTime) mod 60]));
    if FAutomapTitle.Exists then
      FStatsText.Anchor(vpBottom, FStatusBar.Height + 6 + FAutomapTitle.EffectiveHeight)
    else
      FStatsText.Anchor(vpBottom, FStatusBar.Height + 4);
  end;
  { Closed captions, a line below the message's place. }
  if Settings.Captions then
  begin
    FCaptionText.SetScale(Max(1, Round(FViewport.EffectiveHeight / 200)));
    FCaptionText.SetText(UpperCase(FCaptions.Text(FWorld.Tic)));
    FCaptionText.Anchor(vpTop, -8 - 10 * Max(1, Round(FViewport.EffectiveHeight / 200)));
  end else
    FCaptionText.SetText('');
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
  UpdateDynamicLights;
  FPerfWeapon := FPerfWeapon + TimerSeconds(Timer, PerfT);
  Inc(FPerfFrames);
  FPerfClock := FPerfClock + SecondsPassed;
  if FPerfClock >= 10 then
    PerfLog;
  FCrosshair.Exists := (FNavigation.MouseLook or FTouch.Exists) and not P.Dead and not FAutomap.Exists;

  if FWorld.ExitRequested then
  begin
    Info := MapInfoFor(FMapName);
    if (Info <> nil) and Info.NoIntermission then
    begin
      { UMAPINFO "nointermission": no stats screen, on to the story text
        or the next map. }
      FWorld.ExitRequested := false;
      WritelnLog('MapInfo', '%s: no intermission', [FMapName]);
      FinishIntermission;
    end else
    { Doom 1 (G_DoCompleted): ExM8 goes straight to the finale (a
      UMAPINFO text comes after the intermission). }
    if Wad.IsDoom2 or MapInfoDecidesFinale(FMapName, FWorld.SecretExit) or not StartFinale then
      StartIntermission;
  end;
end;

function TViewPlay.Press(const Event: TInputPressRelease): Boolean;
var
  Idx: Integer;
  K: TKey;
  BoundAction: TGameAction;
begin
  Result := inherited;
  if Result then Exit;
  if FWorld = nil then Exit;

  { Gamepad buttons: the bound actions in the game (GameSettings' Pad),
    the keys of the same meaning in the menus and the intermission. }
  if Event.EventType = itGameController then
  begin
    if (not FIntermission) and (FSlotMenu = SlotMenuNone) and
       PadPressed(PadButtonOfEvent(Event)) then
      Exit(true);
    if GamepadKey(Event, FIntermission or (FSlotMenu <> SlotMenuNone), K) then
      Exit(Press(InputKey(Container.MousePosition, K, '', [])));
    Exit;
  end;

  if FIntermission then
  begin
    if FPendingMap <> '' then Exit;
    if (FIntermissionTime > 0.3) and (Event.IsKey(keyE) or Event.IsKey(keySpace) or
       Event.IsKey(keyEnter) or Event.IsMouseButton(buttonLeft) or Event.IsKey(keyCtrl) or
       EventIs(Event, gaUse) or EventIs(Event, gaFire)) then
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

  { Photo mode: only leaving it, screenshots and the view's look. }
  if FPhoto then
  begin
    if EventIs(Event, gaPhoto) or Event.IsKey(keyEscape) then
    begin
      SetPhotoMode(false);
      Exit(true);
    end;
    if EventIs(Event, gaScreenshot) then
    begin
      { Without the hint in the picture. }
      FMessageText.SetText('');
      FPhotoHintTime := 0;
      WritelnLog('Photo', 'Screenshot saved: %s', [Container.SaveScreenToDefaultFile]);
      Exit(true);
    end;
    if EventIs(Event, gaUse) then
    begin
      TogglePhotoRunning;
      Exit(true);
    end;
    if Event.IsKey(keyPlus) or Event.IsKey(keyNumpadPlus) or Event.IsKey(keyEqual) or
       ((Event.EventType = itMouseWheel) and (Event.MouseWheelScroll > 0)) then
    begin
      PhotoZoom(1);
      Exit(true);
    end;
    if Event.IsKey(keyMinus) or Event.IsKey(keyNumpadMinus) or
       ((Event.EventType = itMouseWheel) and (Event.MouseWheelScroll < 0)) then
    begin
      PhotoZoom(-1);
      Exit(true);
    end;
    if Event.IsKey(keyLeftBracket) or Event.IsKey(keyRightBracket) then
    begin
      if Event.IsKey(keyLeftBracket) then PhotoTilt(-1) else PhotoTilt(1);
      Exit(true);
    end;
    if not (EventIs(Event, gaGamma) or EventIs(Event, gaLightDiminish) or EventIs(Event, gaMouseLook)) then
      Exit(true);
  end else
  if EventIs(Event, gaPhoto) then
  begin
    SetPhotoMode(true);
    Exit(true);
  end;
  if EventIs(Event, gaEditor) then
  begin
    OpenEditor;
    Exit(true);
  end;
  if EventIs(Event, gaUse) then
  begin
    FWorld.UseInFront;
    Exit(true);
  end;
  if EventIs(Event, gaGamma) then
  begin
    SetGamma((Settings.Gamma + 1) mod (MaxGamma + 1));
    Exit(true);
  end;
  if EventIs(Event, gaStats) then
  begin
    Settings.ShowStats := not Settings.ShowStats;
    SaveSettings;
    WritelnLog('Stats', 'Overlay %s', [Iff(Settings.ShowStats, 'shown', 'hidden')]);
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
  if EventIs(Event, gaFire) then
  begin
    FWorld.FireWeapon;
    Exit(true);
  end;
  { The wheel zooms the automap while it is shown. }
  if FAutomap.Exists and (Event.EventType = itMouseWheel) then
  begin
    if Event.MouseWheelScroll > 0 then FAutomap.ZoomBy(1.25) else FAutomap.ZoomBy(1 / 1.25);
    Exit(true);
  end;
  if EventIs(Event, gaNextWeapon) then
  begin
    FWorld.NextWeapon(1);
    Exit(true);
  end;
  if EventIs(Event, gaPrevWeapon) then
  begin
    FWorld.NextWeapon(-1);
    Exit(true);
  end;
  for Idx := 1 to 7 do
  begin
    if EventIs(Event, TGameAction(Ord(gaWeapon1) + Idx - 1)) then
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
  if EventIs(Event, gaQuickSave) then
  begin
    SaveGame(0);
    Exit(true);
  end;
  if EventIs(Event, gaQuickLoad) then
  begin
    LoadGame(0);
    Exit(true);
  end;
  if EventIs(Event, gaAutomap) then
  begin
    FAutomap.Exists := not FAutomap.Exists;
    Exit(true);
  end;
  { A key bound to an action handled elsewhere (moving, turning and
    running are the navigation's) does nothing else, e.g. "-" bound to
    strafing must not zoom the automap. }
  if ActionOfEvent(Event, BoundAction) and
     not (BoundAction in [gaGrid, gaRevealMap, gaLightDiminish, gaMouseLook, gaMusic, gaHelp,
       gaNextMap, gaPrevMap, gaScreenshot]) then
    Exit;
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
    if EventIs(Event, gaGrid) then
    begin
      FAutomap.Grid := not FAutomap.Grid;
      if FAutomap.Grid then
        FWorld.ShowMessage(FWorld.Text('AMSTR_GRIDON', 'Grid ON'))
      else
        FWorld.ShowMessage(FWorld.Text('AMSTR_GRIDOFF', 'Grid OFF'));
      Exit(true);
    end;
    if EventIs(Event, gaRevealMap) then
    begin
      FAutomap.ShowAll := not FAutomap.ShowAll;
      Exit(true);
    end;
  end;
  { The toggles are remembered (GameSettings). }
  if EventIs(Event, gaLightDiminish) then
  begin
    DoomLightingInstance.Diminish := not DoomLightingInstance.Diminish;
    Settings.Diminish := DoomLightingInstance.Diminish;
    SaveSettings;
    Exit(true);
  end;
  if EventIs(Event, gaMouseLook) then
  begin
    FNavigation.MouseLook := not FNavigation.MouseLook;
    Settings.MouseLook := FNavigation.MouseLook;
    SaveSettings;
    Exit(true);
  end;
  if EventIs(Event, gaMusic) and (Music <> nil) then
  begin
    Music.Enabled := not Music.Enabled;
    Settings.MusicOn := Music.Enabled;
    SaveSettings;
    FWorld.ShowMessage('Music ' + BoolToStr(Music.Enabled, 'on', 'off'));
    Exit(true);
  end;
  if EventIs(Event, gaHelp) then
  begin
    FHelpVisible := not FHelpVisible;
    FHelpLabel.Exists := FHelpVisible;
    Exit(true);
  end;
  if EventIs(Event, gaNextMap) or EventIs(Event, gaPrevMap) then
  begin
    Idx := Wad.MapNames.IndexOf(FMapName);
    if EventIs(Event, gaNextMap) then Inc(Idx) else Dec(Idx);
    if Idx < 0 then Idx := Wad.MapNames.Count - 1;
    if Idx >= Wad.MapNames.Count then Idx := 0;
    StartMap(Wad.MapNames[Idx], true);
    Exit(true);
  end;
  if EventIs(Event, gaScreenshot) then
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
