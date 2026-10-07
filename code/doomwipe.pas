{ Doom's screen melt (f_wipe.c wipe_initMelt / wipe_doMelt): the old screen
  is captured as an image and drawn on top of the new one in 160 columns
  that slide down, each starting after a small random delay that differs by
  at most one tic from its neighbour. Columns move 1, 2, 3... pixels per tic
  for the first 16 lines, then 8 (on Doom's 200-line grid), so the whole
  melt takes about 30 tics. }
unit DoomWipe;

interface

uses Classes,
  CastleUIControls, CastleGLImages, CastleImages;

type
  TDoomWipe = class(TCastleUserInterface)
  strict private
    FImage: TDrawableImage;
    FY: array [0..159] of Integer;
    FActive: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { Begin melting this picture of the old screen (the wipe owns it). }
    procedure Start(const OldScreen: TCastleImage);
    procedure Stop;
    { Advance one Doom tic. }
    procedure Tic;
    procedure Render; override;
    property Active: Boolean read FActive;
  end;

implementation

uses SysUtils, Math,
  CastleRectangles, CastleLog;

const
  WipeHeight = 200;

constructor TDoomWipe.Create(AOwner: TComponent);
begin
  inherited;
  FullSize := true;
end;

destructor TDoomWipe.Destroy;
begin
  FreeAndNil(FImage);
  inherited;
end;

procedure TDoomWipe.Start(const OldScreen: TCastleImage);
var
  I: Integer;
begin
  FreeAndNil(FImage);
  if OldScreen = nil then Exit;
  FImage := TDrawableImage.Create(OldScreen, false, true);
  { wipe_initMelt }
  FY[0] := -Random(16);
  for I := 1 to High(FY) do
  begin
    FY[I] := FY[I - 1] + Random(3) - 1;
    if FY[I] > 0 then FY[I] := 0
    else if FY[I] = -16 then FY[I] := -15;
  end;
  FActive := true;
  Exists := true;
  WritelnLog('Wipe', 'Melt started (%d x %d)', [OldScreen.Width, OldScreen.Height]);
end;

procedure TDoomWipe.Stop;
begin
  FActive := false;
  Exists := false;
  FreeAndNil(FImage);
end;

procedure TDoomWipe.Tic;
var
  I, DY: Integer;
  Done: Boolean;
begin
  if not FActive then Exit;
  Done := true;
  for I := 0 to High(FY) do
    if FY[I] < 0 then
    begin
      Inc(FY[I]);
      Done := false;
    end else
    if FY[I] < WipeHeight then
    begin
      if FY[I] < 16 then DY := FY[I] + 1 else DY := 8;
      if FY[I] + DY >= WipeHeight then DY := WipeHeight - FY[I];
      Inc(FY[I], DY);
      Done := false;
    end;
  if Done then
  begin
    WritelnLog('Wipe', 'Melt done');
    Stop;
  end;
end;

procedure TDoomWipe.Render;
var
  R: TFloatRectangle;
  I: Integer;
  ColW, ImgColW, Y: Single;
begin
  inherited;
  if (not FActive) or (FImage = nil) then Exit;
  R := RenderRect;
  ColW := R.Width / Length(FY);
  ImgColW := FImage.Width / Length(FY);
  for I := 0 to High(FY) do
  begin
    if FY[I] >= WipeHeight then Continue;
    Y := Max(0, FY[I]) * R.Height / WipeHeight;
    { The column of the old screen, shifted down by Y (the part below the
      window is simply not visible). }
    FImage.Draw(
      FloatRectangle(R.Left + I * ColW, R.Bottom - Y, ColW + 1, R.Height),
      FloatRectangle(I * ImgColW, 0, ImgColW, FImage.Height));
  end;
end;

end.
