(* ZDoom's TERRAIN lumps: what a floor flat is made of.

    splash Water
    {
      smallclass WaterSplashBase
      smallclip 12
      smallsound world/drip
      baseclass WaterSplashBase
      chunkclass WaterSplash
      chunkxvelshift 8
      chunkyvelshift 8
      chunkzvelshift 8
      chunkbasezvel 2
      sound world/watersplash
    }
    terrain Water
    {
      splash Water
      footclip 10
      liquid
      friction 0.5
      damageamount 5
      damagetimemask 31
    }
    floor FWATER1 Water
    floor optional NUKAGE1 Nukage
    defaultterrain Solid

  `ifheretic` / `ifhexen` / `ifstrife` ... `endif` blocks are skipped
  (`ifdoom` blocks read). A later definition of a name replaces the
  earlier one, so a PWAD's lump overrides the IWAD's. The world uses a
  terrain's splash (where things land and missiles hit), footclip (things
  sink that deep), damage and friction. Reading never raises (the web
  build cannot catch). *)
unit DoomTerrain;

interface

uses SysUtils, Classes, DoomWad;

type
  TTerrainSplash = record
    Name: String;
    { ZDoom's actor classes: the small splash (light things), the base
      left on the surface and the chunks thrown up, with their sounds. }
    SmallClass, SmallSound, BaseClass, ChunkClass, Sound: String;
    SmallClip: Single;
    { Chunk velocity: random(-255..255) shl shift / 65536 across, base
      plus random(0..255) shl shift / 65536 up; shift -1: none. }
    ChunkXVelShift, ChunkYVelShift, ChunkZVelShift: Integer;
    ChunkBaseZVel: Single;
    NoAlert: Boolean;
  end;

  TTerrainDef = record
    Name: String;
    { Index in Splashes, -1 none. }
    Splash: Integer;
    SplashName: String;
    FootClip: Single;
    Liquid: Boolean;
    { Damage every DamageTimeMask + 1 tics to the player standing on it
      (only when landing with DamageOnLand); a radiation suit protects
      with AllowProtection. }
    DamageAmount, DamageTimeMask: Integer;
    DamageType: String;
    DamageOnLand, AllowProtection: Boolean;
    { Footsteps (GZDoom's MakeFootsteps): StepSound for every step, else
      LeftStepSound and RightStepSound in turn, every WalkStepTics while
      walking, RunStepTics while running (0: none); StepVolume 0..1. }
    StepSound, LeftStepSound, RightStepSound: String;
    StepVolume: Single;
    WalkStepTics, RunStepTics: Integer;
    { ZDoom's friction (1.0 normal): Boom's friction and move factor. }
    HasFriction: Boolean;
    Friction, MoveFactor: Single;
  end;

  TTerrainTable = class
  strict private
    { Flat name -> index in FFlatTerrains (the terrain's name, resolved on
      lookup: a floor line may come before its terrain). }
    FFlats, FFlatTerrains: TStringList;
    FDefault: Integer;
    FDefaultName: String;
    FProblems: Integer;
    function AddTerrain(const Name: String): Integer;
    function AddSplash(const Name: String): Integer;
  public
    Splashes: array of TTerrainSplash;
    Terrains: array of TTerrainDef;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    { Every TERRAIN lump of the WADs, in load order. }
    procedure LoadFromWad(const Wad: TDoomWad);
    procedure Parse(const Text: String);
    function TerrainByName(const Name: String): Integer;
    function SplashByName(const Name: String): Integer;
    { The terrain of a floor flat (the default terrain when it has none
      of its own), -1 none. }
    function TerrainOfFlat(const Flat: String): Integer;
    function FlatCount: Integer;
    { Things the parser did not understand (unknown keywords...). }
    property Problems: Integer read FProblems;
  end;

{ ZDoom's friction value (1.0 normal) as Boom's friction and move factor. }
procedure TerrainFriction(const Value: Single; out Friction, MoveFactor: Single);

implementation

uses Math;

type
  TTerrainScanner = class
    Text: String;
    P, N: Integer;
    Tok: String;
    IsString: Boolean;
    constructor Create(const AText: String);
    function Next: Boolean;
    function Num: Single;
    { The next token is a value (not a keyword or a brace). }
    function PeekValue: Boolean;
  end;

constructor TTerrainScanner.Create(const AText: String);
begin
  inherited Create;
  Text := AText;
  P := 1;
  N := Length(Text);
end;

function TTerrainScanner.Next: Boolean;
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

function TTerrainScanner.Num: Single;
var
  Code: Integer;
begin
  Result := 0;
  if not Next then Exit;
  Val(Tok, Result, Code);
  if Code <> 0 then Result := 0;
end;

function TTerrainScanner.PeekValue: Boolean;
var
  SaveP: Integer;
  SaveTok: String;
  SaveStr: Boolean;
  V: Single;
  Code: Integer;
begin
  SaveP := P;
  SaveTok := Tok;
  SaveStr := IsString;
  Result := Next and (IsString or not ((Tok = '{') or (Tok = '}')));
  if Result and not IsString then
  begin
    Val(Tok, V, Code);
    Result := Code = 0;
  end;
  P := SaveP;
  Tok := SaveTok;
  IsString := SaveStr;
end;

procedure TerrainFriction(const Value: Single; out Friction, MoveFactor: Single);
var
  F, MF: Single;
begin
  { p_terrain.cpp's ParseFriction, in Boom's units (P_SetSectorFriction). }
  F := ($1EB8 * (Value * 100)) / $80 + $D001;
  MF := (($10092 - F) * 1024) / 4352 + 568;
  if F > $10000 then F := $10000;
  if F < 0 then F := 0;
  if MF < 32 then MF := 32;
  Friction := F / $10000;
  MoveFactor := MF / 2048;
end;

constructor TTerrainTable.Create;
begin
  inherited;
  FFlats := TStringList.Create;
  FFlats.CaseSensitive := false;
  FFlats.Sorted := true;
  FFlats.Duplicates := dupIgnore;
  FFlatTerrains := TStringList.Create;
  FDefault := -1;
end;

destructor TTerrainTable.Destroy;
begin
  FreeAndNil(FFlats);
  FreeAndNil(FFlatTerrains);
  inherited;
end;

procedure TTerrainTable.Clear;
begin
  SetLength(Splashes, 0);
  SetLength(Terrains, 0);
  FFlats.Clear;
  FFlatTerrains.Clear;
  FDefault := -1;
  FDefaultName := '';
  FProblems := 0;
end;

function TTerrainTable.TerrainByName(const Name: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Terrains) do
    if SameText(Terrains[I].Name, Name) then Exit(I);
  Result := -1;
end;

function TTerrainTable.SplashByName(const Name: String): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Splashes) do
    if SameText(Splashes[I].Name, Name) then Exit(I);
  Result := -1;
end;

function TTerrainTable.AddTerrain(const Name: String): Integer;
begin
  Result := TerrainByName(Name);
  if Result < 0 then
  begin
    Result := Length(Terrains);
    SetLength(Terrains, Result + 1);
  end;
  Terrains[Result] := Default(TTerrainDef);
  Terrains[Result].Name := Name;
  Terrains[Result].Splash := -1;
  Terrains[Result].DamageTimeMask := 31;
  Terrains[Result].Friction := 1;
  Terrains[Result].StepVolume := 1;
  Terrains[Result].MoveFactor := 1;
end;

function TTerrainTable.AddSplash(const Name: String): Integer;
begin
  Result := SplashByName(Name);
  if Result < 0 then
  begin
    Result := Length(Splashes);
    SetLength(Splashes, Result + 1);
  end;
  Splashes[Result] := Default(TTerrainSplash);
  Splashes[Result].Name := Name;
  Splashes[Result].ChunkXVelShift := -1;
  Splashes[Result].ChunkYVelShift := -1;
  Splashes[Result].ChunkZVelShift := -1;
  Splashes[Result].ChunkBaseZVel := 1;
end;

procedure TTerrainTable.Parse(const Text: String);
var
  Sc: TTerrainScanner;
  Key, Flat, Name: String;
  T, S, I, Skip: Integer;
  F: Single;
begin
  Sc := TTerrainScanner.Create(Text);
  try
    while Sc.Next do
    begin
      Key := LowerCase(Sc.Tok);
      if (Key = 'ifheretic') or (Key = 'ifhexen') or (Key = 'ifstrife') or (Key = 'ifchex') then
      begin
        { Another game's definitions: up to the endif. }
        Skip := 1;
        while (Skip > 0) and Sc.Next do
          if SameText(Sc.Tok, 'endif') then Dec(Skip)
          else if SameText(Copy(Sc.Tok, 1, 2), 'if') and (Length(Sc.Tok) > 2) then Inc(Skip);
      end else
      if (Key = 'ifdoom') or (Key = 'endif') then
        { Doom's: read on. }
      else
      if Key = 'splash' then
      begin
        if not Sc.Next then Break;
        S := AddSplash(Sc.Tok);
        if not Sc.Next or (Sc.Tok <> '{') then
        begin
          Inc(FProblems);
          Continue;
        end;
        while Sc.Next and (Sc.Tok <> '}') do
        begin
          Key := LowerCase(Sc.Tok);
          if Key = 'smallclass' then begin Sc.Next; Splashes[S].SmallClass := Sc.Tok; end
          else if Key = 'smallclip' then Splashes[S].SmallClip := Sc.Num
          else if Key = 'smallsound' then begin Sc.Next; Splashes[S].SmallSound := Sc.Tok; end
          else if Key = 'baseclass' then begin Sc.Next; Splashes[S].BaseClass := Sc.Tok; end
          else if Key = 'chunkclass' then begin Sc.Next; Splashes[S].ChunkClass := Sc.Tok; end
          else if Key = 'chunkxvelshift' then Splashes[S].ChunkXVelShift := Round(Sc.Num)
          else if Key = 'chunkyvelshift' then Splashes[S].ChunkYVelShift := Round(Sc.Num)
          else if Key = 'chunkzvelshift' then Splashes[S].ChunkZVelShift := Round(Sc.Num)
          else if Key = 'chunkbasezvel' then Splashes[S].ChunkBaseZVel := Sc.Num
          else if Key = 'sound' then begin Sc.Next; Splashes[S].Sound := Sc.Tok; end
          else if Key = 'noalert' then Splashes[S].NoAlert := true
          else
          begin
            Inc(FProblems);
            if Sc.PeekValue then Sc.Next;
          end;
        end;
      end else
      if Key = 'terrain' then
      begin
        if not Sc.Next then Break;
        Name := Sc.Tok;
        { "terrain Name modify" (then a block) changes an existing one. }
        if Sc.Next and SameText(Sc.Tok, 'modify') then
        begin
          T := TerrainByName(Name);
          if T < 0 then T := AddTerrain(Name);
          Sc.Next;
        end else
          T := AddTerrain(Name);
        if Sc.Tok <> '{' then
        begin
          Inc(FProblems);
          Continue;
        end;
        while Sc.Next and (Sc.Tok <> '}') do
        begin
          Key := LowerCase(Sc.Tok);
          if Key = 'splash' then begin Sc.Next; Terrains[T].SplashName := Sc.Tok; end
          else if Key = 'footclip' then Terrains[T].FootClip := Sc.Num
          else if Key = 'liquid' then Terrains[T].Liquid := true
          else if Key = 'damageamount' then Terrains[T].DamageAmount := Round(Sc.Num)
          else if Key = 'damagetype' then begin Sc.Next; Terrains[T].DamageType := Sc.Tok; end
          else if Key = 'damagetimemask' then Terrains[T].DamageTimeMask := Round(Sc.Num)
          else if Key = 'damageonland' then Terrains[T].DamageOnLand := true
          else if Key = 'allowprotection' then Terrains[T].AllowProtection := true
          else if Key = 'friction' then
          begin
            F := Sc.Num;
            Terrains[T].HasFriction := true;
            TerrainFriction(F, Terrains[T].Friction, Terrains[T].MoveFactor);
          end
          else if Key = 'stepsounds' then begin Sc.Next; Terrains[T].StepSound := Sc.Tok; end
          else if Key = 'leftstepsounds' then begin Sc.Next; Terrains[T].LeftStepSound := Sc.Tok; end
          else if Key = 'rightstepsounds' then begin Sc.Next; Terrains[T].RightStepSound := Sc.Tok; end
          else if Key = 'stepvolume' then Terrains[T].StepVolume := Sc.Num
          { Times in seconds (p_terrain.cpp's GEN_Time: * TICRATE). }
          else if Key = 'walkingsteptime' then Terrains[T].WalkStepTics := Round(Sc.Num * 35)
          else if Key = 'runningsteptime' then Terrains[T].RunStepTics := Round(Sc.Num * 35)
          else if (Key = 'stepdistance') or (Key = 'stepdistanceminvel') or (Key = 'splashmass') then
            { GZDoom's distance-based steps and splash mass: not used. }
            Sc.Next
          else
          begin
            Inc(FProblems);
            if Sc.PeekValue then Sc.Next;
          end;
        end;
      end else
      if Key = 'floor' then
      begin
        if not Sc.Next then Break;
        if SameText(Sc.Tok, 'optional') and not Sc.Next then Break;
        Flat := Sc.Tok;
        if not Sc.Next then Break;
        I := FFlats.IndexOf(Flat);
        if I >= 0 then FFlats.Delete(I);
        FFlatTerrains.Add(Sc.Tok);
        FFlats.AddObject(UpperCase(Flat), TObject(PtrInt(FFlatTerrains.Count - 1)));
      end else
      if Key = 'defaultterrain' then
      begin
        if not Sc.Next then Break;
        FDefaultName := Sc.Tok;
      end else
        Inc(FProblems);
    end;
  finally
    FreeAndNil(Sc);
  end;
  { Splash names resolve once everything is read. }
  for T := 0 to High(Terrains) do
    Terrains[T].Splash := SplashByName(Terrains[T].SplashName);
  if FDefaultName <> '' then
    FDefault := TerrainByName(FDefaultName);
end;

procedure TTerrainTable.LoadFromWad(const Wad: TDoomWad);
var
  L: Integer;
  Bytes: TBytes;
  Text: String;
begin
  Clear;
  L := Wad.FindLumpForward('TERRAIN', 0);
  while L >= 0 do
  begin
    Bytes := Wad.LumpBytes(L);
    SetLength(Text, Length(Bytes));
    if Length(Bytes) > 0 then
      Move(Bytes[0], Text[1], Length(Bytes));
    Parse(Text);
    L := Wad.FindLumpForward('TERRAIN', L + 1);
  end;
end;

function TTerrainTable.TerrainOfFlat(const Flat: String): Integer;
var
  I: Integer;
begin
  I := FFlats.IndexOf(Flat);
  if I >= 0 then
    Result := TerrainByName(FFlatTerrains[Integer(PtrInt(FFlats.Objects[I]))])
  else
    Result := FDefault;
end;

function TTerrainTable.FlatCount: Integer;
begin
  Result := FFlats.Count;
end;

end.
