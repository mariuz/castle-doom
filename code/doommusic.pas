{ Doom music: MUS and MIDI lumps rendered with the WAD's GENMIDI instrument
  bank (the same instrument definitions the original game used with AdLib /
  Sound Blaster cards). The song is rendered once to a 16-bit WAV in memory,
  a slice per frame (TDoomMusic.Update) so a level start does not freeze,
  served through the custom "doommus:" URL protocol and looped by the
  engine's sound system.

  Two synthesizers share the parsing, the timeline and the WAV writer
  (TSongRenderer): TOplSongRenderer programs a real OPL3 emulator (Nuked
  OPL3, loaded as a shared library by DoomOpl3) with the GENMIDI registers
  the way the game's DMX driver did; TFmSongRenderer is the built-in
  approximation of the Yamaha YM3812 (two operators per voice, modulator ->
  carrier or additive, 4 waveforms, ADSR envelopes with rate scaling,
  key-scale level, feedback, vibrato and tremolo), used when the library is
  missing and always on the web. }
unit DoomMusic;

interface

uses SysUtils, Classes, Generics.Collections,
  CastleSoundEngine, CastleTimeUtils,
  DoomWad;

type
  TDoomMusic = class
  strict private
    FWad: TDoomWad;
    FSounds: {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>;
    { Rendered songs (WAV in memory), served by ReadMusic. }
    FReady: {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TMemoryStream>;
    { The song being rendered a slice per frame (a TSongRenderer), its lump
      and the time spent so far; lumps waiting to be rendered. }
    FRenderer: TObject;
    FRendering: String;
    FRenderTime: Double;
    FQueue: TStringList;
    FCurrent: String;
    FEnabled: Boolean;
    FVolume: Single;
    { The music playing now, and the quick-start part of a song still being
      rendered (its lump and when it started). }
    FPlaying: TCastlePlayingSound;
    FIntroSound: TCastleSound;
    FIntroOf: String;
    FIntroStart: TTimerResult;
    { The song whose first seconds should start playing as soon as they
      are rendered (Update renders them in slices), and since when. }
    FIntroWanted: String;
    FIntroWantedSince: TTimerResult;
    FPrefetch: String;
    procedure PlaySound(const Sound: TCastleSound; const Loop: Boolean; const Offset: Single);
    procedure StopSound;
    procedure StartIntro(const LumpName: String);
    procedure TryStartIntro;
    function ReadMusic(const Url: String; out MimeType: String): TStream;
    procedure SetEnabled(const Value: Boolean);
    procedure SetVolume(const Value: Single);
    { Queue a lump for rendering; First puts it before everything else. }
    procedure Prepare(const LumpName: String; const First: Boolean);
    procedure StartNextRender;
    procedure FinishRender;
    procedure StartPlaying(const LumpName: String; const Offset: Single);
    { Free rendered songs nothing will play soon (each is ~0.5 MB a 15 s). }
    procedure ReleaseUnneeded;
  public
    { Seconds of synthesis per Update call (one per frame). }
    RenderBudget: Single;
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;
    { Start looping the music lump (like 'D_E1M1'). Empty name stops music. }
    procedure Play(const LumpName: String);
    procedure Stop;
    { Render a song in the background (after the ones already queued), e.g.
      the next map's while this one is played, so that it starts at once. }
    procedure Prefetch(const LumpName: String);
    { Call every frame: renders the next slice of a queued song and starts
      the current one as soon as it is ready. }
    procedure Update;
    { Music lump for a map: D_E1M1..., or the Doom 2 track table. }
    function LumpForMap(const MapName: String): String;
    function TitleLump: String;
    function IntermissionLump: String;
    property Current: String read FCurrent;
    property Enabled: Boolean read FEnabled write SetEnabled;
    property Volume: Single read FVolume write SetVolume;
  end;

{ Render a MUS or MIDI lump to a WAV stream using GENMIDI. nil when the data
  is not a song or GENMIDI is missing. }
function RenderDoomSong(const Wad: TDoomWad; const SongData: PByte; const SongSize: Integer): TMemoryStream;

var
  { Use the built-in FM model even when the Nuked OPL3 library is there
    (command line --fm-synth). }
  ForceFmSynth: Boolean = false;

implementation

uses Math, CastleDownload, CastleLog, CastleUriUtils, CastleUtils, DoomOpl3;

const
  SampleRate = 22050;
  MaxVoices = 36;
  MaxSongSeconds = 480;

type
  TEventKind = (ekNoteOn, ekNoteOff, ekProgram, ekVolume, ekExpression, ekPitchBend, ekAllNotesOff);

  TMusicEvent = record
    Time: Double; { seconds }
    Kind: TEventKind;
    Channel: Byte; { 0..15, 9 = percussion }
    Data1, Data2: Integer;
  end;
  TMusicEventList = {$ifdef FPC}specialize{$endif} TList<TMusicEvent>;

  TOperatorParams = record
    Tremolo, Vibrato, Sustain, Ksr: Boolean;
    Multi: Integer;
    Attack, Decay, SustainLevel, Release: Integer;
    Waveform: Integer;
    Ksl: Integer;
    Level: Integer;
  end;

  TVoiceParams = record
    Modulator, Carrier: TOperatorParams;
    Feedback: Integer;
    Additive: Boolean;
    NoteOffset: Integer;
  end;

  TInstrument = record
    FixedPitch: Boolean;
    DoubleVoice: Boolean;
    FineTuning: Integer;
    FixedNote: Integer;
    Voices: array [0..1] of TVoiceParams;
  end;

  TEnvState = (esOff, esAttack, esDecay, esSustain, esRelease);

  TOperator = record
    Params: TOperatorParams;
    { Fixed point phase: 2^32 = one cycle. }
    Phase: Cardinal;
    PhaseInc: Cardinal;
    State: TEnvState;
    { Attenuation in dB (0 = full), used in decay/sustain/release. }
    AttDb: Double;
    { Linear level during attack (0..1). }
    AttackLevel: Double;
    AttackRate, DecayRate, ReleaseRate: Double; { per sample }
    SustainDb: Double;
    StaticGain: Double; { total level + key scale level, linear }
    Out1, Out2: Double; { previous outputs for feedback }
  end;

  TVoice = record
    Active: Boolean;
    Channel: Integer;
    Note: Integer;
    Params: TVoiceParams;
    Ops: array [0..1] of TOperator;
    Gain: Double;
    BaseFreq: Double;
    Age: Int64;
  end;

  TChannelState = record
    Prog: Integer;
    Volume: Integer;
    Expression: Integer;
    PitchBend: Double; { semitones }
  end;

const
  PhaseBits = 11; { 2048-entry wave tables }
  PhaseShift = 32 - PhaseBits;
  PhaseMask = (1 shl PhaseBits) - 1;
  GainTableSize = 961; { 0..96 dB in 0.1 dB steps }

var
  { Four OPL waveforms: sine, half sine, absolute sine, pulse sine. }
  WaveTables: array [0..3, 0..2047] of Single;
  GainTable: array [0..GainTableSize - 1] of Single;
  MultiTable: array [0..15] of Double = (0.5, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 10, 12, 12, 15, 15);

procedure InitTables;
var
  I: Integer;
  S, P: Double;
begin
  for I := 0 to 2047 do
  begin
    P := I / 2048;
    S := Sin(P * 2 * Pi);
    WaveTables[0, I] := S;
    if P < 0.5 then WaveTables[1, I] := S else WaveTables[1, I] := 0;
    WaveTables[2, I] := Abs(S);
    if (P < 0.25) or ((P >= 0.5) and (P < 0.75)) then WaveTables[3, I] := Abs(S) else WaveTables[3, I] := 0;
  end;
  for I := 0 to GainTableSize - 1 do
    GainTable[I] := Power(10, -(I / 10) / 20);
end;

function DbToGain(const Db: Double): Double; inline;
var
  I: Integer;
begin
  I := Trunc(Db * 10);
  if I < 0 then I := 0;
  if I >= GainTableSize then Exit(0);
  Result := GainTable[I];
end;

function CyclesToPhase(const Cycles: Double): Cardinal; inline;
var
  F: Double;
begin
  F := Cycles - Floor(Cycles);
  Result := Cardinal(Trunc(F * 4294967296.0));
end;

{ --- GENMIDI -------------------------------------------------------------- }

function LoadGenMidi(const Wad: TDoomWad; out Instruments: array of TInstrument): Boolean;
var
  Lump, I, V: Integer;
  P, Q: PByte;

  procedure ReadOp(const B: PByte; var Op: TOperatorParams);
  begin
    Op.Tremolo := (B[0] and $80) <> 0;
    Op.Vibrato := (B[0] and $40) <> 0;
    Op.Sustain := (B[0] and $20) <> 0;
    Op.Ksr := (B[0] and $10) <> 0;
    Op.Multi := B[0] and $0F;
    Op.Attack := B[1] shr 4;
    Op.Decay := B[1] and $0F;
    Op.SustainLevel := B[2] shr 4;
    Op.Release := B[2] and $0F;
    Op.Waveform := B[3] and $03;
    Op.Ksl := B[4] shr 6;
    Op.Level := B[5] and $3F;
  end;

begin
  Lump := Wad.FindLump('GENMIDI');
  if (Lump < 0) or (Wad.LumpSize(Lump) < 8 + 175 * 36) then Exit(false);
  P := Wad.LumpPointer(Lump);
  if (Chr(P[0]) + Chr(P[1]) + Chr(P[2]) + Chr(P[3])) <> '#OPL' then Exit(false);
  for I := 0 to 174 do
  begin
    Q := P + 8 + I * 36;
    Instruments[I].FixedPitch := (Q[0] and 1) <> 0;
    Instruments[I].DoubleVoice := (Q[0] and 4) <> 0;
    Instruments[I].FineTuning := Q[2];
    Instruments[I].FixedNote := Q[3];
    for V := 0 to 1 do
    begin
      ReadOp(Q + 4 + V * 16, Instruments[I].Voices[V].Modulator);
      Instruments[I].Voices[V].Feedback := (Q[4 + V * 16 + 6] shr 1) and 7;
      Instruments[I].Voices[V].Additive := (Q[4 + V * 16 + 6] and 1) <> 0;
      ReadOp(Q + 4 + V * 16 + 7, Instruments[I].Voices[V].Carrier);
      Instruments[I].Voices[V].NoteOffset := PInt16(Q + 4 + V * 16 + 14)^;
    end;
  end;
  Result := true;
end;

{ --- MUS parsing ---------------------------------------------------------- }

function ParseMus(const Data: PByte; const Size: Integer; const Events: TMusicEventList): Boolean;
var
  ScoreLen, ScoreStart, Pos, EndPos: Integer;
  Time: Double;
  B, Kind, Channel, Note, Ctrl, Value: Integer;
  LastVolume: array [0..15] of Integer;
  E: TMusicEvent;
  Delay: Integer;
  Last: Boolean;

  function MusChannel(const C: Integer): Byte;
  begin
    { MUS channel 15 is percussion; MIDI convention is channel 9. }
    if C = 15 then Result := 9
    else if C = 9 then Result := 15
    else Result := C;
  end;

begin
  Result := false;
  if (Size < 16) or (Data[0] <> Ord('M')) or (Data[1] <> Ord('U')) or (Data[2] <> Ord('S')) then Exit;
  ScoreLen := PUInt16(Data + 4)^;
  ScoreStart := PUInt16(Data + 6)^;
  Pos := ScoreStart;
  EndPos := Min(Size, ScoreStart + ScoreLen);
  Time := 0;
  for Channel := 0 to 15 do LastVolume[Channel] := 100;
  while Pos < EndPos do
  begin
    B := Data[Pos]; Inc(Pos);
    Last := (B and $80) <> 0;
    Kind := (B shr 4) and 7;
    Channel := B and 15;
    E := Default(TMusicEvent);
    E.Time := Time;
    E.Channel := MusChannel(Channel);
    case Kind of
      0: begin
           if Pos >= EndPos then Break;
           Note := Data[Pos] and $7F; Inc(Pos);
           E.Kind := ekNoteOff; E.Data1 := Note; Events.Add(E);
         end;
      1: begin
           if Pos >= EndPos then Break;
           B := Data[Pos]; Inc(Pos);
           Note := B and $7F;
           if (B and $80) <> 0 then
           begin
             if Pos >= EndPos then Break;
             LastVolume[Channel] := Data[Pos] and $7F; Inc(Pos);
           end;
           E.Kind := ekNoteOn; E.Data1 := Note; E.Data2 := LastVolume[Channel]; Events.Add(E);
         end;
      2: begin
           if Pos >= EndPos then Break;
           Value := Data[Pos]; Inc(Pos);
           E.Kind := ekPitchBend; E.Data1 := Round((Value - 128) / 128 * 8192) + 8192; Events.Add(E);
         end;
      3: begin
           if Pos >= EndPos then Break;
           Ctrl := Data[Pos]; Inc(Pos);
           if Ctrl in [10, 11] then
           begin
             E.Kind := ekAllNotesOff; Events.Add(E);
           end;
         end;
      4: begin
           if Pos + 1 >= EndPos then Break;
           Ctrl := Data[Pos]; Value := Data[Pos + 1]; Inc(Pos, 2);
           case Ctrl of
             0: begin E.Kind := ekProgram; E.Data1 := Value and $7F; Events.Add(E); end;
             3: begin E.Kind := ekVolume; E.Data1 := Value and $7F; Events.Add(E); end;
             5: begin E.Kind := ekExpression; E.Data1 := Value and $7F; Events.Add(E); end;
           end;
         end;
      5: ;
      6: Break;
      7: Inc(Pos);
    end;
    if Last then
    begin
      Delay := 0;
      repeat
        if Pos >= EndPos then Break;
        B := Data[Pos]; Inc(Pos);
        Delay := Delay * 128 + (B and $7F);
      until (B and $80) = 0;
      Time := Time + Delay / 140;
    end;
  end;
  Result := Events.Count > 0;
end;

{ --- MIDI parsing --------------------------------------------------------- }

type
  TTickEvent = record
    Tick: Int64;
    Order: Integer;
    IsTempo: Boolean;
    Tempo: Integer; { microseconds per quarter }
    Ev: TMusicEvent;
  end;
  TTickEventList = {$ifdef FPC}specialize{$endif} TList<TTickEvent>;

function TickBefore(const A, B: TTickEvent): Boolean;
begin
  if A.Tick <> B.Tick then Exit(A.Tick < B.Tick);
  Result := A.Order <= B.Order;
end;

{ Stable merge sort by (Tick, Order); avoids Generics.Defaults comparers,
  whose types differ between FPC 3.2 and the main branch. }
procedure SortTickEvents(var A: array of TTickEvent);
var
  Tmp: array of TTickEvent;

  procedure Sort(const Lo, Hi: Integer);
  var
    Mid, I, J, K: Integer;
  begin
    if Hi - Lo < 1 then Exit;
    Mid := (Lo + Hi) div 2;
    Sort(Lo, Mid);
    Sort(Mid + 1, Hi);
    I := Lo; J := Mid + 1; K := Lo;
    while (I <= Mid) and (J <= Hi) do
    begin
      if TickBefore(A[I], A[J]) then
      begin
        Tmp[K] := A[I]; Inc(I);
      end else
      begin
        Tmp[K] := A[J]; Inc(J);
      end;
      Inc(K);
    end;
    while I <= Mid do begin Tmp[K] := A[I]; Inc(I); Inc(K); end;
    while J <= Hi do begin Tmp[K] := A[J]; Inc(J); Inc(K); end;
    for K := Lo to Hi do A[K] := Tmp[K];
  end;

begin
  SetLength(Tmp, Length(A));
  Sort(0, High(A));
end;

function ParseMidi(const Data: PByte; const Size: Integer; const Events: TMusicEventList): Boolean;
var
  Division, NTracks, T, Pos, TrackEnd, Len, Status, RunningStatus, D1, D2, Order: Integer;
  Tick: Int64;
  All: TTickEventList;
  TE: TTickEvent;
  I: Integer;
  Tempo: Integer;
  LastTick: Int64;
  Time: Double;
  Sorted: array of TTickEvent;

  function ReadVlq: Integer;
  var
    B: Integer;
  begin
    Result := 0;
    repeat
      if Pos >= TrackEnd then Exit;
      B := Data[Pos]; Inc(Pos);
      Result := (Result shl 7) or (B and $7F);
    until (B and $80) = 0;
  end;

  function Be32(const P: PByte): Integer;
  begin
    Result := (P[0] shl 24) or (P[1] shl 16) or (P[2] shl 8) or P[3];
  end;

  procedure AddEvent(const Kind: TEventKind; const Channel, A, B: Integer);
  begin
    TE := Default(TTickEvent);
    TE.Tick := Tick;
    TE.Order := Order; Inc(Order);
    TE.Ev.Kind := Kind;
    TE.Ev.Channel := Channel;
    TE.Ev.Data1 := A;
    TE.Ev.Data2 := B;
    All.Add(TE);
  end;

begin
  Result := false;
  if (Size < 14) or (Data[0] <> Ord('M')) or (Data[1] <> Ord('T')) or (Data[2] <> Ord('h')) or (Data[3] <> Ord('d')) then Exit;
  NTracks := (Data[10] shl 8) or Data[11];
  Division := (Data[12] shl 8) or Data[13];
  if (Division and $8000) <> 0 then Division := 96; { SMPTE timing: rare, approximate }
  if Division <= 0 then Division := 96;
  All := TTickEventList.Create;
  try
    Order := 0;
    Pos := 8 + Be32(Data + 4);
    for T := 0 to NTracks - 1 do
    begin
      if Pos + 8 > Size then Break;
      if not ((Data[Pos] = Ord('M')) and (Data[Pos + 1] = Ord('T')) and (Data[Pos + 2] = Ord('r')) and (Data[Pos + 3] = Ord('k'))) then Break;
      Len := Be32(Data + Pos + 4);
      Pos := Pos + 8;
      TrackEnd := Min(Size, Pos + Len);
      Tick := 0;
      RunningStatus := 0;
      while Pos < TrackEnd do
      begin
        Tick := Tick + ReadVlq;
        if Pos >= TrackEnd then Break;
        Status := Data[Pos];
        if (Status and $80) <> 0 then
        begin
          Inc(Pos);
          if Status < $F0 then RunningStatus := Status;
        end else
          Status := RunningStatus;
        case Status and $F0 of
          $80, $90, $A0, $B0, $E0:
            begin
              if Pos + 1 >= TrackEnd then Break;
              D1 := Data[Pos] and $7F; D2 := Data[Pos + 1] and $7F; Inc(Pos, 2);
              case Status and $F0 of
                $80: AddEvent(ekNoteOff, Status and 15, D1, D2);
                $90: if D2 = 0 then AddEvent(ekNoteOff, Status and 15, D1, 0)
                     else AddEvent(ekNoteOn, Status and 15, D1, D2);
                $B0: case D1 of
                       7: AddEvent(ekVolume, Status and 15, D2, 0);
                       11: AddEvent(ekExpression, Status and 15, D2, 0);
                       120, 123: AddEvent(ekAllNotesOff, Status and 15, 0, 0);
                     end;
                $E0: AddEvent(ekPitchBend, Status and 15, D1 or (D2 shl 7), 0);
              end;
            end;
          $C0, $D0:
            begin
              if Pos >= TrackEnd then Break;
              D1 := Data[Pos] and $7F; Inc(Pos);
              if (Status and $F0) = $C0 then AddEvent(ekProgram, Status and 15, D1, 0);
            end;
          $F0:
            begin
              if Status = $FF then
              begin
                if Pos >= TrackEnd then Break;
                D1 := Data[Pos]; Inc(Pos);
                Len := ReadVlq;
                if (D1 = $51) and (Len = 3) and (Pos + 2 < TrackEnd) then
                begin
                  TE := Default(TTickEvent);
                  TE.Tick := Tick;
                  TE.Order := Order; Inc(Order);
                  TE.IsTempo := true;
                  TE.Tempo := (Data[Pos] shl 16) or (Data[Pos + 1] shl 8) or Data[Pos + 2];
                  All.Add(TE);
                end;
                if D1 = $2F then
                begin
                  Pos := TrackEnd;
                  Break;
                end;
                Pos := Pos + Len;
              end else if (Status = $F0) or (Status = $F7) then
              begin
                Len := ReadVlq;
                Pos := Pos + Len;
              end else
                Break; { unexpected realtime/system message }
            end;
          else Break;
        end;
      end;
      Pos := TrackEnd;
    end;

    Sorted := All.ToArray;
    SortTickEvents(Sorted);

    Tempo := 500000;
    LastTick := 0;
    Time := 0;
    for I := 0 to High(Sorted) do
    begin
      Time := Time + (Sorted[I].Tick - LastTick) * (Tempo / 1000000) / Division;
      LastTick := Sorted[I].Tick;
      if Sorted[I].IsTempo then
        Tempo := Sorted[I].Tempo
      else
      begin
        TE := Sorted[I];
        TE.Ev.Time := Time;
        Events.Add(TE.Ev);
      end;
    end;
    Result := Events.Count > 0;
  finally
    FreeAndNil(All);
  end;
end;

{ --- Synthesizer ---------------------------------------------------------- }

function RateTime(const Rate: Integer; const Block: Integer; const Ksr: Boolean; const Attack: Boolean): Double;
var
  Base, Rks: Double;
begin
  { YM3812 timings: attack rate 1 = 2.83 s, decay/release rate 1 = 39.3 s for
    96 dB, halving with every rate step. Rate scaling shortens them with pitch. }
  if Rate <= 0 then Exit(1e9);
  if Rate >= 15 then Exit(0.0005);
  if Attack then Base := 2.826 else Base := 39.28;
  if Ksr then Rks := Block * 2 else Rks := Block / 2;
  Result := Base / Power(2, (Rate - 1) + Rks / 4);
end;

procedure SetupOperator(var Op: TOperator; const Params: TOperatorParams; const Freq: Double; const Block: Integer);
const
  KslDb: array [0..3] of Double = (0, 1.5, 3, 6);
begin
  Op.Params := Params;
  Op.PhaseInc := CyclesToPhase(Freq * MultiTable[Params.Multi] / SampleRate);
  Op.Phase := 0;
  Op.Out1 := 0;
  Op.Out2 := 0;
  Op.State := esAttack;
  Op.AttackLevel := 0;
  Op.AttDb := 0;
  Op.StaticGain := DbToGain(Params.Level * 0.75 + KslDb[Params.Ksl] * Max(0, Block - 1));
  Op.SustainDb := Params.SustainLevel * 3;
  if Params.SustainLevel = 15 then Op.SustainDb := 93;
  Op.AttackRate := 1 / (RateTime(Params.Attack, Block, Params.Ksr, true) * SampleRate);
  Op.DecayRate := 96 / (RateTime(Params.Decay, Block, Params.Ksr, false) * SampleRate);
  Op.ReleaseRate := 96 / (RateTime(Params.Release, Block, Params.Ksr, false) * SampleRate);
  if Params.Attack >= 15 then
  begin
    Op.State := esDecay;
    Op.AttackLevel := 1;
  end;
end;

{ Advance the envelope one sample; returns linear amplitude (0..1). }
function EnvelopeStep(var Op: TOperator): Double;
begin
  case Op.State of
    esAttack:
      begin
        Op.AttackLevel := Op.AttackLevel + Op.AttackRate * (1.5 - Op.AttackLevel);
        if Op.AttackLevel >= 0.999 then
        begin
          Op.AttackLevel := 1;
          Op.State := esDecay;
        end;
        Exit(Op.AttackLevel);
      end;
    esDecay:
      begin
        Op.AttDb := Op.AttDb + Op.DecayRate;
        if Op.AttDb >= Op.SustainDb then
        begin
          Op.AttDb := Op.SustainDb;
          if Op.Params.Sustain then
            Op.State := esSustain
          else
            Op.State := esRelease;
        end;
      end;
    esSustain: ;
    esRelease:
      begin
        Op.AttDb := Op.AttDb + Op.ReleaseRate;
        if Op.AttDb >= 96 then
        begin
          Op.AttDb := 96;
          Op.State := esOff;
          Exit(0);
        end;
      end;
    esOff: Exit(0);
  end;
  Result := DbToGain(Op.AttDb);
end;

{ TSongRenderer -------------------------------------------------------------- }

{ The synthesizer as an object, so a song can be rendered a slice at a time
  (TDoomMusic.Update) instead of blocking for seconds at a level start. }
type
  { A song being rendered: the parsed events, the channel state and the
    output; the synthesizer itself is the subclass. }
  TSongRenderer = class
  protected
    Instruments: array [0..174] of TInstrument;
    Events: TMusicEventList;
    Channels: array [0..15] of TChannelState;
    TotalSamples, SampleIndex, NextEvent: Integer;
    Float: array of Single;
    Peak: Double;
    { Start a new song (after the parse; the channels are reset already). }
    procedure ResetSynth; virtual; abstract;
    { Render samples SampleIndex .. Last - 1 into Float, handling the events
      that fall due (Events[NextEvent] onwards), and keep Peak. }
    procedure Render(const Last: Integer); virtual; abstract;
  public
    destructor Destroy; override;
    class function SynthName: String; virtual; abstract;
    { Multiplies the rendered samples in MakeWav (one gain for every song:
      the OPL had no normalization either, and the first seconds rendered
      for a quick start, TDoomMusic.Play, must equal the same part of the
      finished song, so switching is seamless). }
    class function OutputGain: Double; virtual; abstract;
    { Parse the song; false when it is not MUS / MIDI or GENMIDI is missing. }
    function Init(const Wad: TDoomWad; const SongData: PByte; const SongSize: Integer): Boolean;
    { Render up to Count more samples; true when the song is complete. }
    function Step(const Count: Integer): Boolean;
    function Done: Boolean;
    { The first Count rendered samples (all of them by default) as a 16-bit
      mono WAV (caller owns it). }
    function MakeWav(const Count: Integer = -1): TMemoryStream;
    { Samples rendered so far. }
    function Rendered: Integer;
    function Seconds: Double;
    property SongPeak: Double read Peak;
  end;

  { The built-in FM model. }
  TFmSongRenderer = class(TSongRenderer)
  strict private
    Voices: array [0..MaxVoices - 1] of TVoice;
    VoiceHigh: Integer;
    VibLfo, TremLfo, VibPhase, TremPhase: Double;
    Age: Int64;
    function FindVoice: Integer;
    procedure ReleaseVoice(var Vc: TVoice);
    procedure StartVoice(const Channel, Note, Velocity: Integer; const Params: TVoiceParams;
      const PlayNote: Double);
    procedure NoteOn(const Channel, Note, Velocity: Integer);
    procedure NoteOff(const Channel, Note: Integer);
    procedure UpdateVoiceFreqs(const Channel: Integer);
    procedure UpdateVoiceGains(const Channel: Integer);
    procedure HandleEvent(const Ev: TMusicEvent);
    function RenderVoice(var Vc: TVoice; const VibMul, Trem: Double): Double;
  protected
    procedure ResetSynth; override;
    procedure Render(const Last: Integer); override;
  public
    class function SynthName: String; override;
    class function OutputGain: Double; override;
  end;

const
  OplVoices = 18;
  { The OPL3's own sample rate: F-number to Hz. }
  OplRate = 49716;
  { Operator slot of the first operator of channels 0..8 in a bank; the
    second operator is 3 higher. }
  OplSlot: array [0..8] of Byte = (0, 1, 2, 8, 9, 10, 16, 17, 18);

type
  TOplVoice = record
    { Key on. A voice that was released may be taken again at once (the
      release tail is cut when all 18 are needed, like DMX did). }
    Active: Boolean;
    Channel, Note, Velocity: Integer;
    Params: TVoiceParams;
    PlayNote: Double;
    Age: Int64;
  end;

  { Nuked OPL3 driven like the game's DMX driver: two-operator melodic
    channels (18 in OPL3 mode), one per GENMIDI voice, with the instrument's
    operator bytes written to the chip and the note's F-number / block. }
  TOplSongRenderer = class(TSongRenderer)
  strict private
    Chip: TOpl3Chip;
    Voices: array [0..OplVoices - 1] of TOplVoice;
    Age: Int64;
    Buffer: array of SmallInt;
    function ChannelReg(const V, Base: Integer): Word;
    function SlotReg(const V, Op, Base: Integer): Word;
    procedure WriteOperator(const V, Op: Integer; const P: TOperatorParams; const Level: Integer);
    procedure SetVolume(const V: Integer);
    procedure SetFrequency(const V: Integer; const KeyOn: Boolean);
    function FindVoice: Integer;
    procedure StartVoice(const Channel, Note, Velocity: Integer; const Params: TVoiceParams;
      const PlayNote: Double);
    procedure NoteOn(const Channel, Note, Velocity: Integer);
    procedure NoteOff(const Channel, Note: Integer);
    procedure HandleEvent(const Ev: TMusicEvent);
  protected
    procedure ResetSynth; override;
    procedure Render(const Last: Integer); override;
  public
    destructor Destroy; override;
    class function SynthName: String; override;
    class function OutputGain: Double; override;
  end;

{ The synthesizer for the next song: the OPL3 library when it loads. }
function NewSongRenderer: TSongRenderer;
begin
  if (not ForceFmSynth) and Opl3Available then
    Result := TOplSongRenderer.Create
  else
    Result := TFmSongRenderer.Create;
end;

destructor TSongRenderer.Destroy;
begin
  FreeAndNil(Events);
  inherited;
end;

function TFmSongRenderer.FindVoice: Integer;
var
  J, Oldest: Integer;
begin
  for J := 0 to MaxVoices - 1 do
    if not Voices[J].Active then Exit(J);
  Oldest := 0;
  for J := 1 to MaxVoices - 1 do
    if Voices[J].Age < Voices[Oldest].Age then Oldest := J;
  Result := Oldest;
end;

procedure TFmSongRenderer.ReleaseVoice(var Vc: TVoice);
var
  O: Integer;
begin
  for O := 0 to 1 do
    if Vc.Ops[O].State <> esOff then
    begin
      if Vc.Ops[O].State = esAttack then Vc.Ops[O].AttDb := -20 * Log10(Max(Vc.Ops[O].AttackLevel, 1e-4));
      Vc.Ops[O].State := esRelease;
    end;
end;

procedure TFmSongRenderer.StartVoice(const Channel, Note, Velocity: Integer; const Params: TVoiceParams;
  const PlayNote: Double);
var
  Idx, Block: Integer;
  Freq: Double;
begin
  Idx := FindVoice;
  if Idx >= VoiceHigh then VoiceHigh := Idx + 1;
  Voices[Idx] := Default(TVoice);
  Voices[Idx].Active := true;
  Voices[Idx].Channel := Channel;
  Voices[Idx].Note := Note;
  Voices[Idx].Params := Params;
  Voices[Idx].Age := Age; Inc(Age);
  Voices[Idx].BaseFreq := 440 * Power(2, (PlayNote - 69) / 12);
  Freq := Voices[Idx].BaseFreq * Power(2, Channels[Channel].PitchBend / 12);
  Block := Clamped(Round(PlayNote) div 12 - 1, 0, 7);
  SetupOperator(Voices[Idx].Ops[0], Params.Modulator, Freq, Block);
  SetupOperator(Voices[Idx].Ops[1], Params.Carrier, Freq, Block);
  Voices[Idx].Gain := (Velocity / 127) * (Channels[Channel].Volume / 127) * (Channels[Channel].Expression / 127);
end;

procedure TFmSongRenderer.NoteOn(const Channel, Note, Velocity: Integer);
var
  Inst: Integer;
  PlayNote: Double;
  I2: TInstrument;
begin
  if Channel = 9 then
  begin
    Inst := 128 + Note - 35;
    if (Inst < 128) or (Inst > 174) then Exit;
  end else
    Inst := Clamped(Channels[Channel].Prog, 0, 127);
  I2 := Instruments[Inst];
  if I2.FixedPitch then PlayNote := I2.FixedNote else PlayNote := Note;
  StartVoice(Channel, Note, Velocity, I2.Voices[0], PlayNote + I2.Voices[0].NoteOffset);
  if I2.DoubleVoice then
    StartVoice(Channel, Note, Velocity, I2.Voices[1], PlayNote + I2.Voices[1].NoteOffset + (I2.FineTuning - 128) / 64);
end;

procedure TFmSongRenderer.NoteOff(const Channel, Note: Integer);
var
  J: Integer;
begin
  for J := 0 to MaxVoices - 1 do
    if Voices[J].Active and (Voices[J].Channel = Channel) and (Voices[J].Note = Note) and
       (Voices[J].Ops[1].State <> esRelease) then
      ReleaseVoice(Voices[J]);
end;

procedure TFmSongRenderer.UpdateVoiceFreqs(const Channel: Integer);
var
  J: Integer;
  Freq: Double;
begin
  for J := 0 to MaxVoices - 1 do
    if Voices[J].Active and (Voices[J].Channel = Channel) then
    begin
      Freq := Voices[J].BaseFreq * Power(2, Channels[Channel].PitchBend / 12);
      Voices[J].Ops[0].PhaseInc := CyclesToPhase(Freq * MultiTable[Voices[J].Ops[0].Params.Multi] / SampleRate);
      Voices[J].Ops[1].PhaseInc := CyclesToPhase(Freq * MultiTable[Voices[J].Ops[1].Params.Multi] / SampleRate);
    end;
end;

procedure TFmSongRenderer.UpdateVoiceGains(const Channel: Integer);
var
  J: Integer;
begin
  for J := 0 to MaxVoices - 1 do
    if Voices[J].Active and (Voices[J].Channel = Channel) then
      Voices[J].Gain := 1.0 * (Channels[Channel].Volume / 127) * (Channels[Channel].Expression / 127);
end;

procedure TFmSongRenderer.HandleEvent(const Ev: TMusicEvent);
var
  J: Integer;
begin
  case Ev.Kind of
    ekNoteOn: NoteOn(Ev.Channel, Ev.Data1, Ev.Data2);
    ekNoteOff: NoteOff(Ev.Channel, Ev.Data1);
    ekProgram: Channels[Ev.Channel].Prog := Ev.Data1;
    ekVolume: begin Channels[Ev.Channel].Volume := Ev.Data1; UpdateVoiceGains(Ev.Channel); end;
    ekExpression: begin Channels[Ev.Channel].Expression := Ev.Data1; UpdateVoiceGains(Ev.Channel); end;
    ekPitchBend:
      begin
        Channels[Ev.Channel].PitchBend := (Ev.Data1 - 8192) / 8192 * 2;
        UpdateVoiceFreqs(Ev.Channel);
      end;
    ekAllNotesOff:
      for J := 0 to MaxVoices - 1 do
        if Voices[J].Active and (Voices[J].Channel = Ev.Channel) then ReleaseVoice(Voices[J]);
  end;
end;

function TFmSongRenderer.RenderVoice(var Vc: TVoice; const VibMul, Trem: Double): Double;
var
  ModOut, CarOut, Env0, Env1, Fb: Double;
  Idx: Cardinal;
  Inc0, Inc1: Cardinal;
begin
  Env0 := EnvelopeStep(Vc.Ops[0]);
  Env1 := EnvelopeStep(Vc.Ops[1]);
  if (Vc.Ops[1].State = esOff) and ((not Vc.Params.Additive) or (Vc.Ops[0].State = esOff)) then
  begin
    Vc.Active := false;
    Exit(0);
  end;
  if Vc.Ops[0].Params.Vibrato then Inc0 := Trunc(Vc.Ops[0].PhaseInc * VibMul) else Inc0 := Vc.Ops[0].PhaseInc;
  if Vc.Ops[1].Params.Vibrato then Inc1 := Trunc(Vc.Ops[1].PhaseInc * VibMul) else Inc1 := Vc.Ops[1].PhaseInc;
  if Vc.Ops[0].Params.Tremolo then Env0 := Env0 * Trem;
  if Vc.Ops[1].Params.Tremolo then Env1 := Env1 * Trem;

  { Modulator with feedback (feedback 7 = up to 2 cycles of phase). }
  Idx := Vc.Ops[0].Phase;
  if Vc.Params.Feedback > 0 then
  begin
    Fb := (Vc.Ops[0].Out1 + Vc.Ops[0].Out2) * (2.0 / (1 shl (8 - Vc.Params.Feedback)));
    Idx := Idx + Cardinal(Int64(Trunc(Fb * 4294967296.0)) and $FFFFFFFF);
  end;
  ModOut := WaveTables[Vc.Ops[0].Params.Waveform, Idx shr PhaseShift] * Env0 * Vc.Ops[0].StaticGain;
  Vc.Ops[0].Out2 := Vc.Ops[0].Out1;
  Vc.Ops[0].Out1 := ModOut;
  Vc.Ops[0].Phase := Vc.Ops[0].Phase + Inc0;

  if Vc.Params.Additive then
  begin
    CarOut := WaveTables[Vc.Ops[1].Params.Waveform, Vc.Ops[1].Phase shr PhaseShift] * Env1 * Vc.Ops[1].StaticGain;
    Result := (ModOut + CarOut) * Vc.Gain;
  end else
  begin
    { Full modulator output swings the carrier phase by up to 4 cycles. }
    Idx := Vc.Ops[1].Phase + Cardinal(Int64(Trunc(ModOut * 4 * 4294967296.0)) and $FFFFFFFF);
    CarOut := WaveTables[Vc.Ops[1].Params.Waveform, Idx shr PhaseShift] * Env1 * Vc.Ops[1].StaticGain;
    Result := CarOut * Vc.Gain;
  end;
  Vc.Ops[1].Phase := Vc.Ops[1].Phase + Inc1;
end;

function TSongRenderer.Init(const Wad: TDoomWad; const SongData: PByte; const SongSize: Integer): Boolean;
var
  I: Integer;
  EndTime: Double;
begin
  Result := false;
  if not LoadGenMidi(Wad, Instruments) then
  begin
    WritelnWarning('Music', 'No GENMIDI lump, cannot synthesize music');
    Exit;
  end;
  FreeAndNil(Events);
  Events := TMusicEventList.Create;
  if not (ParseMus(SongData, SongSize, Events) or ParseMidi(SongData, SongSize, Events)) then
    Exit;
  EndTime := 0;
  for I := 0 to Events.Count - 1 do
    EndTime := Max(EndTime, Events[I].Time);
  EndTime := Min(EndTime + 1.5, MaxSongSeconds);
  TotalSamples := Trunc(EndTime * SampleRate);
  if TotalSamples <= 0 then Exit;
  SetLength(Float, TotalSamples);
  Peak := 0;
  for I := 0 to 15 do
  begin
    Channels[I].Prog := 0;
    Channels[I].Volume := 100;
    Channels[I].Expression := 127;
    Channels[I].PitchBend := 0;
  end;
  NextEvent := 0;
  SampleIndex := 0;
  ResetSynth;
  Result := true;
end;

procedure TFmSongRenderer.ResetSynth;
var
  I: Integer;
begin
  for I := 0 to MaxVoices - 1 do Voices[I].Active := false;
  Age := 0;
  VoiceHigh := 0;
  VibPhase := 0;
  TremPhase := 0;
  VibLfo := 1;
  TremLfo := 1;
end;

class function TFmSongRenderer.SynthName: String;
begin
  Result := 'the built-in FM synthesizer';
end;

class function TFmSongRenderer.OutputGain: Double;
begin
  { Freedoom's tracks peak at 3.4 .. 8 here, 5.5 maps to 0.89. }
  Result := 0.89 / 5.5;
end;

function TSongRenderer.Step(const Count: Integer): Boolean;
var
  Last: Integer;
begin
  if Count >= TotalSamples - SampleIndex then
    Last := TotalSamples
  else
    Last := SampleIndex + Count;
  Render(Last);
  Result := Done;
end;

procedure TFmSongRenderer.Render(const Last: Integer);
var
  V: Integer;
  Mix: Double;
begin
  while SampleIndex < Last do
  begin
    while (NextEvent < Events.Count) and (Events[NextEvent].Time * SampleRate <= SampleIndex) do
    begin
      HandleEvent(Events[NextEvent]);
      Inc(NextEvent);
    end;
    { OPL vibrato: 6.1 Hz, about 7 cents; tremolo: 3.7 Hz, 1 dB. Updated every 32 samples. }
    if (SampleIndex and 31) = 0 then
    begin
      VibPhase := VibPhase + 6.1 * 32 / SampleRate;
      TremPhase := TremPhase + 3.7 * 32 / SampleRate;
      VibLfo := Power(2, Sin(VibPhase * 2 * Pi) * 0.07 / 12);
      TremLfo := Power(10, (Sin(TremPhase * 2 * Pi) - 1) * 0.5 / 20);
    end;
    Mix := 0;
    for V := 0 to VoiceHigh - 1 do
      if Voices[V].Active then
        Mix := Mix + RenderVoice(Voices[V], VibLfo, TremLfo);
    Float[SampleIndex] := Mix;
    if Abs(Mix) > Peak then Peak := Abs(Mix);
    Inc(SampleIndex);
  end;
end;

function TSongRenderer.Done: Boolean;
begin
  Result := SampleIndex >= TotalSamples;
end;

function TSongRenderer.Seconds: Double;
begin
  Result := TotalSamples / SampleRate;
end;

function TSongRenderer.Rendered: Integer;
begin
  Result := SampleIndex;
end;

function TSongRenderer.MakeWav(const Count: Integer): TMemoryStream;
const
  Knee = 0.7;
var
  Samples: array of SmallInt;
  I, N: Integer;
  X, A, Gain: Double;

  procedure WriteU32(const S: TStream; const X: UInt32);
  begin
    S.WriteBuffer(X, 4);
  end;

  procedure WriteU16(const S: TStream; const X: UInt16);
  begin
    S.WriteBuffer(X, 2);
  end;

  procedure WriteTag(const S: TStream; const T: AnsiString);
  begin
    S.WriteBuffer(T[1], 4);
  end;

begin
  if (Count < 0) or (Count > SampleIndex) then N := SampleIndex else N := Count;
  if N < 1 then N := 1;
  Gain := OutputGain;
  SetLength(Samples, N);
  for I := 0 to N - 1 do
  begin
    X := Float[I] * Gain;
    { Soft limiter above the knee: smooth, never past full scale. }
    A := Abs(X);
    if A > Knee then
    begin
      A := Knee + (1 - Knee) * Tanh((A - Knee) / (1 - Knee));
      if X < 0 then X := -A else X := A;
    end;
    Samples[I] := Round(X * 32767);
  end;
  Result := TMemoryStream.Create;
  WriteTag(Result, 'RIFF');
  WriteU32(Result, 36 + N * 2);
  WriteTag(Result, 'WAVE');
  WriteTag(Result, 'fmt ');
  WriteU32(Result, 16);
  WriteU16(Result, 1);
  WriteU16(Result, 1);
  WriteU32(Result, SampleRate);
  WriteU32(Result, SampleRate * 2);
  WriteU16(Result, 2);
  WriteU16(Result, 16);
  WriteTag(Result, 'data');
  WriteU32(Result, N * 2);
  Result.WriteBuffer(Samples[0], N * 2);
  Result.Position := 0;
end;


{ TOplSongRenderer ----------------------------------------------------------- }

destructor TOplSongRenderer.Destroy;
begin
  FreeAndNil(Chip);
  inherited;
end;

class function TOplSongRenderer.SynthName: String;
begin
  Result := 'Nuked OPL3';
end;

class function TOplSongRenderer.OutputGain: Double;
begin
  { The chip's 16-bit output scaled to -1..1; Freedoom's songs peak around
    0.3 .. 0.5 there. }
  Result := 1.8;
end;

function TOplSongRenderer.ChannelReg(const V, Base: Integer): Word;
begin
  Result := (V div 9) * $100 + Base + (V mod 9);
end;

function TOplSongRenderer.SlotReg(const V, Op, Base: Integer): Word;
begin
  Result := (V div 9) * $100 + Base + OplSlot[V mod 9] + Op * 3;
end;

procedure TOplSongRenderer.WriteOperator(const V, Op: Integer; const P: TOperatorParams; const Level: Integer);
begin
  Chip.WriteReg(SlotReg(V, Op, $20),
    Ord(P.Tremolo) shl 7 or Ord(P.Vibrato) shl 6 or Ord(P.Sustain) shl 5 or Ord(P.Ksr) shl 4 or P.Multi);
  Chip.WriteReg(SlotReg(V, Op, $40), P.Ksl shl 6 or Level);
  Chip.WriteReg(SlotReg(V, Op, $60), P.Attack shl 4 or P.Decay);
  Chip.WriteReg(SlotReg(V, Op, $80), P.SustainLevel shl 4 or P.Release);
  Chip.WriteReg(SlotReg(V, Op, $E0), P.Waveform);
end;

{ The carrier's total level (and the modulator's when the operators add)
  attenuated by velocity, channel volume and expression: 0.75 dB per step. }
procedure TOplSongRenderer.SetVolume(const V: Integer);
var
  Vol: Double;
  Att: Integer;
begin
  Vol := (Voices[V].Velocity / 127) * (Channels[Voices[V].Channel].Volume / 127) *
    (Channels[Voices[V].Channel].Expression / 127);
  if Vol <= 0.0001 then
    Att := 63
  else
    Att := Round(-20 * Log10(Vol) / 0.75);
  Chip.WriteReg(SlotReg(V, 1, $40),
    Voices[V].Params.Carrier.Ksl shl 6 or Min(63, Voices[V].Params.Carrier.Level + Att));
  if Voices[V].Params.Additive then
    Chip.WriteReg(SlotReg(V, 0, $40),
      Voices[V].Params.Modulator.Ksl shl 6 or Min(63, Voices[V].Params.Modulator.Level + Att));
end;

procedure TOplSongRenderer.SetFrequency(const V: Integer; const KeyOn: Boolean);
var
  Freq, FNum: Double;
  Block, N: Integer;
begin
  Freq := 440 * Power(2, (Voices[V].PlayNote - 69 + Channels[Voices[V].Channel].PitchBend) / 12);
  FNum := Freq * 1048576 / OplRate;
  Block := 0;
  while (FNum >= 1024) and (Block < 7) do
  begin
    FNum := FNum / 2;
    Inc(Block);
  end;
  N := Min(1023, Round(FNum));
  Chip.WriteReg(ChannelReg(V, $A0), N and $FF);
  Chip.WriteReg(ChannelReg(V, $B0), Ord(KeyOn) shl 5 or Block shl 2 or N shr 8);
end;

function TOplSongRenderer.FindVoice: Integer;
var
  J, Oldest: Integer;
begin
  for J := 0 to OplVoices - 1 do
    if not Voices[J].Active then Exit(J);
  Oldest := 0;
  for J := 1 to OplVoices - 1 do
    if Voices[J].Age < Voices[Oldest].Age then Oldest := J;
  Result := Oldest;
end;

procedure TOplSongRenderer.StartVoice(const Channel, Note, Velocity: Integer; const Params: TVoiceParams;
  const PlayNote: Double);
var
  V: Integer;
begin
  V := FindVoice;
  if Voices[V].Active then
    SetFrequency(V, false);
  Voices[V].Active := true;
  Voices[V].Channel := Channel;
  Voices[V].Note := Note;
  Voices[V].Velocity := Velocity;
  Voices[V].Params := Params;
  Voices[V].PlayNote := PlayNote;
  Voices[V].Age := Age; Inc(Age);
  WriteOperator(V, 0, Params.Modulator, Params.Modulator.Level);
  WriteOperator(V, 1, Params.Carrier, Params.Carrier.Level);
  { Feedback, connection; bits 4 and 5 send the channel to both outputs. }
  Chip.WriteReg(ChannelReg(V, $C0), $30 or Params.Feedback shl 1 or Ord(Params.Additive));
  SetVolume(V);
  SetFrequency(V, true);
end;

procedure TOplSongRenderer.NoteOn(const Channel, Note, Velocity: Integer);
var
  Inst: Integer;
  PlayNote: Double;
  I2: TInstrument;
begin
  if Channel = 9 then
  begin
    Inst := 128 + Note - 35;
    if (Inst < 128) or (Inst > 174) then Exit;
  end else
    Inst := Clamped(Channels[Channel].Prog, 0, 127);
  I2 := Instruments[Inst];
  if I2.FixedPitch then PlayNote := I2.FixedNote else PlayNote := Note;
  StartVoice(Channel, Note, Velocity, I2.Voices[0], PlayNote + I2.Voices[0].NoteOffset);
  if I2.DoubleVoice then
    StartVoice(Channel, Note, Velocity, I2.Voices[1], PlayNote + I2.Voices[1].NoteOffset + (I2.FineTuning - 128) / 64);
end;

procedure TOplSongRenderer.NoteOff(const Channel, Note: Integer);
var
  J: Integer;
begin
  for J := 0 to OplVoices - 1 do
    if Voices[J].Active and (Voices[J].Channel = Channel) and (Voices[J].Note = Note) then
    begin
      SetFrequency(J, false);
      Voices[J].Active := false;
    end;
end;

procedure TOplSongRenderer.HandleEvent(const Ev: TMusicEvent);
var
  J: Integer;
begin
  case Ev.Kind of
    ekNoteOn: NoteOn(Ev.Channel, Ev.Data1, Ev.Data2);
    ekNoteOff: NoteOff(Ev.Channel, Ev.Data1);
    ekProgram: Channels[Ev.Channel].Prog := Ev.Data1;
    ekVolume, ekExpression:
      begin
        if Ev.Kind = ekVolume then
          Channels[Ev.Channel].Volume := Ev.Data1
        else
          Channels[Ev.Channel].Expression := Ev.Data1;
        for J := 0 to OplVoices - 1 do
          if Voices[J].Active and (Voices[J].Channel = Ev.Channel) then SetVolume(J);
      end;
    ekPitchBend:
      begin
        Channels[Ev.Channel].PitchBend := (Ev.Data1 - 8192) / 8192 * 2;
        for J := 0 to OplVoices - 1 do
          if Voices[J].Active and (Voices[J].Channel = Ev.Channel) then SetFrequency(J, true);
      end;
    ekAllNotesOff:
      for J := 0 to OplVoices - 1 do
        if Voices[J].Active and (Voices[J].Channel = Ev.Channel) then
        begin
          SetFrequency(J, false);
          Voices[J].Active := false;
        end;
  end;
end;

procedure TOplSongRenderer.ResetSynth;
var
  V: Integer;
begin
  FreeAndNil(Chip);
  Chip := TOpl3Chip.Create(SampleRate);
  SetLength(Buffer, 2 * 2048);
  Chip.WriteReg($105, 1);  { OPL3 mode: 18 channels, 8 waveforms }
  Chip.WriteReg($104, 0);  { no four-operator channels }
  Chip.WriteReg($01, $20); { waveform select }
  Chip.WriteReg($BD, 0);   { no rhythm mode, shallow vibrato and tremolo }
  for V := 0 to OplVoices - 1 do
  begin
    Voices[V] := Default(TOplVoice);
    Chip.WriteReg(ChannelReg(V, $B0), 0);
    Chip.WriteReg(ChannelReg(V, $C0), $30);
    Chip.WriteReg(SlotReg(V, 0, $40), $3F);
    Chip.WriteReg(SlotReg(V, 1, $40), $3F);
  end;
  Age := 0;
end;

procedure TOplSongRenderer.Render(const Last: Integer);
var
  N, I: Integer;
  X: Single;
begin
  while SampleIndex < Last do
  begin
    while (NextEvent < Events.Count) and (Events[NextEvent].Time * SampleRate <= SampleIndex) do
    begin
      HandleEvent(Events[NextEvent]);
      Inc(NextEvent);
    end;
    { Up to the next event, in buffer-sized pieces. }
    N := Last - SampleIndex;
    if NextEvent < Events.Count then
      N := Min(N, Ceil(Events[NextEvent].Time * SampleRate) - SampleIndex);
    N := Min(Max(N, 1), Length(Buffer) div 2);
    Chip.Generate(@Buffer[0], N);
    for I := 0 to N - 1 do
    begin
      X := Buffer[2 * I] / 32768;
      Float[SampleIndex + I] := X;
      if Abs(X) > Peak then Peak := Abs(X);
    end;
    Inc(SampleIndex, N);
  end;
end;

function RenderDoomSong(const Wad: TDoomWad; const SongData: PByte; const SongSize: Integer): TMemoryStream;
var
  R: TSongRenderer;
begin
  Result := nil;
  R := NewSongRenderer;
  try
    if not R.Init(Wad, SongData, SongSize) then Exit;
    R.Step(MaxInt);
    Result := R.MakeWav;
  finally
    FreeAndNil(R);
  end;
end;

{ TDoomMusic ----------------------------------------------------------------- }

constructor TDoomMusic.Create(const AWad: TDoomWad);
begin
  inherited Create;
  FWad := AWad;
  FEnabled := true;
  FVolume := 0.5;
  RenderBudget := 0.012;
  FSounds := {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>.Create([doOwnsValues]);
  FReady := {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TMemoryStream>.Create([doOwnsValues]);
  FQueue := TStringList.Create;
  RegisterUrlProtocol('doommus', {$ifdef FPC}@{$endif} ReadMusic, nil);
  if ForceFmSynth then
    WritelnLog('Music', 'Built-in FM synthesizer forced (--fm-synth)')
  else
    WritelnLog('Music', Opl3Status);
end;

destructor TDoomMusic.Destroy;
begin
  Stop;
  FreeAndNil(FRenderer);
  FreeAndNil(FQueue);
  FreeAndNil(FSounds);
  FreeAndNil(FReady);
  UnregisterUrlProtocol('doommus');
  inherited;
end;

function TDoomMusic.ReadMusic(const Url: String; out MimeType: String): TStream;
var
  Name: String;
  Lump: Integer;
  Wav: TMemoryStream;
begin
  Name := UpperCase(ExtractUriName(Url));
  if LowerCase(ExtractFileExt(Name)) = '.wav' then
    Name := Copy(Name, 1, Length(Name) - 4);
  if not FReady.TryGetValue(Name, Wav) then
  begin
    { Not rendered in slices (yet): render it all now. }
    Lump := FWad.FindLump(Name);
    if Lump < 0 then
      raise Exception.CreateFmt('Music lump %s not found', [Name]);
    Wav := RenderDoomSong(FWad, FWad.LumpPointer(Lump), FWad.LumpSize(Lump));
    if Wav = nil then
      raise Exception.CreateFmt('Lump %s is not a MUS/MIDI song', [Name]);
    FReady.AddOrSetValue(Name, Wav);
  end;
  Result := TMemoryStream.Create;
  Wav.Position := 0;
  Result.CopyFrom(Wav, 0);
  Result.Position := 0;
  MimeType := 'audio/x-wav';
end;

procedure TDoomMusic.Prepare(const LumpName: String; const First: Boolean);
var
  Idx: Integer;
begin
  if (LumpName = '') or FReady.ContainsKey(LumpName) or (FRendering = LumpName) then Exit;
  if FWad.FindLump(LumpName) < 0 then Exit;
  Idx := FQueue.IndexOf(LumpName);
  if Idx >= 0 then FQueue.Delete(Idx);
  if First then FQueue.Insert(0, LumpName) else FQueue.Add(LumpName);
end;

procedure TDoomMusic.StartNextRender;
var
  Lump: Integer;
  R: TSongRenderer;
  Name: String;
begin
  while (FRenderer = nil) and (FQueue.Count > 0) do
  begin
    Name := FQueue[0];
    FQueue.Delete(0);
    if FReady.ContainsKey(Name) then Continue;
    Lump := FWad.FindLump(Name);
    if Lump < 0 then Continue;
    R := NewSongRenderer;
    if not R.Init(FWad, FWad.LumpPointer(Lump), FWad.LumpSize(Lump)) then
    begin
      WritelnWarning('Music', 'Lump %s is not a MUS/MIDI song', [Name]);
      FreeAndNil(R);
      Continue;
    end;
    FRenderer := R;
    FRendering := Name;
    FRenderTime := 0;
  end;
end;

procedure TDoomMusic.FinishRender;
var
  Wav: TMemoryStream;
  R: TSongRenderer;
  Name: String;
  Offset, Len: Single;
begin
  R := FRenderer as TSongRenderer;
  Name := FRendering;
  if FIntroWanted = Name then
    FIntroWanted := '';
  Wav := R.MakeWav;
  WritelnLog('Music', 'Rendered %s with %s: %.1f s of audio in %d ms (in slices), peak %.2f', [
    Name, R.SynthName, R.Seconds, Round(FRenderTime * 1000), R.SongPeak * R.OutputGain]);
  FreeAndNil(FRenderer);
  FRendering := '';
  FReady.AddOrSetValue(Name, Wav);
  { Debug aid: dump the rendered song to a directory. }
  if GetEnvironmentVariable('CASTLE_DOOM_DUMP_MUSIC') <> '' then
  begin
    Wav.SaveToFile(InclPathDelim(GetEnvironmentVariable('CASTLE_DOOM_DUMP_MUSIC')) + Name + '.wav');
    Wav.Position := 0;
  end;
  if FEnabled and (FCurrent = Name) then
  begin
    { Take over from the quick-start part at the same point of the song. }
    if FIntroOf = Name then
      Offset := TimerSeconds(Timer, FIntroStart)
    else
      Offset := 0;
    Len := Wav.Size / (SampleRate * 2);
    if Len > 1 then
      Offset := Offset - Trunc(Offset / Len) * Len
    else
      Offset := 0;
    StartPlaying(Name, Offset);
    if FIntroOf = Name then
      WritelnLog('Music', 'Switched %s to the full song at %.2f s', [Name, Offset]);
  end;
  if FIntroOf = Name then
  begin
    FIntroOf := '';
    FReady.Remove(Name + '_INTRO');
  end;
end;

procedure TDoomMusic.Update;
var
  Start: TTimerResult;
  Spent, Budget: Double;
begin
  StartNextRender;
  if FRenderer = nil then Exit;
  { Nothing plays while a song's first seconds are awaited: spend more of
    the frame on them (still no stall: a few frames of silence instead of
    the 100-300 ms the synchronous intro took, more on the web). }
  if FIntroWanted <> '' then
    Budget := Max(RenderBudget, 0.04)
  else
    Budget := RenderBudget;
  Start := Timer;
  repeat
    if (FRenderer as TSongRenderer).Step(2048) then
    begin
      FRenderTime := FRenderTime + TimerSeconds(Timer, Start);
      FinishRender;
      Exit;
    end;
    Spent := TimerSeconds(Timer, Start);
  until Spent >= Budget;
  FRenderTime := FRenderTime + Spent;
  TryStartIntro;
end;

procedure TDoomMusic.PlaySound(const Sound: TCastleSound; const Loop: Boolean; const Offset: Single);
begin
  StopSound;
  FPlaying := TCastlePlayingSound.Create(nil);
  FPlaying.Sound := Sound;
  FPlaying.Loop := Loop;
  FPlaying.Volume := FVolume;
  FPlaying.Priority := 1; { sound effects must not take the music's source }
  FPlaying.InitialOffset := Offset;
  SoundEngine.Play(FPlaying);
end;

procedure TDoomMusic.StopSound;
begin
  if FPlaying <> nil then
  begin
    FPlaying.Stop;
    FreeAndNil(FPlaying);
  end;
  FreeAndNil(FIntroSound);
end;

procedure TDoomMusic.StartPlaying(const LumpName: String; const Offset: Single);
var
  S: TCastleSound;
begin
  if not FSounds.TryGetValue(LumpName, S) then
  begin
    S := TCastleSound.Create(nil);
    S.Url := 'doommus:/' + LumpName + '.wav';
    FSounds.Add(LumpName, S);
  end;
  PlaySound(S, true, Offset);
end;

{ Play the first IntroSeconds of the song as soon as Update has rendered
  them (a few frames), while it renders the rest. Rendering them here at
  once was the last stall of a level start (100-300 ms natively, more on
  the web). }
procedure TDoomMusic.StartIntro(const LumpName: String);
begin
  StartNextRender;
  if (FRenderer = nil) or (FRendering <> LumpName) then Exit;
  FIntroWanted := LumpName;
  FIntroWantedSince := Timer;
  TryStartIntro;
end;

procedure TDoomMusic.TryStartIntro;
const
  IntroSeconds = 8;
var
  R: TSongRenderer;
begin
  if (FIntroWanted = '') or (FRenderer = nil) or (FRendering <> FIntroWanted) then Exit;
  R := FRenderer as TSongRenderer;
  if R.Rendered < IntroSeconds * SampleRate then Exit;
  FReady.AddOrSetValue(FIntroWanted + '_INTRO', R.MakeWav(R.Rendered));
  StopSound;
  FIntroSound := TCastleSound.Create(nil);
  FIntroSound.Url := 'doommus:/' + FIntroWanted + '_INTRO.wav';
  PlaySound(FIntroSound, false, 0);
  FIntroOf := FIntroWanted;
  FIntroStart := Timer;
  WritelnLog('Music', 'Playing the first %.1f s of %s while the rest renders (ready after %d ms)',
    [R.Rendered / SampleRate, FIntroWanted, Round(TimerSeconds(Timer, FIntroWantedSince) * 1000)]);
  FIntroWanted := '';
end;

procedure TDoomMusic.Play(const LumpName: String);
var
  U: String;
begin
  U := UpperCase(LumpName);
  if U = '' then
  begin
    Stop;
    Exit;
  end;
  if FCurrent = U then Exit;
  FCurrent := U;
  if not FEnabled then Exit;
  if FWad.FindLump(U) < 0 then
  begin
    WritelnWarning('Music', 'Missing music lump %s', [U]);
    StopSound;
    Exit;
  end;
  ReleaseUnneeded;
  if FReady.ContainsKey(U) then
  begin
    StartPlaying(U, 0);
    WritelnLog('Music', 'Playing %s, rendered before', [U]);
  end else
  begin
    { The first seconds now, the rest a slice per frame (Update); then the
      intermission track, the next one needed. }
    StopSound;
    if FRendering <> U then
    begin
      if FRenderer <> nil then
      begin
        { Another song (a prefetch) was in progress: it waits. }
        FQueue.Insert(0, FRendering);
        FreeAndNil(FRenderer);
        FRendering := '';
      end;
      Prepare(U, true);
    end;
    StartIntro(U);
    Prepare(IntermissionLump, false);
  end;
end;

procedure TDoomMusic.Prefetch(const LumpName: String);
begin
  FPrefetch := UpperCase(LumpName);
  Prepare(FPrefetch, false);
  ReleaseUnneeded;
end;

procedure TDoomMusic.ReleaseUnneeded;
var
  Names: TStringList;
  Name: String;

  function Needed(const N: String): Boolean;
  begin
    Result := (N = FCurrent) or (N = FPrefetch) or (N = IntermissionLump) or
      ((FIntroOf <> '') and (N = FIntroOf + '_INTRO'));
  end;

begin
  Names := TStringList.Create;
  try
    for Name in FReady.Keys do
      if not Needed(Name) then
        Names.Add(Name);
    for Name in Names do
    begin
      FReady.Remove(Name);
      FSounds.Remove(Name);
      WritelnLog('Music', 'Released %s', [Name]);
    end;
  finally
    FreeAndNil(Names);
  end;
end;

procedure TDoomMusic.Stop;
begin
  FIntroWanted := '';
  StopSound;
  FIntroOf := '';
  FCurrent := '';
end;

procedure TDoomMusic.SetEnabled(const Value: Boolean);
var
  Was: String;
begin
  if FEnabled = Value then Exit;
  FEnabled := Value;
  Was := FCurrent;
  if not FEnabled then
    Stop
  else if Was <> '' then
  begin
    FCurrent := '';
    Play(Was);
  end;
  FCurrent := Was;
end;

procedure TDoomMusic.SetVolume(const Value: Single);
begin
  FVolume := Value;
  if FPlaying <> nil then FPlaying.Volume := FVolume;
end;

function TDoomMusic.LumpForMap(const MapName: String): String;
const
  Doom2Tracks: array [1..32] of String = (
    'D_RUNNIN', 'D_STALKS', 'D_COUNTD', 'D_BETWEE', 'D_DOOM', 'D_THE_DA', 'D_SHAWN', 'D_DDTBLU',
    'D_IN_CIT', 'D_DEAD', 'D_STLKS2', 'D_THEDA2', 'D_DOOM2', 'D_DDTBL2', 'D_RUNNI2', 'D_DEAD2',
    'D_STLKS3', 'D_ROMERO', 'D_SHAWN2', 'D_MESSAG', 'D_COUNT2', 'D_DDTBL3', 'D_AMPIE', 'D_THEDA3',
    'D_ADRIAN', 'D_MESSG2', 'D_ROMER2', 'D_TENSE', 'D_SHAWN3', 'D_OPENIN', 'D_EVIL', 'D_ULTIMA');
var
  N: Integer;
begin
  if FWad.IsDoom2 then
  begin
    N := StrToIntDef(Copy(MapName, 4, 2), 1);
    if (N >= 1) and (N <= 32) then Result := Doom2Tracks[N] else Result := 'D_RUNNIN';
  end else
    Result := 'D_' + UpperCase(MapName);
  if FWad.FindLump(Result) < 0 then
  begin
    if FWad.IsDoom2 then Result := 'D_RUNNIN' else Result := 'D_E1M1';
  end;
end;

function TDoomMusic.TitleLump: String;
begin
  if FWad.IsDoom2 then Result := 'D_DM2TTL' else Result := 'D_INTRO';
end;

function TDoomMusic.IntermissionLump: String;
begin
  if FWad.IsDoom2 then Result := 'D_DM2INT' else Result := 'D_INTER';
end;

initialization
  InitTables;
end.
