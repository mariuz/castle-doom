{ Building Castle Game Engine scenes (X3D node graphs) from Doom map data.

  Walls become textured quads, floors and ceilings are the convex subsector
  polygons recovered from the BSP, light levels become per-vertex colors on
  unlit materials. The map is split into "chunks": one big static chunk and
  one chunk per sector that can move (doors, lifts...). A chunk can be
  regenerated in place when its sector heights or light change.

  Coordinates: Doom (X, Y, Z-up) -> CGE (X, Z, -Y), 1 Doom unit = 1 CGE unit. }
unit DoomGeometry;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleVectors, CastleScene, CastleTransform, X3DNodes, CastleUtils, CastleColors, CastleRenderOptions,
  DoomMap, DoomGraphics, DoomLighting;

{ Doom map coordinates to CGE world coordinates. }
function DoomToCge(const X, Y, Z: Single): TVector3; inline;
function CgeToDoom(const V: TVector3): TVector3; inline;

type
  TDoomGeometry = class;

  { A set of triangles sharing one texture (and rendering flags) within a chunk. }
  TGeomBatch = class
  public
    Key: String;
    { Texture node created in CreateNodes, owned by the scene graph. }
    TexNode: TImageTextureNode;
    Img: TDoomImage;
    { Clamp texture coordinates (sky) instead of repeating. }
    Clamp: Boolean;
    Coords: TVector3List;
    TexCoords: TVector2List;
    { Per vertex: sector light level and kind (DoomLightWall + contrast,
      DoomLightPlane, DoomLightFullBright), the doom_light attribute. }
    Lights: TSingleList;
    Indices: TInt32List;
    CoordNode: TCoordinateNode;
    TexCoordNode: TTextureCoordinateNode;
    LightNode: TFloatVertexAttributeNode;
    Geometry: TIndexedTriangleSetNode;
    Shape: TShapeNode;
    TexTransform: TTextureTransformNode;
    { Does not block movement (masked middle textures on passable lines). }
    Passable: Boolean;
    { Scrolling wall (linedef special 48). }
    Scrolling: Boolean;
    { Vertex count the nodes were created with; topology changes force a rebuild. }
    CommittedVertices: Integer;
    constructor Create;
    destructor Destroy; override;
    procedure Reset;
    { Forget the nodes (they are owned by a scene root that is being replaced). }
    procedure DropNodes;
    { Quad A B C D counter-clockwise as seen from the front. }
    procedure AddQuad(const A, B, C, D: TVector3; const TA, TB, TC, TD: TVector2;
      const Light: TVector2);
    { Convex polygon (fan), counter-clockwise as seen from the front. }
    procedure AddPolygon(const Pts: array of TVector3; const Tex: array of TVector2;
      const Light: TVector2);
    procedure CreateNodes;
    { Update node fields from the lists (nodes must exist). }
    procedure UpdateNodes;
  end;

  TGeomBatchDict = {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TGeomBatch>;

  TLineSideRef = record
    Line, Side: Integer;
  end;

  TMapChunk = class
  strict private
    FOwner: TDoomGeometry;
    FBatches: TGeomBatchDict;
    FBuilt: Boolean;
    FRootSolid, FRootPassable: TX3DRootNode;
    function Batch(const Img: TDoomImage; const Passable, Scrolling: Boolean;
      const SwitchLine: Integer = -1): TGeomBatch;
    procedure EmitLineSide(const Line, Side: Integer);
    procedure EmitFlats(const Sub: Integer);
    procedure EmitWall(const B: TGeomBatch; const AX, AY, BX, BY: Single;
      const ZBottom, ZTop: Single; const U0, U1: Single;
      const TexTopZ: Single; const TexW, TexH: Integer; const Light: TVector2);
  public
    Name: String;
    SceneSolid, ScenePassable: TCastleScene;
    Lines: array of TLineSideRef;
    Subsectors: array of Integer;
    constructor Create(const AOwner: TDoomGeometry; const AName: String);
    destructor Destroy; override;
    { (Re)generate geometry from the current map state. }
    procedure Generate;
    { Update texture transforms of scrolling walls. }
    procedure UpdateScroll(const Offset: Single);
    function FindBatch(const Key: String): TGeomBatch;
    property Built: Boolean read FBuilt;
  end;

  TMapChunkList = {$ifdef FPC}specialize{$endif} TObjectList<TMapChunk>;
  TChunkSet = {$ifdef FPC}specialize{$endif} TList<TMapChunk>;

  TDoomGeometry = class
  strict private
    FMap: TDoomMap;
    FGraphics: TDoomGraphics;
    FChunks: TMapChunkList;
    FStaticChunk: TMapChunk;
    FSectorChunk: array of TMapChunk;
    FSectorDependents: array of TChunkSet;
    FDirty: TChunkSet;
    FCollisionScene: TCastleScene;
    FSkyScene: TCastleScene;
    FDynamic: array of Boolean;
    FScrollOffset: Single;
    FLineChunk: array of TMapChunk;
    procedure AssignChunks;
    procedure BuildCollisionScene;
    procedure BuildSky(const SkyTexture: String);
    procedure Dependency(const Sec: Integer; const Chunk: TMapChunk);
  public
    constructor Create(const AMap: TDoomMap; const AGraphics: TDoomGraphics;
      const DynamicSectors: array of Boolean; const SkyTexture: String);
    destructor Destroy; override;
    { Add all scenes to a viewport's Items. }
    procedure AddToWorld(const Parent: TCastleTransform);
    { Call after changing a sector's heights or light. }
    procedure SectorChanged(const Sec: Integer);
    { Regenerate chunks marked by SectorChanged. Call once per frame. }
    procedure FlushDirty;
    { Animate scrolling walls; SecondsPassed since last frame. }
    procedure Update(const SecondsPassed: Single; const CameraPosition: TVector3);
    { Flip a switch texture on a line (SW1xxx <-> SW2xxx). }
    procedure FlipSwitch(const Line: Integer);
    { Chunk that renders the given line side. }
    function ChunkOfLine(const Line: Integer): TMapChunk;
    property Map: TDoomMap read FMap;
    property Graphics: TDoomGraphics read FGraphics;
    property SkyScene: TCastleScene read FSkyScene;
  end;

implementation

uses Math, CastleLog, CastleStringUtils, CastleImages;

function DoomToCge(const X, Y, Z: Single): TVector3;
begin
  Result.X := X;
  Result.Y := Z;
  Result.Z := -Y;
end;

function CgeToDoom(const V: TVector3): TVector3;
begin
  Result.X := V.X;
  Result.Y := -V.Z;
  Result.Z := V.Y;
end;

{ TGeomBatch ----------------------------------------------------------------- }

constructor TGeomBatch.Create;
begin
  inherited;
  Coords := TVector3List.Create;
  TexCoords := TVector2List.Create;
  Lights := TSingleList.Create;
  Indices := TInt32List.Create;
end;

destructor TGeomBatch.Destroy;
begin
  DropNodes;
  FreeAndNil(Coords);
  FreeAndNil(TexCoords);
  FreeAndNil(Lights);
  FreeAndNil(Indices);
  inherited;
end;

procedure TGeomBatch.DropNodes;
begin
  if (TexNode <> nil) and (Img <> nil) and (Img.AnimGroup <> nil) then
    Img.AnimGroup.Unregister(TexNode);
  TexNode := nil;
  CoordNode := nil;
  TexCoordNode := nil;
  LightNode := nil;
  Geometry := nil;
  Shape := nil;
  TexTransform := nil;
  CommittedVertices := 0;
end;

procedure TGeomBatch.Reset;
begin
  Coords.Count := 0;
  TexCoords.Count := 0;
  Lights.Count := 0;
  Indices.Count := 0;
end;

procedure TGeomBatch.AddQuad(const A, B, C, D: TVector3; const TA, TB, TC, TD: TVector2;
  const Light: TVector2);
var
  Base, I: Integer;
begin
  Base := Coords.Count;
  Coords.Add(A); Coords.Add(B); Coords.Add(C); Coords.Add(D);
  TexCoords.Add(TA); TexCoords.Add(TB); TexCoords.Add(TC); TexCoords.Add(TD);
  for I := 1 to 4 do
  begin
    Lights.Add(Light.X);
    Lights.Add(Light.Y);
  end;
  Indices.Add(Base); Indices.Add(Base + 1); Indices.Add(Base + 2);
  Indices.Add(Base); Indices.Add(Base + 2); Indices.Add(Base + 3);
end;

procedure TGeomBatch.AddPolygon(const Pts: array of TVector3; const Tex: array of TVector2;
  const Light: TVector2);
var
  Base, I: Integer;
begin
  Base := Coords.Count;
  for I := 0 to High(Pts) do
  begin
    Coords.Add(Pts[I]);
    TexCoords.Add(Tex[I]);
    Lights.Add(Light.X);
    Lights.Add(Light.Y);
  end;
  for I := 1 to High(Pts) - 1 do
  begin
    Indices.Add(Base);
    Indices.Add(Base + I);
    Indices.Add(Base + I + 1);
  end;
end;

procedure TGeomBatch.CreateNodes;
var
  Appearance: TAppearanceNode;
  Material: TUnlitMaterialNode;
begin
  CoordNode := TCoordinateNode.Create;
  TexCoordNode := TTextureCoordinateNode.Create;
  LightNode := DoomLightingInstance.LightAttribute;
  Geometry := TIndexedTriangleSetNode.Create;
  Geometry.Coord := CoordNode;
  Geometry.TexCoord := TexCoordNode;
  Geometry.SetAttrib([LightNode]);
  Geometry.Solid := true;
  Geometry.NormalPerVertex := false;

  Material := TUnlitMaterialNode.Create;
  Appearance := TAppearanceNode.Create;
  Appearance.Material := Material;
  if Img <> nil then
  begin
    TexNode := Img.MakeTextureNode(Clamp);
    Appearance.Texture := TexNode;
  end;
  if (Img <> nil) and Img.HasAlpha then
    Appearance.AlphaMode := amMask
  else
    Appearance.AlphaMode := amOpaque;
  if Scrolling then
  begin
    TexTransform := TTextureTransformNode.Create;
    Appearance.TextureTransform := TexTransform;
  end;

  Shape := TShapeNode.Create;
  Shape.Appearance := Appearance;
  Shape.Geometry := Geometry;
  UpdateNodes;
end;

procedure TGeomBatch.UpdateNodes;
begin
  CoordNode.SetPoint(Coords);
  TexCoordNode.SetPoint(TexCoords);
  LightNode.SetValue(Lights);
  if CommittedVertices <> Coords.Count then
    Geometry.SetIndex(Indices);
  CommittedVertices := Coords.Count;
end;

{ TMapChunk ------------------------------------------------------------------ }

constructor TMapChunk.Create(const AOwner: TDoomGeometry; const AName: String);
begin
  inherited Create;
  FOwner := AOwner;
  Name := AName;
  FBatches := TGeomBatchDict.Create([doOwnsValues]);
  SceneSolid := TCastleScene.Create(nil);
  SceneSolid.Name := '';
  SceneSolid.PreciseCollisions := true;
  ScenePassable := TCastleScene.Create(nil);
  ScenePassable.Collides := false;
  ScenePassable.PreciseCollisions := true; { still needed for accurate ray casts (shooting) }
end;

destructor TMapChunk.Destroy;
begin
  FreeAndNil(SceneSolid);
  FreeAndNil(ScenePassable);
  FreeAndNil(FBatches);
  inherited;
end;

function TMapChunk.Batch(const Img: TDoomImage; const Passable, Scrolling: Boolean;
  const SwitchLine: Integer): TGeomBatch;
var
  Key: String;
begin
  Key := Img.Url;
  if SwitchLine >= 0 then Key := 'switch' + IntToStr(SwitchLine);
  if Passable then Key := Key + 'P';
  if Scrolling then Key := Key + 'S';
  if not FBatches.TryGetValue(Key, Result) then
  begin
    Result := TGeomBatch.Create;
    Result.Key := Key;
    Result.Img := Img;
    Result.Passable := Passable;
    Result.Scrolling := Scrolling;
    FBatches.Add(Key, Result);
  end;
end;

procedure TMapChunk.EmitWall(const B: TGeomBatch; const AX, AY, BX, BY: Single;
  const ZBottom, ZTop: Single; const U0, U1: Single;
  const TexTopZ: Single; const TexW, TexH: Integer; const Light: TVector2);
var
  Top: Single;
  VBottom, VTop: Single;
begin
  Top := Max(ZTop, ZBottom);
  { Doom texture rows count from the top; X3D v grows upward. }
  VBottom := 1 - (TexTopZ - ZBottom) / TexH;
  VTop := 1 - (TexTopZ - Top) / TexH;
  B.AddQuad(
    DoomToCge(AX, AY, ZBottom), DoomToCge(BX, BY, ZBottom),
    DoomToCge(BX, BY, Top), DoomToCge(AX, AY, Top),
    Vector2(U0 / TexW, VBottom), Vector2(U1 / TexW, VBottom),
    Vector2(U1 / TexW, VTop), Vector2(U0 / TexW, VTop),
    Light);
end;

procedure TMapChunk.EmitLineSide(const Line, Side: Integer);
var
  Map: TDoomMap;
  L: TDoomLinedef;
  Sd: TDoomSidedef;
  Sec, Other: Integer;
  VA, VB: TDoomVertex;
  Light: TVector2;
  Img: TDoomImage;
  U0, U1: Single;
  SwitchLine: Integer;
  FloorZ, CeilZ, OFloorZ, OCeilZ: Single;
  TexTopZ, ZB, ZT, OpenBottom, OpenTop: Single;
  Scrolling, Passable: Boolean;
begin
  Map := FOwner.Map;
  L := Map.Linedefs[Line];
  if L.Side[Side] < 0 then Exit;
  Sd := Map.Sidedefs[L.Side[Side]];
  Sec := Sd.Sector;
  if Side = 0 then
  begin
    VA := Map.Vertices[L.V1];
    VB := Map.Vertices[L.V2];
    Other := L.BackSector;
  end else
  begin
    VA := Map.Vertices[L.V2];
    VB := Map.Vertices[L.V1];
    Other := L.FrontSector;
  end;

  { Doom's "fake contrast": north-south walls a light step brighter,
    east-west ones a step darker. }
  Light := Vector2(Map.Sectors[Sec].LightLevel, DoomLightWall);
  if VA.Y = VB.Y then Light.Y := DoomLightWall - 1
  else if VA.X = VB.X then Light.Y := DoomLightWall + 1;

  U0 := Sd.XOffset;
  U1 := Sd.XOffset + L.Length;
  Scrolling := L.Special = 48;
  { Switches get a private batch per line so SW1 -> SW2 flips only that wall. }
  SwitchLine := -1;
  if (Side = 0) and (L.Special <> 0) and
     ((Copy(Sd.MiddleTex, 1, 2) = 'SW') or (Copy(Sd.UpperTex, 1, 2) = 'SW') or (Copy(Sd.LowerTex, 1, 2) = 'SW')) then
    SwitchLine := Line;

  FloorZ := Map.Sectors[Sec].FloorHeight;
  CeilZ := Map.Sectors[Sec].CeilingHeight;

  if Other < 0 then
  begin
    { One-sided wall: the middle texture from floor to ceiling. }
    Img := FOwner.Graphics.Texture(Sd.MiddleTex);
    if Img = nil then Exit;
    if (L.Flags and ML_DONTPEGBOTTOM) <> 0 then
      TexTopZ := FloorZ + Img.Height + Sd.YOffset
    else
      TexTopZ := CeilZ + Sd.YOffset;
    EmitWall(Batch(Img, false, Scrolling, SwitchLine), VA.X, VA.Y, VB.X, VB.Y,
      FloorZ, CeilZ, U0, U1, TexTopZ, Img.Width, Img.Height, Light);
    Exit;
  end;

  OFloorZ := Map.Sectors[Other].FloorHeight;
  OCeilZ := Map.Sectors[Other].CeilingHeight;

  { Lower wall: from our floor up to the neighbour's (higher) floor. }
  Img := FOwner.Graphics.Texture(Sd.LowerTex);
  if Img <> nil then
  begin
    if (L.Flags and ML_DONTPEGBOTTOM) <> 0 then
      TexTopZ := CeilZ + Sd.YOffset
    else
      TexTopZ := OFloorZ + Sd.YOffset;
    ZB := FloorZ;
    ZT := Min(OFloorZ, CeilZ);
    EmitWall(Batch(Img, false, Scrolling, SwitchLine), VA.X, VA.Y, VB.X, VB.Y,
      ZB, ZT, U0, U1, TexTopZ, Img.Width, Img.Height, Light);
  end;

  { Upper wall: from the neighbour's (lower) ceiling up to our ceiling.
    Skipped when both ceilings are sky (Doom's sky hack). }
  if not (Map.HasSkyCeiling(Sec) and Map.HasSkyCeiling(Other)) then
  begin
    Img := FOwner.Graphics.Texture(Sd.UpperTex);
    if Img <> nil then
    begin
      if (L.Flags and ML_DONTPEGTOP) <> 0 then
        TexTopZ := CeilZ + Sd.YOffset
      else
        TexTopZ := OCeilZ + Img.Height + Sd.YOffset;
      ZB := Max(OCeilZ, FloorZ);
      ZT := CeilZ;
      EmitWall(Batch(Img, false, Scrolling, SwitchLine), VA.X, VA.Y, VB.X, VB.Y,
        ZB, ZT, U0, U1, TexTopZ, Img.Width, Img.Height, Light);
    end;
  end;

  { Masked middle texture (grates, vines...): one texture height, clipped
    to the opening, not repeated vertically. }
  Img := FOwner.Graphics.Texture(Sd.MiddleTex);
  if Img <> nil then
  begin
    OpenBottom := Max(FloorZ, OFloorZ);
    OpenTop := Min(CeilZ, OCeilZ);
    if (L.Flags and ML_DONTPEGBOTTOM) <> 0 then
      TexTopZ := OpenBottom + Img.Height + Sd.YOffset
    else
      TexTopZ := OpenTop + Sd.YOffset;
    ZB := Max(OpenBottom, TexTopZ - Img.Height);
    ZT := Min(OpenTop, TexTopZ);
    Passable := (L.Flags and ML_BLOCKING) = 0;
    EmitWall(Batch(Img, Passable, Scrolling, SwitchLine), VA.X, VA.Y, VB.X, VB.Y,
      ZB, ZT, U0, U1, TexTopZ, Img.Width, Img.Height, Light);
  end;
end;

procedure TMapChunk.EmitFlats(const Sub: Integer);
var
  Map: TDoomMap;
  S: TDoomSubsector;
  Sec: Integer;
  Light: TVector2;
  Img: TDoomImage;
  Pts: array of TVector3;
  Tex: array of TVector2;
  I, N: Integer;
  Z: Single;
begin
  Map := FOwner.Map;
  S := Map.Subsectors[Sub];
  Sec := S.Sector;
  N := Length(S.Poly);
  if (Sec < 0) or (N < 3) then Exit;
  Light := Vector2(Map.Sectors[Sec].LightLevel, DoomLightPlane);
  SetLength(Pts, N);
  SetLength(Tex, N);

  { Floor: polygon is counter-clockwise in Doom (X, Y) = facing up. }
  Img := FOwner.Graphics.Flat(Map.Sectors[Sec].FloorTex);
  if Img <> nil then
  begin
    Z := Map.Sectors[Sec].FloorHeight;
    for I := 0 to N - 1 do
    begin
      Pts[I] := DoomToCge(S.Poly[I].X, S.Poly[I].Y, Z);
      Tex[I] := Vector2(S.Poly[I].X / 64, S.Poly[I].Y / 64);
    end;
    Batch(Img, false, false).AddPolygon(Pts, Tex, Light);
  end;

  { Ceiling: reversed order = facing down. Sky ceilings are not drawn. }
  if not Map.HasSkyCeiling(Sec) then
  begin
    Img := FOwner.Graphics.Flat(Map.Sectors[Sec].CeilingTex);
    if Img <> nil then
    begin
      Z := Map.Sectors[Sec].CeilingHeight;
      for I := 0 to N - 1 do
      begin
        Pts[I] := DoomToCge(S.Poly[N - 1 - I].X, S.Poly[N - 1 - I].Y, Z);
        Tex[I] := Vector2(S.Poly[N - 1 - I].X / 64, S.Poly[N - 1 - I].Y / 64);
      end;
      Batch(Img, false, false).AddPolygon(Pts, Tex, Light);
    end;
  end;
end;

procedure TMapChunk.Generate;
var
  B: TGeomBatch;
  I: Integer;
  NeedRebuild: Boolean;
begin
  for B in FBatches.Values do
    B.Reset;
  for I := 0 to High(Lines) do
    EmitLineSide(Lines[I].Line, Lines[I].Side);
  for I := 0 to High(Subsectors) do
    EmitFlats(Subsectors[I]);

  NeedRebuild := not FBuilt;
  if FBuilt then
    for B in FBatches.Values do
      if (B.Shape = nil) or (B.CommittedVertices <> B.Coords.Count) then
        NeedRebuild := true;

  if NeedRebuild then
  begin
    FRootSolid := TX3DRootNode.Create;
    FRootPassable := TX3DRootNode.Create;
    FRootSolid.AddChildren(DoomLightingInstance.GeometryEffect);
    FRootPassable.AddChildren(DoomLightingInstance.GeometryEffect);
    for B in FBatches.Values do
      B.DropNodes;
    for B in FBatches.Values do
      if B.Coords.Count > 0 then
      begin
        B.CreateNodes;
        if B.Passable then
          FRootPassable.AddChildren(B.Shape)
        else
          FRootSolid.AddChildren(B.Shape);
      end;
    SceneSolid.Load(FRootSolid, true);
    ScenePassable.Load(FRootPassable, true);
    FBuilt := true;
  end else
  begin
    for B in FBatches.Values do
      if B.Shape <> nil then
        B.UpdateNodes;
  end;
end;

function TMapChunk.FindBatch(const Key: String): TGeomBatch;
begin
  if not FBatches.TryGetValue(Key, Result) then
    Result := nil;
end;

procedure TMapChunk.UpdateScroll(const Offset: Single);
var
  B: TGeomBatch;
begin
  for B in FBatches.Values do
    if B.Scrolling and (B.TexTransform <> nil) and (B.Img <> nil) then
      B.TexTransform.Translation := Vector2(-Offset / B.Img.Width, 0);
end;

{ TDoomGeometry -------------------------------------------------------------- }

constructor TDoomGeometry.Create(const AMap: TDoomMap; const AGraphics: TDoomGraphics;
  const DynamicSectors: array of Boolean; const SkyTexture: String);
var
  I: Integer;
  C: TMapChunk;
begin
  inherited Create;
  FMap := AMap;
  FGraphics := AGraphics;
  FChunks := TMapChunkList.Create(true);
  FDirty := TChunkSet.Create;
  SetLength(FLineChunk, Length(FMap.Linedefs));
  SetLength(FDynamic, Length(FMap.Sectors));
  for I := 0 to High(FDynamic) do
    FDynamic[I] := (I <= High(DynamicSectors)) and DynamicSectors[I];
  SetLength(FSectorChunk, Length(FMap.Sectors));
  SetLength(FSectorDependents, Length(FMap.Sectors));
  for I := 0 to High(FSectorDependents) do
    FSectorDependents[I] := TChunkSet.Create;
  AssignChunks;
  for C in FChunks do
    C.Generate;
  BuildCollisionScene;
  BuildSky(SkyTexture);
  WritelnLog('Geometry', '%s: %d chunks (%d dynamic sectors)', [FMap.Name, FChunks.Count, FChunks.Count - 1]);
end;

destructor TDoomGeometry.Destroy;
var
  I: Integer;
begin
  FreeAndNil(FSkyScene);
  FreeAndNil(FCollisionScene);
  FreeAndNil(FChunks);
  FreeAndNil(FDirty);
  for I := 0 to High(FSectorDependents) do
    FreeAndNil(FSectorDependents[I]);
  inherited;
end;

procedure TDoomGeometry.Dependency(const Sec: Integer; const Chunk: TMapChunk);
begin
  if (Sec >= 0) and (FSectorDependents[Sec].IndexOf(Chunk) < 0) then
    FSectorDependents[Sec].Add(Chunk);
end;

procedure TDoomGeometry.AssignChunks;

  procedure AddLine(const C: TMapChunk; const Line, Side: Integer);
  var
    N: Integer;
  begin
    N := Length(C.Lines);
    SetLength(C.Lines, N + 1);
    C.Lines[N].Line := Line;
    C.Lines[N].Side := Side;
  end;

  procedure AddSub(const C: TMapChunk; const Sub: Integer);
  var
    N: Integer;
  begin
    N := Length(C.Subsectors);
    SetLength(C.Subsectors, N + 1);
    C.Subsectors[N] := Sub;
  end;

var
  I, Side, Sec, Front, Back: Integer;
  C: TMapChunk;
begin
  FStaticChunk := TMapChunk.Create(Self, 'static');
  FChunks.Add(FStaticChunk);
  for I := 0 to High(FMap.Sectors) do
    if FDynamic[I] then
    begin
      C := TMapChunk.Create(Self, 'sector' + IntToStr(I));
      FChunks.Add(C);
      FSectorChunk[I] := C;
    end;

  { Flats go to their sector's chunk. }
  for I := 0 to High(FMap.Subsectors) do
  begin
    Sec := FMap.Subsectors[I].Sector;
    if Sec < 0 then Continue;
    if FSectorChunk[Sec] <> nil then C := FSectorChunk[Sec] else C := FStaticChunk;
    AddSub(C, I);
    Dependency(Sec, C);
  end;

  { Each line side goes to the chunk of the first dynamic sector it touches
    (its own, then the neighbour), else to the static chunk. A side depends
    on both sectors. }
  for I := 0 to High(FMap.Linedefs) do
  begin
    Front := FMap.Linedefs[I].FrontSector;
    Back := FMap.Linedefs[I].BackSector;
    for Side := 0 to 1 do
    begin
      if FMap.Linedefs[I].Side[Side] < 0 then Continue;
      if Side = 0 then Sec := Front else Sec := Back;
      if Sec < 0 then Continue;
      C := nil;
      if FSectorChunk[Sec] <> nil then C := FSectorChunk[Sec]
      else if (Front >= 0) and (FSectorChunk[Front] <> nil) then C := FSectorChunk[Front]
      else if (Back >= 0) and (FSectorChunk[Back] <> nil) then C := FSectorChunk[Back]
      else C := FStaticChunk;
      AddLine(C, I, Side);
      if Side = 0 then FLineChunk[I] := C;
      Dependency(Front, C);
      Dependency(Back, C);
    end;
  end;
end;

procedure TDoomGeometry.BuildCollisionScene;
var
  Root: TX3DRootNode;
  Coords: TVector3List;
  Indices: TInt32List;
  CoordNode: TCoordinateNode;
  Geometry: TIndexedTriangleSetNode;
  Shape: TShapeNode;
  I, Base: Integer;
  L: TDoomLinedef;
  VA, VB: TDoomVertex;
  ZB, ZT: Single;
  F, B: Integer;
begin
  { Invisible walls for two-sided lines flagged "impassable" (fences, ledges). }
  Coords := TVector3List.Create;
  Indices := TInt32List.Create;
  try
    for I := 0 to High(FMap.Linedefs) do
    begin
      L := FMap.Linedefs[I];
      F := L.FrontSector;
      B := L.BackSector;
      if (F < 0) or (B < 0) or ((L.Flags and ML_BLOCKING) = 0) then Continue;
      VA := FMap.Vertices[L.V1];
      VB := FMap.Vertices[L.V2];
      ZB := Min(FMap.Sectors[F].FloorHeight, FMap.Sectors[B].FloorHeight) - 16;
      ZT := Max(FMap.Sectors[F].CeilingHeight, FMap.Sectors[B].CeilingHeight) + 16;
      Base := Coords.Count;
      Coords.Add(DoomToCge(VA.X, VA.Y, ZB));
      Coords.Add(DoomToCge(VB.X, VB.Y, ZB));
      Coords.Add(DoomToCge(VB.X, VB.Y, ZT));
      Coords.Add(DoomToCge(VA.X, VA.Y, ZT));
      Indices.Add(Base); Indices.Add(Base + 1); Indices.Add(Base + 2);
      Indices.Add(Base); Indices.Add(Base + 2); Indices.Add(Base + 3);
    end;
    FCollisionScene := TCastleScene.Create(nil);
    FCollisionScene.Visible := false;
    FCollisionScene.Pickable := false;
    FCollisionScene.PreciseCollisions := true;
    if Coords.Count > 0 then
    begin
      Root := TX3DRootNode.Create;
      CoordNode := TCoordinateNode.Create;
      CoordNode.SetPoint(Coords);
      Geometry := TIndexedTriangleSetNode.Create;
      Geometry.Coord := CoordNode;
      Geometry.SetIndex(Indices);
      Geometry.Solid := false;
      Shape := TShapeNode.Create;
      Shape.Geometry := Geometry;
      Root.AddChildren(Shape);
      FCollisionScene.Load(Root, true);
    end;
  finally
    FreeAndNil(Coords);
    FreeAndNil(Indices);
  end;
end;

procedure TDoomGeometry.BuildSky(const SkyTexture: String);
const
  Radius = 12000;
  Segments = 16; { per quarter }
var
  Img: TDoomImage;
  Root: TX3DRootNode;
  Batch: TGeomBatch;
  Q, I: Integer;
  A0, A1: Single;
  YTop, YBottom, YHorizonTop, YHorizonBottom: Single;
  P0, P1, P2, P3: TVector3;
begin
  FSkyScene := TCastleScene.Create(nil);
  FSkyScene.Collides := false;
  FSkyScene.Pickable := false;
  Img := FGraphics.Texture(SkyTexture);
  if Img = nil then Exit;

  { Doom maps 1024 sky columns around a full turn, i.e. the 256 wide texture
    repeats 4 times. Vertically, texture row 100 (of 128) sits at the horizon. }
  YHorizonTop := Radius * 1.25;    { texture row 0 }
  YHorizonBottom := -Radius * 0.35; { texture row 128 }
  YTop := Radius * 4;
  YBottom := -Radius * 2;

  Batch := TGeomBatch.Create;
  try
    Batch.Img := Img;
    Batch.Clamp := true;
    for Q := 0 to 3 do
      for I := 0 to Segments - 1 do
      begin
        A0 := (Q * Segments + I) / (4 * Segments) * 2 * Pi;
        A1 := (Q * Segments + I + 1) / (4 * Segments) * 2 * Pi;
        { Facing inward (we are inside the cylinder). Doom angles grow
          counter-clockwise; texture columns grow with the angle. }
        P0 := DoomToCge(Cos(A1) * Radius, Sin(A1) * Radius, YBottom);
        P1 := DoomToCge(Cos(A0) * Radius, Sin(A0) * Radius, YBottom);
        P2 := DoomToCge(Cos(A0) * Radius, Sin(A0) * Radius, YTop);
        P3 := DoomToCge(Cos(A1) * Radius, Sin(A1) * Radius, YTop);
        Batch.AddQuad(P0, P1, P2, P3,
          Vector2((I + 1) / Segments, (YBottom - YHorizonBottom) / (YHorizonTop - YHorizonBottom)),
          Vector2(I / Segments, (YBottom - YHorizonBottom) / (YHorizonTop - YHorizonBottom)),
          Vector2(I / Segments, (YTop - YHorizonBottom) / (YHorizonTop - YHorizonBottom)),
          Vector2((I + 1) / Segments, (YTop - YHorizonBottom) / (YHorizonTop - YHorizonBottom)),
          Vector2(255, DoomLightFullBright));
      end;
    Batch.CreateNodes;
    Batch.Geometry.Solid := false;
    Root := TX3DRootNode.Create;
    { Full bright like Doom's sky, but the invulnerability colormap applies. }
    Root.AddChildren(DoomLightingInstance.GeometryEffect);
    Root.AddChildren(Batch.Shape);
    FSkyScene.Load(Root, true);
    Batch.DropNodes;
  finally
    FreeAndNil(Batch);
  end;
end;

procedure TDoomGeometry.AddToWorld(const Parent: TCastleTransform);
var
  C: TMapChunk;
begin
  for C in FChunks do
  begin
    Parent.Add(C.SceneSolid);
    Parent.Add(C.ScenePassable);
  end;
  Parent.Add(FCollisionScene);
  Parent.Add(FSkyScene);
end;

procedure TDoomGeometry.SectorChanged(const Sec: Integer);
var
  C: TMapChunk;
begin
  if (Sec < 0) or (Sec > High(FSectorDependents)) then Exit;
  for C in FSectorDependents[Sec] do
    if FDirty.IndexOf(C) < 0 then
      FDirty.Add(C);
end;

procedure TDoomGeometry.FlushDirty;
var
  C: TMapChunk;
begin
  for C in FDirty do
    C.Generate;
  FDirty.Clear;
end;

procedure TDoomGeometry.Update(const SecondsPassed: Single; const CameraPosition: TVector3);
var
  C: TMapChunk;
begin
  { Scrolling walls move 35 texels per second (1 per tic). }
  FScrollOffset := FScrollOffset + SecondsPassed * 35;
  for C in FChunks do
    C.UpdateScroll(FScrollOffset);
  if FSkyScene <> nil then
    FSkyScene.Translation := CameraPosition;
end;

function TDoomGeometry.ChunkOfLine(const Line: Integer): TMapChunk;
begin
  if (Line >= 0) and (Line <= High(FLineChunk)) then
    Result := FLineChunk[Line]
  else
    Result := nil;
end;

procedure TDoomGeometry.FlipSwitch(const Line: Integer);
var
  Sd: Integer;
  Name, Other: String;
  Img: TDoomImage;
  C: TMapChunk;
  B: TGeomBatch;

  function Flip(const N: String): String;
  begin
    Result := N;
    if Copy(N, 1, 3) = 'SW1' then Result[3] := '2'
    else if Copy(N, 1, 3) = 'SW2' then Result[3] := '1';
  end;

begin
  Sd := FMap.Linedefs[Line].Side[0];
  if Sd < 0 then Exit;
  { Find which of the three textures is the switch and flip it. }
  Name := FMap.Sidedefs[Sd].MiddleTex;
  if Copy(Name, 1, 2) <> 'SW' then Name := FMap.Sidedefs[Sd].UpperTex;
  if Copy(Name, 1, 2) <> 'SW' then Name := FMap.Sidedefs[Sd].LowerTex;
  if Copy(Name, 1, 2) <> 'SW' then Exit;
  Other := Flip(Name);
  if not FGraphics.HasTexture(Other) then Exit;
  Img := FGraphics.Texture(Other);
  if Img = nil then Exit;
  { Remember the new state in the sidedef, so regenerating keeps it. }
  if FMap.Sidedefs[Sd].MiddleTex = Name then FMap.Sidedefs[Sd].MiddleTex := Other
  else if FMap.Sidedefs[Sd].UpperTex = Name then FMap.Sidedefs[Sd].UpperTex := Other
  else if FMap.Sidedefs[Sd].LowerTex = Name then FMap.Sidedefs[Sd].LowerTex := Other;
  { Swap the texture of this line's private batch in place. }
  C := ChunkOfLine(Line);
  if C <> nil then
  begin
    B := C.FindBatch('switch' + IntToStr(Line));
    if (B <> nil) and (B.TexNode <> nil) then
    begin
      B.Img := Img;
      B.TexNode.SetUrl([Img.Url]);
    end;
  end;
end;

end.
