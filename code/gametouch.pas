{ Touch controls for phones and tablets: a floating stick on the left
  third moves (pushed to the edge it runs), dragging anywhere else turns
  and looks, and round buttons fire (dragging the fire button also turns),
  use, change weapons, toggle the automap and open the menu.

  The play view shows them while TouchMode is on. In the browser the page
  script (tools/patch_web_page.py) tracks the fingers itself, because
  CGE's web backend reports every pointer as finger 0 (no multi-touch):
  while the game is being played it keeps touch pointer events from the
  engine and PollTouches reads the fingers every frame; it also says
  whether the last pointer was a finger (TouchMode) or a mouse. On the
  desktop, --touch turns TouchMode on and the mouse acts as one finger
  (the autotests also place fingers with TDOWN / TMOVE / TUP). }
unit GameTouch;

interface

uses Classes,
  CastleVectors, CastleUIControls, CastleKeysMouse, CastleGLImages, CastleRectangles,
  DoomGraphics;

type
  TTouchButton = (tbNone, tbFire, tbUse, tbPrevWeapon, tbNextWeapon, tbAutomap, tbMenu, tbPhoto);
  TTouchButtonEvent = procedure (const Button: TTouchButton) of object;
  TTouchMovedEvent = procedure (const Button: TTouchButton; const Position: TVector2) of object;

  TTouchRole = (trStick, trLook, trButton);

  TTouchPoint = record
    Id: Integer;
    Role: TTouchRole;
    Button: TTouchButton;
    { Where the stick's centre is (it follows a finger pushed beyond the
      edge), the last position the look was taken from, and now. }
    Start, Last, Pos: TVector2;
  end;

  TDoomTouchControls = class(TCastleUserInterface)
  strict private
    FTouches: array of TTouchPoint;
    FLook: TVector2;
    FGraphics: TDoomGraphics;
    FLabels: array [TTouchButton] of TDrawableImage;
    FLabelsMade: Boolean;
    FOnButton: TTouchButtonEvent;
    FWidth, FHeight: Single;
    FLeftHanded: Boolean;
    FSizePercent: Integer;
    FOpacity: Single;
    { Buttons placed by the player: fractions of the width and height
      (X < 0: the default place). }
    FCustom: array [TTouchButton] of TVector2;
    FEditing: Boolean;
    FOnButtonMoved: TTouchMovedEvent;
    { The layout's unit: the shorter side, times the size setting. }
    function LayoutUnit: Single;
    { Left-handed layouts mirror the right-handed one. }
    function Mirror(const P: TVector2): TVector2;
    function InStickZone(const P: TVector2): Boolean;
    function IndexOf(const Id: Integer): Integer;
    procedure UpdateSize;
    { Status bar height: the play view's bar is a tenth of the width. }
    function BottomMargin: Single;
    function StickRadius: Single;
    function StickHome: TVector2;
    procedure MakeLabels;
    procedure FreeLabels;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Render; override;
    function Press(const Event: TInputPressRelease): Boolean; override;
    function Release(const Event: TInputPressRelease): Boolean; override;
    function Motion(const Event: TInputMotion): Boolean; override;

    { Fingers, in pixels from the control's bottom-left corner. }
    procedure TouchDown(const Id: Integer; const Position: TVector2);
    procedure TouchMove(const Id: Integer; const Position: TVector2);
    procedure TouchUp(const Id: Integer);
    { Lift every finger (the controls are hidden). }
    procedure ReleaseAll;
    { The size used when the control is not in a container (unit tests). }
    procedure SetTestSize(const W, H: Single);
    { The button drawn around Position, tbNone when none. }
    function ButtonAt(const Position: TVector2): TTouchButton;
    { A button's circle in the control's pixels. }
    procedure ButtonCircle(const B: TTouchButton; out Middle: TVector2; out Radius: Single);
    { The stick: X strafes right, Y moves forward, length 0..1. }
    function MoveVector: TVector2;
    function FireHeld: Boolean;
    { Degrees turned right (X) and up (Y) by the fingers since the last call. }
    function TakeLook: TVector2;
    function TouchCount: Integer;
    function TouchId(const Index: Integer): Integer;
    property Graphics: TDoomGraphics read FGraphics write FGraphics;
    { The layout (GameSettings' touchLeftHanded, touchSize): the stick on
      the right and the buttons on the left (MAP and MENU stay at the top
      right); the stick and buttons scaled
      by SizePercent (MinTouchSize..MaxTouchSize, 100 = the default). }
    property LeftHanded: Boolean read FLeftHanded write FLeftHanded;
    { Drawing opacity, 0..1 (GameSettings' touchOpacity). }
    property Opacity: Single read FOpacity write FOpacity;
    { A button's own place: its middle as fractions of the width and
      height from the bottom-left corner; a negative X restores the
      default place. }
    procedure SetButtonPlace(const B: TTouchButton; const Fraction: TVector2);
    function ButtonPlace(const B: TTouchButton): TVector2;
    { Layout editing: a finger on a button drags it instead of pressing it
      (OnButtonMoved tells where it was dropped, as fractions); the stick
      and the look do nothing. }
    property Editing: Boolean read FEditing write FEditing;
    property OnButtonMoved: TTouchMovedEvent read FOnButtonMoved write FOnButtonMoved;
    property SizePercent: Integer read FSizePercent write FSizePercent;
    property OnButton: TTouchButtonEvent read FOnButton write FOnButton;
  end;

const
  TouchButtonNames: array [TTouchButton] of String = ('', 'FIRE', 'USE', '<', '>', 'MAP', 'MENU', 'PHOTO');

var
  { Show the touch controls: --touch, the TOUCH demo command, or in the
    browser a finger was the last pointer used. }
  TouchMode: Boolean;
  { --touch (or TOUCH): stay in touch mode whatever the browser says. }
  TouchForced: Boolean;

{ The browser: read the fingers into Controls (when not nil, the game is
  being played: the page then keeps touch events from the engine) and
  update TouchMode. Does nothing on the desktop. }
procedure PollTouches(const Controls: TDoomTouchControls);
{ Apply the page script's answer (public for the unit tests): "1" or "0"
  (the last pointer was a finger), then ";id,x,y" for each finger. }
procedure ApplyTouchState(const S: String; const Controls: TDoomTouchControls);

{ A phone's on-screen keyboard while a menu is typing (a save name, the
  custom page's seed): shown in touch mode through CGE's Android
  "keyboard" service (CastleEngineManifest.xml), whose keys arrive as
  ordinary key presses; logged as "Keyboard:" on every platform. }
procedure ShowTextKeyboard(const Text: String);
procedure HideTextKeyboard;
{ Is the on-screen keyboard up (asked for by ShowTextKeyboard)? }
function TextKeyboardShown: Boolean;

implementation

uses SysUtils, Math, CastleMessaging,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  CastleColors, CastleImages, CastleGLUtils, CastleLog, CastleComponentSerialize,
  DoomFont;

const
  { Drag sensitivity: half a turn over the control's width. }
  LookDegreesPerWidth = 180;
  StickDeadZone = 0.12;
  { The stick takes fingers that land left of this part of the width. }
  StickZone = 0.4;

constructor TDoomTouchControls.Create(AOwner: TComponent);
var
  B: TTouchButton;
begin
  inherited;
  FullSize := true;
  FWidth := 1600;
  FHeight := 900;
  FSizePercent := 100;
  FOpacity := 1;
  for B := Low(TTouchButton) to High(TTouchButton) do
    FCustom[B] := Vector2(-1, -1);
end;

procedure TDoomTouchControls.SetButtonPlace(const B: TTouchButton; const Fraction: TVector2);
begin
  FCustom[B] := Fraction;
end;

function TDoomTouchControls.ButtonPlace(const B: TTouchButton): TVector2;
begin
  Result := FCustom[B];
end;

function TDoomTouchControls.LayoutUnit: Single;
begin
  Result := Min(FWidth, FHeight) * EnsureRange(FSizePercent, 50, 200) / 100;
end;

function TDoomTouchControls.Mirror(const P: TVector2): TVector2;
begin
  if FLeftHanded then
    Result := Vector2(FWidth - P.X, P.Y)
  else
    Result := P;
end;

function TDoomTouchControls.InStickZone(const P: TVector2): Boolean;
begin
  if FLeftHanded then
    Result := P.X > (1 - StickZone) * FWidth
  else
    Result := P.X < StickZone * FWidth;
end;

destructor TDoomTouchControls.Destroy;
begin
  FreeLabels;
  inherited;
end;

procedure TDoomTouchControls.FreeLabels;
var
  B: TTouchButton;
begin
  for B := Low(TTouchButton) to High(TTouchButton) do
    FreeAndNil(FLabels[B]);
  FLabelsMade := false;
end;

procedure TDoomTouchControls.MakeLabels;
var
  B: TTouchButton;
  Img: TRGBAlphaImage;
  W: Integer;
begin
  FLabelsMade := true;
  if FGraphics = nil then Exit;
  for B := Succ(tbNone) to High(TTouchButton) do
  begin
    W := Max(1, DoomTextWidth(FGraphics, TouchButtonNames[B]));
    Img := TRGBAlphaImage.Create(W, 8);
    Img.Clear(Vector4Byte(0, 0, 0, 0));
    DrawDoomText(FGraphics, Img, 0, 0, TouchButtonNames[B]);
    FLabels[B] := TDrawableImage.Create(Img, false, true);
  end;
end;

procedure TDoomTouchControls.SetTestSize(const W, H: Single);
begin
  FWidth := W;
  FHeight := H;
end;

procedure TDoomTouchControls.UpdateSize;
var
  R: TFloatRectangle;
begin
  if Container = nil then Exit;
  R := RenderRect;
  if (R.Width > 0) and (R.Height > 0) then
  begin
    FWidth := R.Width;
    FHeight := R.Height;
  end;
end;

function TDoomTouchControls.BottomMargin: Single;
begin
  Result := Min(FWidth / 10, 0.3 * FHeight);
end;

function TDoomTouchControls.StickRadius: Single;
begin
  Result := 0.13 * LayoutUnit;
end;

function TDoomTouchControls.StickHome: TVector2;
var
  U: Single;
begin
  U := LayoutUnit;
  Result := Mirror(Vector2(0.25 * U, BottomMargin + 0.25 * U));
end;

procedure TDoomTouchControls.ButtonCircle(const B: TTouchButton; out Middle: TVector2; out Radius: Single);
var
  U, M, W, H: Single;
  Spot: TTouchButton;
begin
  W := FWidth;
  H := FHeight;
  U := LayoutUnit;
  M := BottomMargin;
  { Mirrored, "<" must stay left of ">": they trade places first. }
  Spot := B;
  if FLeftHanded and (B = tbPrevWeapon) then Spot := tbNextWeapon
  else if FLeftHanded and (B = tbNextWeapon) then Spot := tbPrevWeapon;
  case Spot of
    tbFire: begin Middle := Vector2(W - 0.17 * U, M + 0.21 * U); Radius := 0.12 * U; end;
    tbUse: begin Middle := Vector2(W - 0.43 * U, M + 0.11 * U); Radius := 0.085 * U; end;
    tbPrevWeapon: begin Middle := Vector2(W - 0.30 * U, M + 0.45 * U); Radius := 0.06 * U; end;
    tbNextWeapon: begin Middle := Vector2(W - 0.12 * U, M + 0.45 * U); Radius := 0.06 * U; end;
    tbAutomap: begin Middle := Vector2(W - 0.22 * U, H - 0.08 * U); Radius := 0.06 * U; end;
    tbMenu: begin Middle := Vector2(W - 0.08 * U, H - 0.08 * U); Radius := 0.06 * U; end;
    tbPhoto: begin Middle := Vector2(W - 0.36 * U, H - 0.08 * U); Radius := 0.06 * U; end;
    else begin Middle := TVector2.Zero; Radius := 0; end;
  end;
  { MAP, MENU and PHOTO stay at the top right, away from Doom's messages. }
  if not (B in [tbAutomap, tbMenu, tbPhoto]) then
    Middle := Mirror(Middle);
  { A place of the player's own wins (it is not mirrored). }
  if (B <> tbNone) and (FCustom[B].X >= 0) then
    Middle := Vector2(FCustom[B].X * W, FCustom[B].Y * H);
end;

function TDoomTouchControls.ButtonAt(const Position: TVector2): TTouchButton;
var
  B: TTouchButton;
  Middle: TVector2;
  Radius: Single;
begin
  for B := Succ(tbNone) to High(TTouchButton) do
  begin
    ButtonCircle(B, Middle, Radius);
    { A little larger than drawn: fingers are not precise. }
    if PointsDistance(Middle, Position) <= Radius * 1.15 then
      Exit(B);
  end;
  Result := tbNone;
end;

function TDoomTouchControls.IndexOf(const Id: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FTouches) do
    if FTouches[I].Id = Id then
      Exit(I);
  Result := -1;
end;

function TDoomTouchControls.TouchCount: Integer;
begin
  Result := Length(FTouches);
end;

function TDoomTouchControls.TouchId(const Index: Integer): Integer;
begin
  Result := FTouches[Index].Id;
end;

procedure TDoomTouchControls.TouchDown(const Id: Integer; const Position: TVector2);
var
  T: TTouchPoint;
  I: Integer;
  Middle: TVector2;
  Radius: Single;
begin
  UpdateSize;
  I := IndexOf(Id);
  if I >= 0 then
  begin
    TouchMove(Id, Position);
    Exit;
  end;
  T.Id := Id;
  T.Start := Position;
  T.Last := Position;
  T.Pos := Position;
  T.Button := ButtonAt(Position);
  if FEditing then
  begin
    { Dragging a button: Start keeps the finger's offset from its middle. }
    if T.Button = tbNone then Exit;
    T.Role := trButton;
    ButtonCircle(T.Button, Middle, Radius);
    T.Start := Position - Middle;
    SetLength(FTouches, Length(FTouches) + 1);
    FTouches[High(FTouches)] := T;
    Exit;
  end;
  if T.Button <> tbNone then
    T.Role := trButton
  else if InStickZone(Position) then
    T.Role := trStick
  else
    T.Role := trLook;
  SetLength(FTouches, Length(FTouches) + 1);
  FTouches[High(FTouches)] := T;
  if (T.Button <> tbNone) and (T.Button <> tbFire) and Assigned(FOnButton) then
    FOnButton(T.Button);
end;

procedure TDoomTouchControls.TouchMove(const Id: Integer; const Position: TVector2);
var
  I: Integer;
  Offset, P: TVector2;
  R, Len, Rate: Single;
begin
  I := IndexOf(Id);
  if I < 0 then Exit;
  FTouches[I].Pos := Position;
  if FEditing then
  begin
    P := Position - FTouches[I].Start;
    P := Vector2(EnsureRange(P.X / Max(1, FWidth), 0.02, 0.98), EnsureRange(P.Y / Max(1, FHeight), 0.02, 0.98));
    FCustom[FTouches[I].Button] := P;
    Exit;
  end;
  case FTouches[I].Role of
    trStick:
      begin
        { A finger pushed beyond the edge drags the stick along. }
        R := StickRadius;
        Offset := Position - FTouches[I].Start;
        Len := Offset.Length;
        if Len > R then
          FTouches[I].Start := Position - Offset * (R / Len);
      end;
    trLook, trButton:
      if (FTouches[I].Role = trLook) or (FTouches[I].Button = tbFire) then
      begin
        Rate := LookDegreesPerWidth / Max(1, FWidth);
        FLook := FLook + (Position - FTouches[I].Last) * Rate;
        FTouches[I].Last := Position;
      end;
  end;
end;

procedure TDoomTouchControls.TouchUp(const Id: Integer);
var
  I, J: Integer;
begin
  I := IndexOf(Id);
  if I < 0 then Exit;
  if FEditing and (FTouches[I].Button <> tbNone) and Assigned(FOnButtonMoved) then
    FOnButtonMoved(FTouches[I].Button, FCustom[FTouches[I].Button]);
  for J := I to High(FTouches) - 1 do
    FTouches[J] := FTouches[J + 1];
  SetLength(FTouches, Length(FTouches) - 1);
end;

procedure TDoomTouchControls.ReleaseAll;
begin
  SetLength(FTouches, 0);
  FLook := TVector2.Zero;
end;

function TDoomTouchControls.MoveVector: TVector2;
var
  I: Integer;
  Len: Single;
begin
  Result := TVector2.Zero;
  for I := 0 to High(FTouches) do
    if FTouches[I].Role = trStick then
    begin
      Result := (FTouches[I].Pos - FTouches[I].Start) / StickRadius;
      Len := Result.Length;
      if Len < StickDeadZone then
        Result := TVector2.Zero
      else if Len > 1 then
        Result := Result / Len;
      Exit;
    end;
end;

function TDoomTouchControls.FireHeld: Boolean;
var
  I: Integer;
begin
  if FEditing then Exit(false);
  for I := 0 to High(FTouches) do
    if FTouches[I].Button = tbFire then
      Exit(true);
  Result := false;
end;

function TDoomTouchControls.TakeLook: TVector2;
begin
  Result := FLook;
  FLook := TVector2.Zero;
end;

{ A ring as a triangle strip (line widths above 1 are not available
  everywhere, e.g. WebGL). }
procedure DrawRing(const Middle: TVector2; const Radius, Thickness: Single; const Color: TCastleColor);
const
  Slices = 40;
var
  Points: array [0..2 * Slices + 1] of TVector2;
  I: Integer;
  A, S, C: Single;
begin
  for I := 0 to Slices do
  begin
    A := 2 * Pi * I / Slices;
    SinCos(A, S, C);
    Points[2 * I] := Middle + Vector2(C, S) * Radius;
    Points[2 * I + 1] := Middle + Vector2(C, S) * (Radius - Thickness);
  end;
  DrawPrimitive2D(pmTriangleStrip, Points, Color);
end;

procedure TDoomTouchControls.Render;
var
  B: TTouchButton;
  Base, Middle, Knob, Size: TVector2;
  Radius, Scale, Line: Single;
  Pressed, StickShown: Boolean;
  I: Integer;
  Img: TDrawableImage;
begin
  inherited;
  UpdateSize;
  if not FLabelsMade then MakeLabels;
  Base := RenderRect.LeftBottom;
  Line := Max(2, Min(FWidth, FHeight) / 250);
  { The stick: where the finger is, or a faint hint at its usual place. }
  StickShown := false;
  for I := 0 to High(FTouches) do
    if FTouches[I].Role = trStick then
    begin
      Middle := Base + FTouches[I].Start;
      Knob := Middle + MoveVector * StickRadius;
      DrawCircle(Middle, StickRadius, StickRadius, Vector4(1, 1, 1, 0.10 * FOpacity));
      DrawRing(Middle, StickRadius, Line, Vector4(1, 1, 1, 0.45 * FOpacity));
      DrawCircle(Knob, StickRadius * 0.4, StickRadius * 0.4, Vector4(1, 1, 1, 0.35 * FOpacity));
      StickShown := true;
      Break;
    end;
  if not StickShown then
    DrawRing(Base + StickHome, StickRadius, Line, Vector4(1, 1, 1, 0.18 * FOpacity));
  for B := Succ(tbNone) to High(TTouchButton) do
  begin
    ButtonCircle(B, Middle, Radius);
    Middle := Middle + Base;
    Pressed := false;
    for I := 0 to High(FTouches) do
      if FTouches[I].Button = B then
        Pressed := true;
    if Pressed then
      DrawCircle(Middle, Radius, Radius, Vector4(1, 0.85, 0.6, 0.35 * FOpacity))
    else
      DrawCircle(Middle, Radius, Radius, Vector4(0, 0, 0, 0.30 * FOpacity));
    DrawRing(Middle, Radius, Line, Vector4(1, 1, 1, 0.5 * FOpacity));
    Img := FLabels[B];
    if Img <> nil then
    begin
      { Doom's font, as large as fits the circle. }
      Scale := Min(Min(FWidth, FHeight) / 200, 1.5 * Radius / Img.Width);
      Size := Vector2(Img.Width * Scale, Img.Height * Scale);
      Img.Color := Vector4(1, 1, 1, 0.85 * FOpacity);
      Img.Draw(FloatRectangle(Middle - Size / 2, Size.X, Size.Y));
    end;
  end;
end;

function TDoomTouchControls.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  { The desktop's mouse (or a platform that reports fingers to CGE). }
  if Event.IsMouseButton(buttonLeft) then
  begin
    TouchDown(Event.FingerIndex, Event.Position - RenderRect.LeftBottom);
    Result := true;
  end;
end;

function TDoomTouchControls.Release(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  if Event.IsMouseButton(buttonLeft) and (IndexOf(Event.FingerIndex) >= 0) then
  begin
    TouchUp(Event.FingerIndex);
    Result := true;
  end;
end;

function TDoomTouchControls.Motion(const Event: TInputMotion): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  if IndexOf(Event.FingerIndex) >= 0 then
  begin
    TouchMove(Event.FingerIndex, Event.Position - RenderRect.LeftBottom);
    Result := true;
  end;
end;

{ The browser's fingers ----------------------------------------------------- }

{$ifdef WASI}
var
  WebChecked, WebAvailable: Boolean;

{ The page script's castleDoomTouches exists (CGE's plain page has none). }
function WebTouchesAvailable: Boolean;
var
  V: TJOB_JSValue;
begin
  if not WebChecked then
  begin
    WebChecked := true;
    V := JSWindow.ReadJSPropertyValue('castleDoomTouches');
    WebAvailable := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
    FreeAndNil(V);
    WritelnLog('Touch', 'Browser touch tracking %s', [BoolToStr(WebAvailable, 'found', 'not found')]);
  end;
  Result := WebAvailable;
end;
{$endif}

{ The next number of S from P (no exceptions: Val), false at the end. }
function NextNumber(const S: String; var P: Integer; out Value: Integer): Boolean;
var
  Start, Code: Integer;
begin
  while (P <= Length(S)) and not (S[P] in ['0'..'9', '-']) do Inc(P);
  if P > Length(S) then Exit(false);
  Start := P;
  Inc(P);
  while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
  Val(Copy(S, Start, P - Start), Value, Code);
  Result := Code = 0;
end;

{ Positions are canvas pixels, Y up (the control fills the canvas). }
procedure ApplyTouchState(const S: String; const Controls: TDoomTouchControls);
var
  Ids: array of Integer;
  Positions: array of TVector2;
  P, Id, X, Y, I, J: Integer;
  Found, WasTouch: Boolean;
begin
  if S = '' then Exit;
  WasTouch := TouchMode;
  TouchMode := TouchForced or (S[1] = '1');
  if TouchMode <> WasTouch then
    WritelnLog('Touch', 'Touch controls %s', [BoolToStr(TouchMode, 'shown', 'hidden')]);
  if Controls = nil then Exit;
  SetLength(Ids, 0);
  SetLength(Positions, 0);
  P := 2;
  while NextNumber(S, P, Id) and NextNumber(S, P, X) and NextNumber(S, P, Y) do
  begin
    SetLength(Ids, Length(Ids) + 1);
    SetLength(Positions, Length(Positions) + 1);
    Ids[High(Ids)] := Id;
    Positions[High(Positions)] := Vector2(X, Y);
  end;
  { Fingers that are gone, then the moved and new ones. }
  for I := Controls.TouchCount - 1 downto 0 do
  begin
    Id := Controls.TouchId(I);
    Found := false;
    for J := 0 to High(Ids) do
      if Ids[J] = Id then Found := true;
    if not Found then
      Controls.TouchUp(Id);
  end;
  for I := 0 to High(Ids) do
    Controls.TouchDown(Ids[I], Positions[I]);
end;

procedure PollTouches(const Controls: TDoomTouchControls);
{$ifdef WASI}
var
  S: String;
{$endif}
begin
  {$ifdef WASI}
  if not WebTouchesAvailable then Exit;
  S := JSWindow.InvokeJSUtf8StringResult('castleDoomTouches', [Ord(Controls <> nil)]);
  ApplyTouchState(S, Controls);
  {$endif}
end;

var
  KeyboardShown: Boolean;

procedure ShowTextKeyboard(const Text: String);
begin
  { Asked again while shown: the keyboard may have been closed by Back. }
  if not TouchMode then Exit;
  KeyboardShown := true;
  { CGE's keyboard service (ServiceKeyboard.java): the text to start
    from, not a password. Nothing listens on the desktop. }
  Messaging.Send(['castle-show-keyboard', Text, 'false']);
  WritelnLog('Keyboard', 'On-screen keyboard shown for "%s"', [Text]);
end;

procedure HideTextKeyboard;
begin
  if not KeyboardShown then Exit;
  KeyboardShown := false;
  Messaging.Send(['castle-hide-keyboard']);
  WritelnLog('Keyboard', 'On-screen keyboard hidden');
end;

function TextKeyboardShown: Boolean;
begin
  Result := KeyboardShown;
end;

initialization
  RegisterSerializableComponent(TDoomTouchControls, 'Doom Touch Controls');
end.
