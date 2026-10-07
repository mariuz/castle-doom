{ Save / load of the level state as JSON. Included by doomworld.pas
  (implementation section), so it can use the world's private fields.

  Saved: map name, player, every sector's heights / light / special / flats,
  every linedef's special and flags, sidedef textures that differ from the
  WAD (flipped switches), active movers, switch timers, light-effect timers,
  and every actor with its state, animation and references (target,
  missile shooter, Arch-vile fire). Loading rebuilds the map from the WAD,
  applies the map state before the geometry is generated, then restores the
  rest. }

const
  SaveVersion = 1;

function EffectKindOf(const Info: PThingInfo; out Kind: TEffectKind): Boolean;
var
  K: TEffectKind;
begin
  for K := Low(TEffectKind) to High(TEffectKind) do
    if Info = @EffectInfos[K] then
    begin
      Kind := K;
      Exit(true);
    end;
  Kind := ekPuff;
  Result := false;
end;

function JsonFloatArray(const Values: array of Single): TJSONArray;
var
  V: Single;
begin
  Result := TJSONArray.Create;
  for V in Values do
    Result.Add(Double(V));
end;

function ArrayItemFloat(const Arr: TJSONArray; const I: Integer; const Default: Single): Single;
begin
  if (Arr = nil) or (I < 0) or (I >= Arr.Count) then Exit(Default);
  Result := Arr.Items[I].AsFloat;
end;

function ArrayItemInt(const Arr: TJSONArray; const I: Integer; const Default: Integer): Integer;
begin
  if (Arr = nil) or (I < 0) or (I >= Arr.Count) then Exit(Default);
  Result := Arr.Items[I].AsInteger;
end;

function ArrayItemStr(const Arr: TJSONArray; const I: Integer; const Default: String): String;
begin
  if (Arr = nil) or (I < 0) or (I >= Arr.Count) then Exit(Default);
  Result := Arr.Items[I].AsString;
end;

function ObjArray(const J: TJSONObject; const Name: String): TJSONArray;
var
  D: TJSONData;
begin
  D := J.Find(Name);
  if (D <> nil) and (D is TJSONArray) then
    Result := TJSONArray(D)
  else
    Result := nil;
end;

function TDoomWorld.SaveState: TJSONObject;
var
  PJ, AJ, MJ: TJSONObject;
  Arr, Sub: TJSONArray;
  I, Bits, SeqIndex, SeqTics, SeqTicsLeft: Integer;
  A: TDoomActor;
  M: TSectorMover;
  Orig: TDoomMap;
  Kind: TEffectKind;
  T: TAmmoType;
  W: TWeapon;
  K: TDoomKey;
  Saved: {$ifdef FPC}specialize{$endif} TList<TDoomActor>;
  SeqFrames: String;
  SeqLoop: Boolean;

  function Ref(const X: TDoomActor): Integer;
  begin
    if X = nil then Result := -1 else Result := Saved.IndexOf(X);
  end;

begin
  Result := TJSONObject.Create;
  Result.Add('version', SaveVersion);
  Result.Add('map', FMap.Name);
  Result.Add('tic', FTic);
  Result.Add('bfgCountdown', FBfgCountdown);
  Result.Add('skill', Skill);
  Result.Add('startX', Double(FDoomStartX));
  Result.Add('startY', Double(FDoomStartY));
  Result.Add('startAngle', Double(FDoomStartAngle));

  { Player }
  PJ := TJSONObject.Create;
  PJ.Add('health', Player.Health);
  PJ.Add('armor', Player.Armor);
  PJ.Add('armorType', Player.ArmorType);
  Arr := TJSONArray.Create;
  for T := amClip to amMisl do Arr.Add(Player.Ammo[T]);
  PJ.Add('ammo', Arr);
  Arr := TJSONArray.Create;
  for T := amClip to amMisl do Arr.Add(Player.MaxAmmo[T]);
  PJ.Add('maxAmmo', Arr);
  Bits := 0;
  for W := Low(TWeapon) to High(TWeapon) do
    if W in Player.Weapons then Bits := Bits or (1 shl Ord(W));
  PJ.Add('weapons', Bits);
  PJ.Add('weapon', Ord(Player.Weapon));
  Bits := 0;
  for K := Low(TDoomKey) to High(TDoomKey) do
    if K in Player.Keys then Bits := Bits or (1 shl Ord(K));
  PJ.Add('keys', Bits);
  PJ.Add('kills', Player.Kills);
  PJ.Add('items', Player.Items);
  PJ.Add('secrets', Player.Secrets);
  PJ.Add('totalKills', Player.TotalKills);
  PJ.Add('totalItems', Player.TotalItems);
  PJ.Add('totalSecrets', Player.TotalSecrets);
  PJ.Add('berserk', Player.BerserkTics);
  PJ.Add('invulnerable', Player.InvulnerableTics);
  PJ.Add('invisible', Player.InvisibleTics);
  PJ.Add('radSuit', Player.RadSuitTics);
  PJ.Add('lightAmp', Player.LightAmpTics);
  PJ.Add('x', Double(Player.X));
  PJ.Add('y', Double(Player.Y));
  PJ.Add('z', Double(Player.Z));
  PJ.Add('angle', Double(Player.Angle));
  Result.Add('player', PJ);

  { Sectors: parallel arrays }
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(Double(FMap.Sectors[I].FloorHeight));
  Result.Add('sectorFloor', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(Double(FMap.Sectors[I].CeilingHeight));
  Result.Add('sectorCeiling', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(FMap.Sectors[I].LightLevel);
  Result.Add('sectorLight', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(FMap.Sectors[I].OrigLight);
  Result.Add('sectorOrigLight', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(FMap.Sectors[I].Special);
  Result.Add('sectorSpecial', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(FMap.Sectors[I].FloorTex);
  Result.Add('sectorFloorTex', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Sectors) do Arr.Add(FMap.Sectors[I].CeilingTex);
  Result.Add('sectorCeilingTex', Arr);

  { Linedefs: specials (one-shot ones are cleared after use) and flags
    (ML_MAPPED marks lines revealed on the automap). }
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Linedefs) do Arr.Add(FMap.Linedefs[I].Special);
  Result.Add('lineSpecial', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FMap.Linedefs) do Arr.Add(FMap.Linedefs[I].Flags);
  Result.Add('lineFlags', Arr);

  { Sidedefs: only those that differ from the WAD (flipped switches). }
  Arr := TJSONArray.Create;
  Orig := TDoomMap.Create(FWad, FMap.Name);
  try
    for I := 0 to Min(High(FMap.Sidedefs), High(Orig.Sidedefs)) do
      if (FMap.Sidedefs[I].UpperTex <> Orig.Sidedefs[I].UpperTex) or
         (FMap.Sidedefs[I].LowerTex <> Orig.Sidedefs[I].LowerTex) or
         (FMap.Sidedefs[I].MiddleTex <> Orig.Sidedefs[I].MiddleTex) then
      begin
        Sub := TJSONArray.Create;
        Sub.Add(I);
        Sub.Add(FMap.Sidedefs[I].UpperTex);
        Sub.Add(FMap.Sidedefs[I].LowerTex);
        Sub.Add(FMap.Sidedefs[I].MiddleTex);
        Arr.Add(Sub);
      end;
  finally
    FreeAndNil(Orig);
  end;
  Result.Add('sides', Arr);

  { Movers in progress }
  Arr := TJSONArray.Create;
  for M in FMovers do
  begin
    MJ := TJSONObject.Create;
    MJ.Add('sector', M.Sector);
    MJ.Add('kind', Ord(M.Kind));
    MJ.Add('ceiling', M.MovesCeiling);
    MJ.Add('target', Double(M.Target));
    MJ.Add('speed', Double(M.Speed));
    MJ.Add('direction', M.Direction);
    MJ.Add('waitTics', M.WaitTics);
    MJ.Add('waitLeft', M.WaitLeft);
    MJ.Add('hasReturn', M.HasReturn);
    MJ.Add('returnTarget', Double(M.ReturnTarget));
    MJ.Add('perpetual', M.Perpetual);
    MJ.Add('phase', Ord(M.Phase));
    MJ.Add('startSound', M.StartSound);
    MJ.Add('stopSound', M.StopSound);
    MJ.Add('moveSound', M.MoveSound);
    MJ.Add('newFloorTex', M.NewFloorTex);
    Arr.Add(MJ);
  end;
  Result.Add('movers', Arr);

  { Switches waiting to flip back }
  Arr := TJSONArray.Create;
  for I := 0 to High(FButtons) do
  begin
    Sub := TJSONArray.Create;
    Sub.Add(FButtons[I].Line);
    Sub.Add(FButtons[I].TicsLeft);
    Arr.Add(Sub);
  end;
  Result.Add('buttons', Arr);

  { Light effects }
  Arr := TJSONArray.Create;
  for I := 0 to High(FLightTimers) do Arr.Add(FLightTimers[I]);
  Result.Add('lightTimers', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to High(FLightPhase) do Arr.Add(FLightPhase[I]);
  Result.Add('lightPhase', Arr);

  { Actors }
  Saved := {$ifdef FPC}specialize{$endif} TList<TDoomActor>.Create;
  try
    for A in FActors do
      if not A.Removed then Saved.Add(A);
    Arr := TJSONArray.Create;
    for A in Saved do
    begin
      AJ := TJSONObject.Create;
      if EffectKindOf(A.Info, Kind) then
        AJ.Add('effect', Ord(Kind))
      else
        AJ.Add('type', A.Info^.Num);
      AJ.Add('sprite', A.SpritePrefix);
      AJ.Add('x', Double(A.DoomX));
      AJ.Add('y', Double(A.DoomY));
      AJ.Add('z', Double(A.DoomZ));
      AJ.Add('angle', Double(A.Angle));
      AJ.Add('state', Ord(A.State));
      AJ.Add('health', A.Health);
      AJ.Add('awake', A.Awake);
      AJ.Add('reaction', A.ReactionTics);
      AJ.Add('mapFlags', A.MapFlags);
      AJ.Add('velocity', JsonFloatArray([A.VelX, A.VelY, A.VelZ]));
      AJ.Add('damageDice', A.MissileDamageDice);
      AJ.Add('damageFaces', A.MissileDamageFaces);
      AJ.Add('fromPlayer', A.FromPlayer);
      AJ.Add('bright', A.Bright);
      AJ.Add('charging', A.Charging);
      AJ.Add('chargeTics', A.ChargeTics);
      AJ.Add('attackFired', A.AttackFired);
      if A.Info^.Kind = tkMonster then
      begin
        AJ.Add('spawn', JsonFloatArray([A.SpawnX, A.SpawnY, A.SpawnAngle]));
        AJ.Add('deadTics', A.DeadTics);
      end;
      AJ.Add('collides', A.Collides);
      AJ.Add('pickable', A.Pickable);
      A.GetAnimation(SeqFrames, SeqIndex, SeqTics, SeqTicsLeft, SeqLoop);
      AJ.Add('frames', SeqFrames);
      AJ.Add('frameIndex', SeqIndex);
      AJ.Add('frameTics', SeqTics);
      AJ.Add('frameTicsLeft', SeqTicsLeft);
      AJ.Add('frameLoop', SeqLoop);
      AJ.Add('target', Ref(A.Target));
      AJ.Add('shooter', Ref(A.Shooter));
      AJ.Add('fire', Ref(A.Fire));
      Arr.Add(AJ);
    end;
    Result.Add('actors', Arr);
  finally
    FreeAndNil(Saved);
  end;
end;

procedure TDoomWorld.LoadState(const State: TJSONObject);
begin
  LoadMapCore(State.Get('map', ''), false, State);
end;

{ Map state, applied before the geometry is generated so walls, floors and
  switch textures come out right. }
procedure TDoomWorld.RestoreMapState(const State: TJSONObject);
var
  I, N: Integer;
  Arr, Sub: TJSONArray;
begin
  Arr := ObjArray(State, 'sectorFloor');
  if (Arr <> nil) and (Arr.Count <> Length(FMap.Sectors)) then
  begin
    WritelnWarning('Save', 'Saved game does not match %s (sector count differs), map state not restored', [FMap.Name]);
    Exit;
  end;
  for I := 0 to High(FMap.Sectors) do
  begin
    FMap.Sectors[I].FloorHeight := ArrayItemFloat(ObjArray(State, 'sectorFloor'), I, FMap.Sectors[I].FloorHeight);
    FMap.Sectors[I].CeilingHeight := ArrayItemFloat(ObjArray(State, 'sectorCeiling'), I, FMap.Sectors[I].CeilingHeight);
    FMap.Sectors[I].LightLevel := ArrayItemInt(ObjArray(State, 'sectorLight'), I, FMap.Sectors[I].LightLevel);
    FMap.Sectors[I].OrigLight := ArrayItemInt(ObjArray(State, 'sectorOrigLight'), I, FMap.Sectors[I].OrigLight);
    FMap.Sectors[I].Special := ArrayItemInt(ObjArray(State, 'sectorSpecial'), I, FMap.Sectors[I].Special);
    FMap.Sectors[I].FloorTex := ArrayItemStr(ObjArray(State, 'sectorFloorTex'), I, FMap.Sectors[I].FloorTex);
    FMap.Sectors[I].CeilingTex := ArrayItemStr(ObjArray(State, 'sectorCeilingTex'), I, FMap.Sectors[I].CeilingTex);
  end;
  Arr := ObjArray(State, 'lineSpecial');
  if (Arr = nil) or (Arr.Count = Length(FMap.Linedefs)) then
    for I := 0 to High(FMap.Linedefs) do
    begin
      FMap.Linedefs[I].Special := ArrayItemInt(ObjArray(State, 'lineSpecial'), I, FMap.Linedefs[I].Special);
      FMap.Linedefs[I].Flags := ArrayItemInt(ObjArray(State, 'lineFlags'), I, FMap.Linedefs[I].Flags);
    end;
  Arr := ObjArray(State, 'sides');
  if Arr <> nil then
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONArray) then Continue;
      Sub := TJSONArray(Arr.Items[I]);
      N := ArrayItemInt(Sub, 0, -1);
      if (N < 0) or (N > High(FMap.Sidedefs)) then Continue;
      FMap.Sidedefs[N].UpperTex := ArrayItemStr(Sub, 1, FMap.Sidedefs[N].UpperTex);
      FMap.Sidedefs[N].LowerTex := ArrayItemStr(Sub, 2, FMap.Sidedefs[N].LowerTex);
      FMap.Sidedefs[N].MiddleTex := ArrayItemStr(Sub, 3, FMap.Sidedefs[N].MiddleTex);
    end;
end;

{ Everything else, after the geometry exists. }
procedure TDoomWorld.RestoreDynamicState(const State: TJSONObject);
var
  PJ, AJ, MJ: TJSONObject;
  Arr, Sub: TJSONArray;
  Loaded: {$ifdef FPC}specialize{$endif} TList<TDoomActor>;
  I, Bits, Sec, Num, EffectNum: Integer;
  A: TDoomActor;
  M: TSectorMover;
  Info: PThingInfo;
  T: TAmmoType;
  W: TWeapon;
  K: TDoomKey;
  D: TJSONData;

  function Actor(const Index: Integer): TDoomActor;
  begin
    if (Index < 0) or (Index >= Loaded.Count) then Result := nil else Result := Loaded[Index];
  end;

begin
  FTic := State.Get('tic', Int64(0));
  FBfgCountdown := State.Get('bfgCountdown', 0);
  Skill := State.Get('skill', 2);
  FDoomStartX := State.Get('startX', Double(FDoomStartX));
  FDoomStartY := State.Get('startY', Double(FDoomStartY));
  FDoomStartAngle := State.Get('startAngle', Double(FDoomStartAngle));
  FHaveStart := true;

  { Player }
  D := State.Find('player');
  if (D <> nil) and (D is TJSONObject) then
  begin
    PJ := TJSONObject(D);
    ResetPlayer;
    Player.Health := PJ.Get('health', 100);
    Player.Armor := PJ.Get('armor', 0);
    Player.ArmorType := PJ.Get('armorType', 0);
    for T := amClip to amMisl do
    begin
      Player.Ammo[T] := ArrayItemInt(ObjArray(PJ, 'ammo'), Ord(T), Player.Ammo[T]);
      Player.MaxAmmo[T] := ArrayItemInt(ObjArray(PJ, 'maxAmmo'), Ord(T), Player.MaxAmmo[T]);
    end;
    Bits := PJ.Get('weapons', 3);
    Player.Weapons := [];
    for W := Low(TWeapon) to High(TWeapon) do
      if (Bits and (1 shl Ord(W))) <> 0 then Include(Player.Weapons, W);
    Player.Weapon := TWeapon(Clamped(PJ.Get('weapon', Ord(wpPistol)), Ord(Low(TWeapon)), Ord(High(TWeapon))));
    Bits := PJ.Get('keys', 0);
    Player.Keys := [];
    for K := Low(TDoomKey) to High(TDoomKey) do
      if (Bits and (1 shl Ord(K))) <> 0 then Include(Player.Keys, K);
    Player.Kills := PJ.Get('kills', 0);
    Player.Items := PJ.Get('items', 0);
    Player.Secrets := PJ.Get('secrets', 0);
    Player.TotalKills := PJ.Get('totalKills', 0);
    Player.TotalItems := PJ.Get('totalItems', 0);
    Player.TotalSecrets := PJ.Get('totalSecrets', 0);
    Player.BerserkTics := PJ.Get('berserk', 0);
    Player.InvulnerableTics := PJ.Get('invulnerable', 0);
    Player.InvisibleTics := PJ.Get('invisible', 0);
    Player.RadSuitTics := PJ.Get('radSuit', 0);
    Player.LightAmpTics := PJ.Get('lightAmp', 0);
    Player.X := PJ.Get('x', Double(FDoomStartX));
    Player.Y := PJ.Get('y', Double(FDoomStartY));
    Player.Z := PJ.Get('z', 0.0);
    Player.Angle := PJ.Get('angle', 0.0);
    Player.Sector := FMap.SectorAt(Player.X, Player.Y);
    Player.Dead := Player.Health <= 0;
    FOldPlayerX := Player.X;
    FOldPlayerY := Player.Y;
  end;

  { Movers }
  Arr := ObjArray(State, 'movers');
  if Arr <> nil then
    for I := 0 to Arr.Count - 1 do
    begin
      if not (Arr.Items[I] is TJSONObject) then Continue;
      MJ := TJSONObject(Arr.Items[I]);
      Sec := MJ.Get('sector', -1);
      if (Sec < 0) or (Sec > High(FMap.Sectors)) then Continue;
      M := TSectorMover.Create(Self, Sec, TMoverKind(Clamped(MJ.Get('kind', 0), Ord(Low(TMoverKind)), Ord(High(TMoverKind)))));
      M.MovesCeiling := MJ.Get('ceiling', false);
      M.Target := MJ.Get('target', 0.0);
      M.Speed := MJ.Get('speed', 1.0);
      M.Direction := MJ.Get('direction', 0);
      M.WaitTics := MJ.Get('waitTics', 0);
      M.WaitLeft := MJ.Get('waitLeft', 0);
      M.HasReturn := MJ.Get('hasReturn', false);
      M.ReturnTarget := MJ.Get('returnTarget', 0.0);
      M.Perpetual := MJ.Get('perpetual', false);
      M.Phase := TMoverPhase(Clamped(MJ.Get('phase', 0), Ord(Low(TMoverPhase)), Ord(High(TMoverPhase))));
      M.StartSound := MJ.Get('startSound', '');
      M.StopSound := MJ.Get('stopSound', '');
      M.MoveSound := MJ.Get('moveSound', '');
      M.NewFloorTex := MJ.Get('newFloorTex', '');
      FMap.Sectors[Sec].Mover := M;
      FMovers.Add(M);
    end;

  { Switch timers }
  Arr := ObjArray(State, 'buttons');
  SetLength(FButtons, 0);
  if Arr <> nil then
    for I := 0 to Arr.Count - 1 do
      if Arr.Items[I] is TJSONArray then
      begin
        Sub := TJSONArray(Arr.Items[I]);
        SetLength(FButtons, Length(FButtons) + 1);
        FButtons[High(FButtons)].Line := ArrayItemInt(Sub, 0, 0);
        FButtons[High(FButtons)].TicsLeft := ArrayItemInt(Sub, 1, 1);
      end;

  { Light effect timers (the sector list itself was rebuilt from the
    restored sector specials) }
  Arr := ObjArray(State, 'lightTimers');
  if (Arr <> nil) and (Arr.Count = Length(FLightTimers)) then
    for I := 0 to High(FLightTimers) do
    begin
      FLightTimers[I] := ArrayItemInt(Arr, I, FLightTimers[I]);
      FLightPhase[I] := ArrayItemInt(ObjArray(State, 'lightPhase'), I, FLightPhase[I]);
    end;

  { Actors: create all, then resolve references by index. }
  Arr := ObjArray(State, 'actors');
  Loaded := {$ifdef FPC}specialize{$endif} TList<TDoomActor>.Create;
  try
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        A := nil;
        if Arr.Items[I] is TJSONObject then
        begin
          AJ := TJSONObject(Arr.Items[I]);
          EffectNum := AJ.Get('effect', -1);
          if (EffectNum >= Ord(Low(TEffectKind))) and (EffectNum <= Ord(High(TEffectKind))) then
            Info := @EffectInfos[TEffectKind(EffectNum)]
          else
          begin
            Num := AJ.Get('type', 0);
            Info := FindThingInfo(Num);
          end;
          if Info <> nil then
          begin
            A := TDoomActor.Create(nil, FGraphics, Info);
            A.SpritePrefix := AJ.Get('sprite', Info^.Sprite);
            A.DoomX := AJ.Get('x', 0.0);
            A.DoomY := AJ.Get('y', 0.0);
            A.DoomZ := AJ.Get('z', 0.0);
            A.Angle := AJ.Get('angle', 0.0);
            A.Sector := FMap.SectorAt(A.DoomX, A.DoomY);
            A.State := TActorState(Clamped(AJ.Get('state', 0), Ord(Low(TActorState)), Ord(High(TActorState))));
            A.Health := AJ.Get('health', Info^.Health);
            A.Awake := AJ.Get('awake', false);
            A.ReactionTics := AJ.Get('reaction', 0);
            A.MapFlags := AJ.Get('mapFlags', 0);
            A.VelX := ArrayItemFloat(ObjArray(AJ, 'velocity'), 0, 0);
            A.VelY := ArrayItemFloat(ObjArray(AJ, 'velocity'), 1, 0);
            A.VelZ := ArrayItemFloat(ObjArray(AJ, 'velocity'), 2, 0);
            A.MissileDamageDice := AJ.Get('damageDice', 0);
            A.MissileDamageFaces := AJ.Get('damageFaces', 0);
            A.FromPlayer := AJ.Get('fromPlayer', false);
            A.Bright := AJ.Get('bright', false);
            A.Charging := AJ.Get('charging', false);
            A.ChargeTics := AJ.Get('chargeTics', 0);
            A.AttackFired := AJ.Get('attackFired', false);
            A.SpawnX := ArrayItemFloat(ObjArray(AJ, 'spawn'), 0, A.DoomX);
            A.SpawnY := ArrayItemFloat(ObjArray(AJ, 'spawn'), 1, A.DoomY);
            A.SpawnAngle := ArrayItemFloat(ObjArray(AJ, 'spawn'), 2, A.Angle);
            A.DeadTics := AJ.Get('deadTics', 0);
            A.Collides := AJ.Get('collides', Info^.Solid);
            A.Pickable := AJ.Get('pickable', false);
            A.SetAnimation(AJ.Get('frames', Info^.IdleFrames), AJ.Get('frameIndex', 0),
              AJ.Get('frameTics', 6), AJ.Get('frameTicsLeft', 6), AJ.Get('frameLoop', true));
            if Info^.Kind = tkTeleportDest then
              A.Scene.Exists := false;
            if A.Sector >= 0 then
              A.SetLight(FMap.Sectors[A.Sector].LightLevel)
            else
              A.SetLight(255);
            A.UpdateRotation(Player.X, Player.Y);
            A.UpdateTransform;
            FActors.Add(A);
            FItems.Add(A);
          end;
        end;
        Loaded.Add(A); { keep indexes aligned even when an entry is unknown }
      end;
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
        if (Loaded[I] <> nil) and (Arr.Items[I] is TJSONObject) then
        begin
          AJ := TJSONObject(Arr.Items[I]);
          Loaded[I].Target := Actor(AJ.Get('target', -1));
          Loaded[I].Shooter := Actor(AJ.Get('shooter', -1));
          Loaded[I].Fire := Actor(AJ.Get('fire', -1));
        end;
    WritelnLog('Save', '%s: restored %d actors, %d movers, %d switch timers', [
      FMap.Name, FActors.Count, FMovers.Count, Length(FButtons)]);
  finally
    FreeAndNil(Loaded);
  end;
end;
