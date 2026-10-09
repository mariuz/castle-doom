{ Game initialization: window, views. }
unit GameInitialize;

interface

implementation

uses SysUtils,
  CastleWindow, CastleLog, CastleUIControls, CastleApplicationProperties, CastleParameters, CastleConfig,
  CastleUtils,
  CastleFilesUtils, CastleUriUtils,
  DoomLighting, GameViewMenu, GameViewPlay, GameSettings, GameSaveBundle;

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
  { Doom-style options: -iwad FILE, -file PWAD [PWAD...], -warp MAP. }
  I := 1;
  while I <= Parameters.High do
  begin
    if (Parameters[I] = '--autotest') and (I + 2 <= Parameters.High) then
    begin
      AutoTestMap := UpperCase(Parameters[I + 1]);
      AutoTestPrefix := Parameters[I + 2];
      Inc(I, 2);
    end else
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
  Window.Container.LoadSettings('castle-data:/CastleSettings.xml');
  { Remembered WAD paths live in the user config (castle-config:/). }
  UserConfig.Load;
  if (ExportSaves <> '') or (ImportSaves <> '') then
  begin
    TransferSaves(ExportSaves, ImportSaves);
    Halt;
  end;
  { Volumes and toggles from the last session. }
  LoadSettings;
  DoomLightingInstance.Diminish := Settings.Diminish;
  ViewMenu := TViewMenu.Create(Application);
  ViewPlay := TViewPlay.Create(Application);
  Window.Container.View := ViewMenu;
end;

initialization
  ApplicationProperties.ApplicationName := 'castle-doom';
  ApplicationProperties.Version := '0.3.0';
  InitializeLog;
  Application.OnInitialize := @ApplicationInitialize;
  Window := TCastleWindow.Create(Application);
  Window.Caption := 'Castle DOOM';
  Window.Width := 1600;
  Window.Height := 900;
  Application.MainWindow := Window;
  Window.ParseParameters;
end.
