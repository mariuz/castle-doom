{ Doom map data: VERTEXES, LINEDEFS, SIDEDEFS, SECTORS, THINGS, plus the BSP
  (SEGS, SSECTORS, NODES) that we use both for point-in-sector queries and
  to recover convex subsector polygons for floors and ceilings.

  Coordinates stay in Doom map units (the player is 56 units tall).
  Doom's map plane is (X, Y) with Z up; conversion to CGE's Y-up happens in
  DoomGeometry. }
unit DoomMap;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleVectors,
  DoomWad;

const
  { Linedef flags. }
  ML_BLOCKING = 1;
  ML_BLOCKMONSTERS = 2;
  ML_TWOSIDED = 4;
  ML_DONTPEGTOP = 8;
  ML_DONTPEGBOTTOM = 16;
  ML_SECRET = 32;
  ML_SOUNDBLOCK = 64;
  ML_DONTDRAW = 128;
  ML_MAPPED = 256;

  { Thing flags. }
  MTF_EASY = 1;
  MTF_NORMAL = 2;
  MTF_HARD = 4;
  MTF_AMBUSH = 8;
  MTF_NOTSINGLE = 16;

type
  TDoomVertex = record
    X, Y: Single;
  end;

  TDoomSidedef = record
    XOffset, YOffset: Integer;
    UpperTex, LowerTex, MiddleTex: String;
    Sector: Integer;
  end;

  TDoomLinedef = record
    V1, V2: Integer;
    Flags, Special, Tag: Integer;
    { Sidedef indices, -1 when absent. [0] = front (right side), [1] = back. }
    Side: array [0..1] of Integer;
    { Derived: sector on each side, -1 when absent. }
    FrontSector, BackSector: Integer;
    Length: Single;
    { Runtime: the switch on this line was already used (for S1/W1 types). }
    Used: Boolean;
  end;

  TDoomSector = record
    { Current heights, changed by doors / lifts / floors. }
    FloorHeight, CeilingHeight: Single;
    OrigFloor, OrigCeiling: Integer;
    FloorTex, CeilingTex: String;
    LightLevel: Integer;
    OrigLight: Integer;
    Special, Tag: Integer;
    { Linedefs touching this sector (either side). }
    Lines: array of Integer;
    { Subsectors belonging to this sector. }
    Subsectors: array of Integer;
    { Runtime: active mover (door, lift...) owned by the world. }
    Mover: TObject;
    SecretFound: Boolean;
  end;

  TDoomThing = record
    X, Y: Single;
    Angle: Integer;
    TypeNum: Integer;
    Flags: Integer;
  end;

  TDoomSeg = record
    V1, V2: Integer;
    Angle: Integer;
    Linedef: Integer;
    Side: Integer;
    Offset: Integer;
  end;

  TDoomSubsector = record
    SegCount, FirstSeg: Integer;
    Sector: Integer;
    { Convex polygon, counter-clockwise in Doom (X, Y). }
    Poly: array of TVector2;
  end;

  TDoomNode = record
    X, Y, DX, DY: Integer;
    { Child codes: bit 15 set = subsector. }
    Children: array [0..1] of Integer;
  end;

  TDoomMap = class
  strict private
    FWad: TDoomWad;
    FName: String;
    procedure LoadLumps(const MarkerIndex: Integer);
    procedure BuildSectorLists;
    procedure BuildSubsectorPolygons;
  public
    Vertices: array of TDoomVertex;
    Linedefs: array of TDoomLinedef;
    Sidedefs: array of TDoomSidedef;
    Sectors: array of TDoomSector;
    Things: array of TDoomThing;
    Segs: array of TDoomSeg;
    Subsectors: array of TDoomSubsector;
    Nodes: array of TDoomNode;
    MinX, MinY, MaxX, MaxY: Single;

    constructor Create(const AWad: TDoomWad; const MapName: String);

    { 0 when (X, Y) is on the front (right) side of the node partition line, else 1. }
    function PointOnNodeSide(const X, Y: Single; const NodeIndex: Integer): Integer;
    { 0 when (X, Y) is on the front (right) side of the linedef, else 1. }
    function PointOnLineSide(const X, Y: Single; const LineIndex: Integer): Integer;
    function SubsectorAt(const X, Y: Single): Integer;
    function SectorAt(const X, Y: Single): Integer;
    { The sector across the line from Sector, -1 when one-sided. }
    function OtherSector(const LineIndex, Sector: Integer): Integer;

    { Doom's p_spec.c neighbour searches. }
    function LowestFloorSurrounding(const Sec: Integer): Single;
    function HighestFloorSurrounding(const Sec: Integer): Single;
    function NextHighestFloor(const Sec: Integer; const CurrentHeight: Single): Single;
    function LowestCeilingSurrounding(const Sec: Integer): Single;
    function HighestCeilingSurrounding(const Sec: Integer): Single;
    function MinSurroundingLight(const Sec: Integer; const MaxLight: Integer): Integer;
    function MaxSurroundingLight(const Sec: Integer; const MinLight: Integer): Integer;
    { Next sector (after Start) with this tag, -1 when none. }
    function FindSectorFromTag(const Tag: Integer; const Start: Integer = -1): Integer;
    { Side texture helper: sidedef for a line side, nil-safe via index -1. }
    function SideSector(const LineIndex, SideIndex: Integer): Integer;
    function HasSkyCeiling(const Sec: Integer): Boolean;

    property Name: String read FName;
    property Wad: TDoomWad read FWad;
  end;

implementation

uses Math, CastleLog, CastleUtils;

type
  TPolyD = array of TVector2Double;

{ Sutherland-Hodgman clip of a convex polygon against a half-plane.
  Keeps points where (X - PX) * DY - (Y - PY) * DX >= 0 (KeepPositive)
  or <= 0 (not KeepPositive). }
function ClipPoly(const Poly: TPolyD; const PX, PY, DX, DY: Double;
  const KeepPositive: Boolean): TPolyD;
const
  Eps = 1e-4;
var
  I, N, Count: Integer;
  A, B: TVector2Double;
  SA, SB, T: Double;
  InA, InB: Boolean;

  function Side(const P: TVector2Double): Double;
  begin
    Result := (P.X - PX) * DY - (P.Y - PY) * DX;
    if not KeepPositive then Result := -Result;
  end;

begin
  N := Length(Poly);
  SetLength(Result, N * 2 + 2);
  Count := 0;
  for I := 0 to N - 1 do
  begin
    A := Poly[I];
    B := Poly[(I + 1) mod N];
    SA := Side(A);
    SB := Side(B);
    InA := SA >= -Eps;
    InB := SB >= -Eps;
    if InA then
    begin
      Result[Count] := A;
      Inc(Count);
    end;
    if InA <> InB then
    begin
      T := SA / (SA - SB);
      Result[Count].X := A.X + (B.X - A.X) * T;
      Result[Count].Y := A.Y + (B.Y - A.Y) * T;
      Inc(Count);
    end;
  end;
  SetLength(Result, Count);
end;

function PolyArea(const Poly: TPolyD): Double;
var
  I, N: Integer;
begin
  Result := 0;
  N := Length(Poly);
  for I := 0 to N - 1 do
    Result := Result + Poly[I].X * Poly[(I + 1) mod N].Y - Poly[(I + 1) mod N].X * Poly[I].Y;
  Result := Result * 0.5;
end;

{ TDoomMap ------------------------------------------------------------------- }

constructor TDoomMap.Create(const AWad: TDoomWad; const MapName: String);
var
  Marker: Integer;
begin
  inherited Create;
  FWad := AWad;
  FName := UpperCase(MapName);
  Marker := FWad.FindLump(FName);
  if Marker < 0 then
    raise Exception.CreateFmt('Map %s not found in %s', [FName, FWad.Url]);
  LoadLumps(Marker);
  BuildSectorLists;
  BuildSubsectorPolygons;
  WritelnLog('Map', '%s: %d vertices, %d linedefs, %d sectors, %d things, %d subsectors, %d nodes', [
    FName, Length(Vertices), Length(Linedefs), Length(Sectors), Length(Things),
    Length(Subsectors), Length(Nodes)]);
end;

procedure TDoomMap.LoadLumps(const MarkerIndex: Integer);

  function MapLump(const LumpName: String): Integer;
  var
    I: Integer;
  begin
    { Map lumps follow the marker; stop at the next map marker. }
    for I := MarkerIndex + 1 to Min(MarkerIndex + 11, FWad.LumpCount - 1) do
      if FWad.LumpName(I) = LumpName then
        Exit(I);
    raise Exception.CreateFmt('Map %s has no %s lump', [FName, LumpName]);
  end;

var
  L, I, N: Integer;
  P: PByte;
  Magic: String;
begin
  { VERTEXES }
  L := MapLump('VERTEXES');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 4;
  SetLength(Vertices, N);
  MinX := 1e9; MinY := 1e9; MaxX := -1e9; MaxY := -1e9;
  for I := 0 to N - 1 do
  begin
    Vertices[I].X := PInt16(P + I * 4)^;
    Vertices[I].Y := PInt16(P + I * 4 + 2)^;
    MinX := Min(MinX, Vertices[I].X);
    MaxX := Max(MaxX, Vertices[I].X);
    MinY := Min(MinY, Vertices[I].Y);
    MaxY := Max(MaxY, Vertices[I].Y);
  end;

  { SECTORS }
  L := MapLump('SECTORS');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 26;
  SetLength(Sectors, N);
  for I := 0 to N - 1 do
  begin
    Sectors[I].OrigFloor := PInt16(P + I * 26)^;
    Sectors[I].OrigCeiling := PInt16(P + I * 26 + 2)^;
    Sectors[I].FloorHeight := Sectors[I].OrigFloor;
    Sectors[I].CeilingHeight := Sectors[I].OrigCeiling;
    Sectors[I].FloorTex := DoomName(P + I * 26 + 4);
    Sectors[I].CeilingTex := DoomName(P + I * 26 + 12);
    Sectors[I].OrigLight := PInt16(P + I * 26 + 20)^;
    Sectors[I].LightLevel := Sectors[I].OrigLight;
    Sectors[I].Special := PInt16(P + I * 26 + 22)^;
    Sectors[I].Tag := PInt16(P + I * 26 + 24)^;
  end;

  { SIDEDEFS }
  L := MapLump('SIDEDEFS');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 30;
  SetLength(Sidedefs, N);
  for I := 0 to N - 1 do
  begin
    Sidedefs[I].XOffset := PInt16(P + I * 30)^;
    Sidedefs[I].YOffset := PInt16(P + I * 30 + 2)^;
    Sidedefs[I].UpperTex := DoomName(P + I * 30 + 4);
    Sidedefs[I].LowerTex := DoomName(P + I * 30 + 12);
    Sidedefs[I].MiddleTex := DoomName(P + I * 30 + 20);
    Sidedefs[I].Sector := PUInt16(P + I * 30 + 28)^;
    if Sidedefs[I].Sector >= Length(Sectors) then
      Sidedefs[I].Sector := 0;
  end;

  { LINEDEFS }
  L := MapLump('LINEDEFS');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 14;
  SetLength(Linedefs, N);
  for I := 0 to N - 1 do
  begin
    Linedefs[I].V1 := PUInt16(P + I * 14)^;
    Linedefs[I].V2 := PUInt16(P + I * 14 + 2)^;
    Linedefs[I].Flags := PUInt16(P + I * 14 + 4)^;
    Linedefs[I].Special := PInt16(P + I * 14 + 6)^;
    Linedefs[I].Tag := PInt16(P + I * 14 + 8)^;
    Linedefs[I].Side[0] := PInt16(P + I * 14 + 10)^;
    Linedefs[I].Side[1] := PInt16(P + I * 14 + 12)^;
    if (Linedefs[I].Side[0] < 0) or (Linedefs[I].Side[0] >= Length(Sidedefs)) then Linedefs[I].Side[0] := -1;
    if (Linedefs[I].Side[1] < 0) or (Linedefs[I].Side[1] >= Length(Sidedefs)) then Linedefs[I].Side[1] := -1;
    if (Linedefs[I].V1 >= Length(Vertices)) then Linedefs[I].V1 := 0;
    if (Linedefs[I].V2 >= Length(Vertices)) then Linedefs[I].V2 := 0;
    Linedefs[I].FrontSector := SideSector(I, 0);
    Linedefs[I].BackSector := SideSector(I, 1);
    Linedefs[I].Length := Sqrt(Sqr(Vertices[Linedefs[I].V2].X - Vertices[Linedefs[I].V1].X) +
      Sqr(Vertices[Linedefs[I].V2].Y - Vertices[Linedefs[I].V1].Y));
  end;

  { THINGS }
  L := MapLump('THINGS');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 10;
  SetLength(Things, N);
  for I := 0 to N - 1 do
  begin
    Things[I].X := PInt16(P + I * 10)^;
    Things[I].Y := PInt16(P + I * 10 + 2)^;
    Things[I].Angle := PInt16(P + I * 10 + 4)^;
    Things[I].TypeNum := PInt16(P + I * 10 + 6)^;
    Things[I].Flags := PInt16(P + I * 10 + 8)^;
  end;

  { NODES (vanilla format only) }
  L := MapLump('NODES');
  P := FWad.LumpPointer(L);
  if FWad.LumpSize(L) >= 4 then
  begin
    Magic := Chr(P[0]) + Chr(P[1]) + Chr(P[2]) + Chr(P[3]);
    if (Magic = 'XNOD') or (Magic = 'ZNOD') or (Magic = 'XGLN') or (Magic = 'ZGLN') then
      raise Exception.CreateFmt('Map %s uses extended nodes (%s), only vanilla nodes are supported', [FName, Magic]);
  end;
  N := FWad.LumpSize(L) div 28;
  SetLength(Nodes, N);
  for I := 0 to N - 1 do
  begin
    Nodes[I].X := PInt16(P + I * 28)^;
    Nodes[I].Y := PInt16(P + I * 28 + 2)^;
    Nodes[I].DX := PInt16(P + I * 28 + 4)^;
    Nodes[I].DY := PInt16(P + I * 28 + 6)^;
    Nodes[I].Children[0] := PUInt16(P + I * 28 + 24)^;
    Nodes[I].Children[1] := PUInt16(P + I * 28 + 26)^;
  end;

  { SEGS }
  L := MapLump('SEGS');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 12;
  SetLength(Segs, N);
  for I := 0 to N - 1 do
  begin
    Segs[I].V1 := PUInt16(P + I * 12)^;
    Segs[I].V2 := PUInt16(P + I * 12 + 2)^;
    Segs[I].Angle := PInt16(P + I * 12 + 4)^;
    Segs[I].Linedef := PUInt16(P + I * 12 + 6)^;
    Segs[I].Side := PInt16(P + I * 12 + 8)^;
    Segs[I].Offset := PInt16(P + I * 12 + 10)^;
    if Segs[I].V1 >= Length(Vertices) then Segs[I].V1 := 0;
    if Segs[I].V2 >= Length(Vertices) then Segs[I].V2 := 0;
    if Segs[I].Linedef >= Length(Linedefs) then Segs[I].Linedef := 0;
    if Segs[I].Side <> 0 then Segs[I].Side := 1;
  end;

  { SSECTORS }
  L := MapLump('SSECTORS');
  P := FWad.LumpPointer(L);
  N := FWad.LumpSize(L) div 4;
  SetLength(Subsectors, N);
  for I := 0 to N - 1 do
  begin
    Subsectors[I].SegCount := PUInt16(P + I * 4)^;
    Subsectors[I].FirstSeg := PUInt16(P + I * 4 + 2)^;
    Subsectors[I].Sector := -1;
  end;
end;

function TDoomMap.SideSector(const LineIndex, SideIndex: Integer): Integer;
var
  S: Integer;
begin
  S := Linedefs[LineIndex].Side[SideIndex];
  if S < 0 then Exit(-1);
  Result := Sidedefs[S].Sector;
end;

procedure TDoomMap.BuildSectorLists;

  procedure AddLine(const Sec, Line: Integer);
  var
    N: Integer;
  begin
    if Sec < 0 then Exit;
    N := Length(Sectors[Sec].Lines);
    SetLength(Sectors[Sec].Lines, N + 1);
    Sectors[Sec].Lines[N] := Line;
  end;

  procedure AddSubsector(const Sec, Sub: Integer);
  var
    N: Integer;
  begin
    if Sec < 0 then Exit;
    N := Length(Sectors[Sec].Subsectors);
    SetLength(Sectors[Sec].Subsectors, N + 1);
    Sectors[Sec].Subsectors[N] := Sub;
  end;

var
  I, J, Seg, Side: Integer;
begin
  for I := 0 to High(Linedefs) do
  begin
    AddLine(Linedefs[I].FrontSector, I);
    if Linedefs[I].BackSector <> Linedefs[I].FrontSector then
      AddLine(Linedefs[I].BackSector, I);
  end;
  for I := 0 to High(Subsectors) do
  begin
    for J := 0 to Subsectors[I].SegCount - 1 do
    begin
      Seg := Subsectors[I].FirstSeg + J;
      if (Seg < 0) or (Seg > High(Segs)) then Break;
      Side := Segs[Seg].Side;
      Subsectors[I].Sector := SideSector(Segs[Seg].Linedef, Side);
      if Subsectors[I].Sector >= 0 then Break;
    end;
    AddSubsector(Subsectors[I].Sector, I);
  end;
end;

procedure TDoomMap.BuildSubsectorPolygons;

  procedure Walk(const Child: Integer; const Poly: TPolyD);
  var
    Sub, J, Seg: Integer;
    P: TPolyD;
    V1, V2: TDoomVertex;
    Node: TDoomNode;
    Area: Double;
  begin
    if Length(Poly) < 3 then Exit;
    if (Child and $8000) <> 0 then
    begin
      Sub := Child and $7FFF;
      if Sub > High(Subsectors) then Exit;
      P := Poly;
      { Clip to the right side of each seg: the subsector lies there. }
      for J := 0 to Subsectors[Sub].SegCount - 1 do
      begin
        Seg := Subsectors[Sub].FirstSeg + J;
        if (Seg < 0) or (Seg > High(Segs)) then Break;
        V1 := Vertices[Segs[Seg].V1];
        V2 := Vertices[Segs[Seg].V2];
        if (V1.X = V2.X) and (V1.Y = V2.Y) then Continue;
        P := ClipPoly(P, V1.X, V1.Y, V2.X - V1.X, V2.Y - V1.Y, true);
        if Length(P) < 3 then Exit;
      end;
      Area := PolyArea(P);
      if Area < 0.5 then Exit;
      SetLength(Subsectors[Sub].Poly, Length(P));
      for J := 0 to High(P) do
        Subsectors[Sub].Poly[J] := Vector2(P[J].X, P[J].Y);
    end else
    begin
      if Child > High(Nodes) then Exit;
      Node := Nodes[Child];
      if (Node.DX = 0) and (Node.DY = 0) then Exit;
      Walk(Node.Children[0], ClipPoly(Poly, Node.X, Node.Y, Node.DX, Node.DY, true));
      Walk(Node.Children[1], ClipPoly(Poly, Node.X, Node.Y, Node.DX, Node.DY, false));
    end;
  end;

var
  Start: TPolyD;
const
  Margin = 128;
begin
  if Length(Nodes) = 0 then
  begin
    if Length(Subsectors) = 1 then
      Walk($8000, Start);
    Exit;
  end;
  { Counter-clockwise bounding rectangle, in Doom (X, Y). }
  SetLength(Start, 4);
  Start[0] := Vector2Double(MinX - Margin, MinY - Margin);
  Start[1] := Vector2Double(MaxX + Margin, MinY - Margin);
  Start[2] := Vector2Double(MaxX + Margin, MaxY + Margin);
  Start[3] := Vector2Double(MinX - Margin, MaxY + Margin);
  Walk(High(Nodes), Start);
end;

function TDoomMap.PointOnNodeSide(const X, Y: Single; const NodeIndex: Integer): Integer;
var
  Cross: Double;
begin
  Cross := (X - Nodes[NodeIndex].X) * Nodes[NodeIndex].DY -
           (Y - Nodes[NodeIndex].Y) * Nodes[NodeIndex].DX;
  if Cross >= 0 then Result := 0 else Result := 1;
end;

function TDoomMap.PointOnLineSide(const X, Y: Single; const LineIndex: Integer): Integer;
var
  V1, V2: TDoomVertex;
  Cross: Double;
begin
  V1 := Vertices[Linedefs[LineIndex].V1];
  V2 := Vertices[Linedefs[LineIndex].V2];
  Cross := (X - V1.X) * (V2.Y - V1.Y) - (Y - V1.Y) * (V2.X - V1.X);
  if Cross >= 0 then Result := 0 else Result := 1;
end;

function TDoomMap.SubsectorAt(const X, Y: Single): Integer;
var
  Child: Integer;
  Guard: Integer;
begin
  if Length(Nodes) = 0 then Exit(0);
  Child := High(Nodes);
  Guard := 0;
  while (Child and $8000) = 0 do
  begin
    Child := Nodes[Child].Children[PointOnNodeSide(X, Y, Child)];
    Inc(Guard);
    if Guard > 100000 then Exit(0);
  end;
  Result := Child and $7FFF;
  if Result > High(Subsectors) then Result := 0;
end;

function TDoomMap.SectorAt(const X, Y: Single): Integer;
begin
  if Length(Subsectors) = 0 then Exit(-1);
  Result := Subsectors[SubsectorAt(X, Y)].Sector;
end;

function TDoomMap.OtherSector(const LineIndex, Sector: Integer): Integer;
begin
  if Linedefs[LineIndex].BackSector < 0 then Exit(-1);
  if Linedefs[LineIndex].FrontSector = Sector then
    Result := Linedefs[LineIndex].BackSector
  else
    Result := Linedefs[LineIndex].FrontSector;
end;

function TDoomMap.LowestFloorSurrounding(const Sec: Integer): Single;
var
  L, O: Integer;
begin
  Result := Sectors[Sec].FloorHeight;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].FloorHeight < Result) then
      Result := Sectors[O].FloorHeight;
  end;
end;

function TDoomMap.HighestFloorSurrounding(const Sec: Integer): Single;
var
  L, O: Integer;
begin
  Result := -500;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].FloorHeight > Result) then
      Result := Sectors[O].FloorHeight;
  end;
end;

function TDoomMap.NextHighestFloor(const Sec: Integer; const CurrentHeight: Single): Single;
var
  L, O: Integer;
  Found: Boolean;
begin
  Result := CurrentHeight;
  Found := false;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].FloorHeight > CurrentHeight) then
      if (not Found) or (Sectors[O].FloorHeight < Result) then
      begin
        Result := Sectors[O].FloorHeight;
        Found := true;
      end;
  end;
end;

function TDoomMap.LowestCeilingSurrounding(const Sec: Integer): Single;
var
  L, O: Integer;
begin
  Result := 32767;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].CeilingHeight < Result) then
      Result := Sectors[O].CeilingHeight;
  end;
end;

function TDoomMap.HighestCeilingSurrounding(const Sec: Integer): Single;
var
  L, O: Integer;
begin
  Result := 0;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].CeilingHeight > Result) then
      Result := Sectors[O].CeilingHeight;
  end;
end;

function TDoomMap.MinSurroundingLight(const Sec: Integer; const MaxLight: Integer): Integer;
var
  L, O: Integer;
begin
  Result := MaxLight;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].LightLevel < Result) then
      Result := Sectors[O].LightLevel;
  end;
end;

function TDoomMap.MaxSurroundingLight(const Sec: Integer; const MinLight: Integer): Integer;
var
  L, O: Integer;
begin
  Result := MinLight;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].LightLevel > Result) then
      Result := Sectors[O].LightLevel;
  end;
end;

function TDoomMap.FindSectorFromTag(const Tag: Integer; const Start: Integer): Integer;
var
  I: Integer;
begin
  for I := Start + 1 to High(Sectors) do
    if Sectors[I].Tag = Tag then
      Exit(I);
  Result := -1;
end;

function TDoomMap.HasSkyCeiling(const Sec: Integer): Boolean;
begin
  Result := (Sec >= 0) and (Sectors[Sec].CeilingTex = 'F_SKY1');
end;

end.
