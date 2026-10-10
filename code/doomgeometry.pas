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

var
  { Mipmaps for the atlas pages when the shaders can sample them with
    explicit gradients (AtlasMipmapsAvailable); --no-atlas-mipmaps turns
    them off. }
  UseAtlasMipmaps: Boolean = true;

{ The atlas pages get mipmaps: UseAtlasMipmaps and CGE upgrades the
  shaders to GLSL 1.40 / 3.00 es (OpenGL 3.1+, OpenGL ES 3, WebGL 2),
  which have textureGrad. }
function AtlasMipmapsAvailable: Boolean;

var
  { Draw each chunk's walls and flats from one texture atlas page (one
    draw call per chunk and page) instead of one shape per texture: the
    browser's frame rate is the number of draw calls. Switches, scrolling
    and animated textures keep their own shapes. --no-atlas / --atlas on
    the command line. }
  UseTextureAtlas: Boolean = true;

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
    { Per vertex: the texture's rectangle in the atlas page (4 values,
      the doom_tile attribute); (0, 0, 1, 1) with an own texture. }
    Tiles: TSingleList;
    { The atlas page this batch draws from, -1 = its own texture (Img). }
    AtlasPage: Integer;
    Indices: TInt32List;
    CoordNode: TCoordinateNode;
    TexCoordNode: TTextureCoordinateNode;
    LightNode: TFloatVertexAttributeNode;
    TileNode: TFloatVertexAttributeNode;
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
    { Quad A B C D counter-clockwise as seen from the front; Tile is the
      texture's atlas rectangle (TileOf). }
    procedure AddQuad(const A, B, C, D: TVector3; const TA, TB, TC, TD: TVector2;
      const Light: TVector2; const Tile: TVector4);
    { Convex polygon (fan), counter-clockwise as seen from the front. }
    procedure AddPolygon(const Pts: array of TVector3; const Tex: array of TVector2;
      const Light: TVector2; const Tile: TVector4);
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
      const TexTopZ: Single; const Img: TDoomImage; const Light: TVector2);
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
    FVisible: Boolean;
    procedure SetVisible(const Value: Boolean);
    procedure AssignChunks;
    procedure BuildCollisionScene;
    procedure BuildSky(const SkyTexture: String);
    procedure Dependency(const Sec: Integer; const Chunk: TMapChunk);
    { The level's wall textures and flats into TDoomGraphics' atlas pages. }
    procedure BuildAtlas(const SkyTexture: String);
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
    { Draw the map (walls, floors, sky); off for profiling the rest. }
    property Visible: Boolean read FVisible write SetVisible;
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

uses Math, CastleLog, CastleStringUtils, CastleImages, CastleGLUtils, CastleGLShaders;

function AtlasMipmapsAvailable: Boolean;
begin
  Result := UseAtlasMipmaps and InternalUpgradeGlslVersion and (GLFeatures <> nil) and
    { CASTLE_WEBGL / OpenGLES are CGE's own defines, not set here: the
      web build is WASI, the desktop builds use desktop OpenGL. }
    GLFeatures.{$ifdef WASI} VersionWebGL_2 {$else} Version_3_1 {$endif};
end;

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
  Tiles := TSingleList.Create;
  AtlasPage := -1;
  Indices := TInt32List.Create;
end;

destructor TGeomBatch.Destroy;
begin
  DropNodes;
  FreeAndNil(Coords);
  FreeAndNil(TexCoords);
  FreeAndNil(Lights);
  FreeAndNil(Tiles);
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
  TileNode := nil;
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
  Tiles.Count := 0;
  Indices.Count := 0;
end;

procedure TGeomBatch.AddQuad(const A, B, C, D: TVector3; const TA, TB, TC, TD: TVector2;
  const Light: TVector2; const Tile: TVector4);
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
    Tiles.Add(Tile.X); Tiles.Add(Tile.Y); Tiles.Add(Tile.Z); Tiles.Add(Tile.W);
  end;
  Indices.Add(Base); Indices.Add(Base + 1); Indices.Add(Base + 2);
  Indices.Add(Base); Indices.Add(Base + 2); Indices.Add(Base + 3);
end;

procedure TGeomBatch.AddPolygon(const Pts: array of TVector3; const Tex: array of TVector2;
  const Light: TVector2; const Tile: TVector4);
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
    Tiles.Add(Tile.X); Tiles.Add(Tile.Y); Tiles.Add(Tile.Z); Tiles.Add(Tile.W);
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
  TileNode := DoomLightingInstance.TileAttribute;
  Geometry := TIndexedTriangleSetNode.Create;
  Geometry.Coord := CoordNode;
  Geometry.TexCoord := TexCoordNode;
  Geometry.SetAttrib([LightNode, TileNode]);
  Geometry.Solid := true;
  Geometry.NormalPerVertex := false;

  Material := TUnlitMaterialNode.Create;
  Appearance := TAppearanceNode.Create;
  Appearance.Material := Material;
  if AtlasPage >= 0 then
  begin
    { The page is clamped, nearest up close and linear far away without
      mipmaps (a mipmap would blend the tiles into each other, and the
      wrap seam breaks the derivatives it needs); the effect wraps the
      coordinates inside each vertex's tile. }
    TexNode := Img.MakeTextureNode(true);
    if AtlasMipmapsAvailable then
    begin
      (TexNode.TextureProperties as TTexturePropertiesNode).MinificationFilter := minLinearMipmapLinear;
      (TexNode.TextureProperties as TTexturePropertiesNode).GenerateMipMaps := true;
    end else
    begin
      (TexNode.TextureProperties as TTexturePropertiesNode).MinificationFilter := minLinear;
      (TexNode.TextureProperties as TTexturePropertiesNode).GenerateMipMaps := false;
    end;
    (TexNode.TextureProperties as TTexturePropertiesNode).AnisotropicDegree := 1;
    TexNode.SetEffects([DoomLightingInstance.AtlasTextureEffect]);
    Appearance.Texture := TexNode;
  end else
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
  TileNode.SetValue(Tiles);
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
  SceneSolid.PreciseCollisions := true;
  ScenePassable := TCastleScene.Create(nil);
  ScenePassable.Collides := false;
  { Not PreciseCollisions, so a ray would hit the whole chunk's box: the
    inspector's F9 auto-select (and SELECT) could not reach a thing. }
  ScenePassable.Pickable := false;
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
  Page: Integer;
begin
  { In the atlas: one batch per page (and passability); switches (their
    texture is swapped in place), scrolling walls (their texture
    transform) and animated textures (their URL changes) keep their own. }
  Page := -1;
  if UseTextureAtlas and (SwitchLine < 0) and (not Scrolling) and (Img.AnimGroup = nil) then
    Page := Img.AtlasPage;
  if Page >= 0 then
    Key := 'atlas' + IntToStr(Page)
  else
    Key := Img.Url;
  if SwitchLine >= 0 then Key := 'switch' + IntToStr(SwitchLine);
  if Passable then Key := Key + 'P';
  if Scrolling then Key := Key + 'S';
  if not FBatches.TryGetValue(Key, Result) then
  begin
    Result := TGeomBatch.Create;
    Result.Key := Key;
    Result.AtlasPage := Page;
    if Page >= 0 then
      Result.Img := FOwner.Graphics.AtlasPage(Page)
    else
      Result.Img := Img;
    Result.Passable := Passable;
    Result.Scrolling := Scrolling;
    FBatches.Add(Key, Result);
  end;
end;

{ The texture's rectangle in its atlas page for the doom_tile attribute,
  or the whole texture. }
function TileOf(const B: TGeomBatch; const Img: TDoomImage): TVector4;
begin
  if B.AtlasPage >= 0 then
    Result := Img.AtlasRect
  else
    Result := Vector4(0, 0, 1, 1);
end;

procedure TMapChunk.EmitWall(const B: TGeomBatch; const AX, AY, BX, BY: Single;
  const ZBottom, ZTop: Single; const U0, U1: Single;
  const TexTopZ: Single; const Img: TDoomImage; const Light: TVector2);
var
  Top: Single;
  VBottom, VTop: Single;
begin
  Top := Max(ZTop, ZBottom);
  { Doom texture rows count from the top; X3D v grows upward. }
  VBottom := 1 - (TexTopZ - ZBottom) / Img.Height;
  VTop := 1 - (TexTopZ - Top) / Img.Height;
  B.AddQuad(
    DoomToCge(AX, AY, ZBottom), DoomToCge(BX, BY, ZBottom),
    DoomToCge(BX, BY, Top), DoomToCge(AX, AY, Top),
    Vector2(U0 / Img.Width, VBottom), Vector2(U1 / Img.Width, VBottom),
    Vector2(U1 / Img.Width, VTop), Vector2(U0 / Img.Width, VTop),
    Light, TileOf(B, Img));
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
      FloorZ, CeilZ, U0, U1, TexTopZ, Img, Light);
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
      ZB, ZT, U0, U1, TexTopZ, Img, Light);
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
        ZB, ZT, U0, U1, TexTopZ, Img, Light);
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
      ZB, ZT, U0, U1, TexTopZ, Img, Light);
  end;
end;

procedure TMapChunk.EmitFlats(const Sub: Integer);
var
  Map: TDoomMap;
  B: TGeomBatch;
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

  { Floor: polygon is counter-clockwise in Doom (X, Y) = facing up. A sky
    floor is not drawn either (r_plane draws any F_SKY1 plane as sky: the
    sky pits); BuildCollisionScene keeps it walkable. }
  if Map.HasSkyFloor(Sec) then
    Img := nil
  else
    Img := FOwner.Graphics.Flat(Map.Sectors[Sec].FloorTex);
  if Img <> nil then
  begin
    Z := Map.Sectors[Sec].FloorHeight;
    for I := 0 to N - 1 do
    begin
      Pts[I] := DoomToCge(S.Poly[I].X, S.Poly[I].Y, Z);
      Tex[I] := Vector2(S.Poly[I].X / 64, S.Poly[I].Y / 64);
    end;
    B := Batch(Img, false, false);
    B.AddPolygon(Pts, Tex, Light, TileOf(B, Img));
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
      B := Batch(Img, false, false);
      B.AddPolygon(Pts, Tex, Light, TileOf(B, Img));
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
  if UseTextureAtlas then
    BuildAtlas(SkyTexture);
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

procedure TDoomGeometry.BuildAtlas(const SkyTexture: String);
var
  Images: TDoomImageList;
  I, Pages: Integer;

  procedure Collect(const Img: TDoomImage);
  begin
    { Animated textures change their URL and switches are swapped in
      place: they keep their own shapes. }
    if (Img <> nil) and (Img.AnimGroup = nil) and (Copy(Img.Name, 1, 2) <> 'SW') and
       (Img.Name <> SkyTexture) and (Images.IndexOf(Img) < 0) then
      Images.Add(Img);
  end;

begin
  Images := TDoomImageList.Create;
  try
    for I := 0 to High(FMap.Sidedefs) do
    begin
      Collect(FGraphics.Texture(FMap.Sidedefs[I].UpperTex));
      Collect(FGraphics.Texture(FMap.Sidedefs[I].MiddleTex));
      Collect(FGraphics.Texture(FMap.Sidedefs[I].LowerTex));
    end;
    for I := 0 to High(FMap.Sectors) do
    begin
      if not FMap.HasSkyFloor(I) then
        Collect(FGraphics.Flat(FMap.Sectors[I].FloorTex));
      if not FMap.HasSkyCeiling(I) then
        Collect(FGraphics.Flat(FMap.Sectors[I].CeilingTex));
    end;
    Pages := FGraphics.BuildAtlas(Images, FMap.Name);
    if AtlasMipmapsAvailable then
      WritelnLog('Atlas', '%s: %d textures and flats in %d page(s), mipmapped', [FMap.Name, Images.Count, Pages])
    else
      WritelnLog('Atlas', '%s: %d textures and flats in %d page(s)', [FMap.Name, Images.Count, Pages]);
    for I := 0 to Pages - 1 do
      WritelnLog('Atlas', '  page %d: %dx%d', [I, FGraphics.AtlasPage(I).Width, FGraphics.AtlasPage(I).Height]);
  finally
    FreeAndNil(Images);
  end;
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
  I, J, Base: Integer;
  L: TDoomLinedef;
  VA, VB: TDoomVertex;
  ZB, ZT: Single;
  F, B: Integer;
  Sub: TDoomSubsector;
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
    { Sky floors are not drawn, so they collide here (at the height they
      have when the level starts). }
    for I := 0 to High(FMap.Subsectors) do
    begin
      Sub := FMap.Subsectors[I];
      if (Length(Sub.Poly) < 3) or not FMap.HasSkyFloor(Sub.Sector) then Continue;
      Base := Coords.Count;
      for J := 0 to High(Sub.Poly) do
        Coords.Add(DoomToCge(Sub.Poly[J].X, Sub.Poly[J].Y, FMap.Sectors[Sub.Sector].FloorHeight));
      for J := 1 to High(Sub.Poly) - 1 do
      begin
        Indices.Add(Base); Indices.Add(Base + J); Indices.Add(Base + J + 1);
      end;
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
  { Doom draws one sky row per screen row and projects heights with a focal
    length of 160 pixels, so texture row R sits at a slope of
    (100 - R) / 160 from the eye, relative to the world like the walls. }
  SkyTextureMid = 100;
  SkyFocal = 160;
  Tiles = 4;
var
  Img: TDoomImage;
  Root: TX3DRootNode;
  Batch: TGeomBatch;
  Q, I, Band: Integer;
  A0, A1, Y0, Y1, V0, V1: Single;
  P0, P1, P2, P3: TVector3;

  function RowHeight(const Row: Single): Single;
  begin
    Result := Radius * (SkyTextureMid - Row) / SkyFocal;
  end;

begin
  FSkyScene := TCastleScene.Create(nil);
  FSkyScene.Collides := false;
  FSkyScene.Pickable := false;
  Img := FGraphics.Texture(SkyTexture);
  if Img = nil then Exit;

  { Doom maps 1024 sky columns around a full turn, i.e. the 256 wide texture
    repeats 4 times. Bands from the top: row 0 stretched upwards (only mouse
    look gets there), then the texture repeated downwards the way Doom wraps
    it below the horizon (what sky pits show). v = 1 is row 0. }
  Batch := TGeomBatch.Create;
  try
    Batch.Img := Img;
    Batch.Clamp := true;
    for Band := -1 to Tiles - 1 do
    begin
      if Band < 0 then
      begin
        Y0 := Radius * 4;
        Y1 := RowHeight(0);
        V0 := 1;
        V1 := 1;
      end else
      begin
        Y0 := RowHeight(Band * Img.Height);
        Y1 := RowHeight((Band + 1) * Img.Height);
        V0 := 1;
        V1 := 0;
      end;
      for Q := 0 to 3 do
        for I := 0 to Segments - 1 do
        begin
          A0 := (Q * Segments + I) / (4 * Segments) * 2 * Pi;
          A1 := (Q * Segments + I + 1) / (4 * Segments) * 2 * Pi;
          { Facing inward (we are inside the cylinder). Doom angles grow
            counter-clockwise; texture columns grow with the angle. }
          P0 := DoomToCge(Cos(A1) * Radius, Sin(A1) * Radius, Y1);
          P1 := DoomToCge(Cos(A0) * Radius, Sin(A0) * Radius, Y1);
          P2 := DoomToCge(Cos(A0) * Radius, Sin(A0) * Radius, Y0);
          P3 := DoomToCge(Cos(A1) * Radius, Sin(A1) * Radius, Y0);
          Batch.AddQuad(P0, P1, P2, P3,
            Vector2((I + 1) / Segments, V1),
            Vector2(I / Segments, V1),
            Vector2(I / Segments, V0),
            Vector2((I + 1) / Segments, V0),
            Vector2(255, DoomLightFullBright), Vector4(0, 0, 1, 1));
        end;
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

procedure TDoomGeometry.SetVisible(const Value: Boolean);
var
  C: TMapChunk;
begin
  FVisible := Value;
  for C in FChunks do
  begin
    C.SceneSolid.Visible := Value;
    C.ScenePassable.Visible := Value;
  end;
  FSkyScene.Visible := Value;
end;

procedure TDoomGeometry.AddToWorld(const Parent: TCastleTransform);
var
  C: TMapChunk;
  I: Integer;
begin
  FVisible := true;
  { Names for the engine's inspector (F8): the scenes have no owner, so
    they are free to carry any. }
  for I := 0 to FChunks.Count - 1 do
  begin
    C := FChunks[I];
    C.SceneSolid.Name := Format('Chunk%d_Solid', [I]);
    C.ScenePassable.Name := Format('Chunk%d_Passable', [I]);
    Parent.Add(C.SceneSolid);
    Parent.Add(C.ScenePassable);
  end;
  FCollisionScene.Name := 'LineCollision';
  FSkyScene.Name := 'Sky';
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
