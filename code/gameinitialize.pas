{ Game initialization: window, views. }
unit GameInitialize;

interface

implementation

uses SysUtils,
  CastleWindow, CastleLog, CastleUIControls, CastleApplicationProperties, CastleParameters,
  GameViewMenu, GameViewPlay;

var
  Window: TCastleWindow;

procedure ApplicationInitialize;
var
  I: Integer;
begin
  { --autotest MAPNAME OUTPUT_PREFIX : load the map, save screenshots, quit. }
  for I := 1 to Parameters.High do
  begin
    if (Parameters[I] = '--autotest') and (I + 2 <= Parameters.High) then
    begin
      AutoTestMap := UpperCase(Parameters[I + 1]);
      AutoTestPrefix := Parameters[I + 2];
    end;
    if (Parameters[I] = '--demo') and (I + 1 <= Parameters.High) then
      AutoTestDemo := Parameters[I + 1];
  end;
  Window.Container.LoadSettings('castle-data:/CastleSettings.xml');
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
