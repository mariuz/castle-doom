{ Random maps: a PWAD of RandomMapCount generated levels, E1M1..E1M8 (or
  MAP01..MAP08 for Doom 2 IWADs) and a UMAPINFO lump with their names,
  made from a seed. TDoomWad.AddFile builds it for the URL random:/SEED
  (RandomWadUrl), so saves, -file and the remembered WADs name it like
  any PWAD and get the same maps back; -random [SEED] on the command line
  and the page URL's random=SEED load it and start its first map.

  Each map is a rectangle cut by recursive straight splits on a 32-unit
  grid (guillotine cuts) until the pieces are room sized: every piece is a
  rectangular sector, and the cuts themselves are the BSP's nodes (every
  leaf is one convex subsector), so no node builder is needed. Rooms that
  share a wall are linked; a random spanning tree of links from the start
  room, plus a few loops, become openings (two-sided lines) with floor
  steps of at most 24 units, everything else stays wall (two one-sided
  lines back to back). Floors, ceilings, lights, textures, nukage and sky
  rooms, monsters (more and tougher on later maps, thinned on easy
  skills), weapons, ammo, health and armour come from the same random
  stream; the exit switch (special 11) is in the room farthest from the
  start. REJECT is empty and BLOCKMAP is real, so the PWAD written by
  --random-wad also plays in other Doom ports.

  The random stream is a xorshift32 of its own (not System.Random), so a
  seed gives the same bytes on every platform. }
unit DoomRandomMap;

interface

uses Classes, SysUtils;

const
  RandomMapCount = 8;
  RandomUrlPrefix = 'random:/';

{ True for random:/SEED (case-insensitive), with the seed. }
function IsRandomWadUrl(const Url: String; out Seed: Cardinal): Boolean;
function RandomWadUrl(const Seed: Cardinal): String;
{ A seed from the clock, never 0. }
function NewRandomSeed: Cardinal;
{ The map slot of random map Index (1..RandomMapCount). }
function RandomMapName(const Index: Integer; const IsDoom2: Boolean): String;

{ The PWAD's bytes. Available (sorted, upper case, may be nil = all) lists
  the textures and flats of the IWAD: the generator only uses those. Log
  (may be nil) gets one summary line per map. }
function BuildRandomWad(const Seed: Cardinal; const IsDoom2: Boolean; const Available: TStrings;
  const Log: TStrings): TMemoryStream;

implementation

uses Math, DateUtils;

const
  Grid = 32;
  MinCells = 6;    { 192 units: the smallest room side }
  MaxCells = 20;   { 640 units: rooms larger than this are split }
  MinLinkOverlap = 64;
  MaxStep = 24;

  ML_BLOCKING = 1;
  ML_TWOSIDED = 4;

function IsRandomWadUrl(const Url: String; out Seed: Cardinal): Boolean;
var
  S: String;
  V: Int64;
begin
  Seed := 0;
  Result := SameText(Copy(Url, 1, Length(RandomUrlPrefix)), RandomUrlPrefix);
  if not Result then Exit;
  S := Copy(Url, Length(RandomUrlPrefix) + 1, MaxInt);
  V := StrToInt64Def(S, -1);
  if (V < 0) or (V > High(Cardinal)) then
    V := 1;
  Seed := Cardinal(V);
end;

function RandomWadUrl(const Seed: Cardinal): String;
begin
  Result := RandomUrlPrefix + IntToStr(Seed);
end;

function NewRandomSeed: Cardinal;
begin
  Result := Cardinal(MilliSecondOfTheDay(Now)) mod 1000000;
  if Result = 0 then Result := 1;
end;

function RandomMapName(const Index: Integer; const IsDoom2: Boolean): String;
begin
  if IsDoom2 then
    Result := Format('MAP%.2d', [Index])
  else
    Result := Format('E1M%d', [Index]);
end;

{ The random stream ---------------------------------------------------------- }

type
  TRng = record
    State: Cardinal;
  end;

function RngNext(var R: TRng): Cardinal;
var
  X: Cardinal;
begin
  X := R.State;
  X := X xor (X shl 13);
  X := X xor (X shr 17);
  X := X xor (X shl 5);
  R.State := X;
  Result := X;
end;

procedure RngInit(var R: TRng; const Seed: Cardinal; const Stream: Integer);
var
  I: Integer;
begin
  R.State := Seed xor $9E3779B9 xor (Cardinal(Stream) shl 20) xor Cardinal(Stream);
  if R.State = 0 then R.State := $A341316C;
  for I := 1 to 8 do RngNext(R);
end;

{ 0..N-1 }
function RngBelow(var R: TRng; const N: Integer): Integer;
begin
  if N <= 1 then Exit(0);
  Result := RngNext(R) mod Cardinal(N);
end;

function RngRange(var R: TRng; const Lo, Hi: Integer): Integer;
begin
  Result := Lo + RngBelow(R, Hi - Lo + 1);
end;

function RngChance(var R: TRng; const Percent: Integer): Boolean;
begin
  Result := RngBelow(R, 100) < Percent;
end;

{ One map --------------------------------------------------------------------- }

type
  TRoom = record
    X0, Y0, X1, Y1: Integer;
    Floor, Ceiling, Light, Special: Integer;
    FloorTex, CeilTex, WallTex: String;
    Sky, Nukage: Boolean;
    { Openings from the start room, -1 when it cannot be reached. }
    Depth: Integer;
    Segs: array of Integer;
  end;

  TBspNode = record
    X0, Y0, X1, Y1: Integer;
    Vertical: Boolean;
    Pos: Integer;
    { Children: a node index, or -(room + 1). Lo is west / south. }
    Lo, Hi: Integer;
  end;

  TLink = record
    A, B: Integer;      { A west / south of the shared line, B east / north }
    Vertical: Boolean;  { the line is x = Pos (else y = Pos) }
    Pos, S, E: Integer; { the shared interval along the line }
    Open: Boolean;
    O1, O2: Integer;    { the opening, when Open }
  end;

  TLine = record
    V1, V2, Flags, Special, Front, Back: Integer;
  end;

  TSide = record
    Upper, Lower, Middle: String;
    Sector: Integer;
  end;

  TSeg = record
    V1, V2, Line, Side: Integer;
  end;

  TThing = record
    X, Y, Angle, TypeNum, Flags: Integer;
  end;

  TSpot = record
    X, Y, Room: Integer;
    Used: Boolean;
  end;

  TTheme = record
    Name: String;
    Walls, Floors, Ceilings: array of String;
  end;

  TMapGen = class
  strict private
    R: TRng;
    Index: Integer;
    IsDoom2: Boolean;
    Available: TStrings;
    RootX0, RootY0, RootX1, RootY1: Integer;
    Rooms: array of TRoom;
    Nodes: array of TBspNode;
    Links: array of TLink;
    VX, VY: array of Integer;
    Lines: array of TLine;
    Sides: array of TSide;
    Segs: array of TSeg;
    Things: array of TThing;
    Spots: array of TSpot;
    StartRoom, ExitRoom, ExitLine, OpenLinks, Monsters, Items, Unreached: Integer;
    { Where to stand to press the exit switch, and the angle to face. }
    ExitX, ExitY, ExitAngle: Integer;
    SwitchTex: String;
    function Has(const Name: String): Boolean;
    function Pick(const Names: array of String): String;
    function Split(const X0, Y0, X1, Y1: Integer): Integer;
    procedure AddLink(const A, B: Integer; const Vertical: Boolean; const Pos, S, E: Integer);
    procedure FindLinks;
    procedure ConnectRooms;
    procedure DecorateRooms;
    function Vertex(const X, Y: Integer): Integer;
    function AddSide(const Upper, Lower, Middle: String; const Sector: Integer): Integer;
    procedure AddSeg(const Room, V1, V2, Line, Side: Integer);
    function RightOf(const Room, AX, AY, BX, BY: Integer): Boolean;
    procedure AddWall(const Room, AX, AY, BX, BY, Special: Integer; const Tex: String);
    procedure AddWallPiece(const Room: Integer; const Vertical: Boolean; const Pos, A, B: Integer);
    procedure AddOpening(const L: TLink);
    procedure BuildLines;
    procedure AddThing(const X, Y, Angle, TypeNum, Flags: Integer);
    procedure MakeSpots;
    function TakeSpot(const Room, Radius: Integer; out X, Y: Integer): Boolean;
    procedure AddItem(const Room, TypeNum: Integer);
    function PickMonster: Integer;
    procedure AddMonster(const Room, Kind: Integer; const AllSkillsToo: Boolean);
    function RoomAtDepth(const D: Integer): Integer;
    procedure PlaceThings;
  public
    Name, Summary: String;
    constructor Create(const ASeed: Cardinal; const AIndex: Integer; const AIsDoom2: Boolean;
      const AAvailable: TStrings);
    procedure Generate;
    { The map's lumps, in Doom's order after the marker. }
    procedure WriteLumps(const Names: TStrings; const Data: TList);
  end;

const
  Adjectives: array [0..15] of String = ('Crimson', 'Toxic', 'Hollow', 'Forgotten', 'Shattered',
    'Silent', 'Burning', 'Frozen', 'Twisted', 'Ancient', 'Sunken', 'Broken', 'Grim', 'Black',
    'Iron', 'Rusted');
  Nouns: array [0..15] of String = ('Depot', 'Vaults', 'Halls', 'Refinery', 'Bunker', 'Outpost',
    'Labyrinth', 'Foundry', 'Catacombs', 'Hangar', 'Complex', 'Annex', 'Citadel', 'Warrens',
    'Reactor', 'Archive');

constructor TMapGen.Create(const ASeed: Cardinal; const AIndex: Integer; const AIsDoom2: Boolean;
  const AAvailable: TStrings);
begin
  inherited Create;
  RngInit(R, ASeed, AIndex);
  Index := AIndex;
  IsDoom2 := AIsDoom2;
  Available := AAvailable;
end;

function TMapGen.Has(const Name: String): Boolean;
var
  I: Integer;
begin
  if (Available = nil) or (Available.Count = 0) then Exit(true);
  if (Available is TStringList) and TStringList(Available).Sorted then
    Result := TStringList(Available).Find(Name, I)
  else
    Result := Available.IndexOf(Name) >= 0;
end;

{ A random one of the names the IWAD has (the first name when none). }
function TMapGen.Pick(const Names: array of String): String;
var
  Ok: array of String;
  I: Integer;
begin
  SetLength(Ok, 0);
  for I := 0 to High(Names) do
    if Has(Names[I]) then
    begin
      SetLength(Ok, Length(Ok) + 1);
      Ok[High(Ok)] := Names[I];
    end;
  if Length(Ok) = 0 then
    Result := Names[0]
  else
    Result := Ok[RngBelow(R, Length(Ok))];
end;

function TMapGen.Split(const X0, Y0, X1, Y1: Integer): Integer;
var
  W, H, Cut: Integer;
  Vertical: Boolean;
  Node: TBspNode;
begin
  W := (X1 - X0) div Grid;
  H := (Y1 - Y0) div Grid;
  if ((W < 2 * MinCells) and (H < 2 * MinCells)) or
     ((W <= MaxCells) and (H <= MaxCells) and RngChance(R, 55)) then
  begin
    SetLength(Rooms, Length(Rooms) + 1);
    Rooms[High(Rooms)].X0 := X0;
    Rooms[High(Rooms)].Y0 := Y0;
    Rooms[High(Rooms)].X1 := X1;
    Rooms[High(Rooms)].Y1 := Y1;
    Rooms[High(Rooms)].Depth := -1;
    Exit(-Length(Rooms));
  end;
  if (W >= 2 * MinCells) and (H >= 2 * MinCells) then
  begin
    if W * 2 > H * 3 then Vertical := true
    else if H * 2 > W * 3 then Vertical := false
    else Vertical := RngChance(R, 50);
  end else
    Vertical := W >= 2 * MinCells;
  if Vertical then
    Cut := X0 + Grid * RngRange(R, MinCells, W - MinCells)
  else
    Cut := Y0 + Grid * RngRange(R, MinCells, H - MinCells);
  Node.X0 := X0;
  Node.Y0 := Y0;
  Node.X1 := X1;
  Node.Y1 := Y1;
  Node.Vertical := Vertical;
  Node.Pos := Cut;
  if Vertical then
  begin
    Node.Lo := Split(X0, Y0, Cut, Y1);
    Node.Hi := Split(Cut, Y0, X1, Y1);
  end else
  begin
    Node.Lo := Split(X0, Y0, X1, Cut);
    Node.Hi := Split(X0, Cut, X1, Y1);
  end;
  { Children first: the root ends up last, as Doom expects. }
  SetLength(Nodes, Length(Nodes) + 1);
  Nodes[High(Nodes)] := Node;
  Result := High(Nodes);
end;

procedure TMapGen.AddLink(const A, B: Integer; const Vertical: Boolean; const Pos, S, E: Integer);
begin
  SetLength(Links, Length(Links) + 1);
  Links[High(Links)].A := A;
  Links[High(Links)].B := B;
  Links[High(Links)].Vertical := Vertical;
  Links[High(Links)].Pos := Pos;
  Links[High(Links)].S := S;
  Links[High(Links)].E := E;
  Links[High(Links)].Open := false;
end;

procedure TMapGen.FindLinks;
var
  I, J, S, E: Integer;
begin
  for I := 0 to High(Rooms) do
    for J := 0 to High(Rooms) do
    begin
      if I = J then Continue;
      if Rooms[I].X1 = Rooms[J].X0 then
      begin
        S := Max(Rooms[I].Y0, Rooms[J].Y0);
        E := Min(Rooms[I].Y1, Rooms[J].Y1);
        if E > S then AddLink(I, J, true, Rooms[I].X1, S, E);
      end;
      if Rooms[I].Y1 = Rooms[J].Y0 then
      begin
        S := Max(Rooms[I].X0, Rooms[J].X0);
        E := Min(Rooms[I].X1, Rooms[J].X1);
        if E > S then AddLink(I, J, false, Rooms[I].Y1, S, E);
      end;
    end;
end;

{ A random spanning tree of openings from the start room (each new room's
  floor a small step from the room it is entered from), then a few loops
  between rooms whose floors are close enough. }
procedure TMapGen.ConnectRooms;
const
  Steps: array [0..6] of Integer = (-24, -16, -8, 0, 8, 16, 24);
var
  InTree: array of Boolean;
  Frontier: array of Integer;
  I, K, L, From, Into, Width: Integer;
  Changed: Boolean;

  procedure OpenLink(const Li: Integer);
  begin
    Width := Min(RngRange(R, 2, 4) * Grid, Links[Li].E - Links[Li].S - 16);
    Links[Li].Open := true;
    Links[Li].O1 := Links[Li].S + (Links[Li].E - Links[Li].S - Width) div 2;
    Links[Li].O2 := Links[Li].O1 + Width;
    Inc(OpenLinks);
  end;

  procedure AddFrontier(const Room: Integer);
  var
    J: Integer;
  begin
    for J := 0 to High(Links) do
      if ((Links[J].A = Room) or (Links[J].B = Room)) and
         (Links[J].E - Links[J].S >= MinLinkOverlap) then
      begin
        SetLength(Frontier, Length(Frontier) + 1);
        Frontier[High(Frontier)] := J;
      end;
  end;

begin
  SetLength(InTree, Length(Rooms));
  StartRoom := RngBelow(R, Length(Rooms));
  InTree[StartRoom] := true;
  Rooms[StartRoom].Floor := 0;
  Rooms[StartRoom].Depth := 0;
  SetLength(Frontier, 0);
  AddFrontier(StartRoom);
  while Length(Frontier) > 0 do
  begin
    K := RngBelow(R, Length(Frontier));
    L := Frontier[K];
    Frontier[K] := Frontier[High(Frontier)];
    SetLength(Frontier, Length(Frontier) - 1);
    if InTree[Links[L].A] = InTree[Links[L].B] then Continue;
    if InTree[Links[L].A] then
    begin
      From := Links[L].A;
      Into := Links[L].B;
    end else
    begin
      From := Links[L].B;
      Into := Links[L].A;
    end;
    OpenLink(L);
    InTree[Into] := true;
    Rooms[Into].Floor := EnsureRange(Rooms[From].Floor + Steps[RngBelow(R, Length(Steps))], -256, 256);
    Rooms[Into].Depth := Rooms[From].Depth + 1;
    AddFrontier(Into);
  end;
  { Loops: openings between two reached rooms with close floors. }
  for I := 0 to High(Links) do
    if (not Links[I].Open) and InTree[Links[I].A] and InTree[Links[I].B] and
       (Links[I].E - Links[I].S >= MinLinkOverlap) and
       (Abs(Rooms[Links[I].A].Floor - Rooms[Links[I].B].Floor) <= MaxStep) and
       RngChance(R, 20) then
      OpenLink(I);
  { Depths through the loops too (shortest number of openings). }
  repeat
    Changed := false;
    for I := 0 to High(Links) do
      if Links[I].Open then
      begin
        if Rooms[Links[I].B].Depth > Rooms[Links[I].A].Depth + 1 then
        begin
          Rooms[Links[I].B].Depth := Rooms[Links[I].A].Depth + 1;
          Changed := true;
        end;
        if Rooms[Links[I].A].Depth > Rooms[Links[I].B].Depth + 1 then
        begin
          Rooms[Links[I].A].Depth := Rooms[Links[I].B].Depth + 1;
          Changed := true;
        end;
      end;
  until not Changed;
  ExitRoom := StartRoom;
  Unreached := 0;
  for I := 0 to High(Rooms) do
    if Rooms[I].Depth < 0 then
      Inc(Unreached)
    else if Rooms[I].Depth > Rooms[ExitRoom].Depth then
      ExitRoom := I;
end;

procedure TMapGen.DecorateRooms;
var
  Themes: array [0..3] of TTheme;
  T: TTheme;
  I, Height: Integer;

  procedure SetTheme(const K: Integer; const AName: String; const AWalls, AFloors, ACeilings: array of String);
  var
    J: Integer;
  begin
    Themes[K].Name := AName;
    SetLength(Themes[K].Walls, Length(AWalls));
    for J := 0 to High(AWalls) do Themes[K].Walls[J] := AWalls[J];
    SetLength(Themes[K].Floors, Length(AFloors));
    for J := 0 to High(AFloors) do Themes[K].Floors[J] := AFloors[J];
    SetLength(Themes[K].Ceilings, Length(ACeilings));
    for J := 0 to High(ACeilings) do Themes[K].Ceilings[J] := ACeilings[J];
  end;

begin
  SetTheme(0, 'tech', ['STARTAN3', 'STARTAN2', 'STARG3', 'STARGR1', 'COMPSPAN', 'TEKWALL4'],
    ['FLOOR4_8', 'FLOOR5_1', 'FLOOR0_1', 'FLAT14', 'FLAT20'], ['CEIL3_5', 'CEIL5_1', 'FLAT18', 'TLITE6_4']);
  SetTheme(1, 'brown', ['BROWN1', 'BROWNGRN', 'BROWN96', 'BROWN144', 'SUPPORT2'],
    ['FLOOR7_1', 'FLAT5', 'FLOOR1_1', 'FLAT4'], ['CEIL3_3', 'CEIL1_1', 'FLAT5_4']);
  SetTheme(2, 'stone', ['STONE2', 'STONE3', 'GRAY1', 'GRAY4', 'CEMENT1'],
    ['FLAT1', 'FLAT5_4', 'FLOOR6_2', 'RROCK09'], ['FLAT1', 'CEIL5_1', 'FLAT5_4']);
  SetTheme(3, 'hell', ['MARBLE1', 'SKIN2', 'GSTONE1', 'WOOD1', 'BRICK1'],
    ['DEM1_5', 'FLAT5', 'GRNROCK', 'RROCK09'], ['FLAT1', 'CEIL1_1', 'DEM1_5']);
  { Later maps lean towards hell. }
  if Index >= 6 then
    T := Themes[2 + RngBelow(R, 2)]
  else
    T := Themes[RngBelow(R, 3)];
  SwitchTex := Pick(['SW1STRTN', 'SW1COMP', 'SW1BRN1', 'SW1STON1', 'SW1GRAY']);
  if T.Name = 'brown' then SwitchTex := Pick(['SW1BRN1', 'SW1STRTN'])
  else if T.Name = 'stone' then SwitchTex := Pick(['SW1STON1', 'SW1GRAY']);
  for I := 0 to High(Rooms) do
  begin
    Rooms[I].WallTex := Pick(T.Walls);
    Rooms[I].FloorTex := Pick(T.Floors);
    Rooms[I].CeilTex := Pick(T.Ceilings);
    Rooms[I].Light := 112 + 16 * RngBelow(R, 7);
    Rooms[I].Special := 0;
    case RngBelow(R, 5) of
      0, 1: Height := 128;
      2: Height := 160;
      3: Height := 192;
      else Height := 224;
    end;
    if (I <> StartRoom) and (I <> ExitRoom) then
    begin
      if RngChance(R, 12) then
      begin
        Rooms[I].Sky := true;
        Rooms[I].CeilTex := 'F_SKY1';
        Inc(Height, 64);
        Rooms[I].Light := Max(Rooms[I].Light, 176);
      end;
      if RngChance(R, 9) then
      begin
        Rooms[I].Nukage := true;
        Rooms[I].FloorTex := Pick(['NUKAGE1', 'SLIME01']);
        Rooms[I].Special := 7; { 5% damage }
      end else if RngChance(R, 10) then
      begin
        if RngChance(R, 50) then Rooms[I].Special := 1 else Rooms[I].Special := 8;
      end;
    end;
    if I = StartRoom then
      Rooms[I].Light := 192;
    if I = ExitRoom then
    begin
      { Switch textures are 128 high. }
      Height := 128;
      Rooms[I].Light := 176;
    end;
    Rooms[I].Ceiling := Rooms[I].Floor + Height;
  end;
end;

function TMapGen.Vertex(const X, Y: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(VX) do
    if (VX[I] = X) and (VY[I] = Y) then Exit(I);
  SetLength(VX, Length(VX) + 1);
  SetLength(VY, Length(VY) + 1);
  VX[High(VX)] := X;
  VY[High(VY)] := Y;
  Result := High(VX);
end;

function TMapGen.AddSide(const Upper, Lower, Middle: String; const Sector: Integer): Integer;
begin
  SetLength(Sides, Length(Sides) + 1);
  Sides[High(Sides)].Upper := Upper;
  Sides[High(Sides)].Lower := Lower;
  Sides[High(Sides)].Middle := Middle;
  Sides[High(Sides)].Sector := Sector;
  Result := High(Sides);
end;

procedure TMapGen.AddSeg(const Room, V1, V2, Line, Side: Integer);
begin
  SetLength(Segs, Length(Segs) + 1);
  Segs[High(Segs)].V1 := V1;
  Segs[High(Segs)].V2 := V2;
  Segs[High(Segs)].Line := Line;
  Segs[High(Segs)].Side := Side;
  SetLength(Rooms[Room].Segs, Length(Rooms[Room].Segs) + 1);
  Rooms[Room].Segs[High(Rooms[Room].Segs)] := High(Segs);
end;

{ Doom's front side is on the right going from V1 to V2 (r_main.c's
  R_PointOnSide): the room's centre must be there. }
function TMapGen.RightOf(const Room, AX, AY, BX, BY: Integer): Boolean;
var
  CX, CY: Double;
begin
  CX := (Rooms[Room].X0 + Rooms[Room].X1) / 2;
  CY := (Rooms[Room].Y0 + Rooms[Room].Y1) / 2;
  Result := (CX - AX) * (BY - AY) - (CY - AY) * (BX - AX) >= 0;
end;

procedure TMapGen.AddWall(const Room, AX, AY, BX, BY, Special: Integer; const Tex: String);
var
  V1, V2: Integer;
begin
  if RightOf(Room, AX, AY, BX, BY) then
  begin
    V1 := Vertex(AX, AY);
    V2 := Vertex(BX, BY);
  end else
  begin
    V1 := Vertex(BX, BY);
    V2 := Vertex(AX, AY);
  end;
  SetLength(Lines, Length(Lines) + 1);
  Lines[High(Lines)].V1 := V1;
  Lines[High(Lines)].V2 := V2;
  Lines[High(Lines)].Flags := ML_BLOCKING;
  Lines[High(Lines)].Special := Special;
  Lines[High(Lines)].Front := AddSide('-', '-', Tex, Room);
  Lines[High(Lines)].Back := -1;
  AddSeg(Room, V1, V2, High(Lines), 0);
end;

{ A wall of Room along the line x = Pos (Vertical) or y = Pos, from A to
  B; the exit switch goes into the exit room's first wall long enough. }
procedure TMapGen.AddWallPiece(const Room: Integer; const Vertical: Boolean; const Pos, A, B: Integer);

  procedure Wall(const P, Q, Special: Integer; const Tex: String);
  begin
    if Q <= P then Exit;
    if Vertical then
      AddWall(Room, Pos, P, Pos, Q, Special, Tex)
    else
      AddWall(Room, P, Pos, Q, Pos, Special, Tex);
  end;

var
  M: Integer;
begin
  if (Room = ExitRoom) and (ExitLine < 0) and (B - A >= 128) then
  begin
    M := A + (B - A - 64) div 2;
    Wall(A, M, 0, Rooms[Room].WallTex);
    Wall(M, M + 64, 11, SwitchTex);
    ExitLine := High(Lines);
    Wall(M + 64, B, 0, Rooms[Room].WallTex);
  end else
    Wall(A, B, 0, Rooms[Room].WallTex);
end;

procedure TMapGen.AddOpening(const L: TLink);
var
  AX, AY, BX, BY, V1, V2, Front, Back: Integer;
begin
  if L.Vertical then
  begin
    AX := L.Pos; AY := L.O1; BX := L.Pos; BY := L.O2;
  end else
  begin
    AX := L.O1; AY := L.Pos; BX := L.O2; BY := L.Pos;
  end;
  if RightOf(L.A, AX, AY, BX, BY) then
  begin
    V1 := Vertex(AX, AY);
    V2 := Vertex(BX, BY);
  end else
  begin
    V1 := Vertex(BX, BY);
    V2 := Vertex(AX, AY);
  end;
  Front := AddSide(Rooms[L.A].WallTex, Rooms[L.A].WallTex, '-', L.A);
  Back := AddSide(Rooms[L.B].WallTex, Rooms[L.B].WallTex, '-', L.B);
  SetLength(Lines, Length(Lines) + 1);
  Lines[High(Lines)].V1 := V1;
  Lines[High(Lines)].V2 := V2;
  Lines[High(Lines)].Flags := ML_TWOSIDED;
  Lines[High(Lines)].Special := 0;
  Lines[High(Lines)].Front := Front;
  Lines[High(Lines)].Back := Back;
  AddSeg(L.A, V1, V2, High(Lines), 0);
  AddSeg(L.B, V2, V1, High(Lines), 1);
end;

procedure TMapGen.BuildLines;
var
  I, Best, BestLen, Len, J, NX, NY: Integer;
  L: TLink;
begin
  ExitLine := -1;
  { The outer walls first (the exit switch prefers them). }
  for I := 0 to High(Rooms) do
  begin
    if Rooms[I].Y1 = RootY1 then AddWallPiece(I, false, RootY1, Rooms[I].X0, Rooms[I].X1);
    if Rooms[I].X1 = RootX1 then AddWallPiece(I, true, RootX1, Rooms[I].Y0, Rooms[I].Y1);
    if Rooms[I].Y0 = RootY0 then AddWallPiece(I, false, RootY0, Rooms[I].X0, Rooms[I].X1);
    if Rooms[I].X0 = RootX0 then AddWallPiece(I, true, RootX0, Rooms[I].Y0, Rooms[I].Y1);
  end;
  for I := 0 to High(Links) do
  begin
    L := Links[I];
    if L.Open then
    begin
      AddWallPiece(L.A, L.Vertical, L.Pos, L.S, L.O1);
      AddWallPiece(L.B, L.Vertical, L.Pos, L.S, L.O1);
      AddOpening(L);
      AddWallPiece(L.A, L.Vertical, L.Pos, L.O2, L.E);
      AddWallPiece(L.B, L.Vertical, L.Pos, L.O2, L.E);
    end else
    begin
      AddWallPiece(L.A, L.Vertical, L.Pos, L.S, L.E);
      AddWallPiece(L.B, L.Vertical, L.Pos, L.S, L.E);
    end;
  end;
  { No wall was long enough: the exit room's longest wall is the switch. }
  if ExitLine < 0 then
  begin
    Best := -1;
    BestLen := -1;
    for J := 0 to High(Rooms[ExitRoom].Segs) do
    begin
      I := Segs[Rooms[ExitRoom].Segs[J]].Line;
      if Lines[I].Back >= 0 then Continue;
      Len := Abs(VX[Lines[I].V2] - VX[Lines[I].V1]) + Abs(VY[Lines[I].V2] - VY[Lines[I].V1]);
      if Len > BestLen then
      begin
        Best := I;
        BestLen := Len;
      end;
    end;
    if Best >= 0 then
    begin
      Lines[Best].Special := 11;
      Sides[Lines[Best].Front].Middle := SwitchTex;
      ExitLine := Best;
    end;
  end;
  { 48 units in front of the switch's middle, facing it (the front side
    is to the right of V1 -> V2). }
  if ExitLine >= 0 then
  begin
    Len := Abs(VX[Lines[ExitLine].V2] - VX[Lines[ExitLine].V1]) + Abs(VY[Lines[ExitLine].V2] - VY[Lines[ExitLine].V1]);
    NX := Sign(VY[Lines[ExitLine].V2] - VY[Lines[ExitLine].V1]);
    NY := -Sign(VX[Lines[ExitLine].V2] - VX[Lines[ExitLine].V1]);
    ExitX := (VX[Lines[ExitLine].V1] + VX[Lines[ExitLine].V2]) div 2 + 48 * NX;
    ExitY := (VY[Lines[ExitLine].V1] + VY[Lines[ExitLine].V2]) div 2 + 48 * NY;
    ExitAngle := (Round(RadToDeg(ArcTan2(-NY, -NX))) + 360) mod 360;
  end;
end;

procedure TMapGen.AddThing(const X, Y, Angle, TypeNum, Flags: Integer);
begin
  SetLength(Things, Length(Things) + 1);
  Things[High(Things)].X := X;
  Things[High(Things)].Y := Y;
  Things[High(Things)].Angle := Angle;
  Things[High(Things)].TypeNum := TypeNum;
  Things[High(Things)].Flags := Flags;
end;

type
  TMonsterKind = record
    TypeNum, FirstMap, Weight, Radius: Integer;
    Doom2: Boolean;
  end;

const
  MonsterKinds: array [0..15] of TMonsterKind = (
    (TypeNum: 3004; FirstMap: 1; Weight: 30; Radius: 20; Doom2: false), { zombieman }
    (TypeNum: 9; FirstMap: 1; Weight: 20; Radius: 20; Doom2: false),    { shotgun guy }
    (TypeNum: 3001; FirstMap: 1; Weight: 30; Radius: 20; Doom2: false), { imp }
    (TypeNum: 3002; FirstMap: 1; Weight: 12; Radius: 30; Doom2: false), { demon }
    (TypeNum: 3006; FirstMap: 2; Weight: 6; Radius: 16; Doom2: false),  { lost soul }
    (TypeNum: 58; FirstMap: 3; Weight: 6; Radius: 30; Doom2: false),    { spectre }
    (TypeNum: 3005; FirstMap: 3; Weight: 8; Radius: 31; Doom2: false),  { cacodemon }
    (TypeNum: 3003; FirstMap: 6; Weight: 3; Radius: 24; Doom2: false),  { baron }
    (TypeNum: 65; FirstMap: 2; Weight: 8; Radius: 20; Doom2: true),     { chaingunner }
    (TypeNum: 69; FirstMap: 3; Weight: 5; Radius: 24; Doom2: true),     { hell knight }
    (TypeNum: 66; FirstMap: 4; Weight: 5; Radius: 20; Doom2: true),     { revenant }
    (TypeNum: 71; FirstMap: 5; Weight: 2; Radius: 31; Doom2: true),     { pain elemental }
    (TypeNum: 67; FirstMap: 5; Weight: 3; Radius: 48; Doom2: true),     { mancubus }
    (TypeNum: 68; FirstMap: 5; Weight: 3; Radius: 64; Doom2: true),     { arachnotron }
    (TypeNum: 64; FirstMap: 7; Weight: 1; Radius: 20; Doom2: true),     { arch-vile }
    (TypeNum: 3003; FirstMap: 8; Weight: 0; Radius: 24; Doom2: false)); { (the bosses) }

  { Skill bits: 1 easy, 2 medium, 4 hard. }
  AllSkills = 7;


{ Thing spots: a 48-unit grid inside every room. }
procedure TMapGen.MakeSpots;
var
  I, X, Y: Integer;
begin
  SetLength(Spots, 0);
  for I := 0 to High(Rooms) do
  begin
    X := Rooms[I].X0 + 48;
    while X <= Rooms[I].X1 - 48 do
    begin
      Y := Rooms[I].Y0 + 48;
      while Y <= Rooms[I].Y1 - 48 do
      begin
        SetLength(Spots, Length(Spots) + 1);
        Spots[High(Spots)].X := X;
        Spots[High(Spots)].Y := Y;
        Spots[High(Spots)].Room := I;
        Spots[High(Spots)].Used := false;
        Inc(Y, 48);
      end;
      Inc(X, 48);
    end;
  end;
end;

{ A free spot of Room at least Radius + 8 from its walls; the spots
  within Radius + 24 of it are taken with it. False when none is left. }
function TMapGen.TakeSpot(const Room, Radius: Integer; out X, Y: Integer): Boolean;
var
  FreeSpots: array of Integer;
  I, K: Integer;
begin
  X := 0;
  Y := 0;
  SetLength(FreeSpots, 0);
  for I := 0 to High(Spots) do
    if (Spots[I].Room = Room) and not Spots[I].Used and
       (Spots[I].X - Rooms[Room].X0 >= Radius + 8) and (Rooms[Room].X1 - Spots[I].X >= Radius + 8) and
       (Spots[I].Y - Rooms[Room].Y0 >= Radius + 8) and (Rooms[Room].Y1 - Spots[I].Y >= Radius + 8) then
    begin
      SetLength(FreeSpots, Length(FreeSpots) + 1);
      FreeSpots[High(FreeSpots)] := I;
    end;
  if Length(FreeSpots) = 0 then Exit(false);
  K := FreeSpots[RngBelow(R, Length(FreeSpots))];
  X := Spots[K].X;
  Y := Spots[K].Y;
  for I := 0 to High(Spots) do
    if (Spots[I].Room = Room) and
       (Abs(Spots[I].X - X) < Radius + 24) and (Abs(Spots[I].Y - Y) < Radius + 24) then
      Spots[I].Used := true;
  Result := true;
end;

procedure TMapGen.AddItem(const Room, TypeNum: Integer);
var
  X, Y: Integer;
begin
  if TakeSpot(Room, 16, X, Y) then
  begin
    AddThing(X, Y, 0, TypeNum, AllSkills);
    Inc(Items);
  end;
end;

function TMapGen.PickMonster: Integer;
var
  I, Total, K: Integer;
begin
  Total := 0;
  for I := 0 to High(MonsterKinds) do
    if (MonsterKinds[I].FirstMap <= Index) and (IsDoom2 or not MonsterKinds[I].Doom2) then
      Inc(Total, MonsterKinds[I].Weight);
  K := RngBelow(R, Total);
  for I := 0 to High(MonsterKinds) do
    if (MonsterKinds[I].FirstMap <= Index) and (IsDoom2 or not MonsterKinds[I].Doom2) then
    begin
      if K < MonsterKinds[I].Weight then Exit(I);
      Dec(K, MonsterKinds[I].Weight);
    end;
  Result := 0;
end;

procedure TMapGen.AddMonster(const Room, Kind: Integer; const AllSkillsToo: Boolean);
var
  X, Y, Flags: Integer;
begin
  if not TakeSpot(Room, MonsterKinds[Kind].Radius, X, Y) then Exit;
  { Hard always; medium mostly; easy about half of those. }
  Flags := 4;
  if AllSkillsToo or RngChance(R, 70) then
  begin
    Flags := Flags or 2;
    if AllSkillsToo or RngChance(R, 60) then Flags := Flags or 1;
  end;
  AddThing(X, Y, 45 * RngBelow(R, 8), MonsterKinds[Kind].TypeNum, Flags);
  Inc(Monsters);
end;

{ The reached room (not the start) whose depth is nearest to D. }
function TMapGen.RoomAtDepth(const D: Integer): Integer;
var
  I: Integer;
begin
  Result := StartRoom;
  for I := 0 to High(Rooms) do
    if (I <> StartRoom) and (Rooms[I].Depth > 0) and
       ((Result = StartRoom) or (Abs(Rooms[I].Depth - D) < Abs(Rooms[Result].Depth - D))) then
      Result := I;
end;

procedure TMapGen.PlaceThings;
var
  I, K, Count, X, Y, Angle, Deepest, L: Integer;
  F: Double;
  HasRockets, HasCells: Boolean;
begin
  MakeSpots;
  { The player in the middle of the start room, facing its first opening. }
  X := (Rooms[StartRoom].X0 + Rooms[StartRoom].X1) div 2;
  Y := (Rooms[StartRoom].Y0 + Rooms[StartRoom].Y1) div 2;
  Angle := 90;
  for L := 0 to High(Links) do
    if Links[L].Open and ((Links[L].A = StartRoom) or (Links[L].B = StartRoom)) then
    begin
      if Links[L].Vertical then
        Angle := Round(RadToDeg(ArcTan2((Links[L].O1 + Links[L].O2) / 2 - Y, Links[L].Pos - X)))
      else
        Angle := Round(RadToDeg(ArcTan2(Links[L].Pos - Y, (Links[L].O1 + Links[L].O2) / 2 - X)));
      Angle := ((Round(Angle / 45) * 45) + 360) mod 360;
      Break;
    end;
  AddThing(X, Y, Angle, 1, AllSkills);
  for I := 0 to High(Spots) do
    if (Spots[I].Room = StartRoom) and (Abs(Spots[I].X - X) < 64) and (Abs(Spots[I].Y - Y) < 64) then
      Spots[I].Used := true;
  AddItem(StartRoom, 2007);

  Deepest := Rooms[ExitRoom].Depth;
  HasRockets := Index >= 3;
  HasCells := Index >= 5;
  { Weapons: the shotgun near the start, the others deeper in. }
  AddItem(RoomAtDepth(1), 2001);
  if IsDoom2 and (Index >= 2) then AddItem(RoomAtDepth(Deepest div 3), 82);
  if Index >= 2 then AddItem(RoomAtDepth(Deepest div 2), 2002);
  if HasRockets then AddItem(RoomAtDepth((Deepest * 2) div 3), 2003);
  if HasCells then AddItem(RoomAtDepth(Deepest div 2), 2004);
  if Index >= 7 then AddItem(RoomAtDepth(Deepest - 1), 2006);
  { The last map's exit is guarded. }
  if Index = RandomMapCount then
  begin
    AddMonster(ExitRoom, 15, true);
    AddMonster(ExitRoom, 15, true);
  end;

  for I := 0 to High(Rooms) do
  begin
    if (I = StartRoom) or (Rooms[I].Depth < 0) then Continue;
    { Monsters: by area, more on later maps. }
    F := (Rooms[I].X1 - Rooms[I].X0) * (Rooms[I].Y1 - Rooms[I].Y0) / 65536 * (0.35 + 0.07 * Index);
    Count := Trunc(F);
    if RngBelow(R, 100) < Round(Frac(F) * 100) then Inc(Count);
    for K := 1 to Count do
      AddMonster(I, PickMonster, false);
    { Supplies. }
    if RngChance(R, 50) then
      case RngBelow(R, 2 + Ord(HasRockets) + Ord(HasCells)) of
        0: if RngChance(R, 15) then AddItem(I, 2048) else AddItem(I, 2007);
        1: if RngChance(R, 15) then AddItem(I, 2049) else AddItem(I, 2008);
        2: if HasRockets then
           begin
             if RngChance(R, 20) then AddItem(I, 2046) else AddItem(I, 2010);
           end else
             AddItem(I, 2047);
        else if RngChance(R, 20) then AddItem(I, 17) else AddItem(I, 2047);
      end;
    if RngChance(R, 22) then
      if RngChance(R, 70) then AddItem(I, 2011) else AddItem(I, 2012);
    if RngChance(R, 8) then
      for K := 1 to 3 do AddItem(I, 2015);
    if RngChance(R, 4) then AddItem(I, 2018);
    if (Index >= 4) and RngChance(R, 2) then AddItem(I, 2019);
    if (Index >= 3) and (Rooms[I].Depth >= 3) and RngChance(R, 3) then AddItem(I, 2013);
    if Rooms[I].Nukage and RngChance(R, 60) then AddItem(I, 2025);
    if RngChance(R, 10) then
      for K := 1 to RngRange(R, 1, 3) do AddItem(I, 2035);
    if RngChance(R, 8) then AddItem(I, 2028);
  end;
end;

procedure TMapGen.Generate;
var
  W, H, I, Sky, Nukage: Integer;
begin
  { 1408 to 2560 units a side, larger on later maps (even cell counts:
    the map is centred on 0, 0). }
  W := (40 + 4 * Index + RngBelow(R, 9)) and not 1;
  H := (40 + 4 * Index + RngBelow(R, 9)) and not 1;
  RootX0 := -(W div 2) * Grid;
  RootX1 := (W div 2) * Grid;
  RootY0 := -(H div 2) * Grid;
  RootY1 := (H div 2) * Grid;
  Split(RootX0, RootY0, RootX1, RootY1);
  FindLinks;
  ConnectRooms;
  DecorateRooms;
  BuildLines;
  PlaceThings;
  Name := Adjectives[RngBelow(R, Length(Adjectives))] + ' ' + Nouns[RngBelow(R, Length(Nouns))];
  Sky := 0;
  Nukage := 0;
  for I := 0 to High(Rooms) do
  begin
    if Rooms[I].Sky then Inc(Sky);
    if Rooms[I].Nukage then Inc(Nukage);
  end;
  Summary := Format('"%s": %d x %d, %d rooms (%d sky, %d nukage, %d unreached), %d openings, ' +
    '%d monsters, %d items, start room %d, exit room %d (%d rooms away), switch line %d at %d %d facing %d', [
    Name, RootX1 - RootX0, RootY1 - RootY0, Length(Rooms), Sky, Nukage, Unreached, OpenLinks,
    Monsters, Items, StartRoom, ExitRoom, Rooms[ExitRoom].Depth, ExitLine, ExitX, ExitY, ExitAngle]);
end;

{ Writing ---------------------------------------------------------------------- }

procedure W16(const S: TStream; const V: Integer);
var
  Wd: Word;
begin
  Wd := Word(V and $FFFF);
  S.WriteBuffer(Wd, 2);
end;

procedure W32(const S: TStream; const V: Integer);
var
  L: LongInt;
begin
  L := V;
  S.WriteBuffer(L, 4);
end;

procedure WName(const S: TStream; const Name: String);
var
  B: array [0..7] of Byte;
  I: Integer;
begin
  FillChar(B, SizeOf(B), 0);
  for I := 1 to Min(8, Length(Name)) do
    B[I - 1] := Ord(UpCase(Name[I]));
  S.WriteBuffer(B, 8);
end;

procedure TMapGen.WriteLumps(const Names: TStrings; const Data: TList);
var
  S: TMemoryStream;
  I, J, K, First, Code, BX, BY, BW, BH, OX, OY, X0, X1, Y0, Y1, Offset: Integer;
  Blocks: array of array of Integer;
  Dx, Dy: Integer;
  Bam: Integer;

  procedure Lump(const AName: String);
  begin
    S := TMemoryStream.Create;
    Names.Add(AName);
    Data.Add(S);
  end;

  function Child(const C: Integer): Integer;
  begin
    if C >= 0 then Result := C else Result := $8000 or (-C - 1);
  end;

  procedure Box(const C: Integer);
  begin
    if C >= 0 then
    begin
      W16(S, Nodes[C].Y1); W16(S, Nodes[C].Y0); W16(S, Nodes[C].X0); W16(S, Nodes[C].X1);
    end else
    begin
      Code := -C - 1;
      W16(S, Rooms[Code].Y1); W16(S, Rooms[Code].Y0); W16(S, Rooms[Code].X0); W16(S, Rooms[Code].X1);
    end;
  end;

begin
  Lump('THINGS');
  for I := 0 to High(Things) do
  begin
    W16(S, Things[I].X); W16(S, Things[I].Y); W16(S, Things[I].Angle);
    W16(S, Things[I].TypeNum); W16(S, Things[I].Flags);
  end;
  Lump('LINEDEFS');
  for I := 0 to High(Lines) do
  begin
    W16(S, Lines[I].V1); W16(S, Lines[I].V2); W16(S, Lines[I].Flags);
    W16(S, Lines[I].Special); W16(S, 0); W16(S, Lines[I].Front);
    if Lines[I].Back >= 0 then W16(S, Lines[I].Back) else W16(S, $FFFF);
  end;
  Lump('SIDEDEFS');
  for I := 0 to High(Sides) do
  begin
    W16(S, 0); W16(S, 0);
    WName(S, Sides[I].Upper); WName(S, Sides[I].Lower); WName(S, Sides[I].Middle);
    W16(S, Sides[I].Sector);
  end;
  Lump('VERTEXES');
  for I := 0 to High(VX) do
  begin
    W16(S, VX[I]); W16(S, VY[I]);
  end;
  Lump('SEGS');
  for I := 0 to High(Rooms) do
    for J := 0 to High(Rooms[I].Segs) do
    begin
      K := Rooms[I].Segs[J];
      Dx := VX[Segs[K].V2] - VX[Segs[K].V1];
      Dy := VY[Segs[K].V2] - VY[Segs[K].V1];
      Bam := Round(ArcTan2(Dy, Dx) * 32768 / Pi);
      W16(S, Segs[K].V1); W16(S, Segs[K].V2); W16(S, Bam);
      W16(S, Segs[K].Line); W16(S, Segs[K].Side); W16(S, 0);
    end;
  Lump('SSECTORS');
  First := 0;
  for I := 0 to High(Rooms) do
  begin
    W16(S, Length(Rooms[I].Segs)); W16(S, First);
    Inc(First, Length(Rooms[I].Segs));
  end;
  Lump('NODES');
  for I := 0 to High(Nodes) do
  begin
    { Children[0] is the right (front) side of the partition: east of a
      northward vertical cut, south of an eastward horizontal one. }
    if Nodes[I].Vertical then
    begin
      W16(S, Nodes[I].Pos); W16(S, Nodes[I].Y0); W16(S, 0); W16(S, Nodes[I].Y1 - Nodes[I].Y0);
      Box(Nodes[I].Hi); Box(Nodes[I].Lo);
      W16(S, Child(Nodes[I].Hi)); W16(S, Child(Nodes[I].Lo));
    end else
    begin
      W16(S, Nodes[I].X0); W16(S, Nodes[I].Pos); W16(S, Nodes[I].X1 - Nodes[I].X0); W16(S, 0);
      Box(Nodes[I].Lo); Box(Nodes[I].Hi);
      W16(S, Child(Nodes[I].Lo)); W16(S, Child(Nodes[I].Hi));
    end;
  end;
  Lump('SECTORS');
  for I := 0 to High(Rooms) do
  begin
    W16(S, Rooms[I].Floor); W16(S, Rooms[I].Ceiling);
    WName(S, Rooms[I].FloorTex); WName(S, Rooms[I].CeilTex);
    W16(S, Rooms[I].Light); W16(S, Rooms[I].Special); W16(S, 0);
  end;
  { REJECT: nothing rejected. }
  Lump('REJECT');
  for I := 1 to (Length(Rooms) * Length(Rooms) + 7) div 8 do
    S.WriteByte(0);
  { BLOCKMAP: 128-unit blocks, each with the lines touching it. }
  Lump('BLOCKMAP');
  OX := RootX0 - 8;
  OY := RootY0 - 8;
  BW := (RootX1 - OX) div 128 + 1;
  BH := (RootY1 - OY) div 128 + 1;
  SetLength(Blocks, BW * BH);
  for I := 0 to High(Lines) do
  begin
    X0 := (Min(VX[Lines[I].V1], VX[Lines[I].V2]) - OX) div 128;
    X1 := (Max(VX[Lines[I].V1], VX[Lines[I].V2]) - OX) div 128;
    Y0 := (Min(VY[Lines[I].V1], VY[Lines[I].V2]) - OY) div 128;
    Y1 := (Max(VY[Lines[I].V1], VY[Lines[I].V2]) - OY) div 128;
    for BY := Y0 to Y1 do
      for BX := X0 to X1 do
      begin
        K := BY * BW + BX;
        SetLength(Blocks[K], Length(Blocks[K]) + 1);
        Blocks[K][High(Blocks[K])] := I;
      end;
  end;
  W16(S, OX); W16(S, OY); W16(S, BW); W16(S, BH);
  Offset := 4 + BW * BH;
  for K := 0 to High(Blocks) do
  begin
    W16(S, Offset);
    Inc(Offset, Length(Blocks[K]) + 2);
  end;
  for K := 0 to High(Blocks) do
  begin
    W16(S, 0);
    for J := 0 to High(Blocks[K]) do W16(S, Blocks[K][J]);
    W16(S, $FFFF);
  end;
end;

function UMapInfoText(const Seed: Cardinal; const IsDoom2: Boolean; const MapNames: TStrings): String;
var
  I: Integer;
begin
  Result := Format('// Castle DOOM random maps, seed %d' + LineEnding, [Seed]);
  for I := 1 to RandomMapCount do
  begin
    Result := Result + 'MAP ' + RandomMapName(I, IsDoom2) + LineEnding + '{' + LineEnding +
      Format('  levelname = "%s"', [MapNames[I - 1]]) + LineEnding +
      Format('  label = "R%d"', [I]) + LineEnding +
      Format('  partime = %d', [60 + 30 * I]) + LineEnding;
    if I < RandomMapCount then
      Result := Result + Format('  next = "%s"', [RandomMapName(I + 1, IsDoom2)]) + LineEnding +
        '  intertext = clear' + LineEnding
    else
      Result := Result + Format('  intertext = "You fought your way through", "%d random maps.", "", ' +
        '"Play them again with seed %d,", "or try another one."', [RandomMapCount, Seed]) + LineEnding +
        '  endgame = true' + LineEnding;
    Result := Result + '}' + LineEnding;
  end;
end;

function BuildRandomWad(const Seed: Cardinal; const IsDoom2: Boolean; const Available: TStrings;
  const Log: TStrings): TMemoryStream;
var
  Names: TStringList;
  Data: TList;
  MapNames: TStringList;
  Gen: TMapGen;
  I, DirOffset: Integer;
  Text: String;
  S: TMemoryStream;
begin
  Names := TStringList.Create;
  Data := TList.Create;
  MapNames := TStringList.Create;
  try
    for I := 1 to RandomMapCount do
    begin
      Gen := TMapGen.Create(Seed, I, IsDoom2, Available);
      try
        Gen.Generate;
        Names.Add(RandomMapName(I, IsDoom2));
        Data.Add(TMemoryStream.Create);
        Gen.WriteLumps(Names, Data);
        MapNames.Add(Gen.Name);
        if Log <> nil then
          Log.Add(Format('seed %d: %s %s', [Seed, RandomMapName(I, IsDoom2), Gen.Summary]));
      finally
        FreeAndNil(Gen);
      end;
    end;
    Text := UMapInfoText(Seed, IsDoom2, MapNames);
    S := TMemoryStream.Create;
    if Text <> '' then S.WriteBuffer(Text[1], Length(Text));
    Names.Add('UMAPINFO');
    Data.Add(S);

    Result := TMemoryStream.Create;
    Result.WriteBuffer(PChar('PWAD')^, 4);
    W32(Result, Names.Count);
    W32(Result, 0); { the directory's offset, below }
    for I := 0 to Data.Count - 1 do
      Result.CopyFrom(TMemoryStream(Data[I]), 0);
    DirOffset := Result.Position;
    for I := 0 to Names.Count - 1 do
    begin
      W32(Result, 12);
      W32(Result, TMemoryStream(Data[I]).Size);
      WName(Result, Names[I]);
    end;
    { The lumps' offsets, now that the sizes are known. }
    Result.Position := DirOffset;
    DirOffset := 12;
    for I := 0 to Names.Count - 1 do
    begin
      W32(Result, DirOffset);
      Result.Seek(12, soCurrent);
      Inc(DirOffset, TMemoryStream(Data[I]).Size);
    end;
    Result.Position := 8;
    W32(Result, Result.Size - 16 * Names.Count);
    Result.Position := 0;
  finally
    for I := 0 to Data.Count - 1 do
      TObject(Data[I]).Free;
    FreeAndNil(Data);
    FreeAndNil(MapNames);
    FreeAndNil(Names);
  end;
end;

end.
