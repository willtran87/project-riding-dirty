// Fast offline mirror of GameplayAudio's QUARRY/STANDARD render contract.
// This avoids executing hundreds of thousands of sample-level GDScript calls
// during startup while preserving the authored 143 BPM arrangement verbatim.
import fs from "node:fs";
import path from "node:path";

const MIX_RATE = 22050;
const MUSIC_BEATS = 16;
const TAU = Math.PI * 2;
const outputDir = path.resolve("assets/generated/audio");
const contract = {
  district: "QUARRY",
  bpm: 143,
  transpose: 0,
  rhythmSeed: 19,
  driveDensity: 1,
  tensionBias: 0.78,
  bass: [38,-1,38,45,38,-1,41,38,36,-1,43,36,36,43,41,-1,34,-1,41,34,34,41,38,-1,33,-1,40,33,36,40,45,-1],
  lead: [-1,69,74,77,76,74,69,72,67,72,76,79,76,74,72,67,65,70,74,77,74,72,70,65,64,69,73,76,73,71,69,-1],
  roots: [50,48,46,45],
  qualities: ["MINOR","MAJOR","MAJOR","MAJOR"],
};

const posmod = (value, divisor) => ((value % divisor) + divisor) % divisor;
const fmod = (value, divisor) => value % divisor;
const clamp = (value, low, high) => Math.min(Math.max(value, low), high);
const midiToHz = (note) => 440 * Math.pow(2, (note - 69) / 12);
const pulse = (phase, duty) => fmod(phase, 1) < duty ? 1 : -1;
const triangle = (phase) => 1 - 4 * Math.abs(fmod(phase, 1) - 0.5);
const chipNoise = (seed) => {
  const value = posmod(seed * 1103515245 + 12345, 2147483647);
  return (value & 65535) / 32767.5 - 1;
};

function renderBase(beat, secondsPerBeat, sampleIndex) {
  const halfStep = posmod(Math.floor(beat * 2), contract.bass.length);
  const halfPhase = fmod(beat * 2, 1);
  const bassNote = contract.bass[halfStep];
  let bass = 0;
  if (bassNote >= 0) {
    const bassHz = midiToHz(bassNote + contract.transpose);
    const bassTime = halfPhase * secondsPerBeat * 0.5;
    const envelope = Math.min(halfPhase * 18, 1) * Math.pow(1 - halfPhase, 0.32);
    const fundamental = Math.sin(bassTime * bassHz * TAU);
    bass = (fundamental * 0.56 + Math.sin(bassTime * bassHz * 0.5 * TAU) * 0.30 + Math.tanh(fundamental * 1.8) * 0.14) * envelope * 0.34;
  }
  const eighthIndex = posmod(Math.floor(beat * 2), 8);
  const eighthPhase = fmod(beat * 2, 1);
  let kick = 0;
  if ([0,3,4,7].includes(eighthIndex)) {
    const kickTime = eighthPhase * secondsPerBeat * 0.5;
    const kickPhase = 42 * kickTime + 5 * (1 - Math.exp(-kickTime * 18));
    kick = Math.sin(kickPhase * TAU) * Math.exp(-eighthPhase * 7) * 0.50;
  }
  const beatIndex = posmod(Math.floor(beat), 4);
  const beatPhase = fmod(beat, 1);
  let snare = 0;
  if (beatIndex === 1 || beatIndex === 3) {
    snare = (chipNoise(sampleIndex + contract.rhythmSeed) * 0.52 + Math.sin(beatPhase * secondsPerBeat * 142 * TAU) * 0.48) * Math.exp(-beatPhase * 13) * 0.17;
  }
  const quarterPhase = fmod(beat * 4, 1);
  const hat = chipNoise(Math.trunc(sampleIndex / 3) + contract.rhythmSeed) * Math.exp(-quarterPhase * 24) * (eighthIndex % 2 === 0 ? 0.028 : 0.018);
  return bass + kick + snare + hat;
}

function renderDrive(beat, secondsPerBeat) {
  const halfStep = posmod(Math.floor(beat * 2), contract.lead.length);
  const halfPhase = fmod(beat * 2, 1);
  const leadNote = contract.lead[halfStep];
  let lead = 0;
  if (leadNote >= 0) {
    const leadHz = midiToHz(leadNote - 12 + contract.transpose);
    const leadTime = halfPhase * secondsPerBeat * 0.5;
    const envelope = Math.min(halfPhase * 24, 1) * Math.pow(1 - halfPhase, 0.6);
    const phase = leadTime * leadHz + Math.sin(leadTime * 6.1 * TAU) * 0.0035;
    lead = (Math.sin(phase * TAU) * 0.62 + triangle(phase) * 0.28 + pulse(phase, 0.5) * 0.10) * envelope * 0.23;
  }
  const step = posmod(Math.floor(beat * 4), 16);
  const phase = fmod(beat * 4, 1);
  const bar = posmod(Math.floor(beat / 4), contract.roots.length);
  const third = contract.qualities[bar] === "MINOR" ? 3 : 4;
  const offsets = [0, third, 7, 12];
  const note = contract.roots[bar] + offsets[posmod(step + bar, offsets.length)] + contract.transpose;
  const localTime = phase * secondsPerBeat * 0.25;
  return lead + (triangle(localTime * midiToHz(note)) * 0.8 + Math.sin(localTime * midiToHz(note) * TAU) * 0.2) * Math.pow(1 - phase, 1.5) * 0.028 * contract.driveDensity;
}

function renderTension(beat, secondsPerBeat, sampleIndex) {
  const bar = posmod(Math.floor(beat / 4), contract.roots.length);
  const step = posmod(Math.floor(beat * 4), 16);
  const phase = fmod(beat * 4, 1);
  const offsets = [12,19,15,22];
  const note = contract.roots[bar] + offsets[posmod(step + contract.rhythmSeed, offsets.length)] + contract.transpose;
  const localTime = phase * secondsPerBeat * 0.25;
  const wave = pulse(localTime * midiToHz(note), 0.34) * Math.pow(1 - phase, 1.1) * 0.052;
  const noise = chipNoise(sampleIndex + contract.rhythmSeed * 13) * Math.exp(-phase * 18) * 0.018;
  return (wave + noise) * contract.tensionBias;
}

function renderResults(beat, secondsPerBeat) {
  const bar = posmod(Math.floor(beat / 4), contract.roots.length);
  const barPhase = fmod(beat / 4, 1);
  const root = contract.roots[bar] + contract.transpose;
  const third = contract.qualities[bar] === "MINOR" ? 3 : 4;
  const barTime = barPhase * secondsPerBeat * 4;
  const envelope = Math.min(barPhase * 12, 1) * Math.pow(1 - barPhase, 0.42);
  const pad = (Math.sin(barTime * midiToHz(root) * TAU) * 0.48 + Math.sin(barTime * midiToHz(root + third) * TAU) * 0.28 + Math.sin(barTime * midiToHz(root + 7) * TAU) * 0.24) * envelope * 0.12;
  const halfPhase = fmod(beat * 0.5, 1);
  const resolveNote = root + (bar === contract.roots.length - 1 ? 12 : 7);
  const resolve = Math.sin(halfPhase * secondsPerBeat * 2 * midiToHz(resolveNote) * TAU) * Math.min(halfPhase * 10, 1) * Math.pow(1 - halfPhase, 1.2) * 0.045;
  return pad + resolve;
}

function writeWav(stem, renderer) {
  const secondsPerBeat = 60 / contract.bpm;
  const sampleCount = Math.trunc(MUSIC_BEATS * secondsPerBeat * MIX_RATE);
  const buffer = Buffer.alloc(44 + sampleCount * 2);
  buffer.write("RIFF", 0); buffer.writeUInt32LE(36 + sampleCount * 2, 4);
  buffer.write("WAVEfmt ", 8); buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20); buffer.writeUInt16LE(1, 22);
  buffer.writeUInt32LE(MIX_RATE, 24); buffer.writeUInt32LE(MIX_RATE * 2, 28);
  buffer.writeUInt16LE(2, 32); buffer.writeUInt16LE(16, 34);
  buffer.write("data", 36); buffer.writeUInt32LE(sampleCount * 2, 40);
  for (let i = 0; i < sampleCount; i++) {
    const time = i / MIX_RATE;
    const beat = time / secondsPerBeat;
    const sample = clamp(Math.trunc(Math.tanh(renderer(beat, secondsPerBeat, i) * 1.18) * 32767), -32768, 32767);
    buffer.writeInt16LE(sample, 44 + i * 2);
  }
  fs.writeFileSync(path.join(outputDir, `music_quarry_standard_${stem.toLowerCase()}.wav`), buffer);
}

fs.mkdirSync(outputDir, { recursive: true });
writeWav("BASE", renderBase);
writeWav("DRIVE", renderDrive);
writeWav("TENSION", renderTension);
writeWav("RESULTS", renderResults);
console.log("AUDIO BAKE PASS: music_stems=4 bpm=143");
