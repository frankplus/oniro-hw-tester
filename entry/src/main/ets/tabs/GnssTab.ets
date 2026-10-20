/*
 * GNSS test tab: turns on the location switch and permissions, then runs a
 * continuous NAVIGATION request (which the framework serves from GNSS) and
 * shows satellites, C/N0, time to first fix and the latest position.
 */
import { geoLocationManager } from '@kit.LocationKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { i18n } from '@kit.LocalizationKit';

const DOMAIN = 0x0003;
const TAG = 'HwTesterGnss';

// SatelliteAdditionalInfo bit for "used in fix" (location_vendor_lib.h).
const SV_USED_IN_FIX = 4;

const CONSTELLATIONS: string[] = ['?', 'GPS', 'SBAS', 'GLO', 'QZSS', 'BDS', 'GAL', 'NavIC'];

@Component
export struct GnssTab {
  @State status: string = 'idle';
  @State running: boolean = false;
  @State svVisible: number = 0;
  @State svUsed: number = 0;
  @State bestCn0: number = 0;
  @State perConstellation: string = '';
  @State fixText: string = 'no fix yet';
  @State ttff: string = '-';
  @State fixes: number = 0;
  @State nmeaCount: number = 0;
  @State tzText: string = '-';
  private startMs: number = 0;

  private onLocation = (loc: geoLocationManager.Location): void => {
    if (this.fixes === 0) {
      this.ttff = `${((Date.now() - this.startMs) / 1000).toFixed(1)} s`;
    }
    this.fixes++;
    if (this.fixes === 1) {
      this.tzText = this.lookupTimezone(loc.latitude, loc.longitude);
    }
    this.fixText = `${loc.latitude.toFixed(6)}, ${loc.longitude.toFixed(6)}\n` +
      `±${loc.accuracy.toFixed(1)} m, alt ${loc.altitude.toFixed(0)} m, ` +
      `${loc.speed.toFixed(1)} m/s, source ${loc.sourceType ?? '?'}`;
    hilog.info(DOMAIN, TAG, 'fix #%{public}d acc %{public}f', this.fixes, loc.accuracy);
  };

  private onSatellites = (info: geoLocationManager.SatelliteStatusInfo): void => {
    this.svVisible = info.satellitesNumber;
    let used = 0;
    let best = 0;
    let counts: number[] = new Array<number>(CONSTELLATIONS.length).fill(0);
    for (let i = 0; i < info.satellitesNumber; i++) {
      let extra = info.satelliteAdditionalInfo ? info.satelliteAdditionalInfo[i] : 0;
      if ((extra & SV_USED_IN_FIX) !== 0) {
        used++;
      }
      if (info.carrierToNoiseDensitys[i] > best) {
        best = info.carrierToNoiseDensitys[i];
      }
      let c = info.satelliteConstellation ? info.satelliteConstellation[i] : 0;
      if (c >= 0 && c < counts.length) {
        counts[c]++;
      }
    }
    this.svUsed = used;
    this.bestCn0 = best;
    let parts: string[] = [];
    for (let c = 1; c < counts.length; c++) {
      if (counts[c] > 0) {
        parts.push(`${CONSTELLATIONS[c]} ${counts[c]}`);
      }
    }
    this.perConstellation = parts.join(', ');
  };

  // Offline boundary lookup shipped with OHOS i18n (/system/usr/ohos_timezone).
  private lookupTimezone(lat: number, lon: number): string {
    try {
      let zones = i18n.TimeZone.getTimezonesByLocation(lon, lat);
      let ids = zones.map((z: i18n.TimeZone) => z.getID());
      hilog.info(DOMAIN, TAG, 'timezone at fix: %{public}s', ids.join(','));
      return ids.length > 0 ? ids.join(', ') : 'none';
    } catch (e) {
      return `error: ${(e as Error).message}`;
    }
  }

  private onNmea = (nmea: string): void => {
    this.nmeaCount++;
  };

  aboutToDisappear(): void {
    this.stop();
  }

  async prepare(): Promise<boolean> {
    let ctx = getContext(this) as common.UIAbilityContext;
    let atManager = abilityAccessCtrl.createAtManager();
    try {
      let result = await atManager.requestPermissionsFromUser(ctx,
        ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION']);
      if (result.authResults.some((r: number) => r !== 0)) {
        this.status = 'location permission denied';
        return false;
      }
    } catch (e) {
      this.status = `permission request failed: ${(e as Error).message}`;
      return false;
    }
    let enabled = false;
    try {
      enabled = geoLocationManager.isLocationEnabled();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'isLocationEnabled: %{public}s', (e as Error).message);
    }
    if (!enabled) {
      try {
        let on = await atManager.requestGlobalSwitch(ctx, abilityAccessCtrl.SwitchType.LOCATION);
        if (!on) {
          this.status = 'location switch left off';
          return false;
        }
      } catch (e) {
        this.status = `turn on Location in Settings (${(e as Error).message})`;
        return false;
      }
    }
    return true;
  }

  async start(): Promise<void> {
    if (this.running) {
      return;
    }
    if (!(await this.prepare())) {
      return;
    }
    this.svVisible = 0;
    this.svUsed = 0;
    this.bestCn0 = 0;
    this.perConstellation = '';
    this.fixes = 0;
    this.nmeaCount = 0;
    this.ttff = '-';
    this.fixText = 'no fix yet';
    this.startMs = Date.now();
    let request: geoLocationManager.ContinuousLocationRequest = {
      interval: 1,
      locationScenario: geoLocationManager.UserActivityScenario.NAVIGATION
    };
    try {
      geoLocationManager.on('satelliteStatusChange', this.onSatellites);
      geoLocationManager.on('nmeaMessage', this.onNmea);
      geoLocationManager.on('locationChange', request, this.onLocation);
      this.running = true;
      this.status = 'searching…';
    } catch (e) {
      this.status = `ERROR: ${(e as Error).message}`;
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', (e as Error).message);
    }
  }

  stop(): void {
    if (!this.running) {
      return;
    }
    try {
      geoLocationManager.off('locationChange', this.onLocation);
      geoLocationManager.off('satelliteStatusChange', this.onSatellites);
      geoLocationManager.off('nmeaMessage', this.onNmea);
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'stop failed: %{public}s', (e as Error).message);
    }
    this.running = false;
    this.status = 'stopped';
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Button('Start').onClick(() => this.start())
        Button('Stop').backgroundColor(Color.Gray).onClick(() => this.stop())
      }
      Text(`Status: ${this.status}`).fontSize(14)

      Divider()

      Text('Satellites').fontSize(18).fontWeight(FontWeight.Bold)
      Text(`${this.svVisible} visible, ${this.svUsed} used in fix`).fontSize(16)
      Text(`best C/N0: ${this.bestCn0.toFixed(1)} dB-Hz`).fontSize(14)
      Text(this.perConstellation).fontSize(14)
      Text(`NMEA sentences: ${this.nmeaCount}`).fontSize(14)

      Divider()

      Text('Fix').fontSize(18).fontWeight(FontWeight.Bold)
      Text(this.fixText).fontSize(16)
      Text(`time to first fix: ${this.ttff}, fixes: ${this.fixes}`).fontSize(14)
      Text(`timezone here: ${this.tzText}`).fontSize(14)
      Text('Cold start outdoors: allow a few minutes; indoors the sky is usually invisible.')
        .fontSize(12)
        .fontColor(Color.Gray)
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
  }
}
