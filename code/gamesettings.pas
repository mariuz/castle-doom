{ Player settings that outlive the session: sound and music volume (Doom's
  0..15 scales), music on / off, light diminishing, mouse look and the
  video options (field of view, fullscreen, UI scale, the browser's render
  resolution). Stored as
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
    { Video: horizontal field of view in degrees (Doom's is 90), window
      or fullscreen (desktop), the 2D layer's scale in percent, and the
      browser's render resolution in percent of the canvas' pixels. }
    FieldOfView: Integer;
    Fullscreen: Boolean;
    UiScale: Integer;
    RenderScale: Integer;
  end;

const
  MaxVolume = 15;
  MinFieldOfView = 60;
  MaxFieldOfView = 120;
  MinUiScale = 50;
  MaxUiScale = 200;
  MinRenderScale = 25;
  MaxRenderScale = 100;

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

{ Apply the video options that belong to the window: fullscreen, the UI
  scale (CastleSettings.xml's reference size divided by it) and, in the
  browser, the render resolution (the page's canvas sizing script, patched
  by tools/patch_web_page.py, multiplies the canvas' pixels by it). The
  field of view is the play view's camera (TViewPlay.ApplyFieldOfView).
  At Startup only turns fullscreen on (CGE's own --fullscreen stays). }
procedure ApplyWindowSettings(const Startup: Boolean = false);

{ The video options for the log. }
function VideoSummary: String;

implementation

uses SysUtils, Math, FpJson, JsonParser, CastleLog, CastleUtils, CastleWindow,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  GameSaveStorage;

const
  { data/CastleSettings.xml's ui_scaling reference size. }
  UiReferenceWidth = 1600;
  UiReferenceHeight = 900;

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
  Settings.FieldOfView := 90;
  Settings.Fullscreen := false;
  Settings.UiScale := 100;
  Settings.RenderScale := 100;
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
    Settings.FieldOfView := Clamped(J.Get('fieldOfView', Settings.FieldOfView), MinFieldOfView, MaxFieldOfView);
    Settings.Fullscreen := J.Get('fullscreen', Settings.Fullscreen);
    Settings.UiScale := Clamped(J.Get('uiScale', Settings.UiScale), MinUiScale, MaxUiScale);
    Settings.RenderScale := Clamped(J.Get('renderScale', Settings.RenderScale), MinRenderScale, MaxRenderScale);
  finally
    FreeAndNil(J);
  end;
  WritelnLog('Settings', 'Sound %d, music %d (%s), light diminishing %s, mouse look %s', [
    Settings.SfxVolume, Settings.MusicVolume, BoolToStr(Settings.MusicOn, 'on', 'off'),
    BoolToStr(Settings.Diminish, 'on', 'off'), BoolToStr(Settings.MouseLook, 'on', 'off')]);
  WritelnLog('Settings', VideoSummary);
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
    J.Add('fieldOfView', Settings.FieldOfView);
    J.Add('fullscreen', Settings.Fullscreen);
    J.Add('uiScale', Settings.UiScale);
    J.Add('renderScale', Settings.RenderScale);
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

function VideoSummary: String;
begin
  Result := Format('Video: field of view %d, %s, UI scale %d%%, render scale %d%%', [
    Settings.FieldOfView, BoolToStr(Settings.Fullscreen, 'fullscreen', 'window'),
    Settings.UiScale, Settings.RenderScale]);
end;

{$ifdef WASI}
{ A JavaScript function of this name exists on Obj (a missing one reads
  as a null TJOB_Object; InvokeJSTypeOf cannot tell, see GameGamepad). }
function HasJSFunction(const Obj: IJSObject; const Name: String): Boolean;
var
  V: TJOB_JSValue;
begin
  V := Obj.ReadJSPropertyValue(Name);
  Result := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
end;
{$endif}

procedure ApplyWindowSettings(const Startup: Boolean);
var
  Window: TCastleWindow;
begin
  Window := Application.MainWindow;
  if Window = nil then Exit;
  Window.Container.UIReferenceWidth := UiReferenceWidth * 100 / Settings.UiScale;
  Window.Container.UIReferenceHeight := UiReferenceHeight * 100 / Settings.UiScale;
  {$ifdef WASI}
  { The page's canvas script (tools/patch_web_page.py) provides
    castleDoomSetScale; CGE's plain page does not. }
  if HasJSFunction(JSWindow, 'castleDoomSetScale') then
    JSWindow.InvokeJSNoResult('castleDoomSetScale', [Settings.RenderScale]);
  {$else}
  { The browser's fullscreen is the page's button (it needs a click). }
  if (Window.FullScreen <> Settings.Fullscreen) and (Settings.Fullscreen or not Startup) then
    Window.FullScreen := Settings.Fullscreen;
  {$endif}
end;

function MusicGain: Single;
begin
  Result := Settings.MusicVolume / 16;
end;

end.
