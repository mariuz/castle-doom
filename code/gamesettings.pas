{ Player settings that outlive the session: sound and music volume (Doom's
  0..15 scales), music on / off, light diminishing and mouse look. Stored as
  JSON next to the save games (GameSaveStorage: a castle-config: file on the
  desktop, localStorage in the browser). }
unit GameSettings;

interface

type
  TGameSettings = record
    SfxVolume, MusicVolume: Integer;
    MusicOn: Boolean;
    Diminish: Boolean;
    MouseLook: Boolean;
    { Doom's options page: mouse sensitivity 0..9, messages on / off. }
    MouseSensitivity: Integer;
    ShowMessages: Boolean;
  end;

const
  MaxVolume = 15;

var
  Settings: TGameSettings;

{ Read the stored settings (defaults for anything missing). }
procedure LoadSettings;
procedure SaveSettings;

{ Gains for TCastleSound.Volume / TDoomMusic.Volume. The defaults keep the
  mix the game always had: effects at full volume, music at half. }
function SfxGain: Single;
function MusicGain: Single;
{ TCastleWalkNavigation.MouseLook*Sensitivity for the mouse sensitivity. }
function MouseLookSensitivity: Single;

implementation

uses SysUtils, Math, FpJson, JsonParser, CastleLog, CastleUtils, GameSaveStorage;

const
  SettingsUrl = 'castle-config:/settings.json';

procedure Defaults;
begin
  Settings.SfxVolume := MaxVolume;
  Settings.MusicVolume := 8;
  Settings.MusicOn := true;
  Settings.Diminish := true;
  Settings.MouseLook := true;
  Settings.MouseSensitivity := 5;
  Settings.ShowMessages := true;
end;

procedure LoadSettings;
var
  Text: String;
  D: TJSONData;
  J: TJSONObject;
begin
  Defaults;
  if not SaveStorageRead(SettingsUrl, Text) then Exit;
  D := nil;
  try
    D := GetJSON(Text);
  except
    on E: Exception do
      WritelnWarning('Settings', 'Cannot read %s: %s', [SettingsUrl, E.Message]);
  end;
  if not (D is TJSONObject) then
  begin
    FreeAndNil(D);
    Exit;
  end;
  J := TJSONObject(D);
  try
    Settings.SfxVolume := Clamped(J.Get('sfxVolume', Settings.SfxVolume), 0, MaxVolume);
    Settings.MusicVolume := Clamped(J.Get('musicVolume', Settings.MusicVolume), 0, MaxVolume);
    Settings.MusicOn := J.Get('musicOn', Settings.MusicOn);
    Settings.Diminish := J.Get('diminish', Settings.Diminish);
    Settings.MouseLook := J.Get('mouseLook', Settings.MouseLook);
    Settings.MouseSensitivity := Clamped(J.Get('mouseSensitivity', Settings.MouseSensitivity), 0, 9);
    Settings.ShowMessages := J.Get('showMessages', Settings.ShowMessages);
  finally
    FreeAndNil(J);
  end;
  WritelnLog('Settings', 'Sound %d, music %d (%s), light diminishing %s, mouse look %s', [
    Settings.SfxVolume, Settings.MusicVolume, BoolToStr(Settings.MusicOn, 'on', 'off'),
    BoolToStr(Settings.Diminish, 'on', 'off'), BoolToStr(Settings.MouseLook, 'on', 'off')]);
end;

procedure SaveSettings;
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  try
    J.Add('sfxVolume', Settings.SfxVolume);
    J.Add('musicVolume', Settings.MusicVolume);
    J.Add('musicOn', Settings.MusicOn);
    J.Add('diminish', Settings.Diminish);
    J.Add('mouseLook', Settings.MouseLook);
    J.Add('mouseSensitivity', Settings.MouseSensitivity);
    J.Add('showMessages', Settings.ShowMessages);
    SaveStorageWrite(SettingsUrl, J.FormatJSON(AsCompressedJSON));
  finally
    FreeAndNil(J);
  end;
end;

function SfxGain: Single;
begin
  Result := Settings.SfxVolume / MaxVolume;
end;

function MouseLookSensitivity: Single;
const
  { G_BuildTiccmd: mousex = count * (sensitivity + 5) / 10, angleturn -=
    mousex * 8, in 1/65536 of a turn: 0.044 degrees a count at Doom's
    default 5. Twice that, about what Chocolate Doom's mouse acceleration
    gives at normal speeds and CGE's own default (0.1 degrees): a full turn
    is about 4000 pixels, 4 inches of a 1000 DPI mouse at Windows' default
    pointer speed. }
  DegreesPerCount = 2 * 8 * 360 / 65536;
begin
  { Radians per pixel, the unit of MouseLook*Sensitivity. }
  Result := DegToRad(DegreesPerCount * (Settings.MouseSensitivity + 5) / 10);
end;

function MusicGain: Single;
begin
  Result := Settings.MusicVolume / 16;
end;

end.
