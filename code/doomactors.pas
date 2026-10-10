{ Map things as CGE transforms: a billboard quad showing the right sprite
  frame and rotation, with Doom-style frame animation. Game logic (AI,
  movement, damage) lives in DoomWorld; this unit is only the visual actor.

  The quads are not rendered one scene per thing: TSpriteBatch keeps one
  TCastleScene per light group and kind (the doom_sprite uniform of the
  DoomLighting effect is per scene) and, in it, one shape per sprite
  texture holding the quads of every thing showing that texture (four
  vertices and six indices each, written in world space every tic). So a
  draw call is a texture in a light, whatever the number of things, and
  the shapes live on: a thing changing frame, light or visibility only
  edits index and vertex lists. One scene per thing was a draw call and a
  scene visit per thing every frame (104 of 255 draw calls on E1M1's
  start); CGE's dynamic batching merged only 8 textures a pass and its
  pool shapes relinked the sprite shaders several times a second (40 ms a
  frame in the browser). Each thing keeps a small invisible scene of its
  own for the player's collisions. }
unit DoomActors;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleVectors, CastleTransform, CastleScene, CastleBehaviors, X3DNodes, X3DFields,
  DoomThings, DoomGraphics, DoomStates;

type
  TActorState = (asIdle, asChase, asAttack, asPain, asDying, asDead, asEffect, asMissile);

  TSpriteBatch = class;
  TSpriteGroup = class;
  TSpriteShape = class;

  TDoomActor = class(TCastleTransform)
  strict private
    FGraphics: TDoomGraphics;
    FBatch: TSpriteBatch;
    { The invisible quad the player collides with. }
    FScene: TCastleScene;
    FCollCoord: TCoordinateNode;
    { Where the drawn quad is: the light group's scene, the texture's
      shape in it and the quad's slot there (-1 = not drawn). }
    FGroup: TSpriteGroup;
    FShape: TSpriteShape;
    FSlot: Integer;
    { The quad's corners around the feet (mirrored sprites have X0 > X1). }
    FX0, FX1, FY0, FY1: Single;
    { The corners last written to the shape, to skip unchanged ticks. }
    FLast: array [0..3] of TVector3;
    FLastValid: Boolean;
    { Light level and kind (the doom_sprite uniform of the scene the quad is in). }
    FLightValue: TVector2;
    FHidden, FShown: Boolean;
    FCurrentImage: TDoomImage;
    FCurrentMirror: Boolean;
    FFrame: Char;
    FRot: Integer;
    FSequence: String;
    FSeqIndex: Integer;
    FSeqTics: Integer;
    FSeqLoop: Boolean;
    FTicsLeft: Integer;
    { Per-frame data of a sequence from the state table (PlayStates):
      empty Tics means the uniform PlaySequence kind. }
    FSeq: TFrameSeq;
    { The current frame is full bright in the state table. }
    FFrameBright: Boolean;
    FLastLight: Integer;
    { Sprite and brightness of frame FSeqIndex of FSeq. }
    procedure ApplyFrameData;
    procedure BuildScene;
    procedure SetShown(const Shown: Boolean);
    { Put the quad in the shape it belongs to now (or in none). }
    procedure UpdateMembership;
    procedure WriteCorners;
  public
    { Profiling: the draw call the quad is part of: "texture|light group|kind"
      ('' while the actor has no sprite image or is not drawn). }
    function RenderKey: String;
    { TSpriteShape bookkeeping. }
    property Slot: Integer read FSlot write FSlot;
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
    { Start playing a sequence from the state table: each frame with its
      own tics, sprite, brightness and action. Loops when Loop or the
      sequence itself loops. An empty sequence plays frame 'A'. }
    procedure PlayStates(const Seq: TFrameSeq; const Loop: Boolean);
    { The current frame's code pointer (saNone for PlaySequence frames). }
    function CurrentAction: TStateAction;
    { Advance the animation by one Doom tic. }
    procedure AnimateTic;
    { Pick the sprite rotation for a viewer at (ViewerX, ViewerY) in Doom coords. }
    procedure UpdateRotation(const ViewerX, ViewerY: Single);
    { Apply the position (DoomX/Y/Z) to the CGE transform and the drawn quad. }
    procedure UpdateTransform;
    { Sector light level -> sprite brightness. }
    procedure SetLight(const Light: Integer);
    property Frame: Char read FFrame;
    { Save games: the current frame sequence and position in it (Seq's
      Tics empty for a PlaySequence animation, else its per-frame data). }
    procedure GetAnimation(out Frames: String; out Index, Tics, TicsLeft: Integer; out Loop: Boolean);
    procedure SetAnimation(const Frames: String; const Index, Tics, TicsLeft: Integer; const Loop: Boolean);
    procedure GetAnimationSeq(out Seq: TFrameSeq);
    procedure SetAnimationSeq(const Seq: TFrameSeq; const Index, TicsLeft: Integer; const Loop: Boolean);
    property Scene: TCastleScene read FScene;
  end;

  TDoomActorList = {$ifdef FPC}specialize{$endif} TObjectList<TDoomActor>;

  { The quads of one texture in one TSpriteGroup: one shape, so one draw
    call. Slot I of a member is vertices 4 I .. 4 I + 3 and indices
    6 I .. 6 I + 5; a removed member's slot is filled by the last one. }
  TSpriteShape = class
    Shape: TShapeNode;
    Geometry: TIndexedTriangleSetNode;
    Coord: TCoordinateNode;
    TexCoord: TTextureCoordinateNode;
    Members: TDoomActorList;
    { Pending change events (TSpriteBatch.Flush sends them once a frame). }
    CoordsDirty, IndexDirty: Boolean;
    constructor Create(const Url: String; const Kind: Integer);
    destructor Destroy; override;
    procedure Add(const A: TDoomActor);
    procedure Remove(const A: TDoomActor);
    procedure Flush;
  end;
  TSpriteShapeDict = {$ifdef FPC}specialize{$endif} TDictionary<String, TSpriteShape>;

  { One scene of a TSpriteBatch: the things of one light group and kind. }
  TSpriteGroup = class
    Root: TX3DRootNode;
    Scene: TCastleScene;
    Kind: Integer;
    { The light effect on every shape's Appearance. }
    Effect: TEffectNode;
    Shapes: TSpriteShapeDict;
    destructor Destroy; override;
    { The shape for a texture URL, made (and added to the scene) on demand. }
    function ShapeFor(const Url: String): TSpriteShape;
  end;
  TGroupDict = {$ifdef FPC}specialize{$endif} TDictionary<Integer, TSpriteGroup>;

  { The scenes the things are drawn in: one per light group (sector light
    div 16, what the shader rounds to anyway) and kind (normal, full
    bright, fuzz), made as needed and added to the world's items. }
  TSpriteBatch = class
  strict private
    FParent: TCastleTransform;
    FGroups: TGroupDict;
    FViewAngle: Single;
    FRight: TVector3;
    procedure SetViewAngle(const Value: Single);
  public
    constructor Create(const AParent: TCastleTransform);
    destructor Destroy; override;
    { The player's view angle (Doom degrees): the quads face the camera
      like Doom's screen-aligned sprites (set every tic by the world). }
    property ViewAngle: Single read FViewAngle write SetViewAngle;
    { The quads' horizontal axis in CGE coordinates for ViewAngle. }
    property Right: TVector3 read FRight;
    { The group for a light level (0..255) and kind (DoomLight*). }
    function GroupFor(const Light, Kind: Integer): TSpriteGroup;
    { Send the frame's vertex and index changes to the scenes (the world
      calls it once per Update, after the tics). }
    procedure Flush;
    function SceneCount: Integer;
    { Shapes with at least one quad (the sprites' draw calls). }
    function ShapeCount: Integer;
    { Show / hide all the drawn quads (profiling). }
    procedure SetVisible(const Value: Boolean);
  end;

implementation

uses Math, CastleUtils, CastleLog, CastleRenderOptions, CastleSceneCore,
  DoomGeometry, DoomLighting;

{ TSpriteShape --------------------------------------------------------------- }

constructor TSpriteShape.Create(const Url: String; const Kind: Integer);
var
  Props: TTexturePropertiesNode;
  Texture: TImageTextureNode;
  Material: TUnlitMaterialNode;
  Appearance: TAppearanceNode;
begin
  inherited Create;
  Members := TDoomActorList.Create(false);
  Coord := TCoordinateNode.Create;
  TexCoord := TTextureCoordinateNode.Create;
  Geometry := TIndexedTriangleSetNode.Create;
  Geometry.Coord := Coord;
  Geometry.TexCoord := TexCoord;
  Geometry.Solid := false;
  Material := TUnlitMaterialNode.Create;
  Appearance := TAppearanceNode.Create;
  Appearance.Material := Material;
  Appearance.AlphaMode := amMask;
  if Kind = DoomLightFuzz then
  begin
    { Blended: the DoomLighting shader turns the sprite into black specks
      of Doom's fuzzoffset pattern, which the background shows through. }
    Appearance.AlphaMode := amBlend;
    Material.EmissiveColor := Vector3(0, 0, 0);
  end;
  Texture := TImageTextureNode.Create;
  Texture.SetUrl([Url]);
  Texture.RepeatS := false;
  Texture.RepeatT := false;
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
  Texture.TextureProperties := Props;
  Appearance.Texture := Texture;
  Shape := TShapeNode.Create;
  Shape.Appearance := Appearance;
  Shape.Geometry := Geometry;
  { Empty until the first quad. }
  Shape.Render := false;
end;

destructor TSpriteShape.Destroy;
begin
  FreeAndNil(Members);
  inherited;
end;

procedure TSpriteShape.Add(const A: TDoomActor);
var
  Base: Integer;
begin
  A.Slot := Members.Count;
  Members.Add(A);
  Base := A.Slot * 4;
  Coord.FdPoint.Items.Count := Base + 4;
  TexCoord.FdPoint.Items.Count := Base + 4;
  TexCoord.FdPoint.Items[Base] := Vector2(0, 0);
  TexCoord.FdPoint.Items[Base + 1] := Vector2(1, 0);
  TexCoord.FdPoint.Items[Base + 2] := Vector2(1, 1);
  TexCoord.FdPoint.Items[Base + 3] := Vector2(0, 1);
  Geometry.FdIndex.Items.AddRange([Base, Base + 1, Base + 2, Base, Base + 2, Base + 3]);
  IndexDirty := true;
  CoordsDirty := true;
end;

procedure TSpriteShape.Remove(const A: TDoomActor);
var
  I, Last, J: Integer;
  B: TDoomActor;
begin
  I := A.Slot;
  Last := Members.Count - 1;
  if (I < 0) or (I > Last) or (Members[I] <> A) then Exit;
  if I <> Last then
  begin
    { The last quad takes the freed slot (its texture coordinates are the
      same in every slot, the indices refer to the slot). }
    B := Members[Last];
    Members[I] := B;
    B.Slot := I;
    for J := 0 to 3 do
      Coord.FdPoint.Items[I * 4 + J] := Coord.FdPoint.Items[Last * 4 + J];
  end;
  Members.Delete(Last);
  A.Slot := -1;
  Coord.FdPoint.Items.Count := Last * 4;
  TexCoord.FdPoint.Items.Count := Last * 4;
  Geometry.FdIndex.Items.Count := Last * 6;
  IndexDirty := true;
  CoordsDirty := true;
end;

procedure TSpriteShape.Flush;
begin
  if IndexDirty then
  begin
    { A different vertex count: the whole geometry again. }
    Geometry.FdIndex.Changed;
    TexCoord.FdPoint.Changed;
    Coord.FdPoint.Changed;
    if Shape.Render <> (Members.Count > 0) then
      Shape.Render := Members.Count > 0;
  end else
  if CoordsDirty then
    Coord.FdPoint.Changed;
  IndexDirty := false;
  CoordsDirty := false;
end;

{ TSpriteGroup --------------------------------------------------------------- }

destructor TSpriteGroup.Destroy;
var
  S: TSpriteShape;
begin
  if Shapes <> nil then
    for S in Shapes.Values do
      S.Free;
  FreeAndNil(Shapes);
  inherited;
end;

function TSpriteGroup.ShapeFor(const Url: String): TSpriteShape;
begin
  if not Shapes.TryGetValue(Url, Result) then
  begin
    Result := TSpriteShape.Create(Url, Kind);
    Result.Shape.Appearance.SetEffects([Effect]);
    Shapes.Add(Url, Result);
    { Adding children rebuilds the scene's shape tree (ChangedAll), but CGE
      (snapshot, castlescenecore.pas ChangedAll -> BeforeNodesFree(true))
      keeps its list of transforms changed since the last frame
      (TransformationDirty) pointing at the freed tree, which crashed the
      next Update once; BeforeNodesFree without the flag clears it. This
      happens once per texture in a light group, not per thing. }
    Scene.BeforeNodesFree;
    Root.AddChildren(Result.Shape);
  end;
end;

{ TSpriteBatch ------------------------------------------------------------- }

constructor TSpriteBatch.Create(const AParent: TCastleTransform);
begin
  inherited Create;
  FParent := AParent;
  FGroups := TGroupDict.Create;
  FRight := Vector3(1, 0, 0);
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

procedure TSpriteBatch.SetViewAngle(const Value: Single);
var
  A: Single;
begin
  FViewAngle := Value;
  { Face the camera like Doom's screen-aligned sprites: the quad's width
    runs along (sin A, -cos A) in Doom coordinates, which is (sin A, 0,
    cos A) in CGE's (Z = -Doom Y). }
  A := DegToRad(Value);
  FRight := Vector3(Sin(A), 0, Cos(A));
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
    Result.Kind := Kind;
    Result.Shapes := TSpriteShapeDict.Create;
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

procedure TSpriteBatch.Flush;
var
  Group: TSpriteGroup;
  S: TSpriteShape;
begin
  for Group in FGroups.Values do
    for S in Group.Shapes.Values do
      if S.IndexDirty or S.CoordsDirty then
        S.Flush;
end;

function TSpriteBatch.SceneCount: Integer;
begin
  Result := FGroups.Count;
end;

function TSpriteBatch.ShapeCount: Integer;
var
  Group: TSpriteGroup;
  S: TSpriteShape;
begin
  Result := 0;
  for Group in FGroups.Values do
    for S in Group.Shapes.Values do
      if S.Members.Count > 0 then Inc(Result);
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
  FSlot := -1;
  FShown := true;
  BuildScene;
  Fuzz := Info^.Shadow;
  Billboard := TCastleBillboard.Create(Self);
  Billboard.AxisOfRotation := Vector3(0, 1, 0);
  AddBehavior(Billboard);
  Collides := Info^.Solid;
  { The quad is drawn from the world's first SetLight on (every spawn
    calls it after setting Bright / Fuzz, and TicActors each tic). }
  { Only monsters and barrels stop bullets. }
  Pickable := (Info^.Kind = tkMonster) or (Info^.Num = 2035);
  PlaySequence(Info^.IdleFrames, Info^.IdleTics, true);
end;

destructor TDoomActor.Destroy;
begin
  if FShape <> nil then
    FShape.Remove(Self);
  FShape := nil;
  FGroup := nil;
  inherited;
end;

procedure TDoomActor.BuildScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  Geometry: TIndexedTriangleSetNode;
begin
  { The collision quad: the sprite's corners, no texture, never drawn. }
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
end;

procedure TDoomActor.UpdateMembership;
var
  Wanted: TSpriteShape;
begin
  if FShown and (FCurrentImage <> nil) and (FGroup <> nil) then
    Wanted := FGroup.ShapeFor(FCurrentImage.Url)
  else
    Wanted := nil;
  if Wanted = FShape then Exit;
  if FShape <> nil then
    FShape.Remove(Self);
  FShape := Wanted;
  FLastValid := false;
  if FShape <> nil then
  begin
    FShape.Add(Self);
    WriteCorners;
  end;
end;

procedure TDoomActor.WriteCorners;
var
  T, R: TVector3;
  C: array [0..3] of TVector3;
  I, Base: Integer;
begin
  if FShape = nil then Exit;
  T := DoomToCge(DoomX, DoomY, DoomZ);
  R := FBatch.Right;
  C[0] := T + R * FX0 + Vector3(0, FY0, 0);
  C[1] := T + R * FX1 + Vector3(0, FY0, 0);
  C[2] := T + R * FX1 + Vector3(0, FY1, 0);
  C[3] := T + R * FX0 + Vector3(0, FY1, 0);
  if FLastValid and TVector3.PerfectlyEquals(C[0], FLast[0]) and TVector3.PerfectlyEquals(C[1], FLast[1]) and
     TVector3.PerfectlyEquals(C[2], FLast[2]) and TVector3.PerfectlyEquals(C[3], FLast[3]) then
    Exit;
  Base := FSlot * 4;
  for I := 0 to 3 do
  begin
    FShape.Coord.FdPoint.Items[Base + I] := C[I];
    FLast[I] := C[I];
  end;
  FLastValid := true;
  FShape.CoordsDirty := true;
end;

procedure TDoomActor.SetShown(const Shown: Boolean);
begin
  if FShown = Shown then Exit;
  FShown := Shown;
  if FScene.Exists <> Shown then
    FScene.Exists := Shown;
  UpdateMembership;
end;

procedure TDoomActor.HideSprite;
begin
  FHidden := true;
  SetShown(false);
end;

function TDoomActor.RenderKey: String;
begin
  if FShape = nil then Exit('');
  Result := Format('%s|%d|%d', [FCurrentImage.Url, Round(FLightValue.X) div 16, Round(FLightValue.Y)]);
end;

procedure TDoomActor.ApplySprite;
var
  Img: TDoomImage;
  Mirror: Boolean;
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
  FX0 := -Img.LeftOffset;
  FX1 := Img.Width - Img.LeftOffset;
  FY1 := Img.TopOffset;
  FY0 := Img.TopOffset - Img.Height;
  if Mirror then
  begin
    FX0 := -FX0;
    FX1 := -FX1;
  end;
  FCollCoord.SetPoint([Vector3(FX0, FY0, 0), Vector3(FX1, FY0, 0), Vector3(FX1, FY1, 0), Vector3(FX0, FY1, 0)]);
  FLastValid := false;
  UpdateMembership;
  WriteCorners;
end;

procedure TDoomActor.PlaySequence(const Frames: String; const TicsPerFrame: Integer; const Loop: Boolean);
begin
  FSequence := Frames;
  if FSequence = '' then FSequence := 'A';
  FSeq := Default(TFrameSeq);
  FSeqIndex := 0;
  FSeqTics := Max(1, TicsPerFrame);
  FSeqLoop := Loop;
  FTicsLeft := FSeqTics;
  SequenceDone := false;
  FFrame := FSequence[1];
  ApplyFrameData;
  ApplySprite;
end;

procedure TDoomActor.PlayStates(const Seq: TFrameSeq; const Loop: Boolean);
begin
  if Length(Seq.Tics) = 0 then
  begin
    PlaySequence('A', 6, Loop);
    Exit;
  end;
  FSeq := Seq;
  FSequence := Seq.Frames;
  FSeqIndex := 0;
  FSeqTics := Max(1, Seq.Tics[0]);
  FSeqLoop := Loop or Seq.Loop;
  FTicsLeft := FSeqTics;
  SequenceDone := false;
  FFrame := FSequence[1];
  ApplyFrameData;
  ApplySprite;
end;

procedure TDoomActor.ApplyFrameData;
var
  WasBright: Boolean;
begin
  WasBright := FFrameBright;
  if (FSeqIndex >= 0) and (FSeqIndex < Length(FSeq.Tics)) then
  begin
    SpritePrefix := FSeq.Sprites[FSeqIndex];
    FFrameBright := FSeq.Bright[FSeqIndex];
  end else
    FFrameBright := false;
  if (WasBright <> FFrameBright) and (FGroup <> nil) then
    SetLight(FLastLight);
end;

function TDoomActor.CurrentAction: TStateAction;
begin
  if (FSeqIndex >= 0) and (FSeqIndex < Length(FSeq.Actions)) then
    Result := FSeq.Actions[FSeqIndex]
  else
    Result := saNone;
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
  FSeq := Default(TFrameSeq);
  FSeqIndex := Clamped(Index, 0, Length(FSequence) - 1);
  FSeqTics := Max(1, Tics);
  FTicsLeft := Max(1, TicsLeft);
  FSeqLoop := Loop;
  SequenceDone := false;
  FFrame := FSequence[FSeqIndex + 1];
  ApplyFrameData;
  ApplySprite;
end;

procedure TDoomActor.GetAnimationSeq(out Seq: TFrameSeq);
begin
  Seq := FSeq;
end;

procedure TDoomActor.SetAnimationSeq(const Seq: TFrameSeq; const Index, TicsLeft: Integer; const Loop: Boolean);
begin
  if (Length(Seq.Tics) = 0) or (Length(Seq.Tics) <> Length(Seq.Frames)) then
  begin
    SetAnimation(Seq.Frames, Index, 6, TicsLeft, Loop);
    Exit;
  end;
  FSeq := Seq;
  FSequence := Seq.Frames;
  FSeqIndex := Clamped(Index, 0, Length(FSequence) - 1);
  FSeqTics := Max(1, Seq.Tics[FSeqIndex]);
  FTicsLeft := Max(1, TicsLeft);
  FSeqLoop := Loop;
  SequenceDone := false;
  FFrame := FSequence[FSeqIndex + 1];
  ApplyFrameData;
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
    Inc(FSeqIndex);
    if FSeqIndex > Length(FSequence) - 1 then
    begin
      if FSeqLoop then
        FSeqIndex := 0
      else
      begin
        FSeqIndex := Length(FSequence) - 1;
        FTicsLeft := FSeqTics;
        SequenceDone := true;
        Exit;
      end;
    end;
    if FSeqIndex < Length(FSeq.Tics) then
      FSeqTics := Max(1, FSeq.Tics[FSeqIndex]);
    FTicsLeft := FSeqTics;
    FFrame := FSequence[FSeqIndex + 1];
    ApplyFrameData;
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
  WriteCorners;
end;

procedure TDoomActor.SetLight(const Light: Integer);
var
  V: TVector2;
  NewGroup: TSpriteGroup;
begin
  { The colour itself comes from the light effect (Doom's colormaps by
    distance); spectres stay black (their fuzz), full-bright things use
    colormap 0. The quad goes to the batch scene of its light group. }
  FLastLight := Light;
  if Fuzz then
    V := Vector2(Light, DoomLightFuzz)
  else
  if Bright or FFrameBright then
    V := Vector2(Light, DoomLightFullBright)
  else
    V := Vector2(Light, DoomLightWall);
  if TVector2.PerfectlyEquals(FLightValue, V) and (FGroup <> nil) then Exit;
  FLightValue := V;
  NewGroup := FBatch.GroupFor(Light, Round(V.Y));
  if NewGroup <> FGroup then
  begin
    FGroup := NewGroup;
    UpdateMembership;
  end;
end;

end.
