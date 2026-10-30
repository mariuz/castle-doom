{ Reading Doom WAD files (IWAD / PWAD): the lump directory and the palette.

  A WAD is a flat archive: a 12-byte header, then lump data, then a directory
  of (offset, size, 8-char name) entries. Everything else in Doom (maps,
  textures, sprites, sounds) is just a convention over lump names and order.

  Several files can be stacked: the IWAD first, then PWADs. Lumps are looked
  up from the last file backwards, so a PWAD's E1M1, TEXTURE1, sprites or
  sounds replace the IWAD's, like Doom's -file. }
unit DoomWad;

interface

uses SysUtils, Classes,
  CastleVectors, CastleStringUtils;

type
  TWadLump = record
    Name: String;
    Offset: Int32;
    Size: Int32;
    FileIndex: Integer;
  end;

  TDoomWad = class
  strict private
    FFiles: array of TMemoryStream;
    FFileUrls: TStringList;
    FLumps: array of TWadLump;
    FPalette: array [0..255] of TVector4Byte;
    FIsDoom2: Boolean;
    FMapNames: TStringList;
    procedure ReadDirectory(const FileIndex: Integer);
    procedure ReadPalette;
    procedure CollectMapNames;
    function CollectResourceNames(const Textures, Flats: Boolean): TStringList;
  public
    { Load the IWAD (castle-data:/..., file:///..., or a plain path). }
    constructor Create(const AUrl: String);
    destructor Destroy; override;
    { Stack a PWAD on top; its lumps override earlier ones by name.
      random:/SEED is generated (DoomRandomMap), not read. }
    procedure AddFile(const AUrl: String);
    { Take the last file off the stack (the map editor's play-test PWAD,
      edit:/MAP, when the editor takes over again). Never the IWAD. }
    procedure RemoveLastFile;
    { The textures (TEXTURE1 / TEXTURE2) and the flats, sorted, for the
      map editor's choices. }
    function TextureNames: TStringList;
    function FlatNames: TStringList;
    { The bytes of a loaded file (0 = the IWAD). }
    function FileData(const Index: Integer): TMemoryStream;
    { The names of all textures (TEXTURE1 / TEXTURE2) and flats, sorted. }
    function ResourceNames: TStringList;

    function LumpCount: Integer;
    function LumpName(const Index: Integer): String;
    function LumpSize(const Index: Integer): Integer;
    { Pointer to the raw lump bytes (valid as long as this TDoomWad lives). }
    function LumpPointer(const Index: Integer): PByte;
    { Index of the last lump with this name (later files win), -1 if none. }
    function FindLump(const Name: String): Integer;
    { Index of the first lump with this name at or after StartFrom, -1 if none. }
    function FindLumpForward(const Name: String; const StartFrom: Integer = 0): Integer;
    { Like FindLump but raises an exception when the lump is missing. }
    function LumpIndex(const Name: String): Integer;
    function HasLump(const Name: String): Boolean;
    { Copy of the lump as a byte string (handy for small lumps). }
    function LumpBytes(const Index: Integer): TBytes;

    { Palette 0 of PLAYPAL, as opaque RGBA. }
    function PaletteColor(const Index: Byte): TVector4Byte;
    { PLAYPAL palette PalIndex (1..13: damage reds, bonus golds, radiation
      green) as a blend of palette 0 towards Color by Amount (0..1), solved
      from the black and white entries. False when the WAD has no such
      palette. }
    function PaletteTint(const PalIndex: Integer; out Color: TVector3; out Amount: Single): Boolean;
    { A colormap lump (Boom's 242 underwater maps) as a blend towards one
      colour: row 0 maps every palette colour p to about
      p + (Color - p) * Amount (fitted by least squares). False when the
      lump is missing or too small. }
    function ColormapTint(const Name: String; out Color: TVector3; out Amount: Single): Boolean;
    { URL of the IWAD. }
    function Url: String;
    { All loaded files, IWAD first. }
    property FileUrls: TStringList read FFileUrls;
    { Short description like "freedoom1.wad + mymap.wad". }
    function Description: String;
    { True when the WAD holds MAPxx levels (Doom 2 / Freedoom Phase 2). }
    property IsDoom2: Boolean read FIsDoom2;
    { Names of all map marker lumps (E1M1..., MAP01...), in WAD order. }
    property MapNames: TStringList read FMapNames;
  end;

const
  { Files the user gave without a path the program can read (the
    browser's file picker): their bytes are kept in memory under
    upload:/NAME for TDoomWad.AddFile. }
  UploadUrlPrefix = 'upload:/';

function IsUploadUrl(const Url: String): Boolean;
function UploadUrl(const FileName: String): String;
{ Keep a copy of Data as upload:/FileName; returns that URL. }
function RegisterUpload(const FileName: String; const Data: TStream): String;
{ False only for an upload:/ URL whose bytes are gone (a reloaded page):
  check before AddFile where an exception must not happen (the web). }
function WadUrlAvailable(const Url: String): Boolean;
{ The bytes of an upload:/ URL as a string; False when there are none. }
function UploadText(const Url: String; out Text: String): Boolean;
{ A WAD URL AddFile can read: an existing file, an upload:/ the memory
  or the store has, the map editor's edit:/ PWADs and random:/ maps
  (made on demand). }
function WadUrlReadable(const Url: String): Boolean;
{ The maps a WAD file holds (markers followed by THINGS), read from its
  directory alone (a PWAD needs no IWAD for this); nil when it is not a
  WAD. The caller frees the list. }
function WadFileMapNames(const Url: String): TStringList;
{ Drop an upload:/ URL's bytes, here and in the store (OnForgetUpload). }
procedure ForgetUpload(const Url: String);

var
  { Where uploads outlive the program (GameSaveStorage installs them: the
    browser's IndexedDB, through the page script, or castle-config:
    files): RegisterUpload keeps each new one, an upload:/ URL not in
    memory is restored from there (nil: none), ForgetUpload drops it. }
  OnKeepUpload: procedure(const Url: String; const Data: TMemoryStream);
  OnRestoreUpload: function(const Url: String): TMemoryStream;
  OnForgetUpload: procedure(const Url: String);

{ Decode an 8-byte, NUL padded Doom name. }
function DoomName(const P: PByte): String;

implementation

uses Math, CastleDownload, CastleLog, CastleUtils, CastleClassUtils, CastleUriUtils,
  DoomRandomMap, DoomEditMap;

var
  Uploads: TStringList;

function IsUploadUrl(const Url: String): Boolean;
begin
  Result := SameText(Copy(Url, 1, Length(UploadUrlPrefix)), UploadUrlPrefix);
end;

function UploadUrl(const FileName: String): String;
begin
  Result := UploadUrlPrefix + ExtractFileName(FileName);
end;

{ The upload's index in Uploads, restored from the store when it is
  not in memory (a reloaded page); -1 when it is nowhere. }
function FindUpload(const Url: String): Integer;
var
  Restored: TMemoryStream;
begin
  Result := Uploads.IndexOf(Url);
  if (Result >= 0) or not Assigned(OnRestoreUpload) then Exit;
  Restored := OnRestoreUpload(Url);
  if Restored = nil then Exit;
  Restored.Position := 0;
  Result := Uploads.AddObject(Url, Restored);
  WritelnLog('WAD', 'Restored %s (%d bytes) from the stored uploads', [Url, Restored.Size]);
end;

procedure ForgetUpload(const Url: String);
var
  I: Integer;
begin
  I := Uploads.IndexOf(Url);
  { The list owns the streams. }
  if I >= 0 then Uploads.Delete(I);
  if Assigned(OnForgetUpload) then OnForgetUpload(Url);
  WritelnLog('WAD', 'Forgot %s', [Url]);
end;

function RegisterUpload(const FileName: String; const Data: TStream): String;
var
  Copied: TMemoryStream;
  I: Integer;
begin
  Result := UploadUrl(FileName);
  Copied := TMemoryStream.Create;
  Copied.CopyFrom(Data, 0);
  Copied.Position := 0;
  I := Uploads.IndexOf(Result);
  if I >= 0 then
  begin
    Uploads.Objects[I].Free;
    Uploads.Objects[I] := Copied;
  end else
    Uploads.AddObject(Result, Copied);
  WritelnLog('WAD', 'Uploaded %s (%d bytes)', [Result, Copied.Size]);
  if Assigned(OnKeepUpload) then OnKeepUpload(Result, Copied);
end;

function WadUrlAvailable(const Url: String): Boolean;
begin
  Result := (not IsUploadUrl(Url)) or (FindUpload(Url) >= 0);
end;

function WadUrlReadable(const Url: String): Boolean;
var
  EditedMap: String;
  Seed: Cardinal;
  Data: TMemoryStream;
begin
  if IsUploadUrl(Url) then Exit(FindUpload(Url) >= 0);
  if IsRandomWadUrl(Url, Seed) then Exit(true);
  if IsEditedWadUrl(Url, EditedMap) then
  begin
    Data := EditedWadData(EditedMap);
    Result := Data <> nil;
    FreeAndNil(Data);
    Exit;
  end;
  Result := UriFileExists(Url);
end;

function WadFileMapNames(const Url: String): TStringList;
var
  Text, Name, Prev: String;
  S: TStream;
  Count, DirPos, I: Integer;

  function Int32At(const P: Integer): Integer;
  begin
    Result := PLongInt(@Text[P + 1])^;
  end;

begin
  Result := nil;
  if IsUploadUrl(Url) then
  begin
    if not UploadText(Url, Text) then Exit;
  end else
  begin
    if not UriFileExists(Url) then Exit;
    S := Download(Url);
    try
      SetLength(Text, S.Size);
      if S.Size > 0 then S.ReadBuffer(Text[1], S.Size);
    finally
      FreeAndNil(S);
    end;
  end;
  if (Length(Text) < 12) or ((Copy(Text, 1, 4) <> 'PWAD') and (Copy(Text, 1, 4) <> 'IWAD')) then Exit;
  Count := Int32At(4);
  DirPos := Int32At(8);
  if (Count < 0) or (DirPos < 12) or (Int64(DirPos) + Int64(Count) * 16 > Length(Text)) then Exit;
  Result := TStringList.Create;
  Prev := '';
  for I := 0 to Count - 1 do
  begin
    Name := DoomName(PByte(@Text[DirPos + I * 16 + 9]));
    { THINGS after the marker, or a UDMF map's TEXTMAP. }
    if ((Name = 'THINGS') or (Name = 'TEXTMAP')) and (Prev <> '') then
      Result.Add(Prev);
    Prev := Name;
  end;
end;

function UploadText(const Url: String; out Text: String): Boolean;
var
  I: Integer;
  M: TMemoryStream;
begin
  Text := '';
  I := FindUpload(Url);
  Result := I >= 0;
  if not Result then Exit;
  M := TMemoryStream(Uploads.Objects[I]);
  SetLength(Text, M.Size);
  if M.Size > 0 then
    Move(M.Memory^, Text[1], M.Size);
end;

function DoomName(const P: PByte): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to 7 do
  begin
    if P[I] = 0 then Break;
    Result := Result + UpCase(Chr(P[I]));
  end;
end;

{ TDoomWad ------------------------------------------------------------------- }

constructor TDoomWad.Create(const AUrl: String);
begin
  inherited Create;
  FFileUrls := TStringList.Create;
  FMapNames := TStringList.Create;
  AddFile(AUrl);
end;

destructor TDoomWad.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(FFiles) do
    FreeAndNil(FFiles[I]);
  FreeAndNil(FMapNames);
  FreeAndNil(FFileUrls);
  inherited;
end;

procedure TDoomWad.AddFile(const AUrl: String);
var
  Source: TStream;
  Data: TMemoryStream;
  FileUrl: String;
  Seed: Cardinal;
  Names, Log: TStringList;
  I: Integer;
  EditedMap: String;
begin
  FileUrl := AUrl;
  { Plain file names (from the command line) become file:// URLs. }
  if (Pos(':', FileUrl) = 0) or ((Length(FileUrl) > 1) and (FileUrl[2] = ':')) then
    FileUrl := FilenameToUriSafe(FileUrl);
  Data := nil;
  try
    if IsRandomWadUrl(FileUrl, Seed) then
    begin
      { Generated maps, with the textures of the WADs loaded so far. }
      if Length(FFiles) = 0 then
        raise Exception.Create('Random maps need an IWAD first');
      FileUrl := RandomWadUrl(Seed);
      Names := ResourceNames;
      Log := TStringList.Create;
      try
        Data := BuildRandomWad(Seed, FIsDoom2, Names, Log);
        for I := 0 to Log.Count - 1 do
          WritelnLog('Random', Log[I]);
      finally
        FreeAndNil(Log);
        FreeAndNil(Names);
      end;
    end else
    if IsUploadUrl(FileUrl) then
    begin
      I := FindUpload(FileUrl);
      if I < 0 then
        raise Exception.CreateFmt('%s is gone; choose the file again', [FileUrl]);
      Data := TMemoryStream.Create;
      Data.CopyFrom(TMemoryStream(Uploads.Objects[I]), 0);
    end else
    if IsEditedWadUrl(FileUrl, EditedMap) then
    begin
      { The map editor's map (play-test), kept in memory. }
      Data := EditedWadData(EditedMap);
      if Data = nil then
        raise Exception.CreateFmt('The map editor has no %s now', [EditedMap]);
    end else
    begin
      Data := TMemoryStream.Create;
      Source := Download(FileUrl);
      try
        Data.CopyFrom(Source, 0);
      finally
        FreeAndNil(Source);
      end;
    end;
    Data.Position := 0;
    SetLength(FFiles, Length(FFiles) + 1);
    FFiles[High(FFiles)] := Data;
    Data := nil;
    FFileUrls.Add(FileUrl);
    ReadDirectory(High(FFiles));
  finally
    FreeAndNil(Data);
  end;
  ReadPalette;
  CollectMapNames;
  WritelnLog('WAD', 'Loaded %s: %d lumps total, %d maps, %s', [
    FileUrl, Length(FLumps), FMapNames.Count, Iff(FIsDoom2, 'MAPxx (Doom 2) layout', 'ExMy (Doom 1) layout')]);
end;

procedure TDoomWad.ReadDirectory(const FileIndex: Integer);
var
  Header: PByte;
  Count, DirOffset, I, Base: Int32;
  Entry: PByte;
  Ident: String;
  Data: TMemoryStream;
begin
  Data := FFiles[FileIndex];
  if Data.Size < 12 then
    raise Exception.CreateFmt('File too small to be a WAD: %s', [FFileUrls[FileIndex]]);
  Header := PByte(Data.Memory);
  Ident := Chr(Header[0]) + Chr(Header[1]) + Chr(Header[2]) + Chr(Header[3]);
  if (Ident <> 'IWAD') and (Ident <> 'PWAD') then
    raise Exception.CreateFmt('Not a WAD file (bad magic "%s"): %s', [Ident, FFileUrls[FileIndex]]);
  Count := PInt32(Header + 4)^;
  DirOffset := PInt32(Header + 8)^;
  if (Count < 0) or (DirOffset < 0) or (Int64(DirOffset) + Int64(Count) * 16 > Data.Size) then
    raise Exception.CreateFmt('Corrupt WAD directory: %s', [FFileUrls[FileIndex]]);
  Base := Length(FLumps);
  SetLength(FLumps, Base + Count);
  for I := 0 to Count - 1 do
  begin
    Entry := Header + DirOffset + I * 16;
    FLumps[Base + I].Offset := PInt32(Entry)^;
    FLumps[Base + I].Size := PInt32(Entry + 4)^;
    FLumps[Base + I].Name := DoomName(Entry + 8);
    FLumps[Base + I].FileIndex := FileIndex;
    if (FLumps[Base + I].Offset < 0) or (FLumps[Base + I].Size < 0) or
       (Int64(FLumps[Base + I].Offset) + FLumps[Base + I].Size > Data.Size) then
    begin
      FLumps[Base + I].Offset := 0;
      FLumps[Base + I].Size := 0;
    end;
  end;
end;

procedure TDoomWad.ReadPalette;
var
  Index: Integer;
  P: PByte;
  I: Integer;
begin
  Index := FindLump('PLAYPAL');
  if (Index < 0) or (LumpSize(Index) < 768) then
  begin
    if Length(FFiles) = 1 then
      raise Exception.Create('WAD has no PLAYPAL palette (is this an IWAD?)');
    Exit;
  end;
  P := LumpPointer(Index);
  for I := 0 to 255 do
    FPalette[I] := Vector4Byte(P[I * 3], P[I * 3 + 1], P[I * 3 + 2], 255);
end;

procedure TDoomWad.CollectMapNames;
var
  I: Integer;
  N: String;
begin
  FMapNames.Clear;
  FIsDoom2 := false;
  for I := 0 to High(FLumps) - 1 do
  begin
    N := FLumps[I].Name;
    { A map marker is immediately followed by THINGS (or TEXTMAP: UDMF). }
    if ((FLumps[I + 1].Name = 'THINGS') or (FLumps[I + 1].Name = 'TEXTMAP')) and
       ( ((Length(N) = 4) and (N[1] = 'E') and (N[3] = 'M')) or
         ((Length(N) = 5) and (Copy(N, 1, 3) = 'MAP')) ) then
    begin
      if FMapNames.IndexOf(N) < 0 then
        FMapNames.Add(N);
      if Copy(N, 1, 3) = 'MAP' then
        FIsDoom2 := true;
    end;
  end;
  FMapNames.Sort;
end;

function TDoomWad.FileData(const Index: Integer): TMemoryStream;
begin
  Result := FFiles[Index];
end;

procedure TDoomWad.RemoveLastFile;
var
  N, I: Integer;
begin
  if Length(FFiles) <= 1 then Exit;
  N := High(FFiles);
  I := Length(FLumps);
  while (I > 0) and (FLumps[I - 1].FileIndex = N) do
    Dec(I);
  SetLength(FLumps, I);
  FreeAndNil(FFiles[N]);
  SetLength(FFiles, N);
  WritelnLog('WAD', 'Removed %s', [FFileUrls[N]]);
  FFileUrls.Delete(N);
  ReadPalette;
  CollectMapNames;
end;

function TDoomWad.TextureNames: TStringList;
begin
  Result := CollectResourceNames(true, false);
end;

function TDoomWad.FlatNames: TStringList;
begin
  Result := CollectResourceNames(false, true);
end;

function TDoomWad.ResourceNames: TStringList;
begin
  Result := CollectResourceNames(true, true);
end;

function TDoomWad.CollectResourceNames(const Textures, Flats: Boolean): TStringList;
var
  I, J, N, Offset: Integer;
  P: PByte;
  InFlats: Boolean;
begin
  Result := TStringList.Create;
  Result.Sorted := true;
  Result.Duplicates := dupIgnore;
  InFlats := false;
  for I := 0 to High(FLumps) do
  begin
    if (FLumps[I].Name = 'TEXTURE1') or (FLumps[I].Name = 'TEXTURE2') then
    begin
      if not Textures then Continue;
      P := LumpPointer(I);
      if FLumps[I].Size < 4 then Continue;
      N := PInt32(P)^;
      for J := 0 to N - 1 do
      begin
        if 4 + J * 4 + 4 > FLumps[I].Size then Break;
        Offset := PInt32(P + 4 + J * 4)^;
        if (Offset >= 0) and (Offset + 8 <= FLumps[I].Size) then
          Result.Add(DoomName(P + Offset));
      end;
    end
    else if (FLumps[I].Name = 'F_START') or (FLumps[I].Name = 'FF_START') then InFlats := true
    else if (FLumps[I].Name = 'F_END') or (FLumps[I].Name = 'FF_END') then InFlats := false
    else if Flats and InFlats and (FLumps[I].Size > 0) then
      Result.Add(FLumps[I].Name);
  end;
end;

function TDoomWad.LumpCount: Integer;
begin
  Result := Length(FLumps);
end;

function TDoomWad.LumpName(const Index: Integer): String;
begin
  Result := FLumps[Index].Name;
end;

function TDoomWad.LumpSize(const Index: Integer): Integer;
begin
  Result := FLumps[Index].Size;
end;

function TDoomWad.LumpPointer(const Index: Integer): PByte;
begin
  Result := PByte(FFiles[FLumps[Index].FileIndex].Memory) + FLumps[Index].Offset;
end;

function TDoomWad.FindLump(const Name: String): Integer;
var
  I: Integer;
  U: String;
begin
  U := UpperCase(Name);
  for I := High(FLumps) downto 0 do
    if FLumps[I].Name = U then
      Exit(I);
  Result := -1;
end;

function TDoomWad.FindLumpForward(const Name: String; const StartFrom: Integer): Integer;
var
  I: Integer;
  U: String;
begin
  U := UpperCase(Name);
  for I := Max(StartFrom, 0) to High(FLumps) do
    if FLumps[I].Name = U then
      Exit(I);
  Result := -1;
end;

function TDoomWad.LumpIndex(const Name: String): Integer;
begin
  Result := FindLump(Name);
  if Result < 0 then
    raise Exception.CreateFmt('Lump "%s" not found in %s', [Name, Description]);
end;

function TDoomWad.HasLump(const Name: String): Boolean;
begin
  Result := FindLump(Name) >= 0;
end;

function TDoomWad.LumpBytes(const Index: Integer): TBytes;
begin
  SetLength(Result, FLumps[Index].Size);
  if FLumps[Index].Size > 0 then
    Move(LumpPointer(Index)^, Result[0], FLumps[Index].Size);
end;

function TDoomWad.ColormapTint(const Name: String; out Color: TVector3; out Amount: Single): Boolean;
var
  Pal, Map, I, C: Integer;
  P, M: PByte;
  X, Y, SX, SY, SXX, SXY, Slope, Offset, SlopeSum: Single;
  Offsets: TVector3;
begin
  Result := false;
  Color := Vector3(0, 0, 0);
  Amount := 0;
  Pal := FindLump('PLAYPAL');
  Map := FindLump(Name);
  if (Pal < 0) or (Map < 0) or (LumpSize(Pal) < 768) or (LumpSize(Map) < 256) then Exit;
  P := LumpPointer(Pal);
  M := LumpPointer(Map);
  { Per channel out = Slope * in + Offset; the blend is Slope = 1 - Amount,
    Offset = Color * Amount. }
  SlopeSum := 0;
  for C := 0 to 2 do
  begin
    SX := 0; SY := 0; SXX := 0; SXY := 0;
    for I := 0 to 255 do
    begin
      X := P[I * 3 + C] / 255;
      Y := P[M[I] * 3 + C] / 255;
      SX := SX + X; SY := SY + Y; SXX := SXX + X * X; SXY := SXY + X * Y;
    end;
    if Abs(256 * SXX - SX * SX) < 1e-6 then Exit;
    Slope := (256 * SXY - SX * SY) / (256 * SXX - SX * SX);
    Offset := (SY - Slope * SX) / 256;
    SlopeSum := SlopeSum + Slope;
    Offsets.Data[C] := Offset;
  end;
  Amount := Clamped(1 - SlopeSum / 3, 0, 1);
  if Amount < 0.01 then Exit;
  for C := 0 to 2 do
    Color.Data[C] := Clamped(Offsets.Data[C] / Amount, 0, 1);
  Result := true;
end;

function TDoomWad.PaletteTint(const PalIndex: Integer; out Color: TVector3; out Amount: Single): Boolean;
var
  Lump, I, Dark, Bright, C, N, Sum, DarkSum, BrightSum: Integer;
  P: PByte;
  A: Single;
begin
  Result := false;
  Color := Vector3(0, 0, 0);
  Amount := 0;
  Lump := FindLump('PLAYPAL');
  if (Lump < 0) or (LumpSize(Lump) < (PalIndex + 1) * 768) then Exit;
  P := LumpPointer(Lump);
  { The darkest and the brightest colour of palette 0. }
  Dark := 0;
  Bright := 0;
  DarkSum := MaxInt;
  BrightSum := -1;
  for I := 0 to 255 do
  begin
    Sum := P[I * 3] + P[I * 3 + 1] + P[I * 3 + 2];
    if Sum < DarkSum then begin DarkSum := Sum; Dark := I; end;
    if Sum > BrightSum then begin BrightSum := Sum; Bright := I; end;
  end;
  { Palette k = base + (tint - base) * a: the bright - dark spread shrinks
    by (1 - a), and the dark entry moves to dark + (tint - dark) * a. }
  A := 0;
  N := 0;
  for C := 0 to 2 do
    if P[Bright * 3 + C] > P[Dark * 3 + C] then
    begin
      A := A + 1 - (P[PalIndex * 768 + Bright * 3 + C] - P[PalIndex * 768 + Dark * 3 + C]) /
        (P[Bright * 3 + C] - P[Dark * 3 + C]);
      Inc(N);
    end;
  if N = 0 then Exit;
  A := A / N;
  if A <= 0.001 then Exit;
  for C := 0 to 2 do
    Color.Data[C] := Clamped((P[PalIndex * 768 + Dark * 3 + C] - P[Dark * 3 + C] * (1 - A)) / A, 0, 255) / 255;
  Amount := Min(1, A);
  Result := true;
end;

function TDoomWad.PaletteColor(const Index: Byte): TVector4Byte;
begin
  Result := FPalette[Index];
end;

function TDoomWad.Url: String;
begin
  if FFileUrls.Count > 0 then Result := FFileUrls[0] else Result := '';
end;

function TDoomWad.Description: String;
var
  I: Integer;
  Seed: Cardinal;
  EditedMap: String;
begin
  Result := '';
  for I := 0 to FFileUrls.Count - 1 do
  begin
    if I > 0 then Result := Result + ' + ';
    if IsRandomWadUrl(FFileUrls[I], Seed) then
      Result := Result + 'random maps ' + IntToStr(Seed)
    else if IsEditedWadUrl(FFileUrls[I], EditedMap) then
      Result := Result + 'edited ' + EditedMap
    else
      Result := Result + ExtractUriName(FFileUrls[I]);
  end;
end;

initialization
  Uploads := TStringList.Create;
  Uploads.OwnsObjects := true;
  Uploads.CaseSensitive := false;
finalization
  FreeAndNil(Uploads);
end.
