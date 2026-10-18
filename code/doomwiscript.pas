{ Intermission scripts: ZDoom's text format for the episode maps behind
  the intermission (the vanilla ones are wi_stuff.c's tables), read from a
  lump that MAPINFO names with exitpic / enterpic = "$LUMP", or built in
  for Doom's episodes 1 to 3 (VanillaWiScript).

    Background WIMAP0
    Splat WISPLAT                 // drawn on the visited levels' spots
    Pointer WIURH0 WIURH1         // "you are here", blinking, the first
                                  // that fits on the screen
    Spots { E1M1 185 164  E1M2 148 143 ... }
    Animation 224 104 11 { WIA00000 WIA00001 WIA00002 }  // x y tics
    Pic 304 166 PATCH
    IfEntering E2M9 Animation 192 144 11 { ... }         // also IfLeaving,
                                  // IfVisited and their IfNot... forms
    NoAutostartMap / Screensize / Tilebackground: accepted, unused

  DoomIntermission draws it (TDoomIntermission.DrawScript). }
unit DoomWiScript;

interface

uses Classes, Generics.Collections;

type
  TWiCondition = (wcAlways, wcEntering, wcNotEntering, wcLeaving, wcNotLeaving,
    wcVisited, wcNotVisited);

  TWiAnimation = class
    X, Y, Period: Integer;
    Frames: TStringList;
    Condition: TWiCondition;
    ConditionMap: String;
    { Conditional animations play once and keep their last frame
      (vanilla's level animations); the others loop. }
    constructor Create;
    destructor Destroy; override;
  end;
  TWiAnimationList = {$ifdef FPC}specialize{$endif} TObjectList<TWiAnimation>;

  TWiScript = class
    Background, Splat: String;
    Pointers: array [0..1] of String;
    { Map names (upper case) in the script's order, their spots in
      SpotX / SpotY. }
    SpotNames: TStringList;
    SpotX, SpotY: array of Integer;
    Animations: TWiAnimationList;
    constructor Create;
    destructor Destroy; override;
    function SpotIndex(const MapName: String): Integer;
  end;

{ Parse a script; Errors (may be nil) gets a line per problem. }
function ParseWiScript(const Text: String; const Errors: TStrings = nil): TWiScript;

{ Doom's own episode maps (1..3) as script text, '' for another episode. }
function VanillaWiScript(const Episode: Integer): String;

implementation

uses SysUtils;

constructor TWiAnimation.Create;
begin
  inherited;
  Frames := TStringList.Create;
end;

destructor TWiAnimation.Destroy;
begin
  FreeAndNil(Frames);
  inherited;
end;

constructor TWiScript.Create;
begin
  inherited;
  SpotNames := TStringList.Create;
  Animations := TWiAnimationList.Create(true);
end;

destructor TWiScript.Destroy;
begin
  FreeAndNil(Animations);
  FreeAndNil(SpotNames);
  inherited;
end;

function TWiScript.SpotIndex(const MapName: String): Integer;
begin
  Result := SpotNames.IndexOf(UpperCase(MapName));
end;

{ Words, with "{" and "}" as words of their own; // and /* */ comments
  dropped, quotes removed. }
function ScriptWords(const Text: String): TStringList;
var
  I: Integer;
  W: String;

  procedure Flush;
  begin
    if W <> '' then Result.Add(W);
    W := '';
  end;

begin
  Result := TStringList.Create;
  W := '';
  I := 1;
  while I <= Length(Text) do
  begin
    if (Text[I] = '/') and (I < Length(Text)) and (Text[I + 1] = '/') then
    begin
      Flush;
      while (I <= Length(Text)) and (Text[I] <> #10) do Inc(I);
      Continue;
    end;
    if (Text[I] = '/') and (I < Length(Text)) and (Text[I + 1] = '*') then
    begin
      Flush;
      Inc(I, 2);
      while (I < Length(Text)) and not ((Text[I] = '*') and (Text[I + 1] = '/')) do Inc(I);
      Inc(I, 2);
      Continue;
    end;
    case Text[I] of
      #0..' ', ',', ';': Flush;
      '"': ;
      '{', '}':
        begin
          Flush;
          Result.Add(Text[I]);
        end;
      else W := W + Text[I];
    end;
    Inc(I);
  end;
  Flush;
end;

function ParseWiScript(const Text: String; const Errors: TStrings): TWiScript;
var
  Words: TStringList;
  P: Integer;
  Condition: TWiCondition;
  ConditionMap: String;

  function Next: String;
  begin
    if P < Words.Count then Result := Words[P] else Result := '';
    Inc(P);
  end;

  function NextInt: Integer;
  var
    W: String;
  begin
    W := Next;
    Result := StrToIntDef(W, 0);
    if (Errors <> nil) and (StrToIntDef(W, MaxInt) = MaxInt) then
      Errors.Add('intermission script: a number expected, not "' + W + '"');
  end;

  procedure ReadSpots;
  var
    N: String;
  begin
    if Next <> '{' then Exit;
    while (P < Words.Count) and (Words[P] <> '}') do
    begin
      N := UpperCase(Next);
      Result.SpotNames.Add(N);
      SetLength(Result.SpotX, Length(Result.SpotX) + 1);
      SetLength(Result.SpotY, Length(Result.SpotY) + 1);
      Result.SpotX[High(Result.SpotX)] := NextInt;
      Result.SpotY[High(Result.SpotY)] := NextInt;
    end;
    Next;
  end;

  procedure ReadAnimation(const IsPic: Boolean);
  var
    A: TWiAnimation;
  begin
    A := TWiAnimation.Create;
    A.Condition := Condition;
    A.ConditionMap := ConditionMap;
    A.X := NextInt;
    A.Y := NextInt;
    if IsPic then
      A.Frames.Add(UpperCase(Next))
    else
    begin
      A.Period := NextInt;
      { Vanilla's "Animation x y period once" forms: an optional word. }
      if (P < Words.Count) and (Words[P] <> '{') then Next;
      if Next = '{' then
        while (P < Words.Count) and (Words[P] <> '}') do
          A.Frames.Add(UpperCase(Next));
      Next;
    end;
    Result.Animations.Add(A);
  end;

var
  W: String;
begin
  Result := TWiScript.Create;
  Words := ScriptWords(Text);
  try
    P := 0;
    while P < Words.Count do
    begin
      W := LowerCase(Next);
      Condition := wcAlways;
      ConditionMap := '';
      if (W = 'ifentering') or (W = 'ifnotentering') or (W = 'ifleaving') or (W = 'ifnotleaving') or
         (W = 'ifvisited') or (W = 'ifnotvisited') then
      begin
        if W = 'ifentering' then Condition := wcEntering
        else if W = 'ifnotentering' then Condition := wcNotEntering
        else if W = 'ifleaving' then Condition := wcLeaving
        else if W = 'ifnotleaving' then Condition := wcNotLeaving
        else if W = 'ifvisited' then Condition := wcVisited
        else Condition := wcNotVisited;
        ConditionMap := UpperCase(Next);
        W := LowerCase(Next);
      end;
      if W = 'background' then Result.Background := UpperCase(Next)
      else if W = 'splat' then Result.Splat := UpperCase(Next)
      else if W = 'pointer' then
      begin
        Result.Pointers[0] := UpperCase(Next);
        Result.Pointers[1] := UpperCase(Next);
      end
      else if W = 'spots' then ReadSpots
      else if W = 'animation' then ReadAnimation(false)
      else if W = 'pic' then ReadAnimation(true)
      else if (W = 'noautostartmap') or (W = 'tilebackground') then
      else if W = 'screensize' then
      begin
        Next;
        Next;
      end
      else if Errors <> nil then
        Errors.Add('intermission script: unknown word "' + W + '"');
    end;
  finally
    FreeAndNil(Words);
  end;
end;

const
  { wi_stuff.c: lnodes (the levels' spots) and the animations' places. }
  Spots: array [1..3, 1..9, 0..1] of Integer = (
    ((185, 164), (148, 143), (69, 122), (209, 102), (116, 89), (166, 55), (71, 56), (135, 29), (71, 24)),
    ((254, 25), (97, 50), (188, 64), (128, 78), (214, 92), (133, 130), (208, 136), (148, 140), (235, 158)),
    ((156, 168), (48, 154), (174, 95), (265, 75), (130, 48), (279, 23), (198, 48), (140, 25), (281, 136)));
  Anims1: array [0..9, 0..1] of Integer = ((224, 104), (184, 160), (112, 136), (72, 112), (88, 96),
    (64, 48), (192, 40), (136, 16), (80, 16), (64, 24));
  Anims3: array [0..5, 0..1] of Integer = ((104, 168), (40, 136), (160, 96), (104, 80), (120, 32), (40, 0));

function VanillaWiScript(const Episode: Integer): String;
var
  M, I: Integer;

  function Frames(const A, Count: Integer): String;
  var
    F: Integer;
  begin
    Result := '{';
    for F := 0 to Count - 1 do
      Result := Result + Format(' WIA%d%.2d%.2d', [Episode - 1, A, F]);
    Result := Result + ' }' + LineEnding;
  end;

begin
  Result := '';
  if (Episode < 1) or (Episode > 3) then Exit;
  Result := Format('Background WIMAP%d', [Episode - 1]) + LineEnding +
    'Splat WISPLAT' + LineEnding + 'Pointer WIURH0 WIURH1' + LineEnding + 'Spots {' + LineEnding;
  for M := 1 to 9 do
    Result := Result + Format('  E%dM%d %d %d', [Episode, M, Spots[Episode, M, 0], Spots[Episode, M, 1]]) + LineEnding;
  Result := Result + '}' + LineEnding;
  case Episode of
    1:
      for I := 0 to High(Anims1) do
        Result := Result + Format('Animation %d %d 11 ', [Anims1[I, 0], Anims1[I, 1]]) + Frames(I, 3);
    2:
      begin
        { Level animations: the one for the map being entered. }
        for I := 0 to 6 do
          Result := Result + Format('IfEntering E2M%d Animation 128 136 11 ', [I + 2]) + Frames(I, 1);
        Result := Result + 'IfEntering E2M9 Animation 192 144 11 ' + Frames(7, 3);
        Result := Result + 'IfEntering E2M9 Animation 128 136 11 ' + Frames(8, 1);
      end;
    3:
      for I := 0 to High(Anims3) do
        if I = High(Anims3) then
          Result := Result + Format('Animation %d %d 8 ', [Anims3[I, 0], Anims3[I, 1]]) + Frames(I, 3)
        else
          Result := Result + Format('Animation %d %d 11 ', [Anims3[I, 0], Anims3[I, 1]]) + Frames(I, 3);
  end;
end;

end.
