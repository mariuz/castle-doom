{ Moving saves between installations: every save slot, the quick save and
  the settings in one JSON "bundle"
  ( {"format": "castle-doom-saves", "version": 1,
     "files": {"save1.json": "<the save's JSON text>", ...}} ).
  The web page's "Your saves" section (pages/index.html) reads and writes
  the same format straight from localStorage, the desktop build through the
  Options panel or --export-saves / --import-saves. }
unit GameSaveBundle;

interface

const
  SaveBundleFormat = 'castle-doom-saves';

{ The bundle of every stored save (and settings) as JSON text. Count: how
  many files went in. }
function ExportSaveBundle(out Count: Integer): String;

{ Store every file of a bundle (replacing saves with the same name). False
  when Text is not a bundle; Count is how many files were stored. }
function ImportSaveBundle(const Text: String; out Count: Integer): Boolean;

implementation

uses SysUtils, FpJson, JsonParser, CastleLog, GameSaveStorage;

const
  BundleFiles: array [0..7] of String = ('quicksave.json',
    'save1.json', 'save2.json', 'save3.json', 'save4.json', 'save5.json', 'save6.json',
    'settings.json');

function ExportSaveBundle(out Count: Integer): String;
var
  J, Files: TJSONObject;
  Name, Text: String;
begin
  Count := 0;
  J := TJSONObject.Create;
  try
    J.Add('format', SaveBundleFormat);
    J.Add('version', 1);
    Files := TJSONObject.Create;
    J.Add('files', Files);
    for Name in BundleFiles do
      if SaveStorageRead('castle-config:/' + Name, Text) and (Text <> '') then
      begin
        Files.Add(Name, Text);
        Inc(Count);
      end;
    Result := J.FormatJSON;
  finally
    FreeAndNil(J);
  end;
end;

function IsBundleFile(const Name: String): Boolean;
var
  N: String;
begin
  for N in BundleFiles do
    if N = Name then Exit(true);
  Result := false;
end;

function ImportSaveBundle(const Text: String; out Count: Integer): Boolean;
var
  D: TJSONData;
  J, Files: TJSONObject;
  I: Integer;
begin
  Result := false;
  Count := 0;
  D := nil;
  try
    D := GetJSON(Text);
  except
    on E: Exception do
      WritelnWarning('Save', 'Not a save bundle: %s', [E.Message]);
  end;
  if not (D is TJSONObject) then
  begin
    FreeAndNil(D);
    Exit;
  end;
  J := TJSONObject(D);
  try
    if J.Get('format', '') <> SaveBundleFormat then Exit;
    if J.IndexOfName('files') < 0 then Exit;
    if not (J.Elements['files'] is TJSONObject) then Exit;
    Files := TJSONObject(J.Elements['files']);
    for I := 0 to Files.Count - 1 do
      { Only the known names: a bundle cannot write anywhere else. }
      if IsBundleFile(Files.Names[I]) and (Files.Items[I] is TJSONString) then
      begin
        SaveStorageWrite('castle-config:/' + Files.Names[I], Files.Items[I].AsString);
        Inc(Count);
      end;
    Result := true;
  finally
    FreeAndNil(J);
  end;
end;

end.
