{ Unit tests of the engine-independent Doom* units: WAD reading, map BSP
  loading (every node format), MUS / MIDI parsing and rendering (both
  synthesizers, the envelope) and DeHackEd parsing, on the Freedoom WADs
  in data/wads. Gameplay is covered by the --autotest runs
  (tools/run_autotests.py); these cover the parsers without a window.

  The node-format tests read the PWADs tools/make_znodes.py and
  tools/make_glnodes.py write into tools/testdata/nodes/ (gitignored, 1.6
  MB; CI generates them first) and are skipped with a note when they are
  missing.

  Build and run from the project root (CI does the same):
    castle-engine simple-compile tests/castle_doom_tests.lpr
    tests/castle_doom_tests --all --format=plain }
program castle_doom_tests;

{$mode objfpc}{$H+}
{$unitpath ../code}

uses SysUtils, Classes, Math, fpcunit, testregistry, consoletestrunner,
  CastleVectors, CastleUriUtils, CastleGameControllers, CastleKeysMouse,
  DoomWad, DoomGraphics, DoomMap, DoomMusic, DoomOpl3, DoomThings, DoomDehacked, DoomStates, GameGamepad, GameSettings, GameTouch, GameLogFilter, DoomMapInfo, DoomWorld, DoomIntermission, DoomFinale,
  DoomGeneralized;

function DataPath(const Name: String): String;
begin
  { The tests run from the project root or from tests/. }
  Result := 'data/wads/' + Name;
  if not FileExists(Result) then
    Result := '../data/wads/' + Name;
end;

function WadUrl(const Name: String): String;
begin
  Result := FilenameToUriSafe(ExpandFileName(DataPath(Name)));
end;

type
  TTestWad = class(TTestCase)
  published
    procedure TestPhase1;
    procedure TestPhase2;
    procedure TestBoomLumps;
    procedure TestLogFilter;
    procedure TestUMapInfo;
    procedure TestZMapInfo;
  end;

  TTestMap = class(TTestCase)
  strict private
    procedure CheckNodeWad(const FileName, ExpectedFormat: String;
      const Subsectors, Area: Integer);
  published
    procedure TestE1M1Bsp;
    procedure TestMap01;
    procedure TestZDoomNodes;
    procedure TestGlBspNodes;
    procedure TestLineGrid;
    procedure TestGeneralized;
    procedure TestScrollers;
    procedure TestDynScrollers;
    procedure TestDeepWater;
    procedure TestFriction;
    procedure TestTranslucency;
    procedure TestTransfers;
  end;

  TTestMusic = class(TTestCase)
  strict private
    procedure CheckEnvelope(const Fm: Boolean);
  published
    procedure TestParseMidi;
    procedure TestParseMus;
    procedure TestRenderMus;
    procedure TestRejectGarbage;
    procedure TestOpl3Synth;
    procedure TestEnvelopeFm;
    procedure TestEnvelopeOpl3;
  end;

  TTestDehacked = class(TTestCase)
  published
    procedure TestFreedoomLump;
    procedure TestPatchFile;
    procedure TestTranslucentBits;
  end;

  TTestGamepad = class(TTestCase)
  published
    procedure TestWebPadMapping;
    procedure TestPadBindings;
    procedure TestTouchControls;
  end;

  TTestStates = class(TTestCase)
  published
    procedure TestVanillaTable;
    procedure TestDerivedSequences;
  end;

{ TTestWad }

{ Boom's ANIMATED and SWITCHES lumps of tools/testdata/boom.wad
  (tools/make_boom_wad.py). }
procedure TTestWad.TestBoomLumps;
var
  W: TDoomWad;
  Path: String;
  Anims: TAnimDefs;
  Switches: TSwitchDefs;
begin
  Path := 'tools/testdata/boom.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/boom.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    Anims := ParseAnimatedLump(W.LumpBytes(W.FindLump('ANIMATED')));
    AssertEquals('animations', 2, Length(Anims));
    AssertTrue('first is a flat', Anims[0].IsFlat);
    AssertEquals('first start', 'NUKAGE1', Anims[0].First);
    AssertEquals('first end', 'NUKAGE3', Anims[0].Last);
    AssertEquals('first speed', 4, Anims[0].Speed);
    AssertFalse('second is a texture', Anims[1].IsFlat);
    AssertEquals('second speed', 16, Anims[1].Speed);
    Switches := ParseSwitchesLump(W.LumpBytes(W.FindLump('SWITCHES')), 2);
    AssertEquals('Doom 1 switches', 2, Length(Switches));
    AssertEquals('switch off', 'SW1BRN1', Switches[0].Off);
    AssertEquals('switch on', 'STARTAN3', Switches[0].On_);
    AssertEquals('commercial switches', 3, Length(ParseSwitchesLump(W.LumpBytes(W.FindLump('SWITCHES')), 3)));
  finally
    FreeAndNil(W);
  end;
end;

{ UMAPINFO parsing (DoomMapInfo) and the lookups that use it, on
  tools/testdata/umapinfo.wad (tools/make_umapinfo_wad.py). }
procedure TTestWad.TestZMapInfo;
var
  W: TDoomWad;
  Path: String;
  List: TMapInfoList;
  Errors: TStringList;
  E: TMapInfoEntry;
  I: Integer;
begin
  List := TMapInfoList.Create(true);
  Errors := TStringList.Create;
  try
    { The old, line-based syntax with ";" comments and clusterdef. }
    AssertEquals('old maps', 2, ParseZMapInfo(
      '; old style' + LineEnding +
      'map E1M1 "Old Hangar"' + LineEnding +
      'next E1M2' + LineEnding +
      'secretnext E1M9' + LineEnding +
      'par 45 ; seconds' + LineEnding +
      'sky1 SKY2 0' + LineEnding +
      'cluster 3' + LineEnding +
      'nointermission' + LineEnding +
      'music D_E1M7' + LineEnding +
      'map E1M2 "Second"' + LineEnding +
      'cluster 4' + LineEnding +
      'clusterdef 3' + LineEnding +
      'exittext "Old text"' + LineEnding +
      'flat SLIME16' + LineEnding, List, Errors));
    E := List[0];
    AssertEquals('name', 'Old Hangar', E.LevelName);
    AssertEquals('next', 'E1M2', E.Next);
    AssertEquals('secret', 'E1M9', E.NextSecret);
    AssertEquals('par', 45, E.ParTime);
    AssertEquals('sky', 'SKY2', E.SkyTexture);
    AssertEquals('music', 'D_E1M7', E.Music);
    AssertTrue('flag without a value', E.NoIntermission);
    AssertEquals('cluster 3 -> 4: its exit text', 'Old text', E.InterText);
    AssertEquals('backdrop', 'SLIME16', E.InterBackdrop);
    AssertEquals('secret exit to no cluster: the text too', 'Old text', E.InterTextSecret);
    AssertEquals('second map', 'Second', List[1].LevelName);
    AssertFalse('second keeps no flag', List[1].NoIntermission);
    AssertEquals('no errors', 0, Errors.Count);

    { The new syntax from tools/testdata/mapinfo.wad. }
    List.Clear;
    Path := 'tools/testdata/mapinfo.wad';
    if not FileExists(Path) then
      Path := '../tools/testdata/mapinfo.wad';
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    try
      W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
      LoadMapInfo(W);
      E := MapInfoFor('E1M1');
      AssertTrue('E1M1', E <> nil);
      AssertEquals('title', 'MapInfo Hangar', E.LevelName);
      AssertEquals('defaultmap sky', 'SKY3', E.SkyTexture);
      AssertEquals('next', 'E1M3', E.Next);
      AssertEquals('par', 77, E.ParTime);
      AssertEquals('exit picture', 'TITLEPIC', E.ExitPic);
      AssertEquals('two-line exit text', 'You left the MAPINFO hangar.' + #10 + 'Cluster one is behind you.', E.InterText);
      AssertEquals('cluster flat', 'FLOOR7_2', E.InterBackdrop);
      AssertEquals('cluster music', 'D_VICTOR', E.InterMusic);
      E := MapInfoFor('E1M3');
      AssertEquals('lookup leaves the vanilla name', '', E.LevelName);
      AssertTrue('EndGame3 is the bunny', (E.EndGame = meYes) and E.EndBunny);
      AssertEquals('enter picture', 'CREDIT', E.EnterPic);
      AssertTrue('nointermission', E.NoIntermission);
      I := MapInfoEntries.Count;
      AssertTrue('clearepisodes before the episode', MapInfoEntries[I - 2].EpisodeClear);
      AssertEquals('episode name', 'MapInfo Episode', MapInfoEntries[I - 1].EpisodeName);
      AssertEquals('episode map', 'E1M3', MapInfoEntries[I - 1].MapName);
      { Back to plain Freedoom (the entries are global). }
      FreeAndNil(W);
      W := TDoomWad.Create(WadUrl('freedoom1.wad'));
      LoadMapInfo(W);
      AssertTrue('cleared', MapInfoFor('E1M1') = nil);
    finally
      FreeAndNil(W);
    end;
  finally
    FreeAndNil(Errors);
    FreeAndNil(List);
  end;
end;

procedure TTestWad.TestUMapInfo;
var
  W: TDoomWad;
  Path: String;
  List: TMapInfoList;
  Errors: TStringList;
  Strings: TDoomStrings;
begin
  List := TMapInfoList.Create(true);
  Errors := TStringList.Create;
  try
    AssertEquals('blocks', 2, ParseUMapInfo(
      'map MAP07 { levelname = "Dead Simple" /* c */ label = clear' + LineEnding +
      '  intertext = "a", "b"  // comment' + LineEnding +
      '  endgame = false  unknownkey = 5, 6 }' + LineEnding +
      'MAP MAP07 { levelname = "Again" next = "map09" nextsecret = "MAP31" partime = 30 }', List, Errors));
    AssertEquals('later block replaces', 1, List.Count);
    AssertEquals('replaced name', 'Again', List[0].LevelName);
    AssertEquals('next upper-cased', 'MAP09', List[0].Next);
    AssertEquals('par', 30, List[0].ParTime);
    AssertEquals('no errors', 0, Errors.Count);
    List.Clear;
    ParseUMapInfo('MAP E1M2 { levelname = "X" label = clear intertext = "a", "b" endgame = false }', List, Errors);
    AssertTrue('label clear', List[0].LabelClear);
    AssertEquals('text lines', 'a' + #10 + 'b', List[0].InterText);
    AssertTrue('endgame false', List[0].EndGame = meNo);
    List.Clear;
    ParseUMapInfo('MAP E2M1 { episode = "M_EPI9", "Fifth", "f" bossaction = BaronOfHell, 23, 666' + LineEnding +
      '  bossaction = 16, 11, 0 } MAP E3M1 { episode = clear bossaction = clear }', List, Errors);
    AssertEquals('episode patch', 'M_EPI9', List[0].EpisodePatch);
    AssertEquals('episode name', 'Fifth', List[0].EpisodeName);
    AssertEquals('boss actions', 2, Length(List[0].BossActions));
    AssertEquals('baron by class name', 3003, List[0].BossActions[0].ThingType);
    AssertEquals('cyberdemon by number', 16, List[0].BossActions[1].ThingType);
    AssertEquals('special', 11, List[0].BossActions[1].Special);
    AssertTrue('episode clear', List[1].EpisodeClear);
    AssertTrue('boss actions cleared', List[1].BossActionsSet and (Length(List[1].BossActions) = 0));
  finally
    FreeAndNil(Errors);
    FreeAndNil(List);
  end;

  Path := 'tools/testdata/umapinfo.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/umapinfo.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    LoadMapInfo(W);
    AssertEquals('next from UMAPINFO', 'E1M3', NextMapName('E1M1', false, false));
    AssertEquals('secret exit falls back to next', 'E1M3', NextMapName('E1M1', true, false));
    AssertEquals('vanilla next elsewhere', 'E1M5', NextMapName('E1M4', false, false));
    AssertEquals('par', 123, ParTime('E1M1', false));
    AssertTrue('E1M1 text decides the finale', MapInfoDecidesFinale('E1M1', false));
    AssertTrue('E1M1 has a finale', HasFinale('E1M1', false, false));
    AssertTrue('E1M3 ends the game', HasFinale('E1M3', false, false));
    AssertFalse('E1M2 has none', HasFinale('E1M2', false, false));
    Strings := TDoomStrings.Create(W);
    try
      AssertEquals('label: name', 'T1: Test Hangar', Strings.LevelName('E1M1', false));
      AssertEquals('label cleared', 'Third Test', Strings.LevelName('E1M3', false));
    finally
      FreeAndNil(Strings);
    end;
  finally
    { Back to no UMAPINFO for the other tests. }
    FreeAndNil(W);
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    LoadMapInfo(W);
    FreeAndNil(W);
  end;
end;

{ GameLogFilter's line rules (CASTLE_DOOM_LOG). }
procedure TTestWad.TestLogFilter;
var
  Categories: TStringList;
begin
  Categories := TStringList.Create;
  try
    Categories.CaseSensitive := false;
    Categories.Add('Load');
    Categories.Add('Shot');
    AssertEquals('category', 'Load', LogLineCategory('Load: E1M1: map parsed in 3 ms'));
    AssertEquals('no category', '', LogLineCategory('  Version: 0.6.0.'));
    AssertEquals('not a word', '', LogLineCategory('0.12 [0.12] - Load E1M1: x'));
    AssertTrue('listed', LogLineKept('load: E1M1', Categories, false));
    AssertFalse('not listed', LogLineKept('Music: Playing D_E1M1', Categories, true));
    AssertTrue('warning', LogLineKept('Warning: Music: no device', Categories, false));
    AssertTrue('continues a kept line', LogLineKept('> 0.09 [0.09] - Build geometry', Categories, true));
    AssertFalse('continues a dropped line', LogLineKept('> 0.09 [0.09] - Build geometry', Categories, false));
  finally
    FreeAndNil(Categories);
  end;
end;

procedure TTestWad.TestPhase1;
var
  W: TDoomWad;
  C: TVector4Byte;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    AssertFalse('Phase 1 is Doom 1', W.IsDoom2);
    AssertTrue('E1M1 listed', W.MapNames.IndexOf('E1M1') >= 0);
    AssertTrue('PLAYPAL', W.HasLump('PLAYPAL'));
    AssertEquals('COLORMAP size', 34 * 256, W.LumpSize(W.FindLump('COLORMAP')));
    AssertEquals('missing lump', -1, W.FindLump('NOSUCHLU'));
    C := W.PaletteColor(0);
    AssertEquals('palette 0 is black', 0, C.X + C.Y + C.Z);
    AssertEquals('palette alpha', 255, C.W);
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestWad.TestPhase2;
var
  W: TDoomWad;
begin
  W := TDoomWad.Create(WadUrl('freedoom2.wad'));
  try
    AssertTrue('Phase 2 is Doom 2', W.IsDoom2);
    AssertTrue('MAP01 listed', W.MapNames.IndexOf('MAP01') >= 0);
    AssertEquals('32 maps', 32, W.MapNames.Count);
  finally
    FreeAndNil(W);
  end;
end;

{ TTestMap }

function PolygonArea(const M: TDoomMap): Double;
var
  I, K, N: Integer;
  S: Double;
begin
  Result := 0;
  for I := 0 to High(M.Subsectors) do
  begin
    N := Length(M.Subsectors[I].Poly);
    S := 0;
    for K := 0 to N - 1 do
      S := S + M.Subsectors[I].Poly[K].X * M.Subsectors[I].Poly[(K + 1) mod N].Y -
        M.Subsectors[I].Poly[(K + 1) mod N].X * M.Subsectors[I].Poly[K].Y;
    Result := Result + Abs(S) / 2;
  end;
end;

procedure TTestMap.TestE1M1Bsp;
var
  W: TDoomWad;
  M: TDoomMap;
  I, Sec: Integer;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    M := TDoomMap.Create(W, 'E1M1');
    try
      AssertEquals('nodes format', 'VANILLA', M.NodesFormat);
      AssertEquals('subsectors', 682, Length(M.Subsectors));
      { The same total the game logs ("total area 6712683"). }
      AssertEquals('polygon area', 6712683, Round(PolygonArea(M)));
      for I := 0 to High(M.Subsectors) do
        AssertTrue('subsector sector', M.Subsectors[I].Sector >= 0);
      { The player start (-416, 256) is inside a sector, and the point
        lookup agrees with the subsector's own sector. }
      Sec := M.SectorAt(-416, 256);
      AssertTrue('start sector', (Sec >= 0) and (Sec <= High(M.Sectors)));
      AssertEquals('point in subsector', Sec, M.Subsectors[M.SubsectorAt(-416, 256)].Sector);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMap.TestMap01;
var
  W: TDoomWad;
  M: TDoomMap;
begin
  W := TDoomWad.Create(WadUrl('freedoom2.wad'));
  try
    M := TDoomMap.Create(W, 'MAP01');
    try
      AssertTrue('things', Length(M.Things) > 0);
      AssertTrue('polygons cover the map', PolygonArea(M) > 1e6);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ The line grid (TDoomMap.LinesInBox / LinesNearSegment) against a scan
  of every line: random boxes and segments over E1M1 and MAP01 must
  find every line a scan finds (bounding box overlap for a box, an
  intersection for a segment), in ascending order. }
procedure CheckLineGrid(const M: TDoomMap);
var
  Found: TLineList;
  Q, I, K, N: Integer;
  X1, Y1, X2, Y2, D, T, U, S0, S1, S2, S3: Single;
  V1, V2: TDoomVertex;
  InList: array of Boolean;
begin
  RandSeed := 7;
  SetLength(InList, Length(M.Linedefs));
  for Q := 1 to 4000 do
  begin
    X1 := M.MinX - 200 + Random * (M.MaxX - M.MinX + 400);
    Y1 := M.MinY - 200 + Random * (M.MaxY - M.MinY + 400);
    if Odd(Q) then
    begin
      X2 := X1 + Random * 100;
      Y2 := Y1 + Random * 100;
      N := M.LinesInBox(X1, Y1, X2, Y2, Found);
    end else
    begin
      X2 := X1 + (Random - 0.5) * 6000;
      Y2 := Y1 + (Random - 0.5) * 6000;
      if Q mod 10 = 0 then Y2 := Y1; { horizontal }
      N := M.LinesNearSegment(X1, Y1, X2, Y2, 1, Found);
    end;
    FillChar(InList[0], Length(InList), 0);
    for K := 0 to N - 1 do
    begin
      if K > 0 then
        TTestCase.AssertTrue('ascending', Found[K] > Found[K - 1]);
      InList[Found[K]] := true;
    end;
    for I := 0 to High(M.Linedefs) do
    begin
      V1 := M.Vertices[M.Linedefs[I].V1];
      V2 := M.Vertices[M.Linedefs[I].V2];
      if Odd(Q) then
      begin
        if (Max(V1.X, V2.X) < X1) or (Min(V1.X, V2.X) > X2) or
           (Max(V1.Y, V2.Y) < Y1) or (Min(V1.Y, V2.Y) > Y2) then Continue;
        { All four corners on one side: the line passes beside the box. }
        S0 := (X1 - V1.X) * (V2.Y - V1.Y) - (Y1 - V1.Y) * (V2.X - V1.X);
        S1 := (X2 - V1.X) * (V2.Y - V1.Y) - (Y1 - V1.Y) * (V2.X - V1.X);
        S2 := (X2 - V1.X) * (V2.Y - V1.Y) - (Y2 - V1.Y) * (V2.X - V1.X);
        S3 := (X1 - V1.X) * (V2.Y - V1.Y) - (Y2 - V1.Y) * (V2.X - V1.X);
        if ((S0 > 0) and (S1 > 0) and (S2 > 0) and (S3 > 0)) or
           ((S0 < 0) and (S1 < 0) and (S2 < 0) and (S3 < 0)) then Continue;
      end else
      begin
        D := (X2 - X1) * (V2.Y - V1.Y) - (Y2 - Y1) * (V2.X - V1.X);
        if Abs(D) < 1e-6 then Continue;
        T := ((V1.X - X1) * (V2.Y - V1.Y) - (V1.Y - Y1) * (V2.X - V1.X)) / D;
        U := ((V1.X - X1) * (Y2 - Y1) - (V1.Y - Y1) * (X2 - X1)) / D;
        if not ((T >= 0) and (T <= 1) and (U >= 0) and (U <= 1)) then Continue;
      end;
      TTestCase.AssertTrue(Format('%s query %d finds line %d', [M.Name, Q, I]), InList[I]);
    end;
  end;
end;

{ Boom's generalized line types decoded from their bit fields
  (boomref.txt's examples and the lines of tools/make_generalized_wad.py). }
procedure TTestMap.TestGeneralized;
var
  G: TGenLine;
begin
  AssertFalse('vanilla special', IsGeneralized(88));
  AssertTrue('vanilla decodes to nothing', DecodeGeneralized(1).Kind = gkNone);
  { 0x6892: S1 floor down to the lowest neighbour floor, fast, texture
    from the trigger line's front sector. }
  G := DecodeGeneralized($6892);
  AssertTrue('floor', G.Kind = gkFloor);
  AssertTrue('S1', G.Trigger = gtS1);
  AssertTrue('fast', G.Speed = gsFast);
  AssertFalse('down', G.Up);
  AssertTrue('lowest neighbour', G.Target = gtLowestNeighbour);
  AssertTrue('texture change', G.Change = gcTexture);
  AssertFalse('trigger model', G.NumericModel);
  AssertFalse('one shot', GenRepeatable(G));
  { The highest floor type: WR? no, DR turbo up by 32, texture and special,
    numeric model, crush. }
  G := DecodeGeneralized($7FFF);
  AssertTrue('top floor', (G.Kind = gkFloor) and (G.Trigger = gtDR) and (G.Speed = gsTurbo) and G.Up and
    (G.Target = gtBy32) and (G.Change = gcTextureAndSpecial) and G.NumericModel and G.Crush);
  AssertTrue('DR is manual and repeatable', GenManual(G) and GenRepeatable(G));
  { Ceiling down to the floor, crushing, fast, W1. }
  G := DecodeGeneralized($5210);
  AssertTrue('ceiling', (G.Kind = gkCeiling) and (G.Target = gtOwnOther) and G.Crush and not G.Up);
  { Doors: DR turbo open-wait-close for monsters too; W1 open-stay. }
  G := DecodeGeneralized($3C9F);
  AssertTrue('door', (G.Kind = gkDoor) and (G.DoorKind = gdOpenWaitClose) and G.Monster and
    (G.DelayTics = 35) and (G.Speed = gsTurbo));
  AssertTrue('monster bumps it', GenMonsterTrigger($3C9F, false));
  AssertFalse('not by walking', GenMonsterTrigger($3C9F, true));
  G := DecodeGeneralized($3C28 or $300);
  AssertTrue('open-stay door, 30 s delay field', (G.DoorKind = gdOpen) and (G.DelayTics = 30 * 35));
  { Locked: blue card or skull, DR. }
  G := DecodeGeneralized($3A8F);
  AssertTrue('locked door', (G.Kind = gkLockedDoor) and (G.Key = gkyBlueCard) and G.SkullIsCard);
  AssertFalse('never monsters', GenMonsterTrigger($3A8F or $20, false));
  { Lift: WR, 3 s, lowest floor; perpetual. }
  G := DecodeGeneralized($3449);
  AssertTrue('lift', (G.Kind = gkLift) and (G.Trigger = gtWR) and (G.DelayTics = 105) and
    (G.LiftTarget = glLowestFloor));
  AssertTrue('perpetual lift', DecodeGeneralized($3708).LiftTarget = glPerpetual);
  { Stairs: up by 16, any texture; crusher: silent. }
  G := DecodeGeneralized($3388);
  AssertTrue('stairs', (G.Kind = gkStairs) and G.Up and (G.StepSize = 16) and G.IgnoreTexture);
  G := DecodeGeneralized($2FC0);
  AssertTrue('crusher', (G.Kind = gkCrusher) and G.Silent and (G.Trigger = gtW1));
  AssertEquals('description', 'floor down to lowest neighbour floor, change texture (trigger model), fast, S1',
    GenDescription(DecodeGeneralized($6892)));
end;

{ Boom's scrollers on tools/testdata/scroll.wad (tools/make_scroll_wad.py):
  a 254 wall, a 255 wall, sector 141's floor, ceiling and carry. }
procedure TTestMap.TestDeepWater;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;
  I, Count: Integer;
  Tint: TVector3;
  Amount: Single;
begin
  Path := 'tools/testdata/water.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/water.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      { Line 829 (front sector 140) is a 242 for the tagged sector 141. }
      AssertEquals('control', 140, M.HeightSec[141]);
      Count := 0;
      for I := 0 to High(M.HeightSec) do
        if M.HeightSec[I] >= 0 then Inc(Count);
      AssertEquals('one deep water sector', 1, Count);
      AssertEquals('under water colormap', 'WATERMAP', M.WaterColormaps[141][0]);
      AssertEquals('a texture is no colormap', '', M.WaterColormaps[141][1]);
      AssertEquals('real floor', -96, M.Sectors[141].FloorHeight, 1e-4);
    finally
      FreeAndNil(M);
    end;
    { WATERMAP pulls colours 40% towards a blue-green. }
    AssertTrue('tint', W.ColormapTint('WATERMAP', Tint, Amount));
    AssertTrue(Format('amount %g', [Amount]), (Amount > 0.3) and (Amount < 0.5));
    AssertTrue('blue-green', (Tint.Z > Tint.X) and (Tint.Y > Tint.X));
    AssertFalse('COLORMAP is no tint', W.ColormapTint('COLORMAP', Tint, Amount));
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMap.TestDynScrollers;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;
  I, Wall, Floor, Carry: Integer;
begin
  Path := 'tools/testdata/dynscroll.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/dynscroll.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      { 248 (displacement floor + carry) and 218 (accelerative wall),
        both controlled by the lift (sector 98, floor 12, ceiling 128). }
      AssertEquals('runtime scrollers', 3, Length(M.DynScrollers));
      Wall := -1;
      Floor := -1;
      Carry := -1;
      for I := 0 to High(M.DynScrollers) do
      begin
        AssertEquals('control', 98, M.DynScrollers[I].Control);
        AssertEquals('last height', 140, M.DynScrollers[I].LastHeight, 1e-4);
        case M.DynScrollers[I].Target of
          stSide: Wall := I;
          stFloor: Floor := I;
          stCarry: Carry := I;
          else ;
        end;
      end;
      AssertTrue('wall found', Wall >= 0);
      AssertTrue('floor found', Floor >= 0);
      AssertTrue('carry found', Carry >= 0);
      AssertTrue('wall accelerates', M.DynScrollers[Wall].Accel);
      AssertFalse('floor displaces', M.DynScrollers[Floor].Accel);
      AssertEquals('wall side', M.Linedefs[911].Side[0], M.DynScrollers[Wall].Index);
      AssertEquals('floor sector', 141, M.DynScrollers[Floor].Index);
      AssertTrue('wall drawn from offsets', M.SideDynamic[M.Linedefs[911].Side[0]]);
      AssertTrue('floor drawn from offsets', M.FloorDynamic[141]);
      AssertFalse('ceiling constant', M.CeilingDynamic[141]);
      AssertEquals('carry is the floor rate times CARRYFACTOR',
        M.DynScrollers[Floor].Rate.Length * 0.1875, M.DynScrollers[Carry].Rate.Length, 1e-4);
      AssertEquals('no constant floor scroll', 0, M.FloorScroll[141].Length, 1e-6);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMap.TestScrollers;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;

  procedure CheckVector(const What: String; const V: TVector2; const X, Y: Single);
  begin
    AssertTrue(Format('%s: (%g, %g), expected (%g, %g)', [What, V.X, V.Y, X, Y]),
      (Abs(V.X - X) < 1e-4) and (Abs(V.Y - Y) < 1e-4));
  end;

begin
  Path := 'tools/testdata/scroll.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/scroll.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      AssertEquals('walls', 2, M.ScrollingSides);
      AssertEquals('floors', 1, M.ScrollingFloors);
      AssertEquals('ceilings', 1, M.ScrollingCeilings);
      AssertEquals('carrying floors', 1, M.CarryingFloors);
      { 254 from line 898 (48 east) onto line 911 (48 west). }
      CheckVector('254 wall', M.SideScroll[M.Linedefs[911].Side[0]], 1.5, 0);
      { 255 with the offsets (2, 0). }
      CheckVector('255 wall', M.SideScroll[M.Linedefs[1046].Side[0]], -2, 0);
      { 253 / 250 from lines 64 long pointing north. }
      CheckVector('floor', M.FloorScroll[141], 0, 2);
      CheckVector('ceiling', M.CeilingScroll[141], 0, 2);
      CheckVector('carry', M.Carry[141], 0, 2 * 0.1875);
      CheckVector('start room floor', M.FloorScroll[140], 0, 0);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ Boom's friction and pushers on tools/testdata/friction.wad
  (tools/make_friction_wad.py). }
procedure TTestMap.TestFriction;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;
  I, Points: Integer;
begin
  Path := 'tools/testdata/friction.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/friction.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      { 192 units of 223 line: ice, 0x1EB8 * 192 / 0x80 + 0xD000. }
      AssertEquals('ice friction', ($1EB8 * 192 / $80 + $D000) / $10000, M.Friction[140], 1e-5);
      AssertTrue('ice: less thrust', M.MoveFactor[140] < 0.2);
      { 64 units: mud. }
      AssertTrue('mud friction', M.Friction[141] < $E800 / $10000);
      AssertEquals('elsewhere Doom''s', $E800 / $10000, M.Friction[0], 1e-6);
      AssertEquals('pushers', 2, Length(M.Pushers));
      Points := 0;
      for I := 0 to High(M.Pushers) do
        if M.Pushers[I].Kind = pkCurrent then
        begin
          AssertEquals('current sector', 144, M.Pushers[I].Sector);
          AssertEquals('current west', -1, M.Pushers[I].X, 1e-6);
        end else
        begin
          Inc(Points);
          AssertTrue('push thing', M.Pushers[I].Kind = pkPush);
          AssertEquals('push radius', 256, M.Pushers[I].Radius, 1e-3);
        end;
      AssertEquals('one point pusher', 1, Points);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ Boom's translucency (260) on tools/testdata/translucent.wad
  (tools/make_translucent_wad.py): the default 66% and a custom map made
  a quarter opaque, its opacity estimated from the map. }
procedure TTestMap.TestTranslucency;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;
begin
  Path := 'tools/testdata/translucent.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/translucent.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      AssertEquals('translucent lines', 3, M.TranslucentLines);
      AssertEquals('default map', 0.66, M.LineAlpha[1052], 1e-6);
      AssertEquals('custom map, estimated', 0.25, M.LineAlpha[837], 0.05);
      AssertEquals('tagged with the 260 line', M.LineAlpha[837], M.LineAlpha[832], 1e-6);
      AssertEquals('the map''s name is not drawn', '-', M.Sidedefs[M.Linedefs[832].Side[0]].MiddleTex);
      AssertEquals('others solid', 1, M.LineAlpha[0], 1e-6);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ Boom's light and sky transfers on tools/testdata/transfer.wad
  (tools/make_transfer_wad.py). }
procedure TTestMap.TestTransfers;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;
begin
  Path := 'tools/testdata/transfer.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/transfer.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      AssertEquals('light transfer lines', 2, M.LightTransfers);
      AssertEquals('floor light from 133', 133, M.FloorLightSector[140]);
      AssertEquals('ceiling light from 133', 133, M.CeilingLightSector[140]);
      AssertEquals('others their own', -1, M.FloorLightSector[141]);
      AssertEquals('sky texture', 'STARTAN3', M.SkyTransferTexture);
      AssertTrue('272 mirrors', M.SkyTransferFlipped);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMap.TestLineGrid;
var
  W: TDoomWad;
  M: TDoomMap;
  Found: TLineList;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    M := TDoomMap.Create(W, 'E1M1');
    try
      AssertTrue('grid built', (M.GridWidth > 1) and (M.GridHeight > 1));
      CheckLineGrid(M);
      { The door at (544..560, 680..744): a small box finds a few lines,
        far fewer than the map has. }
      AssertTrue('few lines near the door', M.LinesInBox(530, 690, 570, 730, Found) < 40);
      AssertEquals('nothing far outside', 0, M.LinesInBox(M.MaxX + 5000, 0, M.MaxX + 5100, 100, Found));
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
  W := TDoomWad.Create(WadUrl('freedoom2.wad'));
  try
    M := TDoomMap.Create(W, 'MAP01');
    try
      CheckLineGrid(M);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ A generated node-format PWAD over Freedoom's E1M1: the format is
  detected and the subsector polygons cover the same area (glBSP builds
  its own BSP, so its totals differ a little from the vanilla ones). }
procedure TTestMap.CheckNodeWad(const FileName, ExpectedFormat: String;
  const Subsectors, Area: Integer);
var
  Path: String;
  W: TDoomWad;
  M: TDoomMap;
begin
  Path := 'tools/testdata/nodes/' + FileName;
  if not FileExists(Path) then
    Path := '../tools/testdata/nodes/' + FileName;
  if not FileExists(Path) then
  begin
    Writeln('Node WAD not generated, skipped: ', FileName,
      ' (python3 tools/make_znodes.py tools/testdata/nodes/ ; python3 tools/make_glnodes.py tools/testdata/nodes)');
    Exit;
  end;
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      AssertEquals(FileName + ' format', ExpectedFormat, M.NodesFormat);
      AssertEquals(FileName + ' subsectors', Subsectors, Length(M.Subsectors));
      AssertEquals(FileName + ' area', Area, Round(PolygonArea(M)));
      AssertEquals(FileName + ' start sector', M.SectorAt(-416, 256),
        M.Subsectors[M.SubsectorAt(-416, 256)].Sector);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMap.TestZDoomNodes;
begin
  CheckNodeWad('e1m1_xnod.wad', 'XNOD', 682, 6712683);
  CheckNodeWad('e1m1_znod.wad', 'ZNOD', 682, 6712683);
  CheckNodeWad('e1m1_xgln.wad', 'XGLN', 682, 6712683);
  CheckNodeWad('e1m1_zgl2.wad', 'ZGL2', 682, 6712683);
  CheckNodeWad('e1m1_xgl3.wad', 'XGL3', 682, 6712683);
  CheckNodeWad('e1m1_zgl3.wad', 'ZGL3', 682, 6712683);
end;

procedure TTestMap.TestGlBspNodes;
begin
  { V1 stores its GL vertices as whole units. }
  CheckNodeWad('e1m1_gl_v1.wad', 'GL_V1', 717, 6691431);
  CheckNodeWad('e1m1_gl_v2.wad', 'GL_V2', 717, 6713389);
  CheckNodeWad('e1m1_gl_v3.wad', 'GL_V3', 717, 6713389);
  CheckNodeWad('e1m1_gl_v5.wad', 'GL_V5', 717, 6713389);
end;

{ TTestMusic }

{ A MUS score: one channel, program 1, a note held 70 ticks (0.5 s at
  140 Hz), released, another 35 ticks, then the end. }
function MakeTestMus(out Size: Integer): TBytes;
const
  Score: array [0..11] of Byte = (
    $40, $00,       { controller 0 (instrument) 1: the next byte }
    $01,
    $90, $BC, $64,  { play note 60 with volume 100 (bit 7: volume follows), last of the tick }
    $46,            { delay 70 ticks }
    $80, $3C,       { release note 60, last }
    $23,            { delay 35 ticks }
    $60, $00);      { end of score (last), delay 0 }
var
  I: Integer;
begin
  Size := 16 + 2 + Length(Score);
  SetLength(Result, Size);
  Result[0] := Ord('M'); Result[1] := Ord('U'); Result[2] := Ord('S'); Result[3] := $1A;
  Result[4] := Length(Score); Result[5] := 0;  { score length }
  Result[6] := 18; Result[7] := 0;             { score start }
  Result[8] := 1; Result[9] := 0;              { primary channels }
  Result[10] := 0; Result[11] := 0;            { secondary channels }
  Result[12] := 1; Result[13] := 0;            { instruments }
  Result[14] := 0; Result[15] := 0;
  Result[16] := 1; Result[17] := 0;            { instrument 1 }
  for I := 0 to High(Score) do
    Result[18 + I] := Score[I];
end;

procedure TTestMusic.TestParseMus;
var
  Data: TBytes;
  Size: Integer;
  Events: TMusicEventList;
begin
  Data := MakeTestMus(Size);
  Events := TMusicEventList.Create;
  try
    AssertTrue('parsed', ParseMus(@Data[0], Size, Events));
    AssertEquals('events', 3, Events.Count);
    AssertTrue('program first', Events[0].Kind = ekProgram);
    AssertEquals('program 1', 1, Events[0].Data1);
    AssertTrue('note on', Events[1].Kind = ekNoteOn);
    AssertEquals('note 60', 60, Events[1].Data1);
    AssertEquals('velocity 100', 100, Events[1].Data2);
    AssertEquals('at 0 s', 0.0, Events[1].Time, 0.001);
    AssertTrue('note off', Events[2].Kind = ekNoteOff);
    AssertEquals('note off at 70 / 140 s', 0.5, Events[2].Time, 0.002);
    Events.Clear;
    AssertFalse('a MUS is not a MIDI', ParseMidi(@Data[0], Size, Events));
  finally
    FreeAndNil(Events);
  end;
end;

{ Freedoom's songs are MIDI: a few thousand events over a few minutes on
  several channels, the tempo map applied (no event at a silly time). }
procedure TTestMusic.TestParseMidi;
var
  W: TDoomWad;
  L, I, NoteOns, Channels: Integer;
  Events: TMusicEventList;
  Seen: set of 0..15;
  LastTime: Double;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  Events := TMusicEventList.Create;
  try
    L := W.FindLump('D_E1M1');
    AssertTrue('music lump', L >= 0);
    AssertTrue('MIDI parsed', ParseMidi(W.LumpPointer(L), W.LumpSize(L), Events));
    AssertTrue('many events', Events.Count > 1000);
    NoteOns := 0;
    Seen := [];
    LastTime := 0;
    for I := 0 to Events.Count - 1 do
    begin
      AssertTrue('times sorted', Events[I].Time >= LastTime);
      LastTime := Events[I].Time;
      if Events[I].Kind = ekNoteOn then
      begin
        Inc(NoteOns);
        Include(Seen, Events[I].Channel);
        AssertTrue('note range', (Events[I].Data1 >= 0) and (Events[I].Data1 <= 127));
      end;
    end;
    AssertTrue('note ons', NoteOns > 500);
    Channels := 0;
    for I := 0 to 15 do
      if I in Seen then Inc(Channels);
    AssertTrue('several channels', Channels >= 3);
    AssertTrue('a few minutes long', (LastTime > 60) and (LastTime < 480));
    Events.Clear;
    AssertFalse('a MIDI is not a MUS', ParseMus(W.LumpPointer(L), W.LumpSize(L), Events));
  finally
    FreeAndNil(Events);
    FreeAndNil(W);
  end;
end;

{ The test MUS rendered: sound while the note is held, the release has
  died away a second after the note off (the song ends 1.5 s after the
  last event, the note off). }
procedure TTestMusic.CheckEnvelope(const Fm: Boolean);
var
  W: TDoomWad;
  Data: TBytes;
  Size, I, N: Integer;
  Wav: TMemoryStream;
  P: PSmallInt;

  function Rms(const FromSec, ToSec: Double): Double;
  var
    A, B, K: Integer;
    S: Double;
  begin
    A := Round(FromSec * 22050);
    B := Min(Round(ToSec * 22050), N) - 1;
    S := 0;
    for K := A to B do
      S := S + Sqr(P[K] / 32768);
    Result := Sqrt(S / Max(1, B - A + 1));
  end;

begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    Data := MakeTestMus(Size);
    ForceFmSynth := Fm;
    Wav := RenderDoomSong(W, @Data[0], Size);
    ForceFmSynth := false;
    AssertNotNull('rendered', Wav);
    try
      P := PSmallInt(PByte(Wav.Memory) + 44);
      N := (Wav.Size - 44) div 2;
      { 1.5 s after the last event, the note off at 0.5 s. }
      AssertTrue('about 2 s long', Abs(N / 22050 - 2.0) < 0.1);
      AssertTrue('sound while held', Rms(0.1, 0.45) > 0.01);
      AssertTrue('quiet a second after the release', Rms(1.5, 1.95) < Rms(0.1, 0.45) / 10);
    finally
      FreeAndNil(Wav);
    end;
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMusic.TestEnvelopeFm;
begin
  CheckEnvelope(true);
end;

procedure TTestMusic.TestEnvelopeOpl3;
begin
  if Opl3Available then
    CheckEnvelope(false)
  else
    Writeln('Nuked OPL3 not available, envelope not tested: ', Opl3Status);
end;

procedure TTestMusic.TestRenderMus;
var
  W: TDoomWad;
  L, Rate, DataSize: Integer;
  Wav: TMemoryStream;
  Header: array [0..43] of Byte;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    L := W.FindLump('D_E1M8');
    AssertTrue('music lump', L >= 0);
    Wav := RenderDoomSong(W, W.LumpPointer(L), W.LumpSize(L));
    AssertNotNull('rendered', Wav);
    try
      Wav.Position := 0;
      Wav.ReadBuffer(Header, SizeOf(Header));
      AssertEquals('RIFF', 'RIFF', Chr(Header[0]) + Chr(Header[1]) + Chr(Header[2]) + Chr(Header[3]));
      AssertEquals('WAVE', 'WAVE', Chr(Header[8]) + Chr(Header[9]) + Chr(Header[10]) + Chr(Header[11]));
      Rate := Header[24] or (Header[25] shl 8) or (Header[26] shl 16) or (Header[27] shl 24);
      AssertEquals('sample rate', 22050, Rate);
      DataSize := Header[40] or (Header[41] shl 8) or (Header[42] shl 16) or (Header[43] shl 24);
      AssertEquals('data size', Wav.Size - 44, DataSize);
      { 16-bit mono: more than 10 s of music. }
      AssertTrue('length', DataSize div 2 > 10 * Rate);
    finally
      FreeAndNil(Wav);
    end;
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestMusic.TestRejectGarbage;
var
  W: TDoomWad;
  Junk: array [0..63] of Byte;
  I: Integer;
  Wav: TMemoryStream;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    for I := 0 to High(Junk) do
      Junk[I] := (I * 37) and $FF;
    Wav := RenderDoomSong(W, @Junk[0], SizeOf(Junk));
    try
      AssertNull('not a song', Wav);
    finally
      FreeAndNil(Wav);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ Both synthesizers render the same song to the same length, and differ
  (the OPL3 library is optional: without it only the FM model is tried). }
procedure TTestMusic.TestOpl3Synth;
var
  W: TDoomWad;
  L, I, Differ: Integer;
  Fm, Opl: TMemoryStream;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    L := W.FindLump('D_E1M8');
    AssertTrue('music lump', L >= 0);
    ForceFmSynth := true;
    Fm := RenderDoomSong(W, W.LumpPointer(L), W.LumpSize(L));
    ForceFmSynth := false;
    Opl := RenderDoomSong(W, W.LumpPointer(L), W.LumpSize(L));
    try
      AssertNotNull('FM rendered', Fm);
      AssertNotNull('OPL rendered', Opl);
      AssertEquals('same length', Fm.Size, Opl.Size);
      if Opl3Available then
      begin
        Differ := 0;
        for I := 44 to Fm.Size - 1 do
          if PByte(Fm.Memory)[I] <> PByte(Opl.Memory)[I] then Inc(Differ);
        AssertTrue('OPL3 output differs from the FM model', Differ > Fm.Size div 2);
        Writeln('Nuked OPL3 tested: ', Opl3Status);
      end else
        Writeln('Nuked OPL3 not tested: ', Opl3Status);
    finally
      FreeAndNil(Fm);
      FreeAndNil(Opl);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ TTestDehacked }

procedure TTestDehacked.TestFreedoomLump;
var
  W: TDoomWad;
  S: TDoomStrings;
  Par: Integer;
begin
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    ApplyDehacked(W);
    { Freedoom's [PARS]: E1M1 is 30 s, E1M2 2:00. }
    AssertTrue('par E1M1', DehackedParTime('E1M1', Par));
    AssertEquals('par E1M1 seconds', 30, Par);
    AssertTrue('par E1M2', DehackedParTime('E1M2', Par));
    AssertEquals('par E1M2 seconds', 120, Par);
    AssertEquals('vanilla health', 100, DehMisc.InitialHealth);
    AssertEquals('vanilla imp', 60, FindThingInfo(3001)^.Health);
    S := TDoomStrings.Create(W);
    try
      AssertTrue('BEX strings', S.Count > 100);
      AssertEquals('level name', 'E1M1: Outer Prison', S.LevelName('E1M1', false));
    finally
      FreeAndNil(S);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ MBF's TRANSLUCENT bit (31) in "Bits", by name and as an unsigned
  number (tools/testdata/translucent.deh). }
procedure TTestDehacked.TestTranslucentBits;
var
  W: TDoomWad;
  Patch: String;
begin
  Patch := 'tools/testdata/translucent.deh';
  if not FileExists(Patch) then
    Patch := '../tools/testdata/translucent.deh';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    AddDehackedFile(Patch);
    ApplyDehacked(W);
    AssertTrue('imp translucent (by name)', FindThingInfo(3001)^.Translucent);
    AssertTrue('imp still solid', FindThingInfo(3001)^.Solid);
    AssertTrue('zombieman translucent (by number)', FindThingInfo(3004)^.Translucent);
    AssertTrue('zombieman still solid', FindThingInfo(3004)^.Solid);
    AssertFalse('sergeant untouched', FindThingInfo(9)^.Translucent);
  finally
    FreeAndNil(W);
  end;
end;

procedure TTestDehacked.TestPatchFile;
var
  W: TDoomWad;
  S: TDoomStrings;
  Par: Integer;
  Patch: String;
begin
  Patch := 'tools/testdata/test.deh';
  if not FileExists(Patch) then
    Patch := '../tools/testdata/test.deh';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    { The patch comes after the WAD's DEHACKED lump and wins. }
    AddDehackedFile(Patch);
    ApplyDehacked(W);
    AssertEquals('Misc initial health', 50, DehMisc.InitialHealth);
    AssertEquals('Misc initial bullets', 20, DehMisc.InitialBullets);
    AssertEquals('Ammo 0 max', 100, DehMaxAmmo[0]);
    AssertEquals('Ammo 0 clip', 7, DehClipAmmo[0]);
    AssertEquals('Thing 12 (imp) hit points', 1, FindThingInfo(3001)^.Health);
    AssertEquals('Thing 12 width (fixed 20.0)', 20, FindThingInfo(3001)^.Radius);
    AssertEquals('zombieman untouched', 20, FindThingInfo(3004)^.Health);
    { "Frame 452 Duration = 1": the imp's first attack frame. }
    AssertEquals('S_TROO_ATK1 tics', 1, States[452].Tics);
    AssertEquals('imp attack frames', 'EFG', FindThingInfo(3001)^.Seqs[skAttack].Frames);
    AssertEquals('imp attack first tics', 1, FindThingInfo(3001)^.Seqs[skAttack].Tics[0]);
    AssertEquals('imp attack second tics', 8, FindThingInfo(3001)^.Seqs[skAttack].Tics[1]);
    { "Pointer 1 (Frame 454) Codep Frame = 487": the imp bites like a demon. }
    AssertTrue('imp attack code pointer', FindThingInfo(3001)^.AttackAction = saSargAttack);
    AssertTrue('imp attack kind', FindThingInfo(3001)^.Attack = akMelee);
    AssertEquals('imp bite dice', 4, FindThingInfo(3001)^.DamageDice);
    { "[CODEPTR] FRAME 185 = A_SPosAttack": the zombieman fires three pellets. }
    AssertTrue('zombie code pointer', FindThingInfo(3004)^.AttackAction = saSPosAttack);
    AssertEquals('zombie pellets', 3, FindThingInfo(3004)^.Shots);
    AssertEquals('zombie attack sound', 'DSSHOTGN', FindThingInfo(3004)^.AttackSound);
    AssertTrue('pistol shot code pointer', States[14].Action = saFireShotgun);
    AssertEquals('imp fireball speed (fixed 20.0)', 20, Mobjs[31].Speed);
    AssertEquals('imp fireball damage', 1, Mobjs[31].Damage);
    AssertEquals('pistol attack state', StateByName('PISTOL1'), Weapons[1].Attack);
    AssertTrue('patch par', DehackedParTime('E1M1', Par));
    AssertEquals('patch par seconds', 999, Par);
    S := TDoomStrings.Create(W);
    try
      { A BEX value continued with a backslash. }
      AssertEquals('GOTCLIP', 'Picked up a DEH clip.Really.', S.Get('GOTCLIP'));
    finally
      FreeAndNil(S);
    end;
  finally
    FreeAndNil(W);
  end;
end;

{ TTestStates }

procedure TTestStates.TestVanillaTable;
var
  A: TStateAction;
begin
  ResetStates;
  AssertEquals('states', 967, Length(States));
  AssertEquals('sprites', 138, Length(Sprites));
  AssertEquals('things', 137, Length(Mobjs));
  AssertEquals('sounds', 109, Length(Sounds));
  AssertEquals('S_NULL sprite', 'TROO', Sprites[States[0].Sprite]);
  AssertEquals('S_TROO_ATK3 tics', 6, States[454].Tics);
  AssertTrue('S_TROO_ATK3 action', States[454].Action = saTroopAttack);
  AssertEquals('S_TROO_ATK3 next is S_TROO_RUN1', 444, States[454].Next);
  AssertTrue('S_SKULL_ATK2 is full bright', (States[590].Frame and $8000) <> 0);
  AssertEquals('MT_TROOP doomednum', 3001, Mobjs[11].DoomedNum);
  AssertEquals('MT_TROOP see sound', 'DSBGSIT1', SoundName(Mobjs[11].SeeSound));
  AssertEquals('imp mobj row', 11, MobjIndexOf(3001));
  AssertEquals('no row for 12345', -1, MobjIndexOf(12345));
  AssertTrue('A_PosAttack by name', ActionByName('A_PosAttack', A) and (A = saPosAttack));
  AssertTrue('posattack without prefix', ActionByName('posattack', A) and (A = saPosAttack));
  AssertFalse('unknown action', ActionByName('A_Nothing', A));
end;

procedure TTestStates.TestDerivedSequences;
var
  Imp, Zombie, Sergeant, Spectre, Caco, Keen, Bonus: PThingInfo;
begin
  ResetStates;
  ResetThingInfos;
  Imp := FindThingInfo(3001);
  AssertEquals('imp sprite', 'TROO', Imp^.Sprite);
  AssertEquals('imp idle', 'AB', Imp^.Seqs[skIdle].Frames);
  AssertEquals('imp idle tics', 10, Imp^.Seqs[skIdle].Tics[0]);
  AssertTrue('imp idle loops', Imp^.Seqs[skIdle].Loop);
  { Each walking frame twice, 3 tics each (S_TROO_RUN1..8). }
  AssertEquals('imp walk', 'AABBCCDD', Imp^.Seqs[skMove].Frames);
  AssertEquals('imp walk tics', 3, Imp^.Seqs[skMove].Tics[0]);
  AssertEquals('imp walk legacy string', 'AABBCCDD', Imp^.MoveFrames);
  AssertEquals('imp attack', 'EFG', Imp^.Seqs[skAttack].Frames);
  AssertEquals('imp attack tics 1', 8, Imp^.Seqs[skAttack].Tics[0]);
  AssertEquals('imp attack tics 3', 6, Imp^.Seqs[skAttack].Tics[2]);
  AssertTrue('imp attack action on G', Imp^.Seqs[skAttack].Actions[2] = saTroopAttack);
  AssertEquals('imp pain', 'HH', Imp^.Seqs[skPain].Frames);
  AssertEquals('imp death', 'IJKLM', Imp^.Seqs[skDeath].Frames);
  AssertTrue('imp corpse stays', Imp^.Seqs[skDeath].Forever);
  AssertEquals('imp gibs', 'NOPQRSTU', Imp^.Seqs[skXDeath].Frames);
  AssertEquals('imp raise', 'MLKJI', Imp^.Seqs[skRaise].Frames);
  AssertEquals('imp legacy strings', 'IJKLM', Imp^.DeathFrames);
  AssertTrue('imp attack kind', Imp^.Attack = akMissile);
  AssertTrue('imp code pointer', Imp^.AttackAction = saTroopAttack);
  Zombie := FindThingInfo(3004);
  AssertTrue('zombie hitscan', (Zombie^.Attack = akHitscan) and (Zombie^.AttackAction = saPosAttack));
  AssertEquals('zombie one pellet', 1, Zombie^.Shots);
  AssertEquals('zombie pistol', 'DSPISTOL', Zombie^.AttackSound);
  { Vanilla lights only the sergeant's flash (Freedoom's DEHACKED lump
    adds the zombieman's). }
  AssertFalse('zombie flash is not bright in vanilla', Zombie^.Seqs[skAttack].Bright[1]);
  Sergeant := FindThingInfo(9);
  AssertEquals('sergeant three pellets', 3, Sergeant^.Shots);
  AssertTrue('sergeant muzzle flash is bright', Sergeant^.Seqs[skAttack].Bright[1]);
  AssertFalse('sergeant aim frame is not', Sergeant^.Seqs[skAttack].Bright[0]);
  Spectre := FindThingInfo(58);
  AssertTrue('spectre shadow', Spectre^.Shadow);
  AssertFalse('demon no shadow', FindThingInfo(3002)^.Shadow);
  AssertTrue('demon bites', FindThingInfo(3002)^.Attack = akMelee);
  Caco := FindThingInfo(3005);
  AssertTrue('cacodemon floats', Caco^.Floats);
  AssertEquals('cacodemon pain', 'EEF', Caco^.Seqs[skPain].Frames);
  Keen := FindThingInfo(72);
  AssertTrue('Keen hangs', Keen^.Hanging);
  AssertTrue('Keen has no attack', Keen^.Attack = akNone);
  AssertEquals('Keen death', 'ABCDEFGHIJKL', Keen^.Seqs[skDeath].Frames);
  Bonus := FindThingInfo(2014);
  AssertEquals('health bonus frames', 'ABCDCB', Bonus^.Seqs[skIdle].Frames);
  AssertEquals('health bonus tics', 6, Bonus^.IdleTics);
  AssertEquals('barrel', 'AB', FindThingInfo(2035)^.IdleFrames);
  AssertTrue('barrel solid', FindThingInfo(2035)^.Solid);
  AssertFalse('candle not solid', FindThingInfo(34)^.Solid);
  AssertEquals('dead player frame', 'W', FindThingInfo(10)^.IdleFrames);
  AssertEquals('brain pain tics', 36, FindThingInfo(88)^.Seqs[skPain].Tics[0]);
  AssertEquals('brain pain sound stays with DoomWorld', '', FindThingInfo(88)^.PainSound);
end;

{ TTestGamepad }

procedure TTestGamepad.TestPadBindings;
var
  Event: TInputPressRelease;
begin
  ResetPad;
  AssertTrue('RT fires', PadIs(pbRightTrigger, gpaFire));
  AssertTrue('X uses', PadIs(pbX, gpaUse));
  AssertEquals('use text', 'A / X', PadActionText(gpaUse));
  { A button moves from the action that had it. }
  BindPad(gpaFire, 1, pbX);
  AssertTrue('X fires', PadIs(pbX, gpaFire));
  AssertFalse('X no longer uses', PadIs(pbX, gpaUse));
  AssertEquals('use text after', 'A', PadActionText(gpaUse));
  BindPad(gpaAutomap, 0, pbNone);
  AssertEquals('cleared', '-', PadActionText(gpaAutomap));
  AssertTrue('names', StrToPadButton('dpadup') = pbDPadUp);
  AssertTrue('unknown', StrToPadButton('Start') = pbNone);
  { Events: B (east) is pbB; Start (menu) has no pad button; triggers
    have no events. }
  AssertTrue('B event', PadButtonEvent(pbB, Event));
  AssertTrue('east', Event.Controller.Button = gbEast);
  AssertTrue('B back', PadButtonOfEvent(Event) = pbB);
  Event.Controller.Button := gbMenu;
  AssertTrue('Start unbindable', PadButtonOfEvent(Event) = pbNone);
  AssertFalse('trigger event', PadButtonEvent(pbLeftTrigger, Event));
  { Held buttons (demo scripts) count for their actions. }
  SimulatedPadHeld := [pbX];
  AssertTrue('fire held through X', GamepadFireHeld);
  SimulatedPadHeld := [];
  ResetPad;
end;

procedure TTestGamepad.TestTouchControls;
var
  T: TDoomTouchControls;
  Middle: TVector2;
  Radius: Single;
  V: TVector2;
begin
  TouchForced := false;
  T := TDoomTouchControls.Create(nil);
  try
    T.SetTestSize(1600, 900);
    { The stick: a finger on the left, pushed up half the stick's radius
      (0.13 of the height) walks forward at half speed. }
    T.TouchDown(1, Vector2(300, 400));
    T.TouchMove(1, Vector2(300, 400 + 0.065 * 900));
    V := T.MoveVector;
    AssertEquals('stick forward', 0.5, V.Y, 0.01);
    AssertEquals('stick sideways', 0, V.X, 0.01);
    { Pushed far beyond the edge it is full speed, and the centre follows. }
    T.TouchMove(1, Vector2(300 + 500, 400));
    AssertEquals('stick right, full', 1, T.MoveVector.X, 0.01);
    T.TouchMove(1, Vector2(300 + 500 - 0.13 * 900, 400));
    AssertEquals('centre followed', 0, T.MoveVector.Length, 0.01);
    { A drag on the right turns: a tenth of the width is 18 degrees. }
    T.TouchDown(2, Vector2(1000, 500));
    T.TouchMove(2, Vector2(1160, 520));
    V := T.TakeLook;
    AssertEquals('look right', 18, V.X, 0.01);
    AssertEquals('look up', 2.25, V.Y, 0.01);
    AssertEquals('look taken', 0, T.TakeLook.Length, 0.0001);
    { Fire is held while a finger is on it, and dragging it turns too. }
    T.ButtonCircle(tbFire, Middle, Radius);
    AssertTrue('fire button found', T.ButtonAt(Middle) = tbFire);
    T.TouchDown(3, Middle);
    AssertTrue('fire held', T.FireHeld);
    T.TouchMove(3, Middle + Vector2(-80, 0));
    AssertEquals('fire turns', -9, T.TakeLook.X, 0.01);
    T.TouchUp(3);
    AssertFalse('fire released', T.FireHeld);
    { The browser's answer: finger 2 stays, 1 lifted, 7 new on Use. }
    T.ButtonCircle(tbUse, Middle, Radius);
    ApplyTouchState(Format('1;2,1160,520;7,%d,%d', [Round(Middle.X), Round(Middle.Y)]), T);
    AssertTrue('touch mode from the page', TouchMode);
    AssertEquals('fingers', 2, T.TouchCount);
    AssertEquals('stick gone', 0, T.MoveVector.Length, 0.0001);
    ApplyTouchState('0', T);
    AssertFalse('mouse again', TouchMode);
    AssertEquals('all lifted', 0, T.TouchCount);
  finally
    FreeAndNil(T);
  end;
end;

procedure TTestGamepad.TestWebPadMapping;
var
  Pads: TWebPads;
  C: TGameController;
begin
  { A browser pad (standard mapping) as the web build reads it each frame:
    the left stick a bit right and half forward (the browser's Y points
    down), the right stick left and fully down, A, D-pad down and Start
    pressed, the right trigger most of the way in. }
  ResetPad;
  Pads := Default(TWebPads);
  Pads[0].Id := 'Test pad (STANDARD GAMEPAD Vendor: 045e Product: 02ea)';
  Pads[0].Axes[0] := 0.25;
  Pads[0].Axes[1] := -0.5;
  Pads[0].Axes[2] := -0.75;
  Pads[0].Axes[3] := 1;
  Pads[0].Pressed[0] := true;
  Pads[0].Pressed[9] := true;
  Pads[0].Pressed[13] := true;
  Pads[0].RightTrigger := 0.8;
  ApplyWebPads(Pads, 1);
  AssertEquals('one controller', 1, Controllers.Count);
  C := Controllers[0];
  AssertEquals('name', Pads[0].Id, C.Name);
  AssertEquals('left stick X', 0.25, C.AxisLeft.X, 0.001);
  AssertEquals('left stick Y (up is forward)', 0.5, C.AxisLeft.Y, 0.001);
  AssertEquals('right stick X', -0.75, C.AxisRight.X, 0.001);
  AssertEquals('right stick Y', -1, C.AxisRight.Y, 0.001);
  AssertEquals('right trigger', 0.8, C.AxisRightTrigger, 0.001);
  AssertEquals('left trigger', 0, C.AxisLeftTrigger, 0.001);
  AssertTrue('A is south', C.InternalPressedToReport[gbSouth]);
  AssertTrue('D-pad down', C.InternalPressedToReport[gbDPadDown]);
  AssertTrue('Start is menu', C.InternalPressedToReport[gbMenu]);
  AssertFalse('B released', C.InternalPressedToReport[gbEast]);
  AssertFalse('D-pad up released', C.InternalPressedToReport[gbDPadUp]);
  AssertFalse('View released', C.InternalPressedToReport[gbView]);
  AssertTrue('fire held', GamepadFireHeld);
  { Buttons let go, then the pad unplugged. }
  Pads[0].Pressed[0] := false;
  Pads[0].RightTrigger := 0;
  ApplyWebPads(Pads, 1);
  AssertEquals('still one controller', 1, Controllers.Count);
  AssertFalse('A released', Controllers[0].InternalPressedToReport[gbSouth]);
  AssertFalse('fire released', GamepadFireHeld);
  ApplyWebPads(Pads, 0);
  AssertEquals('unplugged', 0, Controllers.Count);
end;

var
  App: TTestRunner;
begin
  RegisterTests([TTestWad, TTestMap, TTestMusic, TTestDehacked, TTestGamepad, TTestStates]);
  DefaultFormat := fPlain;
  DefaultRunAllTests := true;
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'Castle DOOM unit tests';
    App.Run;
  finally
    FreeAndNil(App);
  end;
end.
