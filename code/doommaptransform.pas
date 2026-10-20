{ A Doom level as a Castle Game Engine component: a TCastleTransform that
  builds a map's geometry (DoomGeometry, with the texture atlas and the
  light diminishing effects) and its things (DoomActors billboards playing
  their idle frames) from a WAD, from its published Wad and Map
  properties. Registered for the CGE editor, so a design can hold a
  Freedoom level and the editor's 3D view shows it; the game's
  --autotest MAPCOMPONENT loads such a design (data/mapcomponent.castle-user-interface).

  Its published properties are what the CGE editor's inspector edits:
  the WAD and map, PWADs stacked on the WAD (a map editor export, a
  mod), which skill's things show, whether monsters show, and extra
  light for every sector; the read-only counts tell what was built.
  Its parts are named for the hierarchy: Map (with the geometry chunks
  Chunk0_Solid..., LineCollision and Sky), Things and Sprites.
  ExportGltf / ExportX3D write the level as a 3D model (DoomExport). }
unit DoomMapTransform;

interface

uses Classes,
  CastleTransform, CastleVectors,
  DoomWad, DoomGraphics, DoomMap, DoomGeometry, DoomActors;

type
  TDoomMapTransform = class(TCastleTransform)
  strict private
    FWadUrl, FMapName: String;
    FThings, FMonsters: Boolean;
    FSkill, FExtraLight: Integer;
    FPwads: TStrings;
    FDirty: Boolean;
    FWad: TDoomWad;
    FGraphics: TDoomGraphics;
    FMap: TDoomMap;
    FGeometry: TDoomGeometry;
    FBatch: TSpriteBatch;
    FActors: TDoomActorList;
    FMapGroup, FThingsGroup, FSpritesGroup: TCastleTransform;
    FTicAccum: Single;
    FStartX, FStartY, FStartAngle: Single;
    FHaveStart: Boolean;
    procedure SetWadUrl(const Value: String);
    procedure SetMapName(const Value: String);
    procedure SetThings(const Value: Boolean);
    procedure SetMonsters(const Value: Boolean);
    procedure SetSkill(const Value: Integer);
    procedure SetExtraLight(const Value: Integer);
    procedure SetPwads(const Value: TStrings);
    procedure PwadsChanged(Sender: TObject);
    function GetSectorCount: Integer;
    function GetLineCount: Integer;
    function GetThingCount: Integer;
    procedure Clear;
    procedure Build;
    procedure SpawnThings;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Update(const SecondsPassed: Single; var RemoveMe: TRemoveType); override;
    { Build now (Update does it on the next frame otherwise). }
    procedure Rebuild;
    { The level is built (a WAD and a map were found). }
    function Built: Boolean;
    { The map's player 1 start, Doom coordinates (the first vertex when
      the map has none), and the eye position / direction in CGE
      coordinates for a camera. }
    property StartX: Single read FStartX;
    property StartY: Single read FStartY;
    property StartAngle: Single read FStartAngle;
    function StartEye: TVector3;
    function StartDirection: TVector3;
    property DoomMap: TDoomMap read FMap;
    property Geometry: TDoomGeometry read FGeometry;
    property Graphics: TDoomGraphics read FGraphics;
    { The level's walls and flats as glTF (.gltf, .bin and PNG textures)
      or X3D; False with Error when it is not built or cannot be written. }
    function ExportGltf(const FileName: String; out Error: String): Boolean;
    function ExportX3D(const FileName: String; out Error: String): Boolean;
  published
    { The IWAD (or a WAD holding the map), e.g. castle-data:/wads/freedoom1.wad. }
    property Wad: String read FWadUrl write SetWadUrl;
    { The map lump name: E1M1, MAP01... }
    property MapName: String read FMapName write SetMapName;
    { Show the things (monsters, items, decorations) as sprites. }
    property Things: Boolean read FThings write SetThings default true;
    { Show the monsters among the things. }
    property Monsters: Boolean read FMonsters write SetMonsters default true;
    { Whose things show: 1 "I'm too young to die" .. 5 "Nightmare!"
      (the THINGS flags of skills 1-2, 3 and 4-5). }
    property Skill: Integer read FSkill write SetSkill default 3;
    { Added to every sector's light level (0..255), like Doom's light
      amplification: 0 is the map as made. }
    property ExtraLight: Integer read FExtraLight write SetExtraLight default 0;
    { PWADs on top of Wad (URLs), e.g. a map editor export
      (castle-config:/e1m1-edited.wad) replacing MapName. }
    property Pwads: TStrings read FPwads write SetPwads;
    { What was built (read only). }
    property SectorCount: Integer read GetSectorCount;
    property LineCount: Integer read GetLineCount;
    property ThingCount: Integer read GetThingCount;
  end;

implementation

uses SysUtils, Math,
  CastleLog, CastleUriUtils, CastleComponentSerialize, CastleUtils,
  DoomThings, DoomExport;

const
  PlayerViewHeight = 41;

constructor TDoomMapTransform.Create(AOwner: TComponent);
begin
  inherited;
  FThings := true;
  FMonsters := true;
  FSkill := 3;
  FActors := TDoomActorList.Create(true);
  FPwads := TStringList.Create;
  TStringList(FPwads).OnChange := {$ifdef FPC}@{$endif} PwadsChanged;
end;

destructor TDoomMapTransform.Destroy;
begin
  Clear;
  FreeAndNil(FActors);
  FreeAndNil(FPwads);
  inherited;
end;

procedure TDoomMapTransform.SetMonsters(const Value: Boolean);
begin
  if FMonsters = Value then Exit;
  FMonsters := Value;
  FDirty := true;
end;

procedure TDoomMapTransform.SetSkill(const Value: Integer);
begin
  if FSkill = EnsureRange(Value, 1, 5) then Exit;
  FSkill := EnsureRange(Value, 1, 5);
  FDirty := true;
end;

procedure TDoomMapTransform.SetExtraLight(const Value: Integer);
begin
  if FExtraLight = EnsureRange(Value, 0, 255) then Exit;
  FExtraLight := EnsureRange(Value, 0, 255);
  FDirty := true;
end;

procedure TDoomMapTransform.SetPwads(const Value: TStrings);
begin
  FPwads.Assign(Value);
end;

procedure TDoomMapTransform.PwadsChanged(Sender: TObject);
begin
  FDirty := true;
end;

function TDoomMapTransform.GetSectorCount: Integer;
begin
  if FMap = nil then Result := 0 else Result := Length(FMap.Sectors);
end;

function TDoomMapTransform.GetLineCount: Integer;
begin
  if FMap = nil then Result := 0 else Result := Length(FMap.Linedefs);
end;

function TDoomMapTransform.GetThingCount: Integer;
begin
  Result := FActors.Count;
end;

function TDoomMapTransform.ExportGltf(const FileName: String; out Error: String): Boolean;
begin
  if FDirty then Rebuild;
  Error := 'The map is not built';
  Result := (FMap <> nil) and ExportMapGeometry(FMap, FGraphics, FileName, true, Error);
end;

function TDoomMapTransform.ExportX3D(const FileName: String; out Error: String): Boolean;
begin
  if FDirty then Rebuild;
  Error := 'The map is not built';
  Result := (FMap <> nil) and ExportMapGeometry(FMap, FGraphics, FileName, false, Error);
end;

procedure TDoomMapTransform.SetWadUrl(const Value: String);
begin
  if FWadUrl = Value then Exit;
  FWadUrl := Value;
  FDirty := true;
end;

procedure TDoomMapTransform.SetMapName(const Value: String);
begin
  if FMapName = Value then Exit;
  FMapName := Value;
  FDirty := true;
end;

procedure TDoomMapTransform.SetThings(const Value: Boolean);
begin
  if FThings = Value then Exit;
  FThings := Value;
  FDirty := true;
end;

procedure TDoomMapTransform.Clear;
begin
  { The actors are freed by the list; their scenes leave the groups. }
  FActors.Clear;
  FreeAndNil(FBatch);
  FreeAndNil(FGeometry);
  FreeAndNil(FMap);
  FreeAndNil(FGraphics);
  FreeAndNil(FWad);
  FreeAndNil(FSpritesGroup);
  FreeAndNil(FThingsGroup);
  FreeAndNil(FMapGroup);
  FHaveStart := false;
end;

function TDoomMapTransform.Built: Boolean;
begin
  Result := FGeometry <> nil;
end;

procedure TDoomMapTransform.Rebuild;
begin
  FDirty := false;
  Clear;
  if (FWadUrl = '') or (FMapName = '') then Exit;
  Build;
end;

{ Checks instead of exceptions: the editor shows an empty component for a
  wrong URL or map name, and the web build cannot survive an exception. }
procedure TDoomMapTransform.Build;
var
  Lump: String;
  I: Integer;
begin
  if not UriFileExists(FWadUrl) then
  begin
    WritelnWarning('DoomMap', 'WAD not found: %s', [FWadUrl]);
    Exit;
  end;
  Lump := UpperCase(Trim(FMapName));
  FWad := TDoomWad.Create(FWadUrl);
  for I := 0 to FPwads.Count - 1 do
    if Trim(FPwads[I]) <> '' then
    begin
      if not UriFileExists(Trim(FPwads[I])) then
      begin
        WritelnWarning('DoomMap', 'PWAD not found: %s', [Trim(FPwads[I])]);
        Continue;
      end;
      FWad.AddFile(Trim(FPwads[I]));
    end;
  if FWad.MapNames.IndexOf(Lump) < 0 then
  begin
    WritelnWarning('DoomMap', 'Map %s not in %s', [Lump, FWadUrl]);
    FreeAndNil(FWad);
    Exit;
  end;
  FGraphics := TDoomGraphics.Create(FWad);
  FMap := TDoomMap.Create(FWad, Lump);
  if FExtraLight > 0 then
    for I := 0 to High(FMap.Sectors) do
      FMap.Sectors[I].LightLevel := Min(255, FMap.Sectors[I].LightLevel + FExtraLight);
  FMapGroup := TCastleTransform.Create(nil);
  FMapGroup.Name := 'Map';
  Add(FMapGroup);
  FThingsGroup := TCastleTransform.Create(nil);
  FThingsGroup.Name := 'Things';
  Add(FThingsGroup);
  FSpritesGroup := TCastleTransform.Create(nil);
  FSpritesGroup.Name := 'Sprites';
  Add(FSpritesGroup);
  FGraphics.BeginLevel;
  { Every sector static: one chunk for the whole map. }
  if (FMap.SkyTransferTexture <> '') and (FGraphics.Texture(FMap.SkyTransferTexture) <> nil) then
    FGeometry := TDoomGeometry.Create(FMap, FGraphics, [], FMap.SkyTransferTexture, FMap.SkyTransferFlipped,
      FGraphics.SkyTextureName(Lump))
  else
    FGeometry := TDoomGeometry.Create(FMap, FGraphics, [], FGraphics.SkyTextureName(Lump), false,
      FGraphics.SkyTextureName(Lump));
  FGeometry.AddToWorld(FMapGroup);
  FBatch := TSpriteBatch.Create(FSpritesGroup);
  SpawnThings;
  WritelnLog('DoomMap', '%s from %s: %d sectors, %d things shown (skill %d%s%s)', [Lump, FWadUrl,
    Length(FMap.Sectors), FActors.Count, FSkill, Iff(FMonsters, '', ', no monsters'),
    Iff(FExtraLight > 0, Format(', extra light %d', [FExtraLight]), '')]);
end;

procedure TDoomMapTransform.SpawnThings;
var
  I: Integer;
  T: TDoomThing;
  Info: PThingInfo;
  A: TDoomActor;
  Sec, SkillBit: Integer;
begin
  FHaveStart := false;
  FStartX := FMap.Vertices[0].X;
  FStartY := FMap.Vertices[0].Y;
  FStartAngle := 0;
  for I := 0 to High(FMap.Things) do
  begin
    T := FMap.Things[I];
    Info := FindThingInfo(T.TypeNum);
    if Info = nil then Continue;
    if (Info^.Kind = tkPlayerStart) and (T.TypeNum = 1) and not FHaveStart then
    begin
      FStartX := T.X;
      FStartY := T.Y;
      FStartAngle := T.Angle;
      FHaveStart := true;
    end;
    if not FThings then Continue;
    { Single player, the things of the chosen skill. }
    if (T.Flags and MTF_NOTSINGLE) <> 0 then Continue;
    case FSkill of
      1, 2: SkillBit := MTF_EASY;
      3: SkillBit := MTF_NORMAL;
      else SkillBit := MTF_HARD;
    end;
    if (T.Flags and SkillBit) = 0 then Continue;
    if (not FMonsters) and (Info^.Kind = tkMonster) then Continue;
    if Info^.Kind in [tkPlayerStart, tkInvisible, tkTeleportDest, tkBossSpot] then Continue;
    Sec := FMap.SectorAt(T.X, T.Y);
    if Sec < 0 then Continue;
    A := TDoomActor.Create(nil, FGraphics, FBatch, Info);
    A.DoomX := T.X;
    A.DoomY := T.Y;
    A.Angle := T.Angle;
    A.Sector := Sec;
    if Info^.Hanging then
      A.DoomZ := FMap.Sectors[Sec].CeilingHeight - Info^.Height
    else
      A.DoomZ := FMap.Sectors[Sec].FloorHeight;
    A.Collides := false;
    A.Pickable := false;
    A.Bright := Info^.Pickup in [pkSoulsphere, pkMegasphere, pkInvulnerability, pkInvisibility, pkBerserk,
      pkRadSuit, pkComputerMap, pkLightAmp];
    A.SetLight(FMap.Sectors[Sec].LightLevel);
    A.UpdateRotation(FStartX, FStartY);
    A.UpdateTransform;
    FActors.Add(A);
    FThingsGroup.Add(A);
  end;
  FBatch.ViewAngle := FStartAngle;
  FBatch.Flush;
end;

function TDoomMapTransform.StartEye: TVector3;
var
  Sec: Integer;
  Z: Single;
begin
  Z := 0;
  if FMap <> nil then
  begin
    Sec := FMap.SectorAt(FStartX, FStartY);
    if Sec >= 0 then Z := FMap.Sectors[Sec].FloorHeight;
  end;
  Result := DoomToCge(FStartX, FStartY, Z + PlayerViewHeight);
end;

function TDoomMapTransform.StartDirection: TVector3;
begin
  Result := DoomToCge(Cos(DegToRad(FStartAngle)), Sin(DegToRad(FStartAngle)), 0);
end;

procedure TDoomMapTransform.Update(const SecondsPassed: Single; var RemoveMe: TRemoveType);
var
  Camera: TCastleCamera;
  Viewer, CamPos, CamDir, CamUp: TVector3;
  A: TDoomActor;
  Angle: Single;
begin
  inherited;
  if FDirty then Rebuild;
  if (FGeometry = nil) or (FActors.Count = 0) then Exit;
  { The sprites face the viewport's camera and play their idle frames at
    Doom's 35 tics a second (torches, barrels, the bonuses). }
  Camera := nil;
  if World <> nil then Camera := World.MainCamera;
  if Camera <> nil then
  begin
    Camera.GetWorldView(CamPos, CamDir, CamUp);
    Viewer := CgeToDoom(CamPos);
    Angle := RadToDeg(ArcTan2(-CamDir.Z, CamDir.X));
  end else
  begin
    Viewer := Vector3(FStartX, FStartY, 0);
    Angle := FStartAngle;
  end;
  FBatch.ViewAngle := Angle;
  FTicAccum := FTicAccum + SecondsPassed;
  while FTicAccum >= 1 / 35 do
  begin
    FTicAccum := FTicAccum - 1 / 35;
    for A in FActors do
      A.AnimateTic;
  end;
  for A in FActors do
  begin
    A.UpdateRotation(Viewer.X, Viewer.Y);
    A.UpdateTransform;
  end;
  FBatch.Flush;
end;

initialization
  RegisterSerializableComponent(TDoomMapTransform, 'Doom Map');
end.
