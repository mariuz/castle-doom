{ Where save games live. On the desktop they are files under castle-config:
  (the user config directory). In the browser castle-config: is only an
  in-memory file system that is gone when the page reloads, so there the
  JSON text goes to the page's window.localStorage instead (through JOB, the
  JavaScript bridge CGE's web target uses for WebGL and the DOM), keyed by
  the same castle-config: URL. If localStorage is not available (blocked
  storage, private mode quirks) the in-memory castle-config: is used. }
unit GameSaveStorage;

interface

uses Classes;

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

{ In the browser: give Data (bytes, one character each) to the page's
  castleDoomDownload (tools/patch_web_page.py), which saves it as a file.
  False when the page has none, and on other platforms. }
function PageDownload(const FileName, Data, Mime: String): Boolean;

{ Make files given as upload:/NAME (the browser's file picker, --upload)
  outlive the program (DoomWad's OnKeepUpload...): in the browser the
  page script keeps each picked file in IndexedDB and gives it back by
  name (castleDoomStoredFile), on the desktop they are copied to
  castle-config:/uploads/. }
procedure InstallUploadStore;

{ The files the upload store keeps, as NAME=BYTES lines (the caller
  frees the list). }
function StoredUploads: TStringList;

{ The page's file picker (tools/patch_web_page.py's castleDoomOpenFile):
  open it for files of Kind ('iwad', 'pwad', 'demo', 'editwad'); False
  when the page has none (and on other platforms). The chosen file
  arrives later: PageTakeFile gives its kind, name and bytes (the caller
  frees Data), False while nothing waits. }
function PageOpenFile(const Kind: String): Boolean;
function PageTakeFile(out Kind, FileName: String; out Data: TMemoryStream): Boolean;

{ CGE's UserConfig (castle-config:/castle-doom.conf: the last and recent
  WADs) through the save storage, so in the browser it outlives the page
  too (localStorage). }
procedure LoadUserConfig;
procedure SaveUserConfig;

implementation

uses SysUtils,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  CastleLog, CastleDownload, CastleUriUtils, CastleConfig, DoomWad;

function UploadName(const Url: String): String;
begin
  Result := Copy(Url, Length(UploadUrlPrefix) + 1, MaxInt);
end;

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

function PageDownload(const FileName, Data, Mime: String): Boolean;
var
  V: TJOB_JSValue;
  Bytes: UnicodeString;
  I: Integer;
begin
  V := JSWindow.ReadJSPropertyValue('castleDoomDownload');
  Result := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
  if not Result then Exit;
  { A "binary string": one character per byte (not UTF-8 decoded). }
  SetLength(Bytes, Length(Data));
  for I := 1 to Length(Data) do
    Bytes[I] := WideChar(Ord(Data[I]));
  JSWindow.InvokeJSNoResult('castleDoomDownload', [UTF8Decode(FileName), Bytes, UTF8Decode(Mime)]);
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

function PageDownload(const FileName, Data, Mime: String): Boolean;
begin
  Result := false;
end;

{$endif}

{ The upload store ------------------------------------------------------------ }

{$ifdef WASI}

procedure KeepUpload(const Url: String; const Data: TMemoryStream);
begin
  { The page script already keeps what its picker read. }
end;

function RestoreUpload(const Url: String): TMemoryStream;
var
  V: TJOB_JSValue;
  Bytes: UnicodeString;
  I: Integer;
begin
  Result := nil;
  V := JSWindow.ReadJSPropertyValue('castleDoomStoredFile');
  if not ((V is TJOB_Object) and (TJOB_Object(V).Value <> nil)) then
  begin
    FreeAndNil(V);
    Exit;
  end;
  FreeAndNil(V);
  { A binary string (one character per byte), null when not stored. }
  V := JSWindow.InvokeJSValueResult('castleDoomStoredFile', [UTF8Decode(UploadName(Url))]);
  try
    if not (V is TJOB_String) then Exit;
    Bytes := TJOB_String(V).Value;
  finally
    FreeAndNil(V);
  end;
  Result := TMemoryStream.Create;
  Result.Size := Length(Bytes);
  for I := 1 to Length(Bytes) do
    PByte(Result.Memory)[I - 1] := Ord(Bytes[I]) and $FF;
end;

procedure ForgetStoredUpload(const Url: String);
var
  V: TJOB_JSValue;
  HasIt: Boolean;
begin
  V := JSWindow.ReadJSPropertyValue('castleDoomForgetFile');
  HasIt := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
  if HasIt then
    JSWindow.InvokeJSNoResult('castleDoomForgetFile', [UTF8Decode(UploadName(Url))]);
end;

{$else}

function UploadFileName(const Url: String): String;
begin
  Result := UriToFilenameSafe(ResolveCastleConfigUrl('castle-config:/uploads/' + UploadName(Url)));
end;

procedure KeepUpload(const Url: String; const Data: TMemoryStream);
begin
  try
    ForceDirectories(ExtractFilePath(UploadFileName(Url)));
    Data.SaveToFile(UploadFileName(Url));
  except
    on E: Exception do
      WritelnWarning('WAD', 'Cannot keep %s: %s', [Url, E.Message]);
  end;
end;

function RestoreUpload(const Url: String): TMemoryStream;
begin
  Result := nil;
  if (UploadName(Url) = '') or not FileExists(UploadFileName(Url)) then Exit;
  Result := TMemoryStream.Create;
  try
    Result.LoadFromFile(UploadFileName(Url));
  except
    FreeAndNil(Result);
  end;
end;

procedure ForgetStoredUpload(const Url: String);
begin
  if FileExists(UploadFileName(Url)) then
    DeleteFile(UploadFileName(Url));
end;

{$endif}

{$ifdef WASI}
function StoredUploads: TStringList;
var
  V: TJOB_JSValue;
  Text: String;
begin
  Result := TStringList.Create;
  V := JSWindow.ReadJSPropertyValue('castleDoomStoredFiles');
  if not ((V is TJOB_Object) and (TJOB_Object(V).Value <> nil)) then
  begin
    FreeAndNil(V);
    Exit;
  end;
  FreeAndNil(V);
  { "name=bytes" lines. }
  V := JSWindow.InvokeJSValueResult('castleDoomStoredFiles', []);
  try
    if V is TJOB_String then Text := UTF8Encode(TJOB_String(V).Value) else Text := '';
  finally
    FreeAndNil(V);
  end;
  Result.Text := Text;
end;
{$else}
function StoredUploads: TStringList;
var
  Dir: String;
  Info: TSearchRec;
begin
  Result := TStringList.Create;
  Dir := ExtractFilePath(UploadFileName(UploadUrlPrefix + 'x'));
  if FindFirst(Dir + '*', faAnyFile and not faDirectory, Info) = 0 then
  try
    repeat
      if (Info.Attr and faDirectory) = 0 then
        Result.Add(Info.Name + '=' + IntToStr(Info.Size));
    until FindNext(Info) <> 0;
  finally
    FindClose(Info);
  end;
  Result.Sort;
end;
{$endif}

procedure InstallUploadStore;
begin
  OnKeepUpload := @KeepUpload;
  OnRestoreUpload := @RestoreUpload;
  OnForgetUpload := @ForgetStoredUpload;
end;

{ The user config ------------------------------------------------------------- }

const
  UserConfigUrl = 'castle-config:/castle-doom.conf';

procedure LoadUserConfig;
{$ifdef WASI}
var
  Text: String;
{$endif}
begin
  {$ifdef WASI}
  { localStorage's copy into the in-memory castle-config: first. }
  if SaveStorageRead(UserConfigUrl, Text) and (Text <> '') then
    FileWrite(UserConfigUrl, Text);
  {$endif}
  UserConfig.Load;
end;

procedure SaveUserConfig;
{$ifdef WASI}
var
  Text: String;
{$endif}
begin
  UserConfig.Save;
  {$ifdef WASI}
  if FileRead(UserConfigUrl, Text) then
    SaveStorageWrite(UserConfigUrl, Text);
  {$endif}
end;

{ The page's file picker ------------------------------------------------------- }

{$ifdef WASI}
{ A JavaScript function of this name exists on the window. }
function PageHasFunction(const Name: String): Boolean;
var
  V: TJOB_JSValue;
begin
  V := JSWindow.ReadJSPropertyValue(Name);
  Result := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
end;

{ A string the page returns ('' for its null). }
function PageString(const Name: String): UnicodeString;
var
  V: TJOB_JSValue;
begin
  Result := '';
  V := JSWindow.InvokeJSValueResult(Name, []);
  try
    if V is TJOB_String then Result := TJOB_String(V).Value;
  finally
    FreeAndNil(V);
  end;
end;
{$endif}

function PageOpenFile(const Kind: String): Boolean;
begin
  Result := false;
  {$ifdef WASI}
  if not PageHasFunction('castleDoomOpenFile') then Exit;
  JSWindow.InvokeJSNoResult('castleDoomOpenFile', [UTF8Decode(Kind)]);
  Result := true;
  {$endif}
end;

function PageTakeFile(out Kind, FileName: String; out Data: TMemoryStream): Boolean;
{$ifdef WASI}
var
  Head, Bytes: UnicodeString;
  P: Integer;
{$endif}
begin
  Result := false;
  Kind := '';
  FileName := '';
  Data := nil;
  {$ifdef WASI}
  if not PageHasFunction('castleDoomTakeFile') then Exit;
  { First "kind|name", then the bytes as a binary string. }
  Head := PageString('castleDoomTakeFile');
  if Head = '' then Exit;
  P := Pos('|', Head);
  Kind := UTF8Encode(Copy(Head, 1, P - 1));
  FileName := UTF8Encode(Copy(Head, P + 1, MaxInt));
  Bytes := PageString('castleDoomTakeFileBytes');
  Data := TMemoryStream.Create;
  Data.Size := Length(Bytes);
  for P := 1 to Length(Bytes) do
    PByte(Data.Memory)[P - 1] := Ord(Bytes[P]) and $FF;
  Result := true;
  {$endif}
end;

end.
