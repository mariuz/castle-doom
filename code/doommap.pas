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
    { Partition line; fractional for ZDoom XGL3 nodes. }
    X, Y, DX, DY: Single;
    { Child codes: NodeSubsector bit set = subsector index, else node index.
      (Normalized from vanilla's bit 15 and ZDoom's bit 31.) }
    Children: array [0..1] of Integer;
  end;

  TDoomMap = class
  strict private
    FWad: TDoomWad;
    FName: String;
    FNodesFormat: String;
    procedure LoadLumps(const MarkerIndex: Integer);
    procedure LoadVanillaNodes(const NodesLump, SegsLump, SubsLump: Integer);
    procedure LoadExtendedNodes(const Data: PByte; const Size: Integer; const Format: String);
    procedure BuildSectorLists;
    procedure BuildSubsectorPolygons;
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

    property Name: String read FName;
    property Wad: TDoomWad read FWad;
    { VANILLA, XNOD, ZNOD, XGLN, ZGLN, XGL2, ZGL2, XGL3 or ZGL3. }
    property NodesFormat: String read FNodesFormat;
  end;

const
  { Child code flag for subsectors in TDoomNode.Children. }
  NodeSubsector = $40000000;
  NodeIndexMask = $3FFFFFFF;

implementation

uses Math, ZStream, CastleLog, CastleUtils;

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
        raise Exception.CreateFmt('Map %s has no BSP nodes; build it with a node builder (ZDBSP, ZokumBSP...)', [FName]);
      LoadVanillaNodes(NodesL, SegsL, SubsL);
    end;
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

function TDoomMap.SideSector(const LineIndex, SideIndex: Integer): Integer;
var
  S: Integer;
begin
  if (LineIndex < 0) or (LineIndex > High(Linedefs)) then Exit(-1);
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
