{ A Doom level's geometry as a standard 3D file, for Blender, other
  engines or the CGE editor: glTF 2.0 (.gltf with a .bin and PNG
  textures) or X3D (.x3d, CGE's own scene format, written by CGE's
  SaveNode). The walls and flats are the game's own (DoomGeometry, built
  without the texture atlas, so each texture is one material), the light
  levels become vertex colours on unlit materials (glTF's
  KHR_materials_unlit), masked textures (grates, fences) alpha-tested and
  Boom's translucent ones blended. 1 unit = 1 Doom unit (the player is 56
  tall), Y up like CGE. The things a single-player game on the middle
  skill starts with are two crossed quads each with their front sprite
  (glTF has no billboards), lit by their sector; the sky is a cylinder
  around the map with the sky texture wrapped four times.

  The map editor exports what it edits (ExportEditedLevel, F3 / F4),
  --export-gltf / --export-x3d MAP FILE any map of the WADs, and the
  "Doom Map" component (TDoomMapTransform.ExportGltf / ExportX3D) the
  map it shows. }
unit DoomExport;

interface

uses SysUtils, Classes,
  DoomWad, DoomGraphics, DoomMap, DoomEditMap;

{ Write Map's geometry to FileName (.gltf when Gltf, else .x3d), textures
  as PNG files in FileName's directory, in "<name>_textures". False with
  Error when it cannot. }
function ExportMapGeometry(const Map: TDoomMap; const Graphics: TDoomGraphics;
  const FileName: String; const Gltf: Boolean; out Error: String): Boolean;

{ A map of the loaded WADs. }
function ExportLevel(const Wad: TDoomWad; const Graphics: TDoomGraphics; const MapName: String;
  const FileName: String; const Gltf: Boolean; out Error: String): Boolean;

{ The editor's map (its PWAD stacked on Wad while exporting). }
function ExportEditedLevel(const Wad: TDoomWad; const Graphics: TDoomGraphics; const Edit: TDoomEditMap;
  const FileName: String; const Gltf: Boolean; out Error: String): Boolean;

implementation

uses Math, Generics.Collections, FpJson, DoomLighting, DoomThings,
  CastleVectors, CastleImages, CastleLog, CastleUriUtils, CastleUtils, CastleStringUtils,
  X3DNodes, X3DLoad, CastleRenderOptions,
  DoomGeometry;

type
  { All triangles of one texture and blending, from every chunk. }
  TExportGroup = class
    Img: TDoomImage;
    Alpha: Single;
    { Sprites and the sky: seen from both sides. }
    DoubleSided: Boolean;
    Positions: TVector3List;
    TexCoords: TVector2List;
    Colors: TVector3List;
    Indices: TInt32List;
    constructor Create;
    destructor Destroy; override;
  end;

  TExportGroupList = {$ifdef FPC}specialize{$endif} TObjectList<TExportGroup>;

constructor TExportGroup.Create;
begin
  inherited;
  Positions := TVector3List.Create;
  TexCoords := TVector2List.Create;
  Colors := TVector3List.Create;
  Indices := TInt32List.Create;
end;

destructor TExportGroup.Destroy;
begin
  FreeAndNil(Positions);
  FreeAndNil(TexCoords);
  FreeAndNil(Colors);
  FreeAndNil(Indices);
  inherited;
end;

{ The brightness of a vertex from DoomGeometry's light attribute (level,
  kind: walls get Doom's fake contrast, DoomLightFullBright is full). }
function LightColor(const Level, Kind: Single): TVector3;
var
  L: Single;
begin
  if Kind >= 20 then
    L := 1
  else
  begin
    L := Level;
    { A brightmap's flag on the light (DoomLighting). }
    if L >= BrightmapLightFlag then L := L - BrightmapLightFlag;
    if Kind < 10 then
      L := L + (Kind - 0) * 16;
    L := EnsureRange(L / 255, 0.05, 1);
  end;
  Result := Vector3(L, L, L);
end;

procedure CollectGroups(const Geometry: TDoomGeometry; const Groups: TExportGroupList);
var
  C: TMapChunk;
  B: TGeomBatch;
  G, Found: TExportGroup;
  I, Base: Integer;
begin
  for C in Geometry.Chunks do
    for B in C.Batches.Values do
    begin
      if (B.Img = nil) or B.CollisionOnly or B.IsSky or (B.Indices.Count = 0) then Continue;
      Found := nil;
      for G in Groups do
        if (G.Img = B.Img) and (G.Alpha = B.Alpha) then
        begin
          Found := G;
          Break;
        end;
      if Found = nil then
      begin
        Found := TExportGroup.Create;
        Found.Img := B.Img;
        Found.Alpha := B.Alpha;
        Groups.Add(Found);
      end;
      Base := Found.Positions.Count;
      Found.Positions.AddRange(B.Coords);
      Found.TexCoords.AddRange(B.TexCoords);
      for I := 0 to B.Coords.Count - 1 do
        Found.Colors.Add(LightColor(B.Lights[I * 2], B.Lights[I * 2 + 1]));
      for I := 0 to B.Indices.Count - 1 do
        Found.Indices.Add(Base + B.Indices[I]);
    end;
end;

function GroupFor(const Groups: TExportGroupList; const Img: TDoomImage): TExportGroup;
var
  G: TExportGroup;
begin
  for G in Groups do
    if (G.Img = Img) and (G.Alpha = 1) and G.DoubleSided then
      Exit(G);
  Result := TExportGroup.Create;
  Result.Img := Img;
  Result.Alpha := 1;
  Result.DoubleSided := true;
  Groups.Add(Result);
end;

procedure AddQuad(const G: TExportGroup; const A, B, C, D: TVector3; const U0, U1, V0, V1: Single;
  const Color: TVector3);
var
  Base: Integer;
begin
  Base := G.Positions.Count;
  G.Positions.Add(A); G.Positions.Add(B); G.Positions.Add(C); G.Positions.Add(D);
  G.TexCoords.Add(Vector2(U0, V0)); G.TexCoords.Add(Vector2(U1, V0));
  G.TexCoords.Add(Vector2(U1, V1)); G.TexCoords.Add(Vector2(U0, V1));
  G.Colors.Add(Color); G.Colors.Add(Color); G.Colors.Add(Color); G.Colors.Add(Color);
  G.Indices.Add(Base); G.Indices.Add(Base + 1); G.Indices.Add(Base + 2);
  G.Indices.Add(Base); G.Indices.Add(Base + 2); G.Indices.Add(Base + 3);
end;

{ The things of a single-player game on skill 3, as two crossed quads
  with their front sprite (rotation 1, or the one for every angle),
  placed by the sprite's offsets. }
function CollectThings(const Map: TDoomMap; const Graphics: TDoomGraphics; const Groups: TExportGroupList): Integer;
var
  T: TDoomThing;
  Info: PThingInfo;
  Img: TDoomImage;
  Mirror: Boolean;
  Sec, K: Integer;
  Z, Top, Bottom, Left, Right, Angle, U0, U1: Single;
  Dir: TVector2;
  Color: TVector3;
  G: TExportGroup;
begin
  Result := 0;
  for T in Map.Things do
  begin
    if ((T.Flags and MTF_NOTSINGLE) <> 0) or ((T.Flags and MTF_NORMAL) = 0) then Continue;
    Info := FindThingInfo(T.TypeNum);
    if (Info = nil) or (Info^.Kind in [tkNone, tkPlayerStart, tkTeleportDest, tkInvisible, tkBossSpot]) then
      Continue;
    if Info^.IdleFrames = '' then Continue;
    Img := Graphics.Sprite(Info^.Sprite, Info^.IdleFrames[1], 1, Mirror);
    if (Img = nil) or (Img.Image = nil) then Continue;
    Sec := Map.SectorAt(T.X, T.Y);
    if Sec < 0 then Continue;
    if Info^.Hanging then
      Z := Map.CeilingAt(Sec, T.X, T.Y) - Info^.Height
    else
      Z := Map.FloorAt(Sec, T.X, T.Y);
    { Doom draws a sprite's top TopOffset above the thing, its left
      LeftOffset to the left of it. }
    Top := Z + Img.TopOffset;
    Bottom := Top - Img.Height;
    Left := -Img.LeftOffset;
    Right := Img.Width - Img.LeftOffset;
    if Mirror then
    begin
      U0 := 1;
      U1 := 0;
    end else
    begin
      U0 := 0;
      U1 := 1;
    end;
    Color := LightColor(Map.Sectors[Sec].LightLevel, 10);
    G := GroupFor(Groups, Img);
    for K := 0 to 1 do
    begin
      { The first quad faces where the thing looks, the second across it. }
      Angle := DegToRad(T.Angle + 90 + K * 90);
      Dir := Vector2(Cos(Angle), Sin(Angle));
      AddQuad(G,
        DoomToCge(T.X + Dir.X * Left, T.Y + Dir.Y * Left, Bottom),
        DoomToCge(T.X + Dir.X * Right, T.Y + Dir.Y * Right, Bottom),
        DoomToCge(T.X + Dir.X * Right, T.Y + Dir.Y * Right, Top),
        DoomToCge(T.X + Dir.X * Left, T.Y + Dir.Y * Left, Top),
        U0, U1, 0, 1, Color);
    end;
    Inc(Result);
  end;
end;

{ The sky: a cylinder around the map (its middle, half its diagonal and
  a margin away), from the lowest floor to 256 above the highest
  ceiling, the texture four times around. '' when the map has no sky. }
function CollectSky(const Map: TDoomMap; const Graphics: TDoomGraphics; const Groups: TExportGroupList): String;
const
  Segments = 32;
var
  Img: TDoomImage;
  I: Integer;
  HasSky: Boolean;
  MinX, MinY, MaxX, MaxY, MinZ, MaxZ, CX, CY, R, A0, A1: Single;
  V: TDoomVertex;
  G: TExportGroup;
begin
  Result := '';
  HasSky := false;
  for I := 0 to High(Map.Sectors) do
    if Map.HasSkyCeiling(I) then HasSky := true;
  if (not HasSky) or (Length(Map.Vertices) = 0) or (Length(Map.Sectors) = 0) then Exit;
  Img := Graphics.Texture(Graphics.SkyTextureName(Map.Name));
  if (Img = nil) or (Img.Image = nil) then Exit;
  MinX := 1e9; MinY := 1e9; MaxX := -1e9; MaxY := -1e9;
  for V in Map.Vertices do
  begin
    MinX := Min(MinX, V.X); MaxX := Max(MaxX, V.X);
    MinY := Min(MinY, V.Y); MaxY := Max(MaxY, V.Y);
  end;
  MinZ := 1e9; MaxZ := -1e9;
  for I := 0 to High(Map.Sectors) do
  begin
    MinZ := Min(MinZ, Map.Sectors[I].FloorHeight);
    MaxZ := Max(MaxZ, Map.Sectors[I].CeilingHeight);
  end;
  MaxZ := MaxZ + 256;
  CX := (MinX + MaxX) / 2;
  CY := (MinY + MaxY) / 2;
  R := Sqrt(Sqr(MaxX - MinX) + Sqr(MaxY - MinY)) / 2 + 256;
  G := GroupFor(Groups, Img);
  for I := 0 to Segments - 1 do
  begin
    A0 := 2 * Pi * I / Segments;
    A1 := 2 * Pi * (I + 1) / Segments;
    { Seen from inside: the texture runs left to right as the view
      turns clockwise (against Doom's angles). }
    AddQuad(G,
      DoomToCge(CX + R * Cos(A0), CY + R * Sin(A0), MinZ),
      DoomToCge(CX + R * Cos(A1), CY + R * Sin(A1), MinZ),
      DoomToCge(CX + R * Cos(A1), CY + R * Sin(A1), MaxZ),
      DoomToCge(CX + R * Cos(A0), CY + R * Sin(A0), MaxZ),
      4 - 4 * I / Segments, 4 - 4 * (I + 1) / Segments, 0, 1, Vector3(1, 1, 1));
  end;
  Result := Img.Name;
end;

function SafeName(const S: String): String;
var
  I: Integer;
begin
  Result := S;
  for I := 1 to Length(Result) do
    if not CharInSet(Result[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '-']) then
      Result[I] := '_';
end;

{ Write the textures as PNGs; their paths relative to the model. }
procedure WriteTextures(const Groups: TExportGroupList; const Dir, RelDir: String; const Paths: TStrings);
var
  G: TExportGroup;
  Name: String;
begin
  ForceDirectories(Dir);
  for G in Groups do
  begin
    Name := SafeName(G.Img.Name) + '.png';
    if G.Img.Image <> nil then
      SaveImage(G.Img.Image, FilenameToUriSafe(IncludeTrailingPathDelimiter(Dir) + Name));
    Paths.Add(RelDir + '/' + Name);
  end;
end;

procedure WriteGltf(const Groups: TExportGroupList; const FileName: String; const TexturePaths: TStrings;
  const MapName: String);
var
  Root, Asset, Buffer, Node, Mesh, Prim, Attrs, Mat, Pbr, Tex, Img, Acc, View, Ext, Sampler: TJSONObject;
  Buffers, Nodes, Meshes, Prims, Materials, Textures, Images, Accessors, Views, Scenes, Samplers: TJSONArray;
  Bin: TMemoryStream;
  G: TExportGroup;
  I, K, Gi: Integer;
  MinV, MaxV, V: TVector3;
  UV: TVector2;
  BinName, Text: String;
  F: TFileStream;

  function AddView(const Offset, Length, Target: Integer): Integer;
  begin
    View := TJSONObject.Create(['buffer', 0, 'byteOffset', Offset, 'byteLength', Length]);
    if Target <> 0 then View.Add('target', Target);
    Views.Add(View);
    Result := Views.Count - 1;
  end;

  function AddAccessor(const ViewIndex, ComponentType, Count: Integer; const AType: String): Integer;
  begin
    Acc := TJSONObject.Create(['bufferView', ViewIndex, 'componentType', ComponentType,
      'count', Count, 'type', AType]);
    Accessors.Add(Acc);
    Result := Accessors.Count - 1;
  end;

  procedure Align4;
  begin
    while Bin.Size mod 4 <> 0 do Bin.WriteByte(0);
  end;

var
  Offset, PosAcc, UvAcc, ColAcc, IdxAcc: Integer;
  F32: Single;
begin
  Bin := TMemoryStream.Create;
  Root := TJSONObject.Create;
  try
    Asset := TJSONObject.Create(['version', '2.0', 'generator', 'Castle DOOM map export']);
    Root.Add('asset', Asset);
    Root.Add('extensionsUsed', TJSONArray.Create(['KHR_materials_unlit']));
    Scenes := TJSONArray.Create;
    Root.Add('scene', 0);
    Root.Add('scenes', Scenes);
    Nodes := TJSONArray.Create;
    Root.Add('nodes', Nodes);
    Meshes := TJSONArray.Create;
    Root.Add('meshes', Meshes);
    Materials := TJSONArray.Create;
    Root.Add('materials', Materials);
    Textures := TJSONArray.Create;
    Root.Add('textures', Textures);
    Images := TJSONArray.Create;
    Root.Add('images', Images);
    Samplers := TJSONArray.Create;
    Root.Add('samplers', Samplers);
    Accessors := TJSONArray.Create;
    Root.Add('accessors', Accessors);
    Views := TJSONArray.Create;
    Root.Add('bufferViews', Views);
    Buffers := TJSONArray.Create;
    Root.Add('buffers', Buffers);
    { Doom's look: nearest texels, repeating. }
    Sampler := TJSONObject.Create(['magFilter', 9728, 'minFilter', 9984, 'wrapS', 10497, 'wrapT', 10497]);
    Samplers.Add(Sampler);

    Mesh := TJSONObject.Create(['name', MapName]);
    Prims := TJSONArray.Create;
    Mesh.Add('primitives', Prims);
    Meshes.Add(Mesh);
    Node := TJSONObject.Create(['name', MapName, 'mesh', 0]);
    Nodes.Add(Node);
    Scenes.Add(TJSONObject.Create(['nodes', TJSONArray.Create([0])]));

    for Gi := 0 to Groups.Count - 1 do
    begin
      G := Groups[Gi];
      { Positions. }
      Align4;
      Offset := Bin.Position;
      MinV := Vector3(MaxSingle, MaxSingle, MaxSingle);
      MaxV := Vector3(-MaxSingle, -MaxSingle, -MaxSingle);
      for I := 0 to G.Positions.Count - 1 do
      begin
        V := G.Positions[I];
        for K := 0 to 2 do
        begin
          MinV.Data[K] := Min(MinV.Data[K], V.Data[K]);
          MaxV.Data[K] := Max(MaxV.Data[K], V.Data[K]);
        end;
        Bin.WriteBuffer(V, SizeOf(V));
      end;
      PosAcc := AddAccessor(AddView(Offset, Bin.Position - Offset, 34962), 5126, G.Positions.Count, 'VEC3');
      Acc.Add('min', TJSONArray.Create([MinV.X, MinV.Y, MinV.Z]));
      Acc.Add('max', TJSONArray.Create([MaxV.X, MaxV.Y, MaxV.Z]));
      { Texture coordinates: glTF's v runs down the image. }
      Offset := Bin.Position;
      for I := 0 to G.TexCoords.Count - 1 do
      begin
        UV := G.TexCoords[I];
        F32 := UV.X;
        Bin.WriteBuffer(F32, 4);
        F32 := 1 - UV.Y;
        Bin.WriteBuffer(F32, 4);
      end;
      UvAcc := AddAccessor(AddView(Offset, Bin.Position - Offset, 34962), 5126, G.TexCoords.Count, 'VEC2');
      { Light as vertex colours. }
      Offset := Bin.Position;
      for I := 0 to G.Colors.Count - 1 do
      begin
        V := G.Colors[I];
        Bin.WriteBuffer(V, SizeOf(V));
      end;
      ColAcc := AddAccessor(AddView(Offset, Bin.Position - Offset, 34962), 5126, G.Colors.Count, 'VEC3');
      { Indices. }
      Offset := Bin.Position;
      for I := 0 to G.Indices.Count - 1 do
      begin
        K := G.Indices[I];
        Bin.WriteBuffer(K, 4);
      end;
      IdxAcc := AddAccessor(AddView(Offset, Bin.Position - Offset, 34963), 5125, G.Indices.Count, 'SCALAR');

      Img := TJSONObject.Create(['uri', TexturePaths[Gi], 'name', G.Img.Name]);
      Images.Add(Img);
      Tex := TJSONObject.Create(['source', Gi, 'sampler', 0]);
      Textures.Add(Tex);
      Pbr := TJSONObject.Create(['baseColorTexture', TJSONObject.Create(['index', Gi]),
        'metallicFactor', 0.0, 'roughnessFactor', 1.0]);
      Mat := TJSONObject.Create(['name', G.Img.Name, 'pbrMetallicRoughness', Pbr]);
      Ext := TJSONObject.Create(['KHR_materials_unlit', TJSONObject.Create]);
      Mat.Add('extensions', Ext);
      if G.Alpha < 1 then
      begin
        Pbr.Add('baseColorFactor', TJSONArray.Create([1.0, 1.0, 1.0, G.Alpha]));
        Mat.Add('alphaMode', 'BLEND');
        Mat.Add('doubleSided', true);
      end else
      if G.Img.HasAlpha or G.DoubleSided then
      begin
        Mat.Add('alphaMode', 'MASK');
        Mat.Add('alphaCutoff', 0.5);
        Mat.Add('doubleSided', true);
      end;
      Materials.Add(Mat);

      Attrs := TJSONObject.Create(['POSITION', PosAcc, 'TEXCOORD_0', UvAcc, 'COLOR_0', ColAcc]);
      Prim := TJSONObject.Create(['attributes', Attrs, 'indices', IdxAcc, 'material', Gi]);
      Prims.Add(Prim);
    end;

    BinName := ChangeFileExt(ExtractFileName(FileName), '.bin');
    Buffer := TJSONObject.Create(['uri', BinName, 'byteLength', Bin.Size]);
    Buffers.Add(Buffer);
    Bin.SaveToFile(ChangeFileExt(FileName, '.bin'));
    Text := Root.FormatJSON;
    F := TFileStream.Create(FileName, fmCreate);
    try
      if Text <> '' then F.WriteBuffer(Text[1], Length(Text));
    finally
      FreeAndNil(F);
    end;
  finally
    FreeAndNil(Root);
    FreeAndNil(Bin);
  end;
end;

procedure WriteX3d(const Groups: TExportGroupList; const FileName: String; const TexturePaths: TStrings;
  const MapName: String);
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  App: TAppearanceNode;
  Mat: TUnlitMaterialNode;
  Tex: TImageTextureNode;
  Props: TTexturePropertiesNode;
  Geo: TIndexedTriangleSetNode;
  Coord: TCoordinateNode;
  TexCoord: TTextureCoordinateNode;
  Color: TColorNode;
  G: TExportGroup;
  Gi: Integer;
begin
  Root := TX3DRootNode.Create;
  try
    for Gi := 0 to Groups.Count - 1 do
    begin
      G := Groups[Gi];
      Coord := TCoordinateNode.Create;
      Coord.SetPoint(G.Positions);
      TexCoord := TTextureCoordinateNode.Create;
      TexCoord.SetPoint(G.TexCoords);
      Color := TColorNode.Create;
      Color.SetColor(G.Colors);
      Geo := TIndexedTriangleSetNode.Create;
      Geo.Coord := Coord;
      Geo.TexCoord := TexCoord;
      Geo.Color := Color;
      Geo.SetIndex(G.Indices);
      Geo.Solid := not (G.Img.HasAlpha or (G.Alpha < 1) or G.DoubleSided);
      Tex := TImageTextureNode.Create;
      Tex.SetUrl([TexturePaths[Gi]]);
      { Doom's look: nearest texels. }
      Props := TTexturePropertiesNode.Create;
      Props.MagnificationFilter := magNearest;
      Props.MinificationFilter := minNearest;
      Tex.TextureProperties := Props;
      Mat := TUnlitMaterialNode.Create;
      Mat.EmissiveTexture := Tex;
      Mat.Transparency := 1 - G.Alpha;
      App := TAppearanceNode.Create;
      App.Material := Mat;
      if G.Alpha < 1 then
        App.AlphaMode := amBlend
      else if G.Img.HasAlpha then
        App.AlphaMode := amMask;
      Shape := TShapeNode.Create(SafeName(MapName + '_' + G.Img.Name));
      Shape.Appearance := App;
      Shape.Geometry := Geo;
      Root.AddChildren(Shape);
    end;
    SaveNode(Root, FilenameToUriSafe(FileName));
  finally
    FreeAndNil(Root);
  end;
end;

function ExportMapGeometry(const Map: TDoomMap; const Graphics: TDoomGraphics;
  const FileName: String; const Gltf: Boolean; out Error: String): Boolean;
var
  Geometry: TDoomGeometry;
  Groups: TExportGroupList;
  Paths: TStringList;
  OldAtlas: Boolean;
  Dir, RelDir: String;
  Triangles, Things: Integer;
  Sky: String;
  G: TExportGroup;
begin
  Result := false;
  Error := '';
  OldAtlas := UseTextureAtlas;
  UseTextureAtlas := false;
  Geometry := nil;
  Groups := TExportGroupList.Create(true);
  Paths := TStringList.Create;
  try
    try
      Geometry := TDoomGeometry.Create(Map, Graphics, [], Graphics.SkyTextureName(Map.Name), false,
        Graphics.SkyTextureName(Map.Name));
      CollectGroups(Geometry, Groups);
      Things := CollectThings(Map, Graphics, Groups);
      Sky := CollectSky(Map, Graphics, Groups);
      RelDir := ChangeFileExt(ExtractFileName(FileName), '') + '_textures';
      Dir := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FileName))) + RelDir;
      WriteTextures(Groups, Dir, RelDir, Paths);
      if Gltf then
        WriteGltf(Groups, FileName, Paths, Map.Name)
      else
        WriteX3d(Groups, FileName, Paths, Map.Name);
      Triangles := 0;
      for G in Groups do
        Inc(Triangles, G.Indices.Count div 3);
      if Sky = '' then Sky := 'none';
      WritelnLog('Export', '%s: %d triangles in %d materials, %d things, sky %s to %s', [Map.Name, Triangles,
        Groups.Count, Things, Sky, FileName]);
      Result := true;
    except
      on E: Exception do
        Error := E.Message;
    end;
  finally
    FreeAndNil(Geometry);
    FreeAndNil(Paths);
    FreeAndNil(Groups);
    UseTextureAtlas := OldAtlas;
  end;
end;

function ExportLevel(const Wad: TDoomWad; const Graphics: TDoomGraphics; const MapName: String;
  const FileName: String; const Gltf: Boolean; out Error: String): Boolean;
var
  Map: TDoomMap;
begin
  Result := false;
  if Wad.MapNames.IndexOf(UpperCase(MapName)) < 0 then
  begin
    Error := Format('No map %s', [UpperCase(MapName)]);
    Exit;
  end;
  try
    Map := TDoomMap.Create(Wad, MapName);
  except
    on E: Exception do
    begin
      Error := E.Message;
      Exit;
    end;
  end;
  try
    Result := ExportMapGeometry(Map, Graphics, FileName, Gltf, Error);
  finally
    FreeAndNil(Map);
  end;
end;

function ExportEditedLevel(const Wad: TDoomWad; const Graphics: TDoomGraphics; const Edit: TDoomEditMap;
  const FileName: String; const Gltf: Boolean; out Error: String): Boolean;
var
  Data: TMemoryStream;
begin
  Result := false;
  try
    Data := Edit.SaveToWad;
  except
    on E: Exception do
    begin
      Error := E.Message;
      Exit;
    end;
  end;
  try
    RegisterEditedWad(Edit.Name, Data);
  finally
    FreeAndNil(Data);
  end;
  Wad.AddFile(EditedWadUrl(Edit.Name));
  try
    Result := ExportLevel(Wad, Graphics, Edit.Name, FileName, Gltf, Error);
  finally
    Wad.RemoveLastFile;
  end;
end;

end.
