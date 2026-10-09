{ Unit tests of the engine-independent Doom* units: WAD reading, map BSP
  loading, MUS rendering and DeHackEd parsing, on the Freedoom WADs in
  data/wads. Gameplay is covered by the --autotest runs
  (tools/run_autotests.py); these cover the parsers without a window.

  Build and run from the project root (CI does the same):
    castle-engine simple-compile tests/castle_doom_tests.lpr
    tests/castle_doom_tests --all --format=plain }
program castle_doom_tests;

{$mode objfpc}{$H+}
{$unitpath ../code}

uses SysUtils, Classes, Math, fpcunit, testregistry, consoletestrunner,
  CastleVectors, CastleUriUtils,
  DoomWad, DoomMap, DoomMusic, DoomThings, DoomDehacked;

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
  end;

  TTestMap = class(TTestCase)
  published
    procedure TestE1M1Bsp;
    procedure TestMap01;
  end;

  TTestMusic = class(TTestCase)
  published
    procedure TestRenderMus;
    procedure TestRejectGarbage;
  end;

  TTestDehacked = class(TTestCase)
  published
    procedure TestFreedoomLump;
    procedure TestPatchFile;
  end;

{ TTestWad }

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

{ TTestMusic }

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

var
  App: TTestRunner;
begin
  RegisterTests([TTestWad, TTestMap, TTestMusic, TTestDehacked]);
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
