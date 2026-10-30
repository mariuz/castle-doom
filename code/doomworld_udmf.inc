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
