{ Game controllers (gamepads): CGE reads them on Windows and Linux
  (CastleGameControllers; the web build has no backend for them yet).
  The sticks drive TCastleWalkNavigation (UseGameController); buttons are
  turned into the keys the views already handle, so menus, the
  intermission and the game need no gamepad-specific code. }
unit GameGamepad;

interface

uses CastleKeysMouse;

{ Start reading controllers (call once at startup). }
procedure InitializeGamepads;

{ The key a controller button stands for: in menus (title, Doom's in-game
  menu, intermission) the D-pad is the arrows, A (south) Enter, B (east) and
  Menu Escape; in the game A is use (E), View the automap (Tab) and Menu
  Escape. False for buttons with no key (the bumpers switch weapons, see
  GamepadWeaponStep). }
function GamepadKey(const Event: TInputPressRelease; const InMenu: Boolean;
  out Key: TKey): Boolean;

{ +1 / -1 for the right / left bumper (next / previous weapon), else 0. }
function GamepadWeaponStep(const Event: TInputPressRelease): Integer;

{ The fire trigger (right trigger) held on any controller. }
function GamepadFireHeld: Boolean;

implementation

uses CastleGameControllers, CastleLog;

procedure InitializeGamepads;
var
  I: Integer;
begin
  Controllers.Initialize;
  for I := 0 to Controllers.Count - 1 do
    WritelnLog('Gamepad', 'Controller %d: %s', [I, Controllers[I].Name]);
end;

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
    case Event.Controller.Button of
      gbSouth, gbWest: Key := keyE;
      gbView: Key := keyTab;
      gbMenu: Key := keyEscape;
      else ;
    end;
  Result := Key <> keyNone;
end;

function GamepadWeaponStep(const Event: TInputPressRelease): Integer;
begin
  Result := 0;
  if Event.EventType <> itGameController then Exit;
  if Event.Controller.Button = gbRightBumper then Result := 1
  else if Event.Controller.Button = gbLeftBumper then Result := -1;
end;

function GamepadFireHeld: Boolean;
var
  I: Integer;
begin
  Result := false;
  for I := 0 to Controllers.Count - 1 do
    if Controllers[I].AxisRightTrigger > 0.5 then
      Exit(true);
end;

end.
