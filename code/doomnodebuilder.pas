{ A BSP node builder for Doom's vanilla format: from a map's vertices,
  linedefs and sidedefs it makes the SEGS, SSECTORS and NODES lumps' data
  (Doom and every port need them: they are how the renderer and the
  point-in-sector queries find their way), adding the vertices where
  lines are split.

  The usual recursive build (like the original idbsp): the segs (one per
  line side) are split by the line of one of them until every set left is
  convex and of one sector, a subsector. The partition is chosen among
  (at most MaxCandidates of) the segs by the fewest splits and the best
  balance. Split points are rounded to whole units, as the 16-bit format
  needs. Used by the map editor (DoomEditMap) to export what it edits. }
unit DoomNodeBuilder;

interface

uses SysUtils, Classes;

type
  TNbVertex = record
    X, Y: Integer;
  end;

  TNbLine = record
    V1, V2: Integer;
    { Sidedef indices, -1 when absent. }
    Side: array [0..1] of Integer;
  end;

  TNbSeg = record
    V1, V2: Integer;
    { Binary angle (0..65535, 0 = east). }
    Angle: Integer;
    Line, Side, Offset: Integer;
  end;

  TNbSubsector = record
    Count, First: Integer;
  end;

  TNbBox = record
    Top, Bottom, Left, Right: Integer;
  end;

  TNbNode = record
    X, Y, DX, DY: Integer;
    { [0] = right (front) child, [1] = left. }
    Box: array [0..1] of TNbBox;
    { Child codes: >= 0 a node, else -1 - subsector index. }
    Child: array [0..1] of Integer;
  end;

  TNbVertexArray = array of TNbVertex;
  TNbLineArray = array of TNbLine;

  TNodeBuilder = class
  strict private
    type
      TWorkSeg = record
        V1, V2: Integer;
        Line, Side: Integer;
        Sector: Integer;
        { Distance from the line side's start to V1. }
        Offset: Double;
      end;
      TWorkSegs = array of TWorkSeg;
    var
      FSideSectors: array of Integer;
      FLines: TNbLineArray;
      FVertexIndex: TStringList;
    function AddVertex(const X, Y: Integer): Integer;
    function SideOf(const S: TWorkSeg; const PX, PY, DX, DY: Double; out A, B: Double): Integer;
    function IsLeaf(const Segs: TWorkSegs): Boolean;
    function ChoosePartition(const Segs: TWorkSegs): Integer;
    procedure Split(const Segs: TWorkSegs; const P: Integer; out Right, Left: TWorkSegs);
    function BoxOf(const Segs: TWorkSegs): TNbBox;
    function Build(const Segs: TWorkSegs; const Depth: Integer): Integer;
    function MakeSubsector(const Segs: TWorkSegs): Integer;
  public
    { In: the map. Vertices grows by the split points. }
    Vertices: TNbVertexArray;
    { Out. }
    Segs: array of TNbSeg;
    Subsectors: array of TNbSubsector;
    Nodes: array of TNbNode;
    { The root's child code (a lone subsector when the map is convex). }
    Root: Integer;
    { How many segs were split. }
    SplitCount: Integer;
    { Build from the map; SideSectors[i] is sidedef i's sector. }
    procedure Run(const AVertices: TNbVertexArray; const ALines: TNbLineArray;
      const SideSectors: array of Integer);
    destructor Destroy; override;
  end;

const
  { Partition candidates tried per node (every seg when there are fewer). }
  MaxCandidates = 160;

implementation

uses Math;

const
  Eps = 0.01;

destructor TNodeBuilder.Destroy;
begin
  FreeAndNil(FVertexIndex);
  inherited;
end;

function TNodeBuilder.AddVertex(const X, Y: Integer): Integer;
var
  Key: String;
  I: Integer;
begin
  Key := IntToStr(X) + ',' + IntToStr(Y);
  I := FVertexIndex.IndexOf(Key);
  if I >= 0 then Exit(PtrInt(FVertexIndex.Objects[I]));
  Result := Length(Vertices);
  SetLength(Vertices, Result + 1);
  Vertices[Result].X := X;
  Vertices[Result].Y := Y;
  FVertexIndex.AddObject(Key, TObject(PtrInt(Result)));
end;

{ Where S lies from the partition through (PX, PY) along (DX, DY): 0 right
  (Doom's front), 1 left, 2 split; A and B are its ends' distances (right
  positive). A seg on the partition goes right when it runs the same way. }
function TNodeBuilder.SideOf(const S: TWorkSeg; const PX, PY, DX, DY: Double; out A, B: Double): Integer;
var
  Len: Double;
  V1, V2: TNbVertex;
begin
  Len := Sqrt(DX * DX + DY * DY);
  V1 := Vertices[S.V1];
  V2 := Vertices[S.V2];
  A := ((V1.X - PX) * DY - (V1.Y - PY) * DX) / Len;
  B := ((V2.X - PX) * DY - (V2.Y - PY) * DX) / Len;
  if (Abs(A) < Eps) and (Abs(B) < Eps) then
  begin
    if (V2.X - V1.X) * DX + (V2.Y - V1.Y) * DY > 0 then Result := 0 else Result := 1;
  end else
  if (A > -Eps) and (B > -Eps) then
    Result := 0
  else if (A < Eps) and (B < Eps) then
    Result := 1
  else
    Result := 2;
end;

{ Convex (every seg has all the others on its right or on its line) and of
  one sector. }
function TNodeBuilder.IsLeaf(const Segs: TWorkSegs): Boolean;
var
  I, J: Integer;
  A, B: Double;
  PX, PY, DX, DY: Double;
begin
  for I := 1 to High(Segs) do
    if Segs[I].Sector <> Segs[0].Sector then Exit(false);
  for I := 0 to High(Segs) do
  begin
    PX := Vertices[Segs[I].V1].X;
    PY := Vertices[Segs[I].V1].Y;
    DX := Vertices[Segs[I].V2].X - PX;
    DY := Vertices[Segs[I].V2].Y - PY;
    for J := 0 to High(Segs) do
      if (J <> I) and (SideOf(Segs[J], PX, PY, DX, DY, A, B) <> 0) then
        Exit(false);
  end;
  Result := true;
end;

{ The seg whose line splits the fewest others into two non-empty halves
  of about equal size; -1 when no line has segs on both sides. }
function TNodeBuilder.ChoosePartition(const Segs: TWorkSegs): Integer;
var
  Step, I, J, Rights, Lefts, Splits, Cost, BestCost: Integer;
  A, B: Double;
  PX, PY, DX, DY: Double;
begin
  Result := -1;
  BestCost := MaxInt;
  Step := Max(1, Length(Segs) div MaxCandidates);
  I := 0;
  while I <= High(Segs) do
  begin
    PX := Vertices[Segs[I].V1].X;
    PY := Vertices[Segs[I].V1].Y;
    DX := Vertices[Segs[I].V2].X - PX;
    DY := Vertices[Segs[I].V2].Y - PY;
    Rights := 0;
    Lefts := 0;
    Splits := 0;
    for J := 0 to High(Segs) do
      case SideOf(Segs[J], PX, PY, DX, DY, A, B) of
        0: Inc(Rights);
        1: Inc(Lefts);
        else
          begin
            Inc(Rights);
            Inc(Lefts);
            Inc(Splits);
          end;
      end;
    if (Lefts > 0) and (Rights > 0) then
    begin
      Cost := Splits * 8 + Abs(Rights - Lefts);
      { Axis-aligned partitions keep the rounding exact. }
      if (DX <> 0) and (DY <> 0) then Inc(Cost, 2);
      if Cost < BestCost then
      begin
        BestCost := Cost;
        Result := I;
      end;
    end;
    Inc(I, Step);
  end;
end;

procedure TNodeBuilder.Split(const Segs: TWorkSegs; const P: Integer; out Right, Left: TWorkSegs);
var
  NR, NL, I, V: Integer;
  A, B, T, PX, PY, DX, DY: Double;
  S, S2: TWorkSeg;
  V1, V2: TNbVertex;
  SX, SY: Integer;

  procedure AddR(const X: TWorkSeg);
  begin
    if NR > High(Right) then SetLength(Right, NR * 2 + 4);
    Right[NR] := X;
    Inc(NR);
  end;

  procedure AddL(const X: TWorkSeg);
  begin
    if NL > High(Left) then SetLength(Left, NL * 2 + 4);
    Left[NL] := X;
    Inc(NL);
  end;

begin
  Right := nil;
  Left := nil;
  NR := 0;
  NL := 0;
  PX := Vertices[Segs[P].V1].X;
  PY := Vertices[Segs[P].V1].Y;
  DX := Vertices[Segs[P].V2].X - PX;
  DY := Vertices[Segs[P].V2].Y - PY;
  for I := 0 to High(Segs) do
  begin
    S := Segs[I];
    case SideOf(S, PX, PY, DX, DY, A, B) of
      0: AddR(S);
      1: AddL(S);
      else
        begin
          V1 := Vertices[S.V1];
          V2 := Vertices[S.V2];
          T := A / (A - B);
          SX := Round(V1.X + (V2.X - V1.X) * T);
          SY := Round(V1.Y + (V2.Y - V1.Y) * T);
          if ((SX = V1.X) and (SY = V1.Y)) or ((SX = V2.X) and (SY = V2.Y)) then
          begin
            { Too short to split at whole units: the side of its far end. }
            if Abs(A) > Abs(B) then
            begin
              if A > 0 then AddR(S) else AddL(S);
            end else
            begin
              if B > 0 then AddR(S) else AddL(S);
            end;
            Continue;
          end;
          V := AddVertex(SX, SY);
          Inc(SplitCount);
          S2 := S;
          S.V2 := V;
          S2.V1 := V;
          S2.Offset := S.Offset + Sqrt(Sqr(SX - V1.X) + Sqr(SY - V1.Y));
          if A > 0 then
          begin
            AddR(S);
            AddL(S2);
          end else
          begin
            AddL(S);
            AddR(S2);
          end;
        end;
    end;
  end;
  SetLength(Right, NR);
  SetLength(Left, NL);
end;

function TNodeBuilder.BoxOf(const Segs: TWorkSegs): TNbBox;
var
  I: Integer;

  procedure Grow(const V: TNbVertex);
  begin
    Result.Top := Max(Result.Top, V.Y);
    Result.Bottom := Min(Result.Bottom, V.Y);
    Result.Left := Min(Result.Left, V.X);
    Result.Right := Max(Result.Right, V.X);
  end;

begin
  Result.Top := -MaxInt;
  Result.Bottom := MaxInt;
  Result.Left := MaxInt;
  Result.Right := -MaxInt;
  for I := 0 to High(Segs) do
  begin
    Grow(Vertices[Segs[I].V1]);
    Grow(Vertices[Segs[I].V2]);
  end;
end;

function TNodeBuilder.MakeSubsector(const Segs: TWorkSegs): Integer;
var
  I, N: Integer;
  V1, V2: TNbVertex;
begin
  Result := Length(Subsectors);
  SetLength(Subsectors, Result + 1);
  Subsectors[Result].First := Length(Self.Segs);
  Subsectors[Result].Count := Length(Segs);
  for I := 0 to High(Segs) do
  begin
    N := Length(Self.Segs);
    SetLength(Self.Segs, N + 1);
    V1 := Vertices[Segs[I].V1];
    V2 := Vertices[Segs[I].V2];
    Self.Segs[N].V1 := Segs[I].V1;
    Self.Segs[N].V2 := Segs[I].V2;
    Self.Segs[N].Angle := Round(ArcTan2(V2.Y - V1.Y, V2.X - V1.X) * 32768 / Pi) and $FFFF;
    Self.Segs[N].Line := Segs[I].Line;
    Self.Segs[N].Side := Segs[I].Side;
    Self.Segs[N].Offset := Round(Segs[I].Offset);
  end;
  Result := -1 - Result;
end;

function TNodeBuilder.Build(const Segs: TWorkSegs; const Depth: Integer): Integer;
var
  P, N, C0, C1: Integer;
  Right, Left: TWorkSegs;
begin
  if IsLeaf(Segs) or (Depth > 200) then
    Exit(MakeSubsector(Segs));
  P := ChoosePartition(Segs);
  if P < 0 then
    Exit(MakeSubsector(Segs));
  Split(Segs, P, Right, Left);
  { Splits too short to make at whole units may leave a side empty. }
  if (Length(Right) = 0) or (Length(Left) = 0) then
    Exit(MakeSubsector(Segs));
  N := Length(Nodes);
  SetLength(Nodes, N + 1);
  Nodes[N].X := Vertices[Segs[P].V1].X;
  Nodes[N].Y := Vertices[Segs[P].V1].Y;
  Nodes[N].DX := Vertices[Segs[P].V2].X - Nodes[N].X;
  Nodes[N].DY := Vertices[Segs[P].V2].Y - Nodes[N].Y;
  Nodes[N].Box[0] := BoxOf(Right);
  Nodes[N].Box[1] := BoxOf(Left);
  C0 := Build(Right, Depth + 1);
  C1 := Build(Left, Depth + 1);
  Nodes[N].Child[0] := C0;
  Nodes[N].Child[1] := C1;
  Result := N;
end;

procedure TNodeBuilder.Run(const AVertices: TNbVertexArray; const ALines: TNbLineArray;
  const SideSectors: array of Integer);
var
  Work: TWorkSegs;
  I, S, N: Integer;
  L: TNbLine;
begin
  Vertices := Copy(AVertices);
  FLines := ALines;
  SetLength(FSideSectors, Length(SideSectors));
  for I := 0 to High(SideSectors) do
    FSideSectors[I] := SideSectors[I];
  FreeAndNil(FVertexIndex);
  FVertexIndex := TStringList.Create;
  FVertexIndex.Sorted := true;
  FVertexIndex.Duplicates := dupIgnore;
  for I := 0 to High(Vertices) do
    FVertexIndex.AddObject(IntToStr(Vertices[I].X) + ',' + IntToStr(Vertices[I].Y), TObject(PtrInt(I)));
  Segs := nil;
  Subsectors := nil;
  Nodes := nil;
  SplitCount := 0;
  Work := nil;
  N := 0;
  for I := 0 to High(FLines) do
  begin
    L := FLines[I];
    if L.V1 = L.V2 then Continue;
    for S := 0 to 1 do
      if (L.Side[S] >= 0) and (L.Side[S] <= High(FSideSectors)) then
      begin
        SetLength(Work, N + 1);
        if S = 0 then
        begin
          Work[N].V1 := L.V1;
          Work[N].V2 := L.V2;
        end else
        begin
          Work[N].V1 := L.V2;
          Work[N].V2 := L.V1;
        end;
        Work[N].Line := I;
        Work[N].Side := S;
        Work[N].Sector := FSideSectors[L.Side[S]];
        Work[N].Offset := 0;
        Inc(N);
      end;
  end;
  if N = 0 then
    raise Exception.Create('The map has no lines');
  Root := Build(Work, 0);
end;

end.
