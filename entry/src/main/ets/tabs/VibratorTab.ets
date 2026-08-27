/*
 * Vibrator test tab: fixed-duration buzzes plus the preset effects the
 * hybris_generic vibrator VDI maps (haptic.* names), with support probing.
 */
import { vibrator } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0003;
const TAG = 'HwTesterVibrator';

const EFFECTS: string[] = [
  'haptic.clock.timer',
  'haptic.long_press.light',
  'haptic.long_press.medium',
  'haptic.long_press.heavy',
  'haptic.fail',
  'haptic.charging',
  'haptic.slide.light',
  'haptic.threshold',
];

@Component
export struct VibratorTab {
  @State status: string = 'idle';
  @State effectSupport: string[] = [];

  aboutToAppear(): void {
    this.probeEffects();
  }

  async probeEffects(): Promise<void> {
    let out: string[] = [];
    for (let i = 0; i < EFFECTS.length; i++) {
      try {
        let ok = await vibrator.isSupportEffect(EFFECTS[i]);
        out.push(`${ok ? '✓' : '✗'} ${EFFECTS[i]}`);
      } catch (e) {
        out.push(`? ${EFFECTS[i]} (${(e as Error).message})`);
      }
    }
    this.effectSupport = out;
  }

  buzz(ms: number): void {
    vibrator.startVibration(
      { type: 'time', duration: ms },
      { id: 0, usage: 'notification' }
    ).then(() => {
      this.status = `buzzing ${ms} ms`;
      hilog.info(DOMAIN, TAG, 'buzz %{public}d ms ok', ms);
    }).catch((e: Error) => {
      this.status = `ERROR: ${e.message}`;
      hilog.error(DOMAIN, TAG, 'buzz failed: %{public}s', e.message);
    });
  }

  playEffect(effectId: string): void {
    vibrator.startVibration(
      { type: 'preset', effectId: effectId, count: 1 },
      { id: 0, usage: 'notification' }
    ).then(() => {
      this.status = `effect: ${effectId}`;
    }).catch((e: Error) => {
      this.status = `ERROR (${effectId}): ${e.message}`;
      hilog.error(DOMAIN, TAG, 'effect %{public}s failed: %{public}s', effectId, e.message);
    });
  }

  stop(): void {
    vibrator.stopVibration().then(() => {
      this.status = 'stopped';
    }).catch((e: Error) => {
      this.status = `ERROR: ${e.message}`;
    });
  }

  build() {
    Column({ space: 10 }) {
      Text('Duration').fontSize(18).fontWeight(FontWeight.Bold)
      Row({ space: 8 }) {
        Button('100 ms').onClick(() => this.buzz(100))
        Button('500 ms').onClick(() => this.buzz(500))
        Button('2 s').onClick(() => this.buzz(2000))
        Button('Stop').backgroundColor(Color.Gray).onClick(() => this.stop())
      }
      Text(`Status: ${this.status}`).fontSize(14)

      Divider()

      Text('Preset effects').fontSize(18).fontWeight(FontWeight.Bold)
      List({ space: 6 }) {
        ForEach(this.effectSupport, (item: string, idx: number) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(item).fontSize(13).layoutWeight(1)
              Button('Play')
                .height(28)
                .onClick(() => this.playEffect(EFFECTS[idx]))
            }
            .width('100%')
          }
        }, (item: string) => item)
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }
}
