# Oniro HW Tester

A small ArkTS app for exercising device hardware from OpenHarmony / Oniro, one
tab per subsystem. It was written to sanity-check a `hybris_generic` HAL port —
audio, sensors, and vibrator — from on-device rather than by reading logs, so
each tab surfaces raw values and errors instead of a pass/fail verdict.

Developed and tested on a **Volla Plinius** running Oniro (API 23).

## What it tests

### Audio

Render path and capture path, both 48 kHz `S16LE`.

- **Render** — a continuous sine tone at 440 Hz or 1 kHz, stereo, synthesised
  in the `writeData` callback at roughly −8.7 dBFS.
- **Capture** — a 5-second mono take from `SOURCE_TYPE_MIC`, with a live RMS
  level meter so you can see the input responding while you speak.
- After each take it reports **peak dBFS**, **RMS dBFS**, and **RMS above
  300 Hz**. The high-passed figure matters: an analog mic front-end always
  carries some DC, handling, and mains rumble, and comparing it against the
  full-band RMS tells you whether you captured real in-band signal or just
  low-frequency noise.
- The take is kept at `files/rec.pcm` and can be replayed in-app or pulled off
  the device (see below).

A capture that returns 0 bytes is called out explicitly — that is the usual
signature of a broken capture path.

### Sensors

Subscribes at 5 Hz and shows live readings for:

| Sensor        | Units   |
| ------------- | ------- |
| Accelerometer | m/s²    |
| Gyroscope     | rad/s   |
| Magnetometer  | µT      |
| Ambient light | lux     |
| Proximity     | near/far |

A running callback counter confirms the event stream is actually alive (as
opposed to values that merely look plausible but are frozen), and the tab
enumerates everything `sensor.getSensorListSync()` reports with its id, name,
and vendor.

### Vibrator

- Fixed-duration buzzes: 100 ms, 500 ms, 2 s, plus stop.
- Probes eight `haptic.*` preset effects with `vibrator.isSupportEffect()`,
  marks each ✓ or ✗, and plays them individually — which is how you find out
  what the vibrator VDI actually maps versus what it merely accepts.

## Requirements

- OpenHarmony SDK **API 23** (SDK 6.1) and the OpenHarmony command-line tools
- [`oniro-app`](https://www.npmjs.com/package/@oniroproject/oniro-app) —
  `npm i -g @oniroproject/oniro-app`
- A device in developer mode, connected and visible to `oniro-app devices`

`oniro-app` can provision the toolchain for you:

```sh
oniro-app sdk install 6.1
oniro-app cmdtools install
```

## Build and run

```sh
oniro-app build          # runs ohpm install when oh_modules/ is missing
oniro-app app apply      # verified install onto the connected device
oniro-app app launch
```

If more than one device is attached, set `ONIRO_DEVICE_SERIAL` or pass
`--device <serial>`.

The app requests the microphone permission on first launch; the Sensors and
Vibrator tabs need no runtime prompt.

## Pulling a recording

The most recent capture stays on the device as raw PCM:

```sh
oniro-app file recv \
  /data/app/el2/100/base/com.oniro.hwtester/haps/entry/files/rec.pcm ./rec.pcm
```

It is headerless — 48 kHz, mono, signed 16-bit little-endian:

```sh
ffplay -f s16le -ar 48000 -ac 1 rec.pcm
```

## Signing

`signatures/` carries the stock OpenHarmony test signing material, wired up
through `signingConfigs` in `build-profile.json5`, so a fresh clone builds and
deploys with no extra setup. This is the public developer certificate that
ships with the SDK, not a production key — replace it before shipping anything
real. To regenerate the material locally, use `oniro-app sign`.

## Layout

```
AppScope/                     app-level config, name, and launcher icon
entry/src/main/
  ets/pages/Index.ets         tab host
  ets/tabs/AudioTab.ets       render + capture
  ets/tabs/SensorsTab.ets     five sensors, live
  ets/tabs/VibratorTab.ets    durations + preset effects
  module.json5                abilities and permissions
  resources/                  strings, colors, layered icon
signatures/                   OpenHarmony test signing material
```

Bundle name: `com.oniro.hwtester`

## License

Apache-2.0. See [LICENSE](LICENSE).
