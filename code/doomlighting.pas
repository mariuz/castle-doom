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

  { Point lights the shader adds (dynamic lights, an option). }
  MaxDynamicLights = 8;

type
  TEffectNodeList = {$ifdef FPC}specialize{$endif} TList<TEffectNode>;

  { A dynamic light: the position in the world (CGE coordinates, units =
    Doom units), the radius it reaches (0 = off) and its colour. }
  TDynamicLight = record
    Position: TVector3;
    Radius: Single;
    Color: TVector3;
  end;

  TDoomLighting = class
  strict private
    FEffects: TEffectNodeList;
    FExtraLight, FFixedColormap, FGamma: Integer;
    FDiminish: Boolean;
    FIndexLutUrl, FColormapLutUrl: String;
    FPaletteMapped: Boolean;
    FFuzzScale: Single;
    FFuzzPhase: Integer;
    FLights: array [0..MaxDynamicLights - 1] of TDynamicLight;
    FLightCount: Integer;
    FView: TMatrix4;
    function LightVectors: TVector4List;
    function LightColors: TVector3List;
    procedure SetFuzzScale(const Value: Single);
    procedure SetFuzzPhase(const Value: Integer);
    procedure SetPaletteMapped(const Value: Boolean);
    procedure EffectDestroyed(const Node: TX3DNode);
    function NewEffect(const VertexCode, FragmentInput: String): TEffectNode;
    procedure SetExtraLight(const Value: Integer);
    procedure SetFixedColormap(const Value: Integer);
    procedure SetDiminish(const Value: Boolean);
    procedure SetGamma(const Value: Integer);
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
    { A new doom_tile vertex attribute node (x, y, width, height of the
      vertex's texture in the atlas page, as texture coordinates; (0, 0, 1,
      1) for a shape with its own texture). }
    function TileAttribute: TFloatVertexAttributeNode;
    { New doom_color (RGB the sector's UDMF light colour) and doom_fade
      (RGB its fog colour, W the fog density a map unit, 0 = none) vertex
      attribute nodes. }
    function ColorAttribute: TFloatVertexAttributeNode;
    function FadeAttribute: TFloatVertexAttributeNode;
    { A new effect for an atlas page's ImageTexture node: the texture
      coordinates wrap inside the vertex's tile (doom_tile), so walls and
      flats repeat as they did with their own textures. }
    function AtlasTextureEffect: TEffectNode;
    { A sky texture on a sector's ceiling (per-sector skies): sampled by
      the direction from the eye (EyeField, Doom coordinates, sent every
      frame) to the fragment's Doom position (the doom_tile attribute),
      the way the sky cylinder maps it; Flipped mirrors it (Boom's 272),
      TextureHeight is the sky's height in rows. }
    function SkyTextureEffect(const Flipped: Boolean; const TextureHeight: Integer;
      out EyeField: TSFVec3f): TEffectNode;
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
    { Gamma correction level 0..4 (Doom's usegamma): the colours raised to
      GammaExponent (1, 0.77, 0.63, 0.53, 0.45), so dark parts brighten
      most, roughly like Doom's gamma tables. }
    property Gamma: Integer read FGamma write SetGamma;
    function GammaExponent: Single;
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
    { The dynamic lights shown (the first MaxDynamicLights) and the
      camera's world to eye matrix (Camera.WorldInverseTransform); the
      shaders get the lights only when they change, the matrix while
      there are lights. }
    procedure SetDynamicLights(const Lights: array of TDynamicLight; const View: TMatrix4);
    { How many slots are on now. }
    function DynamicLightCount: Integer;
  end;

function DoomLightingInstance: TDoomLighting;

{ The dynamic light of a sprite (missiles and explosions by their sprite
  prefix): its radius in Doom units and colour; False for none. }
function SpriteDynamicLight(const Sprite: String; out Radius: Single; out Color: TVector3): Boolean;

{ The light of a lamp, torch or candle (a decoration, by its sprite
  prefix): radius, the light's height above the thing's feet and colour;
  False for other things. }
function LampDynamicLight(const Sprite: String; out Radius, Height: Single; out Color: TVector3): Boolean;

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
    'uniform float doom_gamma;' + NL +
    { Dynamic lights: world positions and radii, colours, how many are
      used (the first ones), and the camera's world to eye matrix. }
    'uniform vec4 doom_dlights[8];' + NL +
    'uniform vec3 doom_dlight_colors[8];' + NL +
    'uniform float doom_dlight_count;' + NL +
    'uniform mat4 doom_view;' + NL +
    '' + NL +
    { A dynamic light: a smooth falloff to its radius (w, 0 = off). }
    'void doom_dlight(vec4 l, vec3 c, inout float boost, inout vec3 tint)' + NL +
    '{' + NL +
    '  if (l.w <= 0.0) return;' + NL +
    '  vec3 p = (doom_view * vec4(l.xyz, 1.0)).xyz;' + NL +
    '  float f = clamp(1.0 - length(doom_eye - p) / l.w, 0.0, 1.0);' + NL +
    '  f = f * f * (3.0 - 2.0 * f);' + NL +
    '  boost += f;' + NL +
    '  tint += c * f;' + NL +
    '}' + NL +
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
    '    if (doom_gamma < 0.999) fragment_color.rgb = pow(max(fragment_color.rgb, vec3(0.0)), vec3(doom_gamma));' + NL +
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
    { Dynamic lights: brighter colormap rows near them, and their colour
      on top of the texel. }
    '  float doom_boost = 0.0;' + NL +
    '  vec3 doom_tint = vec3(0.0);' + NL +
    '  for (int i = 0; i < 8; i++) {' + NL +
    '    if (float(i) >= doom_dlight_count) break;' + NL +
    '    doom_dlight(doom_dlights[i], doom_dlight_colors[i], doom_boost, doom_tint);' + NL +
    '  }' + NL +
    '  level -= floor(min(doom_boost, 1.5) * 16.0);' + NL +
    '  vec3 doom_base = fragment_color.rgb;' + NL +
    '  level = clamp(level, 0.0, 31.0);' + NL +
    '  if (doom_palette_mapped > 0.5)' + NL +
    '    fragment_color.rgb = doom_colormapped(fragment_color.rgb, level);' + NL +
    '  else' + NL +
    '    fragment_color.rgb *= 1.0 - level / 32.0;' + NL +
    '  fragment_color.rgb = min(fragment_color.rgb + doom_base * doom_tint * 0.6, vec3(1.0));' + NL +
    { UDMF sector colours (lightcolor) on lit surfaces, and fog
      (fadecolor): the fade colour by distance, denser in darker sectors
      (doom_fade_info.w, per vertex). }
    '  if (doom_fixed_colormap < -0.5) {' + NL +
    '    if (kind < 15.0) fragment_color.rgb *= doom_color_info.rgb;' + NL +
    '    if (doom_fade_info.w > 0.0)' + NL +
    '      fragment_color.rgb = mix(fragment_color.rgb, doom_fade_info.rgb, 1.0 - exp(-length(doom_eye) * doom_fade_info.w));' + NL +
    '  }' + NL +
    { Gamma correction (Doom's usegamma, F11): an exponent below 1. }
    '  if (doom_gamma < 0.999) fragment_color.rgb = pow(max(fragment_color.rgb, vec3(0.0)), vec3(doom_gamma));' + NL +
    '}';

  GeometryVertex =
    'attribute vec2 doom_light;' + NL +
    'attribute vec4 doom_tile;' + NL +
    'attribute vec4 doom_color;' + NL +
    'attribute vec4 doom_fade;' + NL +
    'varying vec3 doom_light_info;' + NL +
    'varying vec4 doom_tile_v;' + NL +
    'varying vec3 doom_eye;' + NL +
    'varying vec4 doom_color_info;' + NL +
    'varying vec4 doom_fade_info;' + NL +
    'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' + NL +
    '{' + NL +
    '  doom_light_info = vec3(doom_light, -vertex_eye.z);' + NL +
    '  doom_color_info = doom_color;' + NL +
    '  doom_fade_info = doom_fade;' + NL +
    '  doom_eye = vertex_eye.xyz;' + NL +
    '  doom_tile_v = doom_tile;' + NL +
    '}';

  { On an atlas page's texture: sample inside the vertex's tile, the
    coordinates wrapped by fract (the page clamps, the tile has a 1-texel
    border of its wrapped edges for the filtering). }
  AtlasTextureFragment =
    'varying vec4 doom_tile_v;' + NL +
    { The sampler parameter must not be called "texture": CGE renames
      texture2D to texture on newer GLSL, which it would shadow. }
    'void PLUG_texture_color(inout vec4 texture_color, const in sampler2D atlas, const in vec4 tex_coord)' + NL +
    '{' + NL +
    { With GLSL 1.40 / 3.00 es (CGE upgrades the shaders on OpenGL 3.1+
      and WebGL 2), sample the page's mipmaps with the gradients of the
      unwrapped coordinates: fract's jump at a repeat would otherwise
      pick the smallest mipmap along every seam. The gradients are
      clamped to level 3, the deepest the tiles' padding keeps apart. }
    '#ifdef CASTLE_GLSL_VERSION_UPGRADE' + NL +
    '  vec2 doom_c = tex_coord.xy * doom_tile_v.zw;' + NL +
    '  vec2 doom_dx = dFdx(doom_c);' + NL +
    '  vec2 doom_dy = dFdy(doom_c);' + NL +
    '  vec2 doom_size = vec2(textureSize(atlas, 0));' + NL +
    '  float doom_m = max(length(doom_dx * doom_size), length(doom_dy * doom_size));' + NL +
    '  if (doom_m > 8.0) { doom_dx *= 8.0 / doom_m; doom_dy *= 8.0 / doom_m; }' + NL +
    '  texture_color = textureGrad(atlas, doom_tile_v.xy + fract(tex_coord.xy) * doom_tile_v.zw, doom_dx, doom_dy);' + NL +
    '#else' + NL +
    '  texture_color = texture2D(atlas, doom_tile_v.xy + fract(tex_coord.xy) * doom_tile_v.zw);' + NL +
    '#endif' + NL +
    '}';
  { Per-sector skies: the sky cylinder's mapping (TDoomGeometry.BuildSky)
    from the direction to the fragment: 4 tiles a turn, the texture's row
    R at the slope (100 - R) / 160, row 0 stretched upwards, the rows
    repeating downwards. doom_tile_v holds the Doom position here. }
  SkyTextureFragment =
    'varying vec4 doom_tile_v;' + NL +
    'uniform vec3 doom_sky_eye;' + NL +
    'uniform float doom_sky_flip;' + NL +
    'uniform float doom_sky_height;' + NL +
    'void PLUG_texture_color(inout vec4 texture_color, const in sampler2D sky, const in vec4 tex_coord)' + NL +
    '{' + NL +
    '  vec3 d = doom_tile_v.xyz - doom_sky_eye;' + NL +
    '  float u = atan(d.y, d.x) / 1.5707963 * doom_sky_flip;' + NL +
    '  float row = 100.0 - 160.0 * d.z / max(length(d.xy), 0.001);' + NL +
    '  float v = row < 0.0 ? 1.0 : 1.0 - fract(row / doom_sky_height);' + NL +
    '  texture_color = texture2D(sky, vec2(u, v));' + NL +
    '}';
  GeometryFragmentInput =
    'varying vec3 doom_light_info;' + NL +
    'varying vec3 doom_eye;' + NL +
    'varying vec4 doom_color_info;' + NL +
    'varying vec4 doom_fade_info;' + NL;

  SpriteVertex =
    'varying float doom_depth;' + NL +
    'varying vec3 doom_eye;' + NL +
    'void PLUG_vertex_eye_space(const in vec4 vertex_eye, const in vec3 normal_eye)' + NL +
    '{' + NL +
    '  doom_depth = -vertex_eye.z;' + NL +
    '  doom_eye = vertex_eye.xyz;' + NL +
    '}';
  SpriteFragmentInput =
    'uniform vec2 doom_sprite;' + NL +
    'varying float doom_depth;' + NL +
    'varying vec3 doom_eye;' + NL +
    '#define doom_light_info vec3(doom_sprite, doom_depth)' + NL +
    '#define doom_color_info vec4(1.0)' + NL +
    '#define doom_fade_info vec4(0.0)' + NL;

var
  FInstance: TDoomLighting;

type
  TSpriteLight = record
    Sprite: String;
    Radius: Single;
    R, G, B: Single;
  end;

const
  SpriteLights: array [0..15] of TSpriteLight = (
    (Sprite: 'MISL'; Radius: 256; R: 1.0; G: 0.6; B: 0.25),  { rocket }
    (Sprite: 'BAL1'; Radius: 192; R: 1.0; G: 0.5; B: 0.2),   { imp fireball }
    (Sprite: 'BAL2'; Radius: 192; R: 1.0; G: 0.3; B: 0.6),   { cacodemon }
    (Sprite: 'BAL7'; Radius: 192; R: 0.4; G: 1.0; B: 0.3),   { baron, hell knight }
    (Sprite: 'PLSS'; Radius: 192; R: 0.4; G: 0.6; B: 1.0),   { plasma }
    (Sprite: 'PLSE'; Radius: 192; R: 0.4; G: 0.6; B: 1.0),
    (Sprite: 'BFS1'; Radius: 384; R: 0.4; G: 1.0; B: 0.4),   { BFG ball }
    (Sprite: 'BFE1'; Radius: 384; R: 0.4; G: 1.0; B: 0.4),
    (Sprite: 'APLS'; Radius: 160; R: 0.5; G: 1.0; B: 0.3),   { arachnotron }
    (Sprite: 'APBX'; Radius: 160; R: 0.5; G: 1.0; B: 0.3),
    (Sprite: 'MANF'; Radius: 192; R: 1.0; G: 0.6; B: 0.25),  { mancubus }
    (Sprite: 'FATB'; Radius: 160; R: 1.0; G: 0.5; B: 0.3),   { revenant }
    (Sprite: 'BEXP'; Radius: 320; R: 1.0; G: 0.6; B: 0.3),   { barrel }
    (Sprite: 'FIRE'; Radius: 192; R: 1.0; G: 0.6; B: 0.2),   { arch-vile }
    (Sprite: 'BOSF'; Radius: 160; R: 1.0; G: 0.7; B: 0.3),   { spawn cube }
    (Sprite: 'MISF'; Radius: 256; R: 1.0; G: 0.6; B: 0.25)
  );

type
  TLampLight = record
    Sprite: String;
    Radius, Height: Single;
    R, G, B: Single;
  end;

const
  LampLights: array [0..15] of TLampLight = (
    (Sprite: 'COLU'; Radius: 256; Height: 48; R: 1.0; G: 0.95; B: 0.8),  { floor lamp }
    (Sprite: 'TLMP'; Radius: 256; Height: 72; R: 0.85; G: 0.9; B: 1.0),  { tall tech lamp }
    (Sprite: 'TLP2'; Radius: 224; Height: 56; R: 0.85; G: 0.9; B: 1.0),  { short tech lamp }
    (Sprite: 'CAND'; Radius: 96; Height: 12; R: 1.0; G: 0.7; B: 0.3),    { candle }
    (Sprite: 'CBRA'; Radius: 160; Height: 48; R: 1.0; G: 0.7; B: 0.3),   { candelabra }
    (Sprite: 'TBLU'; Radius: 192; Height: 56; R: 0.4; G: 0.5; B: 1.0),   { tall torches }
    (Sprite: 'TGRN'; Radius: 192; Height: 56; R: 0.4; G: 1.0; B: 0.4),
    (Sprite: 'TRED'; Radius: 192; Height: 56; R: 1.0; G: 0.35; B: 0.25),
    (Sprite: 'SMBT'; Radius: 160; Height: 40; R: 0.4; G: 0.5; B: 1.0),   { short torches }
    (Sprite: 'SMGT'; Radius: 160; Height: 40; R: 0.4; G: 1.0; B: 0.4),
    (Sprite: 'SMRT'; Radius: 160; Height: 40; R: 1.0; G: 0.35; B: 0.25),
    (Sprite: 'FCAN'; Radius: 224; Height: 40; R: 1.0; G: 0.6; B: 0.25),  { burning barrel }
    (Sprite: 'CEYE'; Radius: 128; Height: 48; R: 0.4; G: 1.0; B: 0.4),   { evil eye }
    (Sprite: 'FSKU'; Radius: 128; Height: 40; R: 1.0; G: 0.6; B: 0.3),   { floating skull rock }
    (Sprite: 'POL3'; Radius: 96; Height: 16; R: 1.0; G: 0.7; B: 0.3),    { skulls and candles }
    (Sprite: 'TRE2'; Radius: 0; Height: 0; R: 0; G: 0; B: 0)              { (none: a tree) }
  );

function LampDynamicLight(const Sprite: String; out Radius, Height: Single; out Color: TVector3): Boolean;
var
  I: Integer;
begin
  for I := Low(LampLights) to High(LampLights) do
    if (LampLights[I].Sprite = Sprite) and (LampLights[I].Radius > 0) then
    begin
      Radius := LampLights[I].Radius;
      Height := LampLights[I].Height;
      Color := Vector3(LampLights[I].R, LampLights[I].G, LampLights[I].B);
      Exit(true);
    end;
  Radius := 0;
  Height := 0;
  Color := TVector3.Zero;
  Result := false;
end;

function SpriteDynamicLight(const Sprite: String; out Radius: Single; out Color: TVector3): Boolean;
var
  I: Integer;
begin
  for I := Low(SpriteLights) to High(SpriteLights) do
    if SpriteLights[I].Sprite = Sprite then
    begin
      Radius := SpriteLights[I].Radius;
      Color := Vector3(SpriteLights[I].R, SpriteLights[I].G, SpriteLights[I].B);
      Exit(true);
    end;
  Radius := 0;
  Color := TVector3.Zero;
  Result := false;
end;

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
  Vectors: TVector4List;
  Colors: TVector3List;
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
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_gamma', GammaExponent));
  Vectors := LightVectors;
  Colors := LightColors;
  try
    Result.AddCustomField(TMFVec4f.Create(Result, true, 'doom_dlights', Vectors.ToArray));
    Result.AddCustomField(TMFVec3f.Create(Result, true, 'doom_dlight_colors', Colors.ToArray));
  finally
    FreeAndNil(Vectors);
    FreeAndNil(Colors);
  end;
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_dlight_count', FLightCount));
  Result.AddCustomField(TSFMatrix4f.Create(Result, true, 'doom_view', FView));
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

function TDoomLighting.ColorAttribute: TFloatVertexAttributeNode;
begin
  Result := TFloatVertexAttributeNode.Create;
  Result.NameField := 'doom_color';
  Result.NumComponents := 4;
end;

function TDoomLighting.FadeAttribute: TFloatVertexAttributeNode;
begin
  Result := TFloatVertexAttributeNode.Create;
  Result.NameField := 'doom_fade';
  Result.NumComponents := 4;
end;

function TDoomLighting.TileAttribute: TFloatVertexAttributeNode;
begin
  Result := TFloatVertexAttributeNode.Create;
  Result.NameField := 'doom_tile';
  Result.NumComponents := 4;
end;

function TDoomLighting.AtlasTextureEffect: TEffectNode;
var
  FragmentPart: TEffectPartNode;
begin
  Result := TEffectNode.Create;
  Result.Language := slGLSL;
  FragmentPart := TEffectPartNode.Create;
  FragmentPart.ShaderType := stFragment;
  FragmentPart.Contents := AtlasTextureFragment;
  Result.SetParts([FragmentPart]);
end;

function TDoomLighting.SkyTextureEffect(const Flipped: Boolean; const TextureHeight: Integer;
  out EyeField: TSFVec3f): TEffectNode;
var
  FragmentPart: TEffectPartNode;
begin
  Result := TEffectNode.Create;
  Result.Language := slGLSL;
  EyeField := TSFVec3f.Create(Result, true, 'doom_sky_eye', TVector3.Zero);
  Result.AddCustomField(EyeField);
  if Flipped then
    Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_sky_flip', -1))
  else
    Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_sky_flip', 1));
  Result.AddCustomField(TSFFloat.Create(Result, true, 'doom_sky_height', Max(1, TextureHeight)));
  FragmentPart := TEffectPartNode.Create;
  FragmentPart.ShaderType := stFragment;
  FragmentPart.Contents := SkyTextureFragment;
  Result.SetParts([FragmentPart]);
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

function TDoomLighting.LightVectors: TVector4List;
var
  I: Integer;
begin
  Result := TVector4List.Create;
  for I := 0 to MaxDynamicLights - 1 do
    Result.Add(Vector4(FLights[I].Position, FLights[I].Radius));
end;

function TDoomLighting.LightColors: TVector3List;
var
  I: Integer;
begin
  Result := TVector3List.Create;
  for I := 0 to MaxDynamicLights - 1 do
    Result.Add(FLights[I].Color);
end;

function TDoomLighting.DynamicLightCount: Integer;
begin
  Result := FLightCount;
end;

procedure TDoomLighting.SetDynamicLights(const Lights: array of TDynamicLight; const View: TMatrix4);
var
  I, Count: Integer;
  L: TDynamicLight;
  Changed: Boolean;
  E: TEffectNode;
  F: TX3DField;
  Vectors: TVector4List;
  Colors: TVector3List;
begin
  Count := Min(Length(Lights), MaxDynamicLights);
  Changed := Count <> FLightCount;
  for I := 0 to MaxDynamicLights - 1 do
  begin
    if I < Count then
      L := Lights[I]
    else
      L := Default(TDynamicLight);
    if (FLights[I].Radius <> L.Radius) or not TVector3.PerfectlyEquals(FLights[I].Position, L.Position) or
       not TVector3.PerfectlyEquals(FLights[I].Color, L.Color) then
    begin
      FLights[I] := L;
      Changed := true;
    end;
  end;
  if Changed then
  begin
    FLightCount := Count;
    Vectors := LightVectors;
    Colors := LightColors;
    try
      for E in FEffects do
      begin
        F := E.Field('doom_dlights');
        if F is TMFVec4f then TMFVec4f(F).Send(Vectors);
        F := E.Field('doom_dlight_colors');
        if F is TMFVec3f then TMFVec3f(F).Send(Colors);
        F := E.Field('doom_dlight_count');
        if F is TSFFloat then TSFFloat(F).Send(Count);
      end;
    finally
      FreeAndNil(Vectors);
      FreeAndNil(Colors);
    end;
  end;
  { The camera moves every frame; without lights the shader skips them. }
  if (Count > 0) and not TMatrix4.PerfectlyEquals(FView, View) then
  begin
    FView := View;
    for E in FEffects do
    begin
      F := E.Field('doom_view');
      if F is TSFMatrix4f then TSFMatrix4f(F).Send(View);
    end;
  end;
end;

function TDoomLighting.GammaExponent: Single;
begin
  Result := 1 / (1 + 0.3 * FGamma);
end;

procedure TDoomLighting.SetGamma(const Value: Integer);
begin
  if FGamma = Value then Exit;
  FGamma := Value;
  SendAll('doom_gamma', GammaExponent);
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
