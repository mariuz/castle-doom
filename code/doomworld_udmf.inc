{%MainUnit doomworld.pas}
{ UDMF maps' Hexen actions that need their arguments (DoomUdmf's
  UdmfSpecial* types: a floor or ceiling by or to a height, a light level
  set or changed), run with the vanilla movers. The line's Trigger says
  how it is set off (a TGenTrigger, + 8 when monsters may), Args what it
  does: [0] the sector tag, [1] the speed in eighths of a unit a tic, [2]
  the height (or [1] the light level). }

function TDoomWorld.ApplyUdmfSpecial(const Line: Integer; const Activation: TActivation;
  const ByMonster: Boolean): Boolean;
var
  L: TDoomLinedef;
  Trigger: TGenTrigger;
  Wanted: TActivation;
  Manual, Repeatable: Boolean;
  S: Integer;
  Speed, H: Single;

  { The switch or impact line's new look, and a once-only line cleared. }
  procedure FinishLine;
  begin
    if (Activation = acUse) and not Manual then
    begin
      if not ByMonster then
        FSounds.PlayAt('DSSWTCHN', FPlayerEmitter);
      ChangeLineButton(Line, Repeatable);
    end else
    if Activation = acShoot then
      ChangeLineButton(Line, Repeatable);
    if not Repeatable then
      FMap.Linedefs[Line].Special := 0;
  end;

  function NextSector(var Iter: Integer): Boolean;
  begin
    if Manual then
    begin
      if Iter >= 0 then Exit(false);
      Iter := L.BackSector;
      Exit(Iter >= 0);
    end;
    Iter := FMap.FindSectorFromTag(L.Args[0], Iter);
    Result := Iter >= 0;
  end;

begin
  Result := false;
  L := FMap.Linedefs[Line];
  Trigger := TGenTrigger(L.Trigger and 7);
  case Trigger of
    gtW1, gtWR: Wanted := acCross;
    gtG1, gtGR: Wanted := acShoot;
    else Wanted := acUse;
  end;
  if Activation <> Wanted then Exit;
  if ByMonster and ((L.Trigger and 8) = 0) then Exit;
  Manual := Trigger in [gtD1, gtDR];
  Repeatable := Odd(Ord(Trigger));
  if UdmfThingSpecial(L.Special) then
  begin
    Manual := false;
    Result := ThingAction(L.Special, L.Args);
    if Result then FinishLine;
    Exit;
  end;
  if UdmfAcsSpecial(L.Special) then
  begin
    { Scripts: a used line counts as a switch even when its tag would
      say the sector behind it. }
    Manual := false;
    Result := AcsLineAction(Line, ByMonster);
    if Result then FinishLine;
    Exit;
  end;
  if (not Manual) and (L.Args[0] = 0) then Exit;
  Speed := Max(1, L.Args[1]) / 8;
  S := -1;
  case L.Special of
    UdmfFloorByValue:
      while NextSector(S) do
        DoFloor(S, FMap.Sectors[S].FloorHeight + L.Args[2], Speed);
    UdmfFloorToValue:
      while NextSector(S) do
        DoFloor(S, L.Args[2], Speed);
    UdmfCeilingByValue, UdmfCeilingToValue:
      while NextSector(S) do
      begin
        if L.Special = UdmfCeilingByValue then
          H := FMap.Sectors[S].CeilingHeight + L.Args[2]
        else
          H := L.Args[2];
        DoCeiling(S, H, Speed, false);
      end;
    UdmfLightToValue:
      while NextSector(S) do
        DoLight(S, Max(0, Min(255, L.Args[1])));
    UdmfLightByValue:
      while NextSector(S) do
        DoLight(S, Max(0, Min(255, FMap.Sectors[S].LightLevel + L.Args[1])));
    else
      Exit;
  end;
  Result := true;
  WritelnLog('Udmf', 'line %d: %s, tag %d, %d, %d', [Line, UdmfSpecialName(L.Special), L.Args[0],
    L.Args[1], L.Args[2]]);
  FinishLine;
end;

{ ZDoom's spawn numbers of Doom's monsters and the barrel
  (doomworld_acs.inc's AcsThingNames) as Doom thing types, 0 unknown. }
function DoomNumOfSpawnNum(const SpawnNum: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AcsThingNames) do
    if (SpawnNum > 0) and (AcsThingNames[I].SpawnNum = SpawnNum) then
      Exit(AcsThingNames[I].DoomNum);
  Result := 0;
end;

function TDoomWorld.SpawnByScript(const DoomNum: Integer; const X, Y, Angle: Single; const Tid: Integer;
  const Fog: Boolean): TDoomActor;
var
  Sec: Integer;
  Info: PThingInfo;
begin
  Result := nil;
  Info := FindThingInfo(DoomNum);
  if Info = nil then Exit;
  Sec := FMap.SectorAt(X, Y);
  if Sec < 0 then Exit;
  Result := SpawnMonster(DoomNum, X, Y, FMap.FloorAt(Sec, X, Y));
  if Result = nil then Exit;
  Result.Angle := Angle;
  Result.SpawnAngle := Angle;
  Result.Tid := Tid;
  { A spawned monster waits for the player like one of the map's. }
  Result.Awake := false;
  if Info^.Kind = tkMonster then
    Inc(Player.TotalKills);
  if Info^.Hanging then
    Result.DoomZ := FMap.CeilingAt(Sec, X, Y) - Info^.Height;
  Result.UpdateTransform;
  if Fog then
    SpawnFog(X, Y, Result.DoomZ, Sec);
end;

function TDoomWorld.ThingAction(const Special: Integer; const Args: array of Integer): Boolean;
var
  A: array [0..4] of Integer;
  I, N, DoomNum: Integer;
  Act: TDoomActor;
  Spots: array of TVector2;
  Name: String;

  function Arg(const K: Integer): Integer;
  begin
    if K <= High(Args) then Result := Args[K] else Result := 0;
  end;

  { The live things with thing id A[0]. }
  function Matches(const X: TDoomActor): Boolean;
  begin
    Result := (A[0] <> 0) and (X.Tid = A[0]) and not X.Removed;
  end;

begin
  Result := false;
  for I := 0 to 4 do A[I] := Arg(I);
  Name := UdmfSpecialName(Special);
  N := 0;
  case Special of
    UdmfThingSpawn, UdmfThingSpawnNoFog:
      begin
        DoomNum := DoomNumOfSpawnNum(A[1]);
        if DoomNum = 0 then
        begin
          AcsLogOnce(Format('%s of spawn number %d', [Name, A[1]]));
          Exit;
        end;
        { The spots: things with that id, else the map's (map spots). }
        Spots := nil;
        for Act in FActors do
          if Matches(Act) then
          begin
            SetLength(Spots, Length(Spots) + 1);
            Spots[High(Spots)] := Vector2(Act.DoomX, Act.DoomY);
          end;
        if Length(Spots) = 0 then
          for I := 0 to High(FMap.Things) do
            if (A[0] <> 0) and (FMap.Things[I].Tid = A[0]) then
            begin
              SetLength(Spots, Length(Spots) + 1);
              Spots[High(Spots)] := Vector2(FMap.Things[I].X, FMap.Things[I].Y);
            end;
        for I := 0 to High(Spots) do
          if SpawnByScript(DoomNum, Spots[I].X, Spots[I].Y, A[2] * 360 / 256, A[3],
             Special = UdmfThingSpawn) <> nil then
            Inc(N);
      end;
    UdmfThingRemove, UdmfThingDestroy, UdmfThingDamage, UdmfThingActivate:
      begin
        if (A[0] = 0) and (Special = UdmfThingDamage) then
        begin
          DamagePlayer(A[1], nil);
          N := 1;
        end;
        for Act in FActors do
        begin
          if not Matches(Act) then Continue;
          case Special of
            UdmfThingRemove: Act.Removed := true;
            UdmfThingDestroy:
              if (Act.Info^.Kind = tkMonster) and (Act.Health > 0) then
                KillActor(Act, nil, false)
              else
                Continue;
            UdmfThingDamage:
              if (Act.Info^.Kind = tkMonster) and (Act.Health > 0) then
                DamageActor(Act, A[1], Act.DoomX, Act.DoomY, Act.DoomZ, nil, false)
              else
                Continue;
            else
              if Act.Info^.Kind = tkMonster then Act.Awake := true else Continue;
          end;
          Inc(N);
        end;
      end;
    UdmfDamageThing:
      begin
        DamagePlayer(Max(1, A[0]), nil);
        N := 1;
      end;
    UdmfHealThing:
      begin
        I := A[1];
        if I <= 0 then I := 100;
        if Player.Health < I then
        begin
          Player.Health := Min(I, Player.Health + A[0]);
          N := 1;
        end;
      end;
  end;
  WritelnLog('Udmf', '%s (%d, %d, %d, %d): %d things', [Name, A[0], A[1], A[2], A[3], N]);
  Result := N > 0;
end;
