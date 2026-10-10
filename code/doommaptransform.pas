{ A Doom level as a Castle Game Engine component: a TCastleTransform that
  builds a map's geometry (DoomGeometry, with the texture atlas and the
  light diminishing effects) and its things (DoomActors billboards playing
  their idle frames) from a WAD, from its published Wad and Map
  properties. Registered for the CGE editor, so a design can hold a
  Freedoom level and the editor's 3D view shows it; the game's
  --autotest MAPCOMPONENT loads such a design (data/mapcomponent.castle-user-interface). }
unit DoomMapTransform;

interface

uses Classes,
  CastleTransform, CastleVectors,
  DoomWad, DoomGraphics, DoomMap, DoomGeometry, DoomActors;

type
  TDoomMapTransform = class(TCastleTransform)
  strict private
    FWadUrl, FMapName: String;
    FThings: Boolean;
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
  published
    { The IWAD (or a WAD holding the map), e.g. castle-data:/wads/freedoom1.wad. }
    property Wad: String read FWadUrl write SetWadUrl;
    { The map lump name: E1M1, MAP01... }
    property MapName: String read FMapName write SetMapName;
    { Show the things (monsters, items, decorations) as sprites. }
    property Things: Boolean read FThings write SetThings default true;
  end;

implementation

uses SysUtils, Math,
  CastleLog, CastleUriUtils, CastleComponentSerialize,
  DoomThings;

const
  PlayerViewHeight = 41;

constructor TDoomMapTransform.Create(AOwner: TComponent);
begin
  inherited;
  FThings := true;
  FActors := TDoomActorList.Create(true);
end;

destructor TDoomMapTransform.Destroy;
begin
  Clear;
  FreeAndNil(FActors);
  inherited;
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
begin
  if not UriFileExists(FWadUrl) then
  begin
    WritelnWarning('DoomMap', 'WAD not found: %s', [FWadUrl]);
    Exit;
  end;
  Lump := UpperCase(Trim(FMapName));
  FWad := TDoomWad.Create(FWadUrl);
  if FWad.MapNames.IndexOf(Lump) < 0 then
  begin
    WritelnWarning('DoomMap', 'Map %s not in %s', [Lump, FWadUrl]);
    FreeAndNil(FWad);
    Exit;
  end;
  FGraphics := TDoomGraphics.Create(FWad);
  FMap := TDoomMap.Create(FWad, Lump);
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
  FGeometry := TDoomGeometry.Create(FMap, FGraphics, [], FGraphics.SkyTextureName(Lump));
  FGeometry.AddToWorld(FMapGroup);
  FBatch := TSpriteBatch.Create(FSpritesGroup);
  SpawnThings;
  WritelnLog('DoomMap', '%s from %s: %d sectors, %d things shown', [Lump, FWadUrl, Length(FMap.Sectors), FActors.Count]);
end;

procedure TDoomMapTransform.SpawnThings;
var
  I: Integer;
  T: TDoomThing;
  Info: PThingInfo;
  A: TDoomActor;
  Sec: Integer;
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
    { Single player, "hurt me plenty", like the game's default. }
    if (T.Flags and MTF_NOTSINGLE) <> 0 then Continue;
    if (T.Flags and MTF_NORMAL) = 0 then Continue;
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
