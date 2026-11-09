{ ZDoom's (and Hexen's) sound sequences: SNDINFO gives logical sound
  names their lumps ("doors/dr1_open dsdoropn"), SNDSEQ gives the
  sequences that doors, platforms and polyobjects play by number:

    :DoorNormal
      door 0
      playuntildone doors/dr1_open
      stopsound doors/dr1_clos
    end

  Only what the game uses is kept: a sequence's number (per kind), the
  sound it starts with (play / playuntildone / playrepeat / playloop /
  playtime), whether that one repeats, and the sound it stops with
  (stopsound). Reading never raises (the web build cannot catch). }
unit DoomSoundSeq;

interface

uses SysUtils, Classes, DoomWad;

type
  TSoundSeqKind = (skDoor, skPlatform, skEnvironment);

  TSoundSeq = record
    Name: String;
    Kind: TSoundSeqKind;
    Number: Integer;
    StartSound, StopSound: String;
    Repeating: Boolean;
  end;

  TSoundSequences = class
  strict private
    FLogical, FLumps: TStringList;
  public
    Sequences: array of TSoundSeq;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Every SNDINFO and SNDSEQ lump of the WADs, in load order. }
    procedure LoadFromWad(const Wad: TDoomWad);
    procedure ParseSndInfo(const Text: String);
    procedure ParseSndSeq(const Text: String);
    { The sequence of that kind and number, -1 none. }
    function Find(const Kind: TSoundSeqKind; const Number: Integer): Integer;
    { A logical sound's lump (SNDINFO), the name itself when it is none
      (a lump name already: DSDOROPN). Upper case. }
    function LumpOf(const Sound: String): String;
    function LogicalCount: Integer;
  end;

implementation

uses StrUtils;

constructor TSoundSequences.Create;
begin
  inherited;
  FLogical := TStringList.Create;
  FLumps := TStringList.Create;
end;

destructor TSoundSequences.Destroy;
begin
  FreeAndNil(FLogical);
  FreeAndNil(FLumps);
  inherited;
end;

procedure TSoundSequences.Clear;
begin
  FLogical.Clear;
  FLumps.Clear;
  Sequences := nil;
end;

function LumpText(const Wad: TDoomWad; const Index: Integer): String;
var
  Bytes: TBytes;
begin
  Bytes := Wad.LumpBytes(Index);
  SetLength(Result, Length(Bytes));
  if Length(Bytes) > 0 then Move(Bytes[0], Result[1], Length(Bytes));
end;

{ A line without its comment (// or ;), its words split on blanks. }
function Words(const Line: String): TStringArray;
var
  S: String;
  P: Integer;
begin
  S := Line;
  P := Pos('//', S);
  if P > 0 then S := Copy(S, 1, P - 1);
  P := Pos(';', S);
  if P > 0 then S := Copy(S, 1, P - 1);
  S := StringReplace(S, #9, ' ', [rfReplaceAll]);
  Result := Trim(S).Split([' '], TStringSplitOptions.ExcludeEmpty);
end;

procedure TSoundSequences.LoadFromWad(const Wad: TDoomWad);
var
  L: Integer;
begin
  Clear;
  L := Wad.FindLumpForward('SNDINFO', 0);
  while L >= 0 do
  begin
    ParseSndInfo(LumpText(Wad, L));
    L := Wad.FindLumpForward('SNDINFO', L + 1);
  end;
  L := Wad.FindLumpForward('SNDSEQ', 0);
  while L >= 0 do
  begin
    ParseSndSeq(LumpText(Wad, L));
    L := Wad.FindLumpForward('SNDSEQ', L + 1);
  end;
end;

procedure TSoundSequences.ParseSndInfo(const Text: String);
var
  Lines: TStringList;
  I, K: Integer;
  W: TStringArray;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      W := Words(Lines[I]);
      { "$commands" (random, alias, limit...) are not kept. }
      if (Length(W) < 2) or (W[0][1] = '$') then Continue;
      K := FLogical.IndexOf(LowerCase(W[0]));
      if K >= 0 then
        FLumps[K] := UpperCase(W[1])
      else
      begin
        FLogical.Add(LowerCase(W[0]));
        FLumps.Add(UpperCase(W[1]));
      end;
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

procedure TSoundSequences.ParseSndSeq(const Text: String);
var
  Lines: TStringList;
  I, Cur: Integer;
  W: TStringArray;
  Cmd: String;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    Cur := -1;
    for I := 0 to Lines.Count - 1 do
    begin
      W := Words(Lines[I]);
      if Length(W) = 0 then Continue;
      Cmd := LowerCase(W[0]);
      if Cmd[1] = ':' then
      begin
        Cur := Length(Sequences);
        SetLength(Sequences, Cur + 1);
        Sequences[Cur] := Default(TSoundSeq);
        Sequences[Cur].Name := Copy(W[0], 2, MaxInt);
        Sequences[Cur].Number := -1;
        Continue;
      end;
      { ZDoom's "[Name ... ]" slot lists are skipped with what is outside a sequence. }
      if Cur < 0 then Continue;
      if Cmd = 'end' then
      begin
        Cur := -1;
        Continue;
      end;
      if Length(W) < 2 then Continue;
      if (Cmd = 'door') or (Cmd = 'platform') or (Cmd = 'environment') then
      begin
        if Cmd = 'door' then Sequences[Cur].Kind := skDoor
        else if Cmd = 'platform' then Sequences[Cur].Kind := skPlatform
        else Sequences[Cur].Kind := skEnvironment;
        Sequences[Cur].Number := StrToIntDef(W[1], -1);
      end else
      if AnsiMatchText(Cmd, ['play', 'playuntildone', 'playrepeat', 'playloop', 'playtime']) then
      begin
        if Sequences[Cur].StartSound = '' then
        begin
          Sequences[Cur].StartSound := W[1];
          Sequences[Cur].Repeating := (Cmd = 'playrepeat') or (Cmd = 'playloop');
        end;
      end else
      if Cmd = 'stopsound' then
        Sequences[Cur].StopSound := W[1];
    end;
  finally
    FreeAndNil(Lines);
  end;
end;

{ A later sequence of the same kind and number replaces an earlier one
  (a PWAD's over the IWAD's): the last wins. }
function TSoundSequences.Find(const Kind: TSoundSeqKind; const Number: Integer): Integer;
begin
  for Result := High(Sequences) downto 0 do
    if (Sequences[Result].Kind = Kind) and (Sequences[Result].Number = Number) then Exit;
  Result := -1;
end;

function TSoundSequences.LumpOf(const Sound: String): String;
var
  K: Integer;
begin
  K := FLogical.IndexOf(LowerCase(Sound));
  if K >= 0 then Result := FLumps[K] else Result := UpperCase(Sound);
end;

function TSoundSequences.LogicalCount: Integer;
begin
  Result := FLogical.Count;
end;

end.
