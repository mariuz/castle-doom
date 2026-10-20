{ Writing WADs: little-endian lump fields, a map's BLOCKMAP and the PWAD
  file around a list of lumps. Shared by the random maps (DoomRandomMap)
  and the map editor's export (DoomEditMap). }
unit DoomWadWriter;

interface

uses Classes, SysUtils;

procedure W16(const S: TStream; const V: Integer);
procedure W32(const S: TStream; const V: Integer);
{ An 8-byte, NUL padded, upper case lump or texture name. }
procedure WName(const S: TStream; const Name: String);

{ A PWAD of the lumps (Names[i] holding the TMemoryStream Data[i]). }
function MakePwad(const Names: TStrings; const Data: TList): TMemoryStream;

type
  TBlockmapLine = record
    X1, Y1, X2, Y2: Integer;
  end;

{ Doom's BLOCKMAP: 128-unit blocks from just below the lines' lowest
  corner, each listing the lines whose bounding box touches it (what
  idbsp wrote; ports test the lines themselves). }
procedure WriteBlockmap(const S: TStream; const Lines: array of TBlockmapLine);

implementation

uses Math;

procedure W16(const S: TStream; const V: Integer);
var
  Wd: Word;
begin
  Wd := Word(V and $FFFF);
  S.WriteBuffer(Wd, 2);
end;

procedure W32(const S: TStream; const V: Integer);
var
  L: LongInt;
begin
  L := V;
  S.WriteBuffer(L, 4);
end;

procedure WName(const S: TStream; const Name: String);
var
  B: array [0..7] of Byte;
  I: Integer;
begin
  FillChar(B, SizeOf(B), 0);
  for I := 1 to Min(8, Length(Name)) do
    B[I - 1] := Ord(UpCase(Name[I]));
  S.WriteBuffer(B, 8);
end;

function MakePwad(const Names: TStrings; const Data: TList): TMemoryStream;
var
  I, Offset: Integer;
begin
  Result := TMemoryStream.Create;
  Result.WriteBuffer(PChar('PWAD')^, 4);
  W32(Result, Names.Count);
  W32(Result, 0); { the directory's offset, below }
  for I := 0 to Data.Count - 1 do
    Result.CopyFrom(TMemoryStream(Data[I]), 0);
  Offset := 12;
  for I := 0 to Names.Count - 1 do
  begin
    W32(Result, Offset);
    W32(Result, TMemoryStream(Data[I]).Size);
    WName(Result, Names[I]);
    Inc(Offset, TMemoryStream(Data[I]).Size);
  end;
  Result.Position := 8;
  W32(Result, Result.Size - 16 * Names.Count);
  Result.Position := 0;
end;

procedure WriteBlockmap(const S: TStream; const Lines: array of TBlockmapLine);
var
  OX, OY, BW, BH, MaxX, MaxY, I, J, K, BX, BY, X0, X1, Y0, Y1, Offset: Integer;
  Blocks: array of array of Integer;
begin
  OX := MaxInt;
  OY := MaxInt;
  MaxX := -MaxInt;
  MaxY := -MaxInt;
  for I := 0 to High(Lines) do
  begin
    OX := Min(OX, Min(Lines[I].X1, Lines[I].X2));
    OY := Min(OY, Min(Lines[I].Y1, Lines[I].Y2));
    MaxX := Max(MaxX, Max(Lines[I].X1, Lines[I].X2));
    MaxY := Max(MaxY, Max(Lines[I].Y1, Lines[I].Y2));
  end;
  if Length(Lines) = 0 then
  begin
    OX := 0; OY := 0; MaxX := 0; MaxY := 0;
  end;
  OX := OX - 8;
  OY := OY - 8;
  BW := (MaxX - OX) div 128 + 1;
  BH := (MaxY - OY) div 128 + 1;
  SetLength(Blocks, BW * BH);
  for I := 0 to High(Lines) do
  begin
    X0 := (Min(Lines[I].X1, Lines[I].X2) - OX) div 128;
    X1 := (Max(Lines[I].X1, Lines[I].X2) - OX) div 128;
    Y0 := (Min(Lines[I].Y1, Lines[I].Y2) - OY) div 128;
    Y1 := (Max(Lines[I].Y1, Lines[I].Y2) - OY) div 128;
    for BY := Y0 to Y1 do
      for BX := X0 to X1 do
      begin
        K := BY * BW + BX;
        SetLength(Blocks[K], Length(Blocks[K]) + 1);
        Blocks[K][High(Blocks[K])] := I;
      end;
  end;
  W16(S, OX); W16(S, OY); W16(S, BW); W16(S, BH);
  Offset := 4 + BW * BH;
  for K := 0 to High(Blocks) do
  begin
    W16(S, Offset);
    Inc(Offset, Length(Blocks[K]) + 2);
  end;
  for K := 0 to High(Blocks) do
  begin
    W16(S, 0);
    for J := 0 to High(Blocks[K]) do W16(S, Blocks[K][J]);
    W16(S, $FFFF);
  end;
end;

end.
