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
  CastleVectors, CastleUriUtils,
  DoomWad, DoomMap, DoomMusic, DoomOpl3, DoomThings, DoomDehacked;

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
  strict private
    procedure CheckNodeWad(const FileName, ExpectedFormat: String;
      const Subsectors, Area: Integer);
  published
    procedure TestE1M1Bsp;
    procedure TestMap01;
    procedure TestZDoomNodes;
    procedure TestGlBspNodes;
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
