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
  CastleVectors, CastleScene, CastleTransform, X3DNodes, X3DFields, CastleUtils, CastleColors, CastleRenderOptions,
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
    { Per vertex (4 values each): the UDMF sector light colour and fog
      (doom_color, doom_fade); what Add* adds is CurColor / CurFade,
      which the emitter sets before each surface (Reset: white, no fog). }
    Colors, Fades: TSingleList;
    CurColor, CurFade: TVector4;
    ColorNode, FadeNode: TFloatVertexAttributeNode;
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
    { Scrolling walls and flats (vanilla 48, Boom 85 and 250-255): the
      texture transform's translation a tic (ScrollPerTic), so one batch
      per texture and speed. }
    Scrolling: Boolean;
    ScrollPerTic: TVector2;
    { A surface moved by Boom's runtime scrollers (DynIndex >= 0, the
      sidedef or sector): its translation is the map's offset of it. }
    DynTarget: TScrollTarget;
    DynIndex: Integer;
    { Boom's translucent middle textures (260): opacity below 1 makes a
      blended shape outside the atlas. }
    Alpha: Single;
    { Boom's deep water: the real walls and flats of the sectors drawn at
      other heights, only for collisions (an invisible scene). }
    CollisionOnly: Boolean;
    { A per-sector sky (Boom's 271 / 272 on some sky sectors): the
      ceilings are drawn with the sky texture mapped by the view direction
      (DoomLighting.SkyTextureEffect); SkyEye is its eye position. }
    IsSky, SkyFlipped: Boolean;
    SkyEye: TSFVec3f;
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
    { A sky polygon: each vertex's Doom position goes into doom_tile. }
    procedure AddSkyPolygon(const Pts: array of TVector3; const DoomPts: array of TVector3;
      const Light: TVector2);
    procedure CreateNodes;
    { Update node fields from the lists (nodes must exist). }
    procedure UpdateNodes;
  end;

  TGeomBatchDict = {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TGeomBatch>;

  TLineSideRef = record
    Line, Side: Integer;
  end;

  { How TMapChunk.Batch files what is emitted: as usual, only drawn (the
    deep water sectors' fake heights) or only collided with (their real
    ones). }
  TEmitMode = (emNormal, emVisual, emCollision);

  TMapChunk = class
  strict private
    FOwner: TDoomGeometry;
    FBatches: TGeomBatchDict;
    FBuilt: Boolean;
    FRootSolid, FRootPassable, FRootCollision: TX3DRootNode;
    FEmitMode: TEmitMode;
    { What collision mode discards (passable middle textures). }
    FDiscard: TGeomBatch;
    function IsWaterLine(const Line: Integer): Boolean;
    function SkyBatch(const Img: TDoomImage; const Flipped: Boolean): TGeomBatch;
    function IsWaterSub(const Sub: Integer): Boolean;
    function Batch(const Img: TDoomImage; const Passable: Boolean; const ScrollPerTic: TVector2;
      const SwitchLine: Integer = -1; const Alpha: Single = 1;
      const DynTarget: TScrollTarget = stSide; const DynIndex: Integer = -1): TGeomBatch;
    procedure EmitLineSide(const Line, Side: Integer);
    procedure EmitFlats(const Sub: Integer);
    procedure EmitWall(const B: TGeomBatch; const AX, AY, BX, BY: Single;
      const ZBottom, ZTop: Single; const U0, U1: Single;
      const TexTopZ: Single; const Img: TDoomImage; const Light: TVector2;
      const ScaleX: Single = 1; const ScaleY: Single = 1);
    { B's colour and fog for what is emitted next: sector Sec's UDMF
      lightcolor / fadecolor (fog denser in darker sectors). }
    procedure SetLook(const B: TGeomBatch; const Sec: Integer);
  public
    Name: String;
    SceneSolid, ScenePassable: TCastleScene;
    { Invisible: the deep water sectors' real geometry. }
    SceneCollision: TCastleScene;
    Lines: array of TLineSideRef;
    Subsectors: array of Integer;
    constructor Create(const AOwner: TDoomGeometry; const AName: String);
    destructor Destroy; override;
    { (Re)generate geometry from the current map state. }
    procedure Generate;
    { Update texture transforms of scrolling walls and flats, Tics after
      the level start. }
    procedure UpdateScroll(const Tics: Single; const DoomEye: TVector3);
    function FindBatch(const Key: String): TGeomBatch;
    property Built: Boolean read FBuilt;
    { The chunk's triangles by texture (DoomExport reads them). }
    property Batches: TGeomBatchDict read FBatches;
  end;

  TMapChunkList = {$ifdef FPC}specialize{$endif} TObjectList<TMapChunk>;

  { The viewer in a deep water sector: between the control sector's floor
    and ceiling, below its floor (under water) or above its ceiling. }
  TWaterView = (wvNormal, wvUnder, wvAbove);
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
    FSkyTexture, FMapSky: String;
    FSkyFlipped: Boolean;
    FWaterView: TWaterView;
    { The deep water sectors' real state while ApplyFakeSectors runs. }
    FSavedSectors: array of TDoomSector;
    procedure SetWaterView(const Value: TWaterView);
    procedure SetVisible(const Value: Boolean);
    procedure AssignChunks;
    procedure BuildCollisionScene;
    procedure BuildSky(const SkyTexture: String; const Flipped: Boolean);
    procedure Dependency(const Sec: Integer; const Chunk: TMapChunk);
    { The level's wall textures and flats into TDoomGraphics' atlas pages. }
    procedure BuildAtlas(const SkyTexture: String);
  public
    { SkyFlipped mirrors the sky (Boom's 272 sky transfer). }
    { SkyTexture / SkyFlipped: the sky cylinder; MapSky: the map's own sky
      (the sky sectors without a 271 / 272), for the per-sector skies. }
    constructor Create(const AMap: TDoomMap; const AGraphics: TDoomGraphics;
      const DynamicSectors: array of Boolean; const SkyTexture: String; const SkyFlipped: Boolean = false;
      const MapSky: String = '');
    { The sky a sky sector shows when it is not the cylinder's (per-sector
      skies), False when it is the cylinder's or the sector has no sky. }
    function SectorOwnSky(const Sec: Integer; out Texture: String; out Flipped: Boolean): Boolean;
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
    { The static chunk and one per dynamic sector (DoomExport). }
    property Chunks: TMapChunkList read FChunks;
    property SkyScene: TCastleScene read FSkyScene;
    { Boom's deep water (242): where the viewer is relative to their
      sector's control sector; a change regenerates the deep water
      sectors (R_FakeFlat). }
    property WaterView: TWaterView read FWaterView write SetWaterView;
    { Give the deep water sectors the heights, flats and light they are
      drawn with in the current view (TMapChunk.Generate), and back. }
    procedure ApplyFakeSectors;
    procedure RestoreSectors;
  end;

implementation

uses Math, CastleLog, CastleStringUtils, CastleImages, CastleGLUtils, CastleGLShaders;

function AtlasMipmapsAvailable: Boolean;
begin
  Result := UseAtlasMipmaps and InternalUpgradeGlslVersion and (GLFeatures <> nil) and
    { CASTLE_WEBGL / OpenGLES are CGE's own defines, not set here: the
      web build is WASI (WebGL 2), Android uses OpenGL ES (3.0 has
      textureGrad), the desktop builds desktop OpenGL. }
    GLFeatures.{$if defined(WASI)} VersionWebGL_2 {$elseif defined(ANDROID)} VersionES_3_0 {$else} Version_3_1 {$endif};
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
  Colors := TSingleList.Create;
  Fades := TSingleList.Create;
  CurColor := Vector4(1, 1, 1, 1);
  CurFade := TVector4.Zero;
  AtlasPage := -1;
  Alpha := 1;
  Indices := TInt32List.Create;
end;

destructor TGeomBatch.Destroy;
begin
  DropNodes;
  FreeAndNil(Coords);
  FreeAndNil(TexCoords);
  FreeAndNil(Lights);
  FreeAndNil(Tiles);
  FreeAndNil(Colors);
  FreeAndNil(Fades);
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
  ColorNode := nil;
  FadeNode := nil;
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
  Colors.Count := 0;
  Fades.Count := 0;
  Indices.Count := 0;
  CurColor := Vector4(1, 1, 1, 1);
  CurFade := TVector4.Zero;
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
    Colors.Add(CurColor.X); Colors.Add(CurColor.Y); Colors.Add(CurColor.Z); Colors.Add(CurColor.W);
    Fades.Add(CurFade.X); Fades.Add(CurFade.Y); Fades.Add(CurFade.Z); Fades.Add(CurFade.W);
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
    Colors.Add(CurColor.X); Colors.Add(CurColor.Y); Colors.Add(CurColor.Z); Colors.Add(CurColor.W);
    Fades.Add(CurFade.X); Fades.Add(CurFade.Y); Fades.Add(CurFade.Z); Fades.Add(CurFade.W);
  end;
  for I := 1 to High(Pts) - 1 do
  begin
    Indices.Add(Base);
    Indices.Add(Base + I);
    Indices.Add(Base + I + 1);
  end;
end;

procedure TGeomBatch.AddSkyPolygon(const Pts: array of TVector3; const DoomPts: array of TVector3;
  const Light: TVector2);
var
  Base, I: Integer;
begin
  Base := Coords.Count;
  for I := 0 to High(Pts) do
  begin
    Coords.Add(Pts[I]);
    TexCoords.Add(TVector2.Zero);
    Lights.Add(Light.X);
    Lights.Add(Light.Y);
    Tiles.Add(DoomPts[I].X); Tiles.Add(DoomPts[I].Y); Tiles.Add(DoomPts[I].Z); Tiles.Add(1);
    Colors.Add(1); Colors.Add(1); Colors.Add(1); Colors.Add(1);
    Fades.Add(0); Fades.Add(0); Fades.Add(0); Fades.Add(0);
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
  ColorNode := DoomLightingInstance.ColorAttribute;
  FadeNode := DoomLightingInstance.FadeAttribute;
  Geometry := TIndexedTriangleSetNode.Create;
  Geometry.Coord := CoordNode;
  Geometry.TexCoord := TexCoordNode;
  Geometry.SetAttrib([LightNode, TileNode, ColorNode, FadeNode]);
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
  if IsSky and (Img <> nil) then
  begin
    TexNode := Img.MakeTextureNode(false);
    TexNode.SetEffects([DoomLightingInstance.SkyTextureEffect(SkyFlipped, Img.Height, SkyEye)]);
    Appearance.Texture := TexNode;
  end else
  if Img <> nil then
  begin
    TexNode := Img.MakeTextureNode(Clamp);
    Appearance.Texture := TexNode;
  end;
  if Alpha < 1 then
  begin
    { The holes of a masked texture stay holes (alpha 0 blends to
      nothing), the rest shows the scene behind at 1 - Alpha. }
    Material.Transparency := 1 - Alpha;
    Appearance.AlphaMode := amBlend;
  end else
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
  ColorNode.SetValue(Colors);
  FadeNode.SetValue(Fades);
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
  SceneCollision := TCastleScene.Create(nil);
  SceneCollision.Visible := false;
  SceneCollision.Pickable := false;
  SceneCollision.PreciseCollisions := true;
  FDiscard := TGeomBatch.Create;
end;

destructor TMapChunk.Destroy;
begin
  FreeAndNil(SceneSolid);
  FreeAndNil(ScenePassable);
  FreeAndNil(SceneCollision);
  FreeAndNil(FDiscard);
  FreeAndNil(FBatches);
  inherited;
end;

function TMapChunk.Batch(const Img: TDoomImage; const Passable: Boolean; const ScrollPerTic: TVector2;
  const SwitchLine: Integer; const Alpha: Single;
  const DynTarget: TScrollTarget; const DynIndex: Integer): TGeomBatch;
var
  Key: String;
  Page: Integer;
  Scrolling, IsPassable: Boolean;
begin
  if FEmitMode = emCollision then
  begin
    { One invisible batch of everything that blocks; passable middle
      textures do not. }
    if Passable then Exit(FDiscard);
    if not FBatches.TryGetValue('collide', Result) then
    begin
      Result := TGeomBatch.Create;
      Result.Key := 'collide';
      Result.AtlasPage := -1;
      Result.Img := Img;
      Result.Alpha := 1;
      Result.DynIndex := -1;
      Result.CollisionOnly := true;
      FBatches.Add('collide', Result);
    end;
    Exit;
  end;
  { Drawn only: the passable scenes do not collide. }
  IsPassable := Passable or (FEmitMode = emVisual);
  Scrolling := (not ScrollPerTic.IsPerfectlyZero) or (DynIndex >= 0);
  { In the atlas: one batch per page (and passability); switches (their
    texture is swapped in place), scrolling walls (their texture
    transform) and animated textures (their URL changes) keep their own. }
  Page := -1;
  if UseTextureAtlas and (SwitchLine < 0) and (not Scrolling) and (Img.AnimGroup = nil) and (Alpha >= 1) then
    Page := Img.AtlasPage;
  if Page >= 0 then
    Key := 'atlas' + IntToStr(Page)
  else
    Key := Img.Url;
  if SwitchLine >= 0 then Key := 'switch' + IntToStr(SwitchLine);
  if IsPassable then Key := Key + 'P';
  if DynIndex >= 0 then
    Key := Key + Format('D%d,%d', [Ord(DynTarget), DynIndex])
  else if Scrolling then
    Key := Key + Format('S%g,%g', [ScrollPerTic.X, ScrollPerTic.Y]);
  if Alpha < 1 then
    Key := Key + Format('T%g', [Alpha]);
  if not FBatches.TryGetValue(Key, Result) then
  begin
    Result := TGeomBatch.Create;
    Result.Key := Key;
    Result.AtlasPage := Page;
    if Page >= 0 then
      Result.Img := FOwner.Graphics.AtlasPage(Page)
    else
      Result.Img := Img;
    Result.Passable := IsPassable;
    Result.Scrolling := Scrolling;
    Result.ScrollPerTic := ScrollPerTic;
    Result.DynTarget := DynTarget;
    Result.DynIndex := DynIndex;
    Result.Alpha := Alpha;
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

{ A wall's texture transform a tic for a side scrolling Rate texels a
  tic (X: texture offset, Y: row offset); zero = no scrolling. }
function WallScroll(const Rate: TVector2; const Img: TDoomImage): TVector2;
begin
  if Rate.IsPerfectlyZero then
    Result := TVector2.Zero
  else
    Result := Vector2(Rate.X / Img.Width, -Rate.Y / Img.Height);
end;

{ A flat's texture transform a tic for a floor or ceiling moving Rate
  map units a tic (flats repeat every 64 units). }
function FlatScroll(const Rate: TVector2; const Img: TDoomImage): TVector2;
begin
  if Rate.IsPerfectlyZero then
    Result := TVector2.Zero
  else
    Result := Vector2(Rate.X / Img.Width, Rate.Y / Img.Height);
end;

procedure TMapChunk.EmitWall(const B: TGeomBatch; const AX, AY, BX, BY: Single;
  const ZBottom, ZTop: Single; const U0, U1: Single;
  const TexTopZ: Single; const Img: TDoomImage; const Light: TVector2;
  const ScaleX, ScaleY: Single);
var
  Top: Single;
  VBottom, VTop: Single;
begin
  Top := Max(ZTop, ZBottom);
  { Doom texture rows count from the top; X3D v grows upward. A UDMF
    scale is texels a map unit (2: the texture half as big). }
  VBottom := 1 - (TexTopZ - ZBottom) * ScaleY / Img.Height;
  VTop := 1 - (TexTopZ - Top) * ScaleY / Img.Height;
  B.AddQuad(
    DoomToCge(AX, AY, ZBottom), DoomToCge(BX, BY, ZBottom),
    DoomToCge(BX, BY, Top), DoomToCge(AX, AY, Top),
    Vector2(U0 * ScaleX / Img.Width, VBottom), Vector2(U1 * ScaleX / Img.Width, VBottom),
    Vector2(U1 * ScaleX / Img.Width, VTop), Vector2(U0 * ScaleX / Img.Width, VTop),
    Light, TileOf(B, Img));
end;

procedure TMapChunk.SetLook(const B: TGeomBatch; const Sec: Integer);
var
  S: TDoomSector;
begin
  S := FOwner.Map.Sectors[Sec];
  if S.HasColor then
    B.CurColor := Vector4(S.LightColor, 1)
  else
    B.CurColor := Vector4(1, 1, 1, 1);
  if S.HasFade then
    B.CurFade := Vector4(S.FadeColor, FogDensity(S.LightLevel))
  else
    B.CurFade := TVector4.Zero;
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
  SwitchLine, DynSide: Integer;
  FloorZ, CeilZ, OFloorZ, OCeilZ: Single;
  TexTopZ, ZB, ZT, OpenBottom, OpenTop, MidHeight: Single;
  Passable: Boolean;
  Rate: TVector2;
  B: TGeomBatch;
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
  Light := Vector2(SideLightLevel(Sd, Map.Sectors[Sec].LightLevel), DoomLightWall);
  if VA.Y = VB.Y then Light.Y := DoomLightWall - 1
  else if VA.X = VB.X then Light.Y := DoomLightWall + 1;

  U0 := Sd.XOffset;
  U1 := Sd.XOffset + L.Length;
  Rate := Map.SideScroll[L.Side[Side]];
  if Map.SideDynamic[L.Side[Side]] then DynSide := L.Side[Side] else DynSide := -1;
  { Switches get a private batch per line so SW1 -> SW2 flips only that wall. }
  SwitchLine := -1;
  if (Side = 0) and (L.Special <> 0) and
     ((FOwner.Graphics.SwitchPartner(Sd.MiddleTex) <> '') or (FOwner.Graphics.SwitchPartner(Sd.UpperTex) <> '') or
      (FOwner.Graphics.SwitchPartner(Sd.LowerTex) <> '')) then
    SwitchLine := Line;

  FloorZ := Map.Sectors[Sec].FloorHeight;
  CeilZ := Map.Sectors[Sec].CeilingHeight;

  if Other < 0 then
  begin
    { One-sided wall: the middle texture from floor to ceiling. }
    Img := FOwner.Graphics.Texture(Sd.MiddleTex);
    if Img = nil then Exit;
    if (L.Flags and ML_DONTPEGBOTTOM) <> 0 then
      TexTopZ := FloorZ + Img.Height / ScaleOr1(Sd.PartScaleY[1]) + Sd.YOffset + Sd.PartOffsetY[1]
    else
      TexTopZ := CeilZ + Sd.YOffset + Sd.PartOffsetY[1];
    B := Batch(Img, false, WallScroll(Rate, Img), SwitchLine, 1, stSide, DynSide);
    SetLook(B, Sec);
    EmitWall(B, VA.X, VA.Y, VB.X, VB.Y, FloorZ, CeilZ, U0 + Sd.PartOffsetX[1], U1 + Sd.PartOffsetX[1],
      TexTopZ, Img, Light, ScaleOr1(Sd.PartScaleX[1]), ScaleOr1(Sd.PartScaleY[1]));
    Exit;
  end;

  OFloorZ := Map.Sectors[Other].FloorHeight;
  OCeilZ := Map.Sectors[Other].CeilingHeight;

  { Lower wall: from our floor up to the neighbour's (higher) floor. }
  Img := FOwner.Graphics.Texture(Sd.LowerTex);
  if Img <> nil then
  begin
    if (L.Flags and ML_DONTPEGBOTTOM) <> 0 then
      TexTopZ := CeilZ + Sd.YOffset + Sd.PartOffsetY[2]
    else
      TexTopZ := OFloorZ + Sd.YOffset + Sd.PartOffsetY[2];
    ZB := FloorZ;
    ZT := Min(OFloorZ, CeilZ);
    B := Batch(Img, false, WallScroll(Rate, Img), SwitchLine, 1, stSide, DynSide);
    SetLook(B, Sec);
    EmitWall(B, VA.X, VA.Y, VB.X, VB.Y, ZB, ZT, U0 + Sd.PartOffsetX[2], U1 + Sd.PartOffsetX[2],
      TexTopZ, Img, Light, ScaleOr1(Sd.PartScaleX[2]), ScaleOr1(Sd.PartScaleY[2]));
  end;

  { Upper wall: from the neighbour's (lower) ceiling up to our ceiling.
    Skipped when both ceilings are sky (Doom's sky hack). }
  if not (Map.HasSkyCeiling(Sec) and Map.HasSkyCeiling(Other)) then
  begin
    Img := FOwner.Graphics.Texture(Sd.UpperTex);
    if Img <> nil then
    begin
      if (L.Flags and ML_DONTPEGTOP) <> 0 then
        TexTopZ := CeilZ + Sd.YOffset + Sd.PartOffsetY[0]
      else
        TexTopZ := OCeilZ + Img.Height / ScaleOr1(Sd.PartScaleY[0]) + Sd.YOffset + Sd.PartOffsetY[0];
      ZB := Max(OCeilZ, FloorZ);
      ZT := CeilZ;
      B := Batch(Img, false, WallScroll(Rate, Img), SwitchLine, 1, stSide, DynSide);
      SetLook(B, Sec);
      EmitWall(B, VA.X, VA.Y, VB.X, VB.Y, ZB, ZT, U0 + Sd.PartOffsetX[0], U1 + Sd.PartOffsetX[0],
        TexTopZ, Img, Light, ScaleOr1(Sd.PartScaleX[0]), ScaleOr1(Sd.PartScaleY[0]));
    end;
  end;

  { Masked middle texture (grates, vines...): one texture height, clipped
    to the opening, not repeated vertically. }
  Img := FOwner.Graphics.Texture(Sd.MiddleTex);
  if Img <> nil then
  begin
    OpenBottom := Max(FloorZ, OFloorZ);
    OpenTop := Min(CeilZ, OCeilZ);
    { The texture's height in map units (UDMF scale). }
    MidHeight := Img.Height / ScaleOr1(Sd.PartScaleY[1]);
    if (L.Flags and ML_DONTPEGBOTTOM) <> 0 then
      TexTopZ := OpenBottom + MidHeight + Sd.YOffset + Sd.PartOffsetY[1]
    else
      TexTopZ := OpenTop + Sd.YOffset + Sd.PartOffsetY[1];
    ZB := Max(OpenBottom, TexTopZ - MidHeight);
    ZT := Min(OpenTop, TexTopZ);
    Passable := (L.Flags and ML_BLOCKING) = 0;
    B := Batch(Img, Passable, WallScroll(Rate, Img), SwitchLine, Map.LineAlpha[Line], stSide, DynSide);
    SetLook(B, Sec);
    EmitWall(B, VA.X, VA.Y, VB.X, VB.Y, ZB, ZT, U0 + Sd.PartOffsetX[1], U1 + Sd.PartOffsetX[1],
      TexTopZ, Img, Light, ScaleOr1(Sd.PartScaleX[1]), ScaleOr1(Sd.PartScaleY[1]));
  end;
end;

{ A flat's texture coordinates at P (64-unit tiles) with UDMF's
  rotation (degrees, about the map's origin), panning and scale. }
function FlatTexCoord(const P: TVector2; const Look: TPlaneLook): TVector2;
var
  Q: TVector2;
  A, C, Sn: Single;
begin
  Q := P;
  if Look.Rotation <> 0 then
  begin
    A := DegToRad(Look.Rotation);
    C := Cos(A);
    Sn := Sin(A);
    Q := Vector2(P.X * C + P.Y * Sn, -P.X * Sn + P.Y * C);
  end;
  Result := Vector2((Q.X + Look.PanX) * ScaleOr1(Look.ScaleX) / 64, (Q.Y + Look.PanY) * ScaleOr1(Look.ScaleY) / 64);
end;

procedure TMapChunk.EmitFlats(const Sub: Integer);
var
  Map: TDoomMap;
  B: TGeomBatch;
  S: TDoomSubsector;
  Sec, DynSec: Integer;
  Light: TVector2;
  Img: TDoomImage;
  Pts, DoomPts: array of TVector3;
  SkyName: String;
  SkyFlip: Boolean;
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
  { Boom's light transfers (213 floor, 261 ceiling): another sector's
    light; UDMF's lightfloor on top. }
  if Map.FloorLightSector[Sec] >= 0 then
    Light := Vector2(Map.Sectors[Map.FloorLightSector[Sec]].LightLevel, DoomLightPlane)
  else
    Light := Vector2(Map.Sectors[Sec].LightLevel, DoomLightPlane);
  Light.X := PlaneLightLevel(Map.Sectors[Sec].FloorLook, Round(Light.X));
  if Img <> nil then
  begin
    Z := Map.Sectors[Sec].FloorHeight;
    for I := 0 to N - 1 do
    begin
      Pts[I] := DoomToCge(S.Poly[I].X, S.Poly[I].Y, Z);
      Tex[I] := FlatTexCoord(S.Poly[I], Map.Sectors[Sec].FloorLook);
    end;
    if Map.FloorDynamic[Sec] then DynSec := Sec else DynSec := -1;
    B := Batch(Img, false, FlatScroll(Map.FloorScroll[Sec], Img), -1, 1, stFloor, DynSec);
    SetLook(B, Sec);
    B.AddPolygon(Pts, Tex, Light, TileOf(B, Img));
  end;

  { A sky ceiling with a sky of its own (per-sector skies): drawn with
    that sky, mapped by the view direction. Other sky ceilings are not
    drawn: the cylinder shows through. }
  if (FEmitMode <> emCollision) and FOwner.SectorOwnSky(Sec, SkyName, SkyFlip) then
  begin
    Img := FOwner.Graphics.Texture(SkyName);
    Z := Map.Sectors[Sec].CeilingHeight;
    SetLength(DoomPts, N);
    for I := 0 to N - 1 do
    begin
      Pts[I] := DoomToCge(S.Poly[N - 1 - I].X, S.Poly[N - 1 - I].Y, Z);
      DoomPts[I] := Vector3(S.Poly[N - 1 - I].X, S.Poly[N - 1 - I].Y, Z);
    end;
    SkyBatch(Img, SkyFlip).AddSkyPolygon(Pts, DoomPts, Vector2(255, DoomLightFullBright));
  end;
  { Ceiling: reversed order = facing down. Sky ceilings are not drawn. }
  if not Map.HasSkyCeiling(Sec) then
  begin
    Img := FOwner.Graphics.Flat(Map.Sectors[Sec].CeilingTex);
    if Map.CeilingLightSector[Sec] >= 0 then
      Light := Vector2(Map.Sectors[Map.CeilingLightSector[Sec]].LightLevel, DoomLightPlane)
    else
      Light := Vector2(Map.Sectors[Sec].LightLevel, DoomLightPlane);
    Light.X := PlaneLightLevel(Map.Sectors[Sec].CeilingLook, Round(Light.X));
    if Img <> nil then
    begin
      Z := Map.Sectors[Sec].CeilingHeight;
      for I := 0 to N - 1 do
      begin
        Pts[I] := DoomToCge(S.Poly[N - 1 - I].X, S.Poly[N - 1 - I].Y, Z);
        Tex[I] := FlatTexCoord(S.Poly[N - 1 - I], Map.Sectors[Sec].CeilingLook);
      end;
      if Map.CeilingDynamic[Sec] then DynSec := Sec else DynSec := -1;
      B := Batch(Img, false, FlatScroll(Map.CeilingScroll[Sec], Img), -1, 1, stCeiling, DynSec);
      SetLook(B, Sec);
      B.AddPolygon(Pts, Tex, Light, TileOf(B, Img));
    end;
  end;
end;

function TMapChunk.SkyBatch(const Img: TDoomImage; const Flipped: Boolean): TGeomBatch;
var
  Key: String;
begin
  Key := 'sky' + Img.Url + BoolToStr(Flipped, 'F', '');
  if not FBatches.TryGetValue(Key, Result) then
  begin
    Result := TGeomBatch.Create;
    Result.Key := Key;
    Result.AtlasPage := -1;
    Result.Img := Img;
    Result.Alpha := 1;
    Result.DynIndex := -1;
    { Drawn only, like the cylinder: sky ceilings never collided. }
    Result.Passable := true;
    Result.IsSky := true;
    Result.SkyFlipped := Flipped;
    FBatches.Add(Key, Result);
  end;
end;

function TMapChunk.IsWaterLine(const Line: Integer): Boolean;
var
  Map: TDoomMap;
begin
  Map := FOwner.Map;
  Result := ((Map.Linedefs[Line].FrontSector >= 0) and (Map.HeightSec[Map.Linedefs[Line].FrontSector] >= 0)) or
    ((Map.Linedefs[Line].BackSector >= 0) and (Map.HeightSec[Map.Linedefs[Line].BackSector] >= 0));
end;

function TMapChunk.IsWaterSub(const Sub: Integer): Boolean;
begin
  Result := (FOwner.Map.Subsectors[Sub].Sector >= 0) and
    (FOwner.Map.HeightSec[FOwner.Map.Subsectors[Sub].Sector] >= 0);
end;

procedure TMapChunk.Generate;
var
  B: TGeomBatch;
  I: Integer;
  NeedRebuild, HasWater: Boolean;
begin
  for B in FBatches.Values do
    B.Reset;
  FDiscard.Reset;
  HasWater := false;
  FEmitMode := emNormal;
  for I := 0 to High(Lines) do
    if IsWaterLine(Lines[I].Line) then
      HasWater := true
    else
      EmitLineSide(Lines[I].Line, Lines[I].Side);
  for I := 0 to High(Subsectors) do
    if IsWaterSub(Subsectors[I]) then
      HasWater := true
    else
      EmitFlats(Subsectors[I]);
  if HasWater then
  begin
    { Boom's deep water: the real heights collide, the fake ones (the
      sectors temporarily changed by ApplyFakeSectors) are drawn. }
    FEmitMode := emCollision;
    for I := 0 to High(Lines) do
      if IsWaterLine(Lines[I].Line) then EmitLineSide(Lines[I].Line, Lines[I].Side);
    for I := 0 to High(Subsectors) do
      if IsWaterSub(Subsectors[I]) then EmitFlats(Subsectors[I]);
    FEmitMode := emVisual;
    FOwner.ApplyFakeSectors;
    try
      for I := 0 to High(Lines) do
        if IsWaterLine(Lines[I].Line) then EmitLineSide(Lines[I].Line, Lines[I].Side);
      for I := 0 to High(Subsectors) do
        if IsWaterSub(Subsectors[I]) then EmitFlats(Subsectors[I]);
    finally
      FOwner.RestoreSectors;
      FEmitMode := emNormal;
    end;
  end;

  NeedRebuild := not FBuilt;
  if FBuilt then
    for B in FBatches.Values do
      if (B.Shape = nil) or (B.CommittedVertices <> B.Coords.Count) then
        NeedRebuild := true;

  if NeedRebuild then
  begin
    FRootSolid := TX3DRootNode.Create;
    FRootPassable := TX3DRootNode.Create;
    FRootCollision := TX3DRootNode.Create;
    FRootSolid.AddChildren(DoomLightingInstance.GeometryEffect);
    FRootPassable.AddChildren(DoomLightingInstance.GeometryEffect);
    for B in FBatches.Values do
      B.DropNodes;
    for B in FBatches.Values do
      if B.Coords.Count > 0 then
      begin
        B.CreateNodes;
        if B.CollisionOnly then
          FRootCollision.AddChildren(B.Shape)
        else if B.Passable then
          FRootPassable.AddChildren(B.Shape)
        else
          FRootSolid.AddChildren(B.Shape);
      end;
    SceneSolid.Load(FRootSolid, true);
    ScenePassable.Load(FRootPassable, true);
    SceneCollision.Load(FRootCollision, true);
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

procedure TMapChunk.UpdateScroll(const Tics: Single; const DoomEye: TVector3);
var
  B: TGeomBatch;
  T: TVector2;
  Map: TDoomMap;
begin
  Map := FOwner.Map;
  for B in FBatches.Values do
    if B.IsSky and (B.SkyEye <> nil) then
      B.SkyEye.Send(DoomEye);
  { Only the fraction matters (the textures repeat), and keeps the
    numbers small. }
  for B in FBatches.Values do
    if B.Scrolling and (B.TexTransform <> nil) then
    begin
      if B.DynIndex < 0 then
        T := B.ScrollPerTic * Tics
      else
        case B.DynTarget of
          stSide: T := WallScroll(Map.SideOffset[B.DynIndex], B.Img);
          stFloor: T := FlatScroll(Map.FloorOffset[B.DynIndex], B.Img);
          else T := FlatScroll(Map.CeilingOffset[B.DynIndex], B.Img);
        end;
      B.TexTransform.Translation := Vector2(Frac(T.X), Frac(T.Y));
    end;
end;

{ TDoomGeometry -------------------------------------------------------------- }

constructor TDoomGeometry.Create(const AMap: TDoomMap; const AGraphics: TDoomGraphics;
  const DynamicSectors: array of Boolean; const SkyTexture: String; const SkyFlipped: Boolean;
  const MapSky: String);
var
  I, Own: Integer;
  C: TMapChunk;
  Tex: String;
  Flip: Boolean;
begin
  inherited Create;
  FMap := AMap;
  FGraphics := AGraphics;
  FSkyTexture := UpperCase(SkyTexture);
  FSkyFlipped := SkyFlipped;
  FMapSky := UpperCase(MapSky);
  Own := 0;
  for I := 0 to High(FMap.Sectors) do
    if SectorOwnSky(I, Tex, Flip) then Inc(Own);
  if Own > 0 then
    WritelnLog('Geometry', '%s: %d sky sectors show their own sky', [FMap.Name, Own]);
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
  BuildSky(SkyTexture, SkyFlipped);
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
    if (Img <> nil) and (Img.AnimGroup = nil) and (FGraphics.SwitchPartner(Img.Name) = '') and
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
    { A light transfer's source changes these flats too. }
    if FMap.FloorLightSector[Sec] >= 0 then Dependency(FMap.FloorLightSector[Sec], C);
    if FMap.CeilingLightSector[Sec] >= 0 then Dependency(FMap.CeilingLightSector[Sec], C);
    { Deep water: drawn at the control sector's heights. }
    if FMap.HeightSec[Sec] >= 0 then Dependency(FMap.HeightSec[Sec], C);
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
      if (Front >= 0) and (FMap.HeightSec[Front] >= 0) then Dependency(FMap.HeightSec[Front], C);
      if (Back >= 0) and (FMap.HeightSec[Back] >= 0) then Dependency(FMap.HeightSec[Back], C);
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

procedure TDoomGeometry.BuildSky(const SkyTexture: String; const Flipped: Boolean);
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

  { The texture column (0..1 in a tile), mirrored for Boom's 272. }
  function SkyU(const U: Single): Single;
  begin
    if Flipped then Result := 1 - U else Result := U;
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
            Vector2(SkyU((I + 1) / Segments), V1),
            Vector2(SkyU(I / Segments), V1),
            Vector2(SkyU(I / Segments), V0),
            Vector2(SkyU((I + 1) / Segments), V0),
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
    C.SceneCollision.Name := Format('Chunk%d_Collision', [I]);
    Parent.Add(C.SceneSolid);
    Parent.Add(C.ScenePassable);
    Parent.Add(C.SceneCollision);
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

function TDoomGeometry.SectorOwnSky(const Sec: Integer; out Texture: String; out Flipped: Boolean): Boolean;
begin
  Texture := '';
  Flipped := false;
  Result := false;
  if (Sec < 0) or (Sec > High(FMap.Sectors)) or not FMap.HasSkyCeiling(Sec) then Exit;
  if (Sec <= High(FMap.SectorSky)) and (FMap.SectorSky[Sec] <> '') then
  begin
    Texture := FMap.SectorSky[Sec];
    Flipped := FMap.SectorSkyFlipped[Sec];
  end else
    Texture := FMapSky;
  if (Texture = '') or (FGraphics.Texture(Texture) = nil) then Exit(false);
  Result := (Texture <> FSkyTexture) or (Flipped <> FSkyFlipped);
end;

procedure TDoomGeometry.SetWaterView(const Value: TWaterView);
var
  I: Integer;
begin
  if FWaterView = Value then Exit;
  FWaterView := Value;
  for I := 0 to High(FMap.HeightSec) do
    if FMap.HeightSec[I] >= 0 then
      SectorChanged(I);
end;

procedure TDoomGeometry.ApplyFakeSectors;
var
  I, H: Integer;
  C: TDoomSector;
begin
  SetLength(FSavedSectors, Length(FMap.Sectors));
  for I := 0 to High(FMap.Sectors) do
  begin
    H := FMap.HeightSec[I];
    if H < 0 then Continue;
    FSavedSectors[I] := FMap.Sectors[I];
    C := FMap.Sectors[H];
    { Boom's R_FakeFlat. }
    if FWaterView = wvUnder then
    begin
      FMap.Sectors[I].CeilingHeight := C.FloorHeight - 1;
      FMap.Sectors[I].FloorTex := C.FloorTex;
      if FMap.HasSkyCeiling(H) then
      begin
        FMap.Sectors[I].FloorHeight := FMap.Sectors[I].CeilingHeight + 1;
        FMap.Sectors[I].CeilingTex := C.FloorTex;
      end else
        FMap.Sectors[I].CeilingTex := C.CeilingTex;
      FMap.Sectors[I].LightLevel := C.LightLevel;
    end else
    if (FWaterView = wvAbove) and (FSavedSectors[I].CeilingHeight > C.CeilingHeight) then
    begin
      FMap.Sectors[I].CeilingHeight := C.CeilingHeight;
      FMap.Sectors[I].FloorHeight := C.CeilingHeight + 1;
      FMap.Sectors[I].FloorTex := C.CeilingTex;
      FMap.Sectors[I].CeilingTex := C.CeilingTex;
      FMap.Sectors[I].LightLevel := C.LightLevel;
    end else
    begin
      FMap.Sectors[I].FloorHeight := C.FloorHeight;
      FMap.Sectors[I].CeilingHeight := C.CeilingHeight;
    end;
  end;
end;

procedure TDoomGeometry.RestoreSectors;
var
  I: Integer;
begin
  for I := 0 to High(FMap.Sectors) do
    if (FMap.HeightSec[I] >= 0) and (I <= High(FSavedSectors)) then
      FMap.Sectors[I] := FSavedSectors[I];
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
  { FScrollOffset counts tics (35 a second); each scrolling batch knows
    its texture translation a tic. }
  FScrollOffset := FScrollOffset + SecondsPassed * 35;
  for C in FChunks do
    C.UpdateScroll(FScrollOffset, CgeToDoom(CameraPosition));
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

begin
  Sd := FMap.Linedefs[Line].Side[0];
  if Sd < 0 then Exit;
  { Find which of the three textures is the switch and flip it. }
  Name := FMap.Sidedefs[Sd].MiddleTex;
  if FGraphics.SwitchPartner(Name) = '' then Name := FMap.Sidedefs[Sd].UpperTex;
  if FGraphics.SwitchPartner(Name) = '' then Name := FMap.Sidedefs[Sd].LowerTex;
  Other := FGraphics.SwitchPartner(Name);
  if (Other = '') or not FGraphics.HasTexture(Other) then Exit;
  WritelnLog('Switch', 'line %d: %s -> %s', [Line, Name, Other]);
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
