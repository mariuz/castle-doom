{ Doom sound effects through the Castle Game Engine sound engine.

  Doom stores sounds as DMX lumps (DS*): 8-bit unsigned PCM with a small
  header. We register a custom URL protocol "doomsfx:" with CGE, so that
  "doomsfx:/DSPISTOL" is converted on the fly into a WAV stream. From then on
  TCastleSound / TCastleSoundSource / SoundEngine.Play work like with any
  other sound file.

  Positional sounds follow Doom's S_AdjustSoundParams instead of the
  engine's distance model: full volume within 160 units (the approximate
  2D distance adx + ady - min / 2), fading linearly to silence at 1200
  (on the eighth map of an episode, and Doom 2's MAP08, never below 15 of
  127, and never cut), and panned by 0.75 of the sine of the angle from
  the listener's facing (S_STEREO_SWING 96 of 128). Each sound plays
  through its own small transform (a "channel") that the listener update
  keeps right beside the listener in the direction that gives this pan,
  with the volume set on the playing sound; it is recomputed every frame
  while the emitter moves, and the sound stops when it goes out of range
  (S_UpdateSounds). A new sound from an emitter stops the one it was
  playing, like Doom's one channel per origin.

  Like Doom, at most eight sounds play at once (snd_channels): the
  player's own sounds (PlayOwn) replace each other, positional ones those
  of the same emitter, and when all eight channels are busy a new sound
  takes the first one whose priority (sounds.c's, lower wins) is not
  better, or is not played (S_getChannel). A channel is busy for its
  sound's length (from the DMX lump), counted in the game time Advance
  is given. Sounds started without an origin (Play: menus, the boss
  brain) only take channels. }
unit DoomSound;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleSoundEngine, CastleVectors, CastleTransform, CastleBehaviors,
  DoomWad;

type
  TDoomSoundChannel = class;

  { A sound starts: Emitter is nil for a sound without a position. }
  TSoundPlayEvent = procedure (const LumpName: String; const Emitter: TCastleTransform) of object;

  TDoomSounds = class
  strict private
    FWad: TDoomWad;
    FSounds: {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>;
    FVolume: Single;
    FOnPlay: TSoundPlayEvent;
    FChannels: {$ifdef FPC}specialize{$endif} TObjectList<TDoomSoundChannel>;
    FListenerX, FListenerY, FListenerAngle: Single;
    FListenerEye: TVector3;
    FHaveListener, FBossMap, FLogPositional: Boolean;
    FTime: Double;
    FDurations: {$ifdef FPC}specialize{$endif} TDictionary<String, Single>;
    FMaxChannels: Integer;
    procedure PlaceChannel(const C: TDoomSoundChannel);
    function Duration(const LumpName: String): Single;
    procedure PurgeChannels;
    { S_getChannel: room for a new sound (stopping the one it replaces);
      False when every channel holds a better sound. }
    function FreeChannel(const LumpName: String; const Emitter: TCastleTransform;
      const Own: Boolean): Boolean;
    function NewChannel(const LumpName: String; const S: TCastleSound; const Emitter: TCastleTransform;
      const Own: Boolean): TDoomSoundChannel;
    function ReadSfx(const Url: String; out MimeType: String): TStream;
    procedure SetVolume(const Value: Single);
  public
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;
    { TCastleSound for a lump like 'DSPISTOL' (nil when the lump is missing). }
    function Sound(const LumpName: String): TCastleSound;
    { Non-positional playback without an origin (menus, the boss brain,
      monsters heard everywhere). }
    procedure Play(const LumpName: String);
    { The player's own sound (weapons, pickups, pain): a new one stops the
      last. }
    procedure PlayOwn(const LumpName: String);
    { Game time passes (the channels' sounds end). }
    procedure Advance(const SecondsPassed: Single);
    { Sounds playing now (busy channels). }
    function ChannelCount: Integer;
    { Doom's snd_channels: 8. }
    property MaxChannels: Integer read FMaxChannels write FMaxChannels;
    { A positional sound from a transform (an actor, a sector's sound
      origin), with Doom's falloff and separation (see the unit's comment).
      Not played when out of range of the listener. }
    procedure PlayAt(const LumpName: String; const Emitter: TCastleTransform);
    { Where the sounds are heard, every frame: Doom coordinates and facing
      (degrees counter-clockwise from east) and the camera's position in
      the engine's world (the sound engine's listener). BossMap: the
      eighth map's rule (sounds never fade out). }
    procedure UpdateListener(const DoomX, DoomY, AngleDeg: Single; const Eye: TVector3;
      const BossMap: Boolean);
    { Stop every positional sound (a level ends). }
    procedure StopPositional;
    { Positional sounds playing now. }
    function PositionalCount: Integer;
    { Log each positional sound's volume and separation (demo SOUNDLOG). }
    property LogPositional: Boolean read FLogPositional write FLogPositional;
    property Wad: TDoomWad read FWad;
    { Gain of every sound effect (0..1, the options' sound volume). }
    property Volume: Single read FVolume write SetVolume;
    { Every sound that starts (closed captions, GameViewPlay). }
    property OnPlay: TSoundPlayEvent read FOnPlay write FOnPlay;
  end;

  { One positional sound playing (internal to TDoomSounds). }
  TDoomSoundChannel = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    Emitter: TCastleTransform;
    Place: TCastleTransform;
    Playing: TCastlePlayingSound;
    LumpName: String;
    Done: Boolean;
    { The player's own sound; its priority; when it ends (game time). }
    Own: Boolean;
    Priority: Integer;
    EndTime: Double;
    destructor Destroy; override;
  end;

{ Doom's S_AdjustSoundParams: the volume (0..1 of the full one) and the
  separation (-0.75 left .. 0.75 right) of a sound at (SourceX, SourceY)
  heard at (ListenerX, ListenerY) facing ListenerAngle (degrees). False
  when it is out of range (volume 0). BossMap: the eighth map's rule. }
function DoomSoundParams(const ListenerX, ListenerY, ListenerAngle, SourceX, SourceY: Single;
  const BossMap: Boolean; out Volume, Separation: Single): Boolean;

{ Convert a DMX sound lump into a WAV file in memory. nil when not a sound lump. }
function DmxToWav(const Data: PByte; const Size: Integer): TMemoryStream;

implementation

uses Math, CastleDownload, CastleLog, CastleUriUtils, CastleUtils, DoomStates;

const
  { s_sound.c: S_CLOSE_DIST, S_CLIPPING_DIST, S_ATTENUATOR, S_STEREO_SWING
    (in units, out of 128 for the swing) and the eighth map's floor (15 of
    the full 127). }
  SoundCloseDist = 160;
  SoundClippingDist = 1200;
  SoundAttenuator = SoundClippingDist - SoundCloseDist;
  SoundStereoSwing = 96 / 128;
  BossMapFloor = 15 / 127;
  { How far from the listener a channel's transform is placed. }
  ChannelDistance = 16;

function DoomSoundParams(const ListenerX, ListenerY, ListenerAngle, SourceX, SourceY: Single;
  const BossMap: Boolean; out Volume, Separation: Single): Boolean;
var
  AdX, AdY, Dist, Rel: Single;
begin
  AdX := Abs(ListenerX - SourceX);
  AdY := Abs(ListenerY - SourceY);
  { "From _GG1_ p.428. Appox. eucledian distance fast." }
  Dist := AdX + AdY - Min(AdX, AdY) / 2;
  Volume := 0;
  Separation := 0;
  if (not BossMap) and (Dist > SoundClippingDist) then
    Exit(false);
  { The angle of the source from the listener's facing; Doom's sep is
    128 - swing * sin, low on the left: here negative on the left. }
  if (AdX > 0.001) or (AdY > 0.001) then
  begin
    Rel := ArcTan2(SourceY - ListenerY, SourceX - ListenerX) - DegToRad(ListenerAngle);
    Separation := -SoundStereoSwing * Sin(Rel);
  end;
  if Dist < SoundCloseDist then
    Volume := 1
  else if BossMap then
    Volume := BossMapFloor + (1 - BossMapFloor) * (SoundClippingDist - Min(Dist, SoundClippingDist)) / SoundAttenuator
  else
    Volume := (SoundClippingDist - Dist) / SoundAttenuator;
  Result := Volume > 0;
end;

{ TDoomSoundChannel ---------------------------------------------------------- }

procedure TDoomSoundChannel.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent = Emitter) then
  begin
    { Doom stops a removed thing's sounds (P_RemoveMobj). }
    Emitter := nil;
    Done := true;
    if Playing <> nil then Playing.Stop;
  end;
end;

destructor TDoomSoundChannel.Destroy;
begin
  if Emitter <> nil then Emitter.RemoveFreeNotification(Self);
  { Place owns the sound source, which stops the sound. }
  FreeAndNil(Place);
  FreeAndNil(Playing);
  inherited;
end;

function DmxToWav(const Data: PByte; const Size: Integer): TMemoryStream;
var
  Format, Rate: Word;
  SampleCount, DataSize: Int32;
  Samples: PByte;

  procedure WriteU32(const V: UInt32);
  begin
    Result.WriteBuffer(V, 4);
  end;

  procedure WriteU16(const V: UInt16);
  begin
    Result.WriteBuffer(V, 2);
  end;

  procedure WriteTag(const S: AnsiString);
  begin
    Result.WriteBuffer(S[1], 4);
  end;

begin
  Result := nil;
  if Size < 8 then Exit;
  Format := PUInt16(Data)^;
  Rate := PUInt16(Data + 2)^;
  SampleCount := PInt32(Data + 4)^;
  if (Format <> 3) or (Rate = 0) or (SampleCount <= 48) or (SampleCount > Size - 8) then
    Exit;
  { DMX pads the samples with 16 bytes on each side. }
  Samples := Data + 8 + 16;
  DataSize := SampleCount - 32;

  Result := TMemoryStream.Create;
  WriteTag('RIFF');
  WriteU32(36 + DataSize);
  WriteTag('WAVE');
  WriteTag('fmt ');
  WriteU32(16);
  WriteU16(1); { PCM }
  WriteU16(1); { mono }
  WriteU32(Rate);
  WriteU32(Rate); { byte rate: 8-bit mono }
  WriteU16(1); { block align }
  WriteU16(8); { bits per sample }
  WriteTag('data');
  WriteU32(DataSize);
  Result.WriteBuffer(Samples^, DataSize);
  Result.Position := 0;
end;

{ TDoomSounds ---------------------------------------------------------------- }

constructor TDoomSounds.Create(const AWad: TDoomWad);
begin
  inherited Create;
  FWad := AWad;
  FVolume := 1;
  FSounds := {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>.Create([doOwnsValues]);
  FChannels := {$ifdef FPC}specialize{$endif} TObjectList<TDoomSoundChannel>.Create(true);
  FDurations := {$ifdef FPC}specialize{$endif} TDictionary<String, Single>.Create;
  FMaxChannels := 8;
  RegisterUrlProtocol('doomsfx', {$ifdef FPC}@{$endif} ReadSfx, nil);
end;

destructor TDoomSounds.Destroy;
begin
  FreeAndNil(FChannels);
  FreeAndNil(FDurations);
  FreeAndNil(FSounds);
  UnregisterUrlProtocol('doomsfx');
  inherited;
end;

function TDoomSounds.ReadSfx(const Url: String; out MimeType: String): TStream;
var
  Name: String;
  Lump: Integer;
begin
  { URL looks like doomsfx:/DSPISTOL }
  Name := UpperCase(ExtractUriName(Url));
  Lump := FWad.FindLump(Name);
  if Lump < 0 then
    raise Exception.CreateFmt('Sound lump %s not found', [Name]);
  Result := DmxToWav(FWad.LumpPointer(Lump), FWad.LumpSize(Lump));
  if Result = nil then
    raise Exception.CreateFmt('Lump %s is not a DMX sound', [Name]);
  MimeType := 'audio/x-wav';
end;

function TDoomSounds.Sound(const LumpName: String): TCastleSound;
var
  U: String;
begin
  { A BEX [SOUNDS] rename points the name at another lump. }
  U := UpperCase(RenamedSound(LumpName));
  if U = '' then Exit(nil);
  if FSounds.TryGetValue(U, Result) then Exit;
  if U <> UpperCase(LumpName) then
    WritelnLog('Sound', '%s plays %s (BEX rename)', [UpperCase(LumpName), U]);
  if FWad.FindLump(U) < 0 then
  begin
    WritelnWarning('Sound', 'Missing sound lump %s', [U]);
    FSounds.Add(U, nil);
    Exit(nil);
  end;
  Result := TCastleSound.Create(nil);
  { Doom units: sounds are at full volume within ~200 units and fade out
    towards 1200 (S_CLOSE_DIST / S_CLIPPING_DIST in s_sound.c). }
  Result.ReferenceDistance := 200;
  Result.MaxDistance := 1800;
  Result.Url := 'doomsfx:/' + U;
  Result.Volume := FVolume;
  FSounds.Add(U, Result);
end;

procedure TDoomSounds.SetVolume(const Value: Single);
var
  S: TCastleSound;
begin
  FVolume := Value;
  for S in FSounds.Values do
    if S <> nil then
      S.Volume := Value;
end;

function TDoomSounds.Duration(const LumpName: String): Single;
var
  U: String;
  Lump: Integer;
  P: PByte;
  Rate: Word;
  Count: LongWord;
begin
  U := UpperCase(LumpName);
  if FDurations.TryGetValue(U, Result) then Exit;
  Result := 1;
  Lump := FWad.FindLump(U);
  if (Lump >= 0) and (FWad.LumpSize(Lump) >= 8) then
  begin
    { DMX: format, sample rate, sample count (with 32 padding bytes). }
    P := FWad.LumpPointer(Lump);
    Rate := PWord(P + 2)^;
    Count := PLongWord(P + 4)^;
    if (Rate > 0) and (Count > 32) then
      Result := (Count - 32) / Rate;
  end;
  FDurations.Add(U, Result);
end;

procedure TDoomSounds.PurgeChannels;
var
  I: Integer;
  C: TDoomSoundChannel;
begin
  for I := FChannels.Count - 1 downto 0 do
  begin
    C := FChannels[I];
    if C.Done or (FTime >= C.EndTime) then
    begin
      if C.Emitter <> nil then
      begin
        C.Emitter.RemoveFreeNotification(C);
        C.Emitter := nil;
      end;
      FChannels.Delete(I);
    end;
  end;
end;

function TDoomSounds.FreeChannel(const LumpName: String; const Emitter: TCastleTransform;
  const Own: Boolean): Boolean;
var
  I, Priority: Integer;
  C: TDoomSoundChannel;
begin
  PurgeChannels;
  { One sound per origin: a new one stops the last. }
  if (Emitter <> nil) or Own then
    for I := 0 to FChannels.Count - 1 do
    begin
      C := FChannels[I];
      if ((Emitter <> nil) and (C.Emitter = Emitter)) or (Own and C.Own) then
      begin
        if FLogPositional then
          WritelnLog('Sound', '%s replaces %s (the same origin)', [UpperCase(LumpName), C.LumpName]);
        C.Done := true;
        if C.Playing <> nil then C.Playing.Stop;
        PurgeChannels;
        Exit(true);
      end;
    end;
  if FChannels.Count < FMaxChannels then Exit(true);
  { All busy: the first sound whose priority is not better goes. }
  Priority := SoundPriority(LumpName);
  for I := 0 to FChannels.Count - 1 do
  begin
    C := FChannels[I];
    if C.Priority >= Priority then
    begin
      if FLogPositional then
        WritelnLog('Sound', '%s (priority %d) takes the channel of %s (priority %d)',
          [UpperCase(LumpName), Priority, C.LumpName, C.Priority]);
      C.Done := true;
      if C.Playing <> nil then C.Playing.Stop;
      PurgeChannels;
      Exit(true);
    end;
  end;
  if FLogPositional then
    WritelnLog('Sound', '%s (priority %d) not played: %d channels hold better sounds',
      [UpperCase(LumpName), Priority, FChannels.Count]);
  Result := false;
end;

function TDoomSounds.NewChannel(const LumpName: String; const S: TCastleSound; const Emitter: TCastleTransform;
  const Own: Boolean): TDoomSoundChannel;
begin
  Result := TDoomSoundChannel.Create(nil);
  Result.LumpName := UpperCase(LumpName);
  Result.Own := Own;
  Result.Priority := SoundPriority(LumpName);
  Result.EndTime := FTime + Duration(RenamedSound(LumpName));
  if Emitter <> nil then
  begin
    Result.Emitter := Emitter;
    Emitter.FreeNotification(Result);
  end;
  FChannels.Add(Result);
end;

procedure TDoomSounds.Play(const LumpName: String);
var
  S: TCastleSound;
  C: TDoomSoundChannel;
begin
  S := Sound(LumpName);
  if S = nil then Exit;
  if not FreeChannel(LumpName, nil, false) then Exit;
  C := NewChannel(LumpName, S, nil, false);
  C.Playing := TCastlePlayingSound.Create(nil);
  C.Playing.Sound := S;
  SoundEngine.Play(C.Playing);
  if Assigned(FOnPlay) then FOnPlay(LumpName, nil);
end;

procedure TDoomSounds.PlayOwn(const LumpName: String);
var
  S: TCastleSound;
  C: TDoomSoundChannel;
begin
  S := Sound(LumpName);
  if S = nil then Exit;
  if not FreeChannel(LumpName, nil, true) then Exit;
  C := NewChannel(LumpName, S, nil, true);
  C.Playing := TCastlePlayingSound.Create(nil);
  C.Playing.Sound := S;
  SoundEngine.Play(C.Playing);
  if Assigned(FOnPlay) then FOnPlay(LumpName, nil);
end;

procedure TDoomSounds.Advance(const SecondsPassed: Single);
begin
  FTime := FTime + SecondsPassed;
end;

function TDoomSounds.ChannelCount: Integer;
begin
  PurgeChannels;
  Result := FChannels.Count;
end;

procedure TDoomSounds.PlaceChannel(const C: TDoomSoundChannel);
var
  P: TVector3;
  Vol, Sep, A: Single;
begin
  if C.Emitter = nil then Exit;
  P := C.Emitter.WorldTranslation;
  { The emitter in Doom coordinates (CgeToDoom: x, -z). }
  if not DoomSoundParams(FListenerX, FListenerY, FListenerAngle, P.X, -P.Z, FBossMap, Vol, Sep) then
  begin
    C.Done := true;
    if C.Playing <> nil then C.Playing.Stop;
    Exit;
  end;
  if C.Playing <> nil then C.Playing.Volume := Vol;
  { Beside the listener, in the direction whose sine is the separation
    (right of the facing for a positive one), in front, so neither the
    height nor the distance changes what is heard. }
  A := DegToRad(FListenerAngle) - ArcSin(Max(-1, Min(1, Sep)));
  C.Place.Translation := FListenerEye + Vector3(Cos(A) * ChannelDistance, 0, -Sin(A) * ChannelDistance);
end;

procedure TDoomSounds.PlayAt(const LumpName: String; const Emitter: TCastleTransform);
var
  S: TCastleSound;
  Source: TCastleSoundSource;
  C: TDoomSoundChannel;
  P: TVector3;
  Vol, Sep: Single;
begin
  S := Sound(LumpName);
  if (S = nil) or (Emitter = nil) then Exit;
  if (not FHaveListener) or (Emitter.World = nil) then
  begin
    { No listener yet: the engine's own 3D sound at the emitter. }
    Source := Emitter.FindBehavior(TCastleSoundSource) as TCastleSoundSource;
    if Source = nil then
    begin
      Source := TCastleSoundSource.Create(Emitter);
      Source.Spatial := true;
      Emitter.AddBehavior(Source);
    end;
    Source.Play(S);
    if Assigned(FOnPlay) then FOnPlay(LumpName, Emitter);
    Exit;
  end;
  P := Emitter.WorldTranslation;
  if not DoomSoundParams(FListenerX, FListenerY, FListenerAngle, P.X, -P.Z, FBossMap, Vol, Sep) then
  begin
    if FLogPositional then
      WritelnLog('Sound', '%s at (%.0f, %.0f): out of range, not played', [UpperCase(LumpName), P.X, -P.Z]);
    Exit;
  end;
  if not FreeChannel(LumpName, Emitter, false) then Exit;
  C := NewChannel(LumpName, S, Emitter, false);
  C.Place := TCastleTransform.Create(nil);
  C.Place.Name := 'SoundChannel';
  Emitter.World.Add(C.Place);
  Source := TCastleSoundSource.Create(C.Place);
  Source.Spatial := true;
  C.Place.AddBehavior(Source);
  C.Playing := TCastlePlayingSoundSource.Create(nil);
  C.Playing.Sound := S;
  PlaceChannel(C);
  Source.Play(TCastlePlayingSoundSource(C.Playing));
  if FLogPositional then
    WritelnLog('Sound', '%s at (%.0f, %.0f): volume %.2f, separation %.2f', [C.LumpName, P.X, -P.Z, Vol, Sep]);
  if Assigned(FOnPlay) then FOnPlay(LumpName, Emitter);
end;

procedure TDoomSounds.UpdateListener(const DoomX, DoomY, AngleDeg: Single; const Eye: TVector3;
  const BossMap: Boolean);
var
  I: Integer;
begin
  FListenerX := DoomX;
  FListenerY := DoomY;
  FListenerAngle := AngleDeg;
  FListenerEye := Eye;
  FBossMap := BossMap;
  FHaveListener := true;
  PurgeChannels;
  for I := FChannels.Count - 1 downto 0 do
    PlaceChannel(FChannels[I]);
end;

procedure TDoomSounds.StopPositional;
begin
  FChannels.Clear;
  FHaveListener := false;
end;

function TDoomSounds.PositionalCount: Integer;
begin
  Result := FChannels.Count;
end;

end.
