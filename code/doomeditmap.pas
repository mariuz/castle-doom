{ The map editor's data: a Doom map as plain editable lists of vertices,
  linedefs, sidedefs, sectors and things (whole Doom units, the WAD's own
  numbers), with the operations of a 2D map editor and undo, read from a
  map of any loaded WAD (the IWAD's or a PWAD's: import) and written back
  as a PWAD holding just that map, with its BSP built by DoomNodeBuilder,
  an empty REJECT and a real BLOCKMAP, so other Doom ports play it too
  (export). Engine independent: GameViewEdit draws and drives it, the
  play-test loads its PWAD through the edit:/MAP URL (EditedWadUrl). }
unit DoomEditMap;

interface

uses SysUtils, Classes,
  DoomWad;

type
  TEditVertex = record
    X, Y: Integer;
  end;

  TEditLine = record
    V1, V2: Integer;
    Flags, Special, Tag: Integer;
    { Sidedefs, -1 when absent: [0] front (right of V1 -> V2), [1] back. }
    Side: array [0..1] of Integer;
  end;

  TEditSide = record
    XOffset, YOffset: Integer;
    Upper, Lower, Middle: String;
    Sector: Integer;
  end;

  TEditSector = record
    Floor, Ceiling: Integer;
    FloorTex, CeilingTex: String;
    Light, Special, Tag: Integer;
  end;

  TEditThing = record
    X, Y, Angle, TypeNum, Flags: Integer;
  end;

  TEditPoint = record
    X, Y: Integer;
  end;
  TEditPoints = array of TEditPoint;

  TEditHitKind = (ehNone, ehWall, ehFloor, ehCeiling);
  { What a ray from the eye meets first (RayHit): a wall part, a floor
    or a ceiling, and where. }
  TEditRayHit = record
    Kind: TEditHitKind;
    { ehWall: the line, the side facing the eye (0 front, 1 back) and its
      part ('U' upper, 'M' middle, 'L' lower). }
    Line, Side: Integer;
    Part: Char;
    { ehFloor / ehCeiling: the sector. }
    Sector: Integer;
    X, Y, Z: Single;
  end;

  TEditVertexArray = array of TEditVertex;
  TEditLineArray = array of TEditLine;
  TEditSideArray = array of TEditSide;
  TEditSectorArray = array of TEditSector;
  TEditThingArray = array of TEditThing;

  TDoomEditMap = class
  strict private
    type
      TState = record
        Vertices: TEditVertexArray;
        Lines: TEditLineArray;
        Sides: TEditSideArray;
        Sectors: TEditSectorArray;
        Things: TEditThingArray;
      end;
    var
      FUndo, FRedo: array of TState;
      FModified: Boolean;
      FGroup: Integer;
      FGroupTaken: Boolean;
    function Capture: TState;
    procedure Restore(const S: TState);
    function AddSide(const Sector: Integer; const Upper, Lower, Middle: String): Integer;
    function FindVertex(const X, Y: Integer): Integer;
    function VertexAt(const X, Y: Integer): Integer;
    function FindLine(const V1, V2: Integer): Integer;
    procedure DeleteLine(const L: Integer);
    procedure DeleteVertex(const V: Integer);
    procedure PushUndo(const S: TState);
    function OnLineInside(const X, Y, L: Integer): Boolean;
    procedure SplitLineAtPoint(const L, X, Y: Integer);
    procedure AddVerticesOnEdge(const A, B: TEditPoint; var Q: TEditPoints);
    procedure MakeOneSided(const L: Integer);
    procedure FlipLine(const L: Integer);
  public
    { The map lump name (E1M1, MAP01...). }
    Name: String;
    Vertices: TEditVertexArray;
    Lines: TEditLineArray;
    Sides: TEditSideArray;
    Sectors: TEditSectorArray;
    Things: TEditThingArray;
    { Used by new rooms when the map has nothing to copy. }
    DefaultWall, DefaultFloor, DefaultCeiling: String;
    constructor Create;
    { An empty map named AName. }
    procedure Clear(const AName: String);
    { Read a map of the loaded WADs (the last one with that name). False
      with Error for a missing map or one in the Hexen or UDMF format. }
    function LoadFromWad(const Wad: TDoomWad; const MapName: String; out Error: String): Boolean;
    { The map's lumps after its marker (THINGS ... BLOCKMAP, nodes built),
      added to Names / Data (TMemoryStream each, the caller frees them). }
    procedure WriteLumps(const Names: TStrings; const Data: TList);
    { A PWAD holding this map alone. }
    function SaveToWad: TMemoryStream;
    { The bounding box of the vertices and things. }
    procedure Bounds(out X1, Y1, X2, Y2: Integer);
    function Summary: String;

    { Queries (Doom coordinates; -1 when nothing is close enough). }
    function NearestVertex(const X, Y, MaxDistance: Single): Integer;
    function NearestLine(const X, Y, MaxDistance: Single): Integer;
    function NearestThing(const X, Y, MaxDistance: Single): Integer;
    { The first wall part, floor or ceiling a ray from (OX, OY, OZ) along
      (DX, DY, DZ) meets (Doom coordinates; the 3D preview's click).
      False when it starts outside the map or meets nothing. }
    function RayHit(const OX, OY, OZ, DX, DY, DZ: Single; out Hit: TEditRayHit): Boolean;
    { The sector (X, Y) is in, -1 outside the map. }
    function SectorAt(const X, Y: Single): Integer;
    { The sector of line L's side Side, -1 when that side is missing. }
    function LineSector(const L, Side: Integer): Integer;
    { The vertices of sector Sec's lines, of line L, of anything. }
    function SectorVertices(const Sec: Integer): TEditPoints;
    function MostCommonWall: String;

    { Edits. Each first remembers the map for Undo (Snapshot). }
    procedure Snapshot;
    { Edits between BeginChange and EndChange are one undo step (the
      editor's change of every selected sector...). }
    procedure BeginChange;
    procedure EndChange;
    function Undo: Boolean;
    function Redo: Boolean;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Move vertex V; one dropped onto another vertex merges with it (the
      lines that become zero length go). }
    procedure MoveVertex(const V, X, Y: Integer);
    { Vertex V on another vertex's place merges with it (the lines that
      become zero length go; no Snapshot: the editor's drag took one).
      True when it merged. }
    function MergeVertex(const V: Integer): Boolean;
    { Move vertices (indices) by (DX, DY), all at once. }
    procedure MoveVertices(const Indices: array of Integer; const DX, DY: Integer);
    procedure MoveThing(const T, X, Y: Integer);
    function AddThing(const X, Y, TypeNum, Angle: Integer): Integer;
    procedure DeleteThing(const T: Integer);
    { Split line L at the point of it nearest to (X, Y): a new vertex and
      a second line with copies of its sides. The new vertex, -1 when the
      point is an end of the line. }
    function SplitLine(const L, X, Y: Integer): Integer;
    { A new sector from a polygon (3 or more points, either winding): in
      an existing sector (two-sided walls, its heights and flats) or in
      the void (one-sided walls), where edges on existing one-sided lines
      (both ends on their vertices) join the room to the map; corners
      on a line split it, and an edge along a line of the sector the
      room is in gives that line's side to the room. The new sector, -1
      with Error (and the map as before) when the polygon crosses lines,
      contains vertices, spans two sectors or is not simple. }
    function DrawSector(const Points: TEditPoints; out Error: String): Integer;
    { Doom Builder's "make door": the sector's ceiling down to its floor,
      its two-sided lines a DR door (special 1) facing outwards with DOOR3
      above. False when it has no two-sided lines. }
    function MakeDoor(const Sec: Integer): Boolean;
    { Delete lines; their sides and the vertices left alone go too. }
    procedure DeleteLines(const Indices: array of Integer);
    { Delete a sector: its own lines go, a line it shares with another
      sector becomes that sector's wall (one-sided, facing it, its upper or
      lower texture as the wall). }
    procedure DeleteSector(const Sec: Integer);
    { Delete a vertex: its two lines become one when it joins exactly two
      lines going on the same way (True), else it goes with its lines. }
    function DissolveVertex(const V: Integer): Boolean;
    { Cut a sector in two along a path (2 or more points) from one of its
      walls to another, through the sector: the part on the path's right
      becomes a new sector (returned) with the old one's heights and
      flats. Ends on a line's middle split it. -1 with Error (and the map
      as before) when the path leaves the sector, crosses lines or does not
      cut it in two. }
    function SplitSector(const Path: TEditPoints; out Error: String): Integer;
    { Drop the sides no line uses and the vertices no line uses. }
    procedure Compact;
    { Turn two-sided lines around: their ends and sides swap, so the
      other sector is in front (what a special's "front" means). A
      one-sided line has only its front and stays. The number flipped. }
    function FlipLines(const Indices: array of Integer): Integer;
    { The outer boundary of sector Sec (its biggest loop of walls; holes
      left out), the corners in order with the sector on the right
      (clockwise); empty when its walls make no loop. }
    function SectorOutline(const Sec: Integer): TEditPoints;
    { (X, Y) is a vertex or on a line (where a cut may end). }
    function OnWall(const X, Y: Integer): Boolean;
    { Change sector heights and light, keeping the ceiling above the
      floor and the light in 0..255. }
    procedure ChangeSector(const Sec, DFloor, DCeiling, DLight: Integer);
    property Modified: Boolean read FModified write FModified;
  end;

const
  EditedUrlPrefix = 'edit:/';

{ The play-test URL of the editor's map MapName (TDoomWad.AddFile reads
  its PWAD from RegisterEditedWad). }
function EditedWadUrl(const MapName: String): String;
function IsEditedWadUrl(const Url: String; out MapName: String): Boolean;
{ Keep a copy of Data as the PWAD of edit:/MapName. }
procedure RegisterEditedWad(const MapName: String; const Data: TStream);
{ The PWAD registered for edit:/MapName (a new stream), nil when none. }
function EditedWadData(const MapName: String): TMemoryStream;

implementation

uses Math, DoomNodeBuilder, DoomWadWriter;

const
  ML_BLOCKING = 1;
  ML_TWOSIDED = 4;
  MaxUndo = 100;

{ Registry -------------------------------------------------------------------- }

var
  EditedNames: TStringList;

function EditedWadUrl(const MapName: String): String;
begin
  Result := EditedUrlPrefix + UpperCase(MapName);
end;

function IsEditedWadUrl(const Url: String; out MapName: String): Boolean;
begin
  Result := SameText(Copy(Url, 1, Length(EditedUrlPrefix)), EditedUrlPrefix);
  if Result then
    MapName := UpperCase(Copy(Url, Length(EditedUrlPrefix) + 1, MaxInt))
  else
    MapName := '';
end;

procedure RegisterEditedWad(const MapName: String; const Data: TStream);
var
  I: Integer;
  Copied: TMemoryStream;
begin
  Copied := TMemoryStream.Create;
  Copied.CopyFrom(Data, 0);
  Copied.Position := 0;
  I := EditedNames.IndexOf(UpperCase(MapName));
  if I >= 0 then
  begin
    EditedNames.Objects[I].Free;
    EditedNames.Objects[I] := Copied;
  end else
    EditedNames.AddObject(UpperCase(MapName), Copied);
end;

function EditedWadData(const MapName: String): TMemoryStream;
var
  I: Integer;
begin
  Result := nil;
  I := EditedNames.IndexOf(UpperCase(MapName));
  if I < 0 then Exit;
  Result := TMemoryStream.Create;
  Result.CopyFrom(TMemoryStream(EditedNames.Objects[I]), 0);
  Result.Position := 0;
end;

{ Geometry helpers ------------------------------------------------------------ }

function Cross(const AX, AY, BX, BY, CX, CY: Double): Double;
begin
  Result := (BX - AX) * (CY - AY) - (BY - AY) * (CX - AX);
end;

{ The point lies on segment A-B (ends included). }
function OnSegment(const PX, PY, AX, AY, BX, BY: Double): Boolean;
begin
  Result := (Abs(Cross(AX, AY, BX, BY, PX, PY)) < 1e-6) and
    (PX >= Min(AX, BX) - 1e-6) and (PX <= Max(AX, BX) + 1e-6) and
    (PY >= Min(AY, BY) - 1e-6) and (PY <= Max(AY, BY) + 1e-6);
end;

{ Segments A-B and C-D share a point. }
function SegmentsTouch(const AX, AY, BX, BY, CX, CY, DX, DY: Double): Boolean;
var
  D1, D2, D3, D4: Double;
begin
  D1 := Cross(CX, CY, DX, DY, AX, AY);
  D2 := Cross(CX, CY, DX, DY, BX, BY);
  D3 := Cross(AX, AY, BX, BY, CX, CY);
  D4 := Cross(AX, AY, BX, BY, DX, DY);
  if (((D1 > 0) and (D2 < 0)) or ((D1 < 0) and (D2 > 0))) and
     (((D3 > 0) and (D4 < 0)) or ((D3 < 0) and (D4 > 0))) then
    Exit(true);
  Result := OnSegment(AX, AY, CX, CY, DX, DY) or OnSegment(BX, BY, CX, CY, DX, DY) or
    OnSegment(CX, CY, AX, AY, BX, BY) or OnSegment(DX, DY, AX, AY, BX, BY);
end;

function SamePoint(const AX, AY, BX, BY: Double): Boolean;
begin
  Result := (Abs(AX - BX) < 1e-6) and (Abs(AY - BY) < 1e-6);
end;

function PointInPolygon(const X, Y: Double; const P: TEditPoints): Boolean;
var
  I, J: Integer;
begin
  Result := false;
  J := High(P);
  for I := 0 to High(P) do
  begin
    if ((P[I].Y > Y) <> (P[J].Y > Y)) and
       (X < P[J].X + (Y - P[J].Y) * (P[I].X - P[J].X) / (P[I].Y - P[J].Y)) then
      Result := not Result;
    J := I;
  end;
end;

function SignedArea(const P: TEditPoints): Double;
var
  I, J: Integer;
begin
  Result := 0;
  J := High(P);
  for I := 0 to High(P) do
  begin
    Result := Result + P[J].X * Double(P[I].Y) - P[I].X * Double(P[J].Y);
    J := I;
  end;
  Result := Result / 2;
end;

function SegmentDistance(const PX, PY, AX, AY, BX, BY: Double): Double;
var
  DX, DY, T, L2: Double;
begin
  DX := BX - AX;
  DY := BY - AY;
  L2 := DX * DX + DY * DY;
  if L2 = 0 then T := 0 else T := EnsureRange(((PX - AX) * DX + (PY - AY) * DY) / L2, 0, 1);
  Result := Sqrt(Sqr(AX + T * DX - PX) + Sqr(AY + T * DY - PY));
end;

{ TDoomEditMap ----------------------------------------------------------------- }

constructor TDoomEditMap.Create;
begin
  inherited;
  DefaultWall := 'STARTAN3';
  DefaultFloor := 'FLOOR4_8';
  DefaultCeiling := 'CEIL3_5';
end;

procedure TDoomEditMap.Clear(const AName: String);
begin
  Name := UpperCase(AName);
  Vertices := nil;
  Lines := nil;
  Sides := nil;
  Sectors := nil;
  Things := nil;
  FUndo := nil;
  FRedo := nil;
  FModified := false;
end;

function TDoomEditMap.LoadFromWad(const Wad: TDoomWad; const MapName: String; out Error: String): Boolean;
var
  Marker: Integer;
  Lumps: TStringList;
  I, N, L: Integer;
  P: PByte;
  Used: array of Integer;

  function Lump(const LumpName: String): Integer;
  var
    J: Integer;
  begin
    J := Lumps.IndexOf(LumpName);
    if J < 0 then Result := -1 else Result := PtrInt(Lumps.Objects[J]);
  end;

begin
  Result := false;
  Error := '';
  Marker := Wad.FindLump(UpperCase(MapName));
  if Marker < 0 then
  begin
    Error := Format('Map %s not found', [UpperCase(MapName)]);
    Exit;
  end;
  Lumps := TStringList.Create;
  try
    for I := Marker + 1 to Min(Marker + 12, Wad.LumpCount - 1) do
    begin
      if Wad.MapNames.IndexOf(Wad.LumpName(I)) >= 0 then Break;
      if Lumps.IndexOf(Wad.LumpName(I)) < 0 then
        Lumps.AddObject(Wad.LumpName(I), TObject(PtrInt(I)));
    end;
    if Lump('TEXTMAP') >= 0 then
    begin
      Error := Format('%s is a UDMF map, which the editor cannot read', [UpperCase(MapName)]);
      Exit;
    end;
    if Lump('BEHAVIOR') >= 0 then
    begin
      Error := Format('%s is a Hexen-format map, which the editor cannot read', [UpperCase(MapName)]);
      Exit;
    end;
    if (Lump('VERTEXES') < 0) or (Lump('LINEDEFS') < 0) or (Lump('SIDEDEFS') < 0) or
       (Lump('SECTORS') < 0) or (Lump('THINGS') < 0) then
    begin
      Error := Format('%s lacks map lumps', [UpperCase(MapName)]);
      Exit;
    end;
    Clear(MapName);

    L := Lump('VERTEXES');
    P := Wad.LumpPointer(L);
    N := Wad.LumpSize(L) div 4;
    SetLength(Vertices, N);
    for I := 0 to N - 1 do
    begin
      Vertices[I].X := PInt16(P + I * 4)^;
      Vertices[I].Y := PInt16(P + I * 4 + 2)^;
    end;

    L := Lump('SECTORS');
    P := Wad.LumpPointer(L);
    N := Wad.LumpSize(L) div 26;
    SetLength(Sectors, N);
    for I := 0 to N - 1 do
    begin
      Sectors[I].Floor := PInt16(P + I * 26)^;
      Sectors[I].Ceiling := PInt16(P + I * 26 + 2)^;
      Sectors[I].FloorTex := DoomName(P + I * 26 + 4);
      Sectors[I].CeilingTex := DoomName(P + I * 26 + 12);
      Sectors[I].Light := PInt16(P + I * 26 + 20)^;
      Sectors[I].Special := PInt16(P + I * 26 + 22)^;
      Sectors[I].Tag := PInt16(P + I * 26 + 24)^;
    end;

    L := Lump('SIDEDEFS');
    P := Wad.LumpPointer(L);
    N := Wad.LumpSize(L) div 30;
    SetLength(Sides, N);
    for I := 0 to N - 1 do
    begin
      Sides[I].XOffset := PInt16(P + I * 30)^;
      Sides[I].YOffset := PInt16(P + I * 30 + 2)^;
      Sides[I].Upper := DoomName(P + I * 30 + 4);
      Sides[I].Lower := DoomName(P + I * 30 + 12);
      Sides[I].Middle := DoomName(P + I * 30 + 20);
      Sides[I].Sector := PUInt16(P + I * 30 + 28)^;
      if Sides[I].Sector >= Length(Sectors) then Sides[I].Sector := 0;
    end;

    L := Lump('LINEDEFS');
    P := Wad.LumpPointer(L);
    N := Wad.LumpSize(L) div 14;
    SetLength(Lines, N);
    for I := 0 to N - 1 do
    begin
      Lines[I].V1 := PUInt16(P + I * 14)^;
      Lines[I].V2 := PUInt16(P + I * 14 + 2)^;
      Lines[I].Flags := PUInt16(P + I * 14 + 4)^;
      Lines[I].Special := PUInt16(P + I * 14 + 6)^;
      Lines[I].Tag := PInt16(P + I * 14 + 8)^;
      Lines[I].Side[0] := PUInt16(P + I * 14 + 10)^;
      Lines[I].Side[1] := PUInt16(P + I * 14 + 12)^;
      if Lines[I].Side[0] >= Length(Sides) then Lines[I].Side[0] := -1;
      if Lines[I].Side[1] >= Length(Sides) then Lines[I].Side[1] := -1;
      if Lines[I].V1 >= Length(Vertices) then Lines[I].V1 := 0;
      if Lines[I].V2 >= Length(Vertices) then Lines[I].V2 := 0;
    end;

    L := Lump('THINGS');
    P := Wad.LumpPointer(L);
    N := Wad.LumpSize(L) div 10;
    SetLength(Things, N);
    for I := 0 to N - 1 do
    begin
      Things[I].X := PInt16(P + I * 10)^;
      Things[I].Y := PInt16(P + I * 10 + 2)^;
      Things[I].Angle := PInt16(P + I * 10 + 4)^;
      Things[I].TypeNum := PInt16(P + I * 10 + 6)^;
      Things[I].Flags := PInt16(P + I * 10 + 8)^;
    end;
  finally
    FreeAndNil(Lumps);
  end;

  { The node builder's split points are in VERTEXES too: keep only the
    vertices of lines. }
  SetLength(Used, Length(Vertices));
  for I := 0 to High(Used) do Used[I] := -1;
  for I := 0 to High(Lines) do
  begin
    Used[Lines[I].V1] := 0;
    Used[Lines[I].V2] := 0;
  end;
  N := 0;
  for I := 0 to High(Vertices) do
    if Used[I] = 0 then
    begin
      Used[I] := N;
      Vertices[N] := Vertices[I];
      Inc(N);
    end;
  SetLength(Vertices, N);
  for I := 0 to High(Lines) do
  begin
    Lines[I].V1 := Used[Lines[I].V1];
    Lines[I].V2 := Used[Lines[I].V2];
  end;
  if MostCommonWall <> '' then DefaultWall := MostCommonWall;
  if Length(Sectors) > 0 then
  begin
    DefaultFloor := Sectors[0].FloorTex;
    DefaultCeiling := Sectors[0].CeilingTex;
  end;
  Result := true;
end;

function TDoomEditMap.MostCommonWall: String;
var
  Counts: TStringList;
  I, J, Best: Integer;
  T: String;
begin
  Result := '';
  Counts := TStringList.Create;
  try
    Counts.Sorted := true;
    for I := 0 to High(Lines) do
      if (Lines[I].Side[1] < 0) and (Lines[I].Side[0] >= 0) then
      begin
        T := Sides[Lines[I].Side[0]].Middle;
        if (T = '') or (T = '-') then Continue;
        J := Counts.IndexOf(T);
        if J < 0 then J := Counts.AddObject(T, TObject(PtrInt(0)));
        Counts.Objects[J] := TObject(PtrInt(Counts.Objects[J]) + 1);
      end;
    Best := 0;
    for I := 0 to Counts.Count - 1 do
      if PtrInt(Counts.Objects[I]) > Best then
      begin
        Best := PtrInt(Counts.Objects[I]);
        Result := Counts[I];
      end;
  finally
    FreeAndNil(Counts);
  end;
end;

procedure TDoomEditMap.WriteLumps(const Names: TStrings; const Data: TList);
var
  S: TMemoryStream;
  B: TNodeBuilder;
  NbVerts: TNbVertexArray;
  NbLines: TNbLineArray;
  SideSectors: array of Integer;
  BmLines: array of TBlockmapLine;
  I, J: Integer;

  procedure Lump(const AName: String);
  begin
    S := TMemoryStream.Create;
    Names.Add(AName);
    Data.Add(S);
  end;

  function Child(const C: Integer): Integer;
  begin
    if C >= 0 then Result := C else Result := $8000 or (-1 - C);
  end;

  procedure Box(const Bx: TNbBox);
  begin
    W16(S, Bx.Top); W16(S, Bx.Bottom); W16(S, Bx.Left); W16(S, Bx.Right);
  end;

begin
  SetLength(NbVerts, Length(Vertices));
  for I := 0 to High(Vertices) do
  begin
    NbVerts[I].X := Vertices[I].X;
    NbVerts[I].Y := Vertices[I].Y;
  end;
  SetLength(NbLines, Length(Lines));
  for I := 0 to High(Lines) do
  begin
    NbLines[I].V1 := Lines[I].V1;
    NbLines[I].V2 := Lines[I].V2;
    NbLines[I].Side[0] := Lines[I].Side[0];
    NbLines[I].Side[1] := Lines[I].Side[1];
  end;
  SetLength(SideSectors, Length(Sides));
  for I := 0 to High(Sides) do
    SideSectors[I] := Sides[I].Sector;

  B := TNodeBuilder.Create;
  try
    B.Run(NbVerts, NbLines, SideSectors);

    Lump('THINGS');
    for I := 0 to High(Things) do
    begin
      W16(S, Things[I].X); W16(S, Things[I].Y); W16(S, Things[I].Angle);
      W16(S, Things[I].TypeNum); W16(S, Things[I].Flags);
    end;
    Lump('LINEDEFS');
    for I := 0 to High(Lines) do
    begin
      W16(S, Lines[I].V1); W16(S, Lines[I].V2); W16(S, Lines[I].Flags);
      W16(S, Lines[I].Special); W16(S, Lines[I].Tag);
      if Lines[I].Side[0] >= 0 then W16(S, Lines[I].Side[0]) else W16(S, $FFFF);
      if Lines[I].Side[1] >= 0 then W16(S, Lines[I].Side[1]) else W16(S, $FFFF);
    end;
    Lump('SIDEDEFS');
    for I := 0 to High(Sides) do
    begin
      W16(S, Sides[I].XOffset); W16(S, Sides[I].YOffset);
      WName(S, Sides[I].Upper); WName(S, Sides[I].Lower); WName(S, Sides[I].Middle);
      W16(S, Sides[I].Sector);
    end;
    Lump('VERTEXES');
    for I := 0 to High(B.Vertices) do
    begin
      W16(S, B.Vertices[I].X); W16(S, B.Vertices[I].Y);
    end;
    Lump('SEGS');
    for I := 0 to High(B.Segs) do
    begin
      W16(S, B.Segs[I].V1); W16(S, B.Segs[I].V2); W16(S, B.Segs[I].Angle);
      W16(S, B.Segs[I].Line); W16(S, B.Segs[I].Side); W16(S, B.Segs[I].Offset);
    end;
    Lump('SSECTORS');
    for I := 0 to High(B.Subsectors) do
    begin
      W16(S, B.Subsectors[I].Count); W16(S, B.Subsectors[I].First);
    end;
    { Doom starts at the last node; the builder numbers a parent before
      its children (the root is 0), so they are written reversed. }
    Lump('NODES');
    for I := High(B.Nodes) downto 0 do
    begin
      W16(S, B.Nodes[I].X); W16(S, B.Nodes[I].Y); W16(S, B.Nodes[I].DX); W16(S, B.Nodes[I].DY);
      Box(B.Nodes[I].Box[0]);
      Box(B.Nodes[I].Box[1]);
      for J := 0 to 1 do
        if B.Nodes[I].Child[J] >= 0 then
          W16(S, High(B.Nodes) - B.Nodes[I].Child[J])
        else
          W16(S, Child(B.Nodes[I].Child[J]));
    end;
    Lump('SECTORS');
    for I := 0 to High(Sectors) do
    begin
      W16(S, Sectors[I].Floor); W16(S, Sectors[I].Ceiling);
      WName(S, Sectors[I].FloorTex); WName(S, Sectors[I].CeilingTex);
      W16(S, Sectors[I].Light); W16(S, Sectors[I].Special); W16(S, Sectors[I].Tag);
    end;
    Lump('REJECT');
    for I := 1 to (Length(Sectors) * Length(Sectors) + 7) div 8 do
      S.WriteByte(0);
    Lump('BLOCKMAP');
    SetLength(BmLines, Length(Lines));
    for I := 0 to High(Lines) do
    begin
      BmLines[I].X1 := Vertices[Lines[I].V1].X;
      BmLines[I].Y1 := Vertices[Lines[I].V1].Y;
      BmLines[I].X2 := Vertices[Lines[I].V2].X;
      BmLines[I].Y2 := Vertices[Lines[I].V2].Y;
    end;
    WriteBlockmap(S, BmLines);
  finally
    FreeAndNil(B);
  end;
end;

function TDoomEditMap.SaveToWad: TMemoryStream;
var
  Names: TStringList;
  Data: TList;
  I: Integer;
begin
  Names := TStringList.Create;
  Data := TList.Create;
  try
    Names.Add(Name);
    Data.Add(TMemoryStream.Create);
    WriteLumps(Names, Data);
    Result := MakePwad(Names, Data);
  finally
    for I := 0 to Data.Count - 1 do
      TObject(Data[I]).Free;
    FreeAndNil(Data);
    FreeAndNil(Names);
  end;
end;

procedure TDoomEditMap.Bounds(out X1, Y1, X2, Y2: Integer);
var
  I: Integer;
begin
  X1 := MaxInt; Y1 := MaxInt; X2 := -MaxInt; Y2 := -MaxInt;
  for I := 0 to High(Vertices) do
  begin
    X1 := Min(X1, Vertices[I].X); X2 := Max(X2, Vertices[I].X);
    Y1 := Min(Y1, Vertices[I].Y); Y2 := Max(Y2, Vertices[I].Y);
  end;
  for I := 0 to High(Things) do
  begin
    X1 := Min(X1, Things[I].X); X2 := Max(X2, Things[I].X);
    Y1 := Min(Y1, Things[I].Y); Y2 := Max(Y2, Things[I].Y);
  end;
  if X1 > X2 then
  begin
    X1 := -512; Y1 := -512; X2 := 512; Y2 := 512;
  end;
end;

function TDoomEditMap.Summary: String;
begin
  Result := Format('%s: %d vertices, %d lines, %d sides, %d sectors, %d things', [
    Name, Length(Vertices), Length(Lines), Length(Sides), Length(Sectors), Length(Things)]);
end;

{ Queries ------------------------------------------------------------------------ }

function TDoomEditMap.NearestVertex(const X, Y, MaxDistance: Single): Integer;
var
  I: Integer;
  D, Best: Single;
begin
  Result := -1;
  Best := MaxDistance;
  for I := 0 to High(Vertices) do
  begin
    D := Sqrt(Sqr(Vertices[I].X - X) + Sqr(Vertices[I].Y - Y));
    if D <= Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

function TDoomEditMap.NearestLine(const X, Y, MaxDistance: Single): Integer;
var
  I: Integer;
  D, Best: Double;
begin
  Result := -1;
  Best := MaxDistance;
  for I := 0 to High(Lines) do
  begin
    D := SegmentDistance(X, Y, Vertices[Lines[I].V1].X, Vertices[Lines[I].V1].Y,
      Vertices[Lines[I].V2].X, Vertices[Lines[I].V2].Y);
    if D <= Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

function TDoomEditMap.NearestThing(const X, Y, MaxDistance: Single): Integer;
var
  I: Integer;
  D, Best: Single;
begin
  Result := -1;
  Best := MaxDistance;
  for I := 0 to High(Things) do
  begin
    D := Sqrt(Sqr(Things[I].X - X) + Sqr(Things[I].Y - Y));
    if D <= Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

function TDoomEditMap.LineSector(const L, Side: Integer): Integer;
begin
  Result := -1;
  if (L < 0) or (L > High(Lines)) then Exit;
  if Lines[L].Side[Side] >= 0 then
    Result := Sides[Lines[L].Side[Side]].Sector;
end;

{ The nearest line crossed by a ray to the east, and which side of it the
  point is on (Doom Builder's way). }
function TDoomEditMap.RayHit(const OX, OY, OZ, DX, DY, DZ: Single; out Hit: TEditRayHit): Boolean;
var
  Ts: array of Double;
  Ls: array of Integer;
  N, I, J, L, Cur, Other, Side: Integer;
  T, TPrev, U, Den, AX, AY, BX, BY, Z, TT: Double;
  TL: Integer;

  { The floor or ceiling of Cur between TPrev and T1 (T1 < 0: no end). }
  function Flat(const T1: Double): Boolean;
  var
    TF: Double;
  begin
    Result := false;
    if Abs(DZ) < 1e-9 then Exit;
    if DZ < 0 then TF := (Sectors[Cur].Floor - OZ) / DZ else TF := (Sectors[Cur].Ceiling - OZ) / DZ;
    if (TF < TPrev) or ((T1 >= 0) and (TF > T1)) then Exit;
    if DZ < 0 then Hit.Kind := ehFloor else Hit.Kind := ehCeiling;
    Hit.Sector := Cur;
    Hit.X := OX + DX * TF;
    Hit.Y := OY + DY * TF;
    Hit.Z := OZ + DZ * TF;
    Result := true;
  end;

begin
  Hit := Default(TEditRayHit);
  Hit.Kind := ehNone;
  Hit.Line := -1;
  Hit.Sector := -1;
  Result := false;
  Cur := SectorAt(OX, OY);
  if Cur < 0 then Exit;
  { Where the ray crosses each line, in order. }
  N := 0;
  for I := 0 to High(Lines) do
  begin
    AX := Vertices[Lines[I].V1].X; AY := Vertices[Lines[I].V1].Y;
    BX := Vertices[Lines[I].V2].X; BY := Vertices[Lines[I].V2].Y;
    Den := DX * (BY - AY) - DY * (BX - AX);
    if Abs(Den) < 1e-12 then Continue;
    T := ((AX - OX) * (BY - AY) - (AY - OY) * (BX - AX)) / Den;
    U := ((AX - OX) * DY - (AY - OY) * DX) / Den;
    if (T <= 1e-6) or (U < 0) or (U > 1) then Continue;
    SetLength(Ts, N + 1);
    SetLength(Ls, N + 1);
    Ts[N] := T;
    Ls[N] := I;
    Inc(N);
  end;
  for I := 1 to N - 1 do
    for J := I downto 1 do
      if Ts[J] < Ts[J - 1] then
      begin
        TT := Ts[J]; Ts[J] := Ts[J - 1]; Ts[J - 1] := TT;
        TL := Ls[J]; Ls[J] := Ls[J - 1]; Ls[J - 1] := TL;
      end;
  TPrev := 0;
  for I := 0 to N - 1 do
  begin
    if Flat(Ts[I]) then Exit(true);
    L := Ls[I];
    if LineSector(L, 0) = Cur then
    begin
      Side := 0;
      Other := LineSector(L, 1);
    end else
    if LineSector(L, 1) = Cur then
    begin
      Side := 1;
      Other := LineSector(L, 0);
    end else
      { Through a corner, past a line of another sector: go on. }
      Continue;
    Z := OZ + DZ * Ts[I];
    Hit.Line := L;
    Hit.Side := Side;
    Hit.X := OX + DX * Ts[I];
    Hit.Y := OY + DY * Ts[I];
    Hit.Z := Z;
    Hit.Kind := ehWall;
    if Other < 0 then
    begin
      Hit.Part := 'M';
      Exit(true);
    end;
    if Z < Sectors[Other].Floor then
    begin
      Hit.Part := 'L';
      Exit(true);
    end;
    if Z > Sectors[Other].Ceiling then
    begin
      Hit.Part := 'U';
      Exit(true);
    end;
    Hit.Kind := ehNone;
    Hit.Line := -1;
    Cur := Other;
    TPrev := Ts[I];
  end;
  Result := Flat(-1);
end;

function TDoomEditMap.SectorAt(const X, Y: Single): Integer;
var
  I, Best: Integer;
  PY, BestX, IX, X1, Y1, X2, Y2, Side: Double;
begin
  Result := -1;
  { Off the integer grid, so the ray never runs through a vertex. }
  PY := Y + 0.0137;
  Best := -1;
  BestX := 1e30;
  for I := 0 to High(Lines) do
  begin
    X1 := Vertices[Lines[I].V1].X; Y1 := Vertices[Lines[I].V1].Y;
    X2 := Vertices[Lines[I].V2].X; Y2 := Vertices[Lines[I].V2].Y;
    if (Y1 > PY) = (Y2 > PY) then Continue;
    IX := X1 + (PY - Y1) * (X2 - X1) / (Y2 - Y1);
    if (IX >= X) and (IX < BestX) then
    begin
      BestX := IX;
      Best := I;
    end;
  end;
  if Best < 0 then Exit;
  X1 := Vertices[Lines[Best].V1].X; Y1 := Vertices[Lines[Best].V1].Y;
  X2 := Vertices[Lines[Best].V2].X; Y2 := Vertices[Lines[Best].V2].Y;
  Side := (X - X1) * (Y2 - Y1) - (PY - Y1) * (X2 - X1);
  if Side >= 0 then
    Result := LineSector(Best, 0)
  else
    Result := LineSector(Best, 1);
end;

function TDoomEditMap.SectorVertices(const Sec: Integer): TEditPoints;
var
  I, N: Integer;
  Seen: array of Boolean;

  procedure AddV(const V: Integer);
  begin
    if Seen[V] then Exit;
    Seen[V] := true;
    SetLength(Result, N + 1);
    Result[N].X := V;
    Result[N].Y := 0;
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  SetLength(Seen, Length(Vertices));
  for I := 0 to High(Lines) do
    if (LineSector(I, 0) = Sec) or (LineSector(I, 1) = Sec) then
    begin
      AddV(Lines[I].V1);
      AddV(Lines[I].V2);
    end;
end;

{ Undo --------------------------------------------------------------------------- }

function TDoomEditMap.Capture: TState;
begin
  Result.Vertices := Copy(Vertices);
  Result.Lines := Copy(Lines);
  Result.Sides := Copy(Sides);
  Result.Sectors := Copy(Sectors);
  Result.Things := Copy(Things);
end;

procedure TDoomEditMap.Restore(const S: TState);
begin
  Vertices := Copy(S.Vertices);
  Lines := Copy(S.Lines);
  Sides := Copy(S.Sides);
  Sectors := Copy(S.Sectors);
  Things := Copy(S.Things);
end;

procedure TDoomEditMap.Snapshot;
begin
  PushUndo(Capture);
end;

procedure TDoomEditMap.PushUndo(const S: TState);
begin
  FModified := true;
  if FGroup > 0 then
  begin
    if FGroupTaken then Exit;
    FGroupTaken := true;
  end;
  if Length(FUndo) >= MaxUndo then
    Delete(FUndo, 0, 1);
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := S;
  FRedo := nil;
end;

procedure TDoomEditMap.BeginChange;
begin
  Inc(FGroup);
  if FGroup = 1 then FGroupTaken := false;
end;

procedure TDoomEditMap.EndChange;
begin
  if FGroup > 0 then Dec(FGroup);
end;

function TDoomEditMap.CanUndo: Boolean;
begin
  Result := Length(FUndo) > 0;
end;

function TDoomEditMap.CanRedo: Boolean;
begin
  Result := Length(FRedo) > 0;
end;

function TDoomEditMap.Undo: Boolean;
begin
  Result := CanUndo;
  if not Result then Exit;
  SetLength(FRedo, Length(FRedo) + 1);
  FRedo[High(FRedo)] := Capture;
  Restore(FUndo[High(FUndo)]);
  SetLength(FUndo, Length(FUndo) - 1);
  FModified := true;
end;

function TDoomEditMap.Redo: Boolean;
begin
  Result := CanRedo;
  if not Result then Exit;
  SetLength(FUndo, Length(FUndo) + 1);
  FUndo[High(FUndo)] := Capture;
  Restore(FRedo[High(FRedo)]);
  SetLength(FRedo, Length(FRedo) - 1);
  FModified := true;
end;

{ Edits --------------------------------------------------------------------------- }

function TDoomEditMap.FindVertex(const X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Vertices) do
    if (Vertices[I].X = X) and (Vertices[I].Y = Y) then Exit(I);
  Result := -1;
end;

function TDoomEditMap.VertexAt(const X, Y: Integer): Integer;
begin
  Result := FindVertex(X, Y);
  if Result >= 0 then Exit;
  Result := Length(Vertices);
  SetLength(Vertices, Result + 1);
  Vertices[Result].X := X;
  Vertices[Result].Y := Y;
end;

function TDoomEditMap.FindLine(const V1, V2: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Lines) do
    if ((Lines[I].V1 = V1) and (Lines[I].V2 = V2)) or ((Lines[I].V1 = V2) and (Lines[I].V2 = V1)) then
      Exit(I);
  Result := -1;
end;

function TDoomEditMap.AddSide(const Sector: Integer; const Upper, Lower, Middle: String): Integer;
begin
  Result := Length(Sides);
  SetLength(Sides, Result + 1);
  Sides[Result].XOffset := 0;
  Sides[Result].YOffset := 0;
  Sides[Result].Upper := Upper;
  Sides[Result].Lower := Lower;
  Sides[Result].Middle := Middle;
  Sides[Result].Sector := Sector;
end;

function TDoomEditMap.OnWall(const X, Y: Integer): Boolean;
var
  L: Integer;
begin
  if FindVertex(X, Y) >= 0 then Exit(true);
  for L := 0 to High(Lines) do
    if OnLineInside(X, Y, L) then Exit(true);
  Result := false;
end;

procedure TDoomEditMap.Compact;
var
  SideMap, VertexMap: array of Integer;
  I, N, S: Integer;
begin
  SetLength(SideMap, Length(Sides));
  for I := 0 to High(SideMap) do SideMap[I] := -1;
  SetLength(VertexMap, Length(Vertices));
  for I := 0 to High(VertexMap) do VertexMap[I] := -1;
  for I := 0 to High(Lines) do
  begin
    for S := 0 to 1 do
      if Lines[I].Side[S] >= 0 then SideMap[Lines[I].Side[S]] := 0;
    VertexMap[Lines[I].V1] := 0;
    VertexMap[Lines[I].V2] := 0;
  end;
  N := 0;
  for I := 0 to High(Sides) do
    if SideMap[I] = 0 then
    begin
      SideMap[I] := N;
      Sides[N] := Sides[I];
      Inc(N);
    end;
  SetLength(Sides, N);
  N := 0;
  for I := 0 to High(Vertices) do
    if VertexMap[I] = 0 then
    begin
      VertexMap[I] := N;
      Vertices[N] := Vertices[I];
      Inc(N);
    end;
  SetLength(Vertices, N);
  for I := 0 to High(Lines) do
  begin
    for S := 0 to 1 do
      if Lines[I].Side[S] >= 0 then Lines[I].Side[S] := SideMap[Lines[I].Side[S]];
    Lines[I].V1 := VertexMap[Lines[I].V1];
    Lines[I].V2 := VertexMap[Lines[I].V2];
  end;
end;

procedure TDoomEditMap.DeleteLines(const Indices: array of Integer);
var
  Gone: array of Boolean;
  I, N: Integer;
begin
  Snapshot;
  SetLength(Gone, Length(Lines));
  for I := 0 to High(Indices) do
    if (Indices[I] >= 0) and (Indices[I] <= High(Gone)) then Gone[Indices[I]] := true;
  N := 0;
  for I := 0 to High(Lines) do
    if not Gone[I] then
    begin
      Lines[N] := Lines[I];
      Inc(N);
    end;
  SetLength(Lines, N);
  Compact;
end;

{ A line one-sided towards its front (the back side dropped): the wall
  shows the texture its front had above or below. }
procedure TDoomEditMap.MakeOneSided(const L: Integer);
var
  F: Integer;
  Tex: String;
begin
  Lines[L].Side[1] := -1;
  Lines[L].Flags := (Lines[L].Flags or ML_BLOCKING) and not ML_TWOSIDED;
  F := Lines[L].Side[0];
  if F < 0 then Exit;
  Tex := Sides[F].Lower;
  if (Tex = '') or (Tex = '-') then Tex := Sides[F].Upper;
  if (Tex = '') or (Tex = '-') then Tex := Sides[F].Middle;
  if (Tex = '') or (Tex = '-') then Tex := DefaultWall;
  Sides[F].Middle := Tex;
  Sides[F].Upper := '-';
  Sides[F].Lower := '-';
end;

procedure TDoomEditMap.FlipLine(const L: Integer);
var
  T: Integer;
begin
  T := Lines[L].V1; Lines[L].V1 := Lines[L].V2; Lines[L].V2 := T;
  T := Lines[L].Side[0]; Lines[L].Side[0] := Lines[L].Side[1]; Lines[L].Side[1] := T;
end;

function TDoomEditMap.FlipLines(const Indices: array of Integer): Integer;
var
  I: Integer;
  Taken: Boolean;
begin
  Result := 0;
  Taken := false;
  for I := 0 to High(Indices) do
    if (Indices[I] >= 0) and (Indices[I] <= High(Lines)) and
       (Lines[Indices[I]].Side[0] >= 0) and (Lines[Indices[I]].Side[1] >= 0) then
    begin
      if not Taken then
      begin
        Snapshot;
        Taken := true;
      end;
      FlipLine(Indices[I]);
      Inc(Result);
    end;
end;

function TDoomEditMap.SectorOutline(const Sec: Integer): TEditPoints;
var
  From, Upto: array of Integer;
  Used: array of Boolean;
  Loop: array of Integer;
  I, J, N, Start, Cur, Count: Integer;
  Area, BestArea: Double;
  Found: Boolean;
begin
  Result := nil;
  { The walls as edges with the sector on their right. }
  N := 0;
  for I := 0 to High(Lines) do
  begin
    if (LineSector(I, 0) = Sec) and (LineSector(I, 1) = Sec) then Continue;
    if LineSector(I, 0) = Sec then
    begin
      SetLength(From, N + 1); SetLength(Upto, N + 1);
      From[N] := Lines[I].V1; Upto[N] := Lines[I].V2;
      Inc(N);
    end else
    if LineSector(I, 1) = Sec then
    begin
      SetLength(From, N + 1); SetLength(Upto, N + 1);
      From[N] := Lines[I].V2; Upto[N] := Lines[I].V1;
      Inc(N);
    end;
  end;
  SetLength(Used, N);
  BestArea := 0;
  for Start := 0 to N - 1 do
  begin
    if Used[Start] then Continue;
    { Follow the edges from Start until they come back to it. }
    Loop := nil;
    Count := 0;
    Cur := Start;
    repeat
      Used[Cur] := true;
      SetLength(Loop, Count + 1);
      Loop[Count] := From[Cur];
      Inc(Count);
      if Upto[Cur] = From[Start] then Break;
      Found := false;
      for J := 0 to N - 1 do
        if (not Used[J]) and (From[J] = Upto[Cur]) then
        begin
          Cur := J;
          Found := true;
          Break;
        end;
    until not Found;
    if (Upto[Cur] <> From[Start]) or (Count < 3) then Continue;
    Area := 0;
    for I := 0 to Count - 1 do
    begin
      J := (I + 1) mod Count;
      Area := Area + Vertices[Loop[I]].X * Vertices[Loop[J]].Y - Vertices[Loop[J]].X * Vertices[Loop[I]].Y;
    end;
    if Abs(Area) > BestArea then
    begin
      BestArea := Abs(Area);
      SetLength(Result, Count);
      for I := 0 to Count - 1 do
      begin
        Result[I].X := Vertices[Loop[I]].X;
        Result[I].Y := Vertices[Loop[I]].Y;
      end;
    end;
  end;
end;

procedure TDoomEditMap.DeleteSector(const Sec: Integer);
var
  Gone: array of Boolean;
  I, N, S0, S1: Integer;
begin
  Snapshot;
  SetLength(Gone, Length(Lines));
  for I := 0 to High(Lines) do
  begin
    S0 := LineSector(I, 0);
    S1 := LineSector(I, 1);
    if (S0 <> Sec) and (S1 <> Sec) then Continue;
    if ((S0 = Sec) or (S0 < 0)) and ((S1 = Sec) or (S1 < 0)) then
      Gone[I] := true
    else
    begin
      { The other sector keeps it as a wall, in front. }
      if S0 = Sec then FlipLine(I);
      MakeOneSided(I);
    end;
  end;
  N := 0;
  for I := 0 to High(Lines) do
    if not Gone[I] then
    begin
      Lines[N] := Lines[I];
      Inc(N);
    end;
  SetLength(Lines, N);
  Compact;
  Delete(Sectors, Sec, 1);
  for I := 0 to High(Sides) do
    if Sides[I].Sector > Sec then Dec(Sides[I].Sector);
end;

function TDoomEditMap.DissolveVertex(const V: Integer): Boolean;
var
  Found: array of Integer;
  I, A, B: Integer;
begin
  Snapshot;
  Found := nil;
  for I := 0 to High(Lines) do
    if (Lines[I].V1 = V) or (Lines[I].V2 = V) then
    begin
      SetLength(Found, Length(Found) + 1);
      Found[High(Found)] := I;
    end;
  Result := false;
  if Length(Found) = 2 then
  begin
    A := Found[0];
    B := Found[1];
    { A ends at V, B starts there. }
    if Lines[A].V2 <> V then FlipLine(A);
    if Lines[B].V1 <> V then FlipLine(B);
    if (Lines[A].V1 <> Lines[B].V2) and (LineSector(A, 0) = LineSector(B, 0)) and
       (LineSector(A, 1) = LineSector(B, 1)) then
    begin
      Lines[A].V2 := Lines[B].V2;
      Delete(Lines, B, 1);
      Result := true;
    end;
  end;
  if not Result then
    for I := High(Lines) downto 0 do
      if (Lines[I].V1 = V) or (Lines[I].V2 = V) then
        Delete(Lines, I, 1);
  Compact;
end;

function TDoomEditMap.SplitSector(const Path: TEditPoints; out Error: String): Integer;
var
  P, Loop: TEditPoints;
  Before: TState;
  N, I, J, L, S, B, E, Cur, Prev, Best, Steps, Side, NewSec, K: Integer;
  X1, Y1, X2, Y2, MX, MY, NX, NY, Len, T1, T2, RX, RY, CX, CY, Ang, BestAng: Double;
  OnChain: array of Boolean;
  Pt: TEditPoint;

  function EndVertex(const Q: TEditPoint): Integer;
  var
    LL: Integer;
  begin
    Result := FindVertex(Q.X, Q.Y);
    if Result >= 0 then Exit;
    for LL := 0 to High(Lines) do
      if OnLineInside(Q.X, Q.Y, LL) then
      begin
        SplitLineAtPoint(LL, Q.X, Q.Y);
        Exit(FindVertex(Q.X, Q.Y));
      end;
  end;

  function OnBoundary(const V, Sector: Integer): Boolean;
  var
    LL: Integer;
  begin
    for LL := 0 to High(Lines) do
      if ((Lines[LL].V1 = V) or (Lines[LL].V2 = V)) and
         ((LineSector(LL, 0) = Sector) or (LineSector(LL, 1) = Sector)) then
        Exit(true);
    Result := false;
  end;

  procedure Fail(const Msg: String);
  begin
    Error := Msg;
    Restore(Before);
  end;

begin
  Result := -1;
  Error := '';
  P := nil;
  for I := 0 to High(Path) do
    if (Length(P) = 0) or (P[High(P)].X <> Path[I].X) or (P[High(P)].Y <> Path[I].Y) then
    begin
      SetLength(P, Length(P) + 1);
      P[High(P)] := Path[I];
    end;
  N := Length(P);
  if N < 2 then
  begin
    Error := 'A cut needs two points';
    Exit;
  end;
  if (P[0].X = P[N - 1].X) and (P[0].Y = P[N - 1].Y) then
  begin
    Error := 'A closed path draws a room, not a cut';
    Exit;
  end;
  { The sector: where the first segment's middle is. }
  S := SectorAt((P[0].X + P[1].X) / 2 + 0.01, (P[0].Y + P[1].Y) / 2 + 0.013);
  if S < 0 then
  begin
    Error := 'The cut must run through a sector';
    Exit;
  end;
  Before := Capture;
  B := EndVertex(P[0]);
  E := EndVertex(P[N - 1]);
  if (B < 0) or (E < 0) or not OnBoundary(B, S) or not OnBoundary(E, S) then
  begin
    Fail('The cut must start and end on the sector''s walls');
    Exit;
  end;
  { Its points between: inside the sector, off every line. }
  for I := 1 to N - 2 do
    if (FindVertex(P[I].X, P[I].Y) >= 0) or (SectorAt(P[I].X + 0.01, P[I].Y + 0.013) <> S) then
    begin
      Fail(Format('Point %d of the cut is not inside sector %d', [I + 1, S]));
      Exit;
    end;
  { Its segments: touching lines only at the cut's two ends. }
  for I := 0 to N - 2 do
  begin
    X1 := P[I].X; Y1 := P[I].Y;
    X2 := P[I + 1].X; Y2 := P[I + 1].Y;
    for L := 0 to High(Lines) do
    begin
      MX := Vertices[Lines[L].V1].X; MY := Vertices[Lines[L].V1].Y;
      NX := Vertices[Lines[L].V2].X; NY := Vertices[Lines[L].V2].Y;
      if not SegmentsTouch(X1, Y1, X2, Y2, MX, MY, NX, NY) then Continue;
      if (Abs(Cross(X1, Y1, X2, Y2, MX, MY)) < 1e-6) and (Abs(Cross(X1, Y1, X2, Y2, NX, NY)) < 1e-6) then
      begin
        Len := Sqr(X2 - X1) + Sqr(Y2 - Y1);
        T1 := ((MX - X1) * (X2 - X1) + (MY - Y1) * (Y2 - Y1)) / Len;
        T2 := ((NX - X1) * (X2 - X1) + (NY - Y1) * (Y2 - Y1)) / Len;
        if Min(1, Max(T1, T2)) - Max(0, Min(T1, T2)) > 1e-9 then
        begin
          Fail(Format('The cut runs along line %d', [L]));
          Exit;
        end;
        Continue;
      end;
      if ((I = 0) and (SamePoint(X1, Y1, MX, MY) or SamePoint(X1, Y1, NX, NY))) or
         ((I = N - 2) and (SamePoint(X2, Y2, MX, MY) or SamePoint(X2, Y2, NX, NY))) then
        Continue;
      Fail(Format('The cut crosses line %d', [L]));
      Exit;
    end;
  end;

  { The part on the cut's right: from E, follow the sector's wall with the
    sector on the right (the next wall counter-clockwise from where we came
    from) back to B. }
  Loop := Copy(P);
  SetLength(OnChain, Length(Lines));
  Cur := E;
  Prev := -1;
  RX := P[N - 2].X - P[N - 1].X;
  RY := P[N - 2].Y - P[N - 1].Y;
  Steps := 0;
  while Cur <> B do
  begin
    Inc(Steps);
    if Steps > Length(Lines) + 1 then
    begin
      Fail('The cut does not divide the sector in two');
      Exit;
    end;
    Best := -1;
    BestAng := 10;
    for L := 0 to High(Lines) do
      for Side := 0 to 1 do
      begin
        if LineSector(L, Side) <> S then Continue;
        { The wall's direction with the sector on its right. }
        if Side = 0 then
        begin
          if Lines[L].V1 <> Cur then Continue;
          J := Lines[L].V2;
        end else
        begin
          if Lines[L].V2 <> Cur then Continue;
          J := Lines[L].V1;
        end;
        if L = Prev then Continue;
        CX := Vertices[J].X - Vertices[Cur].X;
        CY := Vertices[J].Y - Vertices[Cur].Y;
        Ang := ArcTan2(RX * CY - RY * CX, RX * CX + RY * CY);
        if Ang <= 1e-9 then Ang := Ang + 2 * Pi;
        if Ang < BestAng then
        begin
          BestAng := Ang;
          Best := L * 2 + Side;
        end;
      end;
    if Best < 0 then
    begin
      Fail('The cut does not divide the sector in two');
      Exit;
    end;
    L := Best div 2;
    OnChain[L] := true;
    Prev := L;
    if Best mod 2 = 0 then J := Lines[L].V2 else J := Lines[L].V1;
    RX := Vertices[Cur].X - Vertices[J].X;
    RY := Vertices[Cur].Y - Vertices[J].Y;
    Cur := J;
    if Cur = E then
    begin
      Fail('The cut does not divide the sector in two');
      Exit;
    end;
    if Cur <> B then
    begin
      Pt.X := Vertices[Cur].X;
      Pt.Y := Vertices[Cur].Y;
      SetLength(Loop, Length(Loop) + 1);
      Loop[High(Loop)] := Pt;
    end;
  end;

  NewSec := Length(Sectors);
  SetLength(Sectors, NewSec + 1);
  Sectors[NewSec] := Sectors[S];
  Sectors[NewSec].Special := 0;
  Sectors[NewSec].Tag := 0;
  { The walls on the right part (the chain, and pillars inside the loop)
    face the new sector: copies of their sides. }
  for L := 0 to High(Lines) do
    for Side := 0 to 1 do
    begin
      if LineSector(L, Side) <> S then Continue;
      if not OnChain[L] then
      begin
        { A point just off the wall on the sector's side. }
        X1 := Vertices[Lines[L].V1].X; Y1 := Vertices[Lines[L].V1].Y;
        X2 := Vertices[Lines[L].V2].X; Y2 := Vertices[Lines[L].V2].Y;
        Len := Sqrt(Sqr(X2 - X1) + Sqr(Y2 - Y1));
        if Len = 0 then Continue;
        MX := (X1 + X2) / 2 + (Y2 - Y1) / Len * 0.5 * (1 - 2 * Side);
        MY := (Y1 + Y2) / 2 - (X2 - X1) / Len * 0.5 * (1 - 2 * Side);
        if not PointInPolygon(MX, MY, Loop) then Continue;
      end;
      K := Length(Sides);
      SetLength(Sides, K + 1);
      Sides[K] := Sides[Lines[L].Side[Side]];
      Sides[K].Sector := NewSec;
      Lines[L].Side[Side] := K;
    end;
  { The cut itself: two-sided, the new sector on its right. }
  for I := 0 to N - 2 do
  begin
    L := Length(Lines);
    SetLength(Lines, L + 1);
    Lines[L].V1 := VertexAt(P[I].X, P[I].Y);
    Lines[L].V2 := VertexAt(P[I + 1].X, P[I + 1].Y);
    Lines[L].Special := 0;
    Lines[L].Tag := 0;
    Lines[L].Flags := ML_TWOSIDED;
    Lines[L].Side[0] := AddSide(NewSec, DefaultWall, DefaultWall, '-');
    Lines[L].Side[1] := AddSide(S, DefaultWall, DefaultWall, '-');
  end;
  PushUndo(Before);
  Result := NewSec;
end;

procedure TDoomEditMap.DeleteLine(const L: Integer);
begin
  Delete(Lines, L, 1);
end;

{ Remove vertex V (no line may use it). }
procedure TDoomEditMap.DeleteVertex(const V: Integer);
var
  I: Integer;
begin
  Delete(Vertices, V, 1);
  for I := 0 to High(Lines) do
  begin
    if Lines[I].V1 > V then Dec(Lines[I].V1);
    if Lines[I].V2 > V then Dec(Lines[I].V2);
  end;
end;

procedure TDoomEditMap.MoveVertex(const V, X, Y: Integer);
begin
  Snapshot;
  Vertices[V].X := X;
  Vertices[V].Y := Y;
  MergeVertex(V);
end;

function TDoomEditMap.MergeVertex(const V: Integer): Boolean;
var
  Other, I: Integer;
begin
  Other := -1;
  for I := 0 to High(Vertices) do
    if (I <> V) and (Vertices[I].X = Vertices[V].X) and (Vertices[I].Y = Vertices[V].Y) then
    begin
      Other := I;
      Break;
    end;
  Result := Other >= 0;
  if not Result then Exit;
  for I := 0 to High(Lines) do
  begin
    if Lines[I].V1 = V then Lines[I].V1 := Other;
    if Lines[I].V2 = V then Lines[I].V2 := Other;
  end;
  for I := High(Lines) downto 0 do
    if Lines[I].V1 = Lines[I].V2 then DeleteLine(I);
  DeleteVertex(V);
end;

procedure TDoomEditMap.MoveVertices(const Indices: array of Integer; const DX, DY: Integer);
var
  I: Integer;
begin
  Snapshot;
  for I := 0 to High(Indices) do
  begin
    Inc(Vertices[Indices[I]].X, DX);
    Inc(Vertices[Indices[I]].Y, DY);
  end;
end;

procedure TDoomEditMap.MoveThing(const T, X, Y: Integer);
begin
  Snapshot;
  Things[T].X := X;
  Things[T].Y := Y;
end;

function TDoomEditMap.AddThing(const X, Y, TypeNum, Angle: Integer): Integer;
begin
  Snapshot;
  Result := Length(Things);
  SetLength(Things, Result + 1);
  Things[Result].X := X;
  Things[Result].Y := Y;
  Things[Result].TypeNum := TypeNum;
  Things[Result].Angle := Angle;
  { Every skill. }
  Things[Result].Flags := 7;
end;

procedure TDoomEditMap.DeleteThing(const T: Integer);
begin
  Snapshot;
  Delete(Things, T, 1);
end;

function TDoomEditMap.SplitLine(const L, X, Y: Integer): Integer;
var
  AX, AY, BX, BY, T, L2: Double;
  PX, PY, N, S: Integer;
begin
  Result := -1;
  AX := Vertices[Lines[L].V1].X; AY := Vertices[Lines[L].V1].Y;
  BX := Vertices[Lines[L].V2].X; BY := Vertices[Lines[L].V2].Y;
  L2 := Sqr(BX - AX) + Sqr(BY - AY);
  if L2 = 0 then Exit;
  T := EnsureRange(((X - AX) * (BX - AX) + (Y - AY) * (BY - AY)) / L2, 0, 1);
  PX := Round(AX + T * (BX - AX));
  PY := Round(AY + T * (BY - AY));
  if ((PX = AX) and (PY = AY)) or ((PX = BX) and (PY = BY)) then Exit;
  Snapshot;
  Result := VertexAt(PX, PY);
  N := Length(Lines);
  SetLength(Lines, N + 1);
  Lines[N] := Lines[L];
  Lines[N].V1 := Result;
  Lines[L].V2 := Result;
  for S := 0 to 1 do
    if Lines[L].Side[S] >= 0 then
    begin
      Lines[N].Side[S] := Length(Sides);
      SetLength(Sides, Length(Sides) + 1);
      Sides[High(Sides)] := Sides[Lines[L].Side[S]];
    end;
end;

function TDoomEditMap.DrawSector(const Points: TEditPoints; out Error: String): Integer;
var
  P: TEditPoints;
  N, I, J, K, L, Outer, Sec, NewSide, OuterSide, V1, V2, Shared, FrontSide: Integer;
  Area, MX, MY, NX, NY, Len, T1, T2: Double;
  Pt: TEditPoint;
  Q: TEditPoints;
  SharedLine, SharedSide: array of Integer;
  Before: TState;
  Wall: String;
  X1, Y1, X2, Y2: Double;
begin
  Result := -1;
  Error := '';
  { Without repeated points (the closing click on the first one). }
  P := nil;
  for I := 0 to High(Points) do
    if (Length(P) = 0) or (P[High(P)].X <> Points[I].X) or (P[High(P)].Y <> Points[I].Y) then
    begin
      SetLength(P, Length(P) + 1);
      P[High(P)] := Points[I];
    end;
  if (Length(P) > 1) and (P[0].X = P[High(P)].X) and (P[0].Y = P[High(P)].Y) then
    SetLength(P, Length(P) - 1);
  N := Length(P);
  if N < 3 then
  begin
    Error := 'A room needs at least 3 points';
    Exit;
  end;
  Area := SignedArea(P);
  if Abs(Area) < 1 then
  begin
    Error := 'The room has no area';
    Exit;
  end;
  { Clockwise, so the inside is on the right of each edge (the front). }
  if Area > 0 then
    for I := 0 to N div 2 - 1 do
    begin
      Pt := P[I];
      P[I] := P[N - 1 - I];
      P[N - 1 - I] := Pt;
    end;

  { A simple polygon: edges meet only their neighbours, at their ends. }
  for I := 0 to N - 1 do
    for J := I + 1 to N - 1 do
    begin
      if (J = I + 1) or ((I = 0) and (J = N - 1)) then Continue;
      if SegmentsTouch(P[I].X, P[I].Y, P[(I + 1) mod N].X, P[(I + 1) mod N].Y,
        P[J].X, P[J].Y, P[(J + 1) mod N].X, P[(J + 1) mod N].Y) then
      begin
        Error := 'The room''s walls cross each other';
        Exit;
      end;
    end;

  Before := Capture;
  { Corners on existing lines split them, and existing vertices on the
    room's edges become corners too: then every edge runs from vertex to
    vertex and an edge along a wall is that wall's line. }
  for I := 0 to N - 1 do
    if FindVertex(P[I].X, P[I].Y) < 0 then
      for L := 0 to High(Lines) do
        if OnLineInside(P[I].X, P[I].Y, L) then
        begin
          SplitLineAtPoint(L, P[I].X, P[I].Y);
          Break;
        end;
  Q := nil;
  for I := 0 to N - 1 do
  begin
    SetLength(Q, Length(Q) + 1);
    Q[High(Q)] := P[I];
    AddVerticesOnEdge(P[I], P[(I + 1) mod N], Q);
  end;
  P := Q;
  N := Length(P);

  { Each edge: an existing line (shared) or clear of every line. }
  SetLength(SharedLine, N);
  SetLength(SharedSide, N);
  Shared := 0;
  for I := 0 to N - 1 do
  begin
    SharedLine[I] := -1;
    SharedSide[I] := -1;
    X1 := P[I].X; Y1 := P[I].Y;
    X2 := P[(I + 1) mod N].X; Y2 := P[(I + 1) mod N].Y;
    V1 := FindVertex(P[I].X, P[I].Y);
    V2 := FindVertex(P[(I + 1) mod N].X, P[(I + 1) mod N].Y);
    if (V1 >= 0) and (V2 >= 0) then
    begin
      L := FindLine(V1, V2);
      if L >= 0 then
      begin
        { The room is on the line's front (right) when the edge runs the
          line's way (the room is clockwise), else on its back. }
        if Lines[L].V1 = V1 then SharedSide[I] := 0 else SharedSide[I] := 1;
        SharedLine[I] := L;
        Inc(Shared);
        Continue;
      end;
    end;
    for L := 0 to High(Lines) do
    begin
      MX := Vertices[Lines[L].V1].X; MY := Vertices[Lines[L].V1].Y;
      NX := Vertices[Lines[L].V2].X; NY := Vertices[Lines[L].V2].Y;
      if not SegmentsTouch(X1, Y1, X2, Y2, MX, MY, NX, NY) then Continue;
      if (Abs(Cross(X1, Y1, X2, Y2, MX, MY)) < 1e-6) and (Abs(Cross(X1, Y1, X2, Y2, NX, NY)) < 1e-6) then
      begin
        { On one line: fine when they only meet end to end. }
        Len := Sqr(X2 - X1) + Sqr(Y2 - Y1);
        T1 := ((MX - X1) * (X2 - X1) + (MY - Y1) * (Y2 - Y1)) / Len;
        T2 := ((NX - X1) * (X2 - X1) + (NY - Y1) * (Y2 - Y1)) / Len;
        if Min(1, Max(T1, T2)) - Max(0, Min(T1, T2)) <= 1e-9 then Continue;
      end else
      { Across: fine when they meet at a common end. }
      if SamePoint(X1, Y1, MX, MY) or SamePoint(X1, Y1, NX, NY) or
         SamePoint(X2, Y2, MX, MY) or SamePoint(X2, Y2, NX, NY) then
        Continue;
      Error := Format('The room''s wall %d crosses line %d', [I + 1, L]);
      Restore(Before);
      Exit;
    end;
  end;

  { No vertex inside the room. }
  for I := 0 to High(Vertices) do
    if PointInPolygon(Vertices[I].X + 0.0011, Vertices[I].Y + 0.0013, P) then
    begin
      J := 0;
      for K := 0 to N - 1 do
        if (P[K].X = Vertices[I].X) and (P[K].Y = Vertices[I].Y) then J := 1;
      if J = 0 then
      begin
        Error := Format('The room would contain vertex %d', [I]);
        Restore(Before);
        Exit;
      end;
    end;

  { Where the room is: a point just inside its first new edge, else the
    sector on the room's side of a shared one (-1: the void). }
  Outer := -2;
  for I := 0 to N - 1 do
    if SharedLine[I] < 0 then
    begin
      X1 := P[I].X; Y1 := P[I].Y;
      X2 := P[(I + 1) mod N].X; Y2 := P[(I + 1) mod N].Y;
      Len := Sqrt(Sqr(X2 - X1) + Sqr(Y2 - Y1));
      { The right of the edge (clockwise polygon): (dy, -dx). }
      MX := (X1 + X2) / 2 + (Y2 - Y1) / Len * 0.5;
      MY := (Y1 + Y2) / 2 - (X2 - X1) / Len * 0.5;
      Outer := SectorAt(MX, MY);
      Break;
    end;
  if Outer = -2 then
    Outer := LineSector(SharedLine[0], SharedSide[0]);
  { Every shared line must have Outer (or the void) on the room's side. }
  for I := 0 to N - 1 do
    if (SharedLine[I] >= 0) and (LineSector(SharedLine[I], SharedSide[I]) <> Outer) then
    begin
      Error := Format('The room would span two sectors at line %d', [SharedLine[I]]);
      Restore(Before);
      Exit;
    end;

  Sec := Length(Sectors);
  SetLength(Sectors, Sec + 1);
  if Outer >= 0 then
    Sectors[Sec] := Sectors[Outer]
  else
  begin
    Sectors[Sec].Floor := 0;
    Sectors[Sec].Ceiling := 128;
    Sectors[Sec].FloorTex := DefaultFloor;
    Sectors[Sec].CeilingTex := DefaultCeiling;
    Sectors[Sec].Light := 160;
    for I := 0 to N - 1 do
      if SharedLine[I] >= 0 then
      begin
        K := LineSector(SharedLine[I], 1 - SharedSide[I]);
        if K >= 0 then
        begin
          Sectors[Sec] := Sectors[K];
          Break;
        end;
      end;
  end;
  Sectors[Sec].Special := 0;
  Sectors[Sec].Tag := 0;
  Wall := DefaultWall;

  for I := 0 to N - 1 do
  begin
    L := SharedLine[I];
    if (L >= 0) and (Lines[L].Side[SharedSide[I]] >= 0) then
    begin
      { The room takes over the line's side that faces it (a copy: maps
        may share sidedefs between lines). }
      K := Length(Sides);
      SetLength(Sides, K + 1);
      Sides[K] := Sides[Lines[L].Side[SharedSide[I]]];
      Sides[K].Sector := Sec;
      Lines[L].Side[SharedSide[I]] := K;
      Continue;
    end;
    if L >= 0 then
    begin
      { A wall to the void: it joins the two rooms. }
      FrontSide := Lines[L].Side[0];
      if FrontSide >= 0 then
      begin
        if (Sides[FrontSide].Middle <> '') and (Sides[FrontSide].Middle <> '-') then
          Wall := Sides[FrontSide].Middle;
        Sides[FrontSide].Upper := Wall;
        Sides[FrontSide].Lower := Wall;
        Sides[FrontSide].Middle := '-';
      end;
      Lines[L].Side[1] := AddSide(Sec, Wall, Wall, '-');
      Lines[L].Flags := (Lines[L].Flags or ML_TWOSIDED) and not ML_BLOCKING;
      Continue;
    end;
    V1 := VertexAt(P[I].X, P[I].Y);
    V2 := VertexAt(P[(I + 1) mod N].X, P[(I + 1) mod N].Y);
    L := Length(Lines);
    SetLength(Lines, L + 1);
    Lines[L].V1 := V1;
    Lines[L].V2 := V2;
    Lines[L].Special := 0;
    Lines[L].Tag := 0;
    if Outer >= 0 then
    begin
      NewSide := AddSide(Sec, Wall, Wall, '-');
      OuterSide := AddSide(Outer, Wall, Wall, '-');
      Lines[L].Side[0] := NewSide;
      Lines[L].Side[1] := OuterSide;
      Lines[L].Flags := ML_TWOSIDED;
    end else
    begin
      Lines[L].Side[0] := AddSide(Sec, '-', '-', Wall);
      Lines[L].Side[1] := -1;
      Lines[L].Flags := ML_BLOCKING;
    end;
  end;
  PushUndo(Before);
  Result := Sec;
end;

{ (X, Y) lies on line L, not at its ends (exact: whole units). }
function TDoomEditMap.OnLineInside(const X, Y, L: Integer): Boolean;
var
  AX, AY, BX, BY: Int64;
begin
  AX := Vertices[Lines[L].V1].X; AY := Vertices[Lines[L].V1].Y;
  BX := Vertices[Lines[L].V2].X; BY := Vertices[Lines[L].V2].Y;
  Result := ((BX - AX) * (Y - AY) - (BY - AY) * (X - AX) = 0) and
    (X >= Min(AX, BX)) and (X <= Max(AX, BX)) and (Y >= Min(AY, BY)) and (Y <= Max(AY, BY)) and
    not ((X = AX) and (Y = AY)) and not ((X = BX) and (Y = BY));
end;

procedure TDoomEditMap.SplitLineAtPoint(const L, X, Y: Integer);
var
  V, N, S: Integer;
begin
  V := VertexAt(X, Y);
  N := Length(Lines);
  SetLength(Lines, N + 1);
  Lines[N] := Lines[L];
  Lines[N].V1 := V;
  Lines[L].V2 := V;
  for S := 0 to 1 do
    if Lines[L].Side[S] >= 0 then
    begin
      Lines[N].Side[S] := Length(Sides);
      SetLength(Sides, Length(Sides) + 1);
      Sides[High(Sides)] := Sides[Lines[L].Side[S]];
    end;
end;

{ Add to Q, in order from A to B, the vertices on segment A-B between its
  ends. }
procedure TDoomEditMap.AddVerticesOnEdge(const A, B: TEditPoint; var Q: TEditPoints);
var
  I, J, Count: Integer;
  T: array of Double;
  Idx: array of Integer;
  Tmp: Double;
  TmpI: Integer;
  DX, DY: Int64;
begin
  DX := B.X - A.X;
  DY := B.Y - A.Y;
  Count := 0;
  SetLength(T, 0);
  SetLength(Idx, 0);
  for I := 0 to High(Vertices) do
  begin
    if DX * (Vertices[I].Y - A.Y) - DY * (Vertices[I].X - A.X) <> 0 then Continue;
    if (Vertices[I].X < Min(A.X, B.X)) or (Vertices[I].X > Max(A.X, B.X)) or
       (Vertices[I].Y < Min(A.Y, B.Y)) or (Vertices[I].Y > Max(A.Y, B.Y)) then Continue;
    if ((Vertices[I].X = A.X) and (Vertices[I].Y = A.Y)) or ((Vertices[I].X = B.X) and (Vertices[I].Y = B.Y)) then Continue;
    SetLength(T, Count + 1);
    SetLength(Idx, Count + 1);
    T[Count] := ((Vertices[I].X - A.X) * DX + (Vertices[I].Y - A.Y) * DY) / (DX * DX + DY * DY);
    Idx[Count] := I;
    Inc(Count);
  end;
  for I := 1 to Count - 1 do
    for J := I downto 1 do
      if T[J] < T[J - 1] then
      begin
        Tmp := T[J]; T[J] := T[J - 1]; T[J - 1] := Tmp;
        TmpI := Idx[J]; Idx[J] := Idx[J - 1]; Idx[J - 1] := TmpI;
      end;
  for I := 0 to Count - 1 do
  begin
    SetLength(Q, Length(Q) + 1);
    Q[High(Q)].X := Vertices[Idx[I]].X;
    Q[High(Q)].Y := Vertices[Idx[I]].Y;
  end;
end;

function TDoomEditMap.MakeDoor(const Sec: Integer): Boolean;
var
  I, T: Integer;
  Outside: Integer;
begin
  Result := false;
  for I := 0 to High(Lines) do
    if (Lines[I].Side[0] >= 0) and (Lines[I].Side[1] >= 0) and
       ((LineSector(I, 0) = Sec) or (LineSector(I, 1) = Sec)) and
       (LineSector(I, 0) <> LineSector(I, 1)) then
    begin
      if not Result then Snapshot;
      Result := true;
      { The door sector at the back: flip a line that has it in front. }
      if LineSector(I, 0) = Sec then
      begin
        T := Lines[I].V1; Lines[I].V1 := Lines[I].V2; Lines[I].V2 := T;
        T := Lines[I].Side[0]; Lines[I].Side[0] := Lines[I].Side[1]; Lines[I].Side[1] := T;
      end;
      Lines[I].Special := 1;
      Outside := Lines[I].Side[0];
      Sides[Outside].Upper := 'DOOR3';
    end;
  if Result then
    Sectors[Sec].Ceiling := Sectors[Sec].Floor;
end;

procedure TDoomEditMap.ChangeSector(const Sec, DFloor, DCeiling, DLight: Integer);
begin
  Snapshot;
  Sectors[Sec].Floor := Sectors[Sec].Floor + DFloor;
  Sectors[Sec].Ceiling := Max(Sectors[Sec].Floor, Sectors[Sec].Ceiling + DCeiling);
  if DFloor > 0 then
    Sectors[Sec].Floor := Min(Sectors[Sec].Floor, Sectors[Sec].Ceiling);
  Sectors[Sec].Light := EnsureRange(Sectors[Sec].Light + DLight, 0, 255);
end;

initialization
  EditedNames := TStringList.Create;
  EditedNames.OwnsObjects := true;
finalization
  FreeAndNil(EditedNames);
end.
