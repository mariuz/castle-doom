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
  Shift+click adds to the selection, a drag on nothing (or Ctrl+drag)
  selects a box, Ctrl+A everything; the keys then change all of it.
  Space opens a picker with the pictures of the wall textures (lines) or
  flats (sectors; Shift: ceilings), filtered by typing. Ctrl+C / Ctrl+V
  copy and paste things. A drawn path ending on two walls (Enter instead
  of closing it) cuts the sector in two; Delete removes the selection
  (vertices join their two lines); number keys toggle line and thing
  flags, listed in a panel.
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
  CastleVectors, CastleUIControls, CastleControls, CastleKeysMouse, CastleColors, CastleGLImages,
  DoomWad, DoomGraphics, DoomSound, DoomMusic, DoomEditMap;

type
  TEditMode = (emVertices, emLines, emSectors, emThings);
  TEditIndexArray = array of Integer;

  TViewEdit = class(TCastleView)
  strict private
    FEdit: TDoomEditMap;
    FMode: TEditMode;
    FCenterX, FCenterY, FScale: Single;
    { The selection: FSelected (the last one picked, whose values the
      keys change from) and FMore, the others (Shift+click, box). }
    FSelected, FHover: Integer;
    FMore: array of Integer;
    FGrid: Integer;
    { A box selection being dragged from FBoxStart (window pixels). }
    FBoxing: Boolean;
    FBoxStart: TVector2;
    FDragThings: array of Integer;
    { Copied things, relative to their middle (Ctrl+C / Ctrl+V). }
    FClipboard: TEditThingArray;
    { The texture / flat picker: its kind (0 wall, 1 floor, 2 ceiling),
      the typed filter, the names it shows, the highlighted one and the
      first row shown; thumbnails made as they are first shown. }
    FPicker: Boolean;
    FPickerKind: Integer;
    FPickerFilter: String;
    FPickerList: TStringList;
    FPickerIndex, FPickerTop: Integer;
    FThumbs: TStringList;
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
    { The room was closed by a click on its first corner (else Enter: a
      path ending on two walls cuts the sector instead). }
    FDrawClosed: Boolean;
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
    procedure MouseDown(const P: TVector2; const Button: TCastleMouseButton;
      const Shift: Boolean = false; const Ctrl: Boolean = false);
    procedure MouseMove(const P: TVector2);
    procedure MouseUp(const P: TVector2; const Button: TCastleMouseButton);
    procedure AddDrawPoint(const Pt: TEditPoint);
    procedure FinishDrawing;
    procedure CutSector;
    procedure DeleteSelection;
    procedure ToggleFlag(const Number: Integer);
    procedure RenderFlags;
    function HandleKey(const Key: TKey; const Shift, Ctrl: Boolean): Boolean;
    function CycleName(const List: TStrings; const Current: String; const Delta: Integer): String;
    procedure ChangeWall(const Delta: Integer);
    function MoreText: String;
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
    function IsSelected(const Index: Integer): Boolean;
    { FSelected and FMore. }
    function Selection: TEditIndexArray;
    function SelectionCount: Integer;
    procedure ClearSelection;
    procedure SelectOnly(const Index: Integer);
    procedure ToggleSelect(const Index: Integer);
    procedure SelectBox(const A, B: TVector2);
    procedure SelectAll;
    function ModeCount: Integer;
    procedure StartDrag(const P: TVector2);
    procedure CopyThings;
    procedure PasteThings;
    procedure DeleteThings;
    procedure SetLineTexture(const L: Integer; const Tex: String);
    procedure OpenPicker(const Kind: Integer);
    procedure FilterPicker;
    procedure PickerApply(const TexName: String);
    function PickerKey(const Key: TKey; const Ch: String): Boolean;
    procedure PickerLayout(out Cols, Rows: Integer; out Cell, GridLeft, GridTop: Single);
    function PickerCellAt(const P: TVector2): Integer;
    function Thumb(const TexName: String): TDrawableImage;
    procedure RenderPicker;
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
  CastleFilesUtils, CastleRectangles, CastleRenderOptions, CastleFonts,
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
    'Shift+click: add to the selection' + #10 +
    'Drag on nothing / Ctrl+drag: box select' + #10 +
    'Ctrl+A all, Ctrl+C / Ctrl+V copy things' + #10 +
    'N, a path from wall to wall, Enter: cut a sector' + #10 +
    'Del: delete (vertices join their lines)' + #10 +
    '1-9: flags of lines / things' + #10 +
    'Space: texture / flat picker (Shift: ceiling)' + #10 +
    'Sector: PgUp PgDn floor (Shift: ceiling)' + #10 +
    '  B light  F C flats  P special  D door' + #10 +
    'Line: W texture  P special  X split' + #10 +
    ', .  tag (things: turn)' + #10 +
    'Things: A / Insert add  [ ]  type' + #10 +
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
  FPickerList := TStringList.Create;
  FThumbs := TStringList.Create;
  FThumbs.OwnsObjects := true;
  FThumbs.Sorted := true;
end;

destructor TViewEdit.Destroy;
begin
  FreeAndNil(FEdit);
  FreeAndNil(FTextures);
  FreeAndNil(FFlats);
  FreeAndNil(FSteps);
  FreeAndNil(FPickerList);
  FreeAndNil(FThumbs);
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
  ClearSelection;
  FThumbs.Clear;
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
  ClearSelection;
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
  if Length(FMore) > 0 then
    Result := Format('%d %s selected; the last one: ', [SelectionCount, LowerCase(ModeNames[FMode])]);
  case FMode of
    emVertices:
      if FSelected <= High(FEdit.Vertices) then
        Result := Result + Format('Vertex %d at %d, %d', [FSelected, FEdit.Vertices[FSelected].X, FEdit.Vertices[FSelected].Y]);
    emLines:
      if FSelected <= High(FEdit.Lines) then
      begin
        L := FEdit.Lines[FSelected];
        Side := 'one-sided';
        if L.Side[1] >= 0 then Side := 'two-sided';
        Result := Result + Format('Line %d (%s), length %d, special %s, tag %d, flags %d', [FSelected, Side,
          Round(Sqrt(Sqr(FEdit.Vertices[L.V2].X - FEdit.Vertices[L.V1].X) + Sqr(FEdit.Vertices[L.V2].Y - FEdit.Vertices[L.V1].Y))),
          ChoiceName(LineSpecials, L.Special), L.Tag, L.Flags]) + #10 +
          '  front: ' + SideText(L.Side[0]) + #10 + '  back: ' + SideText(L.Side[1]);
      end;
    emSectors:
      if FSelected <= High(FEdit.Sectors) then
      begin
        S := FEdit.Sectors[FSelected];
        Result := Result + Format('Sector %d: floor %d %s, ceiling %d %s, light %d, special %s, tag %d', [FSelected,
          S.Floor, S.FloorTex, S.Ceiling, S.CeilingTex, S.Light, ChoiceName(SectorSpecials, S.Special), S.Tag]);
      end;
    emThings:
      if FSelected <= High(FEdit.Things) then
      begin
        T := FEdit.Things[FSelected];
        Result := Result + Format('Thing %d: %s at %d, %d, angle %d, flags %d', [FSelected, EditorThingName(T.TypeNum),
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

{ Selection ------------------------------------------------------------------- }

function TViewEdit.IsSelected(const Index: Integer): Boolean;
var
  I: Integer;
begin
  if Index < 0 then Exit(false);
  if Index = FSelected then Exit(true);
  for I := 0 to High(FMore) do
    if FMore[I] = Index then Exit(true);
  Result := false;
end;

function TViewEdit.Selection: TEditIndexArray;
var
  I: Integer;
begin
  Result := nil;
  if FSelected < 0 then Exit;
  SetLength(Result, Length(FMore) + 1);
  Result[0] := FSelected;
  for I := 0 to High(FMore) do
    Result[I + 1] := FMore[I];
end;

function TViewEdit.SelectionCount: Integer;
begin
  if FSelected < 0 then Result := 0 else Result := Length(FMore) + 1;
end;

procedure TViewEdit.ClearSelection;
begin
  FSelected := -1;
  FMore := nil;
end;

procedure TViewEdit.SelectOnly(const Index: Integer);
begin
  FSelected := Index;
  FMore := nil;
end;

procedure TViewEdit.ToggleSelect(const Index: Integer);
var
  I: Integer;
begin
  if Index < 0 then Exit;
  if Index = FSelected then
  begin
    { The next one becomes the main one. }
    if Length(FMore) > 0 then
    begin
      FSelected := FMore[High(FMore)];
      SetLength(FMore, Length(FMore) - 1);
    end else
      FSelected := -1;
    Exit;
  end;
  for I := 0 to High(FMore) do
    if FMore[I] = Index then
    begin
      Delete(FMore, I, 1);
      Exit;
    end;
  if FSelected >= 0 then
  begin
    SetLength(FMore, Length(FMore) + 1);
    FMore[High(FMore)] := FSelected;
  end;
  FSelected := Index;
end;

function TViewEdit.ModeCount: Integer;
begin
  case FMode of
    emVertices: Result := Length(FEdit.Vertices);
    emLines: Result := Length(FEdit.Lines);
    emSectors: Result := Length(FEdit.Sectors);
    else Result := Length(FEdit.Things);
  end;
end;

{ Everything of the mode inside the box from A to B (window pixels): a
  line with both ends in it, a sector with all its vertices. }
procedure TViewEdit.SelectBox(const A, B: TVector2);
var
  D1, D2: TVector2;
  X1, Y1, X2, Y2: Single;
  I, L, Count: Integer;
  Inside: array of Boolean;
  SectorOut: array of Boolean;

  function In_(const X, Y: Single): Boolean;
  begin
    Result := (X >= X1) and (X <= X2) and (Y >= Y1) and (Y <= Y2);
  end;

  procedure Take(const Index: Integer);
  begin
    if IsSelected(Index) then Exit;
    ToggleSelect(Index);
    Inc(Count);
  end;

begin
  D1 := DoomOf(A);
  D2 := DoomOf(B);
  X1 := Min(D1.X, D2.X); X2 := Max(D1.X, D2.X);
  Y1 := Min(D1.Y, D2.Y); Y2 := Max(D1.Y, D2.Y);
  Count := 0;
  SetLength(Inside, Length(FEdit.Vertices));
  for I := 0 to High(FEdit.Vertices) do
    Inside[I] := In_(FEdit.Vertices[I].X, FEdit.Vertices[I].Y);
  case FMode of
    emVertices:
      for I := 0 to High(Inside) do
        if Inside[I] then Take(I);
    emLines:
      for I := 0 to High(FEdit.Lines) do
        if Inside[FEdit.Lines[I].V1] and Inside[FEdit.Lines[I].V2] then Take(I);
    emSectors:
      begin
        SetLength(SectorOut, Length(FEdit.Sectors));
        for L := 0 to High(FEdit.Lines) do
          if not (Inside[FEdit.Lines[L].V1] and Inside[FEdit.Lines[L].V2]) then
          begin
            if FEdit.LineSector(L, 0) >= 0 then SectorOut[FEdit.LineSector(L, 0)] := true;
            if FEdit.LineSector(L, 1) >= 0 then SectorOut[FEdit.LineSector(L, 1)] := true;
          end;
        for I := 0 to High(SectorOut) do
          if not SectorOut[I] then Take(I);
      end;
    else
      for I := 0 to High(FEdit.Things) do
        if In_(FEdit.Things[I].X, FEdit.Things[I].Y) then Take(I);
  end;
  WritelnLog('Editor', 'Box selected %d %s, %d in all', [Count, LowerCase(ModeNames[FMode]), SelectionCount]);
end;

procedure TViewEdit.SelectAll;
var
  I: Integer;
begin
  ClearSelection;
  for I := 0 to ModeCount - 1 do
    ToggleSelect(I);
  LogAction(Format('Selected all %d %s', [SelectionCount, LowerCase(ModeNames[FMode])]));
end;

{ Start moving the selection from P: the vertices of what is selected (a
  vertex, the lines' and the sectors' ends), or the things. }
procedure TViewEdit.StartDrag(const P: TVector2);
var
  I, Line: Integer;
  Seen: array of Boolean;
  Sel: TEditIndexArray;

  procedure TakeVertex(const V: Integer);
  begin
    if Seen[V] then Exit;
    Seen[V] := true;
    SetLength(FDragVertices, Length(FDragVertices) + 1);
    FDragVertices[High(FDragVertices)] := V;
  end;

begin
  FDragging := true;
  FDragMoved := false;
  FDragStart := Snap(P);
  FDragVertices := nil;
  FDragThings := nil;
  Sel := Selection;
  SetLength(Seen, Length(FEdit.Vertices));
  case FMode of
    emVertices:
      for I := 0 to High(Sel) do TakeVertex(Sel[I]);
    emLines:
      for I := 0 to High(Sel) do
      begin
        TakeVertex(FEdit.Lines[Sel[I]].V1);
        TakeVertex(FEdit.Lines[Sel[I]].V2);
      end;
    emSectors:
      for Line := 0 to High(FEdit.Lines) do
        if IsSelected(FEdit.LineSector(Line, 0)) or IsSelected(FEdit.LineSector(Line, 1)) then
        begin
          TakeVertex(FEdit.Lines[Line].V1);
          TakeVertex(FEdit.Lines[Line].V2);
        end;
    else
      FDragThings := Sel;
  end;
  if FMode = emThings then
  begin
    SetLength(FDragOrigins, Length(FDragThings));
    for I := 0 to High(FDragThings) do
    begin
      FDragOrigins[I].X := FEdit.Things[FDragThings[I]].X;
      FDragOrigins[I].Y := FEdit.Things[FDragThings[I]].Y;
    end;
  end else
  begin
    SetLength(FDragOrigins, Length(FDragVertices));
    for I := 0 to High(FDragVertices) do
    begin
      FDragOrigins[I].X := FEdit.Vertices[FDragVertices[I]].X;
      FDragOrigins[I].Y := FEdit.Vertices[FDragVertices[I]].Y;
    end;
  end;
end;

procedure TViewEdit.CopyThings;
var
  Sel: TEditIndexArray;
  I: Integer;
  CX, CY: Single;
begin
  if (FMode <> emThings) or (SelectionCount = 0) then
  begin
    Message('Select things to copy');
    Exit;
  end;
  Sel := Selection;
  CX := 0;
  CY := 0;
  for I := 0 to High(Sel) do
  begin
    CX := CX + FEdit.Things[Sel[I]].X;
    CY := CY + FEdit.Things[Sel[I]].Y;
  end;
  CX := Round(CX / Length(Sel));
  CY := Round(CY / Length(Sel));
  SetLength(FClipboard, Length(Sel));
  for I := 0 to High(Sel) do
  begin
    FClipboard[I] := FEdit.Things[Sel[I]];
    FClipboard[I].X := FClipboard[I].X - Round(CX);
    FClipboard[I].Y := FClipboard[I].Y - Round(CY);
  end;
  LogAction(Format('Copied %d things', [Length(FClipboard)]));
end;

procedure TViewEdit.PasteThings;
var
  Pt: TEditPoint;
  I, T: Integer;
begin
  if Length(FClipboard) = 0 then
  begin
    Message('Nothing copied');
    Exit;
  end;
  Pt := Snap(FMouse);
  SetMode(emThings);
  { The pasted things become the selection. }
  ClearSelection;
  FEdit.BeginChange;
  try
    for I := 0 to High(FClipboard) do
    begin
      T := FEdit.AddThing(Pt.X + FClipboard[I].X, Pt.Y + FClipboard[I].Y, FClipboard[I].TypeNum, FClipboard[I].Angle);
      FEdit.Things[T].Flags := FClipboard[I].Flags;
      ToggleSelect(T);
    end;
  finally
    FEdit.EndChange;
  end;
  LogAction(Format('Pasted %d things at %d, %d', [Length(FClipboard), Pt.X, Pt.Y]));
end;

procedure TViewEdit.DeleteThings;
var
  Sel: TEditIndexArray;
  I, J, T: Integer;
begin
  Sel := Selection;
  { Highest first, so the other indices stay right. }
  for I := 1 to High(Sel) do
    for J := I downto 1 do
      if Sel[J] > Sel[J - 1] then
      begin
        T := Sel[J]; Sel[J] := Sel[J - 1]; Sel[J - 1] := T;
      end;
  FEdit.BeginChange;
  try
    for I := 0 to High(Sel) do
      FEdit.DeleteThing(Sel[I]);
  finally
    FEdit.EndChange;
  end;
  LogAction(Format('Deleted %d things', [Length(Sel)]));
  ClearSelection;
end;

{ The texture picker ------------------------------------------------------------ }

const
  PickerKindNames: array [0..2] of String = ('Wall texture', 'Floor flat', 'Ceiling flat');

procedure TViewEdit.OpenPicker(const Kind: Integer);
var
  Current: String;
  L: TEditLine;
begin
  if SelectionCount = 0 then
  begin
    Message('Select lines or sectors first');
    Exit;
  end;
  FPicker := true;
  FPickerKind := Kind;
  FPickerFilter := '';
  FilterPicker;
  Current := '';
  if Kind = 0 then
  begin
    L := FEdit.Lines[FSelected];
    if L.Side[0] >= 0 then
    begin
      Current := FEdit.Sides[L.Side[0]].Middle;
      if (Current = '') or (Current = '-') then Current := FEdit.Sides[L.Side[0]].Lower;
      if (Current = '') or (Current = '-') then Current := FEdit.Sides[L.Side[0]].Upper;
    end;
  end else
  if Kind = 1 then
    Current := FEdit.Sectors[FSelected].FloorTex
  else
    Current := FEdit.Sectors[FSelected].CeilingTex;
  FPickerIndex := Max(0, FPickerList.IndexOf(UpperCase(Current)));
  FPickerTop := -1;
  WritelnLog('Editor', 'Picker: %s for %d %s, %d to choose from', [PickerKindNames[Kind], SelectionCount,
    LowerCase(ModeNames[FMode]), FPickerList.Count]);
end;

procedure TViewEdit.FilterPicker;
var
  Source: TStringList;
  I: Integer;
begin
  if FPickerKind = 0 then Source := FTextures else Source := FFlats;
  FPickerList.Clear;
  for I := 0 to Source.Count - 1 do
    if (FPickerFilter = '') or (Pos(FPickerFilter, Source[I]) > 0) then
      FPickerList.Add(Source[I]);
  FPickerIndex := 0;
  FPickerTop := 0;
end;

procedure TViewEdit.SetLineTexture(const L: Integer; const Tex: String);
var
  Line: TEditLine;
begin
  Line := FEdit.Lines[L];
  if Line.Side[1] < 0 then
  begin
    if Line.Side[0] >= 0 then FEdit.Sides[Line.Side[0]].Middle := Tex;
  end else
  begin
    FEdit.Sides[Line.Side[0]].Upper := Tex;
    FEdit.Sides[Line.Side[0]].Lower := Tex;
    FEdit.Sides[Line.Side[1]].Upper := Tex;
    FEdit.Sides[Line.Side[1]].Lower := Tex;
  end;
end;

procedure TViewEdit.PickerApply(const TexName: String);
var
  Sel: TEditIndexArray;
  I: Integer;
begin
  FPicker := false;
  Sel := Selection;
  FEdit.BeginChange;
  try
    FEdit.Snapshot;
    for I := 0 to High(Sel) do
      case FPickerKind of
        0: SetLineTexture(Sel[I], TexName);
        1: FEdit.Sectors[Sel[I]].FloorTex := TexName;
        else FEdit.Sectors[Sel[I]].CeilingTex := TexName;
      end;
  finally
    FEdit.EndChange;
  end;
  LogAction(Format('%s %s on %d %s', [PickerKindNames[FPickerKind], TexName, Length(Sel), LowerCase(ModeNames[FMode])]));
end;

function TViewEdit.PickerKey(const Key: TKey; const Ch: String): Boolean;
var
  Cols, Rows: Integer;
  Cell, GridLeft, GridTop: Single;
  C: Char;
begin
  Result := true;
  PickerLayout(Cols, Rows, Cell, GridLeft, GridTop);
  case Key of
    keyEscape:
      begin
        FPicker := false;
        Message('Picker closed');
      end;
    keyEnter:
      if FPickerList.Count > 0 then
        PickerApply(FPickerList[FPickerIndex]);
    keyArrowLeft: FPickerIndex := Max(0, FPickerIndex - 1);
    keyArrowRight: FPickerIndex := Min(FPickerList.Count - 1, FPickerIndex + 1);
    keyArrowUp: FPickerIndex := Max(0, FPickerIndex - Cols);
    keyArrowDown: FPickerIndex := Min(FPickerList.Count - 1, FPickerIndex + Cols);
    keyPageUp: FPickerIndex := Max(0, FPickerIndex - Cols * Rows);
    keyPageDown: FPickerIndex := Min(FPickerList.Count - 1, FPickerIndex + Cols * Rows);
    keyBackSpace:
      if FPickerFilter <> '' then
      begin
        SetLength(FPickerFilter, Length(FPickerFilter) - 1);
        FilterPicker;
      end;
    else
      begin
        { Typed letters, digits, - and _ filter the names. }
        if Length(Ch) <> 1 then Exit;
        C := UpCase(Ch[1]);
        if not CharInSet(C, ['A'..'Z', '0'..'9', '-', '_', '[', ']']) then Exit;
        FPickerFilter := FPickerFilter + C;
        FilterPicker;
      end;
  end;
  { Keep the highlighted one in view. }
  if FPickerList.Count > 0 then
  begin
    if FPickerIndex div Cols < FPickerTop then FPickerTop := FPickerIndex div Cols;
    if FPickerIndex div Cols >= FPickerTop + Rows then FPickerTop := FPickerIndex div Cols - Rows + 1;
  end;
end;

procedure TViewEdit.PickerLayout(out Cols, Rows: Integer; out Cell, GridLeft, GridTop: Single);
var
  W, H: Single;
begin
  W := Container.PixelsWidth;
  H := Container.PixelsHeight;
  Cell := Max(64, Round(H / 7));
  Cols := Max(1, Trunc((W - 40) / Cell));
  Rows := Max(1, Trunc((H - 110) / Cell));
  GridLeft := (W - Cols * Cell) / 2;
  GridTop := H - 70;
end;

function TViewEdit.PickerCellAt(const P: TVector2): Integer;
var
  Cols, Rows, C, R: Integer;
  Cell, GridLeft, GridTop: Single;
begin
  Result := -1;
  PickerLayout(Cols, Rows, Cell, GridLeft, GridTop);
  if (P.X < GridLeft) or (P.Y > GridTop) then Exit;
  C := Trunc((P.X - GridLeft) / Cell);
  R := Trunc((GridTop - P.Y) / Cell);
  if (C >= Cols) or (R >= Rows) then Exit;
  Result := (FPickerTop + R) * Cols + C;
  if Result >= FPickerList.Count then Result := -1;
end;

function TViewEdit.Thumb(const TexName: String): TDrawableImage;
var
  I: Integer;
  Img: TDoomImage;
  Key: String;
begin
  Key := Format('%d:%s', [Ord(FPickerKind <> 0), TexName]);
  I := FThumbs.IndexOf(Key);
  if I >= 0 then Exit(TDrawableImage(FThumbs.Objects[I]));
  Result := nil;
  if FPickerKind = 0 then Img := Graphics.Texture(TexName) else Img := Graphics.Flat(TexName);
  if (Img <> nil) and (Img.Image <> nil) then
    Result := TDrawableImage.Create(Img.Image.MakeCopy, false, true);
  FThumbs.AddObject(Key, Result);
end;

procedure TViewEdit.RenderPicker;
var
  Cols, Rows, R, C, I: Integer;
  Cell, GridLeft, GridTop, Scale, X, Y: Single;
  Img: TDrawableImage;
  Font: TCastleFont;
  Rect: TFloatRectangle;
begin
  PickerLayout(Cols, Rows, Cell, GridLeft, GridTop);
  if FPickerTop < 0 then
    FPickerTop := Max(0, FPickerIndex div Cols - Rows div 2);
  DrawRectangle(FloatRectangle(0, 0, Container.PixelsWidth, Container.PixelsHeight), Vector4(0.03, 0.03, 0.06, 0.93));
  Font := FallbackFont;
  Font.PushProperties;
  try
    Font.Size := Max(12, Cell / 8);
    Font.Print(GridLeft, GridTop + 16, Vector4(1, 0.85, 0.4, 1),
      Format('%s for %d %s: filter "%s" (%d)   type to filter, arrows, Enter, Esc', [
      PickerKindNames[FPickerKind], SelectionCount, LowerCase(ModeNames[FMode]), FPickerFilter, FPickerList.Count]));
    for R := 0 to Rows - 1 do
      for C := 0 to Cols - 1 do
      begin
        I := (FPickerTop + R) * Cols + C;
        if I >= FPickerList.Count then Break;
        X := GridLeft + C * Cell;
        Y := GridTop - (R + 1) * Cell;
        if I = FPickerIndex then
          DrawRectangle(FloatRectangle(X + 1, Y + 1, Cell - 2, Cell - 2), Vector4(1, 0.55, 0.1, 1));
        Img := Thumb(FPickerList[I]);
        if Img <> nil then
        begin
          { Fit in the cell above the name, keeping the proportions. }
          Scale := Min((Cell - 10) / Img.Width, (Cell - 10 - Font.Height - 2) / Img.Height);
          Rect := FloatRectangle(X + (Cell - Img.Width * Scale) / 2, Y + Font.Height + 6,
            Img.Width * Scale, Img.Height * Scale);
          Img.Draw(Rect);
        end;
        Font.Print(X + 5, Y + 4, Vector4(0.9, 0.9, 0.9, 1), FPickerList[I]);
      end;
  finally
    Font.PopProperties;
  end;
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
  Mark: array of Boolean;
  SelIndex: TEditIndexArray;

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

  function Marked_(const Index: Integer): Boolean;
  begin
    Result := (Index >= 0) and (Index <= High(Mark)) and Mark[Index];
  end;

  function LineSelected(const L: Integer): Boolean;
  begin
    case FMode of
      emLines: Result := Marked_(L);
      emSectors: Result := Marked_(FEdit.LineSector(L, 0)) or Marked_(FEdit.LineSector(L, 1));
      else Result := false;
    end;
  end;

begin
  inherited;
  DrawRectangle(FloatRectangle(0, 0, Container.PixelsWidth, Container.PixelsHeight), ColorBack);
  { The selection as marks by index (of the mode's objects). }
  SetLength(Mark, ModeCount);
  SelIndex := Selection;
  for I := 0 to High(SelIndex) do
    if SelIndex[I] <= High(Mark) then Mark[SelIndex[I]] := true;

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
    if LineSelected(I) then
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
      if Marked_(I) then Color := ColorSelected
      else if I = FHover then Color := ColorHover
      else Color := ColorVertex;
      R := 2;
      if Marked_(I) or (I = FHover) then R := 4;
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
    Sel := (FMode = emThings) and Marked_(I);
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

  { The box selection being dragged. }
  if FBoxing then
  begin
    A := FBoxStart;
    B := FMouse;
    DrawPrimitive2D(pmLineLoop, [A, Vector2(B.X, A.Y), B, Vector2(A.X, B.Y)], ColorHover);
  end;

  { The help panel's background (the label draws after this). }
  if (FHelpLabel <> nil) and FHelpLabel.Exists then
    DrawRectangle(FHelpLabel.RenderRect, Vector4(0.1, 0.12, 0.2, 0.9));

  RenderFlags;
  if FPicker then RenderPicker;
end;

{ Input --------------------------------------------------------------------- }

procedure TViewEdit.MouseDown(const P: TVector2; const Button: TCastleMouseButton;
  const Shift, Ctrl: Boolean);
var
  Picked: Integer;
begin
  FMouse := P;
  if FPicker then
  begin
    { A click picks; beside the grid it closes. }
    Picked := PickerCellAt(P);
    if (Button = buttonLeft) and (Picked >= 0) then
      PickerApply(FPickerList[Picked])
    else
      FPicker := false;
    UpdateLabels;
    Exit;
  end;
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
  Picked := -1;
  if not Ctrl then Picked := Pick(P);
  if Picked < 0 then
  begin
    { On nothing (or with Ctrl): a box selection, adding with Shift. }
    if not Shift then ClearSelection;
    FBoxing := true;
    FBoxStart := P;
    UpdateLabels;
    Exit;
  end;
  if Shift then
  begin
    ToggleSelect(Picked);
    UpdateLabels;
    Exit;
  end;
  if not IsSelected(Picked) then
    SelectOnly(Picked)
  else if Picked <> FSelected then
  begin
    { The clicked one becomes the main one, the rest stays selected. }
    ToggleSelect(Picked);
    ToggleSelect(Picked);
  end;
  StartDrag(P);
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
        for I := 0 to High(FDragThings) do
        begin
          FEdit.Things[FDragThings[I]].X := FDragOrigins[I].X + DX;
          FEdit.Things[FDragThings[I]].Y := FDragOrigins[I].Y + DY;
        end;
      end else
        for I := 0 to High(FDragVertices) do
        begin
          FEdit.Vertices[FDragVertices[I]].X := FDragOrigins[I].X + DX;
          FEdit.Vertices[FDragVertices[I]].Y := FDragOrigins[I].Y + DY;
        end;
    end;
  end else
  if not (FDrawing or FBoxing or FPicker) then
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
  if FBoxing then
  begin
    FBoxing := false;
    FMouse := P;
    SelectBox(FBoxStart, P);
    UpdateLabels;
    Exit;
  end;
  if not FDragging then Exit;
  FDragging := false;
  if not FDragMoved then Exit;
  Pt := Snap(P);
  case FMode of
    emVertices:
      if SelectionCount > 1 then
        LogAction(Format('Moved %d vertices by %d, %d', [SelectionCount, Pt.X - FDragStart.X, Pt.Y - FDragStart.Y]))
      else
      begin
        { Dropped on another vertex: they merge. }
        Pt.X := FEdit.Vertices[FSelected].X;
        Pt.Y := FEdit.Vertices[FSelected].Y;
        if FEdit.MergeVertex(FSelected) then
        begin
          ClearSelection;
          LogAction(Format('Merged vertices at %d, %d', [Pt.X, Pt.Y]));
        end else
          LogAction(Format('Moved vertex to %d, %d', [Pt.X, Pt.Y]));
      end;
    emThings:
      if SelectionCount > 1 then
        LogAction(Format('Moved %d things by %d, %d', [SelectionCount, Pt.X - FDragStart.X, Pt.Y - FDragStart.Y]))
      else
        LogAction(Format('Moved thing %d to %d, %d', [FSelected, FEdit.Things[FSelected].X, FEdit.Things[FSelected].Y]));
    else
      if SelectionCount > 1 then
        LogAction(Format('Moved %d %s by %d, %d', [SelectionCount, LowerCase(ModeNames[FMode]),
          Pt.X - FDragStart.X, Pt.Y - FDragStart.Y]))
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
    FDrawClosed := true;
    FinishDrawing;
    Exit;
  end;
  SetLength(FDrawPoints, Length(FDrawPoints) + 1);
  FDrawPoints[High(FDrawPoints)] := Pt;
  UpdateLabels;
end;

procedure TViewEdit.CutSector;
var
  Sec, Old: Integer;
  Error: String;
begin
  FDrawing := false;
  FDrawClosed := false;
  Old := FEdit.SectorAt((FDrawPoints[0].X + FDrawPoints[1].X) / 2 + 0.01,
    (FDrawPoints[0].Y + FDrawPoints[1].Y) / 2 + 0.013);
  Sec := FEdit.SplitSector(FDrawPoints, Error);
  if Sec < 0 then
  begin
    LogAction('Cannot cut: ' + Error);
    WritelnWarning('Editor', 'Cut refused: %s', [Error]);
  end else
  begin
    LogAction(Format('Sector %d cut in two: sector %d with %d points', [Old, Sec, Length(FDrawPoints)]));
    SetMode(emSectors);
    SelectOnly(Sec);
  end;
  FDrawPoints := nil;
  UpdateLabels;
end;

procedure TViewEdit.FinishDrawing;
var
  Sec, N: Integer;
  Error: String;
begin
  FDrawing := false;
  N := Length(FDrawPoints);
  { Enter on a path from wall to wall through a sector: a cut. }
  if (not FDrawClosed) and (N >= 2) and
     FEdit.OnWall(FDrawPoints[0].X, FDrawPoints[0].Y) and
     FEdit.OnWall(FDrawPoints[N - 1].X, FDrawPoints[N - 1].Y) and
     ((FDrawPoints[0].X <> FDrawPoints[N - 1].X) or (FDrawPoints[0].Y <> FDrawPoints[N - 1].Y)) and
     (FEdit.SectorAt((FDrawPoints[0].X + FDrawPoints[1].X) / 2 + 0.01,
       (FDrawPoints[0].Y + FDrawPoints[1].Y) / 2 + 0.013) >= 0) then
  begin
    CutSector;
    Exit;
  end;
  FDrawClosed := false;
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
    SelectOnly(Sec);
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
  S, I: Integer;
  Tex: String;
  Sel: TEditIndexArray;
begin
  L := FEdit.Lines[FSelected];
  S := L.Side[0];
  if S < 0 then S := L.Side[1];
  if S < 0 then Exit;
  if L.Side[1] < 0 then
    Tex := FEdit.Sides[S].Middle
  else
  begin
    Tex := FEdit.Sides[S].Lower;
    if (Tex = '') or (Tex = '-') then Tex := FEdit.Sides[S].Upper;
  end;
  Tex := CycleName(FTextures, Tex, Delta);
  Sel := Selection;
  FEdit.Snapshot;
  for I := 0 to High(Sel) do
    SetLineTexture(Sel[I], Tex);
  LogAction(Format('Line %d wall %s%s', [FSelected, Tex, MoreText]));
end;

{ ", and 3 more" when more than one is selected. }
function TViewEdit.MoreText: String;
begin
  if Length(FMore) > 0 then
    Result := Format(' (and %d more)', [Length(FMore)])
  else
    Result := '';
end;

procedure TViewEdit.DeleteSelection;
var
  Sel: TEditIndexArray;
  Points: TEditPoints;
  I, J, T, Joined: Integer;
begin
  Sel := Selection;
  { Highest first, so the other indices stay right. }
  for I := 1 to High(Sel) do
    for J := I downto 1 do
      if Sel[J] > Sel[J - 1] then
      begin
        T := Sel[J]; Sel[J] := Sel[J - 1]; Sel[J - 1] := T;
      end;
  case FMode of
    emThings:
      begin
        DeleteThings;
        Exit;
      end;
    emLines:
      begin
        FEdit.DeleteLines(Sel);
        LogAction(Format('Deleted %d lines', [Length(Sel)]));
      end;
    emSectors:
      begin
        FEdit.BeginChange;
        try
          for I := 0 to High(Sel) do
            FEdit.DeleteSector(Sel[I]);
        finally
          FEdit.EndChange;
        end;
        LogAction(Format('Deleted %d sectors', [Length(Sel)]));
      end;
    emVertices:
      begin
        { By place: deleting one renumbers the others. }
        SetLength(Points, Length(Sel));
        for I := 0 to High(Sel) do
        begin
          Points[I].X := FEdit.Vertices[Sel[I]].X;
          Points[I].Y := FEdit.Vertices[Sel[I]].Y;
        end;
        Joined := 0;
        FEdit.BeginChange;
        try
          for I := 0 to High(Points) do
          begin
            J := FEdit.NearestVertex(Points[I].X, Points[I].Y, 0);
            if (J >= 0) and FEdit.DissolveVertex(J) then Inc(Joined);
          end;
        finally
          FEdit.EndChange;
        end;
        LogAction(Format('Deleted %d vertices, %d joining their lines', [Length(Points), Joined]));
      end;
  end;
  ClearSelection;
end;

type
  TFlagName = record
    Bit: Integer;
    Name: String;
  end;

const
  LineFlagNames: array [0..8] of TFlagName = (
    (Bit: 1; Name: 'Impassable'), (Bit: 2; Name: 'Blocks monsters'), (Bit: 4; Name: 'Two-sided'),
    (Bit: 8; Name: 'Upper unpegged'), (Bit: 16; Name: 'Lower unpegged'), (Bit: 32; Name: 'Secret'),
    (Bit: 64; Name: 'Blocks sound'), (Bit: 128; Name: 'Hidden on automap'), (Bit: 256; Name: 'Shown on automap'));
  ThingFlagNames: array [0..4] of TFlagName = (
    (Bit: 1; Name: 'Skills 1-2'), (Bit: 2; Name: 'Skill 3'), (Bit: 4; Name: 'Skills 4-5'),
    (Bit: 8; Name: 'Ambush (deaf)'), (Bit: 16; Name: 'Multiplayer only'));

{ Number keys toggle a flag of the selection (lines or things): the main
  one's flag flipped, the same value for all. }
procedure TViewEdit.ToggleFlag(const Number: Integer);
var
  Sel: TEditIndexArray;
  Bit, I: Integer;
  FlagOn: Boolean;
  FlagName: String;
begin
  Sel := Selection;
  if FMode = emLines then
  begin
    if Number > Length(LineFlagNames) then Exit;
    Bit := LineFlagNames[Number - 1].Bit;
    FlagName := LineFlagNames[Number - 1].Name;
    FlagOn := (FEdit.Lines[FSelected].Flags and Bit) = 0;
  end else
  begin
    if Number > Length(ThingFlagNames) then Exit;
    Bit := ThingFlagNames[Number - 1].Bit;
    FlagName := ThingFlagNames[Number - 1].Name;
    FlagOn := (FEdit.Things[FSelected].Flags and Bit) = 0;
  end;
  FEdit.Snapshot;
  for I := 0 to High(Sel) do
    if FMode = emLines then
    begin
      if FlagOn then
        FEdit.Lines[Sel[I]].Flags := FEdit.Lines[Sel[I]].Flags or Bit
      else
        FEdit.Lines[Sel[I]].Flags := FEdit.Lines[Sel[I]].Flags and not Bit;
    end else
    begin
      if FlagOn then
        FEdit.Things[Sel[I]].Flags := FEdit.Things[Sel[I]].Flags or Bit
      else
        FEdit.Things[Sel[I]].Flags := FEdit.Things[Sel[I]].Flags and not Bit;
    end;
  LogAction(Format('%s %d: %s %s%s', [Copy(ModeNames[FMode], 1, Length(ModeNames[FMode]) - 1), FSelected,
    FlagName, Iff(FlagOn, 'on', 'off'), MoreText]));
end;

{ The selected line's or thing's flags, bottom right: number, box, name. }
procedure TViewEdit.RenderFlags;
var
  Font: TCastleFont;
  Flags, I, Count: Integer;
  X, Y, LineH, W: Single;
  Text: String;
  Names: array of TFlagName;
begin
  if (FSelected < 0) or FPicker or not (FMode in [emLines, emThings]) then Exit;
  if FMode = emLines then
  begin
    if FSelected > High(FEdit.Lines) then Exit;
    Flags := FEdit.Lines[FSelected].Flags;
    SetLength(Names, Length(LineFlagNames));
    for I := 0 to High(LineFlagNames) do Names[I] := LineFlagNames[I];
  end else
  begin
    if FSelected > High(FEdit.Things) then Exit;
    Flags := FEdit.Things[FSelected].Flags;
    SetLength(Names, Length(ThingFlagNames));
    for I := 0 to High(ThingFlagNames) do Names[I] := ThingFlagNames[I];
  end;
  Count := Length(Names);
  Font := FallbackFont;
  Font.PushProperties;
  try
    Font.Size := Max(12, Container.PixelsHeight / 60);
    LineH := Font.Height * 1.35;
    W := Font.TextWidth('9 [x] Hidden on automap') + 20;
    X := Container.PixelsWidth - W - 10;
    Y := 10;
    DrawRectangle(FloatRectangle(X - 8, Y - 6, W + 8, LineH * (Count + 1) + 10), Vector4(0.1, 0.12, 0.2, 0.9));
    for I := 0 to Count - 1 do
    begin
      if (Flags and Names[I].Bit) <> 0 then Text := '[x]' else Text := '[ ]';
      Font.Print(X, Y + LineH * (Count - 1 - I), Vector4(0.9, 0.9, 0.9, 1),
        Format('%d %s %s', [I + 1, Text, Names[I].Name]));
    end;
    Font.Print(X, Y + LineH * Count, Vector4(1, 0.85, 0.4, 1), 'Flags (number keys)');
  finally
    Font.PopProperties;
  end;
end;

procedure TViewEdit.CycleSpecial(const Delta: Integer);
var
  I, K: Integer;
  Sel: TEditIndexArray;
begin
  Sel := Selection;
  FEdit.Snapshot;
  if FMode = emLines then
  begin
    I := ChoiceIndex(LineSpecials, FEdit.Lines[FSelected].Special);
    I := (Max(I, 0) + Delta + Length(LineSpecials)) mod Length(LineSpecials);
    for K := 0 to High(Sel) do
      FEdit.Lines[Sel[K]].Special := LineSpecials[I].Num;
    LogAction(Format('Line %d special %d (%s)%s', [FSelected, LineSpecials[I].Num, LineSpecials[I].Name, MoreText]));
  end else
  begin
    I := ChoiceIndex(SectorSpecials, FEdit.Sectors[FSelected].Special);
    I := (Max(I, 0) + Delta + Length(SectorSpecials)) mod Length(SectorSpecials);
    for K := 0 to High(Sel) do
      FEdit.Sectors[Sel[K]].Special := SectorSpecials[I].Num;
    LogAction(Format('Sector %d special %d (%s)%s', [FSelected, SectorSpecials[I].Num, SectorSpecials[I].Name, MoreText]));
  end;
end;

procedure TViewEdit.ChangeTag(const Delta: Integer);
var
  K, NewTag: Integer;
  Sel: TEditIndexArray;
begin
  Sel := Selection;
  FEdit.Snapshot;
  if FMode = emLines then
  begin
    NewTag := Max(0, FEdit.Lines[FSelected].Tag + Delta);
    for K := 0 to High(Sel) do
      FEdit.Lines[Sel[K]].Tag := NewTag;
    LogAction(Format('Line %d tag %d%s', [FSelected, NewTag, MoreText]));
  end else
  begin
    NewTag := Max(0, FEdit.Sectors[FSelected].Tag + Delta);
    for K := 0 to High(Sel) do
      FEdit.Sectors[Sel[K]].Tag := NewTag;
    LogAction(Format('Sector %d tag %d%s', [FSelected, NewTag, MoreText]));
  end;
end;

procedure TViewEdit.CycleThingType(const Delta: Integer);
var
  I, K: Integer;
  Sel: TEditIndexArray;
begin
  if (FMode = emThings) and (FSelected >= 0) then
  begin
    I := ChoiceIndex(ThingChoices, FEdit.Things[FSelected].TypeNum);
    if I < 0 then I := FThingType;
    I := (I + Delta + Length(ThingChoices)) mod Length(ThingChoices);
    Sel := Selection;
    FEdit.Snapshot;
    for K := 0 to High(Sel) do
      FEdit.Things[Sel[K]].TypeNum := ThingChoices[I].Num;
    FThingType := I;
    LogAction(Format('Thing %d is now a %s%s', [FSelected, ThingChoices[I].Name, MoreText]));
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
  V, Dir, K: Integer;
  Sel: TEditIndexArray;
  Tex: String;
begin
  Result := true;
  if FPicker then
  begin
    Result := PickerKey(Key, '');
    UpdateLabels;
    Exit;
  end;
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
      keyA:
        begin
          SelectAll;
          UpdateLabels;
          Exit;
        end;
      keyC:
        begin
          CopyThings;
          Exit;
        end;
      keyV:
        begin
          PasteThings;
          UpdateLabels;
          Exit;
        end;
      else Exit(false);
    end;
    ClearSelection;
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
        ClearSelection;
        Message('Drawing a room: click its corners');
      end;
    keyF9: PlayTest;
    keyF2: ExportWad('');
    keyF3: ExportScene(true, '');
    keyF4: ExportScene(false, '');
    keyEscape:
      if FSelected >= 0 then
        ClearSelection
      else
        Leave;
    keySpace:
      { The picture picker: walls of the selected lines, floors (Shift:
        ceilings) of the selected sectors. }
      if FMode = emLines then
        OpenPicker(0)
      else if FMode = emSectors then
      begin
        if Shift then OpenPicker(2) else OpenPicker(1);
      end else
        Exit(false);
    keyA, keyInsert:
      begin
        Pt := Snap(FMouse);
        SetMode(emThings);
        SelectOnly(FEdit.AddThing(Pt.X, Pt.Y, ThingChoices[FThingType].Num, 90));
        LogAction(Format('Added %s at %d, %d', [ThingChoices[FThingType].Name, Pt.X, Pt.Y]));
      end;
    keyLeftBracket: CycleThingType(-1);
    keyRightBracket: CycleThingType(1);
    keyDelete:
      if FSelected >= 0 then DeleteSelection else Exit(false);
    key1, key2, key3, key4, key5, key6, key7, key8, key9:
      if (FSelected >= 0) and (FMode in [emLines, emThings]) then
        ToggleFlag(Ord(Key) - Ord(key1) + 1)
      else
        Exit(false);
    else
    begin
      if FSelected < 0 then Exit(false);
      case FMode of
        emSectors:
          case Key of
            keyPageUp, keyPageDown:
              begin
                if Key = keyPageUp then V := 8 else V := -8;
                Sel := Selection;
                FEdit.BeginChange;
                for K := 0 to High(Sel) do
                  if Shift then FEdit.ChangeSector(Sel[K], 0, V, 0) else FEdit.ChangeSector(Sel[K], V, 0, 0);
                FEdit.EndChange;
                LogAction(Format('Sector %d floor %d, ceiling %d%s', [FSelected,
                  FEdit.Sectors[FSelected].Floor, FEdit.Sectors[FSelected].Ceiling, MoreText]));
              end;
            keyB:
              begin
                Sel := Selection;
                FEdit.BeginChange;
                for K := 0 to High(Sel) do
                  FEdit.ChangeSector(Sel[K], 0, 0, 16 * Dir);
                FEdit.EndChange;
                LogAction(Format('Sector %d light %d%s', [FSelected, FEdit.Sectors[FSelected].Light, MoreText]));
              end;
            keyF, keyC:
              begin
                Sel := Selection;
                FEdit.Snapshot;
                if Key = keyF then
                begin
                  Tex := CycleName(FFlats, FEdit.Sectors[FSelected].FloorTex, Dir);
                  for K := 0 to High(Sel) do FEdit.Sectors[Sel[K]].FloorTex := Tex;
                  LogAction(Format('Sector %d floor flat %s%s', [FSelected, Tex, MoreText]));
                end else
                begin
                  Tex := CycleName(FFlats, FEdit.Sectors[FSelected].CeilingTex, Dir);
                  for K := 0 to High(Sel) do FEdit.Sectors[Sel[K]].CeilingTex := Tex;
                  LogAction(Format('Sector %d ceiling flat %s%s', [FSelected, Tex, MoreText]));
                end;
              end;
            keyP: CycleSpecial(Dir);
            keyComma: ChangeTag(-1);
            keyPeriod: ChangeTag(1);
            keyD:
              begin
                Sel := Selection;
                V := 0;
                FEdit.BeginChange;
                for K := 0 to High(Sel) do
                  if FEdit.MakeDoor(Sel[K]) then Inc(V);
                FEdit.EndChange;
                if V > 0 then
                  LogAction(Format('Sector %d is a door%s', [FSelected, MoreText]))
                else
                  Message('A door needs two-sided lines');
              end;
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
                Sel := Selection;
                for K := 0 to High(Sel) do
                  FEdit.Things[Sel[K]].Angle := (FEdit.Things[Sel[K]].Angle + V + 360) mod 360;
                LogAction(Format('Thing %d angle %d%s', [FSelected, FEdit.Things[FSelected].Angle, MoreText]));
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
        MouseDown(Event.Position, Event.MouseButton, mkShift in Event.ModifiersDown, mkCtrl in Event.ModifiersDown);
        Exit(true);
      end;
    itMouseWheel:
      begin
        if FPicker then
        begin
          if Event.MouseWheelScroll > 0 then PickerKey(keyArrowUp, '') else PickerKey(keyArrowDown, '');
        end else if Event.MouseWheelScroll > 0 then
          Zoom(1.2, Event.Position)
        else
          Zoom(1 / 1.2, Event.Position);
        UpdateLabels;
        Exit(true);
      end;
    itKey:
      if FPicker then
      begin
        PickerKey(Event.Key, Event.KeyString);
        UpdateLabels;
        Exit(true);
      end else
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
    if Cmd = 'SHIFTCLICK' then
    begin
      MouseMove(At(1));
      MouseDown(At(1), buttonLeft, true);
      MouseUp(At(1), buttonLeft);
    end else
    if Cmd = 'BOX' then
    begin
      { A box selection (Ctrl+drag), adding to the selection. }
      MouseMove(At(1));
      MouseDown(At(1), buttonLeft, true, true);
      MouseMove(At(3));
      MouseUp(At(3), buttonLeft);
    end else
    if Cmd = 'TYPE' then
    begin
      for I := 1 to Length(Step) - 5 do
        PickerKey(keyNone, Step[I + 5]);
    end else
    if Cmd = 'DRAG' then
    begin
      MouseMove(At(1));
      MouseDown(At(1), buttonLeft);
      MouseMove(At(3));
      MouseUp(At(3), buttonLeft);
    end else
    if Cmd = 'CUT' then
    begin
      { A path from wall to wall cutting a sector in two. }
      SetLength(Pts, (Parts.Count - 1) div 2);
      for I := 0 to High(Pts) do
      begin
        Pts[I].X := Round(Num(1 + I * 2));
        Pts[I].Y := Round(Num(2 + I * 2));
      end;
      FDrawPoints := Pts;
      CutSector;
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
      FDrawClosed := true;
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
