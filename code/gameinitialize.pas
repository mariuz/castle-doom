{ Game initialization: window, views. }
unit GameInitialize;

interface

implementation

uses SysUtils, Classes,
  CastleWindow, CastleLog, CastleUIControls, CastleApplicationProperties, CastleParameters, CastleConfig,
  CastleKeysMouse,
  CastleUtils, CastleTimeUtils,
  CastleFilesUtils, CastleUriUtils, CastleGLShaders,
  DoomLighting, DoomDehacked, DoomEditMap, DoomMusic, DoomGeometry, DoomRandomMap, DoomWad, GameGamepad, GameViewMenu, GameViewPlay, GameViewDesign, GameViewEdit, DoomExport, DoomGraphics, GameSettings, GameSaveBundle, GameSaveStorage, GameLogFilter, GameCrash, GameTouch;

var
  Window: TCastleWindow;

{ --export-saves FILE / --import-saves FILE: move the saves and settings
  out of or into this installation as one bundle (the format of the web
  page's "Your saves" export), then quit. }
procedure TransferSaves(const ExportTo, ImportFrom: String);
var
  Count: Integer;
begin
  if ImportFrom <> '' then
  begin
    if ImportSaveBundle(FileToString(FilenameToUriSafe(ImportFrom)), Count) then
      WritelnLog('Save', 'Imported %d files from %s', [Count, ImportFrom])
    else
      WritelnWarning('Save', '%s is not a Castle DOOM save bundle', [ImportFrom]);
  end;
  if ExportTo <> '' then
  begin
    StringToFile(FilenameToUriSafe(ExportTo), ExportSaveBundle(Count));
    WritelnLog('Save', 'Exported %d files to %s', [Count, ExportTo]);
  end;
end;

{ --random-wad FILE: write the random maps' PWAD (the seed of -random, the
  IWAD of -iwad or Freedoom) for other Doom ports. }
procedure WriteRandomWad(const FileName, Iwad: String; const Seed: Cardinal);
var
  Wad: TDoomWad;
  F: TFileStream;
begin
  if Iwad <> '' then
    Wad := TDoomWad.Create(Iwad)
  else
    Wad := TDoomWad.Create('castle-data:/wads/freedoom1.wad');
  try
    Wad.AddFile(RandomWadUrl(Seed));
    F := TFileStream.Create(FileName, fmCreate);
    try
      F.CopyFrom(Wad.FileData(Wad.FileUrls.Count - 1), 0);
    finally
      FreeAndNil(F);
    end;
    WritelnLog('Random', 'Wrote seed %d to %s', [Seed, FileName]);
  finally
    FreeAndNil(Wad);
  end;
end;

{ --export-map MAP FILE: the map editor's export without the editor: MAP
  from the IWAD and PWADs (-iwad, -file) as a PWAD of its own, with its
  nodes built anew. }
procedure ExportMap(const MapName, FileName, Iwad: String);
var
  Wad: TDoomWad;
  Edit: TDoomEditMap;
  Data: TMemoryStream;
  Error: String;
  I: Integer;
begin
  if Iwad <> '' then
    Wad := TDoomWad.Create(Iwad)
  else
    Wad := TDoomWad.Create('castle-data:/wads/freedoom1.wad');
  Edit := TDoomEditMap.Create;
  try
    for I := 0 to CmdPwads.Count - 1 do
      Wad.AddFile(CmdPwads[I]);
    if not Edit.LoadFromWad(Wad, MapName, Error) then
    begin
      WritelnWarning('Editor', 'Cannot export: %s', [Error]);
      Exit;
    end;
    Data := Edit.SaveToWad;
    try
      Data.SaveToFile(FileName);
    finally
      FreeAndNil(Data);
    end;
    WritelnLog('Editor', 'Exported %s to %s', [Edit.Summary, FileName]);
  finally
    FreeAndNil(Edit);
    FreeAndNil(Wad);
  end;
end;

{ --export-gltf / --export-x3d MAP FILE: the level's geometry and
  textures as a 3D model (DoomExport). }
procedure ExportScene(const MapName, FileName, Iwad: String; const Gltf: Boolean);
var
  Wad: TDoomWad;
  Graphics: TDoomGraphics;
  Error: String;
  I: Integer;
begin
  if Iwad <> '' then
    Wad := TDoomWad.Create(Iwad)
  else if Copy(MapName, 1, 3) = 'MAP' then
    Wad := TDoomWad.Create('castle-data:/wads/freedoom2.wad')
  else
    Wad := TDoomWad.Create('castle-data:/wads/freedoom1.wad');
  Graphics := nil;
  try
    for I := 0 to CmdPwads.Count - 1 do
      Wad.AddFile(CmdPwads[I]);
    Graphics := TDoomGraphics.Create(Wad);
    if not ExportLevel(Wad, Graphics, MapName, FileName, Gltf, Error) then
      WritelnWarning('Export', 'Cannot export %s: %s', [MapName, Error]);
  finally
    FreeAndNil(Graphics);
    FreeAndNil(Wad);
  end;
end;

{ -random [SEED]: the random maps' PWAD on top (a new seed when none is
  given), starting at its first map unless -warp says otherwise. }
procedure UseRandomMaps(const SeedText: String; out Seed: Cardinal);
begin
  Seed := Cardinal(StrToInt64Def(SeedText, 0));
  if Seed = 0 then Seed := NewRandomSeed;
  CmdPwads.Add(RandomWadUrl(Seed));
end;

procedure ApplicationInitialize;
var
  I: Integer;
  ExportSaves, ImportSaves, RandomWadFile, ExportMapName, ExportMapFile, SceneMap, SceneFile: String;
  SceneGltf: Boolean;
  Upload: TMemoryStream;
  RandomSeed: Cardinal;
begin
  ExportSaves := '';
  ImportSaves := '';
  RandomWadFile := '';
  ExportMapName := '';
  ExportMapFile := '';
  SceneMap := '';
  SceneFile := '';
  SceneGltf := true;
  RandomSeed := 0;
  { Files picked in the browser (and --upload's) outlive the page. }
  InstallUploadStore;
  { --autotest MAPNAME OUTPUT_PREFIX : load the map, save screenshots, quit. }
  { Doom-style options: -iwad FILE, -file PWAD [PWAD...], -deh PATCH [PATCH...],
    -warp MAP. }
  I := 1;
  while I <= Parameters.High do
  begin
    if (Parameters[I] = '--autotest') and (I + 2 <= Parameters.High) then
    begin
      AutoTestMap := UpperCase(Parameters[I + 1]);
      AutoTestPrefix := Parameters[I + 2];
      Inc(I, 2);
    end else
    if Parameters[I] = '--fm-synth' then
      ForceFmSynth := true
    else
    if Parameters[I] = '--no-atlas' then
      UseTextureAtlas := false
    else
    if Parameters[I] = '--no-atlas-mipmaps' then
      UseAtlasMipmaps := false
    else
    if Parameters[I] = '--atlas' then
      UseTextureAtlas := true
    else
    if Parameters[I] = '--fixed-step' then
      AutoTestFixedStep := true
    else
    if Parameters[I] = '--touch' then
    begin
      { The touch controls on the desktop (the mouse is one finger). }
      TouchForced := true;
      TouchMode := true;
    end else
    if Parameters[I] = '--profile' then
      { CGE's profiler: each map load logs its stages (Profiler.Stop
        with LogSummary), PROFILE in a demo the whole summary. }
      Profiler.Enabled := true
    else
    if (Parameters[I] = '--demo') and (I + 1 <= Parameters.High) then
    begin
      AutoTestDemo := Parameters[I + 1];
      Inc(I);
    end else
    if ((Parameters[I] = '-iwad') or (Parameters[I] = '--iwad')) and (I + 1 <= Parameters.High) then
    begin
      CmdIwad := Parameters[I + 1];
      Inc(I);
    end else
    if ((Parameters[I] = '-loadgame') or (Parameters[I] = '--loadgame')) and (I + 1 <= Parameters.High) then
    begin
      CmdLoadSlot := StrToIntDef(Parameters[I + 1], 0);
      Inc(I);
    end else
    if (Parameters[I] = '--wad-base-url') and (I + 1 <= Parameters.High) then
    begin
      WadBaseUrl := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '--export-saves') and (I + 1 <= Parameters.High) then
    begin
      ExportSaves := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '--import-saves') and (I + 1 <= Parameters.High) then
    begin
      ImportSaves := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '-random') or (Parameters[I] = '--random') then
    begin
      if (I + 1 <= Parameters.High) and (StrToInt64Def(Parameters[I + 1], -1) > 0) then
      begin
        UseRandomMaps(Parameters[I + 1], RandomSeed);
        Inc(I);
      end else
        UseRandomMaps('', RandomSeed);
    end else
    if (Parameters[I] = '--record') and (I + 1 <= Parameters.High) then
    begin
      DemoRecordFile := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '--playdemo') and (I + 1 <= Parameters.High) then
    begin
      DemoPlayFile := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '--ghost') and (I + 1 <= Parameters.High) then
    begin
      DemoGhostFile := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '--random-wad') and (I + 1 <= Parameters.High) then
    begin
      RandomWadFile := Parameters[I + 1];
      Inc(I);
    end else
    if (Parameters[I] = '--export-map') and (I + 2 <= Parameters.High) then
    begin
      ExportMapName := UpperCase(Parameters[I + 1]);
      ExportMapFile := Parameters[I + 2];
      Inc(I, 2);
    end else
    if ((Parameters[I] = '--export-gltf') or (Parameters[I] = '--export-x3d')) and (I + 2 <= Parameters.High) then
    begin
      SceneGltf := Parameters[I] = '--export-gltf';
      SceneMap := UpperCase(Parameters[I + 1]);
      SceneFile := Parameters[I + 2];
      Inc(I, 2);
    end else
    if (Parameters[I] = '--upload') and (I + 1 <= Parameters.High) then
    begin
      { --upload FILE: what the browser's file picker does (the bytes kept
        as upload:/NAME), for testing that path: -file upload:/NAME. }
      Upload := TMemoryStream.Create;
      try
        Upload.LoadFromFile(Parameters[I + 1]);
        RegisterUpload(Parameters[I + 1], Upload);
      finally
        FreeAndNil(Upload);
      end;
      Inc(I);
    end else
    if Parameters[I] = '--edit' then
    begin
      { --edit [MAP]: the map editor on MAP (else the first map). }
      CmdEdit := true;
      if (I + 1 <= Parameters.High) and (Parameters[I + 1] <> '') and (Parameters[I + 1][1] <> '-') then
      begin
        CmdWarp := UpperCase(Parameters[I + 1]);
        Inc(I);
      end;
    end else
    if (Parameters[I] = '--menukeys') and (I + 1 <= Parameters.High) then
    begin
      AutoTestMenuKeys := Parameters[I + 1];
      Inc(I);
    end else
    if ((Parameters[I] = '-skill') or (Parameters[I] = '--skill')) and (I + 1 <= Parameters.High) then
    begin
      { Doom numbering: 1 "I'm too young to die" .. 5 "Nightmare!". }
      CmdSkill := Clamped(StrToIntDef(Parameters[I + 1], 3), 1, 5) - 1;
      Inc(I);
    end else
    if ((Parameters[I] = '-warp') or (Parameters[I] = '--warp')) and (I + 1 <= Parameters.High) then
    begin
      CmdWarp := UpperCase(Parameters[I + 1]);
      Inc(I);
    end else
    if (Parameters[I] = '-deh') or (Parameters[I] = '--deh') or
       (Parameters[I] = '-bex') or (Parameters[I] = '--bex') then
    begin
      { DeHackEd / BEX patches, applied after the WADs' DEHACKED lumps. }
      while (I + 1 <= Parameters.High) and (Parameters[I + 1] <> '') and (Parameters[I + 1][1] <> '-') do
      begin
        AddDehackedFile(Parameters[I + 1]);
        Inc(I);
      end;
    end else
    if (Parameters[I] = '-file') or (Parameters[I] = '--file') then
    begin
      while (I + 1 <= Parameters.High) and (Parameters[I + 1] <> '') and (Parameters[I + 1][1] <> '-') do
      begin
        CmdPwads.Add(Parameters[I + 1]);
        Inc(I);
      end;
    end;
    Inc(I);
  end;
  {$ifdef WASI}
  { The web build has no command line: the page URL's query gives the same
    options, e.g. play/?map=E1M1&demo=G:480:712,A:0,W:30 (profiling, see
    the "Perf:" / "PerfView:" console lines) or ?warp=E1M2&skill=4. }
  if Application.PageUrlParameters.ContainsKey('map') then
  begin
    AutoTestMap := UpperCase(Application.PageUrlParameters['map']);
    AutoTestPrefix := 'web';
  end;
  if Application.PageUrlParameters.ContainsKey('demo') then
    AutoTestDemo := Application.PageUrlParameters['demo'];
  { A map without a demo is just a game on that map: the desktop's
    demo-less autotest saves screenshots, which the browser cannot write
    (an exception stops the WebAssembly program). }
  if (AutoTestMap <> '') and (AutoTestDemo = '') then
  begin
    CmdWarp := AutoTestMap;
    AutoTestMap := '';
    AutoTestPrefix := '';
  end;
  if Application.PageUrlParameters.ContainsKey('warp') then
    CmdWarp := UpperCase(Application.PageUrlParameters['warp']);
  if Application.PageUrlParameters.ContainsKey('random') then
    UseRandomMaps(Application.PageUrlParameters['random'], RandomSeed);
  if Application.PageUrlParameters.ContainsKey('skill') then
    CmdSkill := Clamped(StrToIntDef(Application.PageUrlParameters['skill'], 3), 1, 5) - 1;
  { ?record=1 records the next game (kept in localStorage, downloaded at
    its end), ?playdemo=last plays that recording back. }
  if Application.PageUrlParameters.ContainsKey('record') then
    DemoRecordFile := LastDemoUrl;
  if Application.PageUrlParameters.ContainsKey('playdemo') then
    DemoPlayFile := LastDemoUrl;
  { ?ghost=last races that recording's ghost. }
  if Application.PageUrlParameters.ContainsKey('ghost') then
    DemoGhostFile := LastDemoUrl;
  if (AutoTestMap <> '') or (CmdWarp <> '') then
    WritelnLog('Web', 'Page URL options: map "%s", demo "%s", warp "%s"', [AutoTestMap, AutoTestDemo, CmdWarp]);
  {$endif}
  { -random alone starts the game on the first random map. }
  if (RandomSeed <> 0) and (CmdWarp = '') and (AutoTestMap = '') then
    CmdWarp := 'E1M1';
  if RandomWadFile <> '' then
  begin
    if RandomSeed = 0 then RandomSeed := NewRandomSeed;
    WriteRandomWad(RandomWadFile, CmdIwad, RandomSeed);
    Halt;
  end;
  if ExportMapFile <> '' then
  begin
    ExportMap(ExportMapName, ExportMapFile, CmdIwad);
    Halt;
  end;
  if SceneFile <> '' then
  begin
    ExportScene(SceneMap, SceneFile, CmdIwad, SceneGltf);
    Halt;
  end;
  Window.Container.LoadSettings('castle-data:/CastleSettings.xml');
  { --fixed-step: no frame advances more than a tic (TViewPlay.Update
    also keeps frames from being shorter), so the world, the walk
    navigation and the demo's waits all move by exactly 1/35 s a frame. }
  if AutoTestFixedStep then
  begin
    Window.Container.Fps.MaxSensibleSecondsPassed := 1 / 35;
    WritelnLog('AutoTest', 'Fixed step: 1/35 s a frame');
  end;
  { Phones and tablets (Android): the touch controls, always. }
  if ApplicationProperties.TouchDevice then
  begin
    TouchForced := true;
    TouchMode := true;
    WritelnLog('Touch', 'Touch device: touch controls on');
  end;
  { Remembered WAD paths live in the user config (castle-config:/). }
  LoadUserConfig;
  if (ExportSaves <> '') or (ImportSaves <> '') then
  begin
    TransferSaves(ExportSaves, ImportSaves);
    Halt;
  end;
  { Volumes and toggles from the last session. }
  LoadSettings;
  ApplyWindowSettings(true);
  InitializeGamepads;
  { The engine's inspector on F8 in every build: CGE registers the key
    only through ApplicationProperties.InitializeDebug, which the
    generated program calls in debug builds alone. The hierarchy it shows
    is grouped and named (Map, Things, Sprites, DoomWorldStatus). }
  TCastleContainer.InputInspector.Key := keyF8;
  { CASTLE_DOOM_LOG_SHADERS=1 logs every shader compile and link (CGE's
    LogShaders): a count that keeps growing during play means GL
    resources are being recreated, which is slow in the browser. }
  LogShaders := GetEnvironmentVariable('CASTLE_DOOM_LOG_SHADERS') <> '';
  DoomLightingInstance.Diminish := Settings.Diminish;
  DoomLightingInstance.Gamma := Settings.Gamma;
  ViewMenu := TViewMenu.Create(Application);
  ViewMenu.Name := 'ViewMenu';
  ViewPlay := TViewPlay.Create(Application);
  ViewPlay.Name := 'ViewPlay';
  ViewDesign := TViewDesign.Create(Application);
  ViewEdit := TViewEdit.Create(Application);
  ViewEdit.Name := 'ViewEdit';
  ViewDesign.Name := 'ViewDesign';
  Window.Container.View := ViewMenu;
end;

initialization
  ApplicationProperties.ApplicationName := 'castle-doom';
  ApplicationProperties.Version := '0.59.0';
  InitializeLog;
  { CASTLE_DOOM_LOG=Load,Music: a filtered copy of the log (GameLogFilter). }
  StartLogFilter;
  { Uncaught exceptions: logged and shown with the log's last lines. }
  InstallCrashReporter;
  Application.OnInitialize := @ApplicationInitialize;
  Window := TCastleWindow.Create(Application);
  Window.Caption := 'Castle DOOM';
  Window.Width := 1600;
  Window.Height := 900;
  Application.MainWindow := Window;
  Window.ParseParameters;
end.
