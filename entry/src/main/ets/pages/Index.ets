import { AudioTab } from '../tabs/AudioTab';
import { SensorsTab } from '../tabs/SensorsTab';
import { VibratorTab } from '../tabs/VibratorTab';

@Entry
@Component
struct Index {
  @State currentTab: number = 0;

  @Builder
  tabBarItem(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === index ? Color.Blue : Color.Black)
    }
    .justifyContent(FlexAlign.Center)
    .height('100%')
    .width('100%')
  }

  build() {
    Column() {
      Text('Oniro HW Tester')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .padding({ top: 40, bottom: 8, left: 16 })
        .alignSelf(ItemAlign.Start)
      Tabs({ index: this.currentTab }) {
        TabContent() {
          AudioTab()
        }
        .tabBar(this.tabBarItem('Audio', 0))

        TabContent() {
          SensorsTab()
        }
        .tabBar(this.tabBarItem('Sensors', 1))

        TabContent() {
          VibratorTab()
        }
        .tabBar(this.tabBarItem('Vibrator', 2))
      }
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .layoutWeight(1)
      .barHeight(48)
    }
    .width('100%')
    .height('100%')
  }
}
