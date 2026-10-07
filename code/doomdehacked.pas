{ Strings from DEHACKED lumps (Boom's BEX "[STRINGS]" section). Freedoom
  ships its own finale texts, finale background flats and cast-call names
  this way (E1TEXT, C1TEXT, BGFLATE1, CC_ZOMBIE...). Every DEHACKED lump in
  the loaded WADs is read in order, so a PWAD's strings override the IWAD's.
  Other DeHackEd sections (frames, things, code pointers) are ignored. }
unit DoomDehacked;

interface

uses Classes,
  DoomWad;

type
  TDoomStrings = class
  strict private
    FValues: TStringList;
    procedure ParseLump(const Text: String);
  public
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;
    { The BEX string for Key (case-insensitive), or Default when absent. }
    function Get(const Key: String; const Default: String = ''): String;
    function Has(const Key: String): Boolean;
    function Count: Integer;
    { Doom's level title (HUSTR_E1M1 / HUSTR_1), e.g. "E1M1: Outer Prison";
      the map name itself when the WAD has none. }
    function LevelName(const MapName: String; const IsDoom2: Boolean): String;
  end;

implementation

uses SysUtils;

constructor TDoomStrings.Create(const AWad: TDoomWad);
var
  I: Integer;
  Bytes: TBytes;
  Text: String;
begin
  inherited Create;
  FValues := TStringList.Create;
  FValues.CaseSensitive := false;
  if AWad = nil then Exit;
  for I := 0 to AWad.LumpCount - 1 do
    if AWad.LumpName(I) = 'DEHACKED' then
    begin
      Bytes := AWad.LumpBytes(I);
      SetLength(Text, Length(Bytes));
      if Length(Bytes) > 0 then
        Move(Bytes[0], Text[1], Length(Bytes));
      ParseLump(Text);
    end;
end;

destructor TDoomStrings.Destroy;
begin
  FreeAndNil(FValues);
  inherited;
end;

{ BEX: "KEY = value", a trailing backslash continues the value on the next
  line (its leading blanks dropped), "\n" is a newline. Lines starting with
  '#' are comments; a line starting with '[' begins another section. }
procedure TDoomStrings.ParseLump(const Text: String);
var
  Lines: TStringList;
  I, Eq: Integer;
  Line, Key, Value: String;
  InStrings: Boolean;

  function Unescape(const S: String): String;
  begin
    Result := StringReplace(S, '\n', #10, [rfReplaceAll]);
  end;

begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text; { handles CR LF and LF }
    InStrings := false;
    I := 0;
    while I < Lines.Count do
    begin
      Line := Trim(Lines[I]);
      Inc(I);
      if (Line = '') or (Line[1] = '#') then Continue;
      if Line[1] = '[' then
      begin
        InStrings := SameText(Line, '[STRINGS]');
        Continue;
      end;
      if not InStrings then Continue;
      Eq := Pos('=', Line);
      if Eq = 0 then Continue;
      Key := Trim(Copy(Line, 1, Eq - 1));
      Value := Trim(Copy(Line, Eq + 1, MaxInt));
      while (Value <> '') and (Value[Length(Value)] = '\') and (I < Lines.Count) do
      begin
        SetLength(Value, Length(Value) - 1);
        Value := Value + Trim(Lines[I]);
        Inc(I);
      end;
      FValues.Values[Key] := Unescape(Value);
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

function TDoomStrings.Get(const Key: String; const Default: String): String;
var
  Idx: Integer;
begin
  Idx := FValues.IndexOfName(Key);
  if Idx < 0 then
    Result := Default
  else
    Result := FValues.ValueFromIndex[Idx];
end;

function TDoomStrings.Has(const Key: String): Boolean;
begin
  Result := FValues.IndexOfName(Key) >= 0;
end;

function TDoomStrings.Count: Integer;
begin
  Result := FValues.Count;
end;

function TDoomStrings.LevelName(const MapName: String; const IsDoom2: Boolean): String;
var
  N: Integer;
begin
  if IsDoom2 and (Copy(MapName, 1, 3) = 'MAP') then
  begin
    N := StrToIntDef(Copy(MapName, 4, 2), 0);
    Result := Get('HUSTR_' + IntToStr(N), MapName);
  end else
    Result := Get('HUSTR_' + MapName, MapName);
end;

end.
