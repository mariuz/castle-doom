{ Text drawn with Doom's own font: the STCFN033..STCFN095 patches (ASCII 33
  to 95, upper case only, like HU_FONT). The text is composed into one image
  and shown pixel-perfect by a TCastleImageControl. }
unit DoomFont;

interface

uses Classes,
  CastleControls, CastleImages,
  DoomGraphics;

type
  TDoomFontText = class(TCastleImageControl)
  strict private
    FGraphics: TDoomGraphics;
    FText: String;
    FScale: Single;
    FImageWidth, FImageHeight: Integer;
    procedure Compose;
    procedure ApplyScale;
  public
    constructor Create(AOwner: TComponent); override;
    { Set the text (lines separated by #10); empty hides the control. }
    procedure SetText(const AText: String);
    { Screen pixels per Doom pixel (use ViewportHeight / 200). }
    procedure SetScale(const AScale: Single);
    property Graphics: TDoomGraphics read FGraphics write FGraphics;
    property Text: String read FText;
  end;

{ Width in Doom pixels of a line of text in the STCFN font. }
function DoomTextWidth(const Graphics: TDoomGraphics; const S: String): Integer;
{ Draw a line of STCFN text into an image at Doom coordinates (top-left). }
procedure DrawDoomText(const Graphics: TDoomGraphics; const Dest: TRGBAlphaImage;
  const X, Y: Integer; const S: String);

implementation

uses SysUtils, Math,
  CastleVectors, CastleStringUtils, CastleUIControls,
  DoomHud;

const
  SpaceWidth = 4;
  LineHeight = 8;

function GlyphImage(const Graphics: TDoomGraphics; const C: Char): TDoomImage;
var
  Code: Integer;
begin
  Code := Ord(UpCase(C));
  if (Code < 33) or (Code > 95) then Exit(nil);
  Result := Graphics.Patch(Format('STCFN%3.3d', [Code]));
end;

function DoomTextWidth(const Graphics: TDoomGraphics; const S: String): Integer;
var
  I: Integer;
  G: TDoomImage;
begin
  Result := 0;
  for I := 1 to Length(S) do
  begin
    G := GlyphImage(Graphics, S[I]);
    if G = nil then Inc(Result, SpaceWidth) else Inc(Result, G.Width);
  end;
end;

procedure DrawDoomText(const Graphics: TDoomGraphics; const Dest: TRGBAlphaImage;
  const X, Y: Integer; const S: String);
var
  I, CX: Integer;
  G: TDoomImage;
begin
  CX := X;
  for I := 1 to Length(S) do
  begin
    G := GlyphImage(Graphics, S[I]);
    if G = nil then
      Inc(CX, SpaceWidth)
    else
    begin
      BlitDoomImage(Dest, G, CX, Y);
      Inc(CX, G.Width);
    end;
  end;
end;

{ TDoomFontText -------------------------------------------------------------- }

constructor TDoomFontText.Create(AOwner: TComponent);
begin
  inherited;
  SmoothScaling := false;
  Stretch := true;
  FScale := 3;
end;

procedure TDoomFontText.SetText(const AText: String);
begin
  if FText = AText then Exit;
  FText := AText;
  Compose;
end;

procedure TDoomFontText.SetScale(const AScale: Single);
begin
  if FScale = AScale then Exit;
  FScale := AScale;
  ApplyScale;
end;

procedure TDoomFontText.ApplyScale;
begin
  Width := FImageWidth * FScale;
  Height := FImageHeight * FScale;
end;

procedure TDoomFontText.Compose;
var
  Lines: TStringList;
  I, W: Integer;
  Img: TRGBAlphaImage;
begin
  if (FGraphics = nil) or (FText = '') then
  begin
    Exists := false;
    Exit;
  end;
  Lines := TStringList.Create;
  try
    Lines.Text := FText;
    W := 1;
    for I := 0 to Lines.Count - 1 do
      W := Max(W, DoomTextWidth(FGraphics, Lines[I]));
    FImageWidth := W;
    FImageHeight := Max(1, Lines.Count * LineHeight);
    Img := TRGBAlphaImage.Create(FImageWidth, FImageHeight);
    Img.Clear(Vector4Byte(0, 0, 0, 0));
    for I := 0 to Lines.Count - 1 do
      DrawDoomText(FGraphics, Img, 0, I * LineHeight, Lines[I]);
    Image := Img;
    ApplyScale;
    Exists := true;
  finally
    FreeAndNil(Lines);
  end;
end;

end.
