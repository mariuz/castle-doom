{ Game initialization: window, views. }
unit GameInitialize;

interface

implementation

uses SysUtils,
  CastleWindow, CastleLog, CastleUIControls, CastleApplicationProperties, CastleParameters, CastleConfig,
  GameViewMenu, GameViewPlay;

var
  Window: TCastleWindow;

procedure ApplicationInitialize;
var
  I: Integer;
begin
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
  ViewMenu := TViewMenu.Create(Application);
  ViewPlay := TViewPlay.Create(Application);
  Window.Container.View := ViewMenu;
end;

initialization
  ApplicationProperties.ApplicationName := 'castle-doom';
  ApplicationProperties.Version := '0.1.0';
  InitializeLog;
  Application.OnInitialize := @ApplicationInitialize;
  Window := TCastleWindow.Create(Application);
  Window.Caption := 'Castle DOOM';
  Window.Width := 1600;
  Window.Height := 900;
  Application.MainWindow := Window;
  Window.ParseParameters;
end.
