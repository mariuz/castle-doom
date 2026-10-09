{ Doom's light diminishing (r_main.c scalelight / zlight, the COLORMAP
  levels) as a CGE shader effect.

  Doom darkens a pixel by picking one of 32 colormaps: the sector light
  gives a starting colormap, and the closer the pixel, the brighter the
  colormap. Walls and sprites use their projected scale (scalelight),
  floors and ceilings their distance (zlight). Colormap N is the palette
  darkened to (32 - N) / 32, so the effect multiplies the texel by that,
  with Doom's integer steps (the visible light bands).

  Geometry passes the sector light per vertex in the "doom_light" vertex
  attribute (x = light level 0..255, y = kind, see DoomLightWall etc.);
  sprites set it per actor in the "doom_sprite" uniform. The settings shared
  by everything (the gun flash's extra light, the fixed colormap of the
  invulnerability and light amplification powerups, light diminishing on or
  off) are uniforms of every effect node, kept in sync by DoomLighting. }
unit DoomLighting;

interface

uses Generics.Collections, CastleVectors, X3DNodes, X3DFields;

const
  { Values of the "kind" component of doom_light / doom_sprite.
    Walls use DoomLightWall plus Doom's fake contrast (-1, 0 or +1). }
  DoomLightWall = 0;
  DoomLightPlane = 10;
  DoomLightFullBright = 20;
  { Spectre fuzz (R_DrawFuzzColumn): a black, translucent shimmer in
    Doom's fuzzoffset pattern instead of the sprite's colours. }
  DoomLightFuzz = 30;

  { r_draw.c fuzzoffset: each fuzz pixel copies the background from the
    row above (-) or below (+); FuzzOffsets[(FuzzPhase + ...) mod 50]. }
  FuzzOffsets: array [0..49] of ShortInt = (
    1, -1, 1, -1, 1, 1, -1, 1, 1, -1, 1, 1, 1, -1, 1, 1, 1, -1, -1, -1, -1,
    1, -1, -1, 1, 1, 1, 1, -1, 1, -1, 1, 1, -1, -1, 1, 1, -1, -1, -1, -1,
    1, 1, 1, 1, -1, 1, 1, -1, 1);
  { The black's opacity where the background would come from below / above:
    rows pulled from elsewhere show up as dark and light specks. }
  FuzzAlphaPlus = 0.7;
  FuzzAlphaMinus = 0.3;

  { DoomLighting.FixedColormap values. }
  NoFixedColormap = -1;
  { Invulnerability: inverted greys (Doom's INVERSECOLORMAP). }
  InverseColormap = 32;

type
  TEffectNodeList = {$ifdef FPC}specialize{$endif} TList<TEffectNode>;

  TDoomLighting = class
  strict private
    FEffects: TEffectNodeList;
    FExtraLight, FFixedColormap: Integer;
    FDiminish: Boolean;
    FIndexLutUrl, FColormapLutUrl: String;
    FPaletteMapped: Boolean;
    FFuzzScale: Single;
    FFuzzPhase: Integer;
    procedure SetFuzzScale(const Value: Single);
    procedure SetFuzzPhase(const Value: Integer);
    procedure SetPaletteMapped(const Value: Boolean);
    procedure EffectDestroyed(const Node: TX3DNode);
    function NewEffect(const VertexCode, FragmentInput: String): TEffectNode;
    procedure SetExtraLight(const Value: Integer);
    procedure SetFixedColormap(const Value: Integer);
    procedure SetDiminish(const Value: Boolean);
    procedure SendAll(const FieldName: String; const Value: Single);
  public
    constructor Create;
    destructor Destroy; override;
    { A new effect for shapes whose geometry has the doom_light attribute
      (see LightAttribute). Put it in the scene's root (it applies to all
      shapes in the group). }
    function GeometryEffect: TEffectNode;
    { A new effect for one sprite; LightField receives the doom_sprite
      uniform (x = light level, y = kind). Put it in the appearance. }
    function SpriteEffect(out LightField: TSFVec2f): TEffectNode;
    { A new doom_light vertex attribute node. }
    function LightAttribute: TFloatVertexAttributeNode;
    { Doom's colormap index (0 = full bright, 31 = darkest) for a light
      level seen at the nearest scale, as the player's weapon is lit. }
    function WeaponColormap(const Light: Integer): Integer;
    { Brightness of a colormap index. }
    class function ColormapBrightness(const Colormap: Integer): Single; static;
    { The gun flash (A_Light1 / A_Light2): 0..2 light steps. }
    property ExtraLight: Integer read FExtraLight write SetExtraLight;
    { NoFixedColormap, a colormap 0..31, or InverseColormap. }
    property FixedColormap: Integer read FFixedColormap write SetFixedColormap;
    { Light diminishing with distance; off gives each sector a flat light. }
    property Diminish: Boolean read FDiminish write SetDiminish;
    { The lookup images (TDoomGraphics serves them) for palette-mapped
      colours; effects made after this use them. }
    procedure SetLookupUrls(const IndexUrl, ColormapUrl: String);
    { Doom's real COLORMAP rows instead of darkening by (32 - level) / 32
      (needs the lookup images). }
    property PaletteMapped: Boolean read FPaletteMapped write SetPaletteMapped;
    { Screen pixels per Doom pixel (view height / 200): the fuzz pattern's
      grain. }
    property FuzzScale: Single read FFuzzScale write SetFuzzScale;
    { Where the fuzz pattern starts (0..49), changed every tic like Doom's
      ever-advancing fuzzpos. }
    property FuzzPhase: Integer read FFuzzPhase write SetFuzzPhase;
  end;

function DoomLightingInstance: TDoomLighting;

implementation

uses SysUtils, Math, CastleUtils, CastleRenderOptions;

const
  NL = LineEnding;

  { The level of the colormap, the same arithmetic as r_main.c
    (R_InitLightTables, R_ScaleFromGlobalAngle >> LIGHTSCALESHIFT,
    distance >> LIGHTZSHIFT) for Doom's 320-pixel-wide projection (160):
    walls and sprites: index = min(2560 / depth, 47), level = start - index / 2;
    planes: index = min(depth / 16, 127), level = start - (160 / (index + 1)) / 2;
    start = (15 - lightnum) * 4, lightnum = light / 16 + extra light (+ contrast). }
  FuzzAlphaPlusGlsl = '0.7';
  FuzzAlphaMinusGlsl = '0.3';

  FragmentCode =
    'uniform float doom_extra_light;' + NL +
    'uniform float doom_fixed_colormap;' + NL +
    'uniform float doom_diminish;' + NL +
    'uniform float doom_palette_mapped;' + NL +
    'uniform sampler2D doom_index_lut;' + NL +
    'uniform sampler2D doom_colormap_lut;' + NL +
    'uniform float doom_fuzz_scale;' + NL +
    'uniform float doom_fuzz_phase;' + NL +
    '' + NL +
    { FuzzOffsets as bits (1 = +1), 10 a number so that mediump floats keep
      them exact. }
    'float doom_fuzz_bit(float i)' + NL +
    '{' + NL +
    '  float chunk = floor(i / 10.0);' + NL +
    '  float bits = chunk < 1.0 ? 437.0 : chunk < 2.0 ? 119.0 : chunk < 3.0 ? 754.0 : chunk < 4.0 ? 102.0 : 734.0;' + NL +
    '  return mod(floor(bits / exp2(i - chunk * 10.0)), 2.0);' + NL +
    '}' + NL +
    '' + NL +
    { Doom's exact colour: the texel back to its palette index (6 bits a
      channel, TDoomGraphics.MakeLuts), then COLORMAP row "level". }
    'vec3 doom_colormapped(vec3 c, float level)' + NL +
    '{' + NL +
    '  vec3 q = floor(floor(clamp(c, 0.0, 1.0) * 255.0 + 0.5) / 4.0);' + NL +
    '  vec2 cell = vec2(q.r + 64.0 * mod(q.b, 8.0), q.g + 64.0 * floor(q.b / 8.0));' + NL +
    '  float index = floor(texture2D(doom_index_lut, (cell + 0.5) / 512.0).r * 255.0 + 0.5);' + NL +
    '  return texture2D(doom_colormap_lut, vec2((index + 0.5) / 256.0, (level + 0.5) / 64.0)).rgb;' + NL +
    '}' + NL +
    '' + NL +
    'void PLUG_fragment_modify(inout vec4 fragment_color)' + NL +
    '{' + NL +
    '  float light = doom_light_info.x;' + NL +
    '  float kind = doom_light_info.y;' + NL +
    '  float depth = max(doom_light_info.z, 1.0);' + NL +
    '  float level;' + NL +
    '  if (kind > 25.0) {' + NL +
    { Doom pixels (320x200 grain), counted down each column like fuzzpos;
      the column adds an offset so neighbours differ. }
    '    vec2 p = floor(gl_FragCoord.xy / doom_fuzz_scale);' + NL +
    '    float i = mod(doom_fuzz_phase + mod(p.x, 50.0) * 7.0 + 50.0 - mod(p.y, 50.0), 50.0);' + NL +
    '    float alpha = doom_fuzz_bit(i) > 0.5 ? ' + FuzzAlphaPlusGlsl + ' : ' + FuzzAlphaMinusGlsl + ';' + NL +
    '    fragment_color = vec4(0.0, 0.0, 0.0, fragment_color.a > 0.5 ? alpha : 0.0);' + NL +
    '    return;' + NL +
    '  }' + NL +
    '  if (doom_fixed_colormap > 31.5) {' + NL +
    '    if (doom_palette_mapped > 0.5)' + NL +
    '      fragment_color.rgb = doom_colormapped(fragment_color.rgb, 32.0);' + NL +
    '    else' + NL +
    '      fragment_color.rgb = vec3(1.0 - dot(fragment_color.rgb, vec3(0.299, 0.587, 0.114)));' + NL +
    '    return;' + NL +
    '  }' + NL +
    '  if (doom_fixed_colormap > -0.5)' + NL +
    '    level = doom_fixed_colormap;' + NL +
    '  else if (kind > 15.0)' + NL +
    '    level = 0.0;' + NL +
    '  else {' + NL +
    '    float contrast = kind > 5.0 ? 0.0 : kind;' + NL +
    '    float lightnum = clamp(floor(light / 16.0) + doom_extra_light + contrast, 0.0, 15.0);' + NL +
    '    float start = (15.0 - lightnum) * 4.0;' + NL +
    '    if (doom_diminish < 0.5)' + NL +
    '      level = floor(start / 2.0);' + NL +
    '    else if (kind > 5.0) {' + NL +
    '      float index = min(floor(depth / 16.0), 127.0);' + NL +
    '      level = start - floor(floor(160.0 / (index + 1.0)) / 2.0);' + NL +
    '    } else {' + NL +
    '      float index = min(floor(2560.0 / depth), 47.0);' + NL +
    '      level = start - floor(index / 2.0);' + NL +
    '    }' + NL +
    '  }' + NL +
    '  level = clamp(level, 0.0, 31.0);' + NL +
    '  if (doom_palette_mapped > 0.5)' + NL +
    '    fragment_color.rgb = doom_colormapped(fragment_color.rgb, level);' + NL +
    '  else' + NL +
    '    fragment_color.rgb *= 1.0 - level / 32.0;' + NL +
    '}';

  GeometryVertex =
    'attribute vec2 doom_light;' + NL +
    'varying vec3 doom_light_info;' + NL +
    'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' + NL +
    '{' + NL +
    '  doom_light_info = vec3(doom_light, -vertex_eye.z);' + NL +
    '}';
  GeometryFragmentInput =
    'varying vec3 doom_light_info;' + NL;

  SpriteVertex =
    'varying float doom_depth;' + NL +
    'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' + NL +
    '{' + NL +
    '  doom_depth = -vertex_eye.z;' + NL +
    '}';
  SpriteFragmentInput =
    'uniform vec2 doom_sprite;' + NL +
    'varying float doom_depth;' + NL +
    '#define doom_light_info vec3(doom_sprite, doom_depth)' + NL;

var
  FInstance: TDoomLighting;

function DoomLightingInstance: TDoomLighting;
begin
  if FInstance = nil then
    FInstance := TDoomLighting.Create;
  Result := FInstance;
end;

constructor TDoomLighting.Create;
begin
  inherited;
  FEffects := TEffectNodeList.Create;
  FExtraLight := 0;
  FFixedColormap := NoFixedColormap;
  FDiminish := true;
  FPaletteMapped := true;
  FFuzzScale := 1;
end;

procedure TDoomLighting.SetFuzzScale(const Value: Single);
begin
  if FFuzzScale = Value then Exit;
  FFuzzScale := Value;
  SendAll('doom_fuzz_scale', Value);
end;

procedure TDoomLighting.SetFuzzPhase(const Value: Integer);
begin
  if FFuzzPhase = Value then Exit;
  FFuzzPhase := Value;
  SendAll('doom_fuzz_phase', Value);
end;

procedure TDoomLighting.SetLookupUrls(const IndexUrl, ColormapUrl: String);
begin
  FIndexLutUrl := IndexUrl;
  FColormapLutUrl := ColormapUrl;
end;

{ A lookup image as a texture: exact texels (no filtering, no mipmaps).
  A new node per effect (one node must not be in two scenes); CGE's
  texture cache shares the image by its URL. }
function LutTexture(const Url: String): TImageTextureNode;
var
  Props: TTexturePropertiesNode;
begin
  Result := TImageTextureNode.Create;
  Result.SetUrl([Url]);
  Result.RepeatS := false;
  Result.RepeatT := false;
  Props := TTexturePropertiesNode.Create;
  Props.MagnificationFilter := magNearest;
  Props.MinificationFilter := minNearest;
  Props.GenerateMipMaps := false;
  Props.BoundaryModeS := bmClampToEdge;
  Props.BoundaryModeT := bmClampToEdge;
  Result.TextureProperties := Props;
end;

procedure TDoomLighting.SetPaletteMapped(const Value: Boolean);
begin
  if FPaletteMapped = Value then Exit;
  FPaletteMapped := Value;
  SendAll('doom_palette_mapped', Ord(Value and (FIndexLutUrl <> '')));
end;

destructor TDoomLighting.Destroy;
var
  E: TEffectNode;
begin
  if FEffects <> nil then
    for E in FEffects do
      E.RemoveDestructionNotification({$ifdef FPC}@{$endif}EffectDestroyed);
  FreeAndNil(FEffects);
  inherited;
end;

procedure TDoomLighting.EffectDestroyed(const Node: TX3DNode);
begin
  FEffects.Remove(Node as TEffectNode);
end;

function TDoomLighting.NewEffect(const VertexCode, FragmentInput: String): TEffectNode;
var
  VertexPart, FragmentPart: TEffectPartNode;
begin
  Result := TEffectNode.Create;
  Result.Language := slGLSL;
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_extra_light', FExtraLight));
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_fixed_colormap', FFixedColormap));
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_diminish', Ord(FDiminish)));
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_palette_mapped',
    Ord(FPaletteMapped and (FIndexLutUrl <> ''))));
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_fuzz_scale', FFuzzScale));
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_fuzz_phase', FFuzzPhase));
  if FIndexLutUrl <> '' then
  begin
    Result.AddCustomField(TSFNode.Create(Result, true, 'doom_index_lut', [TImageTextureNode],
      LutTexture(FIndexLutUrl)));
    Result.AddCustomField(TSFNode.Create(Result, true, 'doom_colormap_lut', [TImageTextureNode],
      LutTexture(FColormapLutUrl)));
  end;

  VertexPart := TEffectPartNode.Create;
  VertexPart.ShaderType := stVertex;
  VertexPart.Contents := VertexCode;
  FragmentPart := TEffectPartNode.Create;
  FragmentPart.ShaderType := stFragment;
  FragmentPart.Contents := FragmentInput + FragmentCode;
  Result.SetParts([VertexPart, FragmentPart]);

  Result.AddDestructionNotification({$ifdef FPC}@{$endif}EffectDestroyed);
  FEffects.Add(Result);
end;

function TDoomLighting.GeometryEffect: TEffectNode;
begin
  Result := NewEffect(GeometryVertex, GeometryFragmentInput);
end;

function TDoomLighting.SpriteEffect(out LightField: TSFVec2f): TEffectNode;
begin
  Result := NewEffect(SpriteVertex, SpriteFragmentInput);
  LightField := TSFVec2f.Create(Result, true, 'doom_sprite', TVector2.Zero);
  Result.AddCustomField(LightField);
end;

function TDoomLighting.LightAttribute: TFloatVertexAttributeNode;
begin
  Result := TFloatVertexAttributeNode.Create;
  Result.NameField := 'doom_light';
  Result.NumComponents := 2;
end;

function TDoomLighting.WeaponColormap(const Light: Integer): Integer;
var
  LightNum: Integer;
begin
  if FFixedColormap >= 0 then
    Exit(Min(FFixedColormap, 31));
  LightNum := Clamped(Light div 16 + FExtraLight, 0, 15);
  { spritelights[MAXLIGHTSCALE - 1]: start - 47 / 2 }
  Result := Clamped((15 - LightNum) * 4 - 23, 0, 31);
end;

class function TDoomLighting.ColormapBrightness(const Colormap: Integer): Single;
begin
  Result := 1 - Clamped(Colormap, 0, 31) / 32;
end;

procedure TDoomLighting.SendAll(const FieldName: String; const Value: Single);
var
  E: TEffectNode;
  F: TX3DField;
begin
  for E in FEffects do
  begin
    F := E.Field(FieldName);
    if F is TSFFloat then
      TSFFloat(F).Send(Value);
  end;
end;

procedure TDoomLighting.SetExtraLight(const Value: Integer);
begin
  if FExtraLight = Value then Exit;
  FExtraLight := Value;
  SendAll('doom_extra_light', Value);
end;

procedure TDoomLighting.SetFixedColormap(const Value: Integer);
begin
  if FFixedColormap = Value then Exit;
  FFixedColormap := Value;
  SendAll('doom_fixed_colormap', Value);
end;

procedure TDoomLighting.SetDiminish(const Value: Boolean);
begin
  if FDiminish = Value then Exit;
  FDiminish := Value;
  SendAll('doom_diminish', Ord(Value));
end;

finalization
  FreeAndNil(FInstance);
end.
