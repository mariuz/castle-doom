{%MainUnit doomworld.pas}
{ Boom's generalized linedef types (DoomGeneralized decodes them): floors,
  ceilings, doors, locked doors, lifts, stairs and crushers built from the
  vanilla movers with the speed, target, delay and texture / special
  change the line's bits ask for (EV_DoGenFloor, EV_DoGenCeiling,
  EV_DoGenDoor, EV_DoGenLockedDoor, EV_DoGenLift, EV_DoGenStairs,
  EV_DoGenCrusher in Boom's p_genlin.c). Floors do not crush: like the
  vanilla floors here, a rising floor does not check what stands on it. }

function TDoomWorld.GenKeyOk(const G: TGenLine): Boolean;
var
  Keys: TKeys;
  MsgName, Msg: String;

  function Has(const Card, Skull: TDoomKey; const IsSkull: Boolean): Boolean;
  begin
    if IsSkull then
      Result := (Skull in Keys) or (G.SkullIsCard and (Card in Keys))
    else
      Result := (Card in Keys) or (G.SkullIsCard and (Skull in Keys));
  end;

  procedure Need(const Color: String; const IsSkull: Boolean);
  begin
    { P_CanUnlockGenDoor: "a red key" when either will do. }
    if G.SkullIsCard then
    begin
      MsgName := 'PD_' + UpperCase(Color) + 'K';
      Msg := Format('You need a %s key to open this door', [Color]);
    end else
    if IsSkull then
    begin
      MsgName := 'PD_' + UpperCase(Color) + 'S';
      Msg := Format('You need a %s skull to open this door', [Color]);
    end else
    begin
      MsgName := 'PD_' + UpperCase(Color) + 'C';
      Msg := Format('You need a %s card to open this door', [Color]);
    end;
  end;

begin
  Keys := Player.Keys;
  MsgName := '';
  case G.Key of
    gkyAny:
      if Keys = [] then
      begin
        MsgName := 'PD_ANY';
        Msg := 'Any key will open this door';
      end;
    gkyRedCard: if not Has(keyRed, skullRed, false) then Need('red', false);
    gkyBlueCard: if not Has(keyBlue, skullBlue, false) then Need('blue', false);
    gkyYellowCard: if not Has(keyYellow, skullYellow, false) then Need('yellow', false);
    gkyRedSkull: if not Has(keyRed, skullRed, true) then Need('red', true);
    gkyBlueSkull: if not Has(keyBlue, skullBlue, true) then Need('blue', true);
    gkyYellowSkull: if not Has(keyYellow, skullYellow, true) then Need('yellow', true);
    gkyAll:
      if G.SkullIsCard then
      begin
        if not (Has(keyRed, skullRed, false) and Has(keyBlue, skullBlue, false) and
                Has(keyYellow, skullYellow, false)) then
        begin
          MsgName := 'PD_ALL3';
          Msg := 'You need all three keys to open this door';
        end;
      end else
      if not ([keyBlue, keyYellow, keyRed, skullBlue, skullYellow, skullRed] <= Keys) then
      begin
        MsgName := 'PD_ALL6';
        Msg := 'You need all six keys to open this door';
      end;
  end;
  Result := MsgName = '';
  if not Result then
  begin
    ShowMessage(Text(MsgName, Msg));
    FSounds.Play('DSOOF');
  end;
end;

function TDoomWorld.ApplyGeneralized(const Line: Integer; const Activation: TActivation;
  const ByMonster: Boolean): Boolean;
var
  G: TGenLine;
  Tag, Back, Front, S, Model, NewSpec: Integer;
  Wanted: TActivation;
  Manual, Done, Repeatable, Open, Close: Boolean;
  Speed, H, T, Low, High, Dir: Single;
  M: TSectorMover;

  { The sectors to move: the tagged ones, or once the one behind a manual
    (D1 / DR) line. }
  function NextSector(var Iter: Integer): Boolean;
  begin
    if Manual then
    begin
      if Iter >= 0 then Exit(false);
      Iter := Back;
      Exit(Iter >= 0);
    end;
    Iter := FMap.FindSectorFromTag(Tag, Iter);
    Result := Iter >= 0;
  end;

  { A neighbour of Sec whose floor (or ceiling) is at Height:
    P_FindModelFloorSector / P_FindModelCeilingSector. }
  function NumericModel(const Sec: Integer; const Height: Single; const Ceiling: Boolean): Integer;
  var
    LL, O: Integer;
  begin
    for LL in FMap.Sectors[Sec].Lines do
    begin
      O := FMap.OtherSector(LL, Sec);
      if O < 0 then Continue;
      if Ceiling and (FMap.Sectors[O].CeilingHeight = Height) then Exit(O);
      if (not Ceiling) and (FMap.Sectors[O].FloorHeight = Height) then Exit(O);
    end;
    Result := -1;
  end;

  function ChangeModel(const Sec: Integer; const Height: Single; const Ceiling: Boolean): Integer;
  begin
    if G.Change = gcNone then Exit(-1);
    if G.NumericModel then
      Result := NumericModel(Sec, Height, Ceiling)
    else
      Result := Front;
  end;

  function ModelSpecial(const ModelSec: Integer): Integer;
  begin
    if G.Change = gcTextureAndSpecial then
      Result := FMap.Sectors[ModelSec].Special
    else
      Result := 0;
  end;

begin
  Result := false;
  G := DecodeGeneralized(FMap.Linedefs[Line].Special);
  case G.Trigger of
    gtW1, gtWR: Wanted := acCross;
    gtG1, gtGR: Wanted := acShoot;
    else Wanted := acUse;
  end;
  if Activation <> Wanted then Exit;
  if ByMonster and ((not G.Monster) or (G.Kind = gkLockedDoor)) then Exit;
  Manual := GenManual(G);
  Repeatable := GenRepeatable(G);
  Tag := FMap.Linedefs[Line].Tag;
  Back := FMap.Linedefs[Line].BackSector;
  Front := FMap.Linedefs[Line].FrontSector;
  { Boom: every non-manual type needs a tag, a manual one a sector behind. }
  if Manual then
  begin
    if Back < 0 then Exit;
  end else
  if Tag = 0 then
    Exit;
  if (G.Kind = gkLockedDoor) and not GenKeyOk(G) then
    Exit(true);

  Done := true;
  S := -1;
  case G.Kind of
    gkFloor:
      begin
        Speed := FloorSpeed * (1 shl Ord(G.Speed));
        if G.Up then Dir := 1 else Dir := -1;
        while NextSector(S) do
        begin
          if FMap.Sectors[S].Mover <> nil then Continue;
          H := FMap.Sectors[S].FloorHeight;
          case G.Target of
            gtHighestNeighbour: T := FMap.HighestFloorSurrounding(S);
            gtLowestNeighbour: T := FMap.LowestFloorSurrounding(S);
            gtNextNeighbour:
              if G.Up then T := FMap.NextHighestFloor(S, H) else T := FMap.NextLowestFloor(S, H);
            gtLowestOther: T := FMap.LowestCeilingSurrounding(S);
            gtOwnOther: T := FMap.Sectors[S].CeilingHeight;
            gtShortestTexture: T := H + Dir * ShortestTexture(S, false);
            gtBy24: T := H + Dir * 24;
            else T := H + Dir * 32;
          end;
          Model := ChangeModel(S, T, false);
          M := DoFloor(S, T, Speed, Model);
          if (Model >= 0) and (G.Change in [gcZeroSpecial, gcTextureAndSpecial]) then
          begin
            NewSpec := ModelSpecial(Model);
            if M <> nil then
            begin
              M.ChangeSpecial := true;
              M.NewSpecial := NewSpec;
            end else
              FMap.Sectors[S].Special := NewSpec;
          end;
        end;
      end;
    gkCeiling:
      begin
        Speed := CeilSpeed * (1 shl Ord(G.Speed));
        if G.Up then Dir := 1 else Dir := -1;
        while NextSector(S) do
        begin
          if FMap.Sectors[S].Mover <> nil then Continue;
          H := FMap.Sectors[S].CeilingHeight;
          case G.Target of
            gtHighestNeighbour: T := FMap.HighestCeilingSurrounding(S);
            gtLowestNeighbour: T := FMap.LowestCeilingSurrounding(S);
            gtNextNeighbour:
              if G.Up then T := FMap.NextHighestCeiling(S, H) else T := FMap.NextLowestCeiling(S, H);
            gtLowestOther: T := FMap.HighestFloorSurrounding(S);
            gtOwnOther: T := FMap.Sectors[S].FloorHeight;
            gtShortestTexture: T := H + Dir * ShortestTexture(S, true);
            gtBy24: T := H + Dir * 24;
            else T := H + Dir * 32;
          end;
          Model := ChangeModel(S, T, true);
          if T = H then
          begin
            { Nothing to move: only the change. }
            if Model >= 0 then
            begin
              FMap.Sectors[S].CeilingTex := FMap.Sectors[Model].CeilingTex;
              if G.Change in [gcZeroSpecial, gcTextureAndSpecial] then
                FMap.Sectors[S].Special := ModelSpecial(Model);
              FGeometry.SectorChanged(S);
            end;
            Continue;
          end;
          if G.Crush then
            M := TSectorMover.Create(Self, S, mkCrusher)
          else
            M := TSectorMover.Create(Self, S, mkCeiling);
          M.MovesCeiling := true;
          M.Speed := Speed;
          M.Target := T;
          M.MoveSound := 'DSSTNMOV';
          M.StopSound := 'DSPSTOP';
          if Model >= 0 then
          begin
            M.NewCeilingTex := FMap.Sectors[Model].CeilingTex;
            if G.Change in [gcZeroSpecial, gcTextureAndSpecial] then
            begin
              M.ChangeSpecial := true;
              M.NewSpecial := ModelSpecial(Model);
            end;
          end;
          FMovers.Add(M);
          M.Start;
        end;
      end;
    gkDoor, gkLockedDoor:
      begin
        Speed := DoorSpeed * (1 shl Ord(G.Speed));
        Open := G.DoorKind in [gdOpenWaitClose, gdOpen];
        Close := G.DoorKind in [gdOpenWaitClose, gdCloseWaitOpen];
        while NextSector(S) do
          DoDoor(S, Open, Close, false, G.DelayTics, Speed);
      end;
    gkLift:
      begin
        Speed := PlatSpeed / 2 * (1 shl Ord(G.Speed));
        if G.LiftTarget = glPerpetual then
          ResumeMovers(Tag, mkLift);
        while NextSector(S) do
        begin
          H := FMap.Sectors[S].FloorHeight;
          High := H;
          case G.LiftTarget of
            glLowestFloor: Low := Min(FMap.LowestFloorSurrounding(S), H);
            glNextFloor: Low := FMap.NextLowestFloor(S, H);
            glLowestCeiling: Low := Min(FMap.LowestCeilingSurrounding(S), H);
            else
              begin
                Low := Min(FMap.LowestFloorSurrounding(S), H);
                High := Max(FMap.HighestFloorSurrounding(S), H);
              end;
          end;
          DoLiftTo(S, Low, High, Speed, G.DelayTics, G.LiftTarget = glPerpetual);
        end;
      end;
    gkStairs:
      begin
        case G.Speed of
          gsSlow: Speed := FloorSpeed / 4;
          gsNormal: Speed := FloorSpeed / 2;
          gsFast: Speed := FloorSpeed * 2;
          else Speed := FloorSpeed * 4;
        end;
        if Manual then S := Back else S := -1;
        if G.Up then
          DoStairs(Line, G.StepSize, Speed, G.IgnoreTexture, S)
        else
          DoStairs(Line, -G.StepSize, Speed, G.IgnoreTexture, S);
      end;
    gkCrusher:
      begin
        Speed := CeilSpeed * (1 shl Ord(G.Speed));
        ResumeMovers(Tag, mkCrusher);
        while NextSector(S) do
          DoCeiling(S, FMap.Sectors[S].FloorHeight + 8, Speed, true, G.Silent);
      end;
    else
      Done := false;
  end;

  if not Done then Exit(false);
  Result := true;
  WritelnLog('Generalized', 'line %d: %s', [Line, GenDescription(G)]);
  { Switches flip (S and G types), manual doors do not. }
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
