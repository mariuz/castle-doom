{ Game initialization: window, views. }
unit GameInitialize;

interface

implementation

uses SysUtils,
  CastleWindow, CastleLog, CastleUIControls, CastleApplicationProperties, CastleParameters, CastleConfig,
  CastleKeysMouse,
  CastleUtils, CastleTimeUtils,
  CastleFilesUtils, CastleUriUtils, CastleGLShaders,
  DoomLighting, DoomDehacked, DoomMusic, DoomGeometry, GameGamepad, GameViewMenu, GameViewPlay, GameViewDesign, GameSettings, GameSaveBundle, GameLogFilter, GameCrash;

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

procedure ApplicationInitialize;
var
  I: Integer;
  ExportSaves, ImportSaves: String;
begin
  ExportSaves := '';
  ImportSaves := '';
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
  if Application.PageUrlParameters.ContainsKey('warp') then
    CmdWarp := UpperCase(Application.PageUrlParameters['warp']);
  if Application.PageUrlParameters.ContainsKey('skill') then
    CmdSkill := Clamped(StrToIntDef(Application.PageUrlParameters['skill'], 3), 1, 5) - 1;
  if (AutoTestMap <> '') or (CmdWarp <> '') then
    WritelnLog('Web', 'Page URL options: map "%s", demo "%s", warp "%s"', [AutoTestMap, AutoTestDemo, CmdWarp]);
  {$endif}
  Window.Container.LoadSettings('castle-data:/CastleSettings.xml');
  { --fixed-step: no frame advances more than a tic (TViewPlay.Update
    also keeps frames from being shorter), so the world, the walk
    navigation and the demo's waits all move by exactly 1/35 s a frame. }
  if AutoTestFixedStep then
  begin
    Window.Container.Fps.MaxSensibleSecondsPassed := 1 / 35;
    WritelnLog('AutoTest', 'Fixed step: 1/35 s a frame');
  end;
  { Remembered WAD paths live in the user config (castle-config:/). }
  UserConfig.Load;
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
  ViewMenu := TViewMenu.Create(Application);
  ViewMenu.Name := 'ViewMenu';
  ViewPlay := TViewPlay.Create(Application);
  ViewPlay.Name := 'ViewPlay';
  ViewDesign := TViewDesign.Create(Application);
  ViewDesign.Name := 'ViewDesign';
  Window.Container.View := ViewMenu;
end;

initialization
  ApplicationProperties.ApplicationName := 'castle-doom';
  ApplicationProperties.Version := '0.11.0';
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
