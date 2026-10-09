{ Map things as CGE transforms: a billboard quad showing the right sprite
  frame and rotation, with Doom-style frame animation. Game logic (AI,
  movement, damage) lives in DoomWorld; this unit is only the visual actor.

  The quads are not rendered one scene per thing: TSpriteBatch keeps one
  TCastleScene per light group and kind (the doom_sprite uniform of the
  DoomLighting effect is per scene), each thing's quad is a TTransformNode
  in the scene of its light, and CGE's dynamic batching merges the quads
  with the same texture into one draw call. One scene per thing was a draw
  call and a scene visit per thing every frame (104 of 255 draw calls on
  E1M1's start); a custom vertex attribute for the light would have stopped
  the batching. Each thing keeps a small invisible scene of its own for the
  player's collisions. }
unit DoomActors;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleVectors, CastleTransform, CastleScene, CastleBehaviors, X3DNodes, X3DFields,
  DoomThings, DoomGraphics;

type
  TActorState = (asIdle, asChase, asAttack, asPain, asDying, asDead, asEffect, asMissile);

  TSpriteBatch = class;
  TSpriteGroup = class;

  TDoomActor = class(TCastleTransform)
  strict private
    FGraphics: TDoomGraphics;
    FBatch: TSpriteBatch;
    { The invisible quad the player collides with (its own nodes: one
      node cannot be in two scenes). }
    FScene: TCastleScene;
    FCollCoord: TCoordinateNode;
    { The drawn quad, in a TSpriteBatch scene. }
    FNode: TTransformNode;
    FShape: TShapeNode;
    FGroup: TSpriteGroup;
    FCoord: TCoordinateNode;
    FTexCoord: TTextureCoordinateNode;
    FAppearance: TAppearanceNode;
    FMaterial: TUnlitMaterialNode;
    FTexture: TImageTextureNode;
    { Light level and kind (the doom_sprite uniform of the scene the quad is in). }
    FLightValue: TVector2;
    FHidden, FShown: Boolean;
    FYaw: Single;
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
    procedure SetShown(const Shown: Boolean);
  public
    { Profiling: what CGE's batching merges: "texture|light group|kind"
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
      const ABatch: TSpriteBatch; const AInfo: PThingInfo); reintroduce;
    destructor Destroy; override;
    { Never draw this thing (teleport destinations, boss spots). }
    procedure HideSprite;
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

  { One scene of a TSpriteBatch: the things of one light group and kind. }
  TSpriteGroup = class
    Root: TX3DRootNode;
    Scene: TCastleScene;
    { The light effect, set on every member's Appearance (an Effect node
      in the graph would give each shape its own State.Effects list, which
      CGE's dynamic batching compares by pointer, so nothing would merge). }
    Effect: TEffectNode;
  end;
  TGroupDict = {$ifdef FPC}specialize{$endif} TDictionary<Integer, TSpriteGroup>;

  { The scenes the things are drawn in: one per light group (sector light
    div 16, what the shader rounds to anyway) and kind (normal, full
    bright, fuzz), made as needed and added to the world's items. Within a
    scene CGE's dynamic batching merges the quads with the same texture. }
  TSpriteBatch = class
  strict private
    FParent: TCastleTransform;
    FGroups: TGroupDict;
  public
    { The player's view angle (Doom degrees): the quads face the camera
      like Doom's screen-aligned sprites (set every tic by the world). }
    ViewAngle: Single;
    constructor Create(const AParent: TCastleTransform);
    destructor Destroy; override;
    { The group for a light level (0..255) and kind (DoomLight*). }
    function GroupFor(const Light, Kind: Integer): TSpriteGroup;
    { Put a thing's quad (its transform and appearance) into a group /
      take it out again. }
    procedure Attach(const Group: TSpriteGroup; const Node: TTransformNode;
      const Appearance: TAppearanceNode);
    procedure Detach(const Group: TSpriteGroup; const Node: TTransformNode;
      const Appearance: TAppearanceNode);
    function SceneCount: Integer;
    { Show / hide all the drawn quads (profiling). }
    procedure SetVisible(const Value: Boolean);
  end;

implementation

uses Math, CastleUtils, CastleLog, CastleRenderOptions, CastleSceneCore,
  DoomGeometry, DoomLighting;

{ TSpriteBatch ------------------------------------------------------------- }

constructor TSpriteBatch.Create(const AParent: TCastleTransform);
begin
  inherited Create;
  FParent := AParent;
  FGroups := TGroupDict.Create;
end;

destructor TSpriteBatch.Destroy;
var
  Group: TSpriteGroup;
begin
  if FGroups <> nil then
    for Group in FGroups.Values do
    begin
      FParent.Remove(Group.Scene);
      Group.Scene.Free;
      Group.Effect.KeepExistingEnd;
      Group.Effect.FreeIfUnused;
      Group.Free;
    end;
  FreeAndNil(FGroups);
  inherited;
end;

function TSpriteBatch.GroupFor(const Light, Kind: Integer): TSpriteGroup;
var
  Key: Integer;
  LightField: TSFVec2f;
begin
  Key := (Light div 16) * 100 + Kind;
  if not FGroups.TryGetValue(Key, Result) then
  begin
    Result := TSpriteGroup.Create;
    Result.Effect := DoomLightingInstance.SpriteEffect(LightField);
    Result.Effect.KeepExistingBegin;
    LightField.Value := Vector2((Light div 16) * 16, Kind);
    Result.Root := TX3DRootNode.Create;
    Result.Scene := TCastleScene.Create(nil);
    Result.Scene.Name := '';
    Result.Scene.Collides := false;
    Result.Scene.Pickable := false;
    Result.Scene.CastShadows := false;
    Result.Scene.Load(Result.Root, true);
    FParent.Add(Result.Scene);
    FGroups.Add(Key, Result);
  end;
end;

procedure TSpriteBatch.Attach(const Group: TSpriteGroup; const Node: TTransformNode;
  const Appearance: TAppearanceNode);
begin
  Appearance.SetEffects([Group.Effect]);
  { Adding children rebuilds the scene's shape tree (ChangedAll), but CGE
    (snapshot, castlescenecore.pas ChangedAll -> BeforeNodesFree(true))
    keeps its list of transforms changed since the last frame
    (TransformationDirty) pointing at the freed tree: the next Update then
    crashed with a corrupt depth (EOutOfMemory) once a thing had moved in
    the same frame a thing was added to its scene. BeforeNodesFree without
    the flag clears that list; the rebuild recomputes the transforms anyway. }
  Group.Scene.BeforeNodesFree;
  Group.Root.AddChildren(Node);
end;

procedure TSpriteBatch.Detach(const Group: TSpriteGroup; const Node: TTransformNode;
  const Appearance: TAppearanceNode);
begin
  Group.Root.RemoveChildren(Node);
  Appearance.SetEffects([]);
  { CGE keeps Node.Scene after a removal and warns when another scene
    picks the node up; forget the old scene for the whole subtree. }
  Node.UnregisterScene;
end;

function TSpriteBatch.SceneCount: Integer;
begin
  Result := FGroups.Count;
end;

procedure TSpriteBatch.SetVisible(const Value: Boolean);
var
  Group: TSpriteGroup;
begin
  for Group in FGroups.Values do
    Group.Scene.Visible := Value;
end;

{ TDoomActor ---------------------------------------------------------------- }

constructor TDoomActor.Create(AOwner: TComponent; const AGraphics: TDoomGraphics;
  const ABatch: TSpriteBatch; const AInfo: PThingInfo);
var
  Billboard: TCastleBillboard;
begin
  inherited Create(AOwner);
  FGraphics := AGraphics;
  FBatch := ABatch;
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
  { The quad joins a batch scene with the world's first SetLight (every
    spawn calls it after setting Bright / Fuzz, and TicActors each tic);
    joining here would rebuild two scenes' shape trees per spawn for nothing. }
  { Only monsters and barrels stop bullets. }
  Pickable := (Info^.Kind = tkMonster) or (Info^.Num = 2035);
  PlaySequence(Info^.IdleFrames, Info^.IdleTics, true);
end;

destructor TDoomActor.Destroy;
begin
  if FGroup <> nil then
    FBatch.Detach(FGroup, FNode, FAppearance);
  FGroup := nil;
  if FNode <> nil then
  begin
    FNode.KeepExistingEnd;
    FNode.FreeIfUnused;
    FNode := nil;
  end;
  inherited;
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
  FShape := TShapeNode.Create;
  FShape.Appearance := FAppearance;
  FShape.Geometry := Geometry;
  { The drawn quad lives in a TSpriteBatch scene (SetLight puts it there);
    the node outlives its moves between scenes. }
  FNode := TTransformNode.Create;
  FNode.AddChildren(FShape);
  FNode.KeepExistingBegin;

  { The collision quad: the same corners, no texture, never drawn. }
  FCollCoord := TCoordinateNode.Create;
  FCollCoord.SetPoint([Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(1, 2, 0), Vector3(-1, 2, 0)]);
  Geometry := TIndexedTriangleSetNode.Create;
  Geometry.Coord := FCollCoord;
  Geometry.SetIndex([0, 1, 2, 0, 2, 3]);
  Geometry.Solid := false;
  Shape := TShapeNode.Create;
  Shape.Geometry := Geometry;
  Root := TX3DRootNode.Create;
  Root.AddChildren(Shape);
  FScene := TCastleScene.Create(Self);
  FScene.Load(Root, true);
  FScene.Visible := false;
  Add(FScene);
  FShown := true; { the nodes' defaults: Render and Exists }
end;

procedure TDoomActor.SetShown(const Shown: Boolean);
begin
  { ApplySprite calls this every tic for every thing; an X3D field Send
    is a change event for the batch scene even when the value stays. }
  if FShown = Shown then Exit;
  FShown := Shown;
  FShape.Render := Shown;
  FScene.Exists := Shown;
end;

procedure TDoomActor.HideSprite;
begin
  FHidden := true;
  SetShown(false);
end;

function TDoomActor.RenderKey: String;
begin
  if (FCurrentImage = nil) or not FShape.Render then Exit('');
  Result := Format('%s|%d|%d', [FCurrentImage.Url, Round(FLightValue.X) div 16, Round(FLightValue.Y)]);
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
    SetShown(false);
    Exit;
  end;
  SetShown(not FHidden);
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
  FCollCoord.SetPoint([Vector3(X0, Y0, 0), Vector3(X1, Y0, 0), Vector3(X1, Y1, 0), Vector3(X0, Y1, 0)]);
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
var
  T: TVector3;
  A, Yaw: Single;
begin
  T := DoomToCge(DoomX, DoomY, DoomZ);
  Translation := T;
  if not TVector3.PerfectlyEquals(FNode.Translation, T) then
    FNode.Translation := T;
  { Face the camera like Doom's screen-aligned sprites: the quad's +Z
    (local) turned against the view direction (cos A, sin A) in Doom
    coordinates, (cos A, 0, -sin A) in CGE's. }
  A := DegToRad(FBatch.ViewAngle);
  Yaw := ArcTan2(-Cos(A), Sin(A));
  if Abs(Yaw - FYaw) > 0.0005 then
  begin
    FYaw := Yaw;
    FNode.Rotation := Vector4(0, 1, 0, Yaw);
  end;
end;

procedure TDoomActor.SetLight(const Light: Integer);
var
  V: TVector2;
  NewGroup: TSpriteGroup;
begin
  { The colour itself comes from the light effect (Doom's colormaps by
    distance); spectres stay black (their fuzz), full-bright things use
    colormap 0. The quad goes to the batch scene of its light group. }
  if Fuzz then
    V := Vector2(Light, DoomLightFuzz)
  else
  if Bright then
    V := Vector2(Light, DoomLightFullBright)
  else
    V := Vector2(Light, DoomLightWall);
  if TVector2.PerfectlyEquals(FLightValue, V) and (FGroup <> nil) then Exit;
  FLightValue := V;
  NewGroup := FBatch.GroupFor(Light, Round(V.Y));
  if NewGroup <> FGroup then
  begin
    if FGroup <> nil then
      FBatch.Detach(FGroup, FNode, FAppearance);
    FBatch.Attach(NewGroup, FNode, FAppearance);
    FGroup := NewGroup;
  end;
end;

end.
