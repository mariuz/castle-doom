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
  DoomWad, DoomGldefs;

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

  { UDMF's per-part fields: 0 the upper texture, 1 the middle, 2 the lower. }
  TSidePart = 0..2;

  TDoomSidedef = record
    XOffset, YOffset: Integer;
    UpperTex, LowerTex, MiddleTex: String;
    Sector: Integer;
    { UDMF (UZDoom): offsets added to XOffset / YOffset per part, in map
      units, and texture scales (texels a map unit; 0 = 1, the default). }
    PartOffsetX, PartOffsetY, PartScaleX, PartScaleY: array [TSidePart] of Single;
    { UDMF "light": added to the sector's light, or the light itself when
      LightAbsolute. }
    Light: Integer;
    LightAbsolute: Boolean;
  end;

  { A floor or ceiling's UDMF texture placement (panning in map units,
    scale with 0 = 1, rotation in degrees) and light ("lightfloor":
    added to the sector's, or the light itself when absolute). }
  TPlaneLook = record
    PanX, PanY, ScaleX, ScaleY, Rotation: Single;
    Light: Integer;
    LightAbsolute: Boolean;
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
    { UDMF: the line's id (-1 none), and for the world's UdmfSpecial*
      types (DoomUdmf) their arguments and trigger (a TGenTrigger, + 8
      when monsters may). }
    Id: Integer;
    Args: array [0..4] of Integer;
    Trigger: Integer;
    { UDMF Hexen-style lines: the activation flags (DoomUdmf's Ua*), for
      scripts that give the line another action. }
    Activation: Integer;
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
    { UDMF: the floor's and ceiling's texture placement and light. }
    FloorLook, CeilingLook: TPlaneLook;
    { UDMF "lightcolor" (multiplies the light) and "fadecolor" (fog), as
      0..1 RGB; HasColor / HasFade false = white light, no fog. }
    HasColor, HasFade: Boolean;
    LightColor, FadeColor: TVector3;
  end;

  TDoomThing = record
    X, Y: Single;
    Angle: Integer;
    TypeNum: Integer;
    Flags: Integer;
    { UDMF: the thing id (TID, 0 none), the height above the floor and
      the arguments (arg0..arg4). }
    Tid: Integer;
    Z: Single;
    Args: array [0..4] of Integer;
  end;

  { A UDMF light thing (ZDoom's 9800-9830): where it shines from (its
    sector's floor + the thing's height, at load) and the light. }
  TMapLight = record
    X, Y, Z: Single;
    Light: TGlLight;
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
    { Partition line; fractional for ZDoom XGL3 nodes. }
    X, Y, DX, DY: Single;
    { Child codes: NodeSubsector bit set = subsector index, else node index.
      (Normalized from vanilla's bit 15 and ZDoom's bit 31.) }
    Children: array [0..1] of Integer;
  end;

  { Boom's pushers (P_SpawnPushers): wind (224) and current (225) push
    what is in Sector by (X, Y) map units a tic (wind half as much on the
    floor, current only there); a point pusher (226, a 5001 push or 5002
    pull thing at (SourceX, SourceY)) pushes what it sees within Radius,
    less the farther it is (Strength at its centre). }
  TPusherKind = (pkWind, pkCurrent, pkPush, pkPull);
  TDoomPusher = record
    Kind: TPusherKind;
    Sector: Integer;
    X, Y: Single;
    SourceX, SourceY, Radius, Strength: Single;
  end;

  { Linedef indices returned by the grid queries (reused between calls). }
  TLineList = array of Integer;

  { What a runtime scroller moves (TDynScroller). }
  TScrollTarget = (stSide, stFloor, stCeiling, stCarry);

  { Boom's displacement (245-249) and accelerative (214-218) scrollers,
    T_Scroll: each tic they move their target by Rate times the change of
    the control sector's floor + ceiling height since the last tic;
    accelerative ones add that to a speed (Velocity) they keep and move by
    it. Control -1: a constant scroller of a surface that also has one of
    those (its offset is then kept here too). }
  TDynScroller = record
    Target: TScrollTarget;
    { Sidedef or sector. }
    Index: Integer;
    Rate: TVector2;
    Control: Integer;
    Accel: Boolean;
    LastHeight: Single;
    Velocity: TVector2;
  end;

  TDoomMap = class
  strict private
    FWad: TDoomWad;
    FName: String;
    FNodesFormat: String;
    { The line grid: cells of LineGridCell units from (FGridX, FGridY),
      FGridW x FGridH of them; cell C's lines are FCellLines[FCellStart[C]
      .. FCellStart[C + 1] - 1], ascending. FLineMark / FMarkStamp drop
      the duplicates of a query (a line in several cells). }
    FGridX, FGridY: Single;
    FGridW, FGridH: Integer;
    FCellStart, FCellLines: array of Integer;
    FLineMark: array of Cardinal;
    FMarkStamp: Cardinal;
    FUdmf: Boolean;
    FUdmfNamespace: String;
    FUdmfSummary: String;
    { UDMF lines' opacity ("alpha", TranslucentLine), 1 = solid. }
    FUdmfAlpha: array of Single;
    { UDMF links resolved once the BSP is there: teleports to a thing id,
      (line, TID) pairs. }
    FTidTeleports: array of array [0..1] of Integer;
    FNodesStale: Boolean;
    procedure LoadUdmf(const MarkerIndex: Integer);
    procedure BuildNodes;
    procedure LogUdmfLook;
    procedure ResolveUdmfLinks;
    procedure BuildLineGrid;
    procedure NextMark;
    procedure AddCellRow(const Row, Col0, Col1: Integer; var Found: TLineList; var Count: Integer);
    procedure LoadLumps(const MarkerIndex: Integer);
    procedure LoadVanillaNodes(const NodesLump, SegsLump, SubsLump: Integer);
    procedure LoadExtendedNodes(const Data: PByte; const Size: Integer; const Format: String);
    function LoadGlNodes: Boolean;
    procedure BuildSectorLists;
    procedure BuildSubsectorPolygons;
    procedure BuildScrollers;
    function DynScrollerSummary: String;
    procedure BuildFrictionAndPushers;
    procedure BuildTranslucency;
    procedure BuildTransfers;
    { TexName when it names a colormap lump (Boom's 242), else ''. }
    function ColormapName(const TexName: String): String;
    function TranslucencyMapAlpha(const Lump: Integer): Single;
  public
    Vertices: array of TDoomVertex;
    Linedefs: array of TDoomLinedef;
    Sidedefs: array of TDoomSidedef;
    Sectors: array of TDoomSector;
    Things: array of TDoomThing;
    { REJECT: one bit per sector pair, set when no line of sight can exist
      (empty when the lump is missing or has the wrong size). }
    Reject: TBytes;
    Segs: array of TDoomSeg;
    Subsectors: array of TDoomSubsector;
    Nodes: array of TDoomNode;
    MinX, MinY, MaxX, MaxY: Single;
    { Scrollers (vanilla 48, Boom 85 and 250-255, P_SpawnScrollers), per
      tic and constant: SideScroll per sidedef in texels (X adds to the
      texture offset, Y to the row offset); FloorScroll / CeilingScroll
      per sector in map units, the way the flat moves; Carry per sector,
      the momentum a thing standing on the floor gains (Boom's
      CARRYFACTOR). Zero where nothing scrolls. }
    SideScroll: array of TVector2;
    FloorScroll, CeilingScroll, Carry: array of TVector2;
    { How many sides, floors, ceilings and carrying floors scroll. }
    ScrollingSides, ScrollingFloors, ScrollingCeilings, CarryingFloors: Integer;
    { The runtime scrollers (TDoomWorld.TicScrollers runs them), the
      surfaces they move (those draw from the offsets below instead of a
      constant speed), the offsets so far (SideOffset in texels like
      SideScroll, the flats' in map units like FloorScroll) and the carry
      they add this tic. }
    DynScrollers: array of TDynScroller;
    SideDynamic, FloorDynamic, CeilingDynamic: array of Boolean;
    SideOffset, FloorOffset, CeilingOffset, CarryNow: array of TVector2;
    { Boom's friction (223, P_SpawnFriction) per sector, used where the
      sector type has the friction bit (256): Friction multiplies the
      momentum each tic (Doom's 0.90625 elsewhere), MoveFactor the
      walking thrust (1 = Doom's). }
    Friction, MoveFactor: array of Single;
    Pushers: array of TDoomPusher;
    { Boom's translucency (260): the opacity of each linedef's middle
      texture, 1 = solid. The default map (the WAD's TRANMAP, else Boom's
      66%) or a 64 KB lump the 260 line's middle texture names, its
      opacity estimated from how it mixes the palette. }
    LineAlpha: array of Single;
    TranslucentLines: Integer;
    { Boom's light transfers: the sector whose light a sector's floor (213)
      or ceiling (261) shows, -1 for its own. }
    FloorLightSector, CeilingLightSector: array of Integer;
    LightTransfers: Integer;
    { Boom's sky transfer (271, 272: the upper texture of the line's front
      side as the sky of the tagged sky sectors, 272 mirrored). There is
      one sky here, so the transfer covering most sky sectors is used,
      when it covers more than half of them; empty when none is. }
    SkyTransferTexture: String;
    SkyTransferFlipped: Boolean;
    { Each sky sector's own sky by a 271 / 272 tagging it ('' = the map's
      sky): the geometry draws the ones that differ from the one sky
      cylinder as sky-textured ceilings (per-sector skies). }
    SectorSky: array of String;
    SectorSkyFlipped: array of Boolean;
    { Boom's deep water (242, "height transfer"): the control sector (the
      242 line's front sector) of each tagged sector, -1 for none; such a
      sector is drawn at its control sector's heights, and differently
      when the viewer is below the control's floor or above its ceiling
      (TDoomGeometry.WaterView). The colormaps the 242 line's front side
      names for those three views (lower: below the floor, middle:
      between, upper: above the ceiling; '' when the name is not a
      colormap lump). }
    HeightSec: array of Integer;
    WaterColormaps: array of array [0..2] of String;
    HeightTransfers: Integer;
    { UDMF's light things (ZDoom's dynamic light things). }
    MapLights: array of TMapLight;
    { UDMF: the map's BEHAVIOR lump (compiled ACS scripts), empty if none. }
    Behavior: TBytes;

    constructor Create(const AWad: TDoomWad; const MapName: String);

    { 0 when (X, Y) is on the front (right) side of the node partition line, else 1. }
    function PointOnNodeSide(const X, Y: Single; const NodeIndex: Integer): Integer;
    { 0 when (X, Y) is on the front (right) side of the linedef, else 1. }
    function PointOnLineSide(const X, Y: Single; const LineIndex: Integer): Integer;
    function SubsectorAt(const X, Y: Single): Integer;
    function SectorAt(const X, Y: Single): Integer;
    { The REJECT table says sector S1 can never see S2. }
    function RejectBlocks(const S1, S2: Integer): Boolean;
    { The sector across the line from Sector, -1 when one-sided. }
    function OtherSector(const LineIndex, Sector: Integer): Integer;

    { Doom's p_spec.c neighbour searches. }
    function LowestFloorSurrounding(const Sec: Integer): Single;
    function HighestFloorSurrounding(const Sec: Integer): Single;
    function NextHighestFloor(const Sec: Integer; const CurrentHeight: Single): Single;
    { Boom's P_FindNextLowestFloor, P_FindNextLowestCeiling and
      P_FindNextHighestCeiling: the nearest neighbour height below / above
      CurrentHeight, CurrentHeight itself when there is none. }
    function NextLowestFloor(const Sec: Integer; const CurrentHeight: Single): Single;
    function NextLowestCeiling(const Sec: Integer; const CurrentHeight: Single): Single;
    function NextHighestCeiling(const Sec: Integer; const CurrentHeight: Single): Single;
    function LowestCeilingSurrounding(const Sec: Integer): Single;
    function HighestCeilingSurrounding(const Sec: Integer): Single;
    function MinSurroundingLight(const Sec: Integer; const MaxLight: Integer): Integer;
    function MaxSurroundingLight(const Sec: Integer; const MinLight: Integer): Integer;
    { Next sector (after Start) with this tag, -1 when none. }
    function FindSectorFromTag(const Tag: Integer; const Start: Integer = -1): Integer;
    { Side texture helper: sidedef for a line side, nil-safe via index -1. }
    function SideSector(const LineIndex, SideIndex: Integer): Integer;
    function HasSkyCeiling(const Sec: Integer): Boolean;
    function HasSkyFloor(const Sec: Integer): Boolean;

    { The linedefs that may touch the box, or the segment widened by Pad
      units, in ascending index order like a scan of every line (so the
      callers' first-hit rules do not change): Found[0 .. Result - 1].
      A superset: the callers keep their exact tests. Built from the
      vertices (like Doom's BLOCKMAP, 128-unit cells; a PWAD's own
      BLOCKMAP lump may be missing or broken, so it is not read). }
    function LinesInBox(const X1, Y1, X2, Y2: Single; var Found: TLineList): Integer;
    function LinesNearSegment(const X1, Y1, X2, Y2, Pad: Single; var Found: TLineList): Integer;
    { The grid's size in cells (for the log and the unit test). }
    property GridWidth: Integer read FGridW;
    property GridHeight: Integer read FGridH;

    property Name: String read FName;
    property Wad: TDoomWad read FWad;
    { VANILLA, XNOD, ZNOD, XGLN, ZGLN, XGL2, ZGL2, XGL3, ZGL3, or GL_V1,
      GL_V2, GL_V3, GL_V5 (glBSP lumps). }
    property NodesFormat: String read FNodesFormat;
    { A UDMF map (TEXTMAP), its namespace (lower case). }
    property Udmf: Boolean read FUdmf;
    property UdmfNamespace: String read FUdmfNamespace;
  end;

const
  { Child code flag for subsectors in TDoomNode.Children. }
  NodeSubsector = $40000000;
  NodeIndexMask = $3FFFFFFF;

{ UDMF's light on a wall side or a floor / ceiling from the sector's
  current SectorLight (0..255). }
function SideLightLevel(const Side: TDoomSidedef; const SectorLight: Integer): Integer;
function PlaneLightLevel(const Look: TPlaneLook; const SectorLight: Integer): Integer;
{ A UDMF scale: 0 (not set, e.g. a binary map) means 1. }
function ScaleOr1(const S: Single): Single;

implementation

uses Math, ZStream, CastleLog, CastleUtils, DoomUdmf, DoomNodeBuilder;

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

function SideLightLevel(const Side: TDoomSidedef; const SectorLight: Integer): Integer;
begin
  if Side.LightAbsolute then
    Result := Side.Light
  else
    Result := SectorLight + Side.Light;
  Result := Max(0, Min(255, Result));
end;

function PlaneLightLevel(const Look: TPlaneLook; const SectorLight: Integer): Integer;
begin
  if Look.LightAbsolute then
    Result := Look.Light
  else
    Result := SectorLight + Look.Light;
  Result := Max(0, Min(255, Result));
end;

function ScaleOr1(const S: Single): Single;
begin
  if S = 0 then Result := 1 else Result := S;
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
  if (Marker + 1 < FWad.LumpCount) and (FWad.LumpName(Marker + 1) = 'TEXTMAP') then
    LoadUdmf(Marker)
  else
    LoadLumps(Marker);
  BuildSectorLists;
  BuildSubsectorPolygons;
  if FUdmf then ResolveUdmfLinks;
  BuildLineGrid;
  BuildScrollers;
  BuildFrictionAndPushers;
  BuildTranslucency;
  BuildTransfers;
  if ScrollingSides + ScrollingFloors + ScrollingCeilings + CarryingFloors > 0 then
    WritelnLog('Map', '%s: scrollers: %d walls, %d floors, %d ceilings, %d carrying floors%s', [
      FName, ScrollingSides, ScrollingFloors, ScrollingCeilings, CarryingFloors,
      DynScrollerSummary]);
  WritelnLog('Map', '%s: %d vertices, %d linedefs, %d sectors, %d things, %d subsectors, %d nodes, line grid %d x %d', [
    FName, Length(Vertices), Length(Linedefs), Length(Sectors), Length(Things),
    Length(Subsectors), Length(Nodes), FGridW, FGridH]);
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
  L, I, N, NodesL, SegsL, SubsL: Integer;
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

  { REJECT (optional; a wrong size means a bad or placeholder table) }
  SetLength(Reject, 0);
  for I := MarkerIndex + 1 to Min(MarkerIndex + 11, FWad.LumpCount - 1) do
    if FWad.LumpName(I) = 'REJECT' then
    begin
      if FWad.LumpSize(I) = (Int64(Length(Sectors)) * Length(Sectors) + 7) div 8 then
        Reject := FWad.LumpBytes(I);
      Break;
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
    Linedefs[I].Side[0] := PUInt16(P + I * 14 + 10)^;
    Linedefs[I].Side[1] := PUInt16(P + I * 14 + 12)^;
    if Linedefs[I].Side[0] = $FFFF then Linedefs[I].Side[0] := -1;
    if Linedefs[I].Side[1] = $FFFF then Linedefs[I].Side[1] := -1;
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

  { BSP: vanilla NODES/SEGS/SSECTORS, or ZDoom extended nodes in NODES
    (XNOD, ZNOD, also GL variants) or GL nodes in SSECTORS (XGLN...ZGL3,
    where ZDBSP leaves NODES and SEGS empty). }
  NodesL := MapLump('NODES');
  SegsL := MapLump('SEGS');
  SubsL := MapLump('SSECTORS');
  Magic := '';
  if FWad.LumpSize(NodesL) >= 4 then
  begin
    P := FWad.LumpPointer(NodesL);
    Magic := Chr(P[0]) + Chr(P[1]) + Chr(P[2]) + Chr(P[3]);
  end;
  if (Magic = 'XNOD') or (Magic = 'ZNOD') or (Magic = 'XGLN') or (Magic = 'ZGLN') or
     (Magic = 'XGL2') or (Magic = 'ZGL2') or (Magic = 'XGL3') or (Magic = 'ZGL3') then
    LoadExtendedNodes(FWad.LumpPointer(NodesL), FWad.LumpSize(NodesL), Magic)
  else
  begin
    Magic := '';
    if FWad.LumpSize(SubsL) >= 4 then
    begin
      P := FWad.LumpPointer(SubsL);
      Magic := Chr(P[0]) + Chr(P[1]) + Chr(P[2]) + Chr(P[3]);
    end;
    if (Magic = 'XGLN') or (Magic = 'ZGLN') or (Magic = 'XGL2') or (Magic = 'ZGL2') or
       (Magic = 'XGL3') or (Magic = 'ZGL3') then
      LoadExtendedNodes(FWad.LumpPointer(SubsL), FWad.LumpSize(SubsL), Magic)
    else
    begin
      if (FWad.LumpSize(NodesL) = 0) and (FWad.LumpSize(SubsL) = 0) then
      begin
        { glBSP run with -xn leaves the normal nodes empty: GL_<map>. }
        if not LoadGlNodes then
          raise Exception.CreateFmt('Map %s has no BSP nodes; build it with a node builder (ZDBSP, ZokumBSP, glBSP...)', [FName]);
      end else
        LoadVanillaNodes(NodesL, SegsL, SubsL);
    end;
  end;
end;

{ A UDMF map (DoomUdmf): the marker, TEXTMAP, maybe ZNODES (ZDoom's GL
  nodes for this TEXTMAP), REJECT, BLOCKMAP, BEHAVIOR (ACS scripts, run by DoomAcs)...
  and ENDMAP. Without (current) ZNODES the nodes are built here
  (DoomNodeBuilder), as UZDoom does. Hexen-namespace specials and sector
  types are translated to Doom's / Boom's (TranslateHexenLine). }
procedure TDoomMap.LoadUdmf(const MarkerIndex: Integer);
var
  U: TUdmfMap;
  Text, Kind, NodesMagic: String;
  I, J, L, NV, NL, NS, NSec, NT, ZNodes, Translated, Act: Integer;
  B: PUdmfBlock;
  Hexen: Boolean;
  H: THexenLine;
  Args: array [0..4] of Integer;
  Unsupported: TStringList;
  P: PByte;
  Part: TSidePart;
const
  PartNames: array [TSidePart] of String = ('top', 'mid', 'bottom');

  procedure Flag(const Key: String; const Bit: Integer);
  begin
    if UdmfBool(B^, Key) then
      Linedefs[NL].Flags := Linedefs[NL].Flags or Bit;
  end;

  procedure Act1(const Key: String; const Bit: Integer);
  begin
    if UdmfBool(B^, Key) then
      Act := Act or Bit;
  end;

  function Tex(const Key: String): String;
  begin
    Result := UpperCase(UdmfStr(B^, Key, '-'));
    if Result = '' then Result := '-';
  end;

  { "xpanningfloor", "xscalefloor", "rotationfloor", "lightfloor"... }
  procedure Plane(var Look: TPlaneLook; const Which: String);
  begin
    Look.PanX := UdmfFloat(B^, 'xpanning' + Which);
    Look.PanY := UdmfFloat(B^, 'ypanning' + Which);
    Look.ScaleX := UdmfFloat(B^, 'xscale' + Which, 1);
    Look.ScaleY := UdmfFloat(B^, 'yscale' + Which, 1);
    Look.Rotation := UdmfFloat(B^, 'rotation' + Which);
    Look.Light := UdmfInt(B^, 'light' + Which);
    Look.LightAbsolute := UdmfBool(B^, 'light' + Which + 'absolute');
  end;

  function ColorOf(const C: Integer): TVector3;
  begin
    Result := Vector3(((C shr 16) and 255) / 255, ((C shr 8) and 255) / 255, (C and 255) / 255);
  end;

begin
  FUdmf := true;
  L := MarkerIndex + 1;
  SetLength(Text, FWad.LumpSize(L));
  if Length(Text) > 0 then
    Move(FWad.LumpPointer(L)^, Text[1], Length(Text));
  { The map's other lumps, up to ENDMAP. }
  ZNodes := -1;
  SetLength(Reject, 0);
  for I := L + 1 to FWad.LumpCount - 1 do
  begin
    if FWad.LumpName(I) = 'ENDMAP' then Break;
    if FWad.LumpName(I) = 'ZNODES' then ZNodes := I;
    if FWad.LumpName(I) = 'BEHAVIOR' then Behavior := FWad.LumpBytes(I);
    if FWad.LumpName(I) = 'REJECT' then J := I else J := -1;
    if J >= 0 then Reject := FWad.LumpBytes(J);
  end;

  U := TUdmfMap.Create(Text);
  Unsupported := TStringList.Create;
  try
    if U.Error <> '' then
      raise Exception.CreateFmt('Map %s: %s', [FName, U.Error]);
    FUdmfNamespace := U.Namespace;
    Hexen := U.HexenSpecials;
    NV := 0; NL := 0; NS := 0; NSec := 0; NT := 0;
    for I := 0 to U.BlockCount - 1 do
    begin
      Kind := U.Blocks[I].Kind;
      if Kind = 'vertex' then Inc(NV)
      else if Kind = 'linedef' then Inc(NL)
      else if Kind = 'sidedef' then Inc(NS)
      else if Kind = 'sector' then Inc(NSec)
      else if Kind = 'thing' then Inc(NT);
    end;
    SetLength(Vertices, NV);
    SetLength(Linedefs, NL);
    SetLength(Sidedefs, NS);
    SetLength(Sectors, NSec);
    SetLength(Things, NT);
    SetLength(FUdmfAlpha, NL);
    NV := 0; NL := 0; NS := 0; NSec := 0; NT := 0;
    Translated := 0;
    MinX := 1e9; MinY := 1e9; MaxX := -1e9; MaxY := -1e9;
    for I := 0 to U.BlockCount - 1 do
    begin
      B := @U.Blocks[I];
      Kind := B^.Kind;
      if Kind = 'vertex' then
      begin
        Vertices[NV].X := UdmfFloat(B^, 'x');
        Vertices[NV].Y := UdmfFloat(B^, 'y');
        MinX := Min(MinX, Vertices[NV].X);
        MaxX := Max(MaxX, Vertices[NV].X);
        MinY := Min(MinY, Vertices[NV].Y);
        MaxY := Max(MaxY, Vertices[NV].Y);
        Inc(NV);
      end else
      if Kind = 'sector' then
      begin
        Sectors[NSec].FloorHeight := UdmfFloat(B^, 'heightfloor');
        Sectors[NSec].CeilingHeight := UdmfFloat(B^, 'heightceiling');
        Sectors[NSec].OrigFloor := Round(Sectors[NSec].FloorHeight);
        Sectors[NSec].OrigCeiling := Round(Sectors[NSec].CeilingHeight);
        Sectors[NSec].FloorTex := UpperCase(UdmfStr(B^, 'texturefloor', '-'));
        Sectors[NSec].CeilingTex := UpperCase(UdmfStr(B^, 'textureceiling', '-'));
        Sectors[NSec].OrigLight := UdmfInt(B^, 'lightlevel', 160);
        Sectors[NSec].LightLevel := Sectors[NSec].OrigLight;
        Sectors[NSec].Special := UdmfInt(B^, 'special');
        if Hexen then
          Sectors[NSec].Special := TranslateZDoomSectorSpecial(Sectors[NSec].Special);
        if UdmfBool(B^, 'secret') then
          Sectors[NSec].Special := Sectors[NSec].Special or 128;
        Sectors[NSec].Tag := UdmfInt(B^, 'id');
        Plane(Sectors[NSec].FloorLook, 'floor');
        Plane(Sectors[NSec].CeilingLook, 'ceiling');
        if UdmfHas(B^, 'lightcolor') then
        begin
          Sectors[NSec].LightColor := ColorOf(UdmfInt(B^, 'lightcolor'));
          Sectors[NSec].HasColor := not TVector3.PerfectlyEquals(Sectors[NSec].LightColor, Vector3(1, 1, 1));
        end;
        if UdmfHas(B^, 'fadecolor') and (UdmfInt(B^, 'fadecolor') <> 0) then
        begin
          Sectors[NSec].FadeColor := ColorOf(UdmfInt(B^, 'fadecolor'));
          Sectors[NSec].HasFade := true;
        end;
        Inc(NSec);
      end else
      if Kind = 'sidedef' then
      begin
        Sidedefs[NS].XOffset := UdmfInt(B^, 'offsetx');
        Sidedefs[NS].YOffset := UdmfInt(B^, 'offsety');
        Sidedefs[NS].UpperTex := Tex('texturetop');
        Sidedefs[NS].LowerTex := Tex('texturebottom');
        Sidedefs[NS].MiddleTex := Tex('texturemiddle');
        Sidedefs[NS].Sector := UdmfInt(B^, 'sector');
        for Part := Low(TSidePart) to High(TSidePart) do
        begin
          Sidedefs[NS].PartOffsetX[Part] := UdmfFloat(B^, 'offsetx_' + PartNames[Part]);
          Sidedefs[NS].PartOffsetY[Part] := UdmfFloat(B^, 'offsety_' + PartNames[Part]);
          Sidedefs[NS].PartScaleX[Part] := UdmfFloat(B^, 'scalex_' + PartNames[Part], 1);
          Sidedefs[NS].PartScaleY[Part] := UdmfFloat(B^, 'scaley_' + PartNames[Part], 1);
        end;
        Sidedefs[NS].Light := UdmfInt(B^, 'light');
        Sidedefs[NS].LightAbsolute := UdmfBool(B^, 'lightabsolute');
        Inc(NS);
      end else
      if Kind = 'thing' then
      begin
        Things[NT].X := UdmfFloat(B^, 'x');
        Things[NT].Y := UdmfFloat(B^, 'y');
        Things[NT].Z := UdmfFloat(B^, 'height');
        Things[NT].Angle := UdmfInt(B^, 'angle');
        Things[NT].TypeNum := UdmfInt(B^, 'type');
        { ZDoom's teleport destinations with a height. }
        if (Things[NT].TypeNum = 9043) or (Things[NT].TypeNum = 9044) then
          Things[NT].TypeNum := 14;
        Things[NT].Tid := UdmfInt(B^, 'id');
        for J := 0 to 4 do
          Things[NT].Args[J] := UdmfInt(B^, 'arg' + IntToStr(J));
        Things[NT].Flags := 0;
        if UdmfBool(B^, 'skill1') or UdmfBool(B^, 'skill2') then
          Things[NT].Flags := Things[NT].Flags or MTF_EASY;
        if UdmfBool(B^, 'skill3') then
          Things[NT].Flags := Things[NT].Flags or MTF_NORMAL;
        if UdmfBool(B^, 'skill4') or UdmfBool(B^, 'skill5') then
          Things[NT].Flags := Things[NT].Flags or MTF_HARD;
        if UdmfBool(B^, 'ambush') then
          Things[NT].Flags := Things[NT].Flags or MTF_AMBUSH;
        if not UdmfBool(B^, 'single') then
          Things[NT].Flags := Things[NT].Flags or MTF_NOTSINGLE;
        Inc(NT);
      end else
      if Kind = 'linedef' then
      begin
        Linedefs[NL] := Default(TDoomLinedef);
        Linedefs[NL].V1 := UdmfInt(B^, 'v1');
        Linedefs[NL].V2 := UdmfInt(B^, 'v2');
        Linedefs[NL].Side[0] := UdmfInt(B^, 'sidefront', -1);
        Linedefs[NL].Side[1] := UdmfInt(B^, 'sideback', -1);
        Linedefs[NL].Id := UdmfInt(B^, 'id', -1);
        Flag('blocking', ML_BLOCKING);
        Flag('blockmonsters', ML_BLOCKMONSTERS);
        Flag('twosided', ML_TWOSIDED);
        Flag('dontpegtop', ML_DONTPEGTOP);
        Flag('dontpegbottom', ML_DONTPEGBOTTOM);
        Flag('secret', ML_SECRET);
        Flag('blocksound', ML_SOUNDBLOCK);
        Flag('dontdraw', ML_DONTDRAW);
        Flag('mapped', ML_MAPPED);
        Flag('passuse', 512);
        FUdmfAlpha[NL] := 1;
        if UdmfHas(B^, 'alpha') then
          FUdmfAlpha[NL] := Max(0.0, Min(1.0, UdmfFloat(B^, 'alpha', 1)))
        else if UdmfBool(B^, 'translucent') then
          FUdmfAlpha[NL] := 0.75;
        if Hexen then
        begin
          for J := 0 to 4 do
            Args[J] := UdmfInt(B^, 'arg' + IntToStr(J));
          Act := 0;
          Act1('playercross', UaPlayerCross);
          Act1('playeruse', UaPlayerUse);
          Act1('monstercross', UaMonsterCross);
          Act1('monsteruse', UaMonsterUse);
          Act1('impact', UaImpact);
          Act1('playerpush', UaPlayerPush);
          Act1('monsterpush', UaMonsterPush);
          Act1('missilecross', UaMissileCross);
          Act1('repeatspecial', UaRepeat);
          H := TranslateHexenLine(UdmfInt(B^, 'special'), Args, Act);
          Linedefs[NL].Special := H.Special;
          Linedefs[NL].Tag := H.Tag;
          for J := 0 to 4 do
            Linedefs[NL].Args[J] := H.Args[J];
          Linedefs[NL].Trigger := H.Trigger;
          Linedefs[NL].Activation := Act;
          if H.Special <> 0 then Inc(Translated);
          if H.Unsupported <> '' then
            Unsupported.Add(H.Unsupported);
          if H.TeleportTid <> 0 then
          begin
            SetLength(FTidTeleports, Length(FTidTeleports) + 1);
            FTidTeleports[High(FTidTeleports)][0] := NL;
            FTidTeleports[High(FTidTeleports)][1] := H.TeleportTid;
          end;
          if H.TranslucentId <> 0 then
          begin
            if H.TranslucentId < 0 then
              FUdmfAlpha[NL] := H.Alpha
            else
              { Lines read so far; ResolveUdmfLinks does all of them. }
              Linedefs[NL].Args[4] := Round(H.Alpha * 255);
            Linedefs[NL].Args[3] := H.TranslucentId;
          end;
        end else
        begin
          { Doom's numbers; the id is the tag. }
          Linedefs[NL].Special := UdmfInt(B^, 'special');
          Linedefs[NL].Tag := Max(0, Linedefs[NL].Id);
        end;
        Inc(NL);
      end;
    end;
  except
    FreeAndNil(U);
    FreeAndNil(Unsupported);
    raise;
  end;
  FreeAndNil(U);

  for I := 0 to High(Sidedefs) do
    if (Sidedefs[I].Sector < 0) or (Sidedefs[I].Sector >= Length(Sectors)) then
      Sidedefs[I].Sector := 0;
  for I := 0 to High(Linedefs) do
  begin
    if (Linedefs[I].Side[0] < 0) or (Linedefs[I].Side[0] >= Length(Sidedefs)) then Linedefs[I].Side[0] := -1;
    if (Linedefs[I].Side[1] < 0) or (Linedefs[I].Side[1] >= Length(Sidedefs)) then Linedefs[I].Side[1] := -1;
    if (Linedefs[I].V1 < 0) or (Linedefs[I].V1 >= Length(Vertices)) then Linedefs[I].V1 := 0;
    if (Linedefs[I].V2 < 0) or (Linedefs[I].V2 >= Length(Vertices)) then Linedefs[I].V2 := 0;
    Linedefs[I].FrontSector := SideSector(I, 0);
    Linedefs[I].BackSector := SideSector(I, 1);
    Linedefs[I].Length := Sqrt(Sqr(Vertices[Linedefs[I].V2].X - Vertices[Linedefs[I].V1].X) +
      Sqr(Vertices[Linedefs[I].V2].Y - Vertices[Linedefs[I].V1].Y));
  end;
  if Length(Reject) <> (Int64(Length(Sectors)) * Length(Sectors) + 7) div 8 then
    SetLength(Reject, 0);

  { The nodes: ZDoom's GL nodes in ZNODES, else built here. }
  NodesMagic := '';
  if (ZNodes >= 0) and (FWad.LumpSize(ZNodes) >= 4) then
  begin
    P := FWad.LumpPointer(ZNodes);
    NodesMagic := Chr(P[0]) + Chr(P[1]) + Chr(P[2]) + Chr(P[3]);
  end;
  FNodesStale := false;
  if (NodesMagic = 'XGLN') or (NodesMagic = 'ZGLN') or (NodesMagic = 'XGL2') or (NodesMagic = 'ZGL2') or
     (NodesMagic = 'XGL3') or (NodesMagic = 'ZGL3') or (NodesMagic = 'XNOD') or (NodesMagic = 'ZNOD') then
  begin
    LoadExtendedNodes(FWad.LumpPointer(ZNodes), FWad.LumpSize(ZNodes), NodesMagic);
    if FNodesStale then
    begin
      WritelnLog('Map', '%s: ZNODES do not match the TEXTMAP, building new nodes', [FName]);
      SetLength(Vertices, NV);
      BuildNodes;
    end;
  end else
    BuildNodes;

  Unsupported.Sort;
  FUdmfSummary := '';
  I := 0;
  while I < Unsupported.Count do
  begin
    J := I;
    while (J + 1 < Unsupported.Count) and (Unsupported[J + 1] = Unsupported[I]) do Inc(J);
    if FUdmfSummary <> '' then FUdmfSummary := FUdmfSummary + ', ';
    FUdmfSummary := FUdmfSummary + Unsupported[I];
    if J > I then FUdmfSummary := FUdmfSummary + Format(' x%d', [J - I + 1]);
    I := J + 1;
  end;
  WritelnLog('Map', '%s: UDMF, namespace "%s": %d vertices, %d linedefs, %d sidedefs, %d sectors, %d things, %s nodes', [
    FName, FUdmfNamespace, Length(Vertices), Length(Linedefs), Length(Sidedefs), Length(Sectors),
    Length(Things), FNodesFormat]);
  LogUdmfLook;
  if Hexen then
  begin
    if Unsupported.Count = 0 then
      WritelnLog('Map', '%s: %d Hexen-style line specials translated', [FName, Translated])
    else
      WritelnLog('Map', '%s: %d Hexen-style line specials translated, %d not supported: %s', [
        FName, Translated, Unsupported.Count, FUdmfSummary]);
  end;
  FreeAndNil(Unsupported);
end;

{ How many sectors and sides use UDMF's rendering fields, for the log. }
procedure TDoomMap.LogUdmfLook;
var
  I: Integer;
  Part: TSidePart;
  Colored, Fogged, Flats, Sides, Lit: Integer;

  function Placed(const Look: TPlaneLook): Boolean;
  begin
    Result := (Look.PanX <> 0) or (Look.PanY <> 0) or (ScaleOr1(Look.ScaleX) <> 1) or
      (ScaleOr1(Look.ScaleY) <> 1) or (Look.Rotation <> 0);
  end;

begin
  Colored := 0; Fogged := 0; Flats := 0; Sides := 0; Lit := 0;
  for I := 0 to High(Sectors) do
  begin
    if Sectors[I].HasColor then Inc(Colored);
    if Sectors[I].HasFade then Inc(Fogged);
    if Placed(Sectors[I].FloorLook) then Inc(Flats);
    if Placed(Sectors[I].CeilingLook) then Inc(Flats);
    if (Sectors[I].FloorLook.Light <> 0) or Sectors[I].FloorLook.LightAbsolute or
       (Sectors[I].CeilingLook.Light <> 0) or Sectors[I].CeilingLook.LightAbsolute then
      Inc(Lit);
  end;
  for I := 0 to High(Sidedefs) do
  begin
    if (Sidedefs[I].Light <> 0) or Sidedefs[I].LightAbsolute then Inc(Lit);
    for Part := Low(TSidePart) to High(TSidePart) do
      if (Sidedefs[I].PartOffsetX[Part] <> 0) or (Sidedefs[I].PartOffsetY[Part] <> 0) or
         (ScaleOr1(Sidedefs[I].PartScaleX[Part]) <> 1) or (ScaleOr1(Sidedefs[I].PartScaleY[Part]) <> 1) then
      begin
        Inc(Sides);
        Break;
      end;
  end;
  if Colored + Fogged + Flats + Sides + Lit > 0 then
    WritelnLog('Map', '%s: UDMF look: %d coloured sectors, %d fogged, %d placed flats, %d placed sides, %d own lights', [
      FName, Colored, Fogged, Flats, Sides, Lit]);
end;

{ DoomNodeBuilder's BSP for a map that came without nodes (UDMF): the
  vertices go in rounded (the builder's are whole units), the split
  points are appended after the map's own. }
procedure TDoomMap.BuildNodes;
var
  B: TNodeBuilder;
  NbVerts: TNbVertexArray;
  NbLines: TNbLineArray;
  SideSectors: array of Integer;
  I, K, N, Base, C: Integer;
begin
  SetLength(NbVerts, Length(Vertices));
  for I := 0 to High(Vertices) do
  begin
    NbVerts[I].X := Round(Vertices[I].X);
    NbVerts[I].Y := Round(Vertices[I].Y);
  end;
  SetLength(NbLines, Length(Linedefs));
  for I := 0 to High(Linedefs) do
  begin
    NbLines[I].V1 := Linedefs[I].V1;
    NbLines[I].V2 := Linedefs[I].V2;
    NbLines[I].Side[0] := Linedefs[I].Side[0];
    NbLines[I].Side[1] := Linedefs[I].Side[1];
  end;
  SetLength(SideSectors, Length(Sidedefs));
  for I := 0 to High(Sidedefs) do
    SideSectors[I] := Sidedefs[I].Sector;
  B := TNodeBuilder.Create;
  try
    B.Run(NbVerts, NbLines, SideSectors);
    Base := Length(Vertices);
    SetLength(Vertices, Length(B.Vertices));
    for I := Base to High(B.Vertices) do
    begin
      Vertices[I].X := B.Vertices[I].X;
      Vertices[I].Y := B.Vertices[I].Y;
    end;
    SetLength(Segs, Length(B.Segs));
    for I := 0 to High(B.Segs) do
    begin
      Segs[I].V1 := B.Segs[I].V1;
      Segs[I].V2 := B.Segs[I].V2;
      Segs[I].Angle := B.Segs[I].Angle;
      Segs[I].Linedef := B.Segs[I].Line;
      Segs[I].Side := B.Segs[I].Side;
      Segs[I].Offset := B.Segs[I].Offset;
    end;
    SetLength(Subsectors, Length(B.Subsectors));
    for I := 0 to High(B.Subsectors) do
    begin
      Subsectors[I].SegCount := B.Subsectors[I].Count;
      Subsectors[I].FirstSeg := B.Subsectors[I].First;
      Subsectors[I].Sector := -1;
    end;
    { The builder's root is node 0; Doom's is the last. }
    N := Length(B.Nodes);
    SetLength(Nodes, N);
    for I := 0 to N - 1 do
    begin
      Nodes[N - 1 - I].X := B.Nodes[I].X;
      Nodes[N - 1 - I].Y := B.Nodes[I].Y;
      Nodes[N - 1 - I].DX := B.Nodes[I].DX;
      Nodes[N - 1 - I].DY := B.Nodes[I].DY;
      for K := 0 to 1 do
      begin
        C := B.Nodes[I].Child[K];
        if C >= 0 then
          Nodes[N - 1 - I].Children[K] := N - 1 - C
        else
          Nodes[N - 1 - I].Children[K] := (-1 - C) or NodeSubsector;
      end;
    end;
    FNodesFormat := 'BUILT';
    WritelnLog('Map', '%s: nodes built: %d segs (%d split), %d subsectors, %d nodes', [
      FName, Length(Segs), B.SplitCount, Length(Subsectors), Length(Nodes)]);
  finally
    FreeAndNil(B);
  end;
end;

{ What UDMF lines point at by id: teleport destinations by thing id
  (their sector gets a tag the line uses), Teleport_Line's other line,
  TranslucentLine's lines. }
procedure TDoomMap.ResolveUdmfLinks;
var
  I, J, K, Line, Tid, Sec, NewTag, Id, Skipped: Integer;
  T: TDoomThing;
  L: TGlLight;
begin
  { ZDoom's light things: arg0..2 the colour (0..255), arg3 the radius,
    arg4 the second radius (pulse, flicker); a pulse's cycle is its angle
    in tics, a flicker's chance its angle / 360. 9810-9814 (additive)
    act as 9800-9804; subtractive (9820-9824) and spot lights are
    counted, not drawn. }
  MapLights := nil;
  Skipped := 0;
  for I := 0 to High(Things) do
  begin
    T := Things[I];
    if (T.TypeNum < 9800) or (T.TypeNum > 9849) then Continue;
    L := Default(TGlLight);
    L.Name := 'thing ' + IntToStr(I);
    L.Color := Vector3(T.Args[0], T.Args[1], T.Args[2]) / 255;
    L.Size := T.Args[3];
    L.SecondarySize := T.Args[4];
    L.Interval := Max(1, T.Angle) / 35;
    L.Chance := (T.Angle mod 360) / 360;
    case T.TypeNum of
      9800, 9810: L.Kind := glPoint;
      9801, 9811: L.Kind := glPulse;
      9802, 9812: L.Kind := glFlicker;
      9803, 9813:
        begin
          { The sector's light scales the radius (arg3 = 4: the light). }
          L.Kind := glPoint;
          Sec := SectorAt(T.X, T.Y);
          if Sec >= 0 then L.Size := Sectors[Sec].LightLevel * T.Args[3] / 4;
        end;
      9804, 9814: L.Kind := glFlicker2;
      9830:
        begin
          { Vavoom's light: arg0 the radius, arg1..3 the colour. }
          L.Kind := glPoint;
          L.Size := T.Args[0];
          L.Color := Vector3(T.Args[1], T.Args[2], T.Args[3]) / 255;
        end;
      9825:
        begin
          L.Kind := glPoint;
          L.Size := T.Args[0];
          L.Color := Vector3(1, 1, 1);
        end;
      else
        begin
          Inc(Skipped);
          Continue;
        end;
    end;
    if L.SecondarySize = 0 then L.SecondarySize := L.Size;
    if L.Size <= 0 then Continue;
    Sec := SectorAt(T.X, T.Y);
    if Sec < 0 then Continue;
    SetLength(MapLights, Length(MapLights) + 1);
    MapLights[High(MapLights)].X := T.X;
    MapLights[High(MapLights)].Y := T.Y;
    MapLights[High(MapLights)].Z := Sectors[Sec].FloorHeight + T.Z;
    MapLights[High(MapLights)].Light := L;
  end;
  if (Length(MapLights) > 0) or (Skipped > 0) then
    WritelnLog('Map', '%s: %d light things, %d not supported (subtractive or spot lights)', [
      FName, Length(MapLights), Skipped]);

  NewTag := 0;
  for I := 0 to High(Sectors) do
    NewTag := Max(NewTag, Sectors[I].Tag);
  for I := 0 to High(Linedefs) do
    NewTag := Max(NewTag, Linedefs[I].Tag);
  for K := 0 to High(FTidTeleports) do
  begin
    Line := FTidTeleports[K][0];
    Tid := FTidTeleports[K][1];
    for J := 0 to High(Things) do
      if (Things[J].Tid = Tid) and (Things[J].TypeNum = 14) then
      begin
        Sec := SectorAt(Things[J].X, Things[J].Y);
        if Sec < 0 then Break;
        if Sectors[Sec].Tag = 0 then
        begin
          Inc(NewTag);
          Sectors[Sec].Tag := NewTag;
        end;
        Linedefs[Line].Tag := Sectors[Sec].Tag;
        Break;
      end;
  end;
  for I := 0 to High(Linedefs) do
  begin
    { Teleport_Line: the destination line carries the same tag. }
    if ((Linedefs[I].Special = 243) or (Linedefs[I].Special = 244) or (Linedefs[I].Special = 262) or
        (Linedefs[I].Special = 263)) and (Linedefs[I].Tag <> 0) then
      for J := 0 to High(Linedefs) do
        if (J <> I) and (Linedefs[J].Id = Linedefs[I].Tag) and (Linedefs[J].Tag = 0) then
          Linedefs[J].Tag := Linedefs[I].Tag;
    { TranslucentLine by id: Args[3] the id, Args[4] the opacity x 255. }
    Id := Linedefs[I].Args[3];
    if (Linedefs[I].Special = 0) and (Id > 0) and (Linedefs[I].Args[4] > 0) then
      for J := 0 to High(Linedefs) do
        if Linedefs[J].Id = Id then
          FUdmfAlpha[J] := Linedefs[I].Args[4] / 255;
  end;
end;

procedure TDoomMap.LoadVanillaNodes(const NodesLump, SegsLump, SubsLump: Integer);
var
  P: PByte;
  I, N, C, K: Integer;
begin
  FNodesFormat := 'VANILLA';
  { NODES }
  P := FWad.LumpPointer(NodesLump);
  N := FWad.LumpSize(NodesLump) div 28;
  SetLength(Nodes, N);
  for I := 0 to N - 1 do
  begin
    Nodes[I].X := PInt16(P + I * 28)^;
    Nodes[I].Y := PInt16(P + I * 28 + 2)^;
    Nodes[I].DX := PInt16(P + I * 28 + 4)^;
    Nodes[I].DY := PInt16(P + I * 28 + 6)^;
    for K := 0 to 1 do
    begin
      C := PUInt16(P + I * 28 + 24 + K * 2)^;
      if (C and $8000) <> 0 then
        Nodes[I].Children[K] := (C and $7FFF) or NodeSubsector
      else
        Nodes[I].Children[K] := C;
    end;
  end;

  { SEGS }
  P := FWad.LumpPointer(SegsLump);
  N := FWad.LumpSize(SegsLump) div 12;
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
    if Segs[I].Linedef >= Length(Linedefs) then Segs[I].Linedef := -1;
    if Segs[I].Side <> 0 then Segs[I].Side := 1;
  end;

  { SSECTORS }
  P := FWad.LumpPointer(SubsLump);
  N := FWad.LumpSize(SubsLump) div 4;
  SetLength(Subsectors, N);
  for I := 0 to N - 1 do
  begin
    Subsectors[I].SegCount := PUInt16(P + I * 4)^;
    Subsectors[I].FirstSeg := PUInt16(P + I * 4 + 2)^;
    Subsectors[I].Sector := -1;
  end;
end;

{ ZDoom extended nodes (zdoom.org/wiki/Node#ZDoom_extended_nodes):

    magic  XNOD | ZNOD (zlib) | XGLN | ZGLN | XGL2 | ZGL2 | XGL3 | ZGL3
    uint32 OrgVerts, uint32 NewVerts, NewVerts x (fixed x, fixed y)
    uint32 NumSubsectors, NumSubsectors x uint32 seg count (first seg implicit)
    uint32 NumSegs, segs:
      XNOD: uint32 v1, uint32 v2, uint16 line, uint8 side
      XGLN: uint32 v1, uint32 partner, uint16 line (FFFF = miniseg), uint8 side
      XGL2/XGL3: as XGLN with uint32 line (FFFFFFFF = miniseg)
    uint32 NumNodes, nodes:
      int16 x, y, dx, dy (XGL3: fixed 16.16), int16 bbox[2][4],
      uint32 child[2] (bit 31 = subsector)

  GL segs list only v1; v2 is the next seg's v1 around the (closed) subsector. }
procedure TDoomMap.LoadExtendedNodes(const Data: PByte; const Size: Integer; const Format: String);
var
  Buf: TBytes;
  Pos, BufSize: Integer;
  Compressed, GL, LongLines, FixedNodes: Boolean;
  OrgVerts, NewVerts, NumSubs, NumSegs, NumNodes, First, LineIndex: Int64;
  I, K, Base, VIndex: Integer;
  C: Cardinal;

  procedure Need(const Bytes: Integer);
  begin
    if Pos + Bytes > BufSize then
      raise Exception.CreateFmt('Map %s: truncated %s nodes', [FName, Format]);
  end;

  function U32: Cardinal;
  begin
    Need(4);
    Result := Buf[Pos] or (Cardinal(Buf[Pos + 1]) shl 8) or (Cardinal(Buf[Pos + 2]) shl 16) or (Cardinal(Buf[Pos + 3]) shl 24);
    Inc(Pos, 4);
  end;

  function I32: Int32;
  begin
    Result := Int32(U32);
  end;

  function U16: Word;
  begin
    Need(2);
    Result := Buf[Pos] or (Word(Buf[Pos + 1]) shl 8);
    Inc(Pos, 2);
  end;

  function I16: SmallInt;
  begin
    Result := SmallInt(U16);
  end;

  function U8: Byte;
  begin
    Need(1);
    Result := Buf[Pos];
    Inc(Pos);
  end;

  procedure Decompress;
  var
    Src: TMemoryStream;
    Z: TDecompressionStream;
    Chunk: array [0..65535] of Byte;
    Got: Integer;
    Out: TMemoryStream;
  begin
    Src := TMemoryStream.Create;
    Out := TMemoryStream.Create;
    try
      Src.WriteBuffer((Data + 4)^, Size - 4);
      Src.Position := 0;
      Z := TDecompressionStream.Create(Src);
      try
        repeat
          Got := Z.Read(Chunk, SizeOf(Chunk));
          if Got > 0 then Out.WriteBuffer(Chunk, Got);
        until Got <= 0;
      finally
        FreeAndNil(Z);
      end;
      BufSize := Out.Size;
      SetLength(Buf, BufSize);
      if BufSize > 0 then Move(Out.Memory^, Buf[0], BufSize);
    finally
      FreeAndNil(Src);
      FreeAndNil(Out);
    end;
  end;

  function MapVertex(const V: Cardinal): Integer;
  begin
    { Seg vertex numbers: original VERTEXES first, then the new ones. We keep
      all original vertices (linedefs use them) and append new ones after. }
    if V < OrgVerts then
      Result := V
    else
      Result := Base + (V - OrgVerts);
    if (Result < 0) or (Result > High(Vertices)) then Result := 0;
  end;

begin
  FNodesFormat := Format;
  Compressed := Format[1] = 'Z';
  GL := Copy(Format, 2, 2) = 'GL';
  LongLines := (Format = 'XGL2') or (Format = 'ZGL2') or (Format = 'XGL3') or (Format = 'ZGL3');
  FixedNodes := (Format = 'XGL3') or (Format = 'ZGL3');
  if Compressed then
    Decompress
  else
  begin
    BufSize := Size - 4;
    SetLength(Buf, BufSize);
    if BufSize > 0 then Move((Data + 4)^, Buf[0], BufSize);
  end;
  Pos := 0;

  { Vertices }
  OrgVerts := U32;
  { UDMF's ZNODES made for another TEXTMAP: build new nodes instead. }
  if FUdmf and (OrgVerts <> Length(Vertices)) then
  begin
    FNodesStale := true;
    Exit;
  end;
  NewVerts := U32;
  Base := Length(Vertices);
  SetLength(Vertices, Base + NewVerts);
  for I := 0 to NewVerts - 1 do
  begin
    Vertices[Base + I].X := I32 / 65536;
    Vertices[Base + I].Y := I32 / 65536;
  end;

  { Subsectors: only counts; first seg is the running total. }
  NumSubs := U32;
  SetLength(Subsectors, NumSubs);
  First := 0;
  for I := 0 to NumSubs - 1 do
  begin
    Subsectors[I].SegCount := U32;
    Subsectors[I].FirstSeg := First;
    Subsectors[I].Sector := -1;
    First := First + Subsectors[I].SegCount;
  end;

  { Segs }
  NumSegs := U32;
  SetLength(Segs, NumSegs);
  for I := 0 to NumSegs - 1 do
  begin
    Segs[I].V1 := MapVertex(U32);
    if GL then
      U32 { partner seg, unused }
    else
      Segs[I].V2 := MapVertex(U32);
    if LongLines then
    begin
      C := U32;
      if C = $FFFFFFFF then LineIndex := -1 else LineIndex := C;
    end else
    begin
      C := U16;
      if C = $FFFF then LineIndex := -1 else LineIndex := C;
    end;
    if (LineIndex < 0) or (LineIndex > High(Linedefs)) then
      Segs[I].Linedef := -1
    else
      Segs[I].Linedef := LineIndex;
    Segs[I].Side := U8;
    if Segs[I].Side <> 0 then Segs[I].Side := 1;
    Segs[I].Angle := 0;
    Segs[I].Offset := 0;
  end;
  { GL segs: each ends where the next one (around its subsector) begins. }
  if GL then
    for I := 0 to NumSubs - 1 do
      for K := 0 to Subsectors[I].SegCount - 1 do
      begin
        VIndex := Subsectors[I].FirstSeg + K;
        if VIndex > High(Segs) then Break;
        if K = Subsectors[I].SegCount - 1 then
          Segs[VIndex].V2 := Segs[Subsectors[I].FirstSeg].V1
        else if VIndex + 1 <= High(Segs) then
          Segs[VIndex].V2 := Segs[VIndex + 1].V1;
      end;

  { Nodes }
  NumNodes := U32;
  SetLength(Nodes, NumNodes);
  for I := 0 to NumNodes - 1 do
  begin
    if FixedNodes then
    begin
      Nodes[I].X := I32 / 65536;
      Nodes[I].Y := I32 / 65536;
      Nodes[I].DX := I32 / 65536;
      Nodes[I].DY := I32 / 65536;
    end else
    begin
      Nodes[I].X := I16;
      Nodes[I].Y := I16;
      Nodes[I].DX := I16;
      Nodes[I].DY := I16;
    end;
    for K := 0 to 7 do I16; { bounding boxes, unused }
    for K := 0 to 1 do
    begin
      C := U32;
      if (C and $80000000) <> 0 then
        Nodes[I].Children[K] := Integer(C and $3FFFFFFF) or NodeSubsector
      else
        Nodes[I].Children[K] := Integer(C and $3FFFFFFF);
    end;
  end;
  WritelnLog('Map', '%s: %s nodes, %d new vertices, %d segs, %d subsectors, %d nodes', [
    FName, Format, NewVerts, NumSegs, NumSubs, NumNodes]);
end;

{ glBSP GL nodes (glbsp.sourceforge.net/specs.php): a GL_<map> marker
  (GL_LEVEL with the name inside for names over 5 letters) followed by

    GL_VERT  V1: int16 x, y.  V2, V3: "gNd2" + fixed x, y.  V5: "gNd5" + fixed.
    GL_SEGS  V1, V2: uint16 v1, v2, line (FFFF = miniseg), side, partner;
                     v bit 15 = GL vertex.
             V3: "gNd3" + uint32 v1, v2, uint16 line, side, uint32 partner;
                 v bit 30 = GL vertex.
             V5: as V3 without the header, v bit 31 = GL vertex.
    GL_SSECT V1, V2: uint16 count, first.  V3: "gNd3" + uint32.  V5: uint32.
    GL_NODES V1-V3: as NODES (uint16 children, bit 15 subsector).
             V5: int16 x, y, dx, dy, bbox[8], uint32 children (bit 31).

  GL vertices are appended after VERTEXES. The lumps may also come from a
  .gwa file loaded with -file. }
function TDoomMap.LoadGlNodes: Boolean;
var
  Marker, I, L, Version, N, Base, K, SegSize, Skip: Integer;
  Lumps: array [0..3] of Integer;
  P: PByte;
  Size: Integer;
  GlFlag, C: Cardinal;
  Magic: String;
const
  GlNames: array [0..3] of String = ('GL_VERT', 'GL_SEGS', 'GL_SSECT', 'GL_NODES');

  function MagicOf(const Lump: Integer): String;
  var
    Q: PByte;
  begin
    Result := '';
    if FWad.LumpSize(Lump) < 4 then Exit;
    Q := FWad.LumpPointer(Lump);
    Result := Chr(Q[0]) + Chr(Q[1]) + Chr(Q[2]) + Chr(Q[3]);
  end;

  function MapVertex(const V: Cardinal): Integer;
  begin
    if (V and GlFlag) <> 0 then
      Result := Base + Integer(V and not GlFlag)
    else
      Result := Integer(V);
    if (Result < 0) or (Result > High(Vertices)) then Result := 0;
  end;

  function ToChild(const C: Cardinal; const SubBit: Cardinal): Integer;
  begin
    if (C and SubBit) <> 0 then
      Result := Integer(C and not SubBit) or NodeSubsector
    else
      Result := Integer(C);
  end;

begin
  Result := false;
  if Length(FName) <= 5 then
    Marker := FWad.FindLump('GL_' + FName)
  else
    Marker := -1; { GL_LEVEL markers would need their text lump; rare }
  if Marker < 0 then Exit;
  for K := 0 to 3 do
  begin
    Lumps[K] := -1;
    for I := Marker + 1 to Min(Marker + 6, FWad.LumpCount - 1) do
      if FWad.LumpName(I) = GlNames[K] then
      begin
        Lumps[K] := I;
        Break;
      end;
    if Lumps[K] < 0 then
      raise Exception.CreateFmt('Map %s: GL_%s has no %s lump', [FName, FName, GlNames[K]]);
  end;

  { Version from the magics. }
  Magic := MagicOf(Lumps[0]);
  if Magic = 'gNd5' then Version := 5
  else if MagicOf(Lumps[1]) = 'gNd3' then Version := 3
  else if Magic = 'gNd2' then Version := 2
  else if (Magic = 'gNd4') then
    raise Exception.CreateFmt('Map %s: glBSP GL nodes version 4 are not supported', [FName])
  else Version := 1;
  FNodesFormat := 'GL_V' + IntToStr(Version);

  { GL_VERT }
  P := FWad.LumpPointer(Lumps[0]);
  Size := FWad.LumpSize(Lumps[0]);
  Base := Length(Vertices);
  if Version = 1 then
  begin
    N := Size div 4;
    SetLength(Vertices, Base + N);
    for I := 0 to N - 1 do
    begin
      Vertices[Base + I].X := PInt16(P + I * 4)^;
      Vertices[Base + I].Y := PInt16(P + I * 4 + 2)^;
    end;
  end else
  begin
    N := (Size - 4) div 8;
    SetLength(Vertices, Base + N);
    for I := 0 to N - 1 do
    begin
      Vertices[Base + I].X := PInt32(P + 4 + I * 8)^ / 65536;
      Vertices[Base + I].Y := PInt32(P + 4 + I * 8 + 4)^ / 65536;
    end;
  end;

  { GL_SEGS }
  P := FWad.LumpPointer(Lumps[1]);
  Size := FWad.LumpSize(Lumps[1]);
  if Version <= 2 then
  begin
    SegSize := 10; Skip := 0; GlFlag := $8000;
  end else
  begin
    SegSize := 16; GlFlag := $80000000;
    if Version = 3 then
    begin
      Skip := 4; GlFlag := $40000000;
    end else
      Skip := 0;
  end;
  N := (Size - Skip) div SegSize;
  SetLength(Segs, N);
  for I := 0 to N - 1 do
  begin
    if SegSize = 10 then
    begin
      Segs[I].V1 := MapVertex(PUInt16(P + Skip + I * 10)^);
      Segs[I].V2 := MapVertex(PUInt16(P + Skip + I * 10 + 2)^);
      L := PUInt16(P + Skip + I * 10 + 4)^;
      Segs[I].Side := PUInt16(P + Skip + I * 10 + 6)^;
    end else
    begin
      Segs[I].V1 := MapVertex(PUInt32(P + Skip + I * 16)^);
      Segs[I].V2 := MapVertex(PUInt32(P + Skip + I * 16 + 4)^);
      L := PUInt16(P + Skip + I * 16 + 8)^;
      Segs[I].Side := PUInt16(P + Skip + I * 16 + 10)^;
    end;
    if (L = $FFFF) or (L > High(Linedefs)) then
      Segs[I].Linedef := -1
    else
      Segs[I].Linedef := L;
    if Segs[I].Side <> 0 then Segs[I].Side := 1;
    Segs[I].Angle := 0;
    Segs[I].Offset := 0;
  end;

  { GL_SSECT }
  P := FWad.LumpPointer(Lumps[2]);
  Size := FWad.LumpSize(Lumps[2]);
  if Version <= 2 then
  begin
    N := Size div 4;
    SetLength(Subsectors, N);
    for I := 0 to N - 1 do
    begin
      Subsectors[I].SegCount := PUInt16(P + I * 4)^;
      Subsectors[I].FirstSeg := PUInt16(P + I * 4 + 2)^;
      Subsectors[I].Sector := -1;
    end;
  end else
  begin
    if Version = 3 then Skip := 4 else Skip := 0;
    N := (Size - Skip) div 8;
    SetLength(Subsectors, N);
    for I := 0 to N - 1 do
    begin
      Subsectors[I].SegCount := PUInt32(P + Skip + I * 8)^;
      Subsectors[I].FirstSeg := PUInt32(P + Skip + I * 8 + 4)^;
      Subsectors[I].Sector := -1;
    end;
  end;

  { GL_NODES }
  P := FWad.LumpPointer(Lumps[3]);
  Size := FWad.LumpSize(Lumps[3]);
  if Version = 5 then
  begin
    N := Size div 32;
    SetLength(Nodes, N);
    for I := 0 to N - 1 do
    begin
      Nodes[I].X := PInt16(P + I * 32)^;
      Nodes[I].Y := PInt16(P + I * 32 + 2)^;
      Nodes[I].DX := PInt16(P + I * 32 + 4)^;
      Nodes[I].DY := PInt16(P + I * 32 + 6)^;
      for K := 0 to 1 do
      begin
        C := PUInt32(P + I * 32 + 24 + K * 4)^;
        Nodes[I].Children[K] := ToChild(C, $80000000);
      end;
    end;
  end else
  begin
    N := Size div 28;
    SetLength(Nodes, N);
    for I := 0 to N - 1 do
    begin
      Nodes[I].X := PInt16(P + I * 28)^;
      Nodes[I].Y := PInt16(P + I * 28 + 2)^;
      Nodes[I].DX := PInt16(P + I * 28 + 4)^;
      Nodes[I].DY := PInt16(P + I * 28 + 6)^;
      for K := 0 to 1 do
        Nodes[I].Children[K] := ToChild(PUInt16(P + I * 28 + 24 + K * 2)^, $8000);
    end;
  end;
  WritelnLog('Map', '%s: glBSP GL nodes V%d, %d GL vertices, %d segs, %d subsectors, %d nodes', [
    FName, Version, Length(Vertices) - Base, Length(Segs), Length(Subsectors), Length(Nodes)]);
  Result := true;
end;

function TDoomMap.SideSector(const LineIndex, SideIndex: Integer): Integer;
var
  S: Integer;
begin
  if (LineIndex < 0) or (LineIndex > High(Linedefs)) then Exit(-1);
  S := Linedefs[LineIndex].Side[SideIndex];
  if S < 0 then Exit(-1);
  Result := Sidedefs[S].Sector;
end;

const
  LineGridCell = 128;

{ Sorts A[0 .. Count - 1] ascending: insertion sort for the usual few
  dozen lines, a quicksort pass above that. }
procedure SortLines(var A: TLineList; const L, R: Integer);
var
  I, J, P, T: Integer;
begin
  if R - L < 24 then
  begin
    for I := L + 1 to R do
    begin
      T := A[I];
      J := I - 1;
      while (J >= L) and (A[J] > T) do
      begin
        A[J + 1] := A[J];
        Dec(J);
      end;
      A[J + 1] := T;
    end;
    Exit;
  end;
  P := A[(L + R) div 2];
  I := L;
  J := R;
  repeat
    while A[I] < P do Inc(I);
    while A[J] > P do Dec(J);
    if I <= J then
    begin
      T := A[I]; A[I] := A[J]; A[J] := T;
      Inc(I);
      Dec(J);
    end;
  until I > J;
  if L < J then SortLines(A, L, J);
  if I < R then SortLines(A, I, R);
end;

procedure TDoomMap.BuildLineGrid;
var
  GX0, GY0, GX1, GY1: Single;
  Counts: array of Integer;
  Pass, I, Row, Col, C: Integer;
  V1, V2: TDoomVertex;
  CX0, CY0, CX1, CY1, S0, S1, S2, S3: Single;
begin
  FGridW := 0;
  FGridH := 0;
  SetLength(FLineMark, Length(Linedefs));
  FMarkStamp := 0;
  if (Length(Linedefs) = 0) or (Length(Vertices) = 0) then Exit;
  GX0 := Vertices[0].X; GX1 := GX0;
  GY0 := Vertices[0].Y; GY1 := GY0;
  for I := 1 to High(Vertices) do
  begin
    GX0 := Min(GX0, Vertices[I].X); GX1 := Max(GX1, Vertices[I].X);
    GY0 := Min(GY0, Vertices[I].Y); GY1 := Max(GY1, Vertices[I].Y);
  end;
  FGridX := GX0 - 1;
  FGridY := GY0 - 1;
  FGridW := Trunc((GX1 + 1 - FGridX) / LineGridCell) + 1;
  FGridH := Trunc((GY1 + 1 - FGridY) / LineGridCell) + 1;
  SetLength(Counts, FGridW * FGridH);
  SetLength(FCellStart, FGridW * FGridH + 1);
  { Pass 0 counts the lines per cell, pass 1 stores them (in line order,
    so every cell's list is ascending). A line goes into the cells of its
    bounding box that it crosses (a cell widened by a unit on each side:
    all four corners on one side of the line = it misses). }
  for Pass := 0 to 1 do
  begin
    if Pass = 1 then
    begin
      FCellStart[0] := 0;
      for C := 0 to High(Counts) do
        FCellStart[C + 1] := FCellStart[C] + Counts[C];
      SetLength(FCellLines, FCellStart[High(FCellStart)]);
      for C := 0 to High(Counts) do
        Counts[C] := FCellStart[C];
    end;
    for I := 0 to High(Linedefs) do
    begin
      V1 := Vertices[Linedefs[I].V1];
      V2 := Vertices[Linedefs[I].V2];
      for Row := Trunc((Min(V1.Y, V2.Y) - FGridY) / LineGridCell) to
                 Trunc((Max(V1.Y, V2.Y) - FGridY) / LineGridCell) do
        for Col := Trunc((Min(V1.X, V2.X) - FGridX) / LineGridCell) to
                   Trunc((Max(V1.X, V2.X) - FGridX) / LineGridCell) do
        begin
          CX0 := FGridX + Col * LineGridCell - 1;
          CY0 := FGridY + Row * LineGridCell - 1;
          CX1 := CX0 + LineGridCell + 2;
          CY1 := CY0 + LineGridCell + 2;
          S0 := (CX0 - V1.X) * (V2.Y - V1.Y) - (CY0 - V1.Y) * (V2.X - V1.X);
          S1 := (CX1 - V1.X) * (V2.Y - V1.Y) - (CY0 - V1.Y) * (V2.X - V1.X);
          S2 := (CX1 - V1.X) * (V2.Y - V1.Y) - (CY1 - V1.Y) * (V2.X - V1.X);
          S3 := (CX0 - V1.X) * (V2.Y - V1.Y) - (CY1 - V1.Y) * (V2.X - V1.X);
          if ((S0 > 0) and (S1 > 0) and (S2 > 0) and (S3 > 0)) or
             ((S0 < 0) and (S1 < 0) and (S2 < 0) and (S3 < 0)) then Continue;
          C := Row * FGridW + Col;
          if Pass = 1 then FCellLines[Counts[C]] := I;
          Inc(Counts[C]);
        end;
    end;
  end;
end;

procedure TDoomMap.NextMark;
begin
  Inc(FMarkStamp);
  if FMarkStamp = 0 then
  begin
    { Wrapped around after 4 billion queries: clear the old marks. }
    FillChar(FLineMark[0], Length(FLineMark) * SizeOf(Cardinal), 0);
    FMarkStamp := 1;
  end;
end;

procedure TDoomMap.AddCellRow(const Row, Col0, Col1: Integer; var Found: TLineList; var Count: Integer);
var
  Col, C, K, Line: Integer;
begin
  for Col := Max(Col0, 0) to Min(Col1, FGridW - 1) do
  begin
    C := Row * FGridW + Col;
    for K := FCellStart[C] to FCellStart[C + 1] - 1 do
    begin
      Line := FCellLines[K];
      if FLineMark[Line] = FMarkStamp then Continue;
      FLineMark[Line] := FMarkStamp;
      if Count = Length(Found) then
        SetLength(Found, Count * 2 + 64);
      Found[Count] := Line;
      Inc(Count);
    end;
  end;
end;

function TDoomMap.LinesInBox(const X1, Y1, X2, Y2: Single; var Found: TLineList): Integer;
var
  Row: Integer;
begin
  Result := 0;
  if FGridW = 0 then Exit;
  NextMark;
  { Clamped to the grid (Trunc of a far-away float could overflow). }
  for Row := Max(0, Floor(Max(-1, (Min(Y1, Y2) - FGridY) / LineGridCell))) to
             Min(FGridH - 1, Floor(Min(FGridH, (Max(Y1, Y2) - FGridY) / LineGridCell))) do
    AddCellRow(Row, Floor(Max(-1, (Min(X1, X2) - FGridX) / LineGridCell)),
      Floor(Min(FGridW, (Max(X1, X2) - FGridX) / LineGridCell)), Found, Result);
  if Result > 1 then SortLines(Found, 0, Result - 1);
end;

function TDoomMap.LinesNearSegment(const X1, Y1, X2, Y2, Pad: Single; var Found: TLineList): Integer;
var
  Row: Integer;
  DX, DY, YLo, YHi, TA, TB, XA, XB, Tmp: Single;
begin
  Result := 0;
  if FGridW = 0 then Exit;
  NextMark;
  DX := X2 - X1;
  DY := Y2 - Y1;
  { Row by row: the part of the segment inside the row's band (widened
    by Pad) gives the columns, so a long diagonal sight line visits only
    the cells along it. }
  for Row := Max(0, Floor(Max(-1, (Min(Y1, Y2) - Pad - FGridY) / LineGridCell))) to
             Min(FGridH - 1, Floor(Min(FGridH, (Max(Y1, Y2) + Pad - FGridY) / LineGridCell))) do
  begin
    if Abs(DY) < 1e-6 then
    begin
      XA := Min(X1, X2);
      XB := Max(X1, X2);
    end else
    begin
      YLo := FGridY + Row * LineGridCell - Pad;
      YHi := YLo + LineGridCell + 2 * Pad;
      TA := (YLo - Y1) / DY;
      TB := (YHi - Y1) / DY;
      if TA > TB then
      begin
        Tmp := TA; TA := TB; TB := Tmp;
      end;
      TA := Max(TA, 0);
      TB := Min(TB, 1);
      if TA > TB then Continue;
      XA := X1 + DX * TA;
      XB := X1 + DX * TB;
      if XA > XB then
      begin
        Tmp := XA; XA := XB; XB := Tmp;
      end;
    end;
    AddCellRow(Row, Floor(Max(-1, (XA - Pad - FGridX) / LineGridCell)),
      Floor(Min(FGridW, (XB + Pad - FGridX) / LineGridCell)), Found, Result);
  end;
  if Result > 1 then SortLines(Found, 0, Result - 1);
end;

function TDoomMap.TranslucencyMapAlpha(const Lump: Integer): Single;
var
  Map: TBytes;
  Weights: array of Single;
  Fg, Bg, N, I, K: Integer;
  F, B, O: TVector4Byte;
  DotFB, LenFB: Single;
begin
  { tranmap[fg * 256 + bg] is the mix of a foreground and a background
    colour: the weight w of the foreground in out = w * fg + (1 - w) * bg,
    projected on fg - bg for pairs far enough apart, and the median of
    them (nearest-colour rounding makes each one rough). }
  Result := 0.66;
  Map := FWad.LumpBytes(Lump);
  if Length(Map) <> 65536 then Exit;
  SetLength(Weights, 0);
  N := 0;
  Fg := 0;
  while Fg < 256 do
  begin
    Bg := 3;
    while Bg < 256 do
    begin
      F := FWad.PaletteColor(Fg);
      B := FWad.PaletteColor(Bg);
      O := FWad.PaletteColor(Map[Fg * 256 + Bg]);
      LenFB := Sqr(F.X - B.X) + Sqr(F.Y - B.Y) + Sqr(F.Z - B.Z);
      if LenFB > 100 * 100 then
      begin
        DotFB := (O.X - B.X) * (F.X - B.X) + (O.Y - B.Y) * (F.Y - B.Y) + (O.Z - B.Z) * (F.Z - B.Z);
        if N = Length(Weights) then SetLength(Weights, N * 2 + 64);
        Weights[N] := DotFB / LenFB;
        Inc(N);
      end;
      Inc(Bg, 7);
    end;
    Inc(Fg, 5);
  end;
  if N = 0 then Exit;
  { Insertion sort of a few thousand values, then the middle one. }
  for I := 1 to N - 1 do
  begin
    DotFB := Weights[I];
    K := I - 1;
    while (K >= 0) and (Weights[K] > DotFB) do
    begin
      Weights[K + 1] := Weights[K];
      Dec(K);
    end;
    Weights[K + 1] := DotFB;
  end;
  Result := Min(1, Max(0, Weights[N div 2]));
end;

procedure TDoomMap.BuildTransfers;
var
  I, S, Front, SkySectors, Covered, Best, BestLine: Integer;
begin
  SetLength(FloorLightSector, Length(Sectors));
  SetLength(CeilingLightSector, Length(Sectors));
  for I := 0 to High(Sectors) do
  begin
    FloorLightSector[I] := -1;
    CeilingLightSector[I] := -1;
  end;
  LightTransfers := 0;
  HeightTransfers := 0;
  SetLength(HeightSec, Length(Sectors));
  SetLength(WaterColormaps, Length(Sectors));
  for I := 0 to High(Sectors) do
  begin
    HeightSec[I] := -1;
    WaterColormaps[I][0] := '';
    WaterColormaps[I][1] := '';
    WaterColormaps[I][2] := '';
  end;
  SkyTransferTexture := '';
  SkyTransferFlipped := false;
  SetLength(SectorSky, Length(Sectors));
  SetLength(SectorSkyFlipped, Length(Sectors));
  for I := 0 to High(Sectors) do
  begin
    SectorSky[I] := '';
    SectorSkyFlipped[I] := false;
  end;
  SkySectors := 0;
  for I := 0 to High(Sectors) do
    if HasSkyCeiling(I) then Inc(SkySectors);
  Best := 0;
  BestLine := -1;
  for I := 0 to High(Linedefs) do
  begin
    Front := Linedefs[I].FrontSector;
    case Linedefs[I].Special of
      213, 261:
        if Front >= 0 then
        begin
          Inc(LightTransfers);
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            if Linedefs[I].Special = 213 then
              FloorLightSector[S] := Front
            else
              CeilingLightSector[S] := Front;
          until false;
        end;
      242:
        if (Front >= 0) and (Linedefs[I].Side[0] >= 0) then
        begin
          Inc(HeightTransfers);
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            { The control sector itself is never transferred. }
            if S = Front then Continue;
            HeightSec[S] := Front;
            WaterColormaps[S][0] := ColormapName(Sidedefs[Linedefs[I].Side[0]].LowerTex);
            WaterColormaps[S][1] := ColormapName(Sidedefs[Linedefs[I].Side[0]].MiddleTex);
            WaterColormaps[S][2] := ColormapName(Sidedefs[Linedefs[I].Side[0]].UpperTex);
          until false;
        end;
      271, 272:
        begin
          Covered := 0;
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            if HasSkyCeiling(S) then
            begin
              Inc(Covered);
              if Linedefs[I].Side[0] >= 0 then
              begin
                SectorSky[S] := UpperCase(Sidedefs[Linedefs[I].Side[0]].UpperTex);
                SectorSkyFlipped[S] := Linedefs[I].Special = 272;
              end;
            end;
          until false;
          if Covered > Best then
          begin
            Best := Covered;
            BestLine := I;
          end;
        end;
    end;
  end;
  if BestLine >= 0 then
  begin
    if (Best * 2 > SkySectors) and (Linedefs[BestLine].Side[0] >= 0) then
    begin
      SkyTransferTexture := UpperCase(Sidedefs[Linedefs[BestLine].Side[0]].UpperTex);
      SkyTransferFlipped := Linedefs[BestLine].Special = 272;
      WritelnLog('Map', '%s: sky transfer: line %d gives %s%s to %d of %d sky sectors', [FName, BestLine,
        SkyTransferTexture, BoolToStr(SkyTransferFlipped, ' (mirrored)', ''), Best, SkySectors]);
    end else
      WritelnLog('Map', '%s: sky transfer of line %d covers only %d of %d sky sectors: the map''s sky stays the main one',
        [FName, BestLine, Best, SkySectors]);
  end;
  if LightTransfers > 0 then
    WritelnLog('Map', '%s: %d light transfer lines', [FName, LightTransfers]);
  if HeightTransfers > 0 then
  begin
    Covered := 0;
    for I := 0 to High(Sectors) do
      if HeightSec[I] >= 0 then Inc(Covered);
    WritelnLog('Map', '%s: %d deep water lines for %d sectors', [FName, HeightTransfers, Covered]);
  end;
end;

function TDoomMap.ColormapName(const TexName: String): String;
var
  N: String;
  L, CStart, CEnd: Integer;
begin
  { A colormap is 34 rows of 256 bytes (at least 33: Boom's own maps). }
  N := UpperCase(Trim(TexName));
  Result := '';
  if (N = '') or (N = '-') then Exit;
  L := FWad.FindLump(N);
  if L < 0 then Exit;
  { Boom's colormaps sit between C_START and C_END; elsewhere only a lump
    of exactly a colormap's size counts (wall patches have other sizes). }
  CStart := FWad.FindLump('C_START');
  CEnd := FWad.FindLump('C_END');
  if ((CStart >= 0) and (CEnd > CStart) and (L > CStart) and (L < CEnd)) or
     (FWad.LumpSize(L) = 33 * 256) or (FWad.LumpSize(L) = 34 * 256) then
    Result := N;
end;

procedure TDoomMap.BuildTranslucency;
var
  I, J, Lump, Side: Integer;
  DefaultAlpha, Alpha: Single;
  TexName: String;
begin
  SetLength(LineAlpha, Length(Linedefs));
  for I := 0 to High(LineAlpha) do
    LineAlpha[I] := 1;
  TranslucentLines := 0;
  DefaultAlpha := -1;
  for I := 0 to High(Linedefs) do
  begin
    if Linedefs[I].Special <> 260 then Continue;
    Alpha := -1;
    { P_LoadSideDefs2: a middle texture naming a 64 KB lump is that
      line's map (and not drawn). }
    Side := Linedefs[I].Side[0];
    if Side >= 0 then
    begin
      TexName := UpperCase(Sidedefs[Side].MiddleTex);
      Lump := -1;
      if (TexName <> '') and (TexName <> '-') then Lump := FWad.FindLump(TexName);
      if (Lump >= 0) and (FWad.LumpSize(Lump) = 65536) then
      begin
        Alpha := TranslucencyMapAlpha(Lump);
        for J := 0 to 1 do
          if Linedefs[I].Side[J] >= 0 then
            Sidedefs[Linedefs[I].Side[J]].MiddleTex := '-';
      end;
    end;
    if Alpha < 0 then
    begin
      if DefaultAlpha < 0 then
      begin
        Lump := FWad.FindLump('TRANMAP');
        if (Lump >= 0) and (FWad.LumpSize(Lump) = 65536) then
          DefaultAlpha := TranslucencyMapAlpha(Lump)
        else
          DefaultAlpha := 0.66; { Boom's tran_filter_pct }
      end;
      Alpha := DefaultAlpha;
    end;
    if Linedefs[I].Tag = 0 then
      LineAlpha[I] := Alpha
    else
      for J := 0 to High(Linedefs) do
        if Linedefs[J].Tag = Linedefs[I].Tag then
          LineAlpha[J] := Alpha;
  end;
  { UDMF's "alpha" and TranslucentLine. }
  for I := 0 to Min(High(FUdmfAlpha), High(LineAlpha)) do
    if FUdmfAlpha[I] < LineAlpha[I] then
      LineAlpha[I] := FUdmfAlpha[I];
  for I := 0 to High(LineAlpha) do
    if LineAlpha[I] < 1 then Inc(TranslucentLines);
  if TranslucentLines > 0 then
    WritelnLog('Map', '%s: %d translucent lines', [FName, TranslucentLines]);
end;

procedure TDoomMap.BuildFrictionAndPushers;
const
  DoomFriction = $E800 / $10000;
var
  I, S, T, FrictionLines, N: Integer;
  Len, F, MF, DX, DY: Single;
  Kind: TPusherKind;
begin
  SetLength(Friction, Length(Sectors));
  SetLength(MoveFactor, Length(Sectors));
  for I := 0 to High(Sectors) do
  begin
    Friction[I] := DoomFriction;
    MoveFactor[I] := 1;
  end;
  SetLength(Pushers, 0);
  FrictionLines := 0;
  for I := 0 to High(Linedefs) do
  begin
    DX := Vertices[Linedefs[I].V2].X - Vertices[Linedefs[I].V1].X;
    DY := Vertices[Linedefs[I].V2].Y - Vertices[Linedefs[I].V1].Y;
    case Linedefs[I].Special of
      223:
        begin
          { The longer the line, the slipperier: 0xD000 (mud) up to 1. }
          Len := Sqrt(Sqr(DX) + Sqr(DY));
          F := ($1EB8 * Len / $80 + $D000) / $10000;
          F := Min(1, Max(0, F));
          { Boom's movefactor (in 1/2048ths of Doom's thrust). }
          if F > DoomFriction then
            MF := ($10092 - F * $10000) * $70 / $158
          else
            MF := (F * $10000 - $DB34) * $A / $80;
          MF := Max(32, MF) / 2048;
          Inc(FrictionLines);
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            Friction[S] := F;
            MoveFactor[S] := MF;
          until false;
        end;
      224, 225:
        begin
          if Linedefs[I].Special = 224 then Kind := pkWind else Kind := pkCurrent;
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            N := Length(Pushers);
            SetLength(Pushers, N + 1);
            Pushers[N] := Default(TDoomPusher);
            Pushers[N].Kind := Kind;
            Pushers[N].Sector := S;
            { PUSH_FACTOR: 128 units of line = 1 unit a tic. }
            Pushers[N].X := DX / 128;
            Pushers[N].Y := DY / 128;
          until false;
        end;
      226:
        { The first push (5001) or pull (5002) thing in each tagged sector. }
        begin
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            for T := 0 to High(Things) do
              if ((Things[T].TypeNum = 5001) or (Things[T].TypeNum = 5002)) and (SectorAt(Things[T].X, Things[T].Y) = S) then
              begin
                N := Length(Pushers);
                SetLength(Pushers, N + 1);
                Pushers[N] := Default(TDoomPusher);
                if Things[T].TypeNum = 5001 then Pushers[N].Kind := pkPush else Pushers[N].Kind := pkPull;
                Pushers[N].Sector := S;
                Pushers[N].SourceX := Things[T].X;
                Pushers[N].SourceY := Things[T].Y;
                Pushers[N].Strength := Sqrt(Sqr(DX) + Sqr(DY));
                Pushers[N].Radius := 2 * Pushers[N].Strength;
                Break;
              end;
          until false;
        end;
    end;
  end;
  if FrictionLines + Length(Pushers) > 0 then
    WritelnLog('Map', '%s: %d friction lines, %d pushers', [FName, FrictionLines, Length(Pushers)]);
end;

function TDoomMap.DynScrollerSummary: String;
var
  I, Displacement, Accelerative: Integer;
begin
  Displacement := 0;
  Accelerative := 0;
  for I := 0 to High(DynScrollers) do
    if DynScrollers[I].Control >= 0 then
      if DynScrollers[I].Accel then Inc(Accelerative) else Inc(Displacement);
  if Displacement + Accelerative = 0 then
    Result := ''
  else
    Result := Format(' (%d displacement, %d accelerative)', [Displacement, Accelerative]);
end;

procedure TDoomMap.BuildScrollers;
const
  { Boom's CARRYFACTOR (0x3000 / 0x10000): with Doom's friction a thing
    then drifts at twice the floor's scroll speed. }
  CarryFactor = 0.1875;
var
  I, J, S, Special, Control: Integer;
  Accel: Boolean;
  DX, DY, LX, LY, Len: Single;
  V: TVector2;

  { A scroller of Target Index at Rate: constant (Control < 0) into the
    tables, else a runtime one. }
  procedure Add(const Target: TScrollTarget; const Index: Integer; const Rate: TVector2);
  var
    D: TDynScroller;
  begin
    if Index < 0 then Exit;
    if Control < 0 then
    begin
      case Target of
        stSide: if Index <= High(SideScroll) then SideScroll[Index] := SideScroll[Index] + Rate;
        stFloor: FloorScroll[Index] := FloorScroll[Index] + Rate;
        stCeiling: CeilingScroll[Index] := CeilingScroll[Index] + Rate;
        stCarry: Carry[Index] := Carry[Index] + Rate;
      end;
      Exit;
    end;
    if (Target = stSide) and (Index > High(SideScroll)) then Exit;
    D.Target := Target;
    D.Index := Index;
    D.Rate := Rate;
    D.Control := Control;
    D.Accel := Accel;
    D.LastHeight := Sectors[Control].FloorHeight + Sectors[Control].CeilingHeight;
    D.Velocity := TVector2.Zero;
    SetLength(DynScrollers, Length(DynScrollers) + 1);
    DynScrollers[High(DynScrollers)] := D;
    case Target of
      stSide: SideDynamic[Index] := true;
      stFloor: FloorDynamic[Index] := true;
      stCeiling: CeilingDynamic[Index] := true;
      else ;
    end;
  end;

  procedure AddSide(const Side: Integer; const Rate: TVector2);
  begin
    Add(stSide, Side, Rate);
  end;

  { A surface moved by a runtime scroller keeps its constant speed as
    one more runtime scroller (its offset is drawn from the tables). }
  procedure MoveConstant(const Target: TScrollTarget; const Index: Integer; var Rate: TVector2);
  begin
    if Rate.IsPerfectlyZero then Exit;
    SetLength(DynScrollers, Length(DynScrollers) + 1);
    DynScrollers[High(DynScrollers)].Target := Target;
    DynScrollers[High(DynScrollers)].Index := Index;
    DynScrollers[High(DynScrollers)].Rate := Rate;
    DynScrollers[High(DynScrollers)].Control := -1;
    DynScrollers[High(DynScrollers)].Accel := false;
    DynScrollers[High(DynScrollers)].LastHeight := 0;
    DynScrollers[High(DynScrollers)].Velocity := TVector2.Zero;
    Rate := TVector2.Zero;
  end;

begin
  SetLength(SideScroll, Length(Sidedefs));
  SetLength(FloorScroll, Length(Sectors));
  SetLength(CeilingScroll, Length(Sectors));
  SetLength(Carry, Length(Sectors));
  SetLength(DynScrollers, 0);
  SetLength(SideDynamic, Length(Sidedefs));
  SetLength(FloorDynamic, Length(Sectors));
  SetLength(CeilingDynamic, Length(Sectors));
  SetLength(SideOffset, Length(Sidedefs));
  SetLength(FloorOffset, Length(Sectors));
  SetLength(CeilingOffset, Length(Sectors));
  SetLength(CarryNow, Length(Sectors));
  for I := 0 to High(Linedefs) do
  begin
    { The line's vector, 32 units = 1 unit a tic (SCROLL_SHIFT). }
    DX := (Vertices[Linedefs[I].V2].X - Vertices[Linedefs[I].V1].X) / 32;
    DY := (Vertices[Linedefs[I].V2].Y - Vertices[Linedefs[I].V1].Y) / 32;
    { 245-249 (displacement) and 214-218 (accelerative) are 250-254
      driven by the height changes of the line's front sector. }
    Special := Linedefs[I].Special;
    Control := -1;
    Accel := false;
    if (Special >= 245) and (Special <= 249) then
      Special := Special + 5
    else if (Special >= 214) and (Special <= 218) then
    begin
      Special := Special + 36;
      Accel := true;
    end;
    if (Special <> Linedefs[I].Special) and (Linedefs[I].Side[0] >= 0) then
      Control := Sidedefs[Linedefs[I].Side[0]].Sector;
    if (Special <> Linedefs[I].Special) and ((Control < 0) or (Control > High(Sectors))) then
      Continue;
    case Special of
      48: AddSide(Linedefs[I].Side[0], Vector2(1, 0));
      UdmfScrollWall:
        AddSide(Linedefs[I].Side[0], Vector2(Linedefs[I].Args[0] / 64, Linedefs[I].Args[1] / 64));
      85: AddSide(Linedefs[I].Side[0], Vector2(-1, 0));
      250, 251, 252, 253:
        begin
          S := -1;
          repeat
            S := FindSectorFromTag(Linedefs[I].Tag, S);
            if S < 0 then Break;
            case Special of
              250: Add(stCeiling, S, Vector2(DX, DY));
              251: Add(stFloor, S, Vector2(DX, DY));
              252: Add(stCarry, S, Vector2(DX, DY) * CarryFactor);
              else
                begin
                  Add(stFloor, S, Vector2(DX, DY));
                  Add(stCarry, S, Vector2(DX, DY) * CarryFactor);
                end;
            end;
          until false;
        end;
      254:
        { Add_WallScroller: the tagged walls move like the floor would,
          projected on each wall's own direction. }
        for J := 0 to High(Linedefs) do
          if (J <> I) and (Linedefs[J].Tag = Linedefs[I].Tag) and (Linedefs[I].Tag <> 0) then
          begin
            LX := Vertices[Linedefs[J].V2].X - Vertices[Linedefs[J].V1].X;
            LY := Vertices[Linedefs[J].V2].Y - Vertices[Linedefs[J].V1].Y;
            Len := Sqrt(Sqr(LX) + Sqr(LY));
            if Len = 0 then Continue;
            V.X := -(DY * LY + DX * LX) / Len;
            V.Y := -(DX * LY - DY * LX) / Len;
            AddSide(Linedefs[J].Side[0], V);
          end;
      255:
        { The front side's own offsets give the speed. }
        if Linedefs[I].Side[0] >= 0 then
          AddSide(Linedefs[I].Side[0], Vector2(-Sidedefs[Linedefs[I].Side[0]].XOffset,
            Sidedefs[Linedefs[I].Side[0]].YOffset));
    end;
  end;
  for I := 0 to High(SideScroll) do
    if SideDynamic[I] then MoveConstant(stSide, I, SideScroll[I]);
  for I := 0 to High(Sectors) do
  begin
    if FloorDynamic[I] then MoveConstant(stFloor, I, FloorScroll[I]);
    if CeilingDynamic[I] then MoveConstant(stCeiling, I, CeilingScroll[I]);
  end;
  ScrollingSides := 0;
  for I := 0 to High(SideScroll) do
    if not SideScroll[I].IsPerfectlyZero then Inc(ScrollingSides);
  ScrollingFloors := 0;
  ScrollingCeilings := 0;
  CarryingFloors := 0;
  for I := 0 to High(Sectors) do
  begin
    if not FloorScroll[I].IsPerfectlyZero then Inc(ScrollingFloors);
    if not CeilingScroll[I].IsPerfectlyZero then Inc(ScrollingCeilings);
    if not Carry[I].IsPerfectlyZero then Inc(CarryingFloors);
  end;
  for I := 0 to High(DynScrollers) do
    case DynScrollers[I].Target of
      stSide: if DynScrollers[I].Control >= 0 then Inc(ScrollingSides);
      stFloor: if DynScrollers[I].Control >= 0 then Inc(ScrollingFloors);
      stCeiling: if DynScrollers[I].Control >= 0 then Inc(ScrollingCeilings);
      stCarry: Inc(CarryingFloors);
    end;
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

  { Total floor area and polygon count: a format-independent checksum used to
    compare vanilla and ZDoom node formats of the same map. }
  procedure LogPolygonStats;
  var
    I, J, N, Count: Integer;
    Area, A: Double;
  begin
    Area := 0;
    Count := 0;
    for I := 0 to High(Subsectors) do
    begin
      N := Length(Subsectors[I].Poly);
      if N < 3 then Continue;
      Inc(Count);
      A := 0;
      for J := 0 to N - 1 do
        A := A + Subsectors[I].Poly[J].X * Subsectors[I].Poly[(J + 1) mod N].Y -
          Subsectors[I].Poly[(J + 1) mod N].X * Subsectors[I].Poly[J].Y;
      Area := Area + A / 2;
    end;
    WritelnLog('Map', '%s: %s nodes, %d subsector polygons, total area %.0f', [FName, FNodesFormat, Count, Area]);
  end;

  procedure Walk(const Child: Integer; const Poly: TPolyD);
  var
    Sub, J, Seg: Integer;
    P: TPolyD;
    V1, V2: TDoomVertex;
    Node: TDoomNode;
    Area: Double;
  begin
    if Length(Poly) < 3 then Exit;
    if (Child and NodeSubsector) <> 0 then
    begin
      Sub := Child and NodeIndexMask;
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
      Walk(NodeSubsector, Start);
    Exit;
  end;
  { Counter-clockwise bounding rectangle, in Doom (X, Y). }
  SetLength(Start, 4);
  Start[0] := Vector2Double(MinX - Margin, MinY - Margin);
  Start[1] := Vector2Double(MaxX + Margin, MinY - Margin);
  Start[2] := Vector2Double(MaxX + Margin, MaxY + Margin);
  Start[3] := Vector2Double(MinX - Margin, MaxY + Margin);
  Walk(High(Nodes), Start);
  LogPolygonStats;
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
  while (Child and NodeSubsector) = 0 do
  begin
    if Child > High(Nodes) then Exit(0);
    Child := Nodes[Child].Children[PointOnNodeSide(X, Y, Child)];
    Inc(Guard);
    if Guard > 100000 then Exit(0);
  end;
  Result := Child and NodeIndexMask;
  if Result > High(Subsectors) then Result := 0;
end;

function TDoomMap.RejectBlocks(const S1, S2: Integer): Boolean;
var
  Bit: Integer;
begin
  Result := false;
  if (Length(Reject) = 0) or (S1 < 0) or (S2 < 0) then Exit;
  Bit := S1 * Length(Sectors) + S2;
  if (Bit shr 3) >= Length(Reject) then Exit;
  Result := (Reject[Bit shr 3] and (1 shl (Bit and 7))) <> 0;
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

function TDoomMap.NextLowestFloor(const Sec: Integer; const CurrentHeight: Single): Single;
var
  L, O: Integer;
  Found: Boolean;
begin
  Result := CurrentHeight;
  Found := false;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].FloorHeight < CurrentHeight) then
      if (not Found) or (Sectors[O].FloorHeight > Result) then
      begin
        Result := Sectors[O].FloorHeight;
        Found := true;
      end;
  end;
end;

function TDoomMap.NextLowestCeiling(const Sec: Integer; const CurrentHeight: Single): Single;
var
  L, O: Integer;
  Found: Boolean;
begin
  Result := CurrentHeight;
  Found := false;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].CeilingHeight < CurrentHeight) then
      if (not Found) or (Sectors[O].CeilingHeight > Result) then
      begin
        Result := Sectors[O].CeilingHeight;
        Found := true;
      end;
  end;
end;

function TDoomMap.NextHighestCeiling(const Sec: Integer; const CurrentHeight: Single): Single;
var
  L, O: Integer;
  Found: Boolean;
begin
  Result := CurrentHeight;
  Found := false;
  for L in Sectors[Sec].Lines do
  begin
    O := OtherSector(L, Sec);
    if (O >= 0) and (Sectors[O].CeilingHeight > CurrentHeight) then
      if (not Found) or (Sectors[O].CeilingHeight < Result) then
      begin
        Result := Sectors[O].CeilingHeight;
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

function TDoomMap.HasSkyFloor(const Sec: Integer): Boolean;
begin
  Result := (Sec >= 0) and (Sectors[Sec].FloorTex = 'F_SKY1');
end;

end.
