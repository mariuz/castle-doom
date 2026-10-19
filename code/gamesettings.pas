{ Player settings that outlive the session: sound and music volume (Doom's
  0..15 scales), music on / off, light diminishing, mouse look and the
  video options (field of view, fullscreen, UI scale, the browser's render
  resolution). Stored as
  JSON next to the save games (GameSaveStorage: a castle-config: file on the
  desktop, localStorage in the browser). }
unit GameSettings;

interface

uses CastleKeysMouse, CastleVectors;

type
  { The bindable actions of the game (two keys each; the mouse's left
    button always fires and its wheel changes weapons). The Controls page
    shows them in three pages: movement and actions, weapons, hotkeys
    (ControlsPages). The menus' keys (F1-F4, Esc, arrows, Enter) and the
    automap's zoom stay fixed. }
  TGameAction = (gaForward, gaBackward, gaStrafeLeft, gaStrafeRight,
    gaTurnLeft, gaTurnRight, gaRun, gaFire, gaUse, gaAutomap,
    gaWeapon1, gaWeapon2, gaWeapon3, gaWeapon4, gaWeapon5, gaWeapon6, gaWeapon7,
    gaNextWeapon, gaPrevWeapon,
    gaLightDiminish, gaMouseLook, gaMusic, gaHelp, gaGrid, gaRevealMap,
    gaNextMap, gaPrevMap, gaScreenshot, gaQuickSave, gaQuickLoad, gaStats, gaGamma, gaPhoto);

  { The gamepad's bindable actions (the sticks move and look, Start opens
    the menu, and the menus use the D-pad, A and B whatever is bound). }
  TPadAction = (gpaFire, gpaUse, gpaAutomap, gpaNextWeapon, gpaPrevWeapon);
  { A gamepad button in the standard (Xbox) layout; the triggers count as
    buttons when pressed past half way. Start and Guide are not bindable. }
  { A mouse button or wheel direction bound to an action (one per action,
    besides its two keys; Chocolate Doom's mouseb_ settings). }
  TMouseBind = (mbNone, mbLeft, mbMiddle, mbRight, mbButton4, mbButton5,
    mbWheelUp, mbWheelDown);

  TPadButton = (pbNone, pbA, pbB, pbX, pbY, pbLeftBumper, pbRightBumper,
    pbLeftTrigger, pbRightTrigger, pbLeftStick, pbRightStick,
    pbDPadUp, pbDPadDown, pbDPadLeft, pbDPadRight, pbView);

  TGameSettings = record
    SfxVolume, MusicVolume: Integer;
    MusicOn: Boolean;
    Diminish: Boolean;
    MouseLook: Boolean;
    { Doom's options page: mouse sensitivity 0..9, messages on / off. }
    MouseSensitivity: Integer;
    ShowMessages: Boolean;
    { The level statistics overlay (kills, items, secrets, time). }
    ShowStats: Boolean;
    { Closed captions: a line per sound heard, with its direction. }
    Captions: Boolean;
    { Missiles, explosions and muzzle flashes light their surroundings
      (an option next to the vanilla look). }
    DynamicLights: Boolean;
    { Doom's gamma correction level, 0 (off) .. MaxGamma (F11). }
    Gamma: Integer;
    { Best times in seconds, by BestTimeKey (WADs, map, skill). }
    BestTimeKeys: array of String;
    BestTimes: array of Integer;
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
    { Mouse bindings: a button or wheel direction per action. }
    Mouse: array [TGameAction] of TMouseBind;
    { Touch controls: mirrored for the left hand, and their size in
      percent (TouchSizes). }
    TouchLeftHanded: Boolean;
    TouchSize: Integer;
    { Their opacity in percent (TouchOpacities), and the buttons' own
      places (GameTouch's TTouchButton order without tbNone: fractions of
      the width and height from the bottom left; X < 0 = the default). }
    TouchOpacity: Integer;
    TouchPlaces: array [0..5] of TVector2;
    { Gamepad bindings: two buttons per action (pbNone = unused). }
    Pad: array [TPadAction, 0..1] of TPadButton;
  end;

const
  MaxVolume = 15;
  MinFieldOfView = 60;
  MaxFieldOfView = 120;
  MinUiScale = 50;
  MaxUiScale = 200;
  MinRenderScale = 25;
  MaxRenderScale = 100;
  { The touch controls' size choices, in percent. }
  TouchSizes: array [0..3] of Integer = (75, 100, 125, 150);
  TouchOpacities: array [0..3] of Integer = (25, 50, 75, 100);
  { settings.json's names of the touch buttons (TouchPlaces' order). }
  TouchButtonIds: array [0..5] of String = ('fire', 'use', 'prevWeapon',
    'nextWeapon', 'automap', 'menu');
  { Gamma correction levels (Doom's usegamma): 0 = off. }
  MaxGamma = 4;
  { The frame rate cap's choices (0 = no cap); 120 is CGE's default. }
  FrameCaps: array [0..4] of Integer = (35, 60, 120, 144, 0);

const
  ActionNames: array [TGameAction] of String = (
    'Move forward', 'Move backward', 'Strafe left', 'Strafe right',
    'Turn left', 'Turn right', 'Run', 'Fire', 'Use / open', 'Automap',
    'Fist / chainsaw', 'Pistol', 'Shotguns', 'Chaingun', 'Rocket launcher',
    'Plasma rifle', 'BFG 9000', 'Next weapon', 'Previous weapon',
    'Light diminishing', 'Mouse look', 'Music on / off', 'Help', 'Automap grid',
    'Reveal map', 'Next map', 'Previous map', 'Screenshot', 'Quick save',
    'Quick load', 'Level statistics', 'Brightness (gamma)', 'Photo mode');
  { The JSON keys of settings.json's "keys" object. }
  ActionIds: array [TGameAction] of String = (
    'forward', 'backward', 'strafeLeft', 'strafeRight',
    'turnLeft', 'turnRight', 'run', 'fire', 'use', 'automap',
    'weapon1', 'weapon2', 'weapon3', 'weapon4', 'weapon5', 'weapon6', 'weapon7',
    'nextWeapon', 'prevWeapon',
    'lightDiminish', 'mouseLook', 'music', 'help', 'grid', 'revealMap',
    'nextMap', 'prevMap', 'screenshot', 'quickSave', 'quickLoad', 'stats', 'gamma', 'photo');
  DefaultKeys: array [TGameAction, 0..1] of TKey = (
    (keyW, keyArrowUp), (keyS, keyArrowDown), (keyA, keyNone), (keyD, keyNone),
    (keyArrowLeft, keyNone), (keyArrowRight, keyNone), (keyShift, keyNone),
    (keyCtrl, keyNone), (keyE, keySpace), (keyTab, keyNone),
    (key1, keyNone), (key2, keyNone), (key3, keyNone), (key4, keyNone),
    (key5, keyNone), (key6, keyNone), (key7, keyNone),
    (keyNone, keyNone), (keyNone, keyNone),
    (keyF, keyNone), (keyM, keyNone), (keyJ, keyNone), (keyH, keyNone),
    (keyG, keyNone), (keyI, keyNone), (keyN, keyNone), (keyP, keyNone),
    (keyF5, keyNone), (keyF6, keyNone), (keyF9, keyNone), (keyL, keyNone), (keyF11, keyNone),
    (keyO, keyNone));

  { settings.json's mouse names and the Controls page's. }
  MouseBindIds: array [TMouseBind] of String = ('None', 'Left', 'Middle',
    'Right', 'Button4', 'Button5', 'WheelUp', 'WheelDown');
  MouseBindNames: array [TMouseBind] of String = ('-', 'Left button',
    'Middle button', 'Right button', 'Button 4', 'Button 5', 'Wheel up',
    'Wheel down');
  DefaultMouse: array [TGameAction] of TMouseBind = (
    mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbLeft, mbNone, mbNone,
    mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbWheelUp, mbWheelDown,
    mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone, mbNone);

  { The Controls page's pages: their titles and first / last actions. }
  ControlsPageCount = 3;
  ControlsPageNames: array [0..ControlsPageCount - 1] of String = (
    'Movement', 'Weapons', 'Hotkeys');
  ControlsPageFirst: array [0..ControlsPageCount - 1] of TGameAction = (
    gaForward, gaWeapon1, gaLightDiminish);
  ControlsPageLast: array [0..ControlsPageCount - 1] of TGameAction = (
    gaAutomap, gaPrevWeapon, gaPhoto);

  PadActionNames: array [TPadAction] of String = (
    'Fire', 'Use / open', 'Automap', 'Next weapon', 'Previous weapon');
  { The JSON keys of settings.json's "pad" object. }
  PadActionIds: array [TPadAction] of String = (
    'fire', 'use', 'automap', 'nextWeapon', 'prevWeapon');
  { settings.json's, the log's and the Controls page's button names. }
  PadButtonNames: array [TPadButton] of String = ('-', 'A', 'B', 'X', 'Y',
    'LB', 'RB', 'LT', 'RT', 'LS', 'RS', 'DPadUp', 'DPadDown', 'DPadLeft',
    'DPadRight', 'View');
  DefaultPad: array [TPadAction, 0..1] of TPadButton = (
    (pbRightTrigger, pbNone), (pbA, pbX), (pbView, pbNone),
    (pbRightBumper, pbNone), (pbLeftBumper, pbNone));

var
  Settings: TGameSettings;

{ Read the stored settings (defaults for anything missing). }
procedure LoadSettings;
procedure SaveSettings;

{ The best time of a level (seconds), -1 when none; SetBestTime stores it
  (SaveSettings writes it). }
function BestTimeKey(const WadDescription, MapName: String; const Skill: Integer): String;
function BestTime(const Key: String): Integer;
procedure SetBestTime(const Key: String; const Seconds: Integer);

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
{ The touch layout for the log: "Touch: right-handed, size 100%". }
function TouchSummary: String;
{ The next touch size in TouchSizes (wrapping). }
function NextTouchSize(const Size: Integer): Integer;
{ The next opacity in TouchOpacities (wrapping). }
function NextTouchOpacity(const Opacity: Integer): Integer;
{ All touch buttons back at their default places. }
procedure ResetTouchPlaces;
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
  F1-F4 of the menus, F8 of the engine's inspector). }
function BindKey(const Action: TGameAction; const Slot: Integer; const Key: TKey): Boolean;
{ "W / Up", "Tab", "-" for the help panel and the Controls page. }
function KeyName(const Key: TKey): String;
function ActionKeysText(const Action: TGameAction): String;
{ The keys and the mouse binding: "Ctrl / Left button". }
function ActionInputText(const Action: TGameAction): String;
{ The bindings for the log. }
function KeysSummary: String;
{ Mouse bindings: the defaults (the left button fires, the wheel changes
  weapons), the action a button or wheel event is bound to, binding one
  (taken from any other action; mbNone clears the action's). }
procedure ResetMouse;
function MouseIs(const B: TMouseBind; const Action: TGameAction): Boolean;
function MouseBindOfEvent(const Event: TInputPressRelease): TMouseBind;
procedure BindMouse(const Action: TGameAction; const B: TMouseBind);
function StrToMouseBind(const S: String): TMouseBind;
function MouseSummary: String;
{ The event is a key or mouse input bound to Action. }
function EventIs(const Event: TInputPressRelease; const Action: TGameAction): Boolean;
{ The action of a key or mouse event (False when none). }
function ActionOfEvent(const Event: TInputPressRelease; out Action: TGameAction): Boolean;

{ Read a "keys" object (settings.json's, as JSON text) over the current
  bindings, like LoadSettings (for the unit tests). }
procedure ApplyKeysJson(const JsonText: String);

{ Gamepad bindings, like the keys'. }
procedure ResetPad;
function PadIs(const Button: TPadButton; const Action: TPadAction): Boolean;
{ Bind Button to slot Slot of Action, removing it from other actions;
  pbNone clears the slot. }
procedure BindPad(const Action: TPadAction; const Slot: Integer; const Button: TPadButton);
{ A button by its name (PadButtonNames, any case); pbNone when unknown. }
function StrToPadButton(const S: String): TPadButton;
function PadActionText(const Action: TPadAction): String;
function PadSummary: String;

implementation

uses SysUtils, Math, FpJson, JsonParser, CastleLog, CastleUtils, CastleWindow, CastleApplicationProperties,
  { Desktop OpenGL for the swap interval (not on the web or Android, whose
    GLES has none). }
  {$if not (defined(WASI) or defined(ANDROID))} CastleGL, {$endif}
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
  if Key in [keyEscape, keyF1..keyF4, keyF8] then Exit(false);
  if Key <> keyNone then
    for A := Low(TGameAction) to High(TGameAction) do
      for I := 0 to 1 do
        if Settings.Keys[A, I] = Key then
          Settings.Keys[A, I] := keyNone;
  Settings.Keys[Action, Slot] := Key;
  Result := true;
end;

procedure ResetMouse;
var
  A: TGameAction;
begin
  for A := Low(TGameAction) to High(TGameAction) do
    Settings.Mouse[A] := DefaultMouse[A];
end;

function MouseIs(const B: TMouseBind; const Action: TGameAction): Boolean;
begin
  Result := (B <> mbNone) and (Settings.Mouse[Action] = B);
end;

function MouseBindOfEvent(const Event: TInputPressRelease): TMouseBind;
begin
  Result := mbNone;
  if Event.EventType = itMouseButton then
    case Event.MouseButton of
      buttonLeft: Result := mbLeft;
      buttonMiddle: Result := mbMiddle;
      buttonRight: Result := mbRight;
      buttonExtra1: Result := mbButton4;
      buttonExtra2: Result := mbButton5;
    end
  else
  if (Event.EventType = itMouseWheel) and (Event.MouseWheelScroll <> 0) and Event.MouseWheelVertical then
  begin
    if Event.MouseWheelScroll > 0 then
      Result := mbWheelUp
    else
      Result := mbWheelDown;
  end;
end;

procedure BindMouse(const Action: TGameAction; const B: TMouseBind);
var
  A: TGameAction;
begin
  if B <> mbNone then
    for A := Low(TGameAction) to High(TGameAction) do
      if Settings.Mouse[A] = B then
        Settings.Mouse[A] := mbNone;
  Settings.Mouse[Action] := B;
end;

function StrToMouseBind(const S: String): TMouseBind;
var
  B: TMouseBind;
begin
  for B := Low(TMouseBind) to High(TMouseBind) do
    if SameText(MouseBindIds[B], S) then
      Exit(B);
  Result := mbNone;
end;

function MouseSummary: String;
var
  A: TGameAction;
begin
  Result := 'Mouse:';
  for A := Low(TGameAction) to High(TGameAction) do
    if Settings.Mouse[A] <> mbNone then
      Result := Result + ' ' + ActionIds[A] + ' ' + MouseBindIds[Settings.Mouse[A]] + ';';
end;

function EventIs(const Event: TInputPressRelease; const Action: TGameAction): Boolean;
begin
  if Event.EventType = itKey then
    Result := KeyIs(Event.Key, Action)
  else
    Result := MouseIs(MouseBindOfEvent(Event), Action);
end;

function ActionOfEvent(const Event: TInputPressRelease; out Action: TGameAction): Boolean;
var
  A: TGameAction;
begin
  if Event.EventType = itKey then
    Exit(ActionOfKey(Event.Key, Action));
  for A := Low(TGameAction) to High(TGameAction) do
    if MouseIs(MouseBindOfEvent(Event), A) then
    begin
      Action := A;
      Exit(true);
    end;
  Action := gaForward;
  Result := false;
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

function ActionInputText(const Action: TGameAction): String;
begin
  Result := ActionKeysText(Action);
  if Settings.Mouse[Action] <> mbNone then
  begin
    if Result = '-' then
      Result := MouseBindNames[Settings.Mouse[Action]]
    else
      Result := Result + ' / ' + MouseBindNames[Settings.Mouse[Action]];
  end;
end;

function KeysSummary: String;
var
  A: TGameAction;
begin
  Result := 'Keys:';
  for A := Low(TGameAction) to High(TGameAction) do
    Result := Result + ' ' + ActionIds[A] + ' ' + ActionKeysText(A) + ';';
end;

procedure ResetPad;
var
  A: TPadAction;
begin
  for A := Low(TPadAction) to High(TPadAction) do
  begin
    Settings.Pad[A, 0] := DefaultPad[A, 0];
    Settings.Pad[A, 1] := DefaultPad[A, 1];
  end;
end;

function PadIs(const Button: TPadButton; const Action: TPadAction): Boolean;
begin
  Result := (Button <> pbNone) and ((Settings.Pad[Action, 0] = Button) or (Settings.Pad[Action, 1] = Button));
end;

procedure BindPad(const Action: TPadAction; const Slot: Integer; const Button: TPadButton);
var
  A: TPadAction;
  I: Integer;
begin
  if Button <> pbNone then
    for A := Low(TPadAction) to High(TPadAction) do
      for I := 0 to 1 do
        if Settings.Pad[A, I] = Button then
          Settings.Pad[A, I] := pbNone;
  Settings.Pad[Action, Slot] := Button;
end;

function StrToPadButton(const S: String): TPadButton;
var
  B: TPadButton;
begin
  for B := Succ(pbNone) to High(TPadButton) do
    if SameText(S, PadButtonNames[B]) then
      Exit(B);
  Result := pbNone;
end;

function PadActionText(const Action: TPadAction): String;
begin
  if Settings.Pad[Action, 0] = pbNone then
    Result := PadButtonNames[Settings.Pad[Action, 1]]
  else if Settings.Pad[Action, 1] = pbNone then
    Result := PadButtonNames[Settings.Pad[Action, 0]]
  else
    Result := PadButtonNames[Settings.Pad[Action, 0]] + ' / ' + PadButtonNames[Settings.Pad[Action, 1]];
end;

function PadSummary: String;
var
  A: TPadAction;
begin
  Result := 'Gamepad:';
  for A := Low(TPadAction) to High(TPadAction) do
    Result := Result + ' ' + PadActionIds[A] + ' ' + PadActionText(A) + ';';
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
  Settings.TouchLeftHanded := false;
  Settings.TouchSize := 100;
  ResetTouchPlaces;
  Settings.TouchOpacity := 100;
  ResetKeys;
  ResetMouse;
  ResetPad;
end;

{ settings.json's "keys": {"forward": ["W", "Up"], ...} (KeyToStr names;
  a missing action keeps its defaults, except keys a stored action uses:
  settings from before the weapon and hotkey actions existed may have
  given F or 1 to another action). }
procedure ReadKeys(const J: TJSONObject);
var
  A, B: TGameAction;
  Arr: TJSONArray;
  I, K: Integer;
  Stored: array [TGameAction] of Boolean;
begin
  for A := Low(TGameAction) to High(TGameAction) do
  begin
    Stored[A] := J.Find(ActionIds[A], Arr);
    if Stored[A] then
      for I := 0 to 1 do
        if I < Arr.Count then
          Settings.Keys[A, I] := StrToKey(Arr.Strings[I], keyNone)
        else
          Settings.Keys[A, I] := keyNone;
  end;
  for A := Low(TGameAction) to High(TGameAction) do
    if not Stored[A] then
      for I := 0 to 1 do
        for B := Low(TGameAction) to High(TGameAction) do
          if Stored[B] then
            for K := 0 to 1 do
              if (Settings.Keys[A, I] <> keyNone) and (Settings.Keys[B, K] = Settings.Keys[A, I]) then
                Settings.Keys[A, I] := keyNone;
end;

procedure ApplyKeysJson(const JsonText: String);
var
  Data: TJSONData;
begin
  Data := GetJSON(JsonText);
  try
    if Data is TJSONObject then
      ReadKeys(TJSONObject(Data));
  finally
    FreeAndNil(Data);
  end;
end;

{ settings.json's "touchButtons": {"fire": [0.9, 0.4], ...} (only the
  moved buttons). }
procedure ReadTouchPlaces(const J: TJSONObject);
var
  I: Integer;
  Arr: TJSONArray;
begin
  ResetTouchPlaces;
  for I := 0 to High(TouchButtonIds) do
    if J.Find(TouchButtonIds[I], Arr) and (Arr.Count = 2) then
      Settings.TouchPlaces[I] := Vector2(
        Clamped(Arr.Floats[0], 0, 1), Clamped(Arr.Floats[1], 0, 1));
end;

function WriteTouchPlaces: TJSONObject;
var
  I: Integer;
  Arr: TJSONArray;
begin
  Result := TJSONObject.Create;
  for I := 0 to High(TouchButtonIds) do
    if Settings.TouchPlaces[I].X >= 0 then
    begin
      Arr := TJSONArray.Create;
      Arr.Add(Settings.TouchPlaces[I].X);
      Arr.Add(Settings.TouchPlaces[I].Y);
      Result.Add(TouchButtonIds[I], Arr);
    end;
end;

{ settings.json's "mouse": {"fire": "Left", ...}; without it, the
  defaults. }
procedure ReadMouse(const J: TJSONObject);
var
  A: TGameAction;
  S: String;
begin
  for A := Low(TGameAction) to High(TGameAction) do
  begin
    S := J.Get(ActionIds[A], '');
    if S <> '' then
      BindMouse(A, StrToMouseBind(S))
    else
      Settings.Mouse[A] := mbNone;
  end;
end;

function WriteMouse: TJSONObject;
var
  A: TGameAction;
begin
  Result := TJSONObject.Create;
  for A := Low(TGameAction) to High(TGameAction) do
    if Settings.Mouse[A] <> mbNone then
      Result.Add(ActionIds[A], MouseBindIds[Settings.Mouse[A]]);
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

{ settings.json's "pad": {"fire": ["RT", "None"], ...} (PadButtonNames). }
procedure ReadPad(const J: TJSONObject);
var
  A: TPadAction;
  Arr: TJSONArray;
  I: Integer;
begin
  for A := Low(TPadAction) to High(TPadAction) do
    if J.Find(PadActionIds[A], Arr) then
      for I := 0 to 1 do
        if I < Arr.Count then
          Settings.Pad[A, I] := StrToPadButton(Arr.Strings[I])
        else
          Settings.Pad[A, I] := pbNone;
end;

function WritePad: TJSONObject;
var
  A: TPadAction;
  Arr: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  for A := Low(TPadAction) to High(TPadAction) do
  begin
    Arr := TJSONArray.Create;
    for I := 0 to 1 do
      if Settings.Pad[A, I] = pbNone then
        Arr.Add('None')
      else
        Arr.Add(PadButtonNames[Settings.Pad[A, I]]);
    Result.Add(PadActionIds[A], Arr);
  end;
end;

function BestTimeKey(const WadDescription, MapName: String; const Skill: Integer): String;
begin
  Result := Format('%s %s skill %d', [WadDescription, UpperCase(MapName), Skill + 1]);
end;

function BestTime(const Key: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Settings.BestTimeKeys) do
    if Settings.BestTimeKeys[I] = Key then Exit(Settings.BestTimes[I]);
  Result := -1;
end;

procedure SetBestTime(const Key: String; const Seconds: Integer);
var
  I: Integer;
begin
  for I := 0 to High(Settings.BestTimeKeys) do
    if Settings.BestTimeKeys[I] = Key then
    begin
      Settings.BestTimes[I] := Seconds;
      Exit;
    end;
  SetLength(Settings.BestTimeKeys, Length(Settings.BestTimeKeys) + 1);
  SetLength(Settings.BestTimes, Length(Settings.BestTimes) + 1);
  Settings.BestTimeKeys[High(Settings.BestTimeKeys)] := Key;
  Settings.BestTimes[High(Settings.BestTimes)] := Seconds;
end;

procedure LoadSettings;
var
  Text: String;
  D: TJSONData;
  J, KeysJ, MouseJ, PadJ, PlacesJ, BestJ: TJSONObject;
  BestI: Integer;
begin
  Defaults;
  SetLength(Settings.BestTimeKeys, 0);
  SetLength(Settings.BestTimes, 0);
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
    Settings.ShowStats := J.Get('showStats', Settings.ShowStats);
    Settings.Captions := J.Get('captions', Settings.Captions);
    Settings.DynamicLights := J.Get('dynamicLights', Settings.DynamicLights);
    Settings.Gamma := Clamped(J.Get('gamma', Settings.Gamma), 0, MaxGamma);
    if J.Find('bestTimes', BestJ) then
      for BestI := 0 to BestJ.Count - 1 do
        SetBestTime(BestJ.Names[BestI], BestJ.Items[BestI].AsInteger);
    Settings.FieldOfView := Clamped(J.Get('fieldOfView', Settings.FieldOfView), MinFieldOfView, MaxFieldOfView);
    Settings.Fullscreen := J.Get('fullscreen', Settings.Fullscreen);
    Settings.UiScale := Clamped(J.Get('uiScale', Settings.UiScale), MinUiScale, MaxUiScale);
    Settings.RenderScale := Clamped(J.Get('renderScale', Settings.RenderScale), MinRenderScale, MaxRenderScale);
    Settings.VSync := J.Get('vsync', Settings.VSync);
    Settings.FrameCap := Clamped(J.Get('frameCap', Settings.FrameCap), 0, 1000);
    Settings.TouchLeftHanded := J.Get('touchLeftHanded', Settings.TouchLeftHanded);
    Settings.TouchSize := Clamped(J.Get('touchSize', Settings.TouchSize), TouchSizes[0], TouchSizes[High(TouchSizes)]);
    Settings.TouchOpacity := Clamped(J.Get('touchOpacity', Settings.TouchOpacity), TouchOpacities[0], 100);
    if J.Find('touchButtons', PlacesJ) then
      ReadTouchPlaces(PlacesJ);
    if J.Find('keys', KeysJ) then
      ReadKeys(KeysJ);
    if J.Find('mouse', MouseJ) then
      ReadMouse(MouseJ);
    if J.Find('pad', PadJ) then
      ReadPad(PadJ);
  finally
    FreeAndNil(J);
  end;
  WritelnLog('Settings', 'Sound %d, music %d (%s), light diminishing %s, mouse look %s', [
    Settings.SfxVolume, Settings.MusicVolume, BoolToStr(Settings.MusicOn, 'on', 'off'),
    BoolToStr(Settings.Diminish, 'on', 'off'), BoolToStr(Settings.MouseLook, 'on', 'off')]);
  WritelnLog('Settings', VideoSummary);
  WritelnLog('Settings', KeysSummary);
  WritelnLog('Settings', MouseSummary);
  WritelnLog('Settings', TouchSummary);
  WritelnLog('Settings', PadSummary);
end;

procedure SaveSettings;
var
  J, Best: TJSONObject;
  BestI: Integer;
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
    J.Add('showStats', Settings.ShowStats);
    J.Add('captions', Settings.Captions);
    J.Add('dynamicLights', Settings.DynamicLights);
    J.Add('gamma', Settings.Gamma);
    Best := TJSONObject.Create;
    for BestI := 0 to High(Settings.BestTimeKeys) do
      Best.Add(Settings.BestTimeKeys[BestI], Settings.BestTimes[BestI]);
    J.Add('bestTimes', Best);
    J.Add('fieldOfView', Settings.FieldOfView);
    J.Add('fullscreen', Settings.Fullscreen);
    J.Add('uiScale', Settings.UiScale);
    J.Add('renderScale', Settings.RenderScale);
    J.Add('vsync', Settings.VSync);
    J.Add('frameCap', Settings.FrameCap);
    J.Add('touchLeftHanded', Settings.TouchLeftHanded);
    J.Add('touchSize', Settings.TouchSize);
    J.Add('touchOpacity', Settings.TouchOpacity);
    J.Add('touchButtons', WriteTouchPlaces);
    J.Add('keys', WriteKeys);
    J.Add('mouse', WriteMouse);
    J.Add('pad', WritePad);
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

function TouchSummary: String;
var
  I: Integer;
begin
  Result := Format('Touch: %s, size %d%%, opacity %d%%', [BoolToStr(Settings.TouchLeftHanded, 'left-handed', 'right-handed'),
    Settings.TouchSize, Settings.TouchOpacity]);
  for I := 0 to High(Settings.TouchPlaces) do
    if Settings.TouchPlaces[I].X >= 0 then
      Result := Result + Format(', %s at %.3f %.3f', [TouchButtonIds[I], Settings.TouchPlaces[I].X,
        Settings.TouchPlaces[I].Y]);
end;

function NextTouchOpacity(const Opacity: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(TouchOpacities) do
    if TouchOpacities[I] > Opacity then
      Exit(TouchOpacities[I]);
  Result := TouchOpacities[0];
end;

procedure ResetTouchPlaces;
var
  I: Integer;
begin
  for I := 0 to High(Settings.TouchPlaces) do
    Settings.TouchPlaces[I] := Vector2(-1, -1);
end;

function NextTouchSize(const Size: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(TouchSizes) do
    if TouchSizes[I] > Size then
      Exit(TouchSizes[I]);
  Result := TouchSizes[0];
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
{$if defined(LINUX) and not defined(ANDROID)}
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
  {$ifdef ANDROID}
  Exit;
  {$endif}
  {$ifdef MSWINDOWS}
  if Assigned(wglSwapIntervalEXT) then
  begin
    if wglSwapIntervalEXT(Interval) then Result := 'wglSwapIntervalEXT' else Result := 'wglSwapIntervalEXT failed';
  end;
  {$endif}
  {$if defined(LINUX) and not defined(ANDROID)}
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
