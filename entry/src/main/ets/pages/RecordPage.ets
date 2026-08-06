import { uiMaterial } from '@kit.ArkUI';
import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { vibrator } from '@kit.SensorServiceKit';

@Component
export struct RecordPage {
  scroller: Scroller = new Scroller();
  @State records: SongRecord[] = [];
  @StorageProp('recordsNeedRefresh') @Watch('loadRecords') refreshFlag: number = 0;
  @StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
  @StorageLink('multiSelectIds') selectedIds: number[] = [];
  @StorageLink('isSearching') isSearching: boolean = false;
  @State searchOffset: number = 0;
  // 搜索入口栏顶部留白（状态栏+标题栏）与完全隐藏所需位移
  private readonly SEARCH_BAR_TOP: number = 96;
  private readonly SEARCH_BAR_HIDE: number = 140;

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

  enterSearch(): void {
    this.getUIContext()?.animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.isSearching = true;
    });
  }

  exitSearch(): void {
    // 收起键盘
    this.searchOffset = 0;
    this.getUIContext()?.animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
      this.isSearching = false;
    });
  }

  formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
  }

  @Builder
  searchEntryBar() {
    // 外层负责定位和边距
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(18)
          .fontColor([$r('app.color.app_text_hint')])
        Text($r('app.string.search_placeholder'))
          .fontSize(15)
          .fontColor($r('app.color.app_text_hint'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(40)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      // HDS 沉浸光感：挂载官方 systemMaterial 沉浸材质（THIN 薄样式，官方指定用于搜索框场景），
      // 背景透明以透出材质，由系统统一接管背景、边框与阴影，无需手写模糊。
      .backgroundColor(Color.Transparent)
      .borderRadius(22)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN
      }))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .margin({ top: this.SEARCH_BAR_TOP })
    .translate({ y: -Math.min(Math.max(this.searchOffset, 0), this.SEARCH_BAR_HIDE) })
    .onClick(() => {
      this.enterSearch();
    })
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
              .width('100%')

            Text(record.artistName)
              .fontSize(14)
              .fontColor($r('app.color.app_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .flexGrow(1)
          .flexShrink(1)
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
          Text($r('app.string.record_tap_count', record.tapCount))
            .fontSize(12)
            .fontColor($r('app.color.app_text_hint'))

          Text($r('app.string.record_avg_interval', record.averageInterval.toFixed(2)))
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

          Text($r('app.string.record_no_data'))
            .fontSize(18)
            .fontColor($r('app.color.app_text_hint'))
            .margin({ bottom: 8 })

          Text($r('app.string.record_empty_hint'))
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
          .padding({ left: 16, right: 16, top: 148, bottom: 120 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clipContent(ContentClipMode.SAFE_AREA)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor($r('app.color.app_bg_primary'))
        .onDidScroll(() => {
          this.searchOffset = this.scroller.currentOffset().yOffset;
        })
      }

      // 搜索入口栏：随内容上滑消失，下拉到顶时固定不跟随
      if (this.records.length > 0 && !this.isSearching) {
        this.searchEntryBar()
      }


    }
    .width('100%')
    .height('100%')
  }
}
