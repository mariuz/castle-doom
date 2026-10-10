{ Player settings that outlive the session: sound and music volume (Doom's
  0..15 scales), music on / off, light diminishing, mouse look and the
  video options (field of view, fullscreen, UI scale, the browser's render
  resolution). Stored as
  JSON next to the save games (GameSaveStorage: a castle-config: file on the
  desktop, localStorage in the browser). }
unit GameSettings;

interface

uses CastleKeysMouse;

type
  { The bindable actions of the game (two keys each; the mouse's left
    button always fires, the gamepad has its own fixed layout). }
  TGameAction = (gaForward, gaBackward, gaStrafeLeft, gaStrafeRight,
    gaTurnLeft, gaTurnRight, gaRun, gaFire, gaUse, gaAutomap);

  TGameSettings = record
    SfxVolume, MusicVolume: Integer;
    MusicOn: Boolean;
    Diminish: Boolean;
    MouseLook: Boolean;
    { Doom's options page: mouse sensitivity 0..9, messages on / off. }
    MouseSensitivity: Integer;
    ShowMessages: Boolean;
    { Video: horizontal field of view in degrees (Doom's is 90), window
      or fullscreen (desktop), the 2D layer's scale in percent, and the
      browser's render resolution in percent of the canvas' pixels. }
    FieldOfView: Integer;
    Fullscreen: Boolean;
    UiScale: Integer;
    RenderScale: Integer;
    { Desktop: v-sync (the driver's swap interval) and the frame rate cap
      (ApplicationProperties.LimitFPS; 0 = none). The browser always
      draws on its own refresh. }
    VSync: Boolean;
    FrameCap: Integer;
    { Key bindings: two keys per action (keyNone = unused). }
    Keys: array [TGameAction, 0..1] of TKey;
  end;

const
  MaxVolume = 15;
  MinFieldOfView = 60;
  MaxFieldOfView = 120;
  MinUiScale = 50;
  MaxUiScale = 200;
  MinRenderScale = 25;
  MaxRenderScale = 100;
  { The frame rate cap's choices (0 = no cap); 120 is CGE's default. }
  FrameCaps: array [0..4] of Integer = (35, 60, 120, 144, 0);

const
  ActionNames: array [TGameAction] of String = (
    'Move forward', 'Move backward', 'Strafe left', 'Strafe right',
    'Turn left', 'Turn right', 'Run', 'Fire', 'Use / open', 'Automap');
  { The JSON keys of settings.json's "keys" object. }
  ActionIds: array [TGameAction] of String = (
    'forward', 'backward', 'strafeLeft', 'strafeRight',
    'turnLeft', 'turnRight', 'run', 'fire', 'use', 'automap');
  DefaultKeys: array [TGameAction, 0..1] of TKey = (
    (keyW, keyArrowUp), (keyS, keyArrowDown), (keyA, keyNone), (keyD, keyNone),
    (keyArrowLeft, keyNone), (keyArrowRight, keyNone), (keyShift, keyNone),
    (keyCtrl, keyNone), (keyE, keySpace), (keyTab, keyNone));

var
  Settings: TGameSettings;

{ Read the stored settings (defaults for anything missing). }
procedure LoadSettings;
procedure SaveSettings;

{ Gains for TCastleSound.Volume / TDoomMusic.Volume. The defaults keep the
  mix the game always had: effects at full volume, music at half. }
function SfxGain: Single;
function MusicGain: Single;
{ TCastleWalkNavigation.MouseLook*Sensitivity for the mouse sensitivity. }
function MouseLookSensitivity: Single;

{ Apply the video options that belong to the window: fullscreen, the UI
  scale (CastleSettings.xml's reference size divided by it) and, in the
  browser, the render resolution (the page's canvas sizing script, patched
  by tools/patch_web_page.py, multiplies the canvas' pixels by it). The
  field of view is the play view's camera (TViewPlay.ApplyFieldOfView).
  At Startup only turns fullscreen on (CGE's own --fullscreen stays). }
procedure ApplyWindowSettings(const Startup: Boolean = false);

{ The video options for the log. }
function VideoSummary: String;

{ The frame cap Steps choices further in FrameCaps (wrapping). }
function NextFrameCap(const Cap, Steps: Integer): Integer;
{ "60 FPS", "no cap". }
function FrameCapText(const Cap: Integer): String;

{ Key bindings. }
procedure ResetKeys;
{ Key is bound to Action (either slot). }
function KeyIs(const Key: TKey; const Action: TGameAction): Boolean;
{ The action Key is bound to; False when none. }
function ActionOfKey(const Key: TKey; out Action: TGameAction): Boolean;
{ Bind Key to slot Slot of Action, removing it from wherever else it was;
  keyNone clears the slot. False for keys that cannot be bound (Escape,
  the function keys, which the game and the engine's inspector use). }
function BindKey(const Action: TGameAction; const Slot: Integer; const Key: TKey): Boolean;
{ "W / Up", "Tab", "-" for the help panel and the Controls page. }
function KeyName(const Key: TKey): String;
function ActionKeysText(const Action: TGameAction): String;
{ The bindings for the log. }
function KeysSummary: String;

implementation

uses SysUtils, Math, FpJson, JsonParser, CastleLog, CastleUtils, CastleWindow, CastleApplicationProperties,
  {$ifndef WASI} CastleGL, {$endif}
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  GameSaveStorage;

const
  { data/CastleSettings.xml's ui_scaling reference size. }
  UiReferenceWidth = 1600;
  UiReferenceHeight = 900;

const
  SettingsUrl = 'castle-config:/settings.json';

procedure ResetKeys;
var
  A: TGameAction;
begin
  for A := Low(TGameAction) to High(TGameAction) do
  begin
    Settings.Keys[A, 0] := DefaultKeys[A, 0];
    Settings.Keys[A, 1] := DefaultKeys[A, 1];
  end;
end;

function KeyIs(const Key: TKey; const Action: TGameAction): Boolean;
begin
  Result := (Key <> keyNone) and ((Settings.Keys[Action, 0] = Key) or (Settings.Keys[Action, 1] = Key));
end;

function ActionOfKey(const Key: TKey; out Action: TGameAction): Boolean;
var
  A: TGameAction;
begin
  for A := Low(TGameAction) to High(TGameAction) do
    if KeyIs(Key, A) then
    begin
      Action := A;
      Exit(true);
    end;
  Action := gaForward;
  Result := false;
end;

function BindKey(const Action: TGameAction; const Slot: Integer; const Key: TKey): Boolean;
var
  A: TGameAction;
  I: Integer;
begin
  if Key in [keyEscape, keyF1..keyF12] then Exit(false);
  if Key <> keyNone then
    for A := Low(TGameAction) to High(TGameAction) do
      for I := 0 to 1 do
        if Settings.Keys[A, I] = Key then
          Settings.Keys[A, I] := keyNone;
  Settings.Keys[Action, Slot] := Key;
  Result := true;
end;

function KeyName(const Key: TKey): String;
begin
  if Key = keyNone then
    Result := '-'
  else
    Result := KeyToStr(Key);
end;

function ActionKeysText(const Action: TGameAction): String;
begin
  if Settings.Keys[Action, 0] = keyNone then
    Result := KeyName(Settings.Keys[Action, 1])
  else if Settings.Keys[Action, 1] = keyNone then
    Result := KeyName(Settings.Keys[Action, 0])
  else
    Result := KeyName(Settings.Keys[Action, 0]) + ' / ' + KeyName(Settings.Keys[Action, 1]);
end;

function KeysSummary: String;
var
  A: TGameAction;
begin
  Result := 'Keys:';
  for A := Low(TGameAction) to High(TGameAction) do
    Result := Result + ' ' + ActionIds[A] + ' ' + ActionKeysText(A) + ';';
end;

procedure Defaults;
begin
  Settings.SfxVolume := MaxVolume;
  Settings.MusicVolume := 8;
  Settings.MusicOn := true;
  Settings.Diminish := true;
  Settings.MouseLook := true;
  Settings.MouseSensitivity := 5;
  Settings.ShowMessages := true;
  Settings.FieldOfView := 90;
  Settings.Fullscreen := false;
  Settings.UiScale := 100;
  Settings.RenderScale := 100;
  Settings.VSync := false;
  Settings.FrameCap := 120;
  ResetKeys;
end;

{ settings.json's "keys": {"forward": ["W", "Up"], ...} (KeyToStr names;
  a missing action keeps its defaults). }
procedure ReadKeys(const J: TJSONObject);
var
  A: TGameAction;
  Arr: TJSONArray;
  I: Integer;
begin
  for A := Low(TGameAction) to High(TGameAction) do
    if J.Find(ActionIds[A], Arr) then
      for I := 0 to 1 do
        if I < Arr.Count then
          Settings.Keys[A, I] := StrToKey(Arr.Strings[I], keyNone)
        else
          Settings.Keys[A, I] := keyNone;
end;

function WriteKeys: TJSONObject;
var
  A: TGameAction;
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  for A := Low(TGameAction) to High(TGameAction) do
  begin
    Arr := TJSONArray.Create;
    Arr.Add(KeyToStr(Settings.Keys[A, 0]));
    Arr.Add(KeyToStr(Settings.Keys[A, 1]));
    Result.Add(ActionIds[A], Arr);
  end;
end;

procedure LoadSettings;
var
  Text: String;
  D: TJSONData;
  J, KeysJ: TJSONObject;
begin
  Defaults;
  if not SaveStorageRead(SettingsUrl, Text) then Exit;
  D := nil;
  try
    D := GetJSON(Text);
  except
    on E: Exception do
      WritelnWarning('Settings', 'Cannot read %s: %s', [SettingsUrl, E.Message]);
  end;
  if not (D is TJSONObject) then
  begin
    FreeAndNil(D);
    Exit;
  end;
  J := TJSONObject(D);
  try
    Settings.SfxVolume := Clamped(J.Get('sfxVolume', Settings.SfxVolume), 0, MaxVolume);
    Settings.MusicVolume := Clamped(J.Get('musicVolume', Settings.MusicVolume), 0, MaxVolume);
    Settings.MusicOn := J.Get('musicOn', Settings.MusicOn);
    Settings.Diminish := J.Get('diminish', Settings.Diminish);
    Settings.MouseLook := J.Get('mouseLook', Settings.MouseLook);
    Settings.MouseSensitivity := Clamped(J.Get('mouseSensitivity', Settings.MouseSensitivity), 0, 9);
    Settings.ShowMessages := J.Get('showMessages', Settings.ShowMessages);
    Settings.FieldOfView := Clamped(J.Get('fieldOfView', Settings.FieldOfView), MinFieldOfView, MaxFieldOfView);
    Settings.Fullscreen := J.Get('fullscreen', Settings.Fullscreen);
    Settings.UiScale := Clamped(J.Get('uiScale', Settings.UiScale), MinUiScale, MaxUiScale);
    Settings.RenderScale := Clamped(J.Get('renderScale', Settings.RenderScale), MinRenderScale, MaxRenderScale);
    Settings.VSync := J.Get('vsync', Settings.VSync);
    Settings.FrameCap := Clamped(J.Get('frameCap', Settings.FrameCap), 0, 1000);
    if J.Find('keys', KeysJ) then
      ReadKeys(KeysJ);
  finally
    FreeAndNil(J);
  end;
  WritelnLog('Settings', 'Sound %d, music %d (%s), light diminishing %s, mouse look %s', [
    Settings.SfxVolume, Settings.MusicVolume, BoolToStr(Settings.MusicOn, 'on', 'off'),
    BoolToStr(Settings.Diminish, 'on', 'off'), BoolToStr(Settings.MouseLook, 'on', 'off')]);
  WritelnLog('Settings', VideoSummary);
  WritelnLog('Settings', KeysSummary);
end;

procedure SaveSettings;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('sfxVolume', Settings.SfxVolume);
    J.Add('musicVolume', Settings.MusicVolume);
    J.Add('musicOn', Settings.MusicOn);
    J.Add('diminish', Settings.Diminish);
    J.Add('mouseLook', Settings.MouseLook);
    J.Add('mouseSensitivity', Settings.MouseSensitivity);
    J.Add('showMessages', Settings.ShowMessages);
    J.Add('fieldOfView', Settings.FieldOfView);
    J.Add('fullscreen', Settings.Fullscreen);
    J.Add('uiScale', Settings.UiScale);
    J.Add('renderScale', Settings.RenderScale);
    J.Add('vsync', Settings.VSync);
    J.Add('frameCap', Settings.FrameCap);
    J.Add('keys', WriteKeys);
    SaveStorageWrite(SettingsUrl, J.FormatJSON(AsCompressedJSON));
  finally
    FreeAndNil(J);
  end;
end;

function SfxGain: Single;
begin
  Result := Settings.SfxVolume / MaxVolume;
end;

function MouseLookSensitivity: Single;
const
  { G_BuildTiccmd: mousex = count * (sensitivity + 5) / 10, angleturn -=
    mousex * 8, in 1/65536 of a turn: 0.044 degrees a count at Doom's
    default 5. Twice that, about what Chocolate Doom's mouse acceleration
    gives at normal speeds and CGE's own default (0.1 degrees): a full turn
    is about 4000 pixels, 4 inches of a 1000 DPI mouse at Windows' default
    pointer speed. }
  DegreesPerCount = 2 * 8 * 360 / 65536;
begin
  { Radians per pixel, the unit of MouseLook*Sensitivity. }
  Result := DegToRad(DegreesPerCount * (Settings.MouseSensitivity + 5) / 10);
end;

function VideoSummary: String;
begin
  Result := Format('Video: field of view %d, %s, UI scale %d%%, render scale %d%%, v-sync %s, %s', [
    Settings.FieldOfView, BoolToStr(Settings.Fullscreen, 'fullscreen', 'window'),
    Settings.UiScale, Settings.RenderScale, BoolToStr(Settings.VSync, 'on', 'off'),
    FrameCapText(Settings.FrameCap)]);
end;

function NextFrameCap(const Cap, Steps: Integer): Integer;
var
  I, N: Integer;
begin
  N := Length(FrameCaps);
  I := 0;
  while (I < N) and (FrameCaps[I] <> Cap) do Inc(I);
  if I = N then I := 2; { an unusual value from settings.json: from 120 }
  Result := FrameCaps[((I + Steps) mod N + N) mod N];
end;

function FrameCapText(const Cap: Integer): String;
begin
  if Cap <= 0 then
    Result := 'no frame cap'
  else
    Result := Format('%d FPS cap', [Cap]);
end;

{$ifdef WASI}
{ A JavaScript function of this name exists on Obj (a missing one reads
  as a null TJOB_Object; InvokeJSTypeOf cannot tell, see GameGamepad). }
function HasJSFunction(const Obj: IJSObject; const Name: String): Boolean;
var
  V: TJOB_JSValue;
begin
  V := Obj.ReadJSPropertyValue(Name);
  Result := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
end;
{$endif}

{$ifndef WASI}
{ The driver's swap interval through the WGL / GLX extensions CGE's
  OpenGL unit loads (CGE sets it itself only on macOS). Returns how, or
  why not, for the log. }
function ApplySwapInterval(const Interval: Integer): String;
{$ifdef LINUX}
type
  TglXSwapIntervalMESA = function (Interval: Cardinal): Integer; cdecl;
  TglXGetCurrentDisplay = function: Pointer; cdecl;
  TglXGetCurrentDrawable = function: PtrUInt; cdecl;
var
  SwapMesa: TglXSwapIntervalMESA;
  GetDisplay: TglXGetCurrentDisplay;
  GetDrawable: TglXGetCurrentDrawable;
{$endif}
begin
  Result := 'not available';
  {$ifdef MSWINDOWS}
  if Assigned(wglSwapIntervalEXT) then
  begin
    if wglSwapIntervalEXT(Interval) then Result := 'wglSwapIntervalEXT' else Result := 'wglSwapIntervalEXT failed';
  end;
  {$endif}
  {$ifdef LINUX}
  Pointer(SwapMesa) := dglGetProcAddress('glXSwapIntervalMESA');
  if Assigned(SwapMesa) then
  begin
    if SwapMesa(Interval) = 0 then Exit('glXSwapIntervalMESA');
    Result := 'glXSwapIntervalMESA failed';
  end;
  Pointer(GetDisplay) := dglGetProcAddress('glXGetCurrentDisplay');
  Pointer(GetDrawable) := dglGetProcAddress('glXGetCurrentDrawable');
  if Assigned(glXSwapIntervalEXT) and Assigned(GetDisplay) and Assigned(GetDrawable) and
     (GetDisplay() <> nil) and (GetDrawable() <> 0) then
  begin
    glXSwapIntervalEXT(GetDisplay(), GetDrawable(), Interval);
    Result := 'glXSwapIntervalEXT';
  end;
  {$endif}
end;
{$endif}

var
  AppliedVSync: Integer = -1;

procedure ApplyWindowSettings(const Startup: Boolean);
var
  Window: TCastleWindow;
  How: String;
begin
  Window := Application.MainWindow;
  if Window = nil then Exit;
  Window.Container.UIReferenceWidth := UiReferenceWidth * 100 / Settings.UiScale;
  Window.Container.UIReferenceHeight := UiReferenceHeight * 100 / Settings.UiScale;
  {$ifdef WASI}
  { The page's canvas script (tools/patch_web_page.py) provides
    castleDoomSetScale; CGE's plain page does not. }
  if HasJSFunction(JSWindow, 'castleDoomSetScale') then
    JSWindow.InvokeJSNoResult('castleDoomSetScale', [Settings.RenderScale]);
  {$else}
  { The browser's fullscreen is the page's button (it needs a click). }
  if (Window.FullScreen <> Settings.Fullscreen) and (Settings.Fullscreen or not Startup) then
    Window.FullScreen := Settings.Fullscreen;
  ApplicationProperties.LimitFPS := Settings.FrameCap;
  { The swap interval only when it changes (and once at startup: the
    driver's default may be either). }
  if AppliedVSync <> Ord(Settings.VSync) then
  begin
    How := ApplySwapInterval(Ord(Settings.VSync));
    AppliedVSync := Ord(Settings.VSync);
    WritelnLog('Settings', 'V-sync %s (%s)', [BoolToStr(Settings.VSync, 'on', 'off'), How]);
  end;
  {$endif}
end;

function MusicGain: Single;
begin
  Result := Settings.MusicVolume / 16;
end;

end.
