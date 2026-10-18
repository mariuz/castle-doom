{ Debug drawing: the simulation's shapes as wireframes over the map, in
  a "Debug" group of four scenes that the engine's inspector (F8) switches
  with their Exists checkboxes, or the demo command
  DEBUG:subsectors|blocking|actors|shots|all|off:

  - DebugSubsectors: every subsector's convex polygon at its floor (cyan).
  - DebugBlocking: the lines that block walking (one-sided or
    ML_BLOCKING) at their floor and ceiling (red).
  - DebugActors: each live actor's box, radius and height (yellow; not
    the player's, which holds the camera).
  - DebugShots: the player's last hitscans, gun to stop (green when they
    hit an actor, white otherwise; TDoomWorld.ShotTrail).

  The first two are built once per map (with the heights at that time);
  the others follow the world every frame while shown. None takes part in
  collisions or picking, and they are drawn in front of the map
  (RenderLayer rlFront), so walls do not hide them. }
unit GameDebugDraw;

interface

uses Classes,
  CastleVectors, CastleColors, CastleTransform, CastleScene, X3DNodes,
  DoomMap, DoomWorld;

type
  TDebugDraw = class(TCastleTransform)
  strict private
    FSubsectors, FBlocking, FActors, FShots: TCastleScene;
    FActorCoords, FShotCoords: TCoordinateNode;
    FMap: TDoomMap;
    function MakeScene(const AName: String; const Color: TCastleColorRGB;
      out Coords: TCoordinateNode): TCastleScene;
  public
    constructor Create(AOwner: TComponent); override;
    { Build the map's static wireframes (when the map changed). }
    procedure BuildMap(const Map: TDoomMap);
    { Follow the actors and shots (only the shown scenes). }
    procedure UpdateWorld(const AWorld: TDoomWorld);
    { "subsectors", "blocking", "actors", "shots", "all" or "off": shows
      that one (toggles it) or all / none. }
    procedure Toggle(const What: String);
    function Summary: String;
    property Subsectors: TCastleScene read FSubsectors;
    property Blocking: TCastleScene read FBlocking;
    property Actors: TCastleScene read FActors;
    property Shots: TCastleScene read FShots;
  end;

implementation

uses SysUtils, CastleLog, CastleRenderOptions,
  DoomActors, DoomThings, DoomGeometry;

constructor TDebugDraw.Create(AOwner: TComponent);
var
  Dummy: TCoordinateNode;
begin
  inherited;
  Name := 'Debug';
  Pickable := false;
  Collides := false;
  FSubsectors := MakeScene('DebugSubsectors', Vector3(0.2, 0.9, 0.9), Dummy);
  FBlocking := MakeScene('DebugBlocking', Vector3(1, 0.2, 0.2), Dummy);
  FActors := MakeScene('DebugActors', Vector3(1, 0.9, 0.2), FActorCoords);
  FShots := MakeScene('DebugShots', Vector3(0.3, 1, 0.3), FShotCoords);
end;

function TDebugDraw.MakeScene(const AName: String; const Color: TCastleColorRGB;
  out Coords: TCoordinateNode): TCastleScene;
var
  Root: TX3DRootNode;
  Shape: TShapeNode;
  Lines: TLineSetNode;
  Material: TUnlitMaterialNode;
begin
  Coords := TCoordinateNode.Create;
  Lines := TLineSetNode.Create;
  Lines.Mode := lmPair;
  Lines.Coord := Coords;
  Material := TUnlitMaterialNode.Create;
  Material.EmissiveColor := Color;
  Shape := TShapeNode.Create;
  Shape.Geometry := Lines;
  Shape.Appearance := TAppearanceNode.Create;
  Shape.Appearance.Material := Material;
  Root := TX3DRootNode.Create;
  Root.AddChildren(Shape);
  Result := TCastleScene.Create(Self);
  Result.Name := AName;
  Result.Load(Root, true);
  Result.Pickable := false;
  Result.Collides := false;
  { Drawn over the map (the lines lie on its walls and floors). }
  Result.RenderLayer := rlFront;
  Result.Exists := false;
  Add(Result);
end;

{ The coordinate node of a scene made by MakeScene. }
function SceneCoords(const Scene: TCastleScene): TCoordinateNode;
begin
  Result := (((Scene.RootNode.FdChildren[0] as TShapeNode).Geometry) as TLineSetNode).Coord as TCoordinateNode;
end;

procedure TDebugDraw.BuildMap(const Map: TDoomMap);
var
  Points: TVector3List;
  I, J, N, Sec: Integer;
  Z: Single;
  L: TDoomLinedef;
  V1, V2: TDoomVertex;

  procedure Segment(const X1, Y1, Z1, X2, Y2, Z2: Single);
  begin
    Points.Add(DoomToCge(X1, Y1, Z1));
    Points.Add(DoomToCge(X2, Y2, Z2));
  end;

begin
  if Map = FMap then Exit;
  FMap := Map;
  Points := TVector3List.Create;
  try
    for I := 0 to High(Map.Subsectors) do
    begin
      N := Length(Map.Subsectors[I].Poly);
      if N < 3 then Continue;
      Sec := Map.Subsectors[I].Sector;
      Z := 1;
      if (Sec >= 0) and (Sec <= High(Map.Sectors)) then
        Z := Map.Sectors[Sec].FloorHeight + 1;
      for J := 0 to N - 1 do
        Segment(Map.Subsectors[I].Poly[J].X, Map.Subsectors[I].Poly[J].Y, Z,
          Map.Subsectors[I].Poly[(J + 1) mod N].X, Map.Subsectors[I].Poly[(J + 1) mod N].Y, Z);
    end;
    SceneCoords(FSubsectors).SetPoint(Points);
    Points.Clear;
    for I := 0 to High(Map.Linedefs) do
    begin
      L := Map.Linedefs[I];
      if (L.BackSector >= 0) and ((L.Flags and ML_BLOCKING) = 0) then Continue;
      if (L.FrontSector < 0) or (L.FrontSector > High(Map.Sectors)) then Continue;
      V1 := Map.Vertices[L.V1];
      V2 := Map.Vertices[L.V2];
      Z := Map.Sectors[L.FrontSector].FloorHeight + 2;
      Segment(V1.X, V1.Y, Z, V2.X, V2.Y, Z);
      Z := Map.Sectors[L.FrontSector].CeilingHeight - 2;
      Segment(V1.X, V1.Y, Z, V2.X, V2.Y, Z);
    end;
    SceneCoords(FBlocking).SetPoint(Points);
  finally
    FreeAndNil(Points);
  end;
end;

procedure TDebugDraw.UpdateWorld(const AWorld: TDoomWorld);
var
  Points: TVector3List;
  A: TDoomActor;
  R, H: Single;
  I: Integer;

  procedure Segment(const X1, Y1, Z1, X2, Y2, Z2: Single);
  begin
    Points.Add(DoomToCge(X1, Y1, Z1));
    Points.Add(DoomToCge(X2, Y2, Z2));
  end;

  { An axis-aligned box like Doom's (radius around X, Y; Z up). }
  procedure Box(const X, Y, Z, R, H: Single);
  var
    K: Integer;
    CX, CY: array [0..3] of Single;
  begin
    CX[0] := X - R; CY[0] := Y - R;
    CX[1] := X + R; CY[1] := Y - R;
    CX[2] := X + R; CY[2] := Y + R;
    CX[3] := X - R; CY[3] := Y + R;
    for K := 0 to 3 do
    begin
      Segment(CX[K], CY[K], Z, CX[(K + 1) mod 4], CY[(K + 1) mod 4], Z);
      Segment(CX[K], CY[K], Z + H, CX[(K + 1) mod 4], CY[(K + 1) mod 4], Z + H);
      Segment(CX[K], CY[K], Z, CX[K], CY[K], Z + H);
    end;
  end;

begin
  if AWorld = nil then Exit;
  if FActors.Exists then
  begin
    Points := TVector3List.Create;
    try
      for A in AWorld.Actors do
      begin
        if A.Removed or (A.Info = nil) or (A.State in [asDead, asEffect]) then Continue;
        R := A.Info^.Radius;
        H := A.Info^.Height;
        if (R <= 0) or (H <= 0) then Continue;
        Box(A.DoomX, A.DoomY, A.DoomZ, R, H);
      end;
      FActorCoords.SetPoint(Points);
    finally
      FreeAndNil(Points);
    end;
  end;
  if FShots.Exists then
  begin
    Points := TVector3List.Create;
    try
      for I := 0 to High(AWorld.ShotTrail) do
        Segment(AWorld.ShotTrail[I].X1, AWorld.ShotTrail[I].Y1, AWorld.ShotTrail[I].Z1,
          AWorld.ShotTrail[I].X2, AWorld.ShotTrail[I].Y2, AWorld.ShotTrail[I].Z2);
      FShotCoords.SetPoint(Points);
    finally
      FreeAndNil(Points);
    end;
  end;
end;

procedure TDebugDraw.Toggle(const What: String);
var
  W: String;
begin
  W := LowerCase(What);
  if W = 'subsectors' then FSubsectors.Exists := not FSubsectors.Exists
  else if W = 'blocking' then FBlocking.Exists := not FBlocking.Exists
  else if W = 'actors' then FActors.Exists := not FActors.Exists
  else if W = 'shots' then FShots.Exists := not FShots.Exists
  else if (W = 'all') or (W = 'off') then
  begin
    FSubsectors.Exists := W = 'all';
    FBlocking.Exists := W = 'all';
    FActors.Exists := W = 'all';
    FShots.Exists := W = 'all';
  end else
    WritelnWarning('Debug', 'Unknown debug drawing "%s"', [What]);
  WritelnLog('Debug', Summary);
end;

function TDebugDraw.Summary: String;

  function Shown(const Scene: TCastleScene): String;
  begin
    if Scene.Exists then Result := 'shown' else Result := 'hidden';
  end;

begin
  Result := Format('subsectors %s (%d segments), blocking %s (%d segments), actors %s, shots %s', [
    Shown(FSubsectors), SceneCoords(FSubsectors).FdPoint.Count div 2,
    Shown(FBlocking), SceneCoords(FBlocking).FdPoint.Count div 2,
    Shown(FActors), Shown(FShots)]);
end;

end.
