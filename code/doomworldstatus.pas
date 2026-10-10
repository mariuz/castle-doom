{ An invisible control (named DoomWorldStatus in the play view's design)
  whose published properties show the game's state in the engine's
  inspector (F8, or the INSPECTOR demo command): select it in the
  hierarchy. Registered for the CGE editor too. }
unit DoomWorldStatus;

interface

uses Classes,
  CastleUIControls,
  DoomWorld;

type
  TDoomWorldStatus = class(TCastleUserInterface)
  strict private
    function GetTic: Integer;
    function GetHealth: Integer;
    function GetArmor: Integer;
    function GetPlayerX: Single;
    function GetPlayerY: Single;
    function GetPlayerZ: Single;
    function GetPlayerAngle: Single;
    function GetKills: Integer;
    function GetTotalKills: Integer;
    function GetItemsFound: Integer;
    function GetSecretsFound: Integer;
    function GetThings: Integer;
    function GetSectors: Integer;
  public
    World: TDoomWorld;
    MapName: String;
  published
    property Map: String read MapName;
    property Tic: Integer read GetTic;
    property PlayerHealth: Integer read GetHealth;
    property PlayerArmor: Integer read GetArmor;
    property PlayerX: Single read GetPlayerX;
    property PlayerY: Single read GetPlayerY;
    property PlayerZ: Single read GetPlayerZ;
    property PlayerAngle: Single read GetPlayerAngle;
    property Kills: Integer read GetKills;
    property TotalKills: Integer read GetTotalKills;
    property ItemsFound: Integer read GetItemsFound;
    property SecretsFound: Integer read GetSecretsFound;
    property Things: Integer read GetThings;
    property Sectors: Integer read GetSectors;
  end;


implementation

uses SysUtils, CastleComponentSerialize;

{ TDoomWorldStatus }

function TDoomWorldStatus.GetTic: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Tic;
end;

function TDoomWorldStatus.GetHealth: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Player.Health;
end;

function TDoomWorldStatus.GetArmor: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Player.Armor;
end;

function TDoomWorldStatus.GetPlayerX: Single;
begin
  if World = nil then Exit(0);
  Result := World.Player.X;
end;

function TDoomWorldStatus.GetPlayerY: Single;
begin
  if World = nil then Exit(0);
  Result := World.Player.Y;
end;

function TDoomWorldStatus.GetPlayerZ: Single;
begin
  if World = nil then Exit(0);
  Result := World.Player.Z;
end;

function TDoomWorldStatus.GetPlayerAngle: Single;
begin
  if World = nil then Exit(0);
  Result := World.Player.Angle;
end;

function TDoomWorldStatus.GetKills: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Player.Kills;
end;

function TDoomWorldStatus.GetTotalKills: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Player.TotalKills;
end;

function TDoomWorldStatus.GetItemsFound: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Player.Items;
end;

function TDoomWorldStatus.GetSecretsFound: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Player.Secrets;
end;

function TDoomWorldStatus.GetThings: Integer;
begin
  if World = nil then Exit(0);
  Result := World.Actors.Count;
end;

function TDoomWorldStatus.GetSectors: Integer;
begin
  if (World = nil) or (World.Map = nil) then Exit(0);
  Result := Length(World.Map.Sectors);
end;

initialization
  RegisterSerializableComponent(TDoomWorldStatus, 'Doom World Status');
end.
