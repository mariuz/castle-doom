(* GLDEFS (GZDoom / UZDoom): the light definitions a mod ships, and which
  sprite frames carry them.

    pointlight REDLAMP { color 1.0 0.2 0.2  size 96  offset 0 48 0 }
    pulselight PULSE { color 0 0 1  size 32  secondarysize 96  interval 2.0 }
    flickerlight FLICK { color 1 0.8 0.4  size 64  secondarysize 80  chance 0.3 }
    flickerlight2 FLICK2 { color ...  size 48  secondarysize 64  interval 0.1 }
    object Column { frame COLU { light REDLAMP } }
    brightmap texture COMPSTA1 { map BMCOMPST }
    #include "OTHERDEF"

  "size" is the light's radius in map units, "offset" is x (forward), y
  (up) and z (sideways) from the thing's feet. A frame names a sprite
  (four characters, every frame of it) or a sprite and frame letters
  ("TROOA" only frame A). The object's class name is kept only for the
  log: bindings go by sprite, which every thing here has. Lights are
  global like the other definition lumps (UMAPINFO, MAPINFO): LoadGldefs
  replaces them for a set of WADs. No exceptions (the web build). *)
unit DoomGldefs;

interface

uses SysUtils, Classes, CastleVectors, DoomWad;

type
  TGlLightKind = (glPoint, glPulse, glFlicker, glFlicker2, glSector);

  TGlLight = record
    Name: String;
    Kind: TGlLightKind;
    Color: TVector3;
    { Radius in map units; Secondary is the other end for pulse and
      flicker lights. }
    Size, SecondarySize: Single;
    { Pulse: seconds a whole cycle; flicker2: seconds between changes. }
    Interval: Single;
    { Flicker: the chance (0..1) a tic of being at SecondarySize. }
    Chance: Single;
    { Forward, up, sideways from the thing's feet. }
    Offset: TVector3;
    Subtractive: Boolean;
  end;

  TGlBinding = record
    ClassName: String;
    { Upper case: a sprite (4 characters) and the frame letters (none =
      every frame). }
    Sprite, Frames: String;
    Light: Integer;
  end;

  { Reads an #include'd lump by name ('' when missing). }
  TGldefsInclude = function(Name: String): String of object;

  TGlBrightmap = record
    { texture, flat or sprite }
    Kind: String;
    Name, Map: String;
  end;

var
  GlLights: array of TGlLight;
  GlBindings: array of TGlBinding;
  GlBrightmaps: array of TGlBrightmap;

{ Read the GLDEFS lumps of Wad (all of them, in order, with their
  #includes); False when there is none. The log gets a summary and what
  was not understood. }
function LoadGldefs(const Wad: TDoomWad): Boolean;
{ Parse one GLDEFS text into the tables (Include reads #include lumps,
  nil: ignored). Returns the problems found ('' none). }
function ParseGldefs(const Text: String; const Include: TGldefsInclude = nil): String;
procedure ClearGldefs;
{ The light of a sprite frame, False when GLDEFS binds none. }
function GldefsLightFor(const Sprite: String; const Frame: Char; out Light: TGlLight): Boolean;
{ A light's radius at a moment (seconds since the level start): pulse
  lights between their sizes, flicker lights by a hash of the moment (no
  random numbers drawn: the world's stay as demos expect). }
function GldefsRadius(const Light: TGlLight; const Time: Single): Single;

implementation

uses Math, CastleLog, CastleStringUtils;

procedure ClearGldefs;
begin
  GlLights := nil;
  GlBindings := nil;
  GlBrightmaps := nil;
end;

function FindLight(const Name: String): Integer;
var
  I: Integer;
begin
  for I := High(GlLights) downto 0 do
    if SameText(GlLights[I].Name, Name) then Exit(I);
  Result := -1;
end;

function ParseGldefs(const Text: String; const Include: TGldefsInclude): String;
var
  P, N, Depth: Integer;
  Tok: String;
  IsString: Boolean;
  Problems: TStringList;

  procedure Problem(const S: String);
  begin
    if Problems.IndexOf(S) < 0 then Problems.Add(S);
  end;

  function Next: Boolean;
  var
    S: Integer;
  begin
    Tok := '';
    IsString := false;
    while P <= N do
    begin
      if Text[P] <= ' ' then Inc(P)
      else if (Text[P] = '/') and (P < N) and (Text[P + 1] = '/') then
        while (P <= N) and (Text[P] <> #10) do Inc(P)
      else if (Text[P] = '/') and (P < N) and (Text[P + 1] = '*') then
      begin
        Inc(P, 2);
        while (P < N) and not ((Text[P] = '*') and (Text[P + 1] = '/')) do Inc(P);
        Inc(P, 2);
      end else
        Break;
    end;
    if P > N then Exit(false);
    if Text[P] = '"' then
    begin
      Inc(P);
      S := P;
      while (P <= N) and (Text[P] <> '"') do Inc(P);
      Tok := Copy(Text, S, P - S);
      Inc(P);
      IsString := true;
    end else
    if Text[P] in ['{', '}', ';', ','] then
    begin
      Tok := Text[P];
      Inc(P);
    end else
    begin
      S := P;
      while (P <= N) and not (Text[P] in [#0..' ', '{', '}', ';', ',', '"']) do Inc(P);
      Tok := Copy(Text, S, P - S);
    end;
    Result := true;
  end;

  function Num: Single;
  var
    Code: Integer;
  begin
    Result := 0;
    if not Next then Exit;
    Val(Tok, Result, Code);
    if Code <> 0 then
    begin
      Problem('a number expected, "' + Tok + '" found');
      Result := 0;
    end;
  end;

  { Skip a block whose opening brace is the next token. }
  procedure SkipBlock;
  begin
    if not Next then Exit;
    if Tok <> '{' then Exit;
    Depth := 1;
    while (Depth > 0) and Next do
      if (not IsString) and (Tok = '{') then Inc(Depth)
      else if (not IsString) and (Tok = '}') then Dec(Depth);
  end;

  procedure ReadLight(const Kind: TGlLightKind);
  var
    L: TGlLight;
    Key: String;
    I: Integer;
  begin
    L := Default(TGlLight);
    L.Kind := Kind;
    L.Color := Vector3(1, 1, 1);
    L.Size := 64;
    L.Interval := 1;
    L.Chance := 0.5;
    if not Next then Exit;
    L.Name := Tok;
    if not Next or (Tok <> '{') then
    begin
      Problem('"{" expected after light ' + L.Name);
      Exit;
    end;
    while Next and (Tok <> '}') do
    begin
      Key := LowerCase(Tok);
      if Key = 'color' then
      begin
        L.Color.X := Num;
        L.Color.Y := Num;
        L.Color.Z := Num;
      end else
      if Key = 'size' then L.Size := Num
      else if Key = 'secondarysize' then L.SecondarySize := Num
      else if Key = 'interval' then L.Interval := Num
      else if Key = 'chance' then L.Chance := Num
      else if Key = 'scale' then L.Size := Num * 255
      else if Key = 'offset' then
      begin
        L.Offset.X := Num;
        L.Offset.Y := Num;
        L.Offset.Z := Num;
      end else
      if Key = 'subtractive' then L.Subtractive := Num <> 0
      else if (Key = 'dontlightself') or (Key = 'attenuate') or (Key = 'dontlightactors') or
              (Key = 'dontlightmap') or (Key = 'additive') or (Key = 'spot') or (Key = 'noshadowmap') or
              (Key = 'lightsize') or (Key = 'softshadowradius') then
        Num
      else
        Problem('light property "' + Tok + '"');
    end;
    if L.SecondarySize = 0 then L.SecondarySize := L.Size;
    I := FindLight(L.Name);
    if I < 0 then
    begin
      I := Length(GlLights);
      SetLength(GlLights, I + 1);
    end;
    GlLights[I] := L;
  end;

  procedure ReadObject;
  var
    ClassName, Frame, LightName: String;
    B: TGlBinding;
  begin
    if not Next then Exit;
    ClassName := Tok;
    if not Next or (Tok <> '{') then Exit;
    while Next and (Tok <> '}') do
    begin
      if not SameText(Tok, 'frame') then
      begin
        Problem('object property "' + Tok + '"');
        Continue;
      end;
      if not Next then Exit;
      Frame := UpperCase(Tok);
      if not Next or (Tok <> '{') then Exit;
      LightName := '';
      while Next and (Tok <> '}') do
        if SameText(Tok, 'light') and Next then
          LightName := Tok;
      if LightName = '' then Continue;
      B.ClassName := ClassName;
      B.Sprite := Copy(Frame, 1, 4);
      B.Frames := Copy(Frame, 5, MaxInt);
      B.Light := FindLight(LightName);
      if B.Light < 0 then
      begin
        Problem('unknown light ' + LightName);
        Continue;
      end;
      SetLength(GlBindings, Length(GlBindings) + 1);
      GlBindings[High(GlBindings)] := B;
    end;
  end;

  procedure ReadBrightmap;
  var
    B: TGlBrightmap;
  begin
    B := Default(TGlBrightmap);
    if not Next then Exit;
    B.Kind := LowerCase(Tok);
    if not Next then Exit;
    B.Name := UpperCase(Tok);
    if not Next or (Tok <> '{') then Exit;
    while Next and (Tok <> '}') do
      if SameText(Tok, 'map') and Next then
        B.Map := UpperCase(Tok);
    if B.Map = '' then Exit;
    SetLength(GlBrightmaps, Length(GlBrightmaps) + 1);
    GlBrightmaps[High(GlBrightmaps)] := B;
  end;

var
  Key, Sub: String;
begin
  Problems := TStringList.Create;
  try
    P := 1;
    N := Length(Text);
    while Next do
    begin
      Key := LowerCase(Tok);
      if Key = '#include' then
      begin
        if Next and Assigned(Include) then
        begin
          Sub := Include(Tok);
          if Sub <> '' then
          begin
            Sub := ParseGldefs(Sub, Include);
            if Sub <> '' then Problem(Sub);
          end else
            Problem('missing include ' + Tok);
        end;
      end else
      if Key = 'pointlight' then ReadLight(glPoint)
      else if Key = 'pulselight' then ReadLight(glPulse)
      else if Key = 'flickerlight' then ReadLight(glFlicker)
      else if Key = 'flickerlight2' then ReadLight(glFlicker2)
      else if Key = 'sectorlight' then ReadLight(glSector)
      else if Key = 'object' then ReadObject
      else if Key = 'brightmap' then ReadBrightmap
      else if (Key = 'skybox') or (Key = 'glow') or (Key = 'hardwareshader') or (Key = 'material') or
              (Key = 'lightsizefactor') or (Key = 'spotlight') then
      begin
        Problem(Key);
        { A name (or two) before the block. }
        while Next and (Tok <> '{') do ;
        Depth := 1;
        while (Depth > 0) and Next do
          if (not IsString) and (Tok = '{') then Inc(Depth)
          else if (not IsString) and (Tok = '}') then Dec(Depth);
      end else
      if Tok = '{' then
        SkipBlock
      else
        Problem('"' + Tok + '"');
    end;
    Problems.Delimiter := ',';
    Problems.StrictDelimiter := true;
    Result := StringReplace(Problems.DelimitedText, ',', ', ', [rfReplaceAll]);
    Result := StringReplace(Result, '"', '', [rfReplaceAll]);
  finally
    FreeAndNil(Problems);
  end;
end;

type
  TIncluder = class
    Wad: TDoomWad;
    Depth: Integer;
    function Read(Name: String): String;
  end;

function TIncluder.Read(Name: String): String;
var
  L: Integer;
begin
  Result := '';
  Inc(Depth);
  if Depth > 16 then Exit;
  L := Wad.FindLump(UpperCase(ExtractFileName(StringReplace(Name, '/', PathDelim, [rfReplaceAll]))));
  if L < 0 then Exit;
  SetLength(Result, Wad.LumpSize(L));
  if Length(Result) > 0 then
    Move(Wad.LumpPointer(L)^, Result[1], Length(Result));
end;

function LoadGldefs(const Wad: TDoomWad): Boolean;
var
  I: Integer;
  Text, Problems, All: String;
  Includer: TIncluder;
begin
  ClearGldefs;
  Result := false;
  All := '';
  Includer := TIncluder.Create;
  try
    Includer.Wad := Wad;
    for I := 0 to Wad.LumpCount - 1 do
      if Wad.LumpName(I) = 'GLDEFS' then
      begin
        SetLength(Text, Wad.LumpSize(I));
        if Length(Text) > 0 then
          Move(Wad.LumpPointer(I)^, Text[1], Length(Text));
        Includer.Depth := 0;
        Problems := ParseGldefs(Text, @Includer.Read);
        if Problems <> '' then
        begin
          if All <> '' then All := All + ', ';
          All := All + Problems;
        end;
        Result := true;
      end;
  finally
    FreeAndNil(Includer);
  end;
  if Result then
  begin
    WritelnLog('Lights', 'GLDEFS: %d lights, %d frame bindings, %d brightmaps', [Length(GlLights),
      Length(GlBindings), Length(GlBrightmaps)]);
    if All <> '' then
      WritelnLog('Lights', 'GLDEFS: not supported: %s', [All]);
  end;
end;

function GldefsLightFor(const Sprite: String; const Frame: Char; out Light: TGlLight): Boolean;
var
  I: Integer;
begin
  for I := High(GlBindings) downto 0 do
    if (GlBindings[I].Sprite = Sprite) and
       ((GlBindings[I].Frames = '') or (Pos(UpCase(Frame), GlBindings[I].Frames) > 0)) then
    begin
      Light := GlLights[GlBindings[I].Light];
      Exit(true);
    end;
  Light := Default(TGlLight);
  Result := false;
end;

{ A repeatable pseudo-random 0..1 from a number. }
function Hash01(const N: Integer): Single;
var
  H: Cardinal;
begin
  H := Cardinal(N) * 2654435761;
  H := (H xor (H shr 15)) * 2246822519;
  H := H xor (H shr 13);
  Result := (H and $FFFF) / 65535;
end;

function GldefsRadius(const Light: TGlLight; const Time: Single): Single;
var
  Phase: Single;
begin
  case Light.Kind of
    glPulse:
      begin
        Phase := Frac(Time / Max(0.01, Light.Interval));
        Result := Light.Size + (Light.SecondarySize - Light.Size) * (0.5 - 0.5 * Cos(Phase * 2 * Pi));
      end;
    glFlicker:
      if Hash01(Trunc(Time * 35)) < Light.Chance then
        Result := Light.SecondarySize
      else
        Result := Light.Size;
    glFlicker2:
      Result := Light.Size + (Light.SecondarySize - Light.Size) *
        Hash01(Trunc(Time / Max(0.01, Light.Interval)));
    else Result := Light.Size;
  end;
end;

end.
