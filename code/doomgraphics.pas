{ Decoding Doom graphics from a WAD into Castle Game Engine images and
  X3D texture nodes: patches (sprites, HUD graphics), composed wall textures
  (PNAMES + TEXTURE1/TEXTURE2), flats (64x64 floors/ceilings) and the
  sprite frame/rotation directory. }
unit DoomGraphics;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleImages, CastleVectors, X3DNodes, CastleRenderOptions,
  DoomWad;

type
  { One decoded Doom graphic. The image rows follow CGE convention
    (row 0 at the bottom); Doom offsets are kept as-is (TopOffset counts
    from the top of the graphic). }
  TAnimGroup = class;

  TDoomImage = class
  public
    Name: String;
    { URL under the "doomgfx:" protocol; CGE's texture cache shares the GL
      texture between all ImageTexture nodes using the same URL. }
    Url: String;
    Image: TRGBAlphaImage;
    Width, Height: Integer;
    LeftOffset, TopOffset: Integer;
    { Any transparent pixel? Then shapes need alpha testing. }
    HasAlpha: Boolean;
    { Animation group (NUKAGE1..3 etc.) this image belongs to, or nil. }
    AnimGroup: TAnimGroup;
    destructor Destroy; override;
    { A new ImageTexture node showing this image. Repeating (walls, flats)
      or clamped (sprites, sky). The caller (its scene) owns the node. }
    function MakeTextureNode(const Clamp: Boolean): TImageTextureNode;
  end;

  TDoomImageDict = {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TDoomImage>;

  TSpriteLumpRef = record
    Lump: Integer;
    Mirror: Boolean;
  end;
  TSpriteDict = {$ifdef FPC}specialize{$endif} TDictionary<String, TSpriteLumpRef>;

  TTextureDef = record
    Name: String;
    Lump: Integer; { TEXTURE1 or TEXTURE2 lump index }
    Offset: Integer; { offset of the maptexture_t inside the lump }
  end;

  TImageTextureNodeList = {$ifdef FPC}specialize{$endif} TList<TImageTextureNode>;

  { Animated texture/flat group (NUKAGE1..3 etc.): every texture node showing
    one of its frames registers here and gets its URL switched as time passes
    (like Doom's P_UpdateSpecials). }
  TAnimGroup = class
    Names: TStringList;
    Frames: array of TDoomImage;
    Nodes: TImageTextureNodeList;
    Current: Integer;
    IsFlat: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Register(const Node: TImageTextureNode);
    procedure Unregister(const Node: TImageTextureNode);
  end;
  TAnimGroupList = {$ifdef FPC}specialize{$endif} TObjectList<TAnimGroup>;

  TDoomGraphics = class
  strict private
    FWad: TDoomWad;
    FPatchNames: array of String;
    FTextureDefs: {$ifdef FPC}specialize{$endif} TDictionary<String, TTextureDef>;
    FTextureOrder: TStringList;
    FFlatLumps: {$ifdef FPC}specialize{$endif} TDictionary<String, Integer>;
    FFlatOrder: TStringList;
    FSprites: TSpriteDict;
    FTextures, FFlats, FPatches: TDoomImageDict;
    FAnimGroups: TAnimGroupList;
    FAnimByName: {$ifdef FPC}specialize{$endif} TDictionary<String, TAnimGroup>;
    FMissing: TDoomImage;
    FPatchStart, FPatchEnd: Integer;
    procedure ReadPNames;
    procedure ReadTextureLump(const LumpName: String);
    procedure IndexFlats;
    procedure IndexSprites;
    procedure SetupAnimations;
    procedure AddAnimRange(const First, Last: String; const IsFlat: Boolean);
    function ComposeTexture(const Def: TTextureDef): TDoomImage;
    function FindPatchLump(const Name: String): Integer;
    function MissingTexture: TDoomImage;
    function ReadGfx(const Url: String; out MimeType: String): TStream;
    procedure ResolveAnim(const Img: TDoomImage; const IsFlat: Boolean);
  public
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;

    { Wall texture by name ('-' and unknown names give nil). }
    function Texture(const Name: String): TDoomImage;
    { Flat (floor/ceiling) by name, nil when unknown. }
    function Flat(const Name: String): TDoomImage;
    { Any patch-format lump (sprite frame, STBAR, TITLEPIC...), nil when missing. }
    function Patch(const LumpName: String): TDoomImage;
    { Sprite frame: Prefix like 'POSS', Frame 'A'..'Z', Rot 1..8 (0 = any).
      Falls back to rotation 0 when a rotation is missing. }
    function Sprite(const Prefix: String; const Frame: Char; const Rot: Integer;
      out Mirror: Boolean): TDoomImage;
    function HasSpriteFrame(const Prefix: String; const Frame: Char): Boolean;
    { Advance animated textures. Call once per Doom tic (35 Hz). }
    procedure AnimationTic(const Tic: Int64);
    { Does the WAD know this wall texture name? }
    function HasTexture(const Name: String): Boolean;
    { Sky texture for the given map (SKY1..SKY4 or Doom 2 ranges). }
    function SkyTextureName(const MapName: String): String;
    property Wad: TDoomWad read FWad;
  end;

implementation

uses Math, CastleLog, CastleStringUtils, CastleUtils, CastleDownload;

{ TDoomImage ----------------------------------------------------------------- }

destructor TDoomImage.Destroy;
begin
  FreeAndNil(Image);
  inherited;
end;

function TDoomImage.MakeTextureNode(const Clamp: Boolean): TImageTextureNode;
var
  Props: TTexturePropertiesNode;
begin
  Result := TImageTextureNode.Create(Name);
  Result.SetUrl([Url]);
  Result.RepeatS := not Clamp;
  Result.RepeatT := not Clamp;
  Props := TTexturePropertiesNode.Create;
  { Doom look: crisp texels up close, mipmaps + anisotropy for far floors. }
  Props.MagnificationFilter := magNearest;
  Props.MinificationFilter := minLinearMipmapLinear;
  Props.GenerateMipMaps := true;
  Props.AnisotropicDegree := 8;
  if Clamp then
  begin
    Props.BoundaryModeS := bmClampToEdge;
    Props.BoundaryModeT := bmClampToEdge;
  end else
  begin
    Props.BoundaryModeS := bmRepeat;
    Props.BoundaryModeT := bmRepeat;
  end;
  Result.TextureProperties := Props;
  if AnimGroup <> nil then
    AnimGroup.Register(Result);
end;

{ TAnimGroup ----------------------------------------------------------------- }

constructor TAnimGroup.Create;
begin
  inherited;
  Names := TStringList.Create;
  Nodes := TImageTextureNodeList.Create;
end;

destructor TAnimGroup.Destroy;
begin
  FreeAndNil(Nodes);
  FreeAndNil(Names);
  inherited;
end;

procedure TAnimGroup.Register(const Node: TImageTextureNode);
begin
  if Nodes.IndexOf(Node) < 0 then
    Nodes.Add(Node);
end;

procedure TAnimGroup.Unregister(const Node: TImageTextureNode);
begin
  Nodes.Remove(Node);
end;

{ patch decoding ------------------------------------------------------------- }

{ Draw a Doom patch lump into Dest at (OriginX, OriginY) (Doom coordinates:
  origin at the top-left, Y grows downward). Clips to the destination. }
procedure DrawPatchInto(const Wad: TDoomWad; const Dest: TRGBAlphaImage;
  const Lump: PByte; const LumpSize: Integer; const OriginX, OriginY: Integer);
var
  W, H, X, Y, ColOfs, TopDelta, Len, I, DX, DY: Integer;
  Col: PByte;
  Pix: PVector4Byte;
begin
  if LumpSize < 8 then Exit;
  W := PInt16(Lump)^;
  H := PInt16(Lump + 2)^;
  if (W <= 0) or (H <= 0) or (LumpSize < 8 + W * 4) then Exit;
  for X := 0 to W - 1 do
  begin
    DX := OriginX + X;
    if (DX < 0) or (DX >= Integer(Dest.Width)) then Continue;
    ColOfs := PInt32(Lump + 8 + X * 4)^;
    if (ColOfs < 0) or (ColOfs >= LumpSize) then Continue;
    Col := Lump + ColOfs;
    while (Col - Lump) < LumpSize do
    begin
      TopDelta := Col^;
      if TopDelta = 255 then Break;
      if (Col - Lump) + 1 >= LumpSize then Break;
      Len := Col[1];
      if (Col - Lump) + 3 + Len > LumpSize then Break;
      for I := 0 to Len - 1 do
      begin
        Y := TopDelta + I;
        DY := OriginY + Y;
        if (DY >= 0) and (DY < Integer(Dest.Height)) then
        begin
          Pix := PVector4Byte(Dest.PixelPtr(DX, Dest.Height - 1 - DY));
          Pix^ := Wad.PaletteColor(Col[3 + I]);
        end;
      end;
      Col := Col + Len + 4;
    end;
  end;
end;

function ImageHasAlpha(const Img: TRGBAlphaImage): Boolean;
var
  I: Integer;
  P: PVector4Byte;
begin
  P := PVector4Byte(Img.RawPixels);
  for I := 0 to Integer(Img.Width * Img.Height) - 1 do
  begin
    if P^.W < 255 then Exit(true);
    Inc(P);
  end;
  Result := false;
end;

{ TDoomGraphics -------------------------------------------------------------- }

constructor TDoomGraphics.Create(const AWad: TDoomWad);
begin
  inherited Create;
  FWad := AWad;
  FTextureDefs := {$ifdef FPC}specialize{$endif} TDictionary<String, TTextureDef>.Create;
  FTextureOrder := TStringList.Create;
  FFlatLumps := {$ifdef FPC}specialize{$endif} TDictionary<String, Integer>.Create;
  FFlatOrder := TStringList.Create;
  FSprites := TSpriteDict.Create;
  FTextures := TDoomImageDict.Create([doOwnsValues]);
  FFlats := TDoomImageDict.Create([doOwnsValues]);
  FPatches := TDoomImageDict.Create([doOwnsValues]);
  FAnimGroups := TAnimGroupList.Create(true);
  FAnimByName := {$ifdef FPC}specialize{$endif} TDictionary<String, TAnimGroup>.Create;

  RegisterUrlProtocol('doomgfx', {$ifdef FPC}@{$endif} ReadGfx, nil);
  FPatchStart := FWad.FindLump('P_START');
  FPatchEnd := FWad.FindLump('P_END');
  ReadPNames;
  ReadTextureLump('TEXTURE1');
  if FWad.HasLump('TEXTURE2') then
    ReadTextureLump('TEXTURE2');
  IndexFlats;
  IndexSprites;
  SetupAnimations;
  WritelnLog('Graphics', '%d wall textures, %d flats, %d sprite lumps, %d animation groups', [
    FTextureDefs.Count, FFlatLumps.Count, FSprites.Count, FAnimGroups.Count]);
end;

destructor TDoomGraphics.Destroy;
begin
  UnregisterUrlProtocol('doomgfx');
  FreeAndNil(FAnimGroups);
  FreeAndNil(FAnimByName);
  FreeAndNil(FMissing);
  FreeAndNil(FTextures);
  FreeAndNil(FFlats);
  FreeAndNil(FPatches);
  FreeAndNil(FSprites);
  FreeAndNil(FFlatLumps);
  FreeAndNil(FFlatOrder);
  FreeAndNil(FTextureDefs);
  FreeAndNil(FTextureOrder);
  inherited;
end;

procedure TDoomGraphics.ReadPNames;
var
  Index, Count, I: Integer;
  P: PByte;
begin
  Index := FWad.LumpIndex('PNAMES');
  P := FWad.LumpPointer(Index);
  Count := PInt32(P)^;
  Count := Min(Count, (FWad.LumpSize(Index) - 4) div 8);
  SetLength(FPatchNames, Count);
  for I := 0 to Count - 1 do
    FPatchNames[I] := DoomName(P + 4 + I * 8);
end;

procedure TDoomGraphics.ReadTextureLump(const LumpName: String);
var
  Index, Count, I, Ofs, Size: Integer;
  P: PByte;
  Def: TTextureDef;
begin
  Index := FWad.LumpIndex(LumpName);
  P := FWad.LumpPointer(Index);
  Size := FWad.LumpSize(Index);
  if Size < 4 then Exit;
  Count := PInt32(P)^;
  for I := 0 to Count - 1 do
  begin
    if 4 + I * 4 + 4 > Size then Break;
    Ofs := PInt32(P + 4 + I * 4)^;
    if (Ofs < 0) or (Ofs + 22 > Size) then Continue;
    Def.Name := DoomName(P + Ofs);
    Def.Lump := Index;
    Def.Offset := Ofs;
    if not FTextureDefs.ContainsKey(Def.Name) then
    begin
      FTextureDefs.Add(Def.Name, Def);
      FTextureOrder.Add(Def.Name);
    end;
  end;
end;

procedure TDoomGraphics.IndexFlats;
var
  S, E, I: Integer;
  N: String;
begin
  S := FWad.FindLump('F_START');
  E := FWad.FindLump('F_END');
  if (S < 0) or (E < 0) then
  begin
    WritelnWarning('Graphics', 'No F_START/F_END markers, no flats');
    Exit;
  end;
  for I := S + 1 to E - 1 do
  begin
    N := FWad.LumpName(I);
    if (FWad.LumpSize(I) >= 4096) and not FFlatLumps.ContainsKey(N) then
    begin
      FFlatLumps.Add(N, I);
      FFlatOrder.Add(N);
    end;
  end;
end;

procedure TDoomGraphics.IndexSprites;

  procedure AddRef(const Key: String; const Lump: Integer; const Mirror: Boolean);
  var
    R: TSpriteLumpRef;
  begin
    R.Lump := Lump;
    R.Mirror := Mirror;
    FSprites.AddOrSetValue(Key, R);
  end;

var
  S, E, I: Integer;
  N: String;
begin
  S := FWad.FindLump('S_START');
  E := FWad.FindLump('S_END');
  if (S < 0) or (E < 0) then
  begin
    WritelnWarning('Graphics', 'No S_START/S_END markers, no sprites');
    Exit;
  end;
  for I := S + 1 to E - 1 do
  begin
    N := FWad.LumpName(I);
    if FWad.LumpSize(I) < 8 then Continue;
    if Length(N) >= 6 then
      AddRef(Copy(N, 1, 6), I, false);
    if Length(N) = 8 then
      AddRef(Copy(N, 1, 4) + Copy(N, 7, 2), I, true);
  end;
end;

procedure TDoomGraphics.AddAnimRange(const First, Last: String; const IsFlat: Boolean);
var
  Order: TStringList;
  I1, I2, I: Integer;
  G: TAnimGroup;
begin
  if IsFlat then Order := FFlatOrder else Order := FTextureOrder;
  I1 := Order.IndexOf(First);
  I2 := Order.IndexOf(Last);
  if (I1 < 0) or (I2 < 0) or (I2 <= I1) then Exit;
  G := TAnimGroup.Create;
  G.IsFlat := IsFlat;
  for I := I1 to I2 do
  begin
    G.Names.Add(Order[I]);
    FAnimByName.AddOrSetValue(Order[I], G);
  end;
  FAnimGroups.Add(G);
end;

procedure TDoomGraphics.SetupAnimations;
begin
  { The vanilla Doom animation table (p_spec.c). }
  AddAnimRange('NUKAGE1', 'NUKAGE3', true);
  AddAnimRange('FWATER1', 'FWATER4', true);
  AddAnimRange('SWATER1', 'SWATER4', true);
  AddAnimRange('LAVA1', 'LAVA4', true);
  AddAnimRange('BLOOD1', 'BLOOD3', true);
  AddAnimRange('RROCK05', 'RROCK08', true);
  AddAnimRange('SLIME01', 'SLIME04', true);
  AddAnimRange('SLIME05', 'SLIME08', true);
  AddAnimRange('SLIME09', 'SLIME12', true);

  AddAnimRange('BLODGR1', 'BLODGR4', false);
  AddAnimRange('SLADRIP1', 'SLADRIP3', false);
  AddAnimRange('BLODRIP1', 'BLODRIP4', false);
  AddAnimRange('FIREWALA', 'FIREWALL', false);
  AddAnimRange('GSTFONT1', 'GSTFONT3', false);
  AddAnimRange('FIRELAV3', 'FIRELAVA', false);
  AddAnimRange('FIREMAG1', 'FIREMAG3', false);
  AddAnimRange('FIREBLU1', 'FIREBLU2', false);
  AddAnimRange('ROCKRED1', 'ROCKRED3', false);
  AddAnimRange('BFALL1', 'BFALL4', false);
  AddAnimRange('SFALL1', 'SFALL4', false);
  AddAnimRange('WFALL1', 'WFALL4', false);
  AddAnimRange('DBRAIN1', 'DBRAIN4', false);
end;

function TDoomGraphics.FindPatchLump(const Name: String): Integer;
begin
  Result := -1;
  if (FPatchStart >= 0) and (FPatchEnd > FPatchStart) then
  begin
    Result := FWad.FindLump(Name, FPatchStart);
    if Result > FPatchEnd then Result := -1;
  end;
  if Result < 0 then
    Result := FWad.FindLump(Name);
end;

function TDoomGraphics.ReadGfx(const Url: String; out MimeType: String): TStream;
var
  Path, Kind, Name: String;
  Img: TDoomImage;
  P: Integer;
begin
  { doomgfx:/tex/NAME.png, doomgfx:/flat/NAME.png, doomgfx:/patch/NAME.png }
  Path := Url;
  P := Pos(':', Path);
  if P > 0 then Delete(Path, 1, P);
  while (Path <> '') and (Path[1] = '/') do Delete(Path, 1, 1);
  P := Pos('/', Path);
  if P = 0 then raise Exception.CreateFmt('Bad doomgfx URL: %s', [Url]);
  Kind := Copy(Path, 1, P - 1);
  Name := Copy(Path, P + 1, MaxInt);
  if LowerCase(ExtractFileExt(Name)) = '.png' then
    Name := Copy(Name, 1, Length(Name) - 4);
  if Kind = 'tex' then Img := Texture(Name)
  else if Kind = 'flat' then Img := Flat(Name)
  else if Kind = 'patch' then Img := Patch(Name)
  else if Kind = 'missing' then Img := MissingTexture
  else Img := nil;
  if Img = nil then
    raise Exception.CreateFmt('Doom graphic not found: %s', [Url]);
  Result := TMemoryStream.Create;
  SaveImage(Img.Image, 'image/png', Result);
  Result.Position := 0;
  MimeType := 'image/png';
end;

procedure TDoomGraphics.ResolveAnim(const Img: TDoomImage; const IsFlat: Boolean);
var
  G: TAnimGroup;
  I: Integer;
begin
  if FAnimByName.TryGetValue(Img.Name, G) and (G.IsFlat = IsFlat) then
  begin
    Img.AnimGroup := G;
    if Length(G.Frames) = 0 then
    begin
      SetLength(G.Frames, G.Names.Count);
      for I := 0 to G.Names.Count - 1 do
        if IsFlat then G.Frames[I] := Flat(G.Names[I]) else G.Frames[I] := Texture(G.Names[I]);
    end;
  end;
end;

function TDoomGraphics.MissingTexture: TDoomImage;
var
  X, Y: Integer;
  C: TVector4Byte;
begin
  if FMissing = nil then
  begin
    { Loud magenta/black checkerboard, like most engines show for a missing texture. }
    FMissing := TDoomImage.Create;
    FMissing.Name := 'MISSING';
    FMissing.Url := 'doomgfx:/missing/MISSING.png';
    FMissing.Width := 64;
    FMissing.Height := 64;
    FMissing.Image := TRGBAlphaImage.Create(64, 64);
    for Y := 0 to 63 do
      for X := 0 to 63 do
      begin
        if ((X div 8) + (Y div 8)) mod 2 = 0 then
          C := Vector4Byte(255, 0, 255, 255)
        else
          C := Vector4Byte(0, 0, 0, 255);
        PVector4Byte(FMissing.Image.PixelPtr(X, Y))^ := C;
      end;
  end;
  Result := FMissing;
end;

function TDoomGraphics.ComposeTexture(const Def: TTextureDef): TDoomImage;
var
  P, PatchEntry: PByte;
  W, H, PatchCount, I, OriginX, OriginY, PatchIdx, LumpIdx, LumpSize: Integer;
begin
  P := FWad.LumpPointer(Def.Lump) + Def.Offset;
  LumpSize := FWad.LumpSize(Def.Lump) - Def.Offset;
  W := PInt16(P + 12)^;
  H := PInt16(P + 14)^;
  PatchCount := PInt16(P + 20)^;
  Result := TDoomImage.Create;
  Result.Name := Def.Name;
  Result.Url := 'doomgfx:/tex/' + Def.Name + '.png';
  if (W <= 0) or (H <= 0) or (W > 4096) or (H > 4096) then
  begin
    W := 64;
    H := 64;
    PatchCount := 0;
  end;
  Result.Width := W;
  Result.Height := H;
  Result.Image := TRGBAlphaImage.Create(W, H);
  Result.Image.Clear(Vector4Byte(0, 0, 0, 0));
  for I := 0 to PatchCount - 1 do
  begin
    if 22 + I * 10 + 10 > LumpSize then Break;
    PatchEntry := P + 22 + I * 10;
    OriginX := PInt16(PatchEntry)^;
    OriginY := PInt16(PatchEntry + 2)^;
    PatchIdx := PInt16(PatchEntry + 4)^;
    if (PatchIdx < 0) or (PatchIdx > High(FPatchNames)) then Continue;
    LumpIdx := FindPatchLump(FPatchNames[PatchIdx]);
    if LumpIdx < 0 then
    begin
      WritelnWarning('Graphics', 'Texture %s references missing patch %s', [Def.Name, FPatchNames[PatchIdx]]);
      Continue;
    end;
    DrawPatchInto(FWad, Result.Image, FWad.LumpPointer(LumpIdx), FWad.LumpSize(LumpIdx), OriginX, OriginY);
  end;
  Result.HasAlpha := ImageHasAlpha(Result.Image);
  FTextures.Add(Def.Name, Result);
  ResolveAnim(Result, false);
end;

function TDoomGraphics.HasTexture(const Name: String): Boolean;
begin
  Result := FTextureDefs.ContainsKey(UpperCase(Name));
end;

function TDoomGraphics.Texture(const Name: String): TDoomImage;
var
  U: String;
  Def: TTextureDef;
begin
  U := UpperCase(Name);
  if (U = '') or (U = '-') then Exit(nil);
  if FTextures.TryGetValue(U, Result) then Exit;
  if FTextureDefs.TryGetValue(U, Def) then
    Result := ComposeTexture(Def)
  else
  begin
    { Some WADs use a flat name as a wall texture; be forgiving. }
    Result := Flat(U);
    if Result <> nil then Exit;
    WritelnWarning('Graphics', 'Unknown wall texture "%s"', [U]);
    Result := MissingTexture;
  end;
end;

function TDoomGraphics.Flat(const Name: String): TDoomImage;
var
  U: String;
  Lump, X, Y: Integer;
  P: PByte;
begin
  U := UpperCase(Name);
  if FFlats.TryGetValue(U, Result) then Exit;
  if not FFlatLumps.TryGetValue(U, Lump) then
  begin
    if U <> 'F_SKY1' then
      WritelnWarning('Graphics', 'Unknown flat "%s"', [U]);
    Exit(nil);
  end;
  Result := TDoomImage.Create;
  Result.Name := U;
  Result.Url := 'doomgfx:/flat/' + U + '.png';
  Result.Width := 64;
  Result.Height := 64;
  Result.Image := TRGBAlphaImage.Create(64, 64);
  P := FWad.LumpPointer(Lump);
  for Y := 0 to 63 do
    for X := 0 to 63 do
      PVector4Byte(Result.Image.PixelPtr(X, 63 - Y))^ := FWad.PaletteColor(P[Y * 64 + X]);
  FFlats.Add(U, Result);
  ResolveAnim(Result, true);
end;

function TDoomGraphics.Patch(const LumpName: String): TDoomImage;
var
  U: String;
  Lump, W, H: Integer;
  P: PByte;
begin
  U := UpperCase(LumpName);
  if FPatches.TryGetValue(U, Result) then Exit;
  Lump := FWad.FindLump(U);
  if (Lump < 0) or (FWad.LumpSize(Lump) < 8) then
  begin
    FPatches.Add(U, nil);
    Exit(nil);
  end;
  P := FWad.LumpPointer(Lump);
  W := PInt16(P)^;
  H := PInt16(P + 2)^;
  if (W <= 0) or (H <= 0) or (W > 2048) or (H > 2048) then
  begin
    FPatches.Add(U, nil);
    Exit(nil);
  end;
  Result := TDoomImage.Create;
  Result.Name := U;
  Result.Url := 'doomgfx:/patch/' + U + '.png';
  Result.Width := W;
  Result.Height := H;
  Result.LeftOffset := PInt16(P + 4)^;
  Result.TopOffset := PInt16(P + 6)^;
  Result.Image := TRGBAlphaImage.Create(W, H);
  Result.Image.Clear(Vector4Byte(0, 0, 0, 0));
  DrawPatchInto(FWad, Result.Image, P, FWad.LumpSize(Lump), 0, 0);
  Result.HasAlpha := true;
  FPatches.Add(U, Result);
end;

function TDoomGraphics.Sprite(const Prefix: String; const Frame: Char;
  const Rot: Integer; out Mirror: Boolean): TDoomImage;
var
  Ref: TSpriteLumpRef;
  Key: String;
begin
  Mirror := false;
  Key := UpperCase(Prefix) + UpCase(Frame) + IntToStr(Rot);
  if not FSprites.TryGetValue(Key, Ref) then
  begin
    Key := UpperCase(Prefix) + UpCase(Frame) + '0';
    if not FSprites.TryGetValue(Key, Ref) then
    begin
      { Rotation 1 as the last resort (some WADs omit 0). }
      Key := UpperCase(Prefix) + UpCase(Frame) + '1';
      if not FSprites.TryGetValue(Key, Ref) then
        Exit(nil);
    end;
  end;
  Mirror := Ref.Mirror;
  Result := Patch(FWad.LumpName(Ref.Lump));
end;

function TDoomGraphics.HasSpriteFrame(const Prefix: String; const Frame: Char): Boolean;
var
  R: Integer;
begin
  for R := 0 to 8 do
    if FSprites.ContainsKey(UpperCase(Prefix) + UpCase(Frame) + IntToStr(R)) then
      Exit(true);
  Result := false;
end;

procedure TDoomGraphics.AnimationTic(const Tic: Int64);
var
  G: TAnimGroup;
  N: TImageTextureNode;
  NewFrame: Integer;
begin
  { Doom switches animation frames every 8 tics. }
  for G in FAnimGroups do
    if (Length(G.Frames) > 0) and (G.Nodes.Count > 0) then
    begin
      NewFrame := (Tic div 8) mod Length(G.Frames);
      if NewFrame <> G.Current then
      begin
        G.Current := NewFrame;
        if G.Frames[NewFrame] <> nil then
          for N in G.Nodes do
            N.SetUrl([G.Frames[NewFrame].Url]);
      end;
    end;
end;

function TDoomGraphics.SkyTextureName(const MapName: String): String;
var
  N: Integer;
begin
  if FWad.IsDoom2 then
  begin
    N := StrToIntDef(Copy(MapName, 4, 2), 1);
    if N <= 11 then Result := 'SKY1'
    else if N <= 20 then Result := 'SKY2'
    else Result := 'SKY3';
  end else
  begin
    N := StrToIntDef(Copy(MapName, 2, 1), 1);
    Result := 'SKY' + IntToStr(Clamped(N, 1, 4));
    if not HasTexture(Result) then
      Result := 'SKY3';
  end;
  if not HasTexture(Result) then
    Result := 'SKY1';
end;

end.
