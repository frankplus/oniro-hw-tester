/*
 * Sensors test tab: live readouts for the five physical sensors the
 * hybris_generic sensor VDI exposes (accel, gyro, mag, ambient light,
 * proximity) plus the enumerated sensor list.
 */
import { sensor } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0002;
const TAG = 'HwTesterSensors';
const INTERVAL_NS = 200000000; // 5 Hz

interface SensorRow {
  name: string;
  value: string;
}

@Component
export struct SensorsTab {
  @State running: boolean = false;
  @State accel: string = '—';
  @State gyro: string = '—';
  @State mag: string = '—';
  @State light: string = '—';
  @State prox: string = '—';
  @State sensorList: string[] = [];
  @State error: string = '';
  @State events: number = 0;

  private rawCount: number = 0;

  aboutToAppear(): void {
    this.loadSensorList();
  }

  aboutToDisappear(): void {
    this.stopAll();
  }

  loadSensorList(): void {
    try {
      let list = sensor.getSensorListSync();
      let names: string[] = [];
      for (let i = 0; i < list.length; i++) {
        names.push(`[${list[i].sensorId}] ${list[i].sensorName} (${list[i].vendorName})`);
      }
      this.sensorList = names;
    } catch (e) {
      this.error = `getSensorList: ${(e as Error).message}`;
      hilog.error(DOMAIN, TAG, 'getSensorListSync failed: %{public}s', (e as Error).message);
    }
  }

  startAll(): void {
    if (this.running) {
      return;
    }
    this.error = '';
    let opts: sensor.Options = { interval: INTERVAL_NS };
    try {
      sensor.on(sensor.SensorId.ACCELEROMETER, (d: sensor.AccelerometerResponse) => {
        this.accel = `x=${d.x.toFixed(2)}  y=${d.y.toFixed(2)}  z=${d.z.toFixed(2)} m/s²`;
      }, opts);
    } catch (e) {
      this.accel = `ERROR: ${(e as Error).message}`;
    }
    try {
      sensor.on(sensor.SensorId.GYROSCOPE, (d: sensor.GyroscopeResponse) => {
        this.rawCount++;
        this.events = this.rawCount;
        this.gyro = `x=${d.x.toFixed(3)}  y=${d.y.toFixed(3)}  z=${d.z.toFixed(3)} rad/s`;
      }, opts);
    } catch (e) {
      this.gyro = `ERROR: ${(e as Error).message}`;
    }
    try {
      sensor.on(sensor.SensorId.MAGNETIC_FIELD, (d: sensor.MagneticFieldResponse) => {
        this.mag = `x=${d.x.toFixed(1)}  y=${d.y.toFixed(1)}  z=${d.z.toFixed(1)} µT`;
      }, opts);
    } catch (e) {
      this.mag = `ERROR: ${(e as Error).message}`;
    }
    try {
      sensor.on(sensor.SensorId.AMBIENT_LIGHT, (d: sensor.LightResponse) => {
        this.light = `${d.intensity.toFixed(1)} lux`;
      }, opts);
    } catch (e) {
      this.light = `ERROR: ${(e as Error).message}`;
    }
    try {
      sensor.on(sensor.SensorId.PROXIMITY, (d: sensor.ProximityResponse) => {
        this.prox = d.distance > 0 ? `far (${d.distance})` : `NEAR (${d.distance})`;
      }, opts);
    } catch (e) {
      this.prox = `ERROR: ${(e as Error).message}`;
    }
    this.running = true;
  }

  stopAll(): void {
    if (!this.running) {
      return;
    }
    try {
      sensor.off(sensor.SensorId.ACCELEROMETER);
      sensor.off(sensor.SensorId.GYROSCOPE);
      sensor.off(sensor.SensorId.MAGNETIC_FIELD);
      sensor.off(sensor.SensorId.AMBIENT_LIGHT);
      sensor.off(sensor.SensorId.PROXIMITY);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'sensor.off failed: %{public}s', (e as Error).message);
    }
    this.running = false;
  }

  /*
   * Takes a single object parameter passed by reference ($$). A @Builder whose
   * parameters are passed by value renders once and never updates again when
   * the bound @State changes — which is why every reading sat at '—' while the
   * callbacks were arriving normally.
   */
  @Builder
  sensorRow($$: SensorRow) {
    Column({ space: 2 }) {
      Text($$.name).fontSize(14).fontWeight(FontWeight.Bold)
      Text($$.value).fontSize(14).fontFamily('monospace')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button(this.running ? 'Stop' : 'Start all sensors')
          .backgroundColor(this.running ? Color.Gray : Color.Blue)
          .onClick(() => {
            if (this.running) {
              this.stopAll();
            } else {
              this.startAll();
            }
          })
      }
      if (this.error !== '') {
        Text(this.error).fontSize(12).fontColor(Color.Red)
      }
      this.sensorRow({ name: 'Accelerometer', value: this.accel })
      this.sensorRow({ name: 'Gyroscope', value: this.gyro })
      this.sensorRow({ name: 'Magnetometer', value: this.mag })
      this.sensorRow({ name: 'Ambient light', value: this.light })
      this.sensorRow({ name: 'Proximity', value: this.prox })

      Divider()

      Text(`Callbacks received: ${this.events}`).fontSize(14).fontColor(Color.Blue)
      Text(`Enumerated sensors (${this.sensorList.length})`).fontSize(14).fontWeight(FontWeight.Bold)
      List() {
        ForEach(this.sensorList, (item: string) => {
          ListItem() {
            Text(item).fontSize(12).fontColor(Color.Gray)
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
