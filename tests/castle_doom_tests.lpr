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

uses FpJson, SysUtils, Classes, Math, fpcunit, testregistry, consoletestrunner,
  CastleVectors, CastleUriUtils, CastleGameControllers, CastleKeysMouse,
  DoomWad, DoomGraphics, DoomMap, DoomMusic, DoomOpl3, DoomThings, DoomDehacked, DoomStates, GameGamepad, GameSettings, GameTouch, GameLogFilter, DoomMapInfo, DoomWorld, DoomIntermission, DoomFinale,
  DoomGeneralized, DoomWiScript, DoomRandomMap, DoomDemo, DoomLighting, X3DNodes, X3DFields, DoomCaptions, DoomMenu, DoomEditMap, DoomNodeBuilder, DoomExport, X3DLoad;

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
  TBooleanArray = array of Boolean;

  TTestWad = class(TTestCase)
  published
    procedure TestPhase1;
    procedure TestPhase2;
    procedure TestBoomLumps;
    procedure TestUploads;
    procedure TestLogFilter;
    procedure TestUMapInfo;
    procedure TestZMapInfo;
    procedure TestLanguage;
    procedure TestWiScript;
    procedure TestDemoFile;
    procedure TestDemoCompact;
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
    procedure TestSectorSkies;
    procedure TestFriction;
    procedure TestTranslucency;
    procedure TestTransfers;
    procedure TestRandomMaps;
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
  strict private
    FMenu: TDoomMenuScreen;
    FMenuRequests: String;
    procedure MenuAction(const Action: TDoomMenuAction);
  published
    procedure TestWebPadMapping;
    procedure TestPadBindings;
    procedure TestKeyBindings;
    procedure TestBestTimes;
    procedure TestGamma;
    procedure TestCaptions;
    procedure TestDynamicLights;
    procedure TestCustomGamePage;
    procedure TestTouchControls;
  end;

  TTestEditor = class(TTestCase)
  strict private
    FTriangles, FShapes: Integer;
    procedure CountTriangles(Node: TX3DNode);
    procedure CountShape(Node: TX3DNode);
    procedure CheckEditRoundTrip(const IwadName, MapName: String; const Tolerance: Double);
  published
    procedure TestEditRoundTrip;
    procedure TestEditOperations;
    procedure TestSceneExport;
    procedure TestEditWalls;
    procedure TestEditCutDelete;
    procedure TestEditFlipOutline;
  end;

  TTestStates = class(TTestCase)
  published
    procedure TestVanillaTable;
    procedure TestDerivedSequences;
  end;

{ TTestWad }

{ Boom's ANIMATED and SWITCHES lumps of tools/testdata/boom.wad
  (tools/make_boom_wad.py). }
{ Files the browser's picker gives (upload:/NAME): loaded from memory,
  gone ones reported by WadUrlAvailable instead of raising. }
{ A stand-in for the upload store (the browser's IndexedDB). }
var
  TestStore: TStringList;

procedure TestKeep(const Url: String; const Data: TMemoryStream);
var
  S: String;
begin
  SetLength(S, Data.Size);
  if Data.Size > 0 then Move(Data.Memory^, S[1], Data.Size);
  TestStore.Values[Url] := S;
end;

function TestRestore(const Url: String): TMemoryStream;
var
  S: String;
begin
  Result := nil;
  if TestStore.IndexOfName(Url) < 0 then Exit;
  S := TestStore.Values[Url];
  Result := TMemoryStream.Create;
  if S <> '' then Result.WriteBuffer(S[1], Length(S));
end;

procedure TestForget(const Url: String);
begin
  if TestStore.IndexOfName(Url) >= 0 then
    TestStore.Delete(TestStore.IndexOfName(Url));
end;

procedure TTestWad.TestUploads;
var
  W: TDoomWad;
  Data: TMemoryStream;
  Path, Url, Text: String;
  Maps: TStringList;
begin
  Path := 'tools/testdata/boom.wad';
  if not FileExists(Path) then Path := '../tools/testdata/boom.wad';
  AssertFalse('not yet', WadUrlAvailable('upload:/boom.wad'));
  AssertTrue('other URLs', WadUrlAvailable('castle-data:/x.wad'));
  Data := TMemoryStream.Create;
  try
    Data.LoadFromFile(Path);
    Url := RegisterUpload('/some/dir/boom.wad', Data);
  finally
    FreeAndNil(Data);
  end;
  AssertEquals('url', 'upload:/boom.wad', Url);
  AssertTrue('available', WadUrlAvailable(Url));
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(Url);
    AssertTrue('its ANIMATED lump', W.FindLump('ANIMATED') >= 0);
    AssertTrue('described', Pos('boom.wad', W.Description) > 0);
  finally
    FreeAndNil(W);
  end;
  { A PWAD's maps from its directory alone (the map editor's Ctrl+O). }
  Maps := WadFileMapNames(FilenameToUriSafe(ExpandFileName(
    StringReplace(Path, 'boom.wad', 'generalized.wad', []))));
  try
    AssertTrue('a WAD', Maps <> nil);
    AssertEquals('its map', 'E1M1', Maps.CommaText);
  finally
    FreeAndNil(Maps);
  end;
  Maps := WadFileMapNames(Url);
  try
    AssertTrue('boom.wad has no map', (Maps <> nil) and (Maps.Count = 0));
  finally
    FreeAndNil(Maps);
  end;
  AssertTrue('readable upload', WadUrlReadable(Url));
  AssertFalse('a missing file', WadUrlReadable('file:///no/such.wad'));
  AssertTrue('random maps', WadUrlReadable('random:/42'));
  { The store keeps a new upload and gives it back after the memory lost
    it (a reloaded page); forgetting drops it from both. }
  TestStore := TStringList.Create;
  try
    OnKeepUpload := @TestKeep;
    OnRestoreUpload := @TestRestore;
    OnForgetUpload := @TestForget;
    Data := TMemoryStream.Create;
    try
      Data.WriteBuffer(PChar('PWAD')^, 4);
      Url := RegisterUpload('kept.wad', Data);
    finally
      FreeAndNil(Data);
    end;
    AssertEquals('kept', 1, TestStore.Count);
    OnForgetUpload := nil;
    ForgetUpload(Url);                 { the memory only }
    OnForgetUpload := @TestForget;
    AssertEquals('still stored', 1, TestStore.Count);
    AssertTrue('restored', UploadText(Url, Text));
    AssertEquals('its bytes', 'PWAD', Text);
    ForgetUpload(Url);
    AssertEquals('forgotten', 0, TestStore.Count);
    AssertFalse('gone', WadUrlAvailable(Url));
  finally
    OnKeepUpload := nil;
    OnRestoreUpload := nil;
    OnForgetUpload := nil;
    FreeAndNil(TestStore);
  end;
end;

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
      AssertEquals('looking up its own HUSTR_E1M3 leaves the vanilla name (and patch)', '', E.LevelName);
      AssertTrue('EndGame3 is the bunny', (E.EndGame = meYes) and E.EndBunny);
      AssertEquals('enter picture', 'CREDIT', E.EnterPic);
      AssertTrue('nointermission', E.NoIntermission);
      I := MapInfoEntries.Count;
      AssertTrue('clearepisodes before the episode', MapInfoEntries[I - 2].EpisodeClear);
      AssertEquals('episode name', 'MapInfo Episode', MapInfoEntries[I - 1].EpisodeName);
      AssertEquals('episode map', 'E1M3', MapInfoEntries[I - 1].MapName);
      { tools/testdata/include.wad: MAPINFO only includes MAPINF2, whose
        exitpic / enterpic name intermission scripts. }
      FreeAndNil(W);
      Path := StringReplace(Path, 'mapinfo.wad', 'include.wad', []);
      W := TDoomWad.Create(WadUrl('freedoom1.wad'));
      W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
      LoadMapInfo(W);
      E := MapInfoFor('E1M1');
      AssertTrue('included map', E <> nil);
      AssertEquals('included title', 'Included Hangar', E.LevelName);
      AssertEquals('script background as the exit picture', 'CREDIT', E.ExitPic);
      AssertEquals('enter script', 'TITLEPIC', MapInfoFor('E1M2').EnterPic);
      { A lump including itself stops after 16 includes. }
      List.Clear;
      Errors.Clear;
      AssertTrue('the loop parses', ParseZMapInfo('include "LOOPINF"', List, Errors, W) >= 1);
      AssertTrue('and says so', Pos('too many includes', Errors.Text) > 0);
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

procedure TTestWad.TestLanguage;
var
  W: TDoomWad;
  Path: String;
  Values, Errors: TStringList;
  Strings: TDoomStrings;
  List: TMapInfoList;
  E: TMapInfoEntry;
begin
  Values := TStringList.Create;
  Errors := TStringList.Create;
  try
    { Sections, joined strings, escapes, comments, $ifgame. }
    AssertEquals('strings set', 4, ParseLanguage(
      'A = "no section: default";' + LineEnding +
      '[enu default]' + LineEnding +
      'greeting = "Hello,\n" // joined' + LineEnding +
      '  "world \"quoted\"";' + LineEnding +
      '$ifgame(doom2) D2 = "Doom 2 only";' + LineEnding +
      '$ifgame(hexen) HX = "skipped";' + LineEnding +
      '[de]' + LineEnding +
      'GREETING = "Hallo";' + LineEnding +
      '[default]' + LineEnding +
      'GREETING = "loses to English"; A = "default again";', Values, Errors));
    AssertEquals('joined, escaped, name in upper case', 'Hello,' + #10 + 'world "quoted"', Values.Values['GREETING']);
    AssertEquals('$ifgame(doom2)', 'Doom 2 only', Values.Values['D2']);
    AssertEquals('other game skipped', '', Values.Values['HX']);
    AssertEquals('default replaces default', 'default again', Values.Values['A']);
    AssertEquals('no errors', 0, Errors.Count);
    ParseLanguage('X "missing equals"; Y = "fine"', Values, Errors);
    AssertTrue('error reported', Errors.Count > 0);
    AssertEquals('and parsing goes on', 'fine', Values.Values['Y']);

    { tools/testdata/language.wad: the strings and MAPINFO's lookups. }
    Path := 'tools/testdata/language.wad';
    if not FileExists(Path) then
      Path := '../tools/testdata/language.wad';
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    try
      W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
      Strings := TDoomStrings.Create(W);
      try
        AssertEquals('replaces a BEX string', 'Picked up language shells.', Strings.Get('GOTSHELLS'));
        AssertEquals('English beats [default] and [fr]', 'E1M1: Language Hangar', Strings.Get('LNG_E1M1'));
        AssertEquals('[default] only', 'From the default section', Strings.Get('lng_default_only'));
        AssertEquals('Freedoom''s other strings stay', 'E1M2: Communications Center', Strings.Get('HUSTR_E1M2'));
        List := TMapInfoList.Create(true);
        try
          ParseZMapInfo('map E1M4 "$LNG_E1M1" {}' + LineEnding + 'map E1M5 "$HUSTR_E1M2" {}', List, Errors, nil, Strings);
          AssertEquals('"$NAME" title', 'E1M1: Language Hangar', List[0].LevelName);
          AssertEquals('another map''s BEX title', 'E1M2: Communications Center', List[1].LevelName);
        finally
          FreeAndNil(List);
        end;
      finally
        FreeAndNil(Strings);
      end;
      LoadMapInfo(W);
      E := MapInfoFor('E1M1');
      AssertEquals('lookup title', 'E1M1: Language Hangar', E.LevelName);
      AssertTrue('shown without a label', E.LabelClear);
      AssertEquals('$MUSIC_ names D_ plus the string', 'D_E1M5', E.Music);
      AssertEquals('looked-up exit text', 'The LANGUAGE lump wrote this,' + #10 + 'over two lines.', E.InterText);
      AssertEquals('"$HUSTR_E1M2" on E1M2: its own vanilla title', '', MapInfoFor('E1M2').LevelName);
      E := MapInfoEntries[MapInfoEntries.Count - 1];
      AssertEquals('episode name', 'Language Episode', E.EpisodeName);
      FreeAndNil(W);
      W := TDoomWad.Create(WadUrl('freedoom1.wad'));
      LoadMapInfo(W);
    finally
      FreeAndNil(W);
    end;
  finally
    FreeAndNil(Errors);
    FreeAndNil(Values);
  end;
end;

procedure TTestWad.TestWiScript;
var
  Script: TWiScript;
  Errors: TStringList;
begin
  Errors := TStringList.Create;
  try
    { Doom's own E1: wi_stuff.c's spots and ten looping animations. }
    Script := ParseWiScript(VanillaWiScript(1), Errors);
    try
      AssertEquals('background', 'WIMAP0', Script.Background);
      AssertEquals('spots', 9, Script.SpotNames.Count);
      AssertEquals('E1M2 x', 148, Script.SpotX[Script.SpotIndex('e1m2')]);
      AssertEquals('E1M2 y', 143, Script.SpotY[Script.SpotIndex('E1M2')]);
      AssertEquals('animations', 10, Script.Animations.Count);
      AssertEquals('frames', 'WIA00102', Script.Animations[1].Frames[2]);
      AssertEquals('period', 11, Script.Animations[0].Period);
      AssertEquals('pointer', 'WIURH1', Script.Pointers[1]);
    finally
      FreeAndNil(Script);
    end;
    { E2: level animations shown when entering a map. }
    Script := ParseWiScript(VanillaWiScript(2), Errors);
    try
      AssertEquals('E2 animations', 9, Script.Animations.Count);
      AssertTrue('conditional', Script.Animations[0].Condition = wcEntering);
      AssertEquals('entering', 'E2M2', Script.Animations[0].ConditionMap);
    finally
      FreeAndNil(Script);
    end;
    AssertEquals('no E4 map', '', VanillaWiScript(4));
    AssertEquals('vanilla scripts parse cleanly', 0, Errors.Count);
    { ZDoom's syntax: comments, a Pic, IfLeaving / IfNotVisited, unknown
      words reported. }
    Script := ParseWiScript('// test' + LineEnding + 'Background "INTERPIC"' + LineEnding +
      'Spots { E1M1 10 20 } /* c */ IfLeaving E1M1 Pic 5 6 WIBOX0' + LineEnding +
      'IfNotVisited E1M5 Animation 1 2 3 { A B }' + LineEnding + 'Bogus', Errors);
    try
      AssertEquals('quoted background', 'INTERPIC', Script.Background);
      AssertEquals('one spot', 1, Script.SpotNames.Count);
      AssertTrue('pic leaving', Script.Animations[0].Condition = wcLeaving);
      AssertEquals('pic patch', 'WIBOX0', Script.Animations[0].Frames[0]);
      AssertTrue('not visited', Script.Animations[1].Condition = wcNotVisited);
      AssertEquals('two frames', 2, Script.Animations[1].Frames.Count);
      AssertEquals('unknown word reported', 1, Errors.Count);
    finally
      FreeAndNil(Script);
    end;
  finally
    FreeAndNil(Errors);
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
procedure TTestMap.TestSectorSkies;
var
  W: TDoomWad;
  M: TDoomMap;
  Path: String;
  I, Own: Integer;
begin
  Path := 'tools/testdata/skies.wad';
  if not FileExists(Path) then
    Path := '../tools/testdata/skies.wad';
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    W.AddFile(FilenameToUriSafe(ExpandFileName(Path)));
    M := TDoomMap.Create(W, 'E1M1');
    try
      { One sky sector of 19 tagged by the 271: not the main sky. }
      AssertEquals('own sky', 'SKY3', M.SectorSky[29]);
      AssertFalse('not mirrored', M.SectorSkyFlipped[29]);
      Own := 0;
      for I := 0 to High(M.SectorSky) do
        if M.SectorSky[I] <> '' then Inc(Own);
      AssertEquals('one sector', 1, Own);
      AssertEquals('no main transfer', '', M.SkyTransferTexture);
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(W);
  end;
end;

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


{ DoomDemo's file: the floats come back bit for bit, an update that ran
  no tics is kept only when an action follows it, the end line carries
  the summary, and a second level starts from its own state. }
procedure TTestWad.TestDemoFile;
var
  FileName: String;
  Rec: TDemoRecorder;
  State: TJSONObject;
  Demo: TDemoPlayer;
  E: TDemoEvent;
  Kinds: String;
  NextState: TJSONObject;
const
  Letters: array [TDemoEventKind] of Char = ('T', 'U', 'F', 'R', 'P', 'N', 'W', 'C', 'E', 'X');
var
  Text: String;
begin
  FileName := GetTempFileName('', 'castle-doom-demo');
  State := TJSONObject.Create(['map', 'E1M1', 'skill', 3]);
  try
    Rec := TDemoRecorder.Create(FileName, 777, State);
    try
      Rec.Update(1, [-416.25, 256, 0, 90, -1.5e-7, 41.0, 3.4e38, 0, 0, -1, 0.125, -30]);
      Rec.Update(0, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);  { dropped: no action follows }
      Rec.Update(0, [9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9]);      { kept: the use sees it }
      Rec.Event(deUse);
      Rec.Event(deSelectWeapon, 3);
      Rec.Update(2, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      Rec.Check(35, $DEADBEEF);
      Rec.Event(deNextWeapon, -1);
      Rec.Update(0, [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]);    { dropped at the end }
      Rec.EndLevel(36, $12345678, 'kills 1/2 health 100');
      State.Strings['map'] := 'E1M2';
      Rec.NextLevel(State);
      Rec.Update(3, [7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]);
      Rec.Event(deFire);
      Rec.EndLevel(40, $87654321, 'kills 2/3 health 90');
      AssertFalse('a file recording', Rec.InMemory);
    finally
      FreeAndNil(Rec);
    end;
    { In memory (the browser's): the same lines, cheats among them. }
    Rec := TDemoRecorder.CreateInMemory('castle-config:/last-demo.cdemo', 5, State);
    try
      AssertTrue('in memory', Rec.InMemory);
      Rec.Update(1, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      Rec.Cheat('P', 3001, 250.5);
      Rec.Cheat('K', 0, 0);
      Rec.EndLevel(1, 1, 'kills 0/0');
      Text := Rec.Text;
    finally
      FreeAndNil(Rec);
    end;
  finally
    FreeAndNil(State);
  end;
  AssertTrue('a cheat line', Pos(#10'X P ', Text) > 0);
  Demo := TDemoPlayer.CreateFromText('memory', Text);
  try
    AssertTrue('valid', Demo.Valid);
    AssertEquals('seed from text', 5, Demo.Seed);
    Kinds := '';
    while Demo.Next(E) do
    begin
      Kinds := Kinds + Letters[E.Kind];
      if (E.Kind = deCheat) and (E.Text = 'P') then
        AssertTrue('cheat numbers', (E.Values[0] = 3001) and (E.Values[1] = Single(250.5)));
    end;
    AssertEquals('cheat events', 'TXXE', Kinds);
  finally
    FreeAndNil(Demo);
  end;
  { Not demos: refused without an exception (the web cannot catch one). }
  Demo := TDemoPlayer.CreateFromText('junk', 'junk');
  try
    AssertFalse('junk', Demo.Valid);
    AssertTrue('why', Pos('not a Castle DOOM demo', Demo.Error) > 0);
  finally
    FreeAndNil(Demo);
  end;
  Demo := TDemoPlayer.CreateFromText('no state', 'CASTLEDOOMDEMO 1'#10'seed 1'#10'state [1, 2'#10);
  try
    AssertFalse('no state', Demo.Valid);
  finally
    FreeAndNil(Demo);
  end;
  Demo := TDemoPlayer.Create(FileName);
  try
    AssertEquals('seed', 777, Demo.Seed);
    AssertEquals('state', 'E1M1', Demo.State.Get('map', ''));
    Kinds := '';
    while Demo.Next(E) do
    begin
      Kinds := Kinds + Letters[E.Kind];
      if (E.Kind = deUpdate) and (Length(Kinds) = 1) then
      begin
        AssertEquals('tics', 1, E.Tics);
        AssertTrue('x exact', E.Values[0] = Single(-416.25));
        AssertTrue('tiny exact', E.Values[4] = Single(-1.5e-7));
        AssertTrue('huge exact', E.Values[6] = Single(3.4e38));
        AssertTrue('walk exact', E.Values[11] = Single(-30));
      end;
      if (E.Kind = deUpdate) and (Length(Kinds) = 2) then
        AssertTrue('the kept frame', E.Values[0] = 9);
      if E.Kind = deSelectWeapon then AssertEquals('weapon', 3, E.Arg);
      if E.Kind = deNextWeapon then AssertEquals('delta', -1, E.Arg);
      if E.Kind = deCheck then
        AssertTrue('check', (E.Tics = 35) and (E.Hash = $DEADBEEF));
      if E.Kind = deEnd then
      begin
        AssertTrue('end', (E.Tics = 36) and (E.Hash = $12345678));
        AssertEquals('summary', 'kills 1/2 health 100', E.Text);
      end;
    end;
    AssertEquals('events in order', 'TTUWTCNE', Kinds);
    NextState := Demo.NextLevelState;
    try
      AssertTrue('the next level', (NextState <> nil) and (NextState.Get('map', '') = 'E1M2'));
    finally
      FreeAndNil(NextState);
    end;
    Kinds := '';
    while Demo.Next(E) do
      Kinds := Kinds + Letters[E.Kind];
    AssertEquals('the next level''s events', 'TFE', Kinds);
    AssertTrue('no third level', Demo.NextLevelState = nil);
    AssertTrue('at the end', Demo.AtEnd);
  finally
    FreeAndNil(Demo);
    DeleteFile(FileName);
  end;
end;

{ Demo format 2: "=" for the values of the update before, the unchanged
  ones at the end left out, saved states as CompactJSON (exact floats in
  few digits, arrays of objects as key tables) expanded back exactly;
  format 1 still reads; ReadGhostTracks gives each level's path and its
  finish (an "exit" end or a next level). }
procedure TTestWad.TestDemoCompact;
const
  V1Text = 'CASTLEDOOMDEMO 1'#10'seed 3'#10'state {"map":"E1M1","tic":0}'#10 +
    'T 2 3F800000 40000000 40400000 40800000 40A00000 40C00000 40E00000 41000000 41100000 41200000 41300000 41400000'#10 +
    'E 2 00000001 kills 0/0'#10;
var
  Rec: TDemoRecorder;
  State, Orig: TJSONObject;
  Expanded: TJSONData;
  Demo: TDemoPlayer;
  E: TDemoEvent;
  Text, Compact: String;
  Lines: TStringList;
  Tracks: TGhostTracks;
  Track: TGhostTrack;
  I: Integer;
begin
  { Exact floats and key tables. }
  Orig := TJSONObject(GetJSON('{"map":"E1M1","tic":7,"f":[0.1,-0.0,1e-7,123456789.0,0.5,1.0,3.4e38],' +
    '"actors":[{"type":1,"x":0.25,"v":[0.0,0.0]},{"type":2,"x":-3.0,"v":[1.5,0.0]},{"type":3,"extra":true}],' +
    '"one":[{"a":1}],"names":["A","B"],"empty":[],"o":{"k":null}}'));
  try
    Compact := CompactJSON(Orig);
    AssertTrue('shorter: ' + Compact, Length(Compact) < Length(Orig.AsJSON) div 2);
    AssertTrue('a key table', Pos('"#keys":[["type","x","v"],["type","extra"]]', Compact) > 0);
    AssertTrue('few digits: ' + Compact, Pos('[0.1,-0.0,1E-7,', Compact) > 0);
    Expanded := GetJSON(Compact);
    try
      State := TJSONObject(ExpandJSON(Expanded));
      try
        AssertEquals('expanded back', Orig.AsJSON, State.AsJSON);
        AssertTrue('a float stays a float', State.Arrays['f'].Items[5] is TJSONFloatNumber);
      finally
        FreeAndNil(State);
      end;
    finally
      FreeAndNil(Expanded);
    end;
  finally
    FreeAndNil(Orig);
  end;

  { "=" and trailing values left out; a ghost of two levels. }
  State := TJSONObject.Create(['map', 'E1M1', 'tic', 10]);
  try
    Rec := TDemoRecorder.CreateInMemory('memory', 1, State);
    try
      Rec.Update(1, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      Rec.Update(2, [1, 2.5, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      Rec.Update(1, [1, 2.5, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
      Rec.Update(1, [1, 2.5, 3, 4, 5, 6, 7, 8, 9, 10, 11, -12]);
      Rec.EndLevel(15, 1, 'kills 0/0 exit');
      State.Strings['map'] := 'E1M2';
      State.Integers['tic'] := 0;
      Rec.NextLevel(State);
      Rec.Update(3, [1, 2.5, 3, 4, 5, 6, 7, 8, 9, 10, 11, -12]);
      Rec.Update(3, [8, 2.5, 3, 4, 5, 6, 7, 8, 9, 10, 11, -12]);
      Rec.EndLevel(6, 1, 'kills 0/0');
      Text := Rec.Text;
    finally
      FreeAndNil(Rec);
    end;
  finally
    FreeAndNil(State);
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    AssertEquals('format 2', 'CASTLEDOOMDEMO 2', Lines[0]);
    AssertEquals('only the change', 'T 2 = 40200000', Lines[4]);
    AssertEquals('nothing changed', 'T 1', Lines[5]);
    AssertEquals('the last value', 'T 1 = = = = = = = = = = = C1400000', Lines[6]);
    AssertEquals('a level starts whole', 'T 3 3F800000 40200000 40400000 40800000 40A00000 40C00000 40E00000 ' +
      '41000000 41100000 41200000 41300000 C1400000', Lines[9]);
  finally
    FreeAndNil(Lines);
  end;
  Demo := TDemoPlayer.CreateFromText('memory', Text);
  try
    AssertTrue('valid', Demo.Valid);
    I := 0;
    while Demo.Next(E) do
      if E.Kind = deUpdate then
      begin
        Inc(I);
        AssertTrue('filled in', (E.Values[0] = 1) and (E.Values[2] = 3) and (E.Values[10] = 11));
        if I >= 2 then AssertTrue('y kept', E.Values[1] = 2.5);
        if I = 3 then AssertTrue('walk kept', E.Values[11] = 12);
        if I = 4 then AssertTrue('walk changed', E.Values[11] = -12);
      end;
    AssertEquals('updates', 4, I);
  finally
    FreeAndNil(Demo);
  end;
  Demo := TDemoPlayer.CreateFromText('memory', Text);
  try
    Tracks := ReadGhostTracks(Demo);
  finally
    FreeAndNil(Demo);
  end;
  AssertEquals('two levels', 2, Length(Tracks));
  AssertTrue('E1M1', FindGhostTrack(Tracks, 'e1m1', Track));
  AssertEquals('points', 4, Length(Track.Points));
  AssertEquals('from the state''s tic', 10, Track.Points[0].Tic);
  AssertEquals('tics add up', 14, Track.Points[3].Tic);
  AssertEquals('finished', 15, Track.FinishTic);
  AssertTrue('E1M2', FindGhostTrack(Tracks, 'E1M2', Track));
  AssertEquals('not finished', -1, Track.FinishTic);
  AssertTrue('its x', (Track.Points[1].X = 8) and (Track.Points[1].Tic = 3));
  AssertFalse('no E1M3', FindGhostTrack(Tracks, 'E1M3', Track));

  { Format 1 (every value, no "exit"). }
  Demo := TDemoPlayer.CreateFromText('v1', V1Text);
  try
    AssertTrue('format 1', Demo.Valid);
    AssertTrue('an update', Demo.Next(E) and (E.Kind = deUpdate));
    AssertTrue('its values', (E.Values[0] = 1) and (E.Values[11] = 12));
  finally
    FreeAndNil(Demo);
  end;
end;

{ DoomRandomMap: random:/SEED makes eight maps (E1M1..E1M8 over Phase 1,
  MAP01..MAP08 over Phase 2) that load with their own BSP: the subsector
  polygons cover the whole rectangle, every thing and the exit switch can
  be walked to from the player start (floor steps of 24 at most, 56 units
  of headroom, doors opened, stairs climbed, secret closets entered), the
  locked door cuts the exit off while its
  key stays reachable, the same seed gives the same bytes and UMAPINFO
  names the maps. }
procedure TTestMap.TestRandomMaps;

  procedure CheckMaps(const Iwad: String; const IsDoom2: Boolean);
  var
    W: TDoomWad;
    M: TDoomMap;
    I, J, K, Start, Exits, Starts, ExitSector, Locked, DoorLines, SecretSectors, Risers: Integer;
    Area, A: Double;
    All, Unlocked: TBooleanArray;
    Ceil: array of Single;
    IsLocked: array of Boolean;

    { Sectors reachable from Start walking (steps of 24 at most, 56 of
      headroom), through doors as opened (their lowest neighbouring
      ceiling - 4), locked ones only when WithKeys. }
    function Reach(const WithKeys: Boolean): TBooleanArray;
    var
      L, Sec, Other: Integer;
      Changed: Boolean;
      Line: TDoomLinedef;
    begin
      SetLength(Result, Length(M.Sectors));
      for L := 0 to High(Result) do Result[L] := L = Start;
      repeat
        Changed := false;
        for L := 0 to High(M.Linedefs) do
        begin
          Line := M.Linedefs[L];
          if (Line.BackSector < 0) or (Result[Line.FrontSector] = Result[Line.BackSector]) then Continue;
          if Result[Line.FrontSector] then
          begin
            Sec := Line.FrontSector;
            Other := Line.BackSector;
          end else
          begin
            Sec := Line.BackSector;
            Other := Line.FrontSector;
          end;
          if IsLocked[Other] and not WithKeys then Continue;
          if (M.Sectors[Other].FloorHeight - M.Sectors[Sec].FloorHeight <= 24) and
             (Min(Ceil[Sec], Ceil[Other]) - Max(M.Sectors[Sec].FloorHeight, M.Sectors[Other].FloorHeight) >= 56) then
          begin
            Result[Other] := true;
            Changed := true;
          end;
        end;
      until not Changed;
    end;

  begin
    Locked := 0;
    DoorLines := 0;
    SecretSectors := 0;
    Risers := 0;
    W := TDoomWad.Create(WadUrl(Iwad));
    try
      W.AddFile('random:/1234');
      AssertTrue('described', Pos('random maps 1234', W.Description) > 0);
      for I := 1 to RandomMapCount do
      begin
        AssertTrue('map listed', W.MapNames.IndexOf(RandomMapName(I, IsDoom2)) >= 0);
        M := TDoomMap.Create(W, RandomMapName(I, IsDoom2));
        try
          Area := 0;
          for J := 0 to High(M.Subsectors) do
          begin
            A := 0;
            for K := 0 to High(M.Subsectors[J].Poly) do
              A := A + M.Subsectors[J].Poly[K].X * M.Subsectors[J].Poly[(K + 1) mod Length(M.Subsectors[J].Poly)].Y -
                M.Subsectors[J].Poly[(K + 1) mod Length(M.Subsectors[J].Poly)].X * M.Subsectors[J].Poly[K].Y;
            Area := Area + A / 2;
          end;
          AssertEquals('polygons cover the map', (M.MaxX - M.MinX) * (M.MaxY - M.MinY), Area, 1);
          CheckLineGrid(M);
          { Doors: sectors behind door lines, opened like Doom does. }
          SetLength(Ceil, Length(M.Sectors));
          SetLength(IsLocked, Length(M.Sectors));
          for J := 0 to High(M.Sectors) do
          begin
            Ceil[J] := M.Sectors[J].CeilingHeight;
            IsLocked[J] := false;
          end;
          for J := 0 to High(M.Linedefs) do
            if (M.Linedefs[J].Special in [1, 26, 27, 28]) and (M.Linedefs[J].BackSector >= 0) then
            begin
              Inc(DoorLines);
              K := M.Linedefs[J].BackSector;
              Ceil[K] := M.LowestCeilingSurrounding(K) - 4;
              if M.Linedefs[J].Special <> 1 then IsLocked[K] := true;
            end;
          Start := -1;
          Starts := 0;
          for J := 0 to High(M.Things) do
            if M.Things[J].TypeNum = 1 then
            begin
              Start := M.SectorAt(M.Things[J].X, M.Things[J].Y);
              Inc(Starts);
            end;
          AssertEquals('one player start', 1, Starts);
          for J := 0 to High(M.Sectors) do
            if M.Sectors[J].Special = 9 then Inc(SecretSectors);
          for J := 0 to High(M.Sidedefs) do
            if Copy(M.Sidedefs[J].LowerTex, 1, 4) = 'STEP' then Inc(Risers);
          All := Reach(true);
          Unlocked := Reach(false);
          for J := 0 to High(M.Things) do
            AssertTrue(Format('%s: thing %d (type %d) reachable', [M.Name, J, M.Things[J].TypeNum]),
              All[M.SectorAt(M.Things[J].X, M.Things[J].Y)]);
          Exits := 0;
          ExitSector := -1;
          for J := 0 to High(M.Linedefs) do
            if M.Linedefs[J].Special = 11 then
            begin
              Inc(Exits);
              ExitSector := M.Linedefs[J].FrontSector;
            end;
          AssertEquals('one exit switch', 1, Exits);
          AssertTrue('exit reachable', All[ExitSector]);
          for J := 0 to High(IsLocked) do
            if IsLocked[J] then
            begin
              Inc(Locked);
              AssertFalse(M.Name + ': the locked door guards the exit', Unlocked[ExitSector]);
              for K := 0 to High(M.Things) do
                if M.Things[K].TypeNum in [5, 6, 13] then
                  AssertTrue(M.Name + ': the key is before the door', Unlocked[M.SectorAt(M.Things[K].X, M.Things[K].Y)]);
              Break;
            end;
        finally
          FreeAndNil(M);
        end;
      end;
      { Locked doors from map 2 on (when no loop goes around every
        opening on the way), plain doors everywhere. }
      AssertTrue('locked doors on most maps', Locked >= RandomMapCount div 2);
      AssertTrue('doors', DoorLines >= 2 * RandomMapCount);
      { A secret closet on every map, stairs on some. }
      AssertTrue('secrets', SecretSectors >= RandomMapCount);
      AssertTrue('stairs', Risers > 0);
      LoadMapInfo(W);
      AssertTrue('UMAPINFO names the maps', (MapInfoFor(RandomMapName(1, IsDoom2)) <> nil) and
        (MapInfoFor(RandomMapName(1, IsDoom2)).LevelName <> ''));
    finally
      FreeAndNil(W);
    end;
  end;

  function WadBytes(const Seed: String): TBytes;
  var
    W: TDoomWad;
    D: TMemoryStream;
  begin
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    try
      W.AddFile('random:/' + Seed);
      D := W.FileData(1);
      SetLength(Result, D.Size);
      Move(D.Memory^, Result[0], D.Size);
    finally
      FreeAndNil(W);
    end;
  end;

var
  A, B, C: TBytes;
  W: TDoomWad;
begin
  CheckMaps('freedoom1.wad', false);
  CheckMaps('freedoom2.wad', true);
  A := WadBytes('77');
  B := WadBytes('77');
  C := WadBytes('78');
  AssertEquals('same size for the same seed', Length(A), Length(B));
  AssertTrue('same bytes for the same seed', CompareMem(@A[0], @B[0], Length(A)));
  AssertTrue('another seed, other maps', (Length(A) <> Length(C)) or not CompareMem(@A[0], @C[0], Length(A)));
  { The map entries are global: back to plain Freedoom. }
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  try
    LoadMapInfo(W);
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

{ GameSettings' best times: one per WADs, map and skill, replaced. }
procedure TTestGamepad.TestBestTimes;
var
  K1, K2: String;
begin
  SetLength(Settings.BestTimeKeys, 0);
  SetLength(Settings.BestTimes, 0);
  K1 := BestTimeKey('freedoom1.wad', 'e1m1', 2);
  K2 := BestTimeKey('freedoom1.wad + random maps 42', 'E1M1', 2);
  AssertEquals('key', 'freedoom1.wad E1M1 skill 3', K1);
  AssertEquals('none yet', -1, BestTime(K1));
  SetBestTime(K1, 95);
  SetBestTime(K2, 40);
  SetBestTime(K1, 61);
  AssertEquals('replaced', 61, BestTime(K1));
  AssertEquals('other WADs', 40, BestTime(K2));
  AssertEquals('two entries', 2, Length(Settings.BestTimeKeys));
  AssertEquals('the statistics key', 'L', KeyToStr(DefaultKeys[gaStats, 0]));
end;

{ Gamma correction: the exponent per level, sent to the effects made
  before and after a change, and the F11 default. }
procedure TTestGamepad.TestGamma;
var
  L: TDoomLighting;
  E1, E2: TEffectNode;
begin
  L := TDoomLighting.Create;
  try
    AssertEquals('off', 1.0, L.GammaExponent, 1e-6);
    E1 := L.GeometryEffect;
    AssertEquals('field off', 1.0, (E1.Field('doom_gamma') as TSFFloat).Value, 1e-6);
    L.Gamma := 2;
    AssertEquals('level 2', 0.625, L.GammaExponent, 1e-6);
    AssertEquals('sent', 0.625, (E1.Field('doom_gamma') as TSFFloat).Value, 1e-6);
    E2 := L.GeometryEffect;
    AssertEquals('new effect', 0.625, (E2.Field('doom_gamma') as TSFFloat).Value, 1e-6);
    L.Gamma := MaxGamma;
    AssertEquals('level 4', 1 / 2.2, L.GammaExponent, 1e-6);
    FreeAndNil(E1);
    FreeAndNil(E2);
  finally
    FreeAndNil(L);
  end;
  AssertEquals('the gamma key', 'F11', KeyToStr(DefaultKeys[gaGamma, 0]));
end;

{ Closed captions: lump and monster captions, directions and the list. }
procedure TTestGamepad.TestCaptions;
var
  L: TCaptionList;
  Key, Name: String;
begin
  AssertEquals('door', 'Door opens', CaptionForLump('dsdoropn', false));
  AssertEquals('door without a position', '', CaptionForLump('DSDOROPN', true));
  AssertEquals('boss everywhere', 'Icon of Sin roars', CaptionForLump('DSBOSSIT', true));
  AssertEquals('player pain', '', CaptionForLump('DSPLPAIN', true));
  AssertTrue('imp', MonsterNameKey(3001, Key, Name));
  AssertEquals('imp key', 'CC_IMP', Key);
  AssertFalse('no monster', MonsterNameKey(2001, Key, Name));
  AssertTrue('pain slot', CaptionSlot('DSPOPAIN', 'DSPOSIT1', 'DSPISTOL', 'DSPOPAIN', 'DSPODTH1') = csPain);
  AssertTrue('other slot', CaptionSlot('DSPOSACT', 'DSPOSIT1', 'DSPISTOL', 'DSPOPAIN', 'DSPODTH1') = csOther);
  AssertEquals('death', 'Serpentipede dies', MonsterCaption('serpentipede', csDeath));
  AssertEquals('vanilla name', 'Imp sees you', MonsterCaption('IMP', csSee));
  AssertEquals('no caption', '', MonsterCaption('Imp', csOther));
  { The player at the origin facing north (90). }
  AssertEquals('ahead', 'ahead', CaptionDirection(0, 0, 90, 10, 500));
  AssertEquals('left', 'left', CaptionDirection(0, 0, 90, -500, 0));
  AssertEquals('right', 'right', CaptionDirection(0, 0, 90, 500, 30));
  AssertEquals('behind', 'behind', CaptionDirection(0, 0, 90, 0, -500));
  AssertEquals('wrapped angle', 'left', CaptionDirection(0, 0, 350, 0, 500));
  AssertEquals('nearby', '', CaptionDirection(0, 0, 90, 20, 20));
  L := TCaptionList.Create;
  try
    L.Add('Door opens', 'ahead', 10);
    L.Add('Imp sees you', 'left', 12);
    L.Add('Door opens', 'right', 20);
    AssertEquals('moved down', 'Imp sees you, left'#10'Door opens, right', L.Text(20));
    L.Add('A', '', 21);
    L.Add('B', '', 22);
    AssertEquals('three kept', 'Door opens, right'#10'A'#10'B', L.Text(22));
    AssertEquals('expired', 'A'#10'B', L.Text(20 + CaptionTics));
    AssertEquals('all expired', '', L.Text(22 + CaptionTics));
  finally
    FreeAndNil(L);
  end;
end;

{ Dynamic lights: the sprite table and the slots sent to the effects. }
procedure TTestGamepad.TestDynamicLights;
var
  L: TDoomLighting;
  E: TEffectNode;
  Radius, Height: Single;
  Color: TVector3;
  Lights: array [0..9] of TDynamicLight;
  I: Integer;
  View: TMatrix4;
begin
  AssertTrue('rocket', SpriteDynamicLight('MISL', Radius, Color));
  AssertEquals('rocket radius', 256, Radius, 0.01);
  AssertTrue('plasma', SpriteDynamicLight('PLSS', Radius, Color));
  AssertTrue('plasma is blue', Color.Z > Color.X);
  AssertFalse('a puff has none', SpriteDynamicLight('PUFF', Radius, Color));
  AssertTrue('floor lamp', LampDynamicLight('COLU', Radius, Height, Color));
  AssertTrue('lamp height', Height > 0);
  AssertTrue('red torch is red', LampDynamicLight('TRED', Radius, Height, Color) and (Color.X > Color.Z));
  AssertFalse('a tree is no lamp', LampDynamicLight('TRE2', Radius, Height, Color));
  L := TDoomLighting.Create;
  try
    E := L.GeometryEffect;
    AssertEquals('none at first', 0, (E.Field('doom_dlight_count') as TSFFloat).Value, 1e-6);
    AssertEquals('eight slots', MaxDynamicLights, (E.Field('doom_dlights') as TMFVec4f).Items.Count);
    for I := 0 to High(Lights) do
    begin
      Lights[I].Position := Vector3(I, 0, -100 * I);
      Lights[I].Radius := 100 + I;
      Lights[I].Color := Vector3(1, 0.5, 0);
    end;
    View := TranslationMatrix(Vector3(0, 0, -5));
    { Ten given, eight kept. }
    L.SetDynamicLights(Lights, View);
    AssertEquals('eight lights', MaxDynamicLights, L.DynamicLightCount);
    AssertEquals('count sent', MaxDynamicLights, (E.Field('doom_dlight_count') as TSFFloat).Value, 1e-6);
    AssertEquals('slot 2 position', -200, (E.Field('doom_dlights') as TMFVec4f).Items[2].Z, 1e-6);
    AssertEquals('slot 7 radius', 107, (E.Field('doom_dlights') as TMFVec4f).Items[7].W, 1e-6);
    AssertEquals('slot 1 colour', 0.5, (E.Field('doom_dlight_colors') as TMFVec3f).Items[1].Y, 1e-6);
    AssertEquals('view sent', -5, (E.Field('doom_view') as TSFMatrix4f).Value.Data[3, 2], 1e-6);
    L.SetDynamicLights(Slice(Lights, 1), View);
    AssertEquals('one left', 1, L.DynamicLightCount);
    AssertEquals('slot 1 off', 0, (E.Field('doom_dlights') as TMFVec4f).Items[1].W, 1e-6);
    FreeAndNil(E);
    { A new effect starts with the lights on now. }
    E := L.GeometryEffect;
    AssertEquals('new effect', 100, (E.Field('doom_dlights') as TMFVec4f).Items[0].W, 1e-6);
    AssertEquals('new effect count', 1, (E.Field('doom_dlight_count') as TSFFloat).Value, 1e-6);
    FreeAndNil(E);
  finally
    FreeAndNil(L);
  end;
end;

procedure TTestGamepad.MenuAction(const Action: TDoomMenuAction);
begin
  if Action = maCustom then
    FMenuRequests := FMenuRequests + Format('%s %d;', [FMenu.CustomItem, FMenu.CustomDelta]);
end;

{ The custom game page without a WAD: its rows ask the view (OnAction),
  the skill and the random seed are its own. }
procedure TTestGamepad.TestCustomGamePage;

  procedure Key(const K: TKey; const S: String = '');
  begin
    FMenu.HandleKey(InputKey(TVector2.Zero, K, S, []));
  end;

begin
  FMenu := TDoomMenuScreen.Create(nil);
  try
    FMenu.OnAction := {$ifdef FPC}@{$endif} MenuAction;
    FMenuRequests := '';
    FMenu.SetMenuActive(true);
    FMenu.OpenPage(mpCustom);
    Key(keyArrowRight);                       { GAME: the next IWAD }
    Key(keyArrowDown);
    Key(keyArrowLeft);                        { PWADS: clear }
    Key(keyEnter);                            { PWADS: add one }
    Key(keyArrowDown);
    Key(keyArrowLeft);                        { RECENT: the one before }
    Key(keyArrowDown);
    Key(keyArrowLeft);                        { MAP: the previous one }
    Key(keyArrowDown);
    Key(keyArrowLeft);                        { SKILL 3 -> 2 }
    AssertEquals('skill', 1, FMenu.Skill);
    Key(keyArrowDown);
    Key(keyEnter);                            { RANDOM SEED: type }
    Key(keyNone, '4');
    Key(keyNone, 'x');                        { not a digit }
    Key(keyNone, '2');
    Key(keyEnter);
    AssertEquals('seed', '42', FMenu.CustomSeed);
    Key(keyArrowLeft);
    AssertEquals('seed cleared', '', FMenu.CustomSeed);
    Key(keyArrowDown);                        { over the blank row to START }
    Key(keyEnter);
    Key(keyArrowDown);                        { EDIT MAP: the map editor }
    Key(keyEnter);
    AssertEquals('requests', 'GAME 1;CLEAR 0;PWADS 0;RECENT -1;MAP -1;START 0;EDIT 0;', FMenuRequests);
    { The PWADs page: order, remove, add, back. }
    FMenuRequests := '';
    FMenu.CustomPwadNames.Add('a.wad');
    FMenu.CustomPwadNames.Add('b.wad');
    FMenu.OpenPage(mpPwads);
    Key(keyArrowDown);
    Key(keyArrowLeft);                        { b.wad earlier }
    AssertEquals('index', 1, FMenu.CustomIndex);
    Key(keyArrowUp);
    Key(keyEnter);                            { a.wad removed }
    AssertEquals('index removed', 0, FMenu.CustomIndex);
    Key(keyArrowDown);
    Key(keyArrowDown);
    Key(keyEnter);                            { ADD PWAD... }
    Key(keyArrowDown);
    Key(keyEnter);                            { STORED FILES... }
    { The stored files page (the view fills it): add, forget, back. }
    FMenu.StoredNames.Add('boom.wad  1 KB');
    FMenu.StoredNames.Add('x.wad  9 KB');
    FMenu.OpenPage(mpStored);
    Key(keyArrowDown);
    Key(keyEnter);                            { x.wad added as a PWAD }
    AssertEquals('stored index', 1, FMenu.CustomIndex);
    Key(keyArrowUp);
    Key(keyDelete);                           { boom.wad forgotten }
    AssertEquals('stored index forgotten', 0, FMenu.CustomIndex);
    Key(keyEscape);                           { back: the view reopens the PWADs page }
    AssertEquals('PWADs and stored pages requests',
      'PWADMOVE -1;PWADREMOVE 0;PWADADD 0;STORED 0;STOREDADD 0;STOREDFORGET 0;PWADS 0;', FMenuRequests);
    FMenuRequests := '';
    FMenu.OpenPage(mpPwads);
    Key(keyEscape);
    AssertTrue('back to the custom page', FMenu.Page = mpCustom);
    AssertEquals('PWADs page back', 'OPEN 0;', FMenuRequests);
    Key(keyArrowDown);                        { from EDIT MAP round to GAME }
    Key(keyEnter);                            { GAME: open an IWAD file }
    AssertEquals('open IWAD', 'OPENIWAD 0;', Copy(FMenuRequests, Length(FMenuRequests) - 10, MaxInt));
    Key(keyEscape);
    { Back to the episodes, or (no WAD set up) the main page. }
    AssertTrue('back', FMenu.Page = mpMain);
  finally
    FreeAndNil(FMenu);
  end;
end;

{ TTestGamepad }

procedure TTestGamepad.TestPadBindings;
var
  Event: TInputPressRelease;
begin
  ResetPad;
  AssertTrue('RT fires', PadIs(pbRightTrigger, gpaFire));
  AssertTrue('X uses', PadIs(pbX, gpaUse));
  AssertTrue('Y: photo mode', PadIs(pbY, gpaPhoto));
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

procedure TTestGamepad.TestKeyBindings;
var
  A: TGameAction;
begin
  ResetKeys;
  AssertTrue('1: fist', KeyIs(key1, gaWeapon1));
  AssertTrue('F: light diminishing', KeyIs(keyF, gaLightDiminish));
  AssertTrue('O: photo mode', KeyIs(keyO, gaPhoto));
  AssertTrue('F6: quick save', KeyIs(keyF6, gaQuickSave));
  AssertEquals('next weapon unbound', '-', ActionKeysText(gaNextWeapon));
  { A key moves from the action that had it. }
  AssertTrue('bound', BindKey(gaStrafeLeft, 1, keyF));
  AssertFalse('F left light diminishing', KeyIs(keyF, gaLightDiminish));
  AssertTrue('F strafes', KeyIs(keyF, gaStrafeLeft));
  AssertFalse('F2 stays the save menu''s', BindKey(gaFire, 0, keyF2));
  AssertFalse('F8 stays the inspector''s', BindKey(gaFire, 0, keyF8));
  AssertTrue('F10 binds', BindKey(gaQuickSave, 1, keyF10));
  { Settings from before the weapon and hotkey actions: their own keys
    win over the new actions' defaults. }
  ResetKeys;
  ApplyKeysJson('{"strafeLeft": ["A", "F"], "fire": ["Ctrl", "1"]}');
  AssertTrue('stored F strafes', KeyIs(keyF, gaStrafeLeft));
  AssertEquals('light diminishing lost F', '-', ActionKeysText(gaLightDiminish));
  AssertEquals('fist lost 1', '-', ActionKeysText(gaWeapon1));
  AssertTrue('2 still the pistol', KeyIs(key2, gaWeapon2));
  { Every action has a JSON name and a Controls page. }
  for A := Low(TGameAction) to High(TGameAction) do
  begin
    AssertTrue('id', ActionIds[A] <> '');
    AssertTrue('on a page', (A <= ControlsPageLast[0]) or
      ((A >= ControlsPageFirst[1]) and (A <= ControlsPageLast[1])) or
      ((A >= ControlsPageFirst[2]) and (A <= ControlsPageLast[2])));
  end;
  AssertTrue('pages cover all', ControlsPageLast[ControlsPageCount - 1] = High(TGameAction));
  ResetKeys;
  { Mouse: the left button fires, the wheel changes weapons; a button
    moves from the action that had it; events find their action. }
  ResetMouse;
  AssertTrue('left fires', MouseIs(mbLeft, gaFire));
  AssertTrue('wheel up: next weapon',
    EventIs(InputMouseWheel(TVector2.Zero, 1, true, []), gaNextWeapon));
  AssertTrue('wheel down: previous weapon',
    EventIs(InputMouseWheel(TVector2.Zero, -1, true, []), gaPrevWeapon));
  AssertEquals('fire text', 'Ctrl / Left button', ActionInputText(gaFire));
  BindMouse(gaUse, mbLeft);
  AssertFalse('left no longer fires', EventIs(InputMouseButton(TVector2.Zero, buttonLeft, 0, []), gaFire));
  AssertTrue('left uses', EventIs(InputMouseButton(TVector2.Zero, buttonLeft, 0, []), gaUse));
  AssertTrue('names', StrToMouseBind('button4') = mbButton4);
  AssertTrue('a key event is no mouse binding', MouseBindOfEvent(InputKey(TVector2.Zero, keyA, 'a', [])) = mbNone);
  ResetMouse;
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
    { Left-handed at 125%: fire on the left, larger; "<" still left of
      ">"; MENU stays at the top right; the stick takes the right side. }
    T.LeftHanded := true;
    T.SizePercent := 125;
    T.ButtonCircle(tbFire, Middle, Radius);
    AssertEquals('fire on the left', 0.17 * 1125, Middle.X, 0.01);
    AssertEquals('fire larger', 0.12 * 1125, Radius, 0.01);
    T.ButtonCircle(tbPrevWeapon, Middle, Radius);
    V := Middle;
    T.ButtonCircle(tbNextWeapon, Middle, Radius);
    AssertTrue('< left of >', V.X < Middle.X);
    T.ButtonCircle(tbMenu, Middle, Radius);
    AssertTrue('menu at the right', Middle.X > 1400);
    V := Middle;
    T.ButtonCircle(tbPhoto, Middle, Radius);
    AssertTrue('photo at the right too, left of menu', (Middle.X > 1000) and (Middle.X < V.X));
    T.TouchDown(5, Vector2(1300, 400));
    T.TouchMove(5, Vector2(1300, 500));
    AssertTrue('stick on the right', T.MoveVector.Y > 0.5);
    T.TouchUp(5);
    T.TouchDown(6, Vector2(500, 400));
    T.TouchMove(6, Vector2(500, 500));
    AssertEquals('the left drags the view', 0, T.MoveVector.Length, 0.0001);
    T.ReleaseAll;
    { A place of one's own (fractions of the size) wins over the mirrored
      default; in editing a finger drags a button instead of pressing it. }
    T.LeftHanded := false;
    T.SizePercent := 100;
    T.SetButtonPlace(tbUse, Vector2(0.5, 0.25));
    T.ButtonCircle(tbUse, Middle, Radius);
    AssertEquals('own place x', 800, Middle.X, 0.01);
    AssertEquals('own place y', 225, Middle.Y, 0.01);
    T.Editing := true;
    T.ButtonCircle(tbFire, Middle, Radius);
    T.TouchDown(8, Middle);
    AssertFalse('no fire while editing', T.FireHeld);
    T.TouchMove(8, Vector2(400, 450));
    T.TouchUp(8);
    AssertEquals('dragged x', 0.25, T.ButtonPlace(tbFire).X, 0.001);
    AssertEquals('dragged y', 0.5, T.ButtonPlace(tbFire).Y, 0.001);
    T.Editing := false;
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

{ TTestEditor }

procedure TTestEditor.CountTriangles(Node: TX3DNode);
begin
  Inc(FTriangles, TIndexedTriangleSetNode(Node).FdIndex.Count div 3);
end;

procedure TTestEditor.CountShape(Node: TX3DNode);
begin
  Inc(FShapes);
end;

{ A map through the editor (DoomEditMap) and back: its PWAD, with the
  BSP of DoomNodeBuilder, loads like the original (the same lines,
  sectors and things, subsector polygons covering the same area, the
  same sector at sample points). }
procedure TTestEditor.CheckEditRoundTrip(const IwadName, MapName: String; const Tolerance: Double);
var
  W, W2: TDoomWad;
  E: TDoomEditMap;
  M, M2: TDoomMap;
  Error: String;
  Data: TMemoryStream;
  I, Same, Tested, S1, S2: Integer;
  X, Y: Single;
begin
  Error := '';
  W := TDoomWad.Create(WadUrl(IwadName));
  E := TDoomEditMap.Create;
  try
    AssertTrue('imported: ' + Error, E.LoadFromWad(W, MapName, Error));
    M := TDoomMap.Create(W, MapName);
    try
      AssertEquals('lines', Length(M.Linedefs), Length(E.Lines));
      AssertEquals('sectors', Length(M.Sectors), Length(E.Sectors));
      AssertEquals('things', Length(M.Things), Length(E.Things));
      Data := E.SaveToWad;
      try
        RegisterEditedWad(MapName, Data);
      finally
        FreeAndNil(Data);
      end;
      W2 := TDoomWad.Create(WadUrl(IwadName));
      try
        W2.AddFile(EditedWadUrl(MapName));
        AssertTrue('described', Pos('edited ' + MapName, W2.Description) > 0);
        M2 := TDoomMap.Create(W2, MapName);
        try
          AssertEquals('nodes format', 'VANILLA', M2.NodesFormat);
          AssertEquals('lines back', Length(M.Linedefs), Length(M2.Linedefs));
          AssertEquals('sides back', Length(M.Sidedefs), Length(M2.Sidedefs));
          AssertEquals('things back', Length(M.Things), Length(M2.Things));
          AssertEquals('polygon area', PolygonArea(M), PolygonArea(M2), PolygonArea(M) * Tolerance);
          for I := 0 to High(M2.Subsectors) do
            AssertTrue('subsector sector', M2.Subsectors[I].Sector >= 0);
          RandSeed := 11;
          Same := 0;
          Tested := 0;
          for I := 1 to 3000 do
          begin
            X := M.MinX + Random * (M.MaxX - M.MinX);
            Y := M.MinY + Random * (M.MaxY - M.MinY);
            { Outside the map any BSP answers something else. }
            if E.SectorAt(X, Y) < 0 then Continue;
            S1 := M.SectorAt(X, Y);
            S2 := M2.SectorAt(X, Y);
            Inc(Tested);
            if S1 = S2 then Inc(Same);
          end;
          AssertTrue(Format('same sectors at %d of %d points', [Same, Tested]), Same >= Tested * 0.995);
          { The editor's own lookup agrees too (inside the map). }
          AssertEquals('editor sector at the start', M.SectorAt(M.Things[0].X + 1, M.Things[0].Y + 1),
            E.SectorAt(M.Things[0].X + 1, M.Things[0].Y + 1));
        finally
          FreeAndNil(M2);
        end;
        W2.RemoveLastFile;
        AssertEquals('removed', 1, W2.FileUrls.Count);
      finally
        FreeAndNil(W2);
      end;
    finally
      FreeAndNil(M);
    end;
  finally
    FreeAndNil(E);
    FreeAndNil(W);
  end;
end;

{ E1M1's geometry as glTF and X3D (DoomExport), read back by CGE: the
  same triangles in both, a texture per material. }
procedure TTestEditor.TestSceneExport;
var
  W: TDoomWad;
  G: TDoomGraphics;
  M: TDoomMap;
  Error, Dir: String;
  Gltf, X3d: TX3DRootNode;

begin
  Error := '';
  Dir := GetTempDir + 'castle-doom-export-test';
  ForceDirectories(Dir);
  W := TDoomWad.Create(WadUrl('freedoom1.wad'));
  G := TDoomGraphics.Create(W);
  M := TDoomMap.Create(W, 'E1M1');
  try
    AssertTrue('glTF: ' + Error, ExportMapGeometry(M, G, Dir + '/e1m1.gltf', true, Error));
    AssertTrue('X3D: ' + Error, ExportMapGeometry(M, G, Dir + '/e1m1.x3d', false, Error));
    AssertTrue('bin', FileExists(Dir + '/e1m1.bin'));
    AssertTrue('a texture', FileExists(Dir + '/e1m1_textures/A-MUD.png'));
    Gltf := LoadNode(FilenameToUriSafe(Dir + '/e1m1.gltf'));
    X3d := LoadNode(FilenameToUriSafe(Dir + '/e1m1.x3d'));
    try
      FTriangles := 0;
      X3d.EnumerateNodes(TIndexedTriangleSetNode, {$ifdef FPC}@{$endif}CountTriangles, false);
      AssertTrue('X3D triangles', FTriangles > 5000);
      FShapes := 0;
      FTriangles := 0;
      Gltf.EnumerateNodes(TShapeNode, {$ifdef FPC}@{$endif}CountShape, false);
      AssertTrue('glTF shapes', FShapes > 100);
    finally
      FreeAndNil(Gltf);
      FreeAndNil(X3d);
    end;
  finally
    FreeAndNil(M);
    FreeAndNil(G);
    FreeAndNil(W);
  end;
end;

{ Rooms drawn against walls: corners on a line split it; an alcove in the
  void joins through the wall's middle piece, a room inside a sector
  along its wall takes that piece's side; a crossing room leaves the map
  as it was; BeginChange makes one undo step. }
procedure TTestEditor.TestEditWalls;

  function Pts(const C: array of Integer): TEditPoints;
  var
    I: Integer;
  begin
    SetLength(Result, Length(C) div 2);
    for I := 0 to High(Result) do
    begin
      Result[I].X := C[I * 2];
      Result[I].Y := C[I * 2 + 1];
    end;
  end;

var
  E: TDoomEditMap;
  Error: String;
  L, Lines: Integer;
  Data: TMemoryStream;
  W: TDoomWad;
  M: TDoomMap;
begin
  E := TDoomEditMap.Create;
  try
    E.Clear('E1M1');
    AssertEquals('room', 0, E.DrawSector(Pts([0, 0, 256, 0, 256, 256, 0, 256]), Error));
    { An alcove east, its corners on the east wall. }
    AssertEquals('alcove: ' + Error, 1, E.DrawSector(Pts([256, 64, 320, 64, 320, 192, 256, 192]), Error));
    AssertEquals('east wall split in three, 3 new walls', 9, Length(E.Lines));
    AssertEquals('in the alcove', 1, E.SectorAt(288, 128));
    L := E.NearestLine(256, 128, 1);
    AssertTrue('the middle piece is two-sided', E.Lines[L].Side[1] >= 0);
    L := E.NearestLine(256, 20, 1);
    AssertEquals('the lower piece stays a wall', -1, E.Lines[L].Side[1]);
    { A room inside the first one, along its west wall. }
    AssertEquals('closet: ' + Error, 2, E.DrawSector(Pts([0, 160, 64, 160, 64, 224, 0, 224]), Error));
    AssertEquals('in the closet', 2, E.SectorAt(32, 192));
    AssertEquals('outside it', 0, E.SectorAt(32, 32));
    L := E.NearestLine(0, 192, 1);
    AssertEquals('west piece one-sided', -1, E.Lines[L].Side[1]);
    AssertEquals('west piece faces the closet', 2, E.LineSector(L, 0));
    { Crossing the east wall away from its corners: refused, unchanged. }
    Lines := Length(E.Lines);
    AssertEquals('crossing', -1, E.DrawSector(Pts([200, 200, 300, 200, 300, 240, 200, 240]), Error));
    AssertEquals('unchanged', Lines, Length(E.Lines));
    { One undo step for a change of two sectors. }
    E.BeginChange;
    E.ChangeSector(0, 8, 0, 0);
    E.ChangeSector(1, 8, 0, 0);
    E.EndChange;
    AssertTrue('undo', E.Undo);
    AssertEquals('both back', 0, E.Sectors[0].Floor + E.Sectors[1].Floor);
    AssertTrue('closet still there', Length(E.Sectors) = 3);
    Data := E.SaveToWad;
    try
      RegisterEditedWad('E1M1', Data);
    finally
      FreeAndNil(Data);
    end;
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    try
      W.AddFile(EditedWadUrl('E1M1'));
      M := TDoomMap.Create(W, 'E1M1');
      try
        AssertEquals('area', 256 * 256 + 64 * 128, PolygonArea(M), 0.5);
        AssertEquals('closet', 2, M.SectorAt(32, 192));
        AssertEquals('alcove', 1, M.SectorAt(288, 128));
      finally
        FreeAndNil(M);
      end;
    finally
      FreeAndNil(W);
    end;
  finally
    FreeAndNil(E);
  end;
end;

{ Cutting a sector in two along a path, deleting a sector (its shared
  walls stay with the neighbour), dissolving a vertex, deleting lines. }
{ Flipping lines (two-sided only) and a sector's outline (what copying
  sectors draws again): the outer walls, clockwise, without the hole. }
procedure TTestEditor.TestEditFlipOutline;

  function Pts(const C: array of Integer): TEditPoints;
  var
    I: Integer;
  begin
    SetLength(Result, Length(C) div 2);
    for I := 0 to High(Result) do
    begin
      Result[I].X := C[I * 2];
      Result[I].Y := C[I * 2 + 1];
    end;
  end;

  function Area(const P: TEditPoints): Integer;
  var
    I, J: Integer;
  begin
    Result := 0;
    for I := 0 to High(P) do
    begin
      J := (I + 1) mod Length(P);
      Result := Result + P[I].X * P[J].Y - P[J].X * P[I].Y;
    end;
    Result := Result div 2;
  end;

var
  E: TDoomEditMap;
  Error: String;
  All: array of Integer;
  I: Integer;
  O: TEditPoints;
  Hit: TEditRayHit;
begin
  E := TDoomEditMap.Create;
  try
    E.Clear('E1M1');
    AssertEquals('room', 0, E.DrawSector(Pts([0, 0, 256, 0, 256, 256, 0, 256]), Error));
    AssertEquals('pillar room', 1, E.DrawSector(Pts([64, 64, 128, 64, 128, 128, 64, 128]), Error));
    O := E.SectorOutline(0);
    AssertEquals('outer corners', 4, Length(O));
    AssertEquals('clockwise, no hole', -256 * 256, Area(O));
    O := E.SectorOutline(1);
    AssertEquals('inner room', -64 * 64, Area(O));
    SetLength(All, Length(E.Lines));
    for I := 0 to High(All) do All[I] := I;
    AssertEquals('only the two-sided ones flip', 4, E.FlipLines(All));
    for I := 0 to High(E.Lines) do
      if E.LineSector(I, 1) >= 0 then
        AssertEquals('the outer room in front', 0, E.LineSector(I, 0));
    { Still the same rooms: the outline does not depend on the line's way. }
    AssertEquals('inner room after the flip', -64 * 64, Area(E.SectorOutline(1)));
    AssertEquals('room 1 at its place', 1, E.SectorAt(96, 96));
    AssertTrue('undo', E.Undo);
    AssertEquals('the inner room in front again', 1, E.LineSector(4, 0));
    { Rays from the eye (the 3D preview's picking): the inner room raised
      to 24, rays east from (10, 96) at eye height 41. }
    E.Sectors[1].Floor := 24;
    AssertTrue('level ray', E.RayHit(10, 96, 41, 1, 0, 0, Hit));
    AssertTrue('level: the east wall', (Hit.Kind = ehWall) and (Hit.Part = 'M') and (Hit.Side = 0) and
      (Abs(Hit.X - 256) < 0.01));
    AssertTrue('a little down', E.RayHit(10, 96, 41, 1, 0, -0.2, Hit));
    AssertTrue('onto the raised floor', (Hit.Kind = ehFloor) and (Hit.Sector = 1) and (Abs(Hit.X - 95) < 0.01));
    AssertTrue('steeply down', E.RayHit(10, 96, 41, 1, 0, -0.5, Hit));
    AssertTrue('the step''s lower part, outer side',
      (Hit.Kind = ehWall) and (Hit.Part = 'L') and (E.LineSector(Hit.Line, Hit.Side) = 0) and (Abs(Hit.X - 64) < 0.01));
    AssertTrue('up', E.RayHit(10, 96, 41, 0, 0, 1, Hit));
    AssertTrue('the ceiling', (Hit.Kind = ehCeiling) and (Hit.Sector = 0) and (Abs(Hit.Z - 128) < 0.01));
    AssertFalse('outside the map', E.RayHit(-50, 96, 41, 1, 0, 0, Hit));
  finally
    FreeAndNil(E);
  end;
end;

procedure TTestEditor.TestEditCutDelete;

  function Pts(const C: array of Integer): TEditPoints;
  var
    I: Integer;
  begin
    SetLength(Result, Length(C) div 2);
    for I := 0 to High(Result) do
    begin
      Result[I].X := C[I * 2];
      Result[I].Y := C[I * 2 + 1];
    end;
  end;

var
  E: TDoomEditMap;
  Error: String;
  L, V: Integer;
  Data: TMemoryStream;
  W: TDoomWad;
  M: TDoomMap;
begin
  E := TDoomEditMap.Create;
  try
    E.Clear('E1M1');
    AssertEquals('room', 0, E.DrawSector(Pts([0, 0, 256, 0, 256, 256, 0, 256]), Error));
    { North through the middle: the east half (on the cut's right) is new. }
    AssertEquals('cut: ' + Error, 1, E.SplitSector(Pts([128, 0, 128, 256]), Error));
    AssertEquals('east', 1, E.SectorAt(200, 128));
    AssertEquals('west', 0, E.SectorAt(50, 128));
    AssertEquals('4 walls, 2 split, 1 cut', 7, Length(E.Lines));
    { An L-shaped cut takes the south-west corner. }
    AssertEquals('corner: ' + Error, 2, E.SplitSector(Pts([0, 64, 64, 64, 64, 0]), Error));
    AssertEquals('in the corner', 2, E.SectorAt(32, 32));
    AssertEquals('west half', 0, E.SectorAt(32, 128));
    { Refused: leaving the sector, starting inside it. }
    L := Length(E.Lines);
    AssertEquals('out of the sector', -1, E.SplitSector(Pts([200, 100, 300, 100]), Error));
    AssertEquals('inside', -1, E.SplitSector(Pts([100, 100, 100, 256]), Error));
    AssertEquals('unchanged', L, Length(E.Lines));
    { Written and read back. }
    Data := E.SaveToWad;
    try
      RegisterEditedWad('E1M1', Data);
    finally
      FreeAndNil(Data);
    end;
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    try
      W.AddFile(EditedWadUrl('E1M1'));
      M := TDoomMap.Create(W, 'E1M1');
      try
        AssertEquals('area', 256 * 256, PolygonArea(M), 0.5);
        AssertEquals('corner read back', 2, M.SectorAt(32, 32));
        AssertEquals('east read back', 1, M.SectorAt(200, 200));
      finally
        FreeAndNil(M);
      end;
    finally
      FreeAndNil(W);
    end;
    { The corner deleted: void, its cut lines walls of sector 0 now. }
    E.DeleteSector(2);
    AssertEquals('sectors', 2, Length(E.Sectors));
    AssertEquals('corner gone', -1, E.SectorAt(32, 32));
    AssertEquals('west half stays', 0, E.SectorAt(32, 128));
    L := E.NearestLine(32, 64, 1);
    AssertEquals('cut line one-sided', -1, E.Lines[L].Side[1]);
    AssertEquals('facing sector 0', 0, E.LineSector(L, 0));
    AssertTrue('undo', E.Undo);
    AssertEquals('corner back', 2, E.SectorAt(32, 32));
    { A vertex in a wall's middle dissolves into one line. }
    E.Clear('E1M1');
    E.DrawSector(Pts([0, 0, 256, 0, 256, 256, 0, 256]), Error);
    V := E.SplitLine(E.NearestLine(128, 0, 1), 128, 0);
    AssertEquals('split', 5, Length(E.Lines));
    AssertTrue('dissolved', E.DissolveVertex(V));
    AssertEquals('joined', 4, Length(E.Lines));
    AssertEquals('vertices', 4, Length(E.Vertices));
    E.DeleteLines([0, 1]);
    AssertEquals('two lines left', 2, Length(E.Lines));
    AssertEquals('their vertices', 3, Length(E.Vertices));
  finally
    FreeAndNil(E);
  end;
end;

procedure TTestEditor.TestEditRoundTrip;
begin
  CheckEditRoundTrip('freedoom1.wad', 'E1M1', 0.002);
  CheckEditRoundTrip('freedoom2.wad', 'MAP01', 0.002);
end;

procedure TTestEditor.TestEditOperations;

  function Pts(const C: array of Integer): TEditPoints;
  var
    I: Integer;
  begin
    SetLength(Result, Length(C) div 2);
    for I := 0 to High(Result) do
    begin
      Result[I].X := C[I * 2];
      Result[I].Y := C[I * 2 + 1];
    end;
  end;

var
  E: TDoomEditMap;
  Error: String;
  Sec, I, V, TwoSided: Integer;
  Data: TMemoryStream;
  W: TDoomWad;
  M: TDoomMap;
  Textures, Flats: TStringList;
begin
  E := TDoomEditMap.Create;
  try
    E.Clear('E1M1');
    { A room in the void, drawn counter-clockwise (the editor turns it). }
    Sec := E.DrawSector(Pts([0, 0, 256, 0, 256, 256, 0, 256]), Error);
    AssertEquals('first room: ' + Error, 0, Sec);
    AssertEquals('4 walls', 4, Length(E.Lines));
    for I := 0 to 3 do
    begin
      AssertEquals('one-sided', -1, E.Lines[I].Side[1]);
      AssertEquals('room in front', 0, E.LineSector(I, 0));
    end;
    AssertEquals('inside', 0, E.SectorAt(128, 128));
    AssertEquals('outside', -1, E.SectorAt(300, 128));
    { A platform inside it: two-sided walls. }
    Sec := E.DrawSector(Pts([64, 64, 64, 192, 192, 192, 192, 64]), Error);
    AssertEquals('second room: ' + Error, 1, Sec);
    AssertEquals('8 walls', 8, Length(E.Lines));
    AssertEquals('platform inside', 1, E.SectorAt(128, 128));
    AssertEquals('around it', 0, E.SectorAt(32, 32));
    E.ChangeSector(1, 24, 0, 32);
    AssertEquals('raised', 24, E.Sectors[1].Floor);
    AssertEquals('lit', E.Sectors[0].Light + 32, E.Sectors[1].Light);
    { Crossing lines are refused. }
    AssertEquals('crossing refused', -1, E.DrawSector(Pts([100, 100, 300, 100, 300, 300]), Error));
    AssertTrue('crossing error', Pos('crosses', Error) > 0);
    { A room on the first one's east wall: the wall becomes two-sided. }
    Sec := E.DrawSector(Pts([256, 0, 512, 0, 512, 256, 256, 256]), Error);
    AssertEquals('joined room: ' + Error, 2, Sec);
    AssertEquals('11 walls', 11, Length(E.Lines));
    TwoSided := 0;
    for I := 0 to High(E.Lines) do
      if E.Lines[I].Side[1] >= 0 then Inc(TwoSided);
    AssertEquals('two-sided walls', 5, TwoSided);
    AssertEquals('east room', 2, E.SectorAt(400, 128));
    { Undo / redo. }
    AssertTrue('undo', E.Undo);
    AssertEquals('undone', 8, Length(E.Lines));
    AssertTrue('redo', E.Redo);
    AssertEquals('redone', 11, Length(E.Lines));
    { A door between: split the east room's north wall... simpler, the
      platform as a door. }
    AssertTrue('door', E.MakeDoor(1));
    AssertEquals('door closed', E.Sectors[1].Floor, E.Sectors[1].Ceiling);
    for I := 0 to High(E.Lines) do
      if E.Lines[I].Special = 1 then
        AssertEquals('door at the back', 1, E.LineSector(I, 1));
    { Splitting a line, merging a vertex back. }
    I := E.NearestLine(384, 256, 8);
    AssertTrue('north wall found', I >= 0);
    V := E.SplitLine(I, 384, 256);
    AssertTrue('split', V >= 0);
    AssertEquals('12 walls', 12, Length(E.Lines));
    E.MoveVertex(V, 256, 256);
    AssertEquals('merged back', 11, Length(E.Lines));
    { Things. }
    AssertEquals('thing', 0, E.AddThing(32, 32, 1, 90));
    E.AddThing(400, 128, 3001, 180);
    E.MoveThing(1, 420, 100);
    AssertEquals('moved', 420, E.Things[1].X);
    AssertEquals('nearest thing', 1, E.NearestThing(410, 110, 32));
    { Written and read back as a map. }
    Data := E.SaveToWad;
    try
      RegisterEditedWad('E1M1', Data);
    finally
      FreeAndNil(Data);
    end;
    W := TDoomWad.Create(WadUrl('freedoom1.wad'));
    try
      W.AddFile(EditedWadUrl('E1M1'));
      M := TDoomMap.Create(W, 'E1M1');
      try
        AssertEquals('sectors', 3, Length(M.Sectors));
        AssertEquals('things', 2, Length(M.Things));
        AssertEquals('area', 512 * 256, PolygonArea(M), 0.5);
        AssertEquals('platform', 1, M.SectorAt(128, 128));
        AssertEquals('west room', 0, M.SectorAt(32, 32));
        AssertEquals('east room', 2, M.SectorAt(400, 128));
      finally
        FreeAndNil(M);
      end;
      Textures := W.TextureNames;
      Flats := W.FlatNames;
      try
        AssertTrue('STARTAN3 a texture', Textures.IndexOf('STARTAN3') >= 0);
        AssertTrue('FLOOR4_8 a flat', Flats.IndexOf('FLOOR4_8') >= 0);
        AssertTrue('FLOOR4_8 no texture', Textures.IndexOf('FLOOR4_8') < 0);
      finally
        FreeAndNil(Textures);
        FreeAndNil(Flats);
      end;
    finally
      FreeAndNil(W);
    end;
  finally
    FreeAndNil(E);
  end;
end;

var
  App: TTestRunner;
begin
  RegisterTests([TTestWad, TTestMap, TTestMusic, TTestDehacked, TTestGamepad, TTestStates, TTestEditor]);
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
