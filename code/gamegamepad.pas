{ Game controllers (gamepads): CGE reads them on Windows and Linux
  (CastleGameControllers). The browser has no backend in CGE, so here the
  web build polls the Gamepad API (navigator.getGamepads(), standard
  mapping) every frame through JOB and feeds CGE's explicit backend, the
  one its console ports use; from there on the game sees the same
  TGameController objects and events as on the desktop.
  The sticks drive TCastleWalkNavigation (UseGameController). In the menus
  and the intermission the buttons are turned into the keys the views
  already handle; in the game they do what GameSettings' Pad bindings
  say (the Controls page rebinds them), Start opens the menu. }
unit GameGamepad;

interface

uses CastleKeysMouse, GameSettings;

type
  { One browser gamepad as the Gamepad API's standard mapping reports it
    (https://w3c.github.io/gamepad/#remapping): 17 buttons (0 A, 1 B, 2 X,
    3 Y, 4 / 5 bumpers, 6 / 7 triggers, 8 Back, 9 Start, 10 / 11 stick
    clicks, 12..15 D-pad up / down / left / right, 16 Guide) and 4 axes
    (left X, left Y, right X, right Y; down and right positive). }
  TWebPad = record
    Id: String;
    Axes: array [0..3] of Single;
    Pressed: array [0..17] of Boolean;
    { The triggers' analog values (buttons 6 and 7). }
    LeftTrigger, RightTrigger: Single;
  end;
  TWebPads = array [0..3] of TWebPad;

{ Start reading controllers (call once at startup). }
procedure InitializeGamepads;

{ The key a controller button stands for: in menus (title, Doom's in-game
  menu, intermission) the D-pad is the arrows, A (south) Enter, B (east) and
  Menu Escape; in the game only Menu is a key (Escape), the other buttons
  are bound to actions (PadButtonOfEvent). }
function GamepadKey(const Event: TInputPressRelease; const InMenu: Boolean;
  out Key: TKey): Boolean;

{ The game's name of a controller event's button; pbNone for other events
  and for Start, Guide and Share. }
function PadButtonOfEvent(const Event: TInputPressRelease): TPadButton;
{ The button (a trigger past half way) is held on any controller. }
function PadButtonHeld(const B: TPadButton): Boolean;
{ A button bound to the action is held. }
function PadActionHeld(const A: TPadAction): Boolean;
{ The fire action's buttons are held. }
function GamepadFireHeld: Boolean;
{ A controller event for a button (demo scripts); false for the triggers,
  which have no events (they are axes). }
function PadButtonEvent(const B: TPadButton; out Event: TInputPressRelease): Boolean;

var
  { Buttons the demo scripts hold down (PADDOWN / PADUP). }
  SimulatedPadHeld: set of TPadButton;

{ Make CGE's controllers the Count browser pads read this frame: the list
  follows the pads (a change is logged), the sticks become AxisLeft /
  AxisRight (Y up), the triggers the trigger axes and the standard
  mapping's buttons CGE's buttons. The web build calls this every frame;
  it is public (and plain Pascal) so the unit tests cover the mapping on
  the desktop. }
procedure ApplyWebPads(const Pads: TWebPads; const Count: Integer);

implementation

uses SysUtils, Math,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, CastleApplicationProperties, {$endif}
  CastleGameControllers, CastleInternalGameControllersExplicit, CastleVectors,
  CastleLog;

function GamepadKey(const Event: TInputPressRelease; const InMenu: Boolean;
  out Key: TKey): Boolean;
begin
  Result := false;
  Key := keyNone;
  if Event.EventType <> itGameController then Exit;
  if InMenu then
    case Event.Controller.Button of
      gbDPadUp: Key := keyArrowUp;
      gbDPadDown: Key := keyArrowDown;
      gbDPadLeft: Key := keyArrowLeft;
      gbDPadRight: Key := keyArrowRight;
      gbSouth: Key := keyEnter;
      gbEast, gbMenu: Key := keyEscape;
      else ;
    end
  else
  if Event.Controller.Button = gbMenu then
    Key := keyEscape;
  Result := Key <> keyNone;
end;

const
  { The CGE button of each pad button (gbMenu for the triggers: none). }
  PadToCge: array [TPadButton] of TGameControllerButton = (gbMenu,
    gbSouth, gbEast, gbWest, gbNorth, gbLeftBumper, gbRightBumper,
    gbMenu, gbMenu, gbLeftStickClick, gbRightStickClick,
    gbDPadUp, gbDPadDown, gbDPadLeft, gbDPadRight, gbView);

function PadButtonOfEvent(const Event: TInputPressRelease): TPadButton;
var
  B: TPadButton;
begin
  Result := pbNone;
  if Event.EventType <> itGameController then Exit;
  for B := Succ(pbNone) to High(TPadButton) do
    if (B <> pbLeftTrigger) and (B <> pbRightTrigger) and (PadToCge[B] = Event.Controller.Button) then
      Exit(B);
end;

function PadButtonHeld(const B: TPadButton): Boolean;
var
  I: Integer;
begin
  if B = pbNone then Exit(false);
  if B in SimulatedPadHeld then Exit(true);
  Result := false;
  for I := 0 to Controllers.Count - 1 do
    case B of
      pbLeftTrigger: if Controllers[I].AxisLeftTrigger > 0.5 then Exit(true);
      pbRightTrigger: if Controllers[I].AxisRightTrigger > 0.5 then Exit(true);
      else if Controllers[I].Pressed[PadToCge[B]] then Exit(true);
    end;
end;

function PadActionHeld(const A: TPadAction): Boolean;
begin
  Result := PadButtonHeld(Settings.Pad[A, 0]) or PadButtonHeld(Settings.Pad[A, 1]);
end;

function GamepadFireHeld: Boolean;
begin
  Result := PadActionHeld(gpaFire);
end;

function PadButtonEvent(const B: TPadButton; out Event: TInputPressRelease): Boolean;
begin
  Event := Default(TInputPressRelease);
  if B in [pbNone, pbLeftTrigger, pbRightTrigger] then Exit(false);
  Event.EventType := itGameController;
  Event.Controller.Button := PadToCge[B];
  Event.Controller.Caption := PadButtonNames[B];
  Result := true;
end;

{ Browser pads -> CGE ------------------------------------------------------ }

procedure ApplyWebPads(const Pads: TWebPads; const Count: Integer);
const
  { The standard mapping's button for each CGE button. }
  ButtonIndex: array [TGameControllerButton] of Integer = (
    3, 1, 0, 2,     // gbNorth (Y), gbEast (B), gbSouth (A), gbWest (X)
    4, 5,           // gbLeftBumper, gbRightBumper
    10, 11,         // gbLeftStickClick, gbRightStickClick
    12, 15, 13, 14, // gbDPadUp, gbDPadRight, gbDPadDown, gbDPadLeft
    8, 9,           // gbView (Back), gbMenu (Start)
    16, 17);        // gbGuide, gbShare (the standard mapping has no Share)
var
  Backend: TExplicitControllerManagerBackend;
  I: Integer;
  B: TGameControllerButton;
  Changed: Boolean;
begin
  Backend := Controllers.InternalExplicitBackend as TExplicitControllerManagerBackend;
  Changed := Count <> Controllers.Count;
  for I := 0 to Count - 1 do
    if (not Changed) and (Controllers[I].Name <> Pads[I].Id) then
      Changed := true;
  if Changed then
  begin
    Backend.SetCount(Count);
    for I := 0 to Count - 1 do
    begin
      Controllers[I].InternalBackend.Name := Pads[I].Id;
      WritelnLog('Gamepad', 'Controller %d: %s', [I, Pads[I].Id]);
    end;
    if Count = 0 then
      WritelnLog('Gamepad', 'No controller connected');
  end;
  for I := 0 to Count - 1 do
  begin
    { The browser's Y axes point down, CGE's up (forward). }
    Backend.SetAxisLeft(I, Vector2(Pads[I].Axes[0], -Pads[I].Axes[1]));
    Backend.SetAxisRight(I, Vector2(Pads[I].Axes[2], -Pads[I].Axes[3]));
    Backend.SetAxisLeftTrigger(I, Pads[I].LeftTrigger);
    Backend.SetAxisRightTrigger(I, Pads[I].RightTrigger);
    for B := Low(TGameControllerButton) to High(TGameControllerButton) do
      Backend.SetButton(I, B, Pads[I].Pressed[ButtonIndex[B]]);
  end;
end;

{$ifdef WASI}

type
  { Reads navigator.getGamepads() every frame (ApplicationProperties.OnUpdate,
    before the container turns button changes into events). Each read is a
    JOB call (about 45 per pad and frame); the list may hold nulls, and
    pads appear only after the user pressed a button on them. }
  TWebGamepads = class
    Pads: TWebPads;
    procedure Poll(Sender: TObject);
  end;

var
  WebGamepads: TWebGamepads;

procedure TWebGamepads.Poll(Sender: TObject);
var
  Navigator, List, Pad, Axes, Buttons, Button: IJSObject;
  Item: TJOB_JSValue;
  Count, N, I, J, NAxes, NButtons: Integer;
  IsPad: Boolean;
begin
  Count := 0;
  Navigator := JSWindow.ReadJSPropertyObject('navigator', TJSObject);
  List := Navigator.InvokeJSObjectResult('getGamepads', [], TJSObject);
  if List <> nil then
  begin
    N := Min(List.ReadJSPropertyLongInt('length'), High(TWebPads) + 1);
    for I := 0 to N - 1 do
    begin
      { Disconnected slots are null: read the element as a generic value
        (a typed read of null raises, which the web build cannot survive). }
      Item := List.ReadJSPropertyValue(IntToStr(I));
      { JOB wraps null as a TJOB_Object with a nil Value. }
      IsPad := (Item is TJOB_Object) and (TJOB_Object(Item).Value <> nil);
      if IsPad then
        Pad := TJOB_Object(Item).Value;
      FreeAndNil(Item);
      if (not IsPad) or (not Pad.ReadJSPropertyBoolean('connected')) then
        Continue;
      Pads[Count].Id := UTF8Encode(Pad.ReadJSPropertyUnicodeString('id'));
      Axes := Pad.ReadJSPropertyObject('axes', TJSObject);
      NAxes := Min(Axes.ReadJSPropertyLongInt('length'), 4);
      for J := 0 to 3 do
        if J < NAxes then
          Pads[Count].Axes[J] := Axes.ReadJSPropertyDouble(IntToStr(J))
        else
          Pads[Count].Axes[J] := 0;
      Buttons := Pad.ReadJSPropertyObject('buttons', TJSObject);
      NButtons := Min(Buttons.ReadJSPropertyLongInt('length'), 18);
      Pads[Count].LeftTrigger := 0;
      Pads[Count].RightTrigger := 0;
      for J := 0 to 17 do
        if J < NButtons then
        begin
          Button := Buttons.ReadJSPropertyObject(IntToStr(J), TJSObject);
          Pads[Count].Pressed[J] := Button.ReadJSPropertyBoolean('pressed');
          if J = 6 then
            Pads[Count].LeftTrigger := Button.ReadJSPropertyDouble('value')
          else
          if J = 7 then
            Pads[Count].RightTrigger := Button.ReadJSPropertyDouble('value');
        end else
          Pads[Count].Pressed[J] := false;
      Inc(Count);
    end;
  end;
  ApplyWebPads(Pads, Count);
end;

{ Obj.Name is a JavaScript function (or at least an object). JOB's
  InvokeJSTypeOf cannot tell: its JavaScript side feeds the typeof text
  itself to the result mapper, so it always answers "string". }
function HasFunction(const Obj: IJSObject; const Name: String): Boolean;
var
  V: TJOB_JSValue;
begin
  V := Obj.ReadJSPropertyValue(Name);
  Result := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
end;

{ navigator.getGamepads exists and the page's permissions policy allows
  it (in a cross-origin iframe without "allow=gamepad" the call throws,
  and a JavaScript exception stops the WebAssembly program). }
function WebGamepadsAvailable: Boolean;
var
  Navigator, Policy: IJSObject;
begin
  Result := false;
  Navigator := JSWindow.ReadJSPropertyObject('navigator', TJSObject);
  if (Navigator = nil) or (not HasFunction(Navigator, 'getGamepads')) then
    Exit;
  Policy := JSDocument.ReadJSPropertyObject('permissionsPolicy', TJSObject);
  if Policy = nil then
    Policy := JSDocument.ReadJSPropertyObject('featurePolicy', TJSObject);
  if (Policy <> nil) and HasFunction(Policy, 'allowsFeature') and
     (not Policy.InvokeJSBooleanResult('allowsFeature', [UTF8Decode('gamepad')])) then
    Exit;
  Result := true;
end;

{$endif}

procedure InitializeGamepads;
var
  I: Integer;
begin
  Controllers.Initialize;
  for I := 0 to Controllers.Count - 1 do
    WritelnLog('Gamepad', 'Controller %d: %s', [I, Controllers[I].Name]);
  {$ifdef WASI}
  if WebGamepadsAvailable then
  begin
    WebGamepads := TWebGamepads.Create;
    ApplicationProperties.OnUpdate.Add(@WebGamepads.Poll);
    WritelnLog('Gamepad', 'Browser Gamepad API: polling navigator.getGamepads() each frame (press a button on the pad)');
  end else
    WritelnLog('Gamepad', 'Browser Gamepad API not available on this page');
  {$endif}
end;

{$ifdef WASI}
finalization
  FreeAndNil(WebGamepads);
{$endif}
end.
