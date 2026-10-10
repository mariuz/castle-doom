{ Doom's automap as a 2D CGE control: linedefs drawn with DrawPrimitive2D in
  Doom's colours (red one-sided, brown floor change, yellow ceiling change),
  only once the player has seen them (ML_MAPPED), with the player arrow,
  zoom and follow mode. }
unit DoomAutomap;

interface

uses Classes,
  CastleUIControls, CastleVectors, CastleColors,
  DoomWorld;

type
  TDoomAutomap = class(TCastleUserInterface)
  strict private
    FWorld: TDoomWorld;
    FScale: Single;
    FShowAll: Boolean;
    FGrid: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Render; override;
    procedure ZoomBy(const Factor: Single);
    property World: TDoomWorld read FWorld write FWorld;
    { Pixels per map unit. }
    property Scale: Single read FScale write FScale;
    { Cheat: draw every line (like IDDT), unseen ones dimmed. }
    property ShowAll: Boolean read FShowAll write FShowAll;
    property Grid: Boolean read FGrid write FGrid;
  end;

implementation

uses SysUtils, Math,
  CastleGLUtils, CastleRectangles, CastleRenderOptions, CastleUtils,
  DoomMap, CastleComponentSerialize;

const
  ColorWall: TCastleColor = (X: 1.0; Y: 0.0; Z: 0.0; W: 1.0);        { one-sided / secret }
  ColorFloorDiff: TCastleColor = (X: 0.75; Y: 0.5; Z: 0.2; W: 1.0);  { floor height change }
  ColorCeilDiff: TCastleColor = (X: 1.0; Y: 1.0; Z: 0.0; W: 1.0);    { ceiling height change }
  ColorFlat: TCastleColor = (X: 0.45; Y: 0.45; Z: 0.45; W: 1.0);     { two-sided, no change }
  ColorUnseen: TCastleColor = (X: 0.3; Y: 0.3; Z: 0.35; W: 1.0);
  ColorGrid: TCastleColor = (X: 0.25; Y: 0.25; Z: 0.25; W: 0.5);
  ColorPlayer: TCastleColor = (X: 1.0; Y: 1.0; Z: 1.0; W: 1.0);
  ColorBack: TCastleColor = (X: 0.0; Y: 0.0; Z: 0.0; W: 1.0);

constructor TDoomAutomap.Create(AOwner: TComponent);
begin
  inherited;
  FScale := 0.4;
  FullSize := true;
end;

procedure TDoomAutomap.ZoomBy(const Factor: Single);
begin
  FScale := Clamped(FScale * Factor, 0.05, 4);
end;

procedure TDoomAutomap.Render;
var
  R: TFloatRectangle;
  CX, CY, PX, PY: Single;
  Map: TDoomMap;
  Walls, FloorDiff, CeilDiff, Flat, Unseen, GridPts, Arrow: array of TVector2;
  NWalls, NFloor, NCeil, NFlat, NUnseen, NGrid: Integer;
  I, F, B: Integer;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;
  Seen: Boolean;
  GridStep, G, GStart, GEnd: Single;
  Ang, S, C: Single;

  function ToScreen(const X, Y: Single): TVector2;
  begin
    Result := Vector2(CX + (X - PX) * FScale, CY + (Y - PY) * FScale);
  end;

  procedure AddLine(var Arr: array of TVector2; var N: Integer);
  begin
    Arr[N] := ToScreen(V1.X, V1.Y);
    Arr[N + 1] := ToScreen(V2.X, V2.Y);
    Inc(N, 2);
  end;

  procedure ArrowSeg(const X1, Y1, X2, Y2: Single);
  var
    N: Integer;
  begin
    { Rotate by the player angle and place at the player. }
    N := Length(Arrow);
    SetLength(Arrow, N + 2);
    Arrow[N] := ToScreen(PX + X1 * C - Y1 * S, PY + X1 * S + Y1 * C);
    Arrow[N + 1] := ToScreen(PX + X2 * C - Y2 * S, PY + X2 * S + Y2 * C);
  end;

const
  { Doom's player arrow, in map units (R = 8 * PLAYERRADIUS / 7). }
  AR = 18.3;
begin
  inherited;
  if (FWorld = nil) or (FWorld.Map = nil) then Exit;
  Map := FWorld.Map;
  R := RenderRect;
  DrawRectangle(R, ColorBack);
  CX := R.Center.X;
  CY := R.Center.Y;
  PX := FWorld.Player.X;
  PY := FWorld.Player.Y;

  { Grid every 128 units (a Doom "block"), like the F key grid in Doom. }
  if FGrid then
  begin
    GridStep := 128;
    GStart := Floor((PX - R.Width / 2 / FScale) / GridStep) * GridStep;
    GEnd := PX + R.Width / 2 / FScale;
    SetLength(GridPts, 0);
    NGrid := 0;
    G := GStart;
    while G <= GEnd do
    begin
      SetLength(GridPts, NGrid + 2);
      GridPts[NGrid] := Vector2(CX + (G - PX) * FScale, R.Bottom);
      GridPts[NGrid + 1] := Vector2(CX + (G - PX) * FScale, R.Top);
      Inc(NGrid, 2);
      G := G + GridStep;
    end;
    GStart := Floor((PY - R.Height / 2 / FScale) / GridStep) * GridStep;
    GEnd := PY + R.Height / 2 / FScale;
    G := GStart;
    while G <= GEnd do
    begin
      SetLength(GridPts, NGrid + 2);
      GridPts[NGrid] := Vector2(R.Left, CY + (G - PY) * FScale);
      GridPts[NGrid + 1] := Vector2(R.Right, CY + (G - PY) * FScale);
      Inc(NGrid, 2);
      G := G + GridStep;
    end;
    if NGrid > 0 then
      DrawPrimitive2D(pmLines, GridPts, ColorGrid);
  end;

  SetLength(Walls, Length(Map.Linedefs) * 2);
  SetLength(FloorDiff, Length(Map.Linedefs) * 2);
  SetLength(CeilDiff, Length(Map.Linedefs) * 2);
  SetLength(Flat, Length(Map.Linedefs) * 2);
  SetLength(Unseen, Length(Map.Linedefs) * 2);
  NWalls := 0; NFloor := 0; NCeil := 0; NFlat := 0; NUnseen := 0;
  for I := 0 to High(Map.Linedefs) do
  begin
    L := Map.Linedefs[I];
    if ((L.Flags and ML_DONTDRAW) <> 0) and not FShowAll then Continue;
    Seen := (L.Flags and ML_MAPPED) <> 0;
    if not (Seen or FShowAll) then Continue;
    V1 := Map.Vertices[L.V1];
    V2 := Map.Vertices[L.V2];
    { Quick reject: off screen. }
    if (Max(V1.X, V2.X) < PX - R.Width / 2 / FScale) or (Min(V1.X, V2.X) > PX + R.Width / 2 / FScale) or
       (Max(V1.Y, V2.Y) < PY - R.Height / 2 / FScale) or (Min(V1.Y, V2.Y) > PY + R.Height / 2 / FScale) then
      Continue;
    F := L.FrontSector;
    B := L.BackSector;
    if not Seen then
      AddLine(Unseen, NUnseen)
    else if (F < 0) or (B < 0) or ((L.Flags and ML_SECRET) <> 0) then
      AddLine(Walls, NWalls)
    else if Map.Sectors[F].FloorHeight <> Map.Sectors[B].FloorHeight then
      AddLine(FloorDiff, NFloor)
    else if Map.Sectors[F].CeilingHeight <> Map.Sectors[B].CeilingHeight then
      AddLine(CeilDiff, NCeil)
    else if FShowAll then
      AddLine(Flat, NFlat);
  end;
  SetLength(Unseen, NUnseen);
  SetLength(Flat, NFlat);
  SetLength(CeilDiff, NCeil);
  SetLength(FloorDiff, NFloor);
  SetLength(Walls, NWalls);
  if NUnseen > 0 then DrawPrimitive2D(pmLines, Unseen, ColorUnseen);
  if NFlat > 0 then DrawPrimitive2D(pmLines, Flat, ColorFlat);
  if NCeil > 0 then DrawPrimitive2D(pmLines, CeilDiff, ColorCeilDiff);
  if NFloor > 0 then DrawPrimitive2D(pmLines, FloorDiff, ColorFloorDiff);
  if NWalls > 0 then DrawPrimitive2D(pmLines, Walls, ColorWall, bsSrcAlpha, bdOneMinusSrcAlpha, false, 2);

  { Player arrow (Doom's player_arrow line list). }
  Ang := DegToRad(FWorld.Player.Angle);
  S := Sin(Ang);
  C := Cos(Ang);
  SetLength(Arrow, 0);
  ArrowSeg(-AR - AR / 8, 0, AR, 0);
  ArrowSeg(AR, 0, AR - AR / 2, AR / 4);
  ArrowSeg(AR, 0, AR - AR / 2, -AR / 4);
  ArrowSeg(-AR - AR / 8, 0, -AR - AR / 8 - AR / 2, AR / 4);
  ArrowSeg(-AR - AR / 8, 0, -AR - AR / 8 - AR / 2, -AR / 4);
  ArrowSeg(-AR - AR / 8 - AR / 4, 0, -AR - AR / 8 - AR / 4 - AR / 2, AR / 4);
  ArrowSeg(-AR - AR / 8 - AR / 4, 0, -AR - AR / 8 - AR / 4 - AR / 2, -AR / 4);
  DrawPrimitive2D(pmLines, Arrow, ColorPlayer, bsSrcAlpha, bdOneMinusSrcAlpha, false, 2);
end;

initialization
  RegisterSerializableComponent(TDoomAutomap, 'Doom Automap');
end.
