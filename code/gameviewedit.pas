{ The map editor: a Doom map from the loaded WADs drawn from above, like
  Doom Builder's 2D mode, with the editing of DoomEditMap behind it.

  Modes V (vertices), L (lines), S (sectors), T (things); a click selects
  what is under the mouse and dragging moves it (snapped to the grid, G
  changes it); the right or middle button pans, the wheel zooms. N draws
  a new room (clicks add corners, a click on the first one or Enter
  closes it). A selected sector's floor (PageUp / PageDown, Shift for the
  ceiling), light (B), flats (F, C), special (P), tag (, .) and "make
  door" (D); a line's wall texture (W), special, tag and split (X); things
  are added with A or Insert, their type changed with [ and ], turned
  with , and . and deleted with Delete. Ctrl+Z / Ctrl+Y undo and redo.
  F9 play-tests (the map's PWAD stacked on the WADs as edit:/MAP; the
  editor key F7 in the game comes back), F2 exports the PWAD (a file on
  the desktop, a download in the browser), F3 / F4 the level as glTF /
  X3D (DoomExport). H shows the keys.

  --edit [MAP] (with -iwad / -file) opens it, F7 in a game opens it on
  that map, the custom game page has EDIT MAP. In an autotest the demo
  script drives it (EditorScript commands below); PLAY hands the rest of
  the script to the game, whose EDIT command hands it back. }
unit GameViewEdit;

interface

uses Classes, SysUtils,
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse, CastleColors,
  DoomWad, DoomGraphics, DoomSound, DoomMusic, DoomEditMap;

type
  TEditMode = (emVertices, emLines, emSectors, emThings);

  TViewEdit = class(TCastleView)
  strict private
    FEdit: TDoomEditMap;
    FMode: TEditMode;
    FCenterX, FCenterY, FScale: Single;
    FSelected, FHover: Integer;
    FGrid: Integer;
    { Dragging the selection: where it started (Doom units, snapped) and
      the original places of what moves. }
    FDragging, FDragMoved: Boolean;
    FDragStart: TEditPoint;
    FDragVertices: array of Integer;
    FDragOrigins: TEditPoints;
    FPanning: Boolean;
    FPanLast: TVector2;
    FMouse: TVector2;
    FDrawing: Boolean;
    FDrawPoints: TEditPoints;
    FThingType: Integer;
    FTextures, FFlats: TStringList;
    FTitle, FInfo, FMessageLabel, FHelpLabel: TCastleLabel;
    FMessageTime: Single;
    FHelp: Boolean;
    { Autotest script. }
    FSteps: TStringList;
    FStep: Integer;
    FWait: Single;
    FShots: Integer;
    { The play-test's PWAD is stacked on Wad. }
    function ScreenOf(const X, Y: Single): TVector2;
    function DoomOf(const P: TVector2): TVector2;
    function Snap(const P: TVector2): TEditPoint;
    { The vertex near the mouse, else the snapped grid point. }
    function SnapToVertex(const P: TVector2): TEditPoint;
    function PickRadius: Single;
    function Pick(const P: TVector2): Integer;
    procedure Message(const Text: String);
    procedure LogAction(const Text: String);
    procedure ZoomToFit;
    procedure Zoom(const Factor: Single; const At: TVector2);
    procedure SetMode(const Mode: TEditMode);
    procedure LoadMap(const AMapName: String);
    procedure UpdateLabels;
    function SelectionInfo: String;
    procedure MouseDown(const P: TVector2; const Button: TCastleMouseButton);
    procedure MouseMove(const P: TVector2);
    procedure MouseUp(const P: TVector2; const Button: TCastleMouseButton);
    procedure AddDrawPoint(const Pt: TEditPoint);
    procedure FinishDrawing;
    function HandleKey(const Key: TKey; const Shift, Ctrl: Boolean): Boolean;
    function CycleName(const List: TStrings; const Current: String; const Delta: Integer): String;
    procedure ChangeWall(const Delta: Integer);
    procedure CycleSpecial(const Delta: Integer);
    procedure ChangeTag(const Delta: Integer);
    procedure CycleThingType(const Delta: Integer);
    procedure PlayTest;
    procedure ExportWad(const FileName: String);
    procedure ExportScene(const Gltf: Boolean; const FileName: String);
    procedure NextMap(const Delta: Integer);
    procedure Leave;
    procedure RunScript(const SecondsPassed: Single);
    procedure RunStep(const Step: String);
  public
    { Set before starting the view (the menu's or the game's objects). }
    Wad: TDoomWad;
    Graphics: TDoomGraphics;
    Sounds: TDoomSounds;
    Music: TDoomMusic;
    { The map to import; Fresh imports it again (else the map edited
      before is kept: back from a play-test). }
    MapName: String;
    Fresh: Boolean;
    { Skill of the play-test, 0..4. }
    Skill: Integer;
    { A play-test is running (the game's editor key comes back here). }
    PlayTesting: Boolean;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Start; override;
    procedure Stop; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
    procedure Render; override;
    function Press(const Event: TInputPressRelease): Boolean; override;
    function Release(const Event: TInputPressRelease): Boolean; override;
    function Motion(const Event: TInputMotion): Boolean; override;
    property Edit: TDoomEditMap read FEdit;
  end;

var
  ViewEdit: TViewEdit;
  { --edit [MAP]: open the editor once the WADs are loaded. }
  CmdEdit: Boolean;

{ Take the editor's play-test PWADs (edit:/...) off the WAD stack. }
procedure RemoveEditedWads(const Wad: TDoomWad);

{ Thing names for the editor (its type list, else the sprite). }
function EditorThingName(const TypeNum: Integer): String;

implementation

uses Math, StrUtils,
  CastleGLUtils, CastleLog, CastleWindow, CastleApplicationProperties, CastleUriUtils, CastleUtils,
  CastleFilesUtils, CastleRectangles, CastleRenderOptions,
  {$ifdef WASI} Job.Js, CastleInternalJobWeb, {$endif}
  DoomThings, DoomMap, GameViewPlay, GameViewMenu, DoomExport;

type
  TThingChoice = record
    Num: Integer;
    Name: String;
  end;

const
  ThingChoices: array [0..58] of TThingChoice = (
    (Num: 1; Name: 'Player 1 start'), (Num: 2; Name: 'Player 2 start'),
    (Num: 11; Name: 'Deathmatch start'), (Num: 14; Name: 'Teleport destination'),
    (Num: 3004; Name: 'Zombieman'), (Num: 9; Name: 'Shotgun guy'), (Num: 65; Name: 'Heavy weapon dude'),
    (Num: 3001; Name: 'Imp'), (Num: 3002; Name: 'Demon'), (Num: 58; Name: 'Spectre'),
    (Num: 3006; Name: 'Lost soul'), (Num: 3005; Name: 'Cacodemon'), (Num: 69; Name: 'Hell knight'),
    (Num: 3003; Name: 'Baron of Hell'), (Num: 68; Name: 'Arachnotron'), (Num: 71; Name: 'Pain elemental'),
    (Num: 66; Name: 'Revenant'), (Num: 67; Name: 'Mancubus'), (Num: 64; Name: 'Arch-vile'),
    (Num: 7; Name: 'Spider mastermind'), (Num: 16; Name: 'Cyberdemon'), (Num: 84; Name: 'SS'),
    (Num: 2001; Name: 'Shotgun'), (Num: 82; Name: 'Super shotgun'), (Num: 2002; Name: 'Chaingun'),
    (Num: 2003; Name: 'Rocket launcher'), (Num: 2004; Name: 'Plasma rifle'), (Num: 2006; Name: 'BFG 9000'),
    (Num: 2005; Name: 'Chainsaw'),
    (Num: 2007; Name: 'Clip'), (Num: 2048; Name: 'Box of bullets'), (Num: 2008; Name: 'Shells'),
    (Num: 2049; Name: 'Box of shells'), (Num: 2010; Name: 'Rocket'), (Num: 2046; Name: 'Box of rockets'),
    (Num: 2047; Name: 'Cell'), (Num: 17; Name: 'Cell pack'), (Num: 8; Name: 'Backpack'),
    (Num: 2011; Name: 'Stimpack'), (Num: 2012; Name: 'Medikit'), (Num: 2014; Name: 'Health bonus'),
    (Num: 2015; Name: 'Armor bonus'), (Num: 2018; Name: 'Green armor'), (Num: 2019; Name: 'Blue armor'),
    (Num: 2013; Name: 'Soulsphere'), (Num: 2022; Name: 'Invulnerability'), (Num: 2023; Name: 'Berserk'),
    (Num: 2024; Name: 'Invisibility'), (Num: 2025; Name: 'Radiation suit'), (Num: 2026; Name: 'Computer map'),
    (Num: 5; Name: 'Blue keycard'), (Num: 6; Name: 'Yellow keycard'), (Num: 13; Name: 'Red keycard'),
    (Num: 2035; Name: 'Barrel'), (Num: 2028; Name: 'Floor lamp'), (Num: 48; Name: 'Tech column'),
    (Num: 34; Name: 'Candle'), (Num: 35; Name: 'Candelabra'), (Num: 46; Name: 'Red torch')
  );

  LineSpecials: array [0..13] of TThingChoice = (
    (Num: 0; Name: 'none'), (Num: 1; Name: 'DR door'), (Num: 26; Name: 'DR blue door'),
    (Num: 27; Name: 'DR yellow door'), (Num: 28; Name: 'DR red door'), (Num: 31; Name: 'D1 door, stays open'),
    (Num: 11; Name: 'S1 exit'), (Num: 51; Name: 'S1 secret exit'), (Num: 52; Name: 'W1 exit'),
    (Num: 88; Name: 'WR lift (tag)'), (Num: 62; Name: 'SR lift (tag)'), (Num: 97; Name: 'WR teleport (tag)'),
    (Num: 103; Name: 'S1 open door (tag)'), (Num: 46; Name: 'GR open door (tag)')
  );

  SectorSpecials: array [0..8] of TThingChoice = (
    (Num: 0; Name: 'none'), (Num: 1; Name: 'random blink'), (Num: 2; Name: 'fast blink'),
    (Num: 8; Name: 'glow'), (Num: 9; Name: 'secret'), (Num: 7; Name: 'damage 5'),
    (Num: 5; Name: 'damage 10'), (Num: 16; Name: 'damage 20'), (Num: 17; Name: 'flicker')
  );

  ModeNames: array [TEditMode] of String = ('Vertices', 'Lines', 'Sectors', 'Things');
  Grids: array [0..5] of Integer = (1, 8, 16, 32, 64, 128);

  HelpText =
    'V L S T  vertices / lines / sectors / things' + #10 +
    'Click  select, drag  move' + #10 +
    'Right / middle drag, arrows  pan' + #10 +
    'Wheel, + -  zoom    Z  fit    G  grid' + #10 +
    'N  draw a room (click corners, Enter)' + #10 +
    'Sector: PgUp PgDn floor (Shift: ceiling)' + #10 +
    '  B light  F C flats  P special  D door' + #10 +
    'Line: W texture  P special  X split' + #10 +
    ', .  tag (things: turn)' + #10 +
    'Things: A / Insert add  [ ]  type  Del' + #10 +
    'Shift: backwards / ceiling' + #10 +
    'Ctrl+Z / Ctrl+Y  undo / redo' + #10 +
    'F9  play-test (F7 in the game: back)' + #10 +
    'F2  export PWAD   F3 glTF   F4 X3D' + #10 +
    'Ctrl+PgUp / PgDn  other map    Esc  leave';

function ChoiceName(const Choices: array of TThingChoice; const Num: Integer): String;
var
  I: Integer;
begin
  for I := 0 to High(Choices) do
    if Choices[I].Num = Num then Exit(Choices[I].Name);
  Result := IntToStr(Num);
end;

function ChoiceIndex(const Choices: array of TThingChoice; const Num: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Choices) do
    if Choices[I].Num = Num then Exit(I);
  Result := -1;
end;

function EditorThingName(const TypeNum: Integer): String;
var
  Info: PThingInfo;
begin
  if ChoiceIndex(ThingChoices, TypeNum) >= 0 then
    Exit(ChoiceName(ThingChoices, TypeNum));
  Info := FindThingInfo(TypeNum);
  if Info <> nil then
    Result := Format('type %d (%s)', [TypeNum, Info^.Sprite])
  else
    Result := Format('type %d', [TypeNum]);
end;

{ A key by a script's name: PageUp, Escape... or KeyToStr's. }
function KeyByName(const Name: String): TKey;
var
  K: TKey;
begin
  if SameText(Name, 'PageUp') then Exit(keyPageUp);
  if SameText(Name, 'PageDown') then Exit(keyPageDown);
  if SameText(Name, 'Escape') then Exit(keyEscape);
  if SameText(Name, 'Enter') then Exit(keyEnter);
  if SameText(Name, 'Delete') then Exit(keyDelete);
  for K := Low(TKey) to High(TKey) do
    if (K <> keyNone) and SameText(KeyToStr(K), Name) then Exit(K);
  Result := keyNone;
end;

procedure RemoveEditedWads(const Wad: TDoomWad);
var
  Name: String;
begin
  if Wad = nil then Exit;
  while (Wad.FileUrls.Count > 1) and IsEditedWadUrl(Wad.FileUrls[Wad.FileUrls.Count - 1], Name) do
    Wad.RemoveLastFile;
end;

{ TViewEdit ------------------------------------------------------------------ }

constructor TViewEdit.Create(AOwner: TComponent);
begin
  inherited;
  FEdit := TDoomEditMap.Create;
  FGrid := 32;
  FScale := 0.5;
  FSelected := -1;
  FHover := -1;
  FMode := emSectors;
  FThingType := 7; { the imp }
  Skill := 2;
end;

destructor TViewEdit.Destroy;
begin
  FreeAndNil(FEdit);
  FreeAndNil(FTextures);
  FreeAndNil(FFlats);
  FreeAndNil(FSteps);
  inherited;
end;

procedure TViewEdit.Start;

  function NewLabel(const Size: Single; const Color: TCastleColor): TCastleLabel;
  begin
    Result := TCastleLabel.Create(FreeAtStop);
    Result.FontSize := Size;
    Result.Color := Color;
    InsertFront(Result);
  end;

begin
  inherited;
  PlayTesting := false;
  RemoveEditedWads(Wad);
  FreeAndNil(FTextures);
  FreeAndNil(FFlats);
  FTextures := Wad.TextureNames;
  FFlats := Wad.FlatNames;
  if Fresh or (FEdit.Name = '') then
  begin
    Fresh := false;
    LoadMap(MapName);
  end else
    WritelnLog('Editor', 'Back to %s', [FEdit.Summary]);
  if Music <> nil then Music.Stop;

  FTitle := NewLabel(16, Vector4(1, 0.85, 0.4, 1));
  FTitle.Anchor(hpLeft, 10);
  FTitle.Anchor(vpTop, -8);
  FInfo := NewLabel(14, Vector4(0.9, 0.9, 0.9, 1));
  FInfo.Anchor(hpLeft, 10);
  FInfo.Anchor(vpBottom, 8);
  FMessageLabel := NewLabel(15, Vector4(0.6, 1, 0.6, 1));
  FMessageLabel.Anchor(hpMiddle);
  FMessageLabel.Anchor(vpTop, -34);
  FHelpLabel := NewLabel(13, Vector4(0.85, 0.9, 1, 1));
  FHelpLabel.Anchor(hpRight, -10);
  FHelpLabel.Anchor(vpTop, -34);
  FHelpLabel.Caption := HelpText;
  FHelpLabel.Padding := 6;
  FHelpLabel.Exists := FHelp;

  FreeAndNil(FSteps);
  if AutoTestDemo <> '' then
  begin
    FSteps := TStringList.Create;
    FSteps.Delimiter := ',';
    FSteps.StrictDelimiter := true;
    FSteps.DelimitedText := AutoTestDemo;
    FStep := 0;
    FWait := 0;
  end;
  UpdateLabels;
end;

procedure TViewEdit.Stop;
begin
  FDragging := false;
  FPanning := false;
  inherited;
end;

procedure TViewEdit.LoadMap(const AMapName: String);
var
  Error: String;
begin
  if not FEdit.LoadFromWad(Wad, AMapName, Error) then
  begin
    WritelnWarning('Editor', 'Cannot edit %s: %s', [AMapName, Error]);
    FEdit.Clear(AMapName);
    Message(Error + '; a new map instead');
  end else
    Message('Editing ' + FEdit.Name);
  MapName := FEdit.Name;
  WritelnLog('Editor', 'Imported %s from %s', [FEdit.Summary, Wad.Description]);
  FSelected := -1;
  FHover := -1;
  FDrawing := false;
  ZoomToFit;
end;

procedure TViewEdit.ZoomToFit;
var
  X1, Y1, X2, Y2: Integer;
  W, H: Single;
begin
  FEdit.Bounds(X1, Y1, X2, Y2);
  FCenterX := (X1 + X2) / 2;
  FCenterY := (Y1 + Y2) / 2;
  if Container <> nil then
  begin
    W := Container.PixelsWidth;
    H := Container.PixelsHeight;
  end else
  begin
    W := 1280;
    H := 720;
  end;
  FScale := Min((W - 40) / Max(64, X2 - X1), (H - 120) / Max(64, Y2 - Y1));
end;

function TViewEdit.ScreenOf(const X, Y: Single): TVector2;
begin
  Result := Vector2(Container.PixelsWidth / 2 + (X - FCenterX) * FScale,
    Container.PixelsHeight / 2 + (Y - FCenterY) * FScale);
end;

function TViewEdit.DoomOf(const P: TVector2): TVector2;
begin
  Result := Vector2(FCenterX + (P.X - Container.PixelsWidth / 2) / FScale,
    FCenterY + (P.Y - Container.PixelsHeight / 2) / FScale);
end;

function TViewEdit.Snap(const P: TVector2): TEditPoint;
var
  D: TVector2;
begin
  D := DoomOf(P);
  Result.X := Round(D.X / FGrid) * FGrid;
  Result.Y := Round(D.Y / FGrid) * FGrid;
end;

function TViewEdit.SnapToVertex(const P: TVector2): TEditPoint;
var
  D: TVector2;
  V: Integer;
begin
  D := DoomOf(P);
  V := FEdit.NearestVertex(D.X, D.Y, PickRadius);
  if V >= 0 then
  begin
    Result.X := FEdit.Vertices[V].X;
    Result.Y := FEdit.Vertices[V].Y;
  end else
    Result := Snap(P);
end;

function TViewEdit.PickRadius: Single;
begin
  Result := 10 / FScale;
end;

function TViewEdit.Pick(const P: TVector2): Integer;
var
  D: TVector2;
begin
  D := DoomOf(P);
  case FMode of
    emVertices: Result := FEdit.NearestVertex(D.X, D.Y, PickRadius);
    emLines: Result := FEdit.NearestLine(D.X, D.Y, PickRadius);
    emSectors: Result := FEdit.SectorAt(D.X, D.Y);
    else Result := FEdit.NearestThing(D.X, D.Y, Max(PickRadius, 20));
  end;
end;

procedure TViewEdit.Message(const Text: String);
begin
  if FMessageLabel <> nil then
    FMessageLabel.Caption := Text;
  FMessageTime := 4;
end;

procedure TViewEdit.LogAction(const Text: String);
begin
  Message(Text);
  WritelnLog('Editor', Text);
end;

procedure TViewEdit.SetMode(const Mode: TEditMode);
begin
  if FMode = Mode then Exit;
  FMode := Mode;
  FSelected := -1;
  FHover := -1;
  WritelnLog('Editor', 'Mode %s', [ModeNames[Mode]]);
end;

procedure TViewEdit.Zoom(const Factor: Single; const At: TVector2);
var
  Before, After: TVector2;
begin
  Before := DoomOf(At);
  FScale := EnsureRange(FScale * Factor, 0.02, 16);
  After := DoomOf(At);
  FCenterX := FCenterX + Before.X - After.X;
  FCenterY := FCenterY + Before.Y - After.Y;
end;

function TViewEdit.SelectionInfo: String;
var
  S: TEditSector;
  L: TEditLine;
  T: TEditThing;
  Side: String;

  function SideText(const Index: Integer): String;
  begin
    if Index < 0 then Exit('-');
    Result := Format('sector %d, upper %s, middle %s, lower %s', [FEdit.Sides[Index].Sector,
      FEdit.Sides[Index].Upper, FEdit.Sides[Index].Middle, FEdit.Sides[Index].Lower]);
  end;

begin
  Result := '';
  if FSelected < 0 then Exit;
  case FMode of
    emVertices:
      if FSelected <= High(FEdit.Vertices) then
        Result := Format('Vertex %d at %d, %d', [FSelected, FEdit.Vertices[FSelected].X, FEdit.Vertices[FSelected].Y]);
    emLines:
      if FSelected <= High(FEdit.Lines) then
      begin
        L := FEdit.Lines[FSelected];
        Side := 'one-sided';
        if L.Side[1] >= 0 then Side := 'two-sided';
        Result := Format('Line %d (%s), length %d, special %s, tag %d, flags %d', [FSelected, Side,
          Round(Sqrt(Sqr(FEdit.Vertices[L.V2].X - FEdit.Vertices[L.V1].X) + Sqr(FEdit.Vertices[L.V2].Y - FEdit.Vertices[L.V1].Y))),
          ChoiceName(LineSpecials, L.Special), L.Tag, L.Flags]) + #10 +
          '  front: ' + SideText(L.Side[0]) + #10 + '  back: ' + SideText(L.Side[1]);
      end;
    emSectors:
      if FSelected <= High(FEdit.Sectors) then
      begin
        S := FEdit.Sectors[FSelected];
        Result := Format('Sector %d: floor %d %s, ceiling %d %s, light %d, special %s, tag %d', [FSelected,
          S.Floor, S.FloorTex, S.Ceiling, S.CeilingTex, S.Light, ChoiceName(SectorSpecials, S.Special), S.Tag]);
      end;
    emThings:
      if FSelected <= High(FEdit.Things) then
      begin
        T := FEdit.Things[FSelected];
        Result := Format('Thing %d: %s at %d, %d, angle %d, flags %d', [FSelected, EditorThingName(T.TypeNum),
          T.X, T.Y, T.Angle, T.Flags]);
      end;
  end;
end;

procedure TViewEdit.UpdateLabels;
var
  D: TVector2;
  Info, Modified: String;
begin
  if FTitle = nil then Exit;
  Modified := '';
  if FEdit.Modified then Modified := ' (modified)';
  FTitle.Caption := Format('MAP EDITOR  %s%s   %s mode   grid %d   %d sectors, %d lines, %d things   H: keys', [
    FEdit.Name, Modified, ModeNames[FMode], FGrid, Length(FEdit.Sectors), Length(FEdit.Lines), Length(FEdit.Things)]);
  D := DoomOf(FMouse);
  Info := SelectionInfo;
  if Info = '' then
  begin
    if FMode = emThings then
      Info := 'New things: ' + ThingChoices[FThingType].Name + ' (A to add, [ ] to choose)'
    else if FDrawing then
      Info := Format('Drawing a room: %d corners (click the first one or Enter to close, Backspace, Esc)', [Length(FDrawPoints)])
    else
      Info := 'Nothing selected';
  end;
  FInfo.Caption := Info + #10 + Format('Mouse at %d, %d', [Round(D.X), Round(D.Y)]);
  FHelpLabel.Exists := FHelp;
end;

{ Drawing ------------------------------------------------------------------- }

procedure TViewEdit.Render;
const
  ColorBack: TCastleColor = (X: 0.08; Y: 0.09; Z: 0.12; W: 1);
  ColorGrid: TCastleColor = (X: 0.16; Y: 0.18; Z: 0.25; W: 1);
  ColorAxis: TCastleColor = (X: 0.25; Y: 0.28; Z: 0.4; W: 1);
  ColorWall: TCastleColor = (X: 0.92; Y: 0.92; Z: 0.92; W: 1);
  ColorTwoSided: TCastleColor = (X: 0.5; Y: 0.52; Z: 0.58; W: 1);
  ColorSpecial: TCastleColor = (X: 0.4; Y: 0.85; Z: 1; W: 1);
  ColorSelected: TCastleColor = (X: 1; Y: 0.55; Z: 0.1; W: 1);
  ColorHover: TCastleColor = (X: 1; Y: 0.9; Z: 0.3; W: 1);
  ColorVertex: TCastleColor = (X: 0.6; Y: 0.8; Z: 1; W: 1);
  ColorMonster: TCastleColor = (X: 1; Y: 0.35; Z: 0.3; W: 1);
  ColorItem: TCastleColor = (X: 0.4; Y: 0.95; Z: 0.5; W: 1);
  ColorOther: TCastleColor = (X: 0.75; Y: 0.6; Z: 1; W: 1);
  ColorDraw: TCastleColor = (X: 0.3; Y: 1; Z: 0.5; W: 1);
var
  Grid, Walls, TwoSided, Specials, Ticks, Marked, Hovered: array of TVector2;
  NW, NT, NS, NK, NM, NH, I, K, G: Integer;
  A, B, Mid, Dir: TVector2;
  X0, X1, Y0, Y1, X, Y, R: Single;
  Info: PThingInfo;
  Color: TCastleColor;
  Box: array [0..9] of TVector2;
  Sel: Boolean;

  procedure Add(var Arr: array of TVector2; var N: Integer; const P, Q: TVector2);
  begin
    Arr[N] := P;
    Arr[N + 1] := Q;
    Inc(N, 2);
  end;

  function LineMarked(const L: Integer; const Index: Integer): Boolean;
  begin
    Result := false;
    if Index < 0 then Exit;
    case FMode of
      emLines: Result := L = Index;
      emSectors: Result := (FEdit.LineSector(L, 0) = Index) or (FEdit.LineSector(L, 1) = Index);
      else ;
    end;
  end;

begin
  inherited;
  DrawRectangle(FloatRectangle(0, 0, Container.PixelsWidth, Container.PixelsHeight), ColorBack);

  { The grid, when its cells are at least 8 pixels. }
  G := FGrid;
  while G * FScale < 8 do G := G * 2;
  X0 := DoomOf(Vector2(0, 0)).X;
  Y0 := DoomOf(Vector2(0, 0)).Y;
  X1 := DoomOf(Vector2(Container.PixelsWidth, Container.PixelsHeight)).X;
  Y1 := DoomOf(Vector2(Container.PixelsWidth, Container.PixelsHeight)).Y;
  SetLength(Grid, 2 * (Ceil((X1 - X0) / G) + Ceil((Y1 - Y0) / G) + 4));
  K := 0;
  X := Floor(X0 / G) * G;
  while (X <= X1) and (K < High(Grid)) do
  begin
    Grid[K] := Vector2(ScreenOf(X, 0).X, 0);
    Grid[K + 1] := Vector2(ScreenOf(X, 0).X, Container.PixelsHeight);
    Inc(K, 2);
    X := X + G;
  end;
  Y := Floor(Y0 / G) * G;
  while (Y <= Y1) and (K < High(Grid)) do
  begin
    Grid[K] := Vector2(0, ScreenOf(0, Y).Y);
    Grid[K + 1] := Vector2(Container.PixelsWidth, ScreenOf(0, Y).Y);
    Inc(K, 2);
    Y := Y + G;
  end;
  if K > 0 then DrawPrimitive2D(pmLines, Slice(Grid, K), ColorGrid);
  A := ScreenOf(0, 0);
  DrawPrimitive2D(pmLines, [Vector2(A.X, 0), Vector2(A.X, Container.PixelsHeight),
    Vector2(0, A.Y), Vector2(Container.PixelsWidth, A.Y)], ColorAxis);

  { The lines, with a tick on their front side. }
  SetLength(Walls, 2 * Length(FEdit.Lines));
  SetLength(TwoSided, 2 * Length(FEdit.Lines));
  SetLength(Specials, 2 * Length(FEdit.Lines));
  SetLength(Ticks, 2 * Length(FEdit.Lines));
  SetLength(Marked, 2 * Length(FEdit.Lines));
  SetLength(Hovered, 2 * Length(FEdit.Lines));
  NW := 0; NT := 0; NS := 0; NK := 0; NM := 0; NH := 0;
  for I := 0 to High(FEdit.Lines) do
  begin
    A := ScreenOf(FEdit.Vertices[FEdit.Lines[I].V1].X, FEdit.Vertices[FEdit.Lines[I].V1].Y);
    B := ScreenOf(FEdit.Vertices[FEdit.Lines[I].V2].X, FEdit.Vertices[FEdit.Lines[I].V2].Y);
    if LineMarked(I, FSelected) then
      Add(Marked, NM, A, B)
    else if LineMarked(I, FHover) then
      Add(Hovered, NH, A, B)
    else if FEdit.Lines[I].Special <> 0 then
      Add(Specials, NS, A, B)
    else if FEdit.Lines[I].Side[1] >= 0 then
      Add(TwoSided, NT, A, B)
    else
      Add(Walls, NW, A, B);
    if (FMode = emLines) and ((B - A).Length > 12) then
    begin
      Mid := (A + B) / 2;
      Dir := (B - A).Normalize;
      Add(Ticks, NK, Mid, Mid + Vector2(Dir.Y, -Dir.X) * 5);
    end;
  end;
  if NT > 0 then DrawPrimitive2D(pmLines, Slice(TwoSided, NT), ColorTwoSided);
  if NW > 0 then DrawPrimitive2D(pmLines, Slice(Walls, NW), ColorWall);
  if NS > 0 then DrawPrimitive2D(pmLines, Slice(Specials, NS), ColorSpecial);
  if NK > 0 then DrawPrimitive2D(pmLines, Slice(Ticks, NK), ColorTwoSided);
  if NH > 0 then DrawPrimitive2D(pmLines, Slice(Hovered, NH), ColorHover, bsSrcAlpha, bdOneMinusSrcAlpha, false, 2);
  if NM > 0 then DrawPrimitive2D(pmLines, Slice(Marked, NM), ColorSelected, bsSrcAlpha, bdOneMinusSrcAlpha, false, 3);

  { Vertices. }
  if FMode = emVertices then
    for I := 0 to High(FEdit.Vertices) do
    begin
      A := ScreenOf(FEdit.Vertices[I].X, FEdit.Vertices[I].Y);
      if (A.X < -4) or (A.Y < -4) or (A.X > Container.PixelsWidth + 4) or (A.Y > Container.PixelsHeight + 4) then Continue;
      if I = FSelected then Color := ColorSelected
      else if I = FHover then Color := ColorHover
      else Color := ColorVertex;
      R := 2;
      if (I = FSelected) or (I = FHover) then R := 4;
      DrawRectangle(FloatRectangle(A.X - R, A.Y - R, 2 * R, 2 * R), Color);
    end;

  { Things: a box of their radius and their facing. }
  for I := 0 to High(FEdit.Things) do
  begin
    A := ScreenOf(FEdit.Things[I].X, FEdit.Things[I].Y);
    if (A.X < -40) or (A.Y < -40) or (A.X > Container.PixelsWidth + 40) or (A.Y > Container.PixelsHeight + 40) then Continue;
    Info := FindThingInfo(FEdit.Things[I].TypeNum);
    R := 16;
    Color := ColorOther;
    if Info <> nil then
    begin
      R := Max(8, Info^.Radius);
      if Info^.Kind = tkMonster then Color := ColorMonster
      else if Info^.Kind = tkPickup then Color := ColorItem;
    end;
    Sel := (FMode = emThings) and (I = FSelected);
    if Sel then Color := ColorSelected
    else if (FMode = emThings) and (I = FHover) then Color := ColorHover
    else if FMode <> emThings then Color.W := 0.6;
    R := Max(3, R * FScale);
    Box[0] := A + Vector2(-R, -R); Box[1] := A + Vector2(R, -R);
    Box[2] := A + Vector2(R, -R); Box[3] := A + Vector2(R, R);
    Box[4] := A + Vector2(R, R); Box[5] := A + Vector2(-R, R);
    Box[6] := A + Vector2(-R, R); Box[7] := A + Vector2(-R, -R);
    Box[8] := A;
    Box[9] := A + Vector2(Cos(DegToRad(FEdit.Things[I].Angle)), Sin(DegToRad(FEdit.Things[I].Angle))) * R * 1.3;
    if Sel then
      DrawPrimitive2D(pmLines, Box, Color, bsSrcAlpha, bdOneMinusSrcAlpha, false, 2)
    else
      DrawPrimitive2D(pmLines, Box, Color, bsSrcAlpha, bdOneMinusSrcAlpha, FMode <> emThings);
  end;

  { The room being drawn. }
  if FDrawing then
  begin
    SetLength(Grid, 2 * Length(FDrawPoints) + 2);
    K := 0;
    for I := 0 to High(FDrawPoints) do
    begin
      A := ScreenOf(FDrawPoints[I].X, FDrawPoints[I].Y);
      if I < High(FDrawPoints) then
        B := ScreenOf(FDrawPoints[I + 1].X, FDrawPoints[I + 1].Y)
      else
        B := ScreenOf(SnapToVertex(FMouse).X, SnapToVertex(FMouse).Y);
      Add(Grid, K, A, B);
      DrawRectangle(FloatRectangle(A.X - 3, A.Y - 3, 6, 6), ColorDraw);
    end;
    if K > 0 then DrawPrimitive2D(pmLines, Slice(Grid, K), ColorDraw, bsSrcAlpha, bdOneMinusSrcAlpha, false, 2);
    A := ScreenOf(SnapToVertex(FMouse).X, SnapToVertex(FMouse).Y);
    DrawRectangle(FloatRectangle(A.X - 3, A.Y - 3, 6, 6), ColorHover);
  end;

  { The help panel's background (the label draws after this). }
  if (FHelpLabel <> nil) and FHelpLabel.Exists then
    DrawRectangle(FHelpLabel.RenderRect, Vector4(0.1, 0.12, 0.2, 0.9));
end;

{ Input --------------------------------------------------------------------- }

procedure TViewEdit.MouseDown(const P: TVector2; const Button: TCastleMouseButton);
var
  I, Line: Integer;
  Seen: array of Boolean;

  procedure TakeVertex(const V: Integer);
  begin
    if Seen[V] then Exit;
    Seen[V] := true;
    SetLength(FDragVertices, Length(FDragVertices) + 1);
    FDragVertices[High(FDragVertices)] := V;
  end;

begin
  FMouse := P;
  if Button <> buttonLeft then
  begin
    FPanning := true;
    FPanLast := P;
    Exit;
  end;
  if FDrawing then
  begin
    AddDrawPoint(SnapToVertex(P));
    Exit;
  end;
  FSelected := Pick(P);
  FDragging := FSelected >= 0;
  FDragMoved := false;
  if not FDragging then
  begin
    UpdateLabels;
    Exit;
  end;
  FDragStart := Snap(P);
  { What moves: the vertex, the line's or the sector's vertices, the thing. }
  FDragVertices := nil;
  SetLength(Seen, Length(FEdit.Vertices));
  case FMode of
    emVertices: TakeVertex(FSelected);
    emLines:
      begin
        TakeVertex(FEdit.Lines[FSelected].V1);
        TakeVertex(FEdit.Lines[FSelected].V2);
      end;
    emSectors:
      for Line := 0 to High(FEdit.Lines) do
        if (FEdit.LineSector(Line, 0) = FSelected) or (FEdit.LineSector(Line, 1) = FSelected) then
        begin
          TakeVertex(FEdit.Lines[Line].V1);
          TakeVertex(FEdit.Lines[Line].V2);
        end;
    else ;
  end;
  if FMode = emThings then
  begin
    SetLength(FDragOrigins, 1);
    FDragOrigins[0].X := FEdit.Things[FSelected].X;
    FDragOrigins[0].Y := FEdit.Things[FSelected].Y;
  end else
  begin
    SetLength(FDragOrigins, Length(FDragVertices));
    for I := 0 to High(FDragVertices) do
    begin
      FDragOrigins[I].X := FEdit.Vertices[FDragVertices[I]].X;
      FDragOrigins[I].Y := FEdit.Vertices[FDragVertices[I]].Y;
    end;
  end;
  UpdateLabels;
end;

procedure TViewEdit.MouseMove(const P: TVector2);
var
  Pt: TEditPoint;
  DX, DY, I: Integer;
begin
  if FPanning then
  begin
    FCenterX := FCenterX - (P.X - FPanLast.X) / FScale;
    FCenterY := FCenterY - (P.Y - FPanLast.Y) / FScale;
    FPanLast := P;
  end;
  FMouse := P;
  if FDragging then
  begin
    Pt := Snap(P);
    DX := Pt.X - FDragStart.X;
    DY := Pt.Y - FDragStart.Y;
    if (DX <> 0) or (DY <> 0) or FDragMoved then
    begin
      if not FDragMoved then
      begin
        FEdit.Snapshot;
        FDragMoved := true;
      end;
      if FMode = emThings then
      begin
        FEdit.Things[FSelected].X := FDragOrigins[0].X + DX;
        FEdit.Things[FSelected].Y := FDragOrigins[0].Y + DY;
      end else
        for I := 0 to High(FDragVertices) do
        begin
          FEdit.Vertices[FDragVertices[I]].X := FDragOrigins[I].X + DX;
          FEdit.Vertices[FDragVertices[I]].Y := FDragOrigins[I].Y + DY;
        end;
    end;
  end else
  if not FDrawing then
    FHover := Pick(P);
  UpdateLabels;
end;

procedure TViewEdit.MouseUp(const P: TVector2; const Button: TCastleMouseButton);
var
  Pt: TEditPoint;
begin
  if Button <> buttonLeft then
  begin
    FPanning := false;
    Exit;
  end;
  if not FDragging then Exit;
  FDragging := false;
  if not FDragMoved then Exit;
  Pt := Snap(P);
  case FMode of
    emVertices:
      begin
        { Dropped on another vertex: they merge. }
        Pt.X := FEdit.Vertices[FSelected].X;
        Pt.Y := FEdit.Vertices[FSelected].Y;
        if FEdit.MergeVertex(FSelected) then
        begin
          FSelected := -1;
          LogAction(Format('Merged vertices at %d, %d', [Pt.X, Pt.Y]));
        end else
          LogAction(Format('Moved vertex to %d, %d', [Pt.X, Pt.Y]));
      end;
    emThings:
      LogAction(Format('Moved thing %d to %d, %d', [FSelected, FEdit.Things[FSelected].X, FEdit.Things[FSelected].Y]));
    else
      LogAction(Format('Moved %s %d by %d, %d', [LowerCase(Copy(ModeNames[FMode], 1, Length(ModeNames[FMode]) - 1)),
        FSelected, Pt.X - FDragStart.X, Pt.Y - FDragStart.Y]));
  end;
  UpdateLabels;
end;

procedure TViewEdit.AddDrawPoint(const Pt: TEditPoint);
begin
  if (Length(FDrawPoints) >= 3) and (FDrawPoints[0].X = Pt.X) and (FDrawPoints[0].Y = Pt.Y) then
  begin
    FinishDrawing;
    Exit;
  end;
  SetLength(FDrawPoints, Length(FDrawPoints) + 1);
  FDrawPoints[High(FDrawPoints)] := Pt;
  UpdateLabels;
end;

procedure TViewEdit.FinishDrawing;
var
  Sec: Integer;
  Error: String;
begin
  FDrawing := false;
  Sec := FEdit.DrawSector(FDrawPoints, Error);
  if Sec < 0 then
  begin
    LogAction('Cannot draw the room: ' + Error);
    WritelnWarning('Editor', 'Room refused: %s', [Error]);
  end else
  begin
    LogAction(Format('Room drawn: sector %d with %d corners, floor %d, ceiling %d', [Sec, Length(FDrawPoints),
      FEdit.Sectors[Sec].Floor, FEdit.Sectors[Sec].Ceiling]));
    SetMode(emSectors);
    FSelected := Sec;
  end;
  FDrawPoints := nil;
  UpdateLabels;
end;

function TViewEdit.CycleName(const List: TStrings; const Current: String; const Delta: Integer): String;
var
  I: Integer;
begin
  if (List = nil) or (List.Count = 0) then Exit(Current);
  I := List.IndexOf(UpperCase(Current));
  if I < 0 then I := 0 else I := (I + Delta + List.Count * 10) mod List.Count;
  Result := List[I];
end;

procedure TViewEdit.ChangeWall(const Delta: Integer);
var
  L: TEditLine;
  S: Integer;
  Tex: String;
begin
  L := FEdit.Lines[FSelected];
  S := L.Side[0];
  if S < 0 then S := L.Side[1];
  if S < 0 then Exit;
  FEdit.Snapshot;
  if L.Side[1] < 0 then
  begin
    Tex := CycleName(FTextures, FEdit.Sides[S].Middle, Delta);
    FEdit.Sides[S].Middle := Tex;
  end else
  begin
    Tex := FEdit.Sides[S].Lower;
    if (Tex = '') or (Tex = '-') then Tex := FEdit.Sides[S].Upper;
    Tex := CycleName(FTextures, Tex, Delta);
    FEdit.Sides[L.Side[0]].Upper := Tex;
    FEdit.Sides[L.Side[0]].Lower := Tex;
    FEdit.Sides[L.Side[1]].Upper := Tex;
    FEdit.Sides[L.Side[1]].Lower := Tex;
  end;
  LogAction(Format('Line %d wall %s', [FSelected, Tex]));
end;

procedure TViewEdit.CycleSpecial(const Delta: Integer);
var
  I: Integer;
begin
  FEdit.Snapshot;
  if FMode = emLines then
  begin
    I := ChoiceIndex(LineSpecials, FEdit.Lines[FSelected].Special);
    I := (Max(I, 0) + Delta + Length(LineSpecials)) mod Length(LineSpecials);
    FEdit.Lines[FSelected].Special := LineSpecials[I].Num;
    LogAction(Format('Line %d special %d (%s)', [FSelected, LineSpecials[I].Num, LineSpecials[I].Name]));
  end else
  begin
    I := ChoiceIndex(SectorSpecials, FEdit.Sectors[FSelected].Special);
    I := (Max(I, 0) + Delta + Length(SectorSpecials)) mod Length(SectorSpecials);
    FEdit.Sectors[FSelected].Special := SectorSpecials[I].Num;
    LogAction(Format('Sector %d special %d (%s)', [FSelected, SectorSpecials[I].Num, SectorSpecials[I].Name]));
  end;
end;

procedure TViewEdit.ChangeTag(const Delta: Integer);
begin
  FEdit.Snapshot;
  if FMode = emLines then
  begin
    FEdit.Lines[FSelected].Tag := Max(0, FEdit.Lines[FSelected].Tag + Delta);
    LogAction(Format('Line %d tag %d', [FSelected, FEdit.Lines[FSelected].Tag]));
  end else
  begin
    FEdit.Sectors[FSelected].Tag := Max(0, FEdit.Sectors[FSelected].Tag + Delta);
    LogAction(Format('Sector %d tag %d', [FSelected, FEdit.Sectors[FSelected].Tag]));
  end;
end;

procedure TViewEdit.CycleThingType(const Delta: Integer);
var
  I: Integer;
begin
  if (FMode = emThings) and (FSelected >= 0) then
  begin
    I := ChoiceIndex(ThingChoices, FEdit.Things[FSelected].TypeNum);
    if I < 0 then I := FThingType;
    I := (I + Delta + Length(ThingChoices)) mod Length(ThingChoices);
    FEdit.Snapshot;
    FEdit.Things[FSelected].TypeNum := ThingChoices[I].Num;
    FThingType := I;
    LogAction(Format('Thing %d is now a %s', [FSelected, ThingChoices[I].Name]));
  end else
  begin
    FThingType := (FThingType + Delta + Length(ThingChoices)) mod Length(ThingChoices);
    Message('New things: ' + ThingChoices[FThingType].Name);
  end;
end;

function TViewEdit.HandleKey(const Key: TKey; const Shift, Ctrl: Boolean): Boolean;
var
  Pt: TEditPoint;
  D: TVector2;
  V, Dir: Integer;
begin
  Result := true;
  Dir := 1;
  if Shift then Dir := -1;
  if FDrawing then
    case Key of
      keyEnter:
        begin
          FinishDrawing;
          Exit;
        end;
      keyBackSpace:
        begin
          if Length(FDrawPoints) > 0 then SetLength(FDrawPoints, Length(FDrawPoints) - 1);
          UpdateLabels;
          Exit;
        end;
      keyEscape:
        begin
          FDrawing := false;
          FDrawPoints := nil;
          Message('Room cancelled');
          UpdateLabels;
          Exit;
        end;
      else ;
    end;
  if Ctrl then
  begin
    case Key of
      keyZ:
        if Shift then
        begin
          if FEdit.Redo then LogAction('Redone') else Message('Nothing to redo');
        end else
        begin
          if FEdit.Undo then LogAction('Undone') else Message('Nothing to undo');
        end;
      keyY: if FEdit.Redo then LogAction('Redone') else Message('Nothing to redo');
      keyPageDown: NextMap(1);
      keyPageUp: NextMap(-1);
      else Exit(false);
    end;
    FSelected := -1;
    UpdateLabels;
    Exit;
  end;
  case Key of
    keyV: SetMode(emVertices);
    keyL: SetMode(emLines);
    keyS: SetMode(emSectors);
    keyT: SetMode(emThings);
    keyTab: SetMode(TEditMode((Ord(FMode) + 1) mod 4));
    keyH, keyF1: FHelp := not FHelp;
    keyG:
      begin
        V := 0;
        while (V < High(Grids)) and (Grids[V] <> FGrid) do Inc(V);
        FGrid := Grids[(V + Dir + Length(Grids)) mod Length(Grids)];
        Message(Format('Grid %d', [FGrid]));
      end;
    keyZ: ZoomToFit;
    keyPlus, keyNumpadPlus, keyEqual: Zoom(1.25, Vector2(Container.PixelsWidth / 2, Container.PixelsHeight / 2));
    keyMinus, keyNumpadMinus: Zoom(0.8, Vector2(Container.PixelsWidth / 2, Container.PixelsHeight / 2));
    keyArrowLeft: FCenterX := FCenterX - 64 / FScale;
    keyArrowRight: FCenterX := FCenterX + 64 / FScale;
    keyArrowUp: FCenterY := FCenterY + 64 / FScale;
    keyArrowDown: FCenterY := FCenterY - 64 / FScale;
    keyN:
      begin
        FDrawing := true;
        FDrawPoints := nil;
        FSelected := -1;
        Message('Drawing a room: click its corners');
      end;
    keyF9: PlayTest;
    keyF2: ExportWad('');
    keyF3: ExportScene(true, '');
    keyF4: ExportScene(false, '');
    keyEscape:
      if FSelected >= 0 then
        FSelected := -1
      else
        Leave;
    keyA, keyInsert:
      begin
        Pt := Snap(FMouse);
        SetMode(emThings);
        FSelected := FEdit.AddThing(Pt.X, Pt.Y, ThingChoices[FThingType].Num, 90);
        LogAction(Format('Added %s at %d, %d', [ThingChoices[FThingType].Name, Pt.X, Pt.Y]));
      end;
    keyLeftBracket: CycleThingType(-1);
    keyRightBracket: CycleThingType(1);
    else
    begin
      if FSelected < 0 then Exit(false);
      case FMode of
        emSectors:
          case Key of
            keyPageUp, keyPageDown:
              begin
                if Key = keyPageUp then V := 8 else V := -8;
                if Shift then FEdit.ChangeSector(FSelected, 0, V, 0) else FEdit.ChangeSector(FSelected, V, 0, 0);
                LogAction(Format('Sector %d floor %d, ceiling %d', [FSelected,
                  FEdit.Sectors[FSelected].Floor, FEdit.Sectors[FSelected].Ceiling]));
              end;
            keyB:
              begin
                FEdit.ChangeSector(FSelected, 0, 0, 16 * Dir);
                LogAction(Format('Sector %d light %d', [FSelected, FEdit.Sectors[FSelected].Light]));
              end;
            keyF:
              begin
                FEdit.Snapshot;
                FEdit.Sectors[FSelected].FloorTex := CycleName(FFlats, FEdit.Sectors[FSelected].FloorTex, Dir);
                LogAction(Format('Sector %d floor flat %s', [FSelected, FEdit.Sectors[FSelected].FloorTex]));
              end;
            keyC:
              begin
                FEdit.Snapshot;
                FEdit.Sectors[FSelected].CeilingTex := CycleName(FFlats, FEdit.Sectors[FSelected].CeilingTex, Dir);
                LogAction(Format('Sector %d ceiling flat %s', [FSelected, FEdit.Sectors[FSelected].CeilingTex]));
              end;
            keyP: CycleSpecial(Dir);
            keyComma: ChangeTag(-1);
            keyPeriod: ChangeTag(1);
            keyD:
              if FEdit.MakeDoor(FSelected) then
                LogAction(Format('Sector %d is a door', [FSelected]))
              else
                Message('A door needs two-sided lines');
            else Exit(false);
          end;
        emLines:
          case Key of
            keyW: ChangeWall(Dir);
            keyP: CycleSpecial(Dir);
            keyComma: ChangeTag(-1);
            keyPeriod: ChangeTag(1);
            keyX:
              begin
                Pt := Snap(FMouse);
                D := DoomOf(FMouse);
                V := FEdit.SplitLine(FSelected, Round(D.X), Round(D.Y));
                if V >= 0 then
                  LogAction(Format('Line %d split at %d, %d', [FSelected, FEdit.Vertices[V].X, FEdit.Vertices[V].Y]))
                else
                  Message('Split nearer the middle of the line');
              end;
            else Exit(false);
          end;
        emThings:
          case Key of
            keyComma, keyPeriod:
              begin
                FEdit.Snapshot;
                if Key = keyComma then V := 45 else V := -45;
                FEdit.Things[FSelected].Angle := (FEdit.Things[FSelected].Angle + V + 360) mod 360;
                LogAction(Format('Thing %d angle %d', [FSelected, FEdit.Things[FSelected].Angle]));
              end;
            keyDelete:
              begin
                FEdit.DeleteThing(FSelected);
                LogAction(Format('Thing %d deleted', [FSelected]));
                FSelected := -1;
              end;
            else Exit(false);
          end;
        else Exit(false);
      end;
    end;
  end;
  UpdateLabels;
end;

function TViewEdit.Press(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  case Event.EventType of
    itMouseButton:
      begin
        MouseDown(Event.Position, Event.MouseButton);
        Exit(true);
      end;
    itMouseWheel:
      begin
        if Event.MouseWheelScroll > 0 then Zoom(1.2, Event.Position) else Zoom(1 / 1.2, Event.Position);
        UpdateLabels;
        Exit(true);
      end;
    itKey:
      Exit(HandleKey(Event.Key, mkShift in Event.ModifiersDown, mkCtrl in Event.ModifiersDown));
    else ;
  end;
end;

function TViewEdit.Release(const Event: TInputPressRelease): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  if Event.EventType = itMouseButton then
  begin
    MouseUp(Event.Position, Event.MouseButton);
    Exit(true);
  end;
end;

function TViewEdit.Motion(const Event: TInputMotion): Boolean;
begin
  Result := inherited;
  if Result then Exit;
  MouseMove(Event.Position);
  Result := true;
end;

{ Play-test and export -------------------------------------------------------- }

procedure TViewEdit.PlayTest;
var
  Data: TMemoryStream;
  I, Starts: Integer;
begin
  Starts := 0;
  for I := 0 to High(FEdit.Things) do
    if FEdit.Things[I].TypeNum = 1 then Inc(Starts);
  if Starts = 0 then
  begin
    LogAction('Add a player 1 start first (things mode, A)');
    Exit;
  end;
  try
    Data := FEdit.SaveToWad;
  except
    on E: Exception do
    begin
      LogAction('Cannot build the map: ' + E.Message);
      Exit;
    end;
  end;
  try
    RegisterEditedWad(FEdit.Name, Data);
  finally
    FreeAndNil(Data);
  end;
  RemoveEditedWads(Wad);
  Wad.AddFile(EditedWadUrl(FEdit.Name));
  WritelnLog('Editor', 'Play-test %s', [FEdit.Summary]);
  { The rest of an autotest script goes on in the game. }
  if FSteps <> nil then
  begin
    AutoTestDemo := '';
    for I := FStep to FSteps.Count - 1 do
    begin
      if AutoTestDemo <> '' then AutoTestDemo := AutoTestDemo + ',';
      AutoTestDemo := AutoTestDemo + FSteps[I];
    end;
    FreeAndNil(FSteps);
  end;
  ViewPlay.Wad := Wad;
  ViewPlay.Graphics := Graphics;
  ViewPlay.Sounds := Sounds;
  ViewPlay.Music := Music;
  ViewPlay.StartMapName := FEdit.Name;
  ViewPlay.Skill := Skill;
  PlayTesting := true;
  Container.View := ViewPlay;
end;

{$ifdef WASI}
{ The page's castleDoomDownload (tools/patch_web_page.py) saves bytes as
  a file; the plain CGE page has none. }
procedure BrowserDownload(const FileName: String; const Data: TMemoryStream; const Mime: String);
var
  V: TJOB_JSValue;
  Bytes: UnicodeString;
  I: Integer;
  P: PByte;
  HasIt: Boolean;
begin
  V := JSWindow.ReadJSPropertyValue('castleDoomDownload');
  HasIt := (V is TJOB_Object) and (TJOB_Object(V).Value <> nil);
  FreeAndNil(V);
  if not HasIt then
  begin
    WritelnWarning('Editor', 'The page cannot save files');
    Exit;
  end;
  { The bytes as a "binary string": one character per byte. }
  SetLength(Bytes, Data.Size);
  P := PByte(Data.Memory);
  for I := 1 to Data.Size do
    Bytes[I] := WideChar(P[I - 1]);
  JSWindow.InvokeJSNoResult('castleDoomDownload', [UTF8Decode(FileName), Bytes, UTF8Decode(Mime)]);
end;
{$endif}

procedure TViewEdit.ExportWad(const FileName: String);
var
  Data: TMemoryStream;
  Target: String;
begin
  if Length(FEdit.Lines) = 0 then
  begin
    LogAction('The map is empty');
    Exit;
  end;
  try
    Data := FEdit.SaveToWad;
  except
    on E: Exception do
    begin
      LogAction('Cannot build the map: ' + E.Message);
      Exit;
    end;
  end;
  try
    Target := FileName;
    {$ifdef WASI}
    if Target = '' then Target := LowerCase(FEdit.Name) + '.wad';
    BrowserDownload(Target, Data, 'application/octet-stream');
    LogAction(Format('Exported %s as %s', [FEdit.Name, Target]));
    {$else}
    if Target = '' then
    begin
      if AutoTestPrefix <> '' then
        Target := AutoTestPrefix + '_' + LowerCase(FEdit.Name) + '.wad'
      else
        Target := UriToFilenameSafe('castle-config:/' + LowerCase(FEdit.Name) + '-edited.wad');
    end;
    Data.SaveToFile(Target);
    FEdit.Modified := false;
    LogAction(Format('Exported %s to %s', [FEdit.Summary, Target]));
    {$endif}
  finally
    FreeAndNil(Data);
  end;
end;

procedure TViewEdit.ExportScene(const Gltf: Boolean; const FileName: String);
var
  Target, Ext, Error: String;
begin
  {$ifdef WASI}
  { The browser has no files to write a model and its textures to (and an
    exception would stop the program). }
  LogAction('glTF / X3D export is in the desktop version');
  Exit;
  {$endif}
  if Length(FEdit.Lines) = 0 then
  begin
    LogAction('The map is empty');
    Exit;
  end;
  if Gltf then Ext := '.gltf' else Ext := '.x3d';
  Target := FileName;
  if Target = '' then
  begin
    if AutoTestPrefix <> '' then
      Target := AutoTestPrefix + '_' + LowerCase(FEdit.Name) + Ext
    else
      Target := UriToFilenameSafe('castle-config:/' + LowerCase(FEdit.Name) + '-edited' + Ext);
  end;
  { The level as it is edited: its PWAD on top for the export. }
  if not ExportEditedLevel(Wad, Graphics, FEdit, Target, Gltf, Error) then
    LogAction('Cannot export: ' + Error)
  else
    LogAction(Format('Exported the %s level to %s', [FEdit.Name, Target]));
end;

procedure TViewEdit.NextMap(const Delta: Integer);
var
  I: Integer;
begin
  if Wad.MapNames.Count = 0 then Exit;
  I := Wad.MapNames.IndexOf(FEdit.Name);
  I := (I + Delta + Wad.MapNames.Count) mod Wad.MapNames.Count;
  LoadMap(Wad.MapNames[I]);
end;

procedure TViewEdit.Leave;
begin
  WritelnLog('Editor', 'Left the editor');
  Container.View := ViewMenu;
end;

{ Script ---------------------------------------------------------------------- }

{ Autotest commands (--demo with --edit): W:sec, S (screenshot
  prefix_edit_N.png), Q, MODE:v|l|s|t, VIEW:x:y:scale (the screen centre
  in Doom units and pixels a unit), CLICK:x:y (a left click there),
  DRAG:x1:y1:x2:y2, DRAW:x:y:x:y:... (a room), KEY:name or KEY:Shift+name
  / Ctrl+name, MOUSE:x:y (the mouse there), THING:type (the type A adds),
  EXPORT[:file], GLTF[:file], X3D[:file], PLAY (the rest runs in the game). }
procedure TViewEdit.RunStep(const Step: String);
var
  Parts: TStringList;
  Cmd, KeyText: String;
  K: TKey;
  Shift, Ctrl: Boolean;
  I: Integer;
  Pts: TEditPoints;

  function Num(const I: Integer): Single;
  begin
    if I < Parts.Count then Result := StrToFloatDefDot(Parts[I], 0) else Result := 0;
  end;

  function At(const I: Integer): TVector2;
  begin
    Result := ScreenOf(Num(I), Num(I + 1));
  end;

begin
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ':';
    Parts.StrictDelimiter := true;
    Parts.DelimitedText := Step;
    Cmd := UpperCase(Parts[0]);
    if Cmd = 'S' then
    begin
      Inc(FShots);
      Application.MainWindow.SaveScreen(Format('%s_edit_%d.png', [AutoTestPrefix, FShots]));
      WritelnLog('AutoTest', 'Saved editor screenshot %d of %s', [FShots, FEdit.Name]);
    end else
    if Cmd = 'Q' then
      Application.Terminate
    else if Cmd = 'W' then
      FWait := Num(1)
    else if Cmd = 'MODE' then
    begin
      KeyText := UpperCase(Copy(Step, 6, 1));
      if KeyText = 'V' then SetMode(emVertices)
      else if KeyText = 'L' then SetMode(emLines)
      else if KeyText = 'S' then SetMode(emSectors)
      else SetMode(emThings);
    end else
    if Cmd = 'VIEW' then
    begin
      FCenterX := Num(1);
      FCenterY := Num(2);
      FScale := Max(0.02, Num(3));
    end else
    if Cmd = 'MOUSE' then
      MouseMove(At(1))
    else if Cmd = 'CLICK' then
    begin
      MouseMove(At(1));
      MouseDown(At(1), buttonLeft);
      MouseUp(At(1), buttonLeft);
    end else
    if Cmd = 'DRAG' then
    begin
      MouseMove(At(1));
      MouseDown(At(1), buttonLeft);
      MouseMove(At(3));
      MouseUp(At(3), buttonLeft);
    end else
    if Cmd = 'DRAW' then
    begin
      SetLength(Pts, (Parts.Count - 1) div 2);
      for I := 0 to High(Pts) do
      begin
        Pts[I].X := Round(Num(1 + I * 2));
        Pts[I].Y := Round(Num(2 + I * 2));
      end;
      FDrawPoints := Pts;
      FinishDrawing;
    end else
    if Cmd = 'THING' then
    begin
      I := ChoiceIndex(ThingChoices, Round(Num(1)));
      if I >= 0 then FThingType := I;
    end else
    if Cmd = 'KEY' then
    begin
      KeyText := Copy(Step, 5, MaxInt);
      Shift := AnsiStartsText('Shift+', KeyText);
      if Shift then KeyText := Copy(KeyText, 7, MaxInt);
      Ctrl := AnsiStartsText('Ctrl+', KeyText);
      if Ctrl then KeyText := Copy(KeyText, 6, MaxInt);
      K := KeyByName(KeyText);
      if K <> keyNone then
        HandleKey(K, Shift, Ctrl)
      else
        WritelnWarning('Editor', 'Unknown key "%s"', [KeyText]);
    end else
    if Cmd = 'EXPORT' then
      ExportWad(Copy(Step, 8, MaxInt))
    else if Cmd = 'GLTF' then
      ExportScene(true, Copy(Step, 6, MaxInt))
    else if Cmd = 'X3D' then
      ExportScene(false, Copy(Step, 5, MaxInt))
    else if Cmd = 'PLAY' then
      PlayTest
    else
      WritelnWarning('Editor', 'Unknown script step "%s"', [Step]);
  finally
    FreeAndNil(Parts);
  end;
end;

procedure TViewEdit.RunScript(const SecondsPassed: Single);
var
  Step: String;
begin
  if FSteps = nil then Exit;
  if FWait > 0 then
  begin
    FWait := FWait - SecondsPassed;
    Exit;
  end;
  if FStep >= FSteps.Count then
  begin
    Application.Terminate;
    Exit;
  end;
  Step := Trim(FSteps[FStep]);
  Inc(FStep);
  if Step <> '' then RunStep(Step);
end;

procedure TViewEdit.Update(const SecondsPassed: Single; var HandleInput: Boolean);
begin
  inherited;
  if FMessageTime > 0 then
  begin
    FMessageTime := FMessageTime - SecondsPassed;
    if FMessageTime <= 0 then FMessageLabel.Caption := '';
  end;
  RunScript(SecondsPassed);
end;

end.
