{ Doom sound effects through the Castle Game Engine sound engine.

  Doom stores sounds as DMX lumps (DS*): 8-bit unsigned PCM with a small
  header. We register a custom URL protocol "doomsfx:" with CGE, so that
  "doomsfx:/DSPISTOL" is converted on the fly into a WAV stream. From then on
  TCastleSound / TCastleSoundSource / SoundEngine.Play work like with any
  other sound file (positional 3D audio included). }
unit DoomSound;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleSoundEngine, CastleVectors, CastleTransform, CastleBehaviors,
  DoomWad;

type
  TDoomSounds = class
  strict private
    FWad: TDoomWad;
    FSounds: {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>;
    function ReadSfx(const Url: String; out MimeType: String): TStream;
  public
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;
    { TCastleSound for a lump like 'DSPISTOL' (nil when the lump is missing). }
    function Sound(const LumpName: String): TCastleSound;
    { Non-positional playback (UI, player's own weapon). }
    procedure Play(const LumpName: String);
    { Attach a positional sound source to a transform and play through it. }
    procedure PlayAt(const LumpName: String; const Emitter: TCastleTransform);
    property Wad: TDoomWad read FWad;
  end;

{ Convert a DMX sound lump into a WAV file in memory. nil when not a sound lump. }
function DmxToWav(const Data: PByte; const Size: Integer): TMemoryStream;

implementation

uses CastleDownload, CastleLog, CastleUriUtils, CastleUtils;

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
  FSounds := {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>.Create([doOwnsValues]);
  RegisterUrlProtocol('doomsfx', {$ifdef FPC}@{$endif} ReadSfx, nil);
end;

destructor TDoomSounds.Destroy;
begin
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
  U := UpperCase(LumpName);
  if U = '' then Exit(nil);
  if FSounds.TryGetValue(U, Result) then Exit;
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
  FSounds.Add(U, Result);
end;

procedure TDoomSounds.Play(const LumpName: String);
var
  S: TCastleSound;
begin
  S := Sound(LumpName);
  if S <> nil then
    SoundEngine.Play(S);
end;

procedure TDoomSounds.PlayAt(const LumpName: String; const Emitter: TCastleTransform);
var
  S: TCastleSound;
  Source: TCastleSoundSource;
begin
  S := Sound(LumpName);
  if (S = nil) or (Emitter = nil) then Exit;
  Source := Emitter.FindBehavior(TCastleSoundSource) as TCastleSoundSource;
  if Source = nil then
  begin
    Source := TCastleSoundSource.Create(Emitter);
    Source.Spatial := true;
    Emitter.AddBehavior(Source);
  end;
  Source.Play(S);
end;

end.
