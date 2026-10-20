{ A Doom level's geometry as a standard 3D file, for Blender, other
  engines or the CGE editor: glTF 2.0 (.gltf with a .bin and PNG
  textures) or X3D (.x3d, CGE's own scene format, written by CGE's
  SaveNode). The walls and flats are the game's own (DoomGeometry, built
  without the texture atlas, so each texture is one material), the light
  levels become vertex colours on unlit materials (glTF's
  KHR_materials_unlit), masked textures (grates, fences) alpha-tested and
  Boom's translucent ones blended. 1 unit = 1 Doom unit (the player is 56
  tall), Y up like CGE. The sky and the things are not exported.

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

uses Math, Generics.Collections, FpJson,
  CastleVectors, CastleImages, CastleLog, CastleUriUtils, CastleUtils, CastleStringUtils,
  X3DNodes, X3DLoad, CastleRenderOptions,
  DoomGeometry;

type
  { All triangles of one texture and blending, from every chunk. }
  TExportGroup = class
    Img: TDoomImage;
    Alpha: Single;
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
      if G.Img.HasAlpha then
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
      Geo.Solid := not (G.Img.HasAlpha or (G.Alpha < 1));
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
  Triangles: Integer;
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
      WritelnLog('Export', '%s: %d triangles in %d materials to %s', [Map.Name, Triangles, Groups.Count, FileName]);
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
