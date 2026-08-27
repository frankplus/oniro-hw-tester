/*
 * Audio test tab: sine-tone playback (render path) and record-then-playback
 * (capture path) with a live input level meter.
 */
import { audio } from '@kit.AudioKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const DOMAIN = 0x0001;
const TAG = 'HwTesterAudio';

const STREAM_INFO: audio.AudioStreamInfo = {
  samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
  channels: audio.AudioChannel.CHANNEL_2,
  sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
  encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
};

const CAPTURE_STREAM_INFO: audio.AudioStreamInfo = {
  samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_48000,
  channels: audio.AudioChannel.CHANNEL_1,
  sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
  encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
};

const RECORD_SECONDS = 5;

@Component
export struct AudioTab {
  @State toneStatus: string = 'idle';
  @State toneHz: number = 440;
  @State captureStatus: string = 'idle';
  @State level: number = 0; // 0..1 RMS of the last capture chunk
  @State recordedMs: number = 0;
  @State hasRecording: boolean = false;
  @State takeStats: string = '';

  // Per-take level statistics. `hp` mirrors a ~300 Hz first-order high-pass so
  // the reading separates real in-band signal from the DC/handling/mains rumble
  // an analog mic front-end always carries.
  private peakAbs: number = 0;
  private sumSq: number = 0;
  private sumSqHp: number = 0;
  private sampleCount: number = 0;
  private hpPrevIn: number = 0;
  private hpPrevOut: number = 0;

  private toneRenderer: audio.AudioRenderer | undefined = undefined;
  private tonePhase: number = 0;
  private capturer: audio.AudioCapturer | undefined = undefined;
  private recordChunks: Uint8Array[] = [];
  private recordedBytes: number = 0;
  private playbackRenderer: audio.AudioRenderer | undefined = undefined;
  private playbackData: Uint8Array | undefined = undefined;
  private playbackOffset: number = 0;

  aboutToDisappear(): void {
    this.stopTone();
    this.stopCapture();
    this.stopPlayback();
  }

  // ---- tone (render path) ----

  async startTone(): Promise<void> {
    if (this.toneRenderer !== undefined) {
      return;
    }
    try {
      let rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      let renderer = await audio.createAudioRenderer({
        streamInfo: STREAM_INFO,
        rendererInfo: rendererInfo
      });
      renderer.on('writeData', (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
        this.fillTone(buffer);
        return audio.AudioDataCallbackResult.VALID;
      });
      await renderer.start();
      this.toneRenderer = renderer;
      this.toneStatus = `playing ${this.toneHz} Hz`;
      hilog.info(DOMAIN, TAG, 'tone started');
    } catch (e) {
      let err = e as Error;
      this.toneStatus = `ERROR: ${err.message}`;
      hilog.error(DOMAIN, TAG, 'startTone failed: %{public}s', err.message);
    }
  }

  fillTone(buffer: ArrayBuffer): void {
    let samples = new Int16Array(buffer);
    let frames = samples.length / 2; // stereo
    let step = 2 * Math.PI * this.toneHz / 48000;
    for (let i = 0; i < frames; i++) {
      let v = Math.round(Math.sin(this.tonePhase) * 12000);
      samples[2 * i] = v;
      samples[2 * i + 1] = v;
      this.tonePhase += step;
      if (this.tonePhase > 2 * Math.PI) {
        this.tonePhase -= 2 * Math.PI;
      }
    }
  }

  async stopTone(): Promise<void> {
    let renderer = this.toneRenderer;
    this.toneRenderer = undefined;
    if (renderer !== undefined) {
      try {
        await renderer.stop();
        await renderer.release();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'stopTone: %{public}s', (e as Error).message);
      }
      this.toneStatus = 'idle';
    }
  }

  // ---- capture path ----

  async startCapture(): Promise<void> {
    if (this.capturer !== undefined) {
      return;
    }
    this.stopPlayback();
    this.recordChunks = [];
    this.recordedBytes = 0;
    this.hasRecording = false;
    this.recordedMs = 0;
    this.takeStats = '';
    this.peakAbs = 0;
    this.sumSq = 0;
    this.sumSqHp = 0;
    this.sampleCount = 0;
    this.hpPrevIn = 0;
    this.hpPrevOut = 0;
    try {
      let capturerInfo: audio.AudioCapturerInfo = {
        source: audio.SourceType.SOURCE_TYPE_MIC,
        capturerFlags: 0
      };
      let capturer = await audio.createAudioCapturer({
        streamInfo: CAPTURE_STREAM_INFO,
        capturerInfo: capturerInfo
      });
      capturer.on('readData', (buffer: ArrayBuffer) => {
        this.onCaptureData(buffer);
      });
      await capturer.start();
      this.capturer = capturer;
      this.captureStatus = 'recording…';
      hilog.info(DOMAIN, TAG, 'capture started');
      setTimeout(() => {
        this.finishCapture();
      }, RECORD_SECONDS * 1000);
    } catch (e) {
      let err = e as Error;
      this.captureStatus = `ERROR: ${err.message}`;
      hilog.error(DOMAIN, TAG, 'startCapture failed: %{public}s', err.message);
    }
  }

  onCaptureData(buffer: ArrayBuffer): void {
    this.recordChunks.push(new Uint8Array(buffer.slice(0)));
    this.recordedBytes += buffer.byteLength;
    // level meter: RMS of this chunk, plus running per-take statistics
    let samples = new Int16Array(buffer);
    let sum = 0;
    const a = 0.9615; // ~300 Hz first-order high-pass at 48 kHz
    let prevIn = this.hpPrevIn;
    let prevOut = this.hpPrevOut;
    for (let i = 0; i < samples.length; i++) {
      let x = samples[i];
      sum += x * x;
      let ax = x < 0 ? -x : x;
      if (ax > this.peakAbs) {
        this.peakAbs = ax;
      }
      let y = a * (prevOut + x - prevIn);
      prevIn = x;
      prevOut = y;
      this.sumSqHp += y * y;
    }
    this.hpPrevIn = prevIn;
    this.hpPrevOut = prevOut;
    this.sumSq += sum;
    this.sampleCount += samples.length;
    let rms = Math.sqrt(sum / Math.max(1, samples.length)) / 32768;
    this.level = rms;
    this.recordedMs = Math.round(this.recordedBytes / (48000 * 2) * 1000);
  }

  private dbfs(sumSq: number, n: number): string {
    if (n <= 0) {
      return '-inf';
    }
    let v = Math.sqrt(sumSq / n) / 32768;
    if (v <= 0) {
      return '-inf';
    }
    return (20 * Math.log10(v)).toFixed(1);
  }

  async finishCapture(): Promise<void> {
    await this.stopCapture();
    if (this.recordedBytes > 0) {
      let all = new Uint8Array(this.recordedBytes);
      let off = 0;
      for (let i = 0; i < this.recordChunks.length; i++) {
        all.set(this.recordChunks[i], off);
        off += this.recordChunks[i].length;
      }
      this.playbackData = all;
      this.hasRecording = true;
      this.captureStatus = `recorded ${this.recordedMs} ms (${this.recordedBytes} bytes)`;
      let peakDb = this.peakAbs > 0 ? (20 * Math.log10(this.peakAbs / 32768)).toFixed(1) : '-inf';
      this.takeStats = `peak ${peakDb} dBFS · RMS ${this.dbfs(this.sumSq, this.sampleCount)} dBFS`
        + ` · RMS>300Hz ${this.dbfs(this.sumSqHp, this.sampleCount)} dBFS`;
      this.saveRecording(all);
    } else {
      this.captureStatus = 'recorded nothing (0 bytes) — capture path broken?';
    }
    this.recordChunks = [];
  }

  async stopCapture(): Promise<void> {
    let capturer = this.capturer;
    this.capturer = undefined;
    this.level = 0;
    if (capturer !== undefined) {
      try {
        await capturer.stop();
        await capturer.release();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'stopCapture: %{public}s', (e as Error).message);
      }
    }
  }

  saveRecording(data: Uint8Array): void {
    // Keep the last take on disk so it can be pulled for analysis.
    try {
      let path = `${getContext(this).filesDir}/rec.pcm`;
      let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, data.buffer);
      fs.closeSync(file);
      hilog.info(DOMAIN, TAG, 'saved recording to %{public}s', path);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'saveRecording failed: %{public}s', (e as Error).message);
    }
  }

  // ---- playback of the recording (mono) ----

  async playRecording(): Promise<void> {
    if (this.playbackRenderer !== undefined || this.playbackData === undefined) {
      return;
    }
    this.playbackOffset = 0;
    try {
      let rendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_MUSIC,
        rendererFlags: 0
      };
      let renderer = await audio.createAudioRenderer({
        streamInfo: CAPTURE_STREAM_INFO,
        rendererInfo: rendererInfo
      });
      renderer.on('writeData', (buffer: ArrayBuffer): audio.AudioDataCallbackResult => {
        return this.fillPlayback(buffer);
      });
      await renderer.start();
      this.playbackRenderer = renderer;
      this.captureStatus = 'playing recording…';
    } catch (e) {
      let err = e as Error;
      this.captureStatus = `ERROR: ${err.message}`;
      hilog.error(DOMAIN, TAG, 'playRecording failed: %{public}s', err.message);
    }
  }

  fillPlayback(buffer: ArrayBuffer): audio.AudioDataCallbackResult {
    let data = this.playbackData;
    if (data === undefined || this.playbackOffset >= data.length) {
      // done — stop from a timer so we don't release inside the callback
      setTimeout(() => {
        this.stopPlayback();
        this.captureStatus = 'playback done';
      }, 0);
      new Uint8Array(buffer).fill(0);
      return audio.AudioDataCallbackResult.VALID;
    }
    let out = new Uint8Array(buffer);
    let n = Math.min(out.length, data.length - this.playbackOffset);
    out.set(data.subarray(this.playbackOffset, this.playbackOffset + n));
    if (n < out.length) {
      out.fill(0, n);
    }
    this.playbackOffset += n;
    return audio.AudioDataCallbackResult.VALID;
  }

  stopPlayback(): void {
    let renderer = this.playbackRenderer;
    this.playbackRenderer = undefined;
    if (renderer !== undefined) {
      let r: audio.AudioRenderer = renderer;
      r.stop().then(() => r.release()).catch((e: Error) => {
        hilog.error(DOMAIN, TAG, 'stopPlayback: %{public}s', e.message);
      });
    }
  }

  build() {
    Column({ space: 12 }) {
      Text('Render (speaker)').fontSize(18).fontWeight(FontWeight.Bold)
        .alignSelf(ItemAlign.Start)
      Row({ space: 8 }) {
        Button('440 Hz').onClick(() => {
          this.toneHz = 440;
          this.stopTone().then(() => this.startTone());
        })
        Button('1 kHz').onClick(() => {
          this.toneHz = 1000;
          this.stopTone().then(() => this.startTone());
        })
        Button('Stop').backgroundColor(Color.Gray).onClick(() => {
          this.stopTone();
        })
      }
      Text(`Tone: ${this.toneStatus}`).fontSize(14)

      Divider()

      Text('Capture (microphone)').fontSize(18).fontWeight(FontWeight.Bold)
        .alignSelf(ItemAlign.Start)
      Row({ space: 8 }) {
        Button(`Record ${RECORD_SECONDS} s`).onClick(() => {
          this.startCapture();
        })
        Button('Play recording')
          .enabled(this.hasRecording)
          .onClick(() => {
            this.playRecording();
          })
      }
      Text(`Capture: ${this.captureStatus}`).fontSize(14)
      Text(`Recorded: ${this.recordedMs} ms`).fontSize(14)
      if (this.takeStats !== '') {
        Text(this.takeStats).fontSize(13).fontColor(Color.Blue)
      }

      // input level meter
      Row() {
        Row()
          .width(`${Math.min(100, Math.round(this.level * 300))}%`)
          .height(16)
          .backgroundColor(this.level > 0.02 ? Color.Green : Color.Orange)
      }
      .width('100%')
      .height(16)
      .backgroundColor('#22000000')
      .borderRadius(4)

      Text('Speak while recording — the bar should move.').fontSize(12).fontColor(Color.Gray)
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }
}
