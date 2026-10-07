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
  public
    { Load the IWAD (castle-data:/..., file:///..., or a plain path). }
    constructor Create(const AUrl: String);
    destructor Destroy; override;
    { Stack a PWAD on top; its lumps override earlier ones by name. }
    procedure AddFile(const AUrl: String);

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

{ Decode an 8-byte, NUL padded Doom name. }
function DoomName(const P: PByte): String;

implementation

uses Math, CastleDownload, CastleLog, CastleUtils, CastleClassUtils, CastleUriUtils;

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
begin
  FileUrl := AUrl;
  { Plain file names (from the command line) become file:// URLs. }
  if (Pos(':', FileUrl) = 0) or ((Length(FileUrl) > 1) and (FileUrl[2] = ':')) then
    FileUrl := FilenameToUriSafe(FileUrl);
  Data := TMemoryStream.Create;
  try
    Source := Download(FileUrl);
    try
      Data.CopyFrom(Source, 0);
    finally
      FreeAndNil(Source);
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
    { A map marker is immediately followed by THINGS. }
    if (FLumps[I + 1].Name = 'THINGS') and
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
begin
  Result := '';
  for I := 0 to FFileUrls.Count - 1 do
  begin
    if I > 0 then Result := Result + ' + ';
    Result := Result + ExtractUriName(FFileUrls[I]);
  end;
end;

end.
