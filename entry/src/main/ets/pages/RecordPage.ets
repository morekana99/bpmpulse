import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { vibrator } from '@kit.SensorServiceKit';

@Entry
@Component
export struct RecordPage {
  scroller: Scroller = new Scroller();
  @State records: SongRecord[] = [];
  @StorageProp('recordsNeedRefresh') @Watch('loadRecords') refreshFlag: number = 0;
  @StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
  @StorageLink('multiSelectIds') selectedIds: number[] = [];

  aboutToAppear(): void {
    this.loadRecords();
  }

  loadRecords(): void {
    DatabaseHelper.getInstance().queryAll().then((data: SongRecord[]) => {
      this.records = data;
      AppStorage.setOrCreate('allRecordIds', data.map(r => r.id));
      console.log('RecordPage: 记录已加载，数量:', this.records.length);
    }).catch((err: Error) => {
      console.error('RecordPage: 加载记录失败:', err.message);
    });
  }

  toggleSelect(id: number) {
    const ids = [...this.selectedIds];
    const idx = ids.indexOf(id);
    if (idx >= 0) {
      ids.splice(idx, 1);
    } else {
      ids.push(id);
      if (!this.isMultiSelectMode) {
        this.isMultiSelectMode = true;
      }
    }
    this.selectedIds = ids;
  }

  enterMultiSelect(id: number) {
    this.isMultiSelectMode = true;
    if (!this.selectedIds.includes(id)) {
      this.selectedIds = [...this.selectedIds, id];
    }
  }

  exitMultiSelect() {
    this.isMultiSelectMode = false;
    this.selectedIds = [];
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  @Builder
  recordCard(record: SongRecord) {
    Row() {
      if (this.isMultiSelectMode) {
        Checkbox({ name: record.id.toString() })
          .select(this.selectedIds.includes(record.id))
          .selectedColor($r('app.color.app_brand_blue'))
          .width(22)
          .height(22)
          .margin({ right: 12 })
          .alignSelf(ItemAlign.Center)
          .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        Row() {
          Column({ space: 4 }) {
            Text(record.songName)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(record.artistName)
              .fontSize(14)
              .fontColor($r('app.color.app_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .flexGrow(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text(record.bpm.toString())
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_brand_blue'))

            Text('BPM')
              .fontSize(12)
              .fontColor($r('app.color.app_text_hint'))
          }
          .margin({ left: 16 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 8 })

        Row() {
          Text(`\u2219 点击 ${record.tapCount}次`)
            .fontSize(12)
            .fontColor($r('app.color.app_text_hint'))

          Text(`\u2219 间隔 ${record.averageInterval.toFixed(2)}秒`)
            .fontSize(12)
            .fontColor($r('app.color.app_text_hint'))
            .margin({ left: 12 })

          Blank()

          Text(this.formatTime(record.timestamp))
            .fontSize(12)
            .fontColor($r('app.color.app_text_hint'))
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 20, right: 20 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#10000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        this.toggleSelect(record.id);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          // 轻微振动反馈：进入多选
          vibrator.startVibration(
            { type: 'time', duration: 20 },
            { id: 0, usage: 'touch' }
          ).catch((err: Error) => {
            console.error('振动失败:', err.message);
          });
          this.enterMultiSelect(record.id);
        })
    )
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.records.length === 0) {
        Column() {
          Text('\u2630')
            .fontSize(72)
            .margin({ bottom: 24 })
            .opacity(0.3)

          Text('暂无记录')
            .fontSize(18)
            .fontColor($r('app.color.app_text_hint'))
            .margin({ bottom: 8 })

          Text('在BPM页面点击浮动按钮保存记录')
            .fontSize(14)
            .fontColor($r('app.color.app_text_hint'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.app_bg_primary'))
      } else {
        Scroll(this.scroller) {
          Column({ space: 12 }) {
            ForEach(this.records, (record: SongRecord) => {
              this.recordCard(record)
            }, (record: SongRecord) => record.id.toString())
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 116, bottom: 120 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clipContent(ContentClipMode.SAFE_AREA)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor($r('app.color.app_bg_primary'))
      }
    }
    .width('100%')
    .height('100%')
  }
}
