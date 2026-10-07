{ Doom music: MUS and MIDI lumps rendered with a small OPL2-style FM
  synthesizer driven by the WAD's GENMIDI instrument bank (the same
  instrument definitions the original game used with AdLib / Sound Blaster
  cards). The song is rendered once to a 16-bit WAV in memory, served through
  the custom "doommus:" URL protocol and looped by the engine's sound system.

  The FM model is an approximation of the Yamaha YM3812: two operators per
  voice (modulator -> carrier, or additive), 4 waveforms, ADSR envelopes with
  rate scaling, key-scale level, feedback, vibrato and tremolo. }
unit DoomMusic;

interface

uses SysUtils, Classes, Generics.Collections, Generics.Defaults,
  CastleSoundEngine,
  DoomWad;

type
  TDoomMusic = class
  strict private
    FWad: TDoomWad;
    FSounds: {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>;
    FCurrent: String;
    FEnabled: Boolean;
    FVolume: Single;
    function ReadMusic(const Url: String; out MimeType: String): TStream;
    procedure SetEnabled(const Value: Boolean);
    procedure SetVolume(const Value: Single);
  public
    constructor Create(const AWad: TDoomWad);
    destructor Destroy; override;
    { Start looping the music lump (like 'D_E1M1'). Empty name stops music. }
    procedure Play(const LumpName: String);
    procedure Stop;
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

implementation

uses Math, CastleDownload, CastleLog, CastleUriUtils, CastleUtils;

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

function CompareTick(constref A, B: TTickEvent): Integer;
begin
  if A.Tick < B.Tick then Exit(-1);
  if A.Tick > B.Tick then Exit(1);
  Result := A.Order - B.Order;
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
  Comparer: {$ifdef FPC}specialize{$endif} IComparer<TTickEvent>;

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

    Comparer := {$ifdef FPC}specialize{$endif} TComparer<TTickEvent>.Construct({$ifdef FPC}@{$endif} CompareTick);
    All.Sort(Comparer);

    Tempo := 500000;
    LastTick := 0;
    Time := 0;
    for I := 0 to All.Count - 1 do
    begin
      Time := Time + (All[I].Tick - LastTick) * (Tempo / 1000000) / Division;
      LastTick := All[I].Tick;
      if All[I].IsTempo then
        Tempo := All[I].Tempo
      else
      begin
        TE := All[I];
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

function RenderDoomSong(const Wad: TDoomWad; const SongData: PByte; const SongSize: Integer): TMemoryStream;
var
  Instruments: array [0..174] of TInstrument;
  Events: TMusicEventList;
  Voices: array [0..MaxVoices - 1] of TVoice;
  Channels: array [0..15] of TChannelState;
  TotalSamples, SampleIndex, NextEvent, I, V, VoiceHigh: Integer;
  EndTime: Double;
  Samples: array of SmallInt;
  Float: array of Single;
  Mix, VibLfo, TremLfo, VibPhase, TremPhase, Peak, Norm: Double;
  Age: Int64;
  E: TMusicEvent;

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

  function FindVoice: Integer;
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

  procedure ReleaseVoice(var Vc: TVoice);
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

  procedure StartVoice(const Channel, Note, Velocity: Integer; const Params: TVoiceParams;
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

  procedure NoteOn(const Channel, Note, Velocity: Integer);
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

  procedure NoteOff(const Channel, Note: Integer);
  var
    J: Integer;
  begin
    for J := 0 to MaxVoices - 1 do
      if Voices[J].Active and (Voices[J].Channel = Channel) and (Voices[J].Note = Note) and
         (Voices[J].Ops[1].State <> esRelease) then
        ReleaseVoice(Voices[J]);
  end;

  procedure UpdateVoiceFreqs(const Channel: Integer);
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

  procedure UpdateVoiceGains(const Channel: Integer);
  var
    J: Integer;
  begin
    for J := 0 to MaxVoices - 1 do
      if Voices[J].Active and (Voices[J].Channel = Channel) then
        Voices[J].Gain := 1.0 * (Channels[Channel].Volume / 127) * (Channels[Channel].Expression / 127);
  end;

  procedure HandleEvent(const Ev: TMusicEvent);
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

  function RenderVoice(var Vc: TVoice; const VibMul, Trem: Double): Double;
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

begin
  Result := nil;
  if not LoadGenMidi(Wad, Instruments) then
  begin
    WritelnWarning('Music', 'No GENMIDI lump, cannot synthesize music');
    Exit;
  end;
  Events := TMusicEventList.Create;
  try
    if not (ParseMus(SongData, SongSize, Events) or ParseMidi(SongData, SongSize, Events)) then
      Exit;
    EndTime := 0;
    for I := 0 to Events.Count - 1 do
      EndTime := Max(EndTime, Events[I].Time);
    EndTime := Min(EndTime + 1.5, MaxSongSeconds);
    TotalSamples := Trunc(EndTime * SampleRate);
    if TotalSamples <= 0 then Exit;
    SetLength(Samples, TotalSamples);
    SetLength(Float, TotalSamples);
    Peak := 0;
    for I := 0 to MaxVoices - 1 do Voices[I].Active := false;
    for I := 0 to 15 do
    begin
      Channels[I].Prog := 0;
      Channels[I].Volume := 100;
      Channels[I].Expression := 127;
      Channels[I].PitchBend := 0;
    end;
    Age := 0;
    VoiceHigh := 0;
    NextEvent := 0;
    VibPhase := 0;
    TremPhase := 0;
    VibLfo := 1;
    TremLfo := 1;
    for SampleIndex := 0 to TotalSamples - 1 do
    begin
      while (NextEvent < Events.Count) and (Events[NextEvent].Time * SampleRate <= SampleIndex) do
      begin
        E := Events[NextEvent];
        HandleEvent(E);
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
    end;
    { Normalize the whole song to -1 dBFS (the OPL had no master limiter,
      but songs were authored for it; this keeps every track at a sane level). }
    if Peak < 0.01 then Peak := 0.01;
    Norm := 0.89 / Peak;
    for SampleIndex := 0 to TotalSamples - 1 do
      Samples[SampleIndex] := Round(Float[SampleIndex] * Norm * 32767);

    Result := TMemoryStream.Create;
    WriteTag(Result, 'RIFF');
    WriteU32(Result, 36 + TotalSamples * 2);
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
    WriteU32(Result, TotalSamples * 2);
    Result.WriteBuffer(Samples[0], TotalSamples * 2);
    Result.Position := 0;
  finally
    FreeAndNil(Events);
  end;
end;

{ TDoomMusic ----------------------------------------------------------------- }

constructor TDoomMusic.Create(const AWad: TDoomWad);
begin
  inherited Create;
  FWad := AWad;
  FEnabled := true;
  FVolume := 0.5;
  FSounds := {$ifdef FPC}specialize{$endif} TObjectDictionary<String, TCastleSound>.Create([doOwnsValues]);
  RegisterUrlProtocol('doommus', {$ifdef FPC}@{$endif} ReadMusic, nil);
end;

destructor TDoomMusic.Destroy;
begin
  Stop;
  FreeAndNil(FSounds);
  UnregisterUrlProtocol('doommus');
  inherited;
end;

function TDoomMusic.ReadMusic(const Url: String; out MimeType: String): TStream;
var
  Name: String;
  Lump: Integer;
  Start: TDateTime;
begin
  Name := UpperCase(ExtractUriName(Url));
  if LowerCase(ExtractFileExt(Name)) = '.wav' then
    Name := Copy(Name, 1, Length(Name) - 4);
  Lump := FWad.FindLump(Name);
  if Lump < 0 then
    raise Exception.CreateFmt('Music lump %s not found', [Name]);
  Start := Now;
  Result := RenderDoomSong(FWad, FWad.LumpPointer(Lump), FWad.LumpSize(Lump));
  if Result = nil then
    raise Exception.CreateFmt('Lump %s is not a MUS/MIDI song', [Name]);
  WritelnLog('Music', 'Rendered %s with the FM synthesizer: %.1f s of audio in %d ms', [
    Name, Result.Size / (SampleRate * 2), Round((Now - Start) * 24 * 3600 * 1000)]);
  { Debug aid: dump the rendered song to a directory. }
  if GetEnvironmentVariable('CASTLE_DOOM_DUMP_MUSIC') <> '' then
  begin
    TMemoryStream(Result).SaveToFile(InclPathDelim(GetEnvironmentVariable('CASTLE_DOOM_DUMP_MUSIC')) + Name + '.wav');
    Result.Position := 0;
  end;
  MimeType := 'audio/x-wav';
end;

procedure TDoomMusic.Play(const LumpName: String);
var
  U: String;
  S: TCastleSound;
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
  if not FSounds.TryGetValue(U, S) then
  begin
    if FWad.FindLump(U) < 0 then
    begin
      WritelnWarning('Music', 'Missing music lump %s', [U]);
      FSounds.Add(U, nil);
      Exit;
    end;
    S := TCastleSound.Create(nil);
    S.Url := 'doommus:/' + U + '.wav';
    FSounds.Add(U, S);
  end;
  if S = nil then Exit;
  SoundEngine.LoopingChannel[0].Volume := FVolume;
  SoundEngine.LoopingChannel[0].Sound := S;
end;

procedure TDoomMusic.Stop;
begin
  if SoundEngine.LoopingChannel[0] <> nil then
    SoundEngine.LoopingChannel[0].Sound := nil;
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
  SoundEngine.LoopingChannel[0].Volume := FVolume;
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
