{ Nuked OPL3 (https://github.com/nukeykt/Nuked-OPL3, LGPL 2.1) as a shared
  library loaded at runtime: libnukedopl3.so / nukedopl3.dll /
  libnukedopl3.dylib from data/lib (tools/build_nuked_opl3.sh builds it, CI
  packages it next to the game with its licence). Castle DOOM itself stays
  MIT: nothing of the emulator is compiled in, the library is optional (the
  built-in FM model plays when it is missing, and always on the web, where
  there is no dynamic linking), and users may replace it with their own
  build. }
unit DoomOpl3;

interface

type
  { One emulated YM3812/YMF262 chip rendering at a sample rate. }
  TOpl3Chip = class
  strict private
    FChip: Pointer;
  public
    constructor Create(const SampleRate: Cardinal);
    destructor Destroy; override;
    { OPL3 register write (0x000..0x1FF; bank 1 is 0x100 + register). }
    procedure WriteReg(const Reg: Word; const Value: Byte);
    { Count stereo samples (2 * Count SmallInts) at the Create sample rate. }
    procedure Generate(const Buffer: PSmallInt; const Count: Integer);
  end;

{ Try loading the library (once) and tell whether chips can be made. }
function Opl3Available: Boolean;
{ Where the library was found, or why not (for the log). }
function Opl3Status: String;
{ The library's file name on this platform. }
function Opl3LibraryName: String;

implementation

uses SysUtils, {$ifndef WASI} DynLibs, {$endif}
  CastleUriUtils, CastleFilesUtils;

type
  TOpl3Reset = procedure(Chip: Pointer; SampleRate: LongWord); cdecl;
  TOpl3WriteReg = procedure(Chip: Pointer; Reg: Word; Value: Byte); cdecl;
  TOpl3GenerateStream = procedure(Chip: Pointer; Buffer: PSmallInt; Count: LongWord); cdecl;

const
  { sizeof(opl3_chip) is 20960 in Nuked OPL3 1.8 (with OPL_WRITEBUF_SIZE
    1024); allocate plenty so a newer library still fits. }
  ChipBytes = 256 * 1024;

var
  Tried: Boolean;
  Status: String;
  ChipReset: TOpl3Reset;
  ChipWriteReg: TOpl3WriteReg;
  ChipGenerate: TOpl3GenerateStream;

function Opl3LibraryName: String;
begin
  {$if defined(MSWINDOWS)}
  Result := 'nukedopl3.dll';
  {$elseif defined(DARWIN)}
  Result := 'libnukedopl3.dylib';
  {$else}
  Result := 'libnukedopl3.so';
  {$endif}
end;

{$ifndef WASI}
procedure TryLoad;
var
  Candidates: array of String;
  Lib: TLibHandle;
  I: Integer;
  Path, Url: String;
begin
  Candidates := nil;
  { An explicit path first, then the packaged data/lib, the exe's directory,
    the current directory's data/lib (unit tests run from the project root)
    and finally the system's library search. }
  if GetEnvironmentVariable('CASTLE_DOOM_OPL3') <> '' then
    Candidates := Concat(Candidates, [GetEnvironmentVariable('CASTLE_DOOM_OPL3')]);
  Url := ResolveCastleDataUrl('castle-data:/lib/' + Opl3LibraryName);
  Path := UriToFilenameSafe(Url);
  if Path <> '' then
    Candidates := Concat(Candidates, [Path]);
  Candidates := Concat(Candidates, [
    ExtractFilePath(ParamStr(0)) + Opl3LibraryName,
    'data' + PathDelim + 'lib' + PathDelim + Opl3LibraryName,
    Opl3LibraryName]);
  for I := 0 to High(Candidates) do
  begin
    if (I < High(Candidates)) and not FileExists(Candidates[I]) then Continue;
    Lib := LoadLibrary(Candidates[I]);
    if Lib = NilHandle then Continue;
    Pointer(ChipReset) := GetProcedureAddress(Lib, 'OPL3_Reset');
    Pointer(ChipWriteReg) := GetProcedureAddress(Lib, 'OPL3_WriteReg');
    Pointer(ChipGenerate) := GetProcedureAddress(Lib, 'OPL3_GenerateStream');
    if Assigned(ChipReset) and Assigned(ChipWriteReg) and Assigned(ChipGenerate) then
    begin
      Status := 'Nuked OPL3 loaded from ' + Candidates[I];
      Exit;
    end;
    ChipReset := nil;
    ChipWriteReg := nil;
    ChipGenerate := nil;
    Status := Candidates[I] + ' has no OPL3_Reset / OPL3_WriteReg / OPL3_GenerateStream';
    UnloadLibrary(Lib);
  end;
  if Status = '' then
    Status := Opl3LibraryName + ' not found (data/lib, next to the program, CASTLE_DOOM_OPL3)';
end;
{$endif}

function Opl3Available: Boolean;
begin
  if not Tried then
  begin
    Tried := true;
    {$ifdef WASI}
    Status := 'no dynamic libraries on the web';
    {$else}
    TryLoad;
    {$endif}
  end;
  Result := Assigned(ChipGenerate);
end;

function Opl3Status: String;
begin
  Opl3Available;
  Result := Status;
end;

{ TOpl3Chip ------------------------------------------------------------------ }

constructor TOpl3Chip.Create(const SampleRate: Cardinal);
begin
  inherited Create;
  if not Opl3Available then
    raise Exception.Create('Nuked OPL3 is not available: ' + Status);
  FChip := AllocMem(ChipBytes);
  ChipReset(FChip, SampleRate);
end;

destructor TOpl3Chip.Destroy;
begin
  if FChip <> nil then
    FreeMem(FChip);
  inherited;
end;

procedure TOpl3Chip.WriteReg(const Reg: Word; const Value: Byte);
begin
  ChipWriteReg(FChip, Reg, Value);
end;

procedure TOpl3Chip.Generate(const Buffer: PSmallInt; const Count: Integer);
begin
  if Count > 0 then
    ChipGenerate(FChip, Buffer, Count);
end;

end.
