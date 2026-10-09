{ Where save games live. On the desktop they are files under castle-config:
  (the user config directory). In the browser castle-config: is only an
  in-memory file system that is gone when the page reloads, so there the
  JSON text goes to the page's window.localStorage instead (through JOB, the
  JavaScript bridge CGE's web target uses for WebGL and the DOM), keyed by
  the same castle-config: URL. If localStorage is not available (blocked
  storage, private mode quirks) the in-memory castle-config: is used. }
unit GameSaveStorage;

interface

{ Read the text stored for this castle-config: URL. False when there is none. }
function SaveStorageRead(const Url: String; out Text: String): Boolean;
{ Store the text for this castle-config: URL. }
procedure SaveStorageWrite(const Url, Text: String);
{ Human-readable name of the storage, for the log. }
function SaveStorageName: String;

{ In the browser: the URL of the directory of the page (window.location
  without the file name, query and fragment, ending with "/"), for files
  published next to the game. Empty on other platforms. }
function PageDirectoryUrl: String;

implementation

uses Classes, SysUtils,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  CastleLog, CastleDownload;

function FileRead(const Url: String; out Text: String): Boolean;
var
  S: TStream;
  Str: TStringStream;
begin
  Result := false;
  Text := '';
  try
    S := Download(Url);
  except
    Exit; { no such file }
  end;
  try
    Str := TStringStream.Create('');
    try
      Str.CopyFrom(S, 0);
      Text := Str.DataString;
      Result := true;
    finally
      FreeAndNil(Str);
    end;
  finally
    FreeAndNil(S);
  end;
end;

procedure FileWrite(const Url, Text: String);
var
  S: TStream;
begin
  S := UrlSaveStream(Url);
  try
    if Text <> '' then
      S.WriteBuffer(Text[1], Length(Text));
  finally
    FreeAndNil(S);
  end;
end;

{$ifdef WASI}

const
  KeyPrefix = 'castle-doom:';

var
  { Set when localStorage failed once; then only castle-config: is used. }
  LocalStorageBroken: Boolean;

function LocalStorage: IJSObject;
begin
  Result := JSWindow.ReadJSPropertyObject('localStorage', TJSObject);
end;

function SaveStorageRead(const Url: String; out Text: String): Boolean;
var
  V: TJOB_JSValue;
begin
  if not LocalStorageBroken then
  try
    { getItem returns null for a missing key, so read it as a generic value. }
    V := LocalStorage.InvokeJSValueResult('getItem', [UTF8Decode(KeyPrefix + Url)]);
    try
      Result := V is TJOB_String;
      if Result then
        Text := UTF8Encode(TJOB_String(V).Value)
      else
        Text := '';
    finally
      FreeAndNil(V);
    end;
    Exit;
  except
    on E: Exception do
    begin
      WritelnWarning('Save', 'localStorage not available, saves will not persist: %s', [E.Message]);
      LocalStorageBroken := true;
    end;
  end;
  Result := FileRead(Url, Text);
end;

procedure SaveStorageWrite(const Url, Text: String);
begin
  if not LocalStorageBroken then
  try
    LocalStorage.InvokeJSNoResult('setItem', [UTF8Decode(KeyPrefix + Url), UTF8Decode(Text)]);
    Exit;
  except
    on E: Exception do
    begin
      WritelnWarning('Save', 'Cannot write to localStorage, saves will not persist: %s', [E.Message]);
      LocalStorageBroken := true;
    end;
  end;
  FileWrite(Url, Text);
end;

function PageDirectoryUrl: String;
var
  Href: String;
  P: Integer;
begin
  Href := UTF8Encode(JSWindow.ReadJSPropertyObject('location', TJSObject).ReadJSPropertyUnicodeString('href'));
  P := Pos('#', Href);
  if P > 0 then Href := Copy(Href, 1, P - 1);
  P := Pos('?', Href);
  if P > 0 then Href := Copy(Href, 1, P - 1);
  P := LastDelimiter('/', Href);
  Result := Copy(Href, 1, P);
end;

function SaveStorageName: String;
begin
  if LocalStorageBroken then
    Result := 'in-memory castle-config: (lost on reload)'
  else
    Result := 'browser localStorage';
end;

{$else}

function SaveStorageRead(const Url: String; out Text: String): Boolean;
begin
  Result := FileRead(Url, Text);
end;

procedure SaveStorageWrite(const Url, Text: String);
begin
  FileWrite(Url, Text);
end;

function SaveStorageName: String;
begin
  Result := 'castle-config: files';
end;

function PageDirectoryUrl: String;
begin
  Result := '';
end;

{$endif}

end.
