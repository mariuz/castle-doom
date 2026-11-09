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
  if UdmfPolySpecial(L.Special) then
  begin
    Manual := false;
    Result := PolyAction(L.Special, L.Args);
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
    UdmfPlatUpWaitDown, UdmfPlatUpNearestWaitDown, UdmfPlatDownByValue, UdmfPlatUpByValue:
      while NextSector(S) do
      begin
        case L.Special of
          UdmfPlatUpWaitDown: H := Max(FMap.Sectors[S].FloorHeight, FMap.HighestFloorSurrounding(S));
          UdmfPlatUpNearestWaitDown: H := FMap.NextHighestFloor(S, FMap.Sectors[S].FloorHeight);
          UdmfPlatDownByValue: H := FMap.Sectors[S].FloorHeight - L.Args[3] * 8;
          else H := FMap.Sectors[S].FloorHeight + L.Args[3] * 8;
        end;
        DoLiftTo(S, H, FMap.Sectors[S].FloorHeight, Speed, Max(1, L.Args[2]), false);
      end;
    UdmfPillarBuild:
      while NextSector(S) do
      begin
        if L.Args[2] = 0 then
          H := (FMap.Sectors[S].FloorHeight + FMap.Sectors[S].CeilingHeight) / 2
        else
          H := Min(FMap.Sectors[S].CeilingHeight, FMap.Sectors[S].FloorHeight + L.Args[2]);
        DoPillar(S, H, H, Speed);
      end;
    UdmfPillarOpen:
      while NextSector(S) do
      begin
        if L.Args[2] = 0 then
          H := FMap.LowestFloorSurrounding(S)
        else
          H := FMap.Sectors[S].FloorHeight - L.Args[2];
        if L.Args[3] = 0 then
          DoPillar(S, H, FMap.HighestCeilingSurrounding(S), Speed)
        else
          DoPillar(S, H, FMap.Sectors[S].CeilingHeight + L.Args[3], Speed);
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

{ ZDoom's spawn numbers of Doom's projectiles as effect kinds. }
function ProjectileOfSpawnNum(const SpawnNum: Integer; out K: TEffectKind): Boolean;
begin
  Result := true;
  case SpawnNum of
    10: K := ekBal1;            { DoomImpBall }
    126: K := ekBal2;           { CacodemonBall }
    154: K := ekBal7;           { BaronBall }
    127: K := ekRocket;         { Rocket }
    53: K := ekRevenantRocket;  { RevenantTracer }
    153: K := ekFatShot;        { FatShot }
    129: K := ekArachPlasma;    { ArachnotronPlasma }
    51: K := ekPlasmaBall;      { PlasmaBall }
    128: K := ekBfgBall;        { BFGBall }
    else Result := false;
  end;
end;

function TDoomWorld.SpawnProjectile(const K: TEffectKind; const X, Y, Z, Angle, Speed, VSpeed: Single;
  const Gravity: Boolean): TDoomActor;
var
  M: TDoomActor;
begin
  Result := nil;
  if FMap.SectorAt(X, Y) < 0 then Exit;
  M := TDoomActor.Create(nil, FGraphics, FSpriteBatch, @EffectInfos[K]);
  M.State := asMissile;
  M.Bright := true;
  M.DoomX := X;
  M.DoomY := Y;
  M.DoomZ := Z;
  M.Sector := FMap.SectorAt(X, Y);
  M.VelX := Cos(DegToRad(Angle)) * Speed;
  M.VelY := Sin(DegToRad(Angle)) * Speed;
  M.VelZ := VSpeed;
  M.MissileGravity := Gravity;
  M.MissileDamageDice := EffectInfos[K].DamageDice;
  M.MissileDamageFaces := EffectInfos[K].DamageFaces;
  M.Angle := Angle;
  M.Collides := false;
  M.Pickable := false;
  M.SetLight(255);
  M.UpdateTransform;
  FActors.Add(M);
  FThingsGroup.Add(M);
  if EffectInfos[K].AttackSound <> '' then
    FSounds.PlayAt(EffectInfos[K].AttackSound, M);
  Result := M;
end;

function TDoomWorld.ThingAction(const Special: Integer; const Args: array of Integer): Boolean;
var
  A: array [0..4] of Integer;
  I, N, DoomNum: Integer;
  Act: TDoomActor;
  Spots: array of TVector2;
  Name: String;
  Kind: TEffectKind;
  Z: Single;

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
    UdmfThingMove:
      begin
        Spots := nil;
        for Act in FActors do
          if (A[1] <> 0) and (Act.Tid = A[1]) and not Act.Removed then
          begin
            SetLength(Spots, 1);
            Spots[0] := Vector2(Act.DoomX, Act.DoomY);
            Break;
          end;
        if Length(Spots) = 0 then
          for I := 0 to High(FMap.Things) do
            if (A[1] <> 0) and (FMap.Things[I].Tid = A[1]) then
            begin
              SetLength(Spots, 1);
              Spots[0] := Vector2(FMap.Things[I].X, FMap.Things[I].Y);
              Break;
            end;
        if Length(Spots) = 0 then Exit;
        I := FMap.SectorAt(Spots[0].X, Spots[0].Y);
        if I < 0 then Exit;
        if A[0] = 0 then
        begin
          { The activator: the player. }
          if A[2] = 0 then
          begin
            SpawnFog(Player.X, Player.Y, Player.Z, Player.Sector);
            SpawnFog(Spots[0].X, Spots[0].Y, FMap.FloorAt(I, Spots[0].X, Spots[0].Y), I);
          end;
          PlayerTeleported := true;
          PlayerTeleportX := Spots[0].X;
          PlayerTeleportY := Spots[0].Y;
          PlayerTeleportZ := FMap.FloorAt(I, Spots[0].X, Spots[0].Y);
          PlayerTeleportAngle := Player.Angle;
          Player.X := Spots[0].X;
          Player.Y := Spots[0].Y;
          Player.Z := PlayerTeleportZ;
          Player.Sector := I;
          FOldPlayerX := Player.X;
          FOldPlayerY := Player.Y;
          N := 1;
        end else
          for Act in FActors do
            if Matches(Act) then
            begin
              if A[2] = 0 then
              begin
                SpawnFog(Act.DoomX, Act.DoomY, Act.DoomZ, Act.Sector);
                SpawnFog(Spots[0].X, Spots[0].Y, FMap.FloorAt(I, Spots[0].X, Spots[0].Y), I);
              end;
              Act.DoomX := Spots[0].X;
              Act.DoomY := Spots[0].Y;
              Act.DoomZ := FMap.FloorAt(I, Spots[0].X, Spots[0].Y);
              Act.Sector := I;
              LightActor(Act, I);
              Act.UpdateTransform;
              Inc(N);
            end;
      end;
    UdmfThingProjectile, UdmfThingProjectileGravity:
      begin
        if not ProjectileOfSpawnNum(A[1], Kind) then
        begin
          AcsLogOnce(Format('%s of spawn number %d', [Name, A[1]]));
          Exit;
        end;
        { From each live thing with that id (at its middle), else each of
          the map's things (map spots, at their height above the floor). }
        for Act in FActors do
          if Matches(Act) then
            if SpawnProjectile(Kind, Act.DoomX, Act.DoomY, Act.DoomZ + Act.Info^.Height / 2, A[2] * 360 / 256,
               A[3] / 8, A[4] / 8, Special = UdmfThingProjectileGravity) <> nil then
              Inc(N);
        if N = 0 then
          for I := 0 to High(FMap.Things) do
            if (A[0] <> 0) and (FMap.Things[I].Tid = A[0]) and (FMap.SectorAt(FMap.Things[I].X, FMap.Things[I].Y) >= 0) then
            begin
              Z := FMap.FloorAt(FMap.SectorAt(FMap.Things[I].X, FMap.Things[I].Y), FMap.Things[I].X,
                FMap.Things[I].Y) + FMap.Things[I].Z;
              if SpawnProjectile(Kind, FMap.Things[I].X, FMap.Things[I].Y, Z, A[2] * 360 / 256, A[3] / 8, A[4] / 8,
                 Special = UdmfThingProjectileGravity) <> nil then
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
  WritelnLog('Udmf', '%s (%d, %d, %d, %d, %d): %d things', [Name, A[0], A[1], A[2], A[3], A[4], N]);
  Result := N > 0;
end;

{ Polyobjects ---------------------------------------------------------------- }

function TDoomWorld.PolyMoving(const P: Integer): Integer;
begin
  for Result := 0 to High(FPolyMoves) do
    if FPolyMoves[Result].Poly = P then Exit;
  Result := -1;
end;

function TDoomWorld.PolyBusy(const Number: Integer): Boolean;
var
  P: Integer;
begin
  P := FMap.FindPolyobj(Number);
  Result := (P >= 0) and (PolyMoving(P) >= 0);
end;

{ The segment A-B passes through the square of half size R around (X, Y). }
function SegmentInBox(const AX, AY, BX, BY, X, Y, R: Single): Boolean;
var
  T0, T1, D, P0, P1, Tmp: Single;
  K: Integer;
begin
  T0 := 0;
  T1 := 1;
  for K := 0 to 1 do
  begin
    if K = 0 then
    begin
      D := BX - AX; P0 := X - R - AX; P1 := X + R - AX;
    end else
    begin
      D := BY - AY; P0 := Y - R - AY; P1 := Y + R - AY;
    end;
    if Abs(D) < 1e-9 then
    begin
      if (P0 > 0) or (P1 < 0) then Exit(false);
    end else
    begin
      P0 := P0 / D;
      P1 := P1 / D;
      if P0 > P1 then
      begin
        Tmp := P0; P0 := P1; P1 := Tmp;
      end;
      T0 := Max(T0, P0);
      T1 := Min(T1, P1);
      if T0 > T1 then Exit(false);
    end;
  end;
  Result := true;
end;

function TDoomWorld.TryPlacePoly(const P: Integer; const X, Y, Angle, Thrust: Single): Boolean;
var
  OldX, OldY, OldAngle, NX, NY: Single;
  A: TDoomActor;
  Blocked: Boolean;

  { The first wall touching the box around (TX, TY), -1 none; its outward
    side (the front faces out) is where Hexen thrusts what it meets. }
  function Touches(const TX, TY, R: Single; out NX, NY: Single): Boolean;
  var
    Line: Integer;
    DX, DY, Len: Single;
  begin
    NX := 0;
    NY := 0;
    for Line in FMap.Polyobjs[P].Lines do
      if SegmentInBox(FMap.Vertices[FMap.Linedefs[Line].V1].X, FMap.Vertices[FMap.Linedefs[Line].V1].Y,
         FMap.Vertices[FMap.Linedefs[Line].V2].X, FMap.Vertices[FMap.Linedefs[Line].V2].Y, TX, TY, R) then
      begin
        DX := FMap.Vertices[FMap.Linedefs[Line].V2].X - FMap.Vertices[FMap.Linedefs[Line].V1].X;
        DY := FMap.Vertices[FMap.Linedefs[Line].V2].Y - FMap.Vertices[FMap.Linedefs[Line].V1].Y;
        Len := Sqrt(DX * DX + DY * DY);
        if Len > 0 then
        begin
          NX := DY / Len;
          NY := -DX / Len;
        end;
        Exit(true);
      end;
    Result := false;
  end;

begin
  OldX := FMap.Polyobjs[P].X;
  OldY := FMap.Polyobjs[P].Y;
  OldAngle := FMap.Polyobjs[P].Angle;
  FMap.Polyobjs[P].X := X;
  FMap.Polyobjs[P].Y := Y;
  FMap.Polyobjs[P].Angle := Angle;
  FMap.PlacePolyobj(P);
  Blocked := false;
  { What is in the way is thrust out (Hexen's ThrustMobj) and stops the
    step; a crushing or hurting polyobject also hurts it. }
  if (not Player.Dead) and Touches(Player.X, Player.Y, PlayerRadius, NX, NY) then
  begin
    Blocked := true;
    PlayerPushVX := PlayerPushVX + NX * Thrust;
    PlayerPushVY := PlayerPushVY + NY * Thrust;
    if FMap.Polyobjs[P].Crush or FMap.Polyobjs[P].Hurt then
      DamagePlayer(3, nil);
  end;
  for A in FActors do
    if A.Collides and (not A.Removed) and (A.State <> asDead) and
       (A.Info^.Kind in [tkMonster, tkDecoration]) and Touches(A.DoomX, A.DoomY, A.Info^.Radius, NX, NY) then
    begin
      Blocked := true;
      if A.Info^.Kind = tkMonster then
      begin
        A.VelX := A.VelX + NX * Thrust;
        A.VelY := A.VelY + NY * Thrust;
      end;
      if (FMap.Polyobjs[P].Crush or FMap.Polyobjs[P].Hurt) and (A.Info^.Kind = tkMonster) and (A.Health > 0) then
        DamageActor(A, 3, A.DoomX, A.DoomY, A.DoomZ, nil, false);
    end;
  if Blocked then
  begin
    FMap.Polyobjs[P].X := OldX;
    FMap.Polyobjs[P].Y := OldY;
    FMap.Polyobjs[P].Angle := OldAngle;
    FMap.PlacePolyobj(P);
    Exit(false);
  end;
  FGeometry.SectorChanged(FMap.Polyobjs[P].Sector);
  Result := true;
end;

function TDoomWorld.PolyAction(const Special: Integer; const Args: array of Integer): Boolean;
var
  P, M, K: Integer;
  Move: TPolyMove;
  Angle, DX, DY: Single;
  Spots: TAcsSpots;
  MirrorArgs: array [0..4] of Integer;
  MirrorSpecial: Integer;

  function Arg(const K: Integer): Integer;
  begin
    if K <= High(Args) then Result := Args[K] else Result := 0;
  end;

begin
  Result := false;
  P := FMap.FindPolyobj(Arg(0));
  if P < 0 then
  begin
    AcsLogOnce(Format('%s on polyobject %d (no such polyobject)', [UdmfSpecialName(Special), Arg(0)]));
    Exit;
  end;
  M := PolyMoving(P);
  { A moving polyobject takes only the OR_ actions. }
  if (M >= 0) and not (((Special >= UdmfPolyOrRotateLeft) and (Special <= UdmfPolyOrMoveTimes8)) or
     (Special = UdmfPolyOrMoveToSpot)) then Exit;
  Move := Default(TPolyMove);
  Move.Poly := P;
  Angle := Arg(2) * 360 / 256;
  case Special of
    UdmfPolyRotateLeft, UdmfPolyRotateRight, UdmfPolyOrRotateLeft, UdmfPolyOrRotateRight:
      begin
        { Hexen: speed in eighths of its byte angles a tic; 0 a whole
          turn, 255 for ever. }
        Move.Kind := pkRotate;
        Move.Speed := Arg(1) * (360 / 256) / 8;
        if (Special = UdmfPolyRotateRight) or (Special = UdmfPolyOrRotateRight) then Move.Speed := -Move.Speed;
        if Arg(2) = 255 then Move.Left := -1
        else if Arg(2) = 0 then Move.Left := 360
        else Move.Left := Angle;
      end;
    UdmfPolyMove, UdmfPolyMoveTimes8, UdmfPolyOrMove, UdmfPolyOrMoveTimes8:
      begin
        Move.Kind := pkMove;
        Move.Speed := Arg(1) / 8;
        Move.Left := Arg(3);
        if (Special = UdmfPolyMoveTimes8) or (Special = UdmfPolyOrMoveTimes8) then Move.Left := Move.Left * 8;
      end;
    UdmfPolyMoveToSpot, UdmfPolyOrMoveToSpot:
      begin
        { Straight to the thing (or map spot) with that id. }
        Spots := AcsSpots(Arg(2));
        if Length(Spots) = 0 then
        begin
          AcsLogOnce(Format('%s to thing id %d (none)', [UdmfSpecialName(Special), Arg(2)]));
          Exit;
        end;
        Move.Kind := pkMove;
        Move.Speed := Arg(1) / 8;
        DX := Spots[0].X - FMap.Polyobjs[P].X;
        DY := Spots[0].Y - FMap.Polyobjs[P].Y;
        Move.Left := Sqrt(DX * DX + DY * DY);
        Angle := RadToDeg(ArcTan2(DY, DX));
      end;
    UdmfPolyDoorSlide:
      begin
        Move.Kind := pkSlide;
        Move.Speed := Arg(1) / 8;
        Move.Left := Arg(3);
        Move.Delay := Arg(4);
      end;
    else
      begin
        { Polyobj_DoorSwing: speed, angle, delay. }
        Move.Kind := pkSwing;
        Move.Speed := Arg(1) * (360 / 256) / 8;
        Move.Left := Angle;
        Move.Delay := Arg(3);
      end;
  end;
  if Move.Kind in [pkMove, pkSlide] then
  begin
    Move.DX := Cos(DegToRad(Angle));
    Move.DY := Sin(DegToRad(Angle));
  end;
  Move.Total := Move.Left;
  if (Move.Speed = 0) or (Move.Left = 0) then Exit;
  if M >= 0 then
    FPolyMoves[M] := Move
  else
  begin
    SetLength(FPolyMoves, Length(FPolyMoves) + 1);
    FPolyMoves[High(FPolyMoves)] := Move;
  end;
  PolySound(P, Move.Kind, true);
  WritelnLog('Udmf', '%s (%d, %d, %d, %d, %d): polyobject %d', [UdmfSpecialName(Special), Arg(0), Arg(1), Arg(2),
    Arg(3), Arg(4), FMap.Polyobjs[P].Number]);
  Result := true;
  { The mirror does the same the other way: turned the other way round,
    moved the opposite way (Hexen's mirrored polyobjects). }
  K := FMap.FindPolyobj(FMap.Polyobjs[P].Mirror);
  if (K >= 0) and (K <> P) and (FPolyMirrorDepth < 8) and (Special <> UdmfPolyMoveToSpot) and
     (Special <> UdmfPolyOrMoveToSpot) then
  begin
    for M := 0 to 4 do MirrorArgs[M] := Arg(M);
    MirrorArgs[0] := FMap.Polyobjs[K].Number;
    MirrorSpecial := Special;
    if Special = UdmfPolyRotateLeft then MirrorSpecial := UdmfPolyRotateRight
    else if Special = UdmfPolyRotateRight then MirrorSpecial := UdmfPolyRotateLeft
    else if Special = UdmfPolyOrRotateLeft then MirrorSpecial := UdmfPolyOrRotateRight
    else if Special = UdmfPolyOrRotateRight then MirrorSpecial := UdmfPolyOrRotateLeft
    else if Special <> UdmfPolyDoorSwing then
      MirrorArgs[2] := (Arg(2) + 128) and 255;
    Inc(FPolyMirrorDepth);
    if PolyAction(MirrorSpecial, MirrorArgs) and (Special = UdmfPolyDoorSwing) then
    begin
      { A swinging door's mirror turns the other way. }
      M := PolyMoving(K);
      if M >= 0 then FPolyMoves[M].Speed := -FPolyMoves[M].Speed;
    end;
    Dec(FPolyMirrorDepth);
  end;
end;

{ The polyobject's sounds where it is: doors open and close, the rest
  start and stop like Doom's lifts. }
procedure TDoomWorld.PolySound(const P: Integer; const Kind: TPolyMoveKind; const Starting: Boolean);
var
  Name: String;
  Seq: Integer;
begin
  if Kind in [pkSlide, pkSwing] then
  begin
    if Starting then Name := 'DSDOROPN' else Name := 'DSDORCLS';
  end else
  begin
    if Starting then Name := 'DSPSTART' else Name := 'DSPSTOP';
  end;
  { Hexen's polyobjects play their door sound sequence (StartLine's
    arg2) from SNDSEQ, its sounds named through SNDINFO. }
  Seq := -1;
  if FSoundSeqs <> nil then Seq := FSoundSeqs.Find(skDoor, FMap.Polyobjs[P].Sound);
  if Seq >= 0 then
  begin
    if Starting then Name := FSoundSeqs.Sequences[Seq].StartSound
    else Name := FSoundSeqs.Sequences[Seq].StopSound;
    if Name = '' then Exit;
    Name := FSoundSeqs.LumpOf(Name);
    WritelnLog('Sound', 'polyobject %d: %s %s (%s)', [FMap.Polyobjs[P].Number, FSoundSeqs.Sequences[Seq].Name,
      BoolToStr(Starting, 'starts', 'stops'), Name]);
  end;
  if FPolyEmitter = nil then
  begin
    FPolyEmitter := TCastleTransform.Create(nil);
    FPolyEmitter.Name := 'PolyobjectSound';
  end;
  if FPolyEmitter.Parent = nil then Items.Add(FPolyEmitter);
  FPolyEmitter.Translation := DoomToCge(FMap.Polyobjs[P].X, FMap.Polyobjs[P].Y, Player.Z + 32);
  FSounds.PlayAt(Name, FPolyEmitter);
end;

procedure TDoomWorld.TicPolys;
var
  I, K: Integer;
  Step, X, Y, Angle: Single;
  Done: Boolean;
begin
  I := 0;
  while I <= High(FPolyMoves) do
  begin
    Done := false;
    if FPolyMoves[I].Phase = 1 then
    begin
      Dec(FPolyMoves[I].Wait);
      if FPolyMoves[I].Wait <= 0 then
      begin
        { Back the way it came. }
        FPolyMoves[I].Phase := 2;
        FPolyMoves[I].Left := FPolyMoves[I].Total;
        FPolyMoves[I].Speed := -FPolyMoves[I].Speed;
        PolySound(FPolyMoves[I].Poly, FPolyMoves[I].Kind, false);
      end;
    end else
    begin
      Step := Abs(FPolyMoves[I].Speed);
      if (FPolyMoves[I].Left >= 0) and (Step > FPolyMoves[I].Left) then Step := FPolyMoves[I].Left;
      X := FMap.Polyobjs[FPolyMoves[I].Poly].X;
      Y := FMap.Polyobjs[FPolyMoves[I].Poly].Y;
      Angle := FMap.Polyobjs[FPolyMoves[I].Poly].Angle;
      if FPolyMoves[I].Kind in [pkRotate, pkSwing] then
        Angle := Angle + Sign(FPolyMoves[I].Speed) * Step
      else
      begin
        X := X + FPolyMoves[I].DX * Sign(FPolyMoves[I].Speed) * Step;
        Y := Y + FPolyMoves[I].DY * Sign(FPolyMoves[I].Speed) * Step;
      end;
      { Keep the angle in 0..360 so saves stay small. }
      if Angle >= 360 then Angle := Angle - 360;
      if Angle < 0 then Angle := Angle + 360;
      if TryPlacePoly(FPolyMoves[I].Poly, X, Y, Angle, Max(2, Step)) and (FPolyMoves[I].Left >= 0) then
      begin
        FPolyMoves[I].Left := FPolyMoves[I].Left - Step;
        if FPolyMoves[I].Left <= 1e-4 then
        begin
          if (FPolyMoves[I].Kind in [pkSlide, pkSwing]) and (FPolyMoves[I].Phase = 0) then
          begin
            FPolyMoves[I].Phase := 1;
            FPolyMoves[I].Wait := FPolyMoves[I].Delay;
          end else
          begin
            Done := true;
            if FPolyMoves[I].Kind in [pkRotate, pkMove] then
              PolySound(FPolyMoves[I].Poly, FPolyMoves[I].Kind, false);
          end;
        end;
      end;
    end;
    if Done then
    begin
      for K := I to High(FPolyMoves) - 1 do
        FPolyMoves[K] := FPolyMoves[K + 1];
      SetLength(FPolyMoves, Length(FPolyMoves) - 1);
    end else
      Inc(I);
  end;
end;
