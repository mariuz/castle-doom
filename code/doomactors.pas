{ Map things as CGE transforms: a billboard quad showing the right sprite
  frame and rotation, with Doom-style frame animation. Game logic (AI,
  movement, damage) lives in DoomWorld; this unit is only the visual actor. }
unit DoomActors;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleVectors, CastleTransform, CastleScene, CastleBehaviors, X3DNodes, X3DFields,
  DoomThings, DoomGraphics;

type
  TActorState = (asIdle, asChase, asAttack, asPain, asDying, asDead, asEffect, asMissile);

  TDoomActor = class(TCastleTransform)
  strict private
    FGraphics: TDoomGraphics;
    FScene: TCastleScene;
    FCoord: TCoordinateNode;
    FTexCoord: TTextureCoordinateNode;
    FAppearance: TAppearanceNode;
    FMaterial: TUnlitMaterialNode;
    FTexture: TImageTextureNode;
    { The doom_sprite uniform of the light effect (DoomLighting). }
    FLightField: TSFVec2f;
    FCurrentImage: TDoomImage;
    FCurrentMirror: Boolean;
    FFrame: Char;
    FRot: Integer;
    FSequence: String;
    FSeqIndex: Integer;
    FSeqTics: Integer;
    FSeqLoop: Boolean;
    FTicsLeft: Integer;
    procedure BuildScene;
  public
    { Profiling: what CGE's batching could merge: "texture|light group|kind"
      ('' while the actor has no sprite image). }
    function RenderKey: String;
  strict private
    procedure ApplySprite;
  public
    Info: PThingInfo;
    { Sprite prefix (normally Info^.Sprite, but explosions/puffs override). }
    SpritePrefix: String;
    { Position in Doom coordinates (Z = feet). }
    DoomX, DoomY, DoomZ: Single;
    { Facing angle in degrees, Doom convention (0 = east, counter-clockwise). }
    Angle: Single;
    Sector: Integer;
    State: TActorState;
    Health: Integer;
    { Monster AI: has seen the player. }
    Awake: Boolean;
    { Tics until the next AI decision / attack. }
    ReactionTics: Integer;
    { Original THINGS flags. }
    MapFlags: Integer;
    { Missiles: velocity in Doom units per tic and damage dice. }
    VelX, VelY, VelZ: Single;
    MissileDamageDice, MissileDamageFaces: Integer;
    { Sequence finished (non-looping) this tic. }
    SequenceDone: Boolean;
    { Set when the actor should be removed from the world. }
    Removed: Boolean;
    { Missiles: fired by the player (hits monsters, never the player). }
    FromPlayer: Boolean;
    { Missiles: the monster that fired it (nil for the player). }
    Shooter: TDoomActor;
    { Monsters: who they are after; nil means the player. }
    Target: TDoomActor;
    { Lost souls: flying at the target (A_SkullAttack / MF_SKULLFLY). }
    Charging: Boolean;
    { Flyer that rose or sank towards an opening this tic (MF_INFLOAT). }
    InFloat: Boolean;
    { Items dropped by a dead monster (MF_DROPPED): a crusher destroys them. }
    Dropped: Boolean;
    ChargeTics: Integer;
    { Arch-vile: the attack's damage already dealt this attack. }
    AttackFired: Boolean;
    { Arch-vile: its fire on the target during the attack. }
    Fire: TDoomActor;
    { Monsters: where they were spawned (Nightmare respawn) and how long the
      corpse has lain there. }
    SpawnX, SpawnY, SpawnAngle: Single;
    DeadTics: Integer;
    { MF_SHADOW (the spectre): drawn as Doom's "fuzz", a shimmering dark
      silhouette that darkens whatever is behind it. }
    Fuzz: Boolean;
    { Fullbright sprite (explosions, projectiles, some items). }
    Bright: Boolean;

    constructor Create(AOwner: TComponent; const AGraphics: TDoomGraphics;
      const AInfo: PThingInfo); reintroduce;
    { Start playing a frame sequence like 'ABCD' at TicsPerFrame tics each. }
    procedure PlaySequence(const Frames: String; const TicsPerFrame: Integer; const Loop: Boolean);
    { Advance the animation by one Doom tic. }
    procedure AnimateTic;
    { Pick the sprite rotation for a viewer at (ViewerX, ViewerY) in Doom coords. }
    procedure UpdateRotation(const ViewerX, ViewerY: Single);
    { Apply the position (DoomX/Y/Z) to the CGE transform. }
    procedure UpdateTransform;
    { Sector light level -> sprite brightness. }
    procedure SetLight(const Light: Integer);
    property Frame: Char read FFrame;
    { Save games: the current frame sequence and position in it. }
    procedure GetAnimation(out Frames: String; out Index, Tics, TicsLeft: Integer; out Loop: Boolean);
    procedure SetAnimation(const Frames: String; const Index, Tics, TicsLeft: Integer; const Loop: Boolean);
    property Scene: TCastleScene read FScene;
  end;

  TDoomActorList = {$ifdef FPC}specialize{$endif} TObjectList<TDoomActor>;

implementation

uses Math, CastleUtils, CastleLog, CastleRenderOptions,
  DoomGeometry, DoomLighting;

constructor TDoomActor.Create(AOwner: TComponent; const AGraphics: TDoomGraphics;
  const AInfo: PThingInfo);
var
  Billboard: TCastleBillboard;
begin
  inherited Create(AOwner);
  FGraphics := AGraphics;
  Info := AInfo;
  SpritePrefix := Info^.Sprite;
  Health := Info^.Health;
  FRot := 1;
  FFrame := 'A';
  BuildScene;
  Fuzz := Info^.Num = 58;
  if Fuzz then
  begin
    { Blended: the DoomLighting shader turns the sprite into black specks
      of Doom's fuzzoffset pattern, which the background shows through. }
    FAppearance.AlphaMode := amBlend;
    FMaterial.EmissiveColor := Vector3(0, 0, 0);
  end;
  Billboard := TCastleBillboard.Create(Self);
  Billboard.AxisOfRotation := Vector3(0, 1, 0);
  AddBehavior(Billboard);
  Collides := Info^.Solid;
  { Only monsters and barrels stop bullets. }
  Pickable := (Info^.Kind = tkMonster) or (Info^.Num = 2035);
  PlaySequence(Info^.IdleFrames, Info^.IdleTics, true);
end;

procedure TDoomActor.BuildScene;
var
  Props: TTexturePropertiesNode;
  Root: TX3DRootNode;
  Shape: TShapeNode;
  Geometry: TIndexedTriangleSetNode;
begin
  FCoord := TCoordinateNode.Create;
  FCoord.SetPoint([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 2, 0), Vector3(-1, 2, 0)]);
  FTexCoord := TTextureCoordinateNode.Create;
  FTexCoord.SetPoint([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]);
  Geometry := TIndexedTriangleSetNode.Create;
  Geometry.Coord := FCoord;
  Geometry.TexCoord := FTexCoord;
  Geometry.SetIndex([0, 1, 2, 0, 2, 3]);
  Geometry.Solid := false;
  FMaterial := TUnlitMaterialNode.Create;
  FAppearance := TAppearanceNode.Create;
  FAppearance.Material := FMaterial;
  FAppearance.AlphaMode := amMask;
  FTexture := TImageTextureNode.Create;
  FTexture.RepeatS := false;
  FTexture.RepeatT := false;
  { Like CGE's own sprite sheets: GuiTexture means no power-of-two resize and
    no mipmaps. Sprites have odd sizes (36x48...) and there are hundreds per
    level; resizing and mipmapping each one on the CPU kept the web build at
    about 1 FPS while a level's sprites were first shown. Nearest filtering
    is also the crisp Doom look. }
  Props := TTexturePropertiesNode.Create;
  Props.GuiTexture := true;
  Props.MagnificationFilter := magNearest;
  Props.MinificationFilter := minNearest;
  Props.BoundaryModeS := bmClampToEdge;
  Props.BoundaryModeT := bmClampToEdge;
  FTexture.TextureProperties := Props;
  FAppearance.Texture := FTexture;
  Shape := TShapeNode.Create;
  Shape.Appearance := FAppearance;
  Shape.Geometry := Geometry;
  Root := TX3DRootNode.Create;
  { The light effect in the root, not in the appearance: CGE's dynamic
    batching compares group effects but not appearance effects, so sprites
    with different lights must not share an appearance-level effect. }
  Root.AddChildren(DoomLightingInstance.SpriteEffect(FLightField));
  Root.AddChildren(Shape);
  FScene := TCastleScene.Create(Self);
  FScene.Load(Root, true);
  Add(FScene);
end;

function TDoomActor.RenderKey: String;
begin
  if (FCurrentImage = nil) or not FScene.Exists then Exit('');
  Result := Format('%s|%d|%d', [FCurrentImage.Url, Round(FLightField.Value.X) div 16, Round(FLightField.Value.Y)]);
end;

procedure TDoomActor.ApplySprite;
var
  Img: TDoomImage;
  Mirror: Boolean;
  X0, X1, Y0, Y1: Single;
begin
  Img := FGraphics.Sprite(SpritePrefix, FFrame, FRot, Mirror);
  if Img = nil then
  begin
    FScene.Exists := false;
    Exit;
  end;
  FScene.Exists := true;
  if (Img = FCurrentImage) and (Mirror = FCurrentMirror) then Exit;
  FCurrentImage := Img;
  FCurrentMirror := Mirror;
  { Doom sprite offsets: LeftOffset pixels from the left edge to the origin,
    TopOffset pixels from the top edge down to the origin (the feet). }
  X0 := -Img.LeftOffset;
  X1 := Img.Width - Img.LeftOffset;
  Y1 := Img.TopOffset;
  Y0 := Img.TopOffset - Img.Height;
  if Mirror then
  begin
    X0 := -X0;
    X1 := -X1;
  end;
  FCoord.SetPoint([Vector3(X0, Y0, 0), Vector3(X1, Y0, 0), Vector3(X1, Y1, 0), Vector3(X0, Y1, 0)]);
  FTexture.SetUrl([Img.Url]);
end;

procedure TDoomActor.PlaySequence(const Frames: String; const TicsPerFrame: Integer; const Loop: Boolean);
begin
  FSequence := Frames;
  if FSequence = '' then FSequence := 'A';
  FSeqIndex := 0;
  FSeqTics := Max(1, TicsPerFrame);
  FSeqLoop := Loop;
  FTicsLeft := FSeqTics;
  SequenceDone := false;
  FFrame := FSequence[1];
  ApplySprite;
end;

procedure TDoomActor.GetAnimation(out Frames: String; out Index, Tics, TicsLeft: Integer; out Loop: Boolean);
begin
  Frames := FSequence;
  Index := FSeqIndex;
  Tics := FSeqTics;
  TicsLeft := FTicsLeft;
  Loop := FSeqLoop;
end;

procedure TDoomActor.SetAnimation(const Frames: String; const Index, Tics, TicsLeft: Integer; const Loop: Boolean);
begin
  FSequence := Frames;
  if FSequence = '' then FSequence := 'A';
  FSeqIndex := Clamped(Index, 0, Length(FSequence) - 1);
  FSeqTics := Max(1, Tics);
  FTicsLeft := Max(1, TicsLeft);
  FSeqLoop := Loop;
  SequenceDone := false;
  FFrame := FSequence[FSeqIndex + 1];
  ApplySprite;
end;

procedure TDoomActor.AnimateTic;
begin
  SequenceDone := false;
  if Length(FSequence) <= 1 then
  begin
    if (not FSeqLoop) and (FTicsLeft > 0) then
    begin
      Dec(FTicsLeft);
      if FTicsLeft = 0 then SequenceDone := true;
    end;
    Exit;
  end;
  Dec(FTicsLeft);
  if FTicsLeft <= 0 then
  begin
    FTicsLeft := FSeqTics;
    Inc(FSeqIndex);
    if FSeqIndex > Length(FSequence) - 1 then
    begin
      if FSeqLoop then
        FSeqIndex := 0
      else
      begin
        FSeqIndex := Length(FSequence) - 1;
        SequenceDone := true;
        Exit;
      end;
    end;
    FFrame := FSequence[FSeqIndex + 1];
    ApplySprite;
  end;
end;

procedure TDoomActor.UpdateRotation(const ViewerX, ViewerY: Single);
var
  Ang, Delta: Single;
  NewRot: Integer;
begin
  { Doom: rot = (angle_to_thing - thing_angle + 202.5 deg) / 45 deg }
  Ang := RadToDeg(ArcTan2(DoomY - ViewerY, DoomX - ViewerX));
  Delta := Ang - Angle + 202.5;
  Delta := Delta - Floor(Delta / 360) * 360;
  NewRot := Trunc(Delta / 45) + 1;
  if NewRot > 8 then NewRot := 8;
  if NewRot <> FRot then
  begin
    FRot := NewRot;
    ApplySprite;
  end;
end;

procedure TDoomActor.UpdateTransform;
begin
  Translation := DoomToCge(DoomX, DoomY, DoomZ);
end;

procedure TDoomActor.SetLight(const Light: Integer);
var
  V: TVector2;
begin
  { The colour itself comes from the light effect (Doom's colormaps by
    distance); spectres stay black (their fuzz), full-bright things use
    colormap 0. }
  if Fuzz then
    V := Vector2(Light, DoomLightFuzz)
  else
  if Bright then
    V := Vector2(Light, DoomLightFullBright)
  else
    V := Vector2(Light, DoomLightWall);
  if not TVector2.PerfectlyEquals(FLightField.Value, V) then
    FLightField.Send(V);
end;

end.
