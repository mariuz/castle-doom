{ --autotest MAPCOMPONENT prefix: shows data/mapcomponent.castle-user-interface,
  a design whose viewport holds a TDoomMapTransform (a Freedoom level
  built from the WAD by the component itself, as the CGE editor would
  show it), puts the camera at the player start, screenshots and quits.
  The design is also the one to open in the editor. }
unit GameViewDesign;

interface

uses Classes,
  CastleUIControls, CastleViewport;

type
  TViewDesign = class(TCastleView)
  strict private
    FViewport: TCastleViewport;
    FTics: Integer;
    FPlaced: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Start; override;
    procedure Update(const SecondsPassed: Single; var HandleInput: Boolean); override;
  end;

var
  ViewDesign: TViewDesign;

implementation

uses SysUtils,
  CastleVectors, CastleWindow, CastleLog, CastleTransform,
  DoomMapTransform, GameViewMenu;

constructor TViewDesign.Create(AOwner: TComponent);
begin
  inherited;
  DesignUrl := 'castle-data:/mapcomponent.castle-user-interface';
end;

procedure TViewDesign.Start;
begin
  inherited;
  FViewport := DesignedComponent('Viewport') as TCastleViewport;
  FTics := 0;
  FPlaced := false;
end;

procedure TViewDesign.Update(const SecondsPassed: Single; var HandleInput: Boolean);
var
  M: TDoomMapTransform;
  Camera: TCastleCamera;
begin
  inherited;
  M := DesignedComponent('DoomMap') as TDoomMapTransform;
  { The component builds the level in its first Update; then the camera
    goes to the player start, looking where the player would. }
  if (not FPlaced) and M.Built then
  begin
    if FViewport.Camera = nil then
    begin
      { A design without a camera (the editor adds one with the viewport). }
      Camera := TCastleCamera.Create(FreeAtStop);
      Camera.Name := 'Camera';
      FViewport.Items.Add(Camera);
      FViewport.Camera := Camera;
    end;
    FViewport.Camera.ProjectionNear := 4;
    FViewport.Camera.SetWorldView(M.StartEye, M.StartDirection, Vector3(0, 1, 0));
    FPlaced := true;
    WritelnLog('AutoTest', 'Design shows %s: camera at the player start (%.0f, %.0f) angle %.0f',
      [M.MapName, M.StartX, M.StartY, M.StartAngle]);
  end;
  Inc(FTics);
  if FPlaced and (FTics = 40) then
  begin
    Application.MainWindow.SaveScreen(Format('%s_design.png', [AutoTestPrefix]));
    WritelnLog('AutoTest', 'Design screenshot saved');
    Application.Terminate;
  end;
end;

end.
