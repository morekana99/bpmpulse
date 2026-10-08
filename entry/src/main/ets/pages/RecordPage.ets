import { common } from '@kit.AbilityKit';
import { vibrator } from '@kit.SensorServiceKit';
import { SongRecord, songRecordKey } from '../models/SongRecord';
import { SetlistPickerParam } from '../models/Setlist';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { TrackEditDialog } from '../components/TrackEditDialog';
import { EmptyView, MetaChip } from '../components/DjWidgets';
import { camelotNoteName } from '../utils/MusicTheory';
import { bpmDiffPercent, formatDuration, normalizeBpm } from '../utils/DjUtils';
import { buildLibraryText } from '../utils/ExportText';
import { shareTextFile } from '../utils/ShareUtils';

const SORT_RECENT: number = 0;
const SORT_BPM: number = 1;
const SORT_KEY: number = 2;
/** 搜索框输入纯数字时的 BPM 容差（百分比，含半速/倍速折算） */
const SEARCH_BPM_TOLERANCE_PERCENT: number = 3;

// 模块级缓存：RecordPage 在切换多选模式时会被销毁重建（Index 的 HdsTabs 在 4/3 个 TabContent 间切换），
// 重建后 aboutToAppear 重新异步拉取数据，首帧 records 为空会闪一下空背景（EmptyView）。
// 用此缓存让重建实例在首帧同步恢复上一次已加载的列表，避免闪烁；loadRecords 成功后更新。
let cachedRecords: SongRecord[] = [];

/**
 * 曲库页：所有测速保存下来的曲目。
 * 支持按 BPM / 调性排序、按风格筛选、多选批量加入歌单 / 导出 / 删除，以及单曲元数据编辑。
 */
@Component
export struct RecordPage {
scroller: Scroller = new Scroller();
stack: NavPathStack = new NavPathStack();
@State records: SongRecord[] = [];
@State sortMode: number = SORT_RECENT;
@State genreFilter: string = '';
@State keyword: string = '';
@State searchOffset: number = 0;
@StorageProp('recordsNeedRefresh') @Watch('loadRecords') refreshFlag: number = 0;
@StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
@StorageLink('multiSelectIds') selectedIds: number[] = [];
@StorageLink('isSearching') isSearching: boolean = false;

  private editController: CustomDialogController = new CustomDialogController({
    builder: TrackEditDialog({
      isNew: false,
      onSave: (record: SongRecord) => {
        this.saveEdit(record);
      },
      onCancel: () => {
        this.editController.close();
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: false
  });

  /** 搜索/筛选区距屏幕顶部的留白（状态栏 + 标题栏） */
  private readonly SEARCH_BAR_TOP: number = 96;
  /** 搜索/筛选区高度兜底值（首帧还没测量到时使用） */
  private readonly SEARCH_BAR_FALLBACK_HEIGHT: number = 140;
  /** 搜索/筛选区实测高度：有风格筛选行时更高，用来算"完全滑出屏幕"所需的位移 */
  @State headerHeight: number = 0;

  /**
   * 让搜索 + 排序/筛选整块完全滑出屏幕所需的位移。
   * 之前写死 140 小于该区域实际高度，导致上滑后还剩一截卡在屏幕最上方。
   */
  searchHideDistance(): number {
    const height: number = this.headerHeight > 0 ? this.headerHeight : this.SEARCH_BAR_FALLBACK_HEIGHT;
    return this.SEARCH_BAR_TOP + height + 8;
  }

  aboutToAppear(): void {
    // 重建时先用缓存同步恢复列表，避免首帧空背景闪烁；随后仍走异步刷新保证数据最新
    if (cachedRecords.length > 0) {
      this.records = cachedRecords;
    }
    this.loadRecords();
  }

  loadRecords(): void {
    DatabaseHelper.getInstance().queryAll().then((data: SongRecord[]) => {
      cachedRecords = data;
      this.records = data;
      AppStorage.setOrCreate('allRecordIds', data.map((r: SongRecord) => r.id));
      console.log('RecordPage: 记录已加载，数量:', this.records.length);
    }).catch((err: Error) => {
      console.error('RecordPage: 加载记录失败:', err.message);
    });
  }

  // ---------------- 数据派生 ----------------

  genreOptions(): string[] {
    const set: string[] = [];
    for (let i = 0; i < this.records.length; i++) {
      const g: string = this.records[i].genre;
      if (g.length > 0 && set.indexOf(g) < 0) {
        set.push(g);
      }
    }
    return set;
  }

  /**
   * 搜索框里的"目标 BPM"：仅当输入是纯数字、且落在合理速度区间（40–300）时才算。
   * 用途是把原先工具页那张「按 BPM 找歌」卡的能力合进曲库搜索——
   * 在能直接编辑 / 多选 / 加入歌单的地方找歌。
   */
  searchBpmTarget(): number {
    const kw: string = this.keyword.trim();
    if (kw.length === 0 || kw.length > 3 || !/^\d+$/.test(kw)) {
      return 0;
    }
    const n: number = parseInt(kw, 10);
    return n >= 40 && n <= 300 ? n : 0;
  }

  visibleRecords(): SongRecord[] {
    let list: SongRecord[] = this.records;
    const kw: string = this.keyword.trim().toLowerCase();
    // 纯数字查询时除文本命中外，再纳入 BPM 相近的曲目；
    // 半速/倍速由 bpmDiffPercent → normalizeBpm 折算，所以搜 128 也会带出 64 的曲子。
    const targetBpm: number = this.searchBpmTarget();
    if (kw.length > 0) {
      list = list.filter((r: SongRecord) =>
        r.songName.toLowerCase().indexOf(kw) >= 0 ||
        r.artistName.toLowerCase().indexOf(kw) >= 0 ||
        r.genre.toLowerCase().indexOf(kw) >= 0 ||
        (targetBpm > 0 && bpmDiffPercent(targetBpm, r.bpm) <= SEARCH_BPM_TOLERANCE_PERCENT));
    }
    if (this.genreFilter.length > 0) {
      list = list.filter((r: SongRecord) => r.genre === this.genreFilter);
    }
    const copy: SongRecord[] = [...list];
    if (this.sortMode === SORT_BPM) {
      copy.sort((a: SongRecord, b: SongRecord) => normalizeBpm(a.bpm) - normalizeBpm(b.bpm));
    } else if (this.sortMode === SORT_KEY) {
      copy.sort((a: SongRecord, b: SongRecord) => a.musicalKey.localeCompare(b.musicalKey));
    }
    return copy;
  }

  /** 列表顶部留白：需要避让搜索入口栏与排序/筛选区，有风格筛选时额外加高 */
  listTopPadding(): number {
    return this.genreOptions().length > 0 ? 236 : 176;
  }

  // ---------------- 交互 ----------------

  toggleSelect(id: number) {
    const ids = [...this.selectedIds];
    const idx = ids.indexOf(id);
    if (idx >= 0) {
      ids.splice(idx, 1);
    } else {
      ids.push(id);
    }
    this.selectedIds = ids;
    if (ids.length === 0) {
      this.isMultiSelectMode = false;
    }
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

  selectedRecords(): SongRecord[] {
    const ids: number[] = this.selectedIds;
    return this.records.filter((r: SongRecord) => ids.includes(r.id));
  }

  showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      // 提示失败不阻断主流程
    }
  }

  openEditor(record: SongRecord) {
    this.editController = new CustomDialogController({
      builder: TrackEditDialog({
        record: record,
        isNew: false,
        onSave: (updated: SongRecord) => {
          this.saveEdit(updated);
        },
        onCancel: () => {
          this.editController.close();
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      autoCancel: false
    });
    this.editController.open();
  }

  saveEdit(record: SongRecord) {
    // 乐观更新：先同步替换内存列表中的对应记录，保证界面立即刷新，
    // 不再单纯依赖异步重新查询（查询返回前界面已是最新）。
    this.records = this.records.map((r: SongRecord) =>
      r.id === record.id ? record : r);
    DatabaseHelper.getInstance().updateSong(record).then(() => {
      this.loadRecords();
      AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
      this.showToast($r('app.string.toast_updated'));
    }).catch((err: Error) => {
      console.error('更新记录失败:', err.message);
    });
    this.editController.close();
  }

  openAddToSetlist() {
    const ids: number[] = this.selectedIds;
    if (ids.length === 0) {
      this.showToast($r('app.string.toast_no_selection'));
      return;
    }
    // 选歌单是整页（与「选曲目」页对称）：歌单多时可整页滚动 + 搜索，新建歌单也在同一页完成
    const param: SetlistPickerParam = {
      recordIds: ids,
      excludeSetlistId: -1,
      onDone: (added: number, name: string) => {
        this.onAddedToSetlist(added, name);
      }
    };
    this.stack.pushPath({ name: 'SetlistPicker', param: param });
  }

  onAddedToSetlist(added: number, name: string) {
    if (added > 0) {
      this.showToast($r('app.string.toast_added_tracks', added));
      this.exitMultiSelect();
    } else {
      // 选中的曲目都在目标歌单里（例如重名歌单）时给明确提示，不要说成"没选曲目"
      this.showToast($r('app.string.toast_already_in_setlist'));
    }
  }

  exportSelected() {
    const list: SongRecord[] = this.selectedRecords();
    if (list.length === 0) {
      this.showToast($r('app.string.toast_no_selection'));
      return;
    }
    this.shareRecords(list);
  }

  shareRecords(list: SongRecord[]) {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const text: string = buildLibraryText(list);
      const title: string = context.resourceManager.getStringSync($r('app.string.share_sheet_title').id);
      const descRes: Resource = list.length === 1
        ? $r('app.string.share_sheet_desc_one')
        : $r('app.string.share_sheet_desc_other');
      const desc: string = context.resourceManager.getStringSync(descRes.id, list.length);
      shareTextFile(context, `BPM曲库_${Date.now()}.txt`, text, title, desc).catch(() => {
        // 用户取消分享不处理
      });
    } catch (err) {
      console.error('分享失败:', JSON.stringify(err));
      this.showToast($r('app.string.toast_share_failed'));
    }
  }

  deleteSelected() {
    const ids: number[] = this.selectedIds;
    if (ids.length === 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.delete_confirm_title'),
      message: $r('app.string.delete_confirm_msg', ids.length),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        fontColor: '#007DFF',
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.dialog_delete'),
        fontColor: '#E84040',
        action: () => {
          DatabaseHelper.getInstance().deleteByIds(ids).then((rows: number) => {
            this.exitMultiSelect();
            this.loadRecords();
            this.showToast($r('app.string.toast_deleted_count', rows));
          }).catch((err: Error) => {
            console.error('删除记录失败:', err.message);
            this.showToast($r('app.string.toast_delete_failed'));
          });
        }
      }
    });
  }

  // ---------------- UI ----------------

  @Builder
  searchBar() {
    Row() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([$r('app.color.app_text_hint')])
        TextInput({ placeholder: $r('app.string.search_placeholder'), text: this.keyword })
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .fontSize(15)
          .onFocus(() => {
            this.isSearching = true;
          })
          .onBlur(() => {
            this.isSearching = false;
          })
          .onChange((value: string) => {
            this.keyword = value;
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 14, right: 14 })
      .backgroundColor($r('app.color.app_bg_card'))
      .borderRadius(20)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  @Builder
  filterRow() {
    Column() {
      Row({ space: 8 }) {
        this.sortChip($r('app.string.library_sort_recent'), SORT_RECENT)
        this.sortChip($r('app.string.library_sort_bpm'), SORT_BPM)
        this.sortChip($r('app.string.library_sort_key'), SORT_KEY)
        Blank()
        Text(this.searchBpmTarget() > 0
          ? $r('app.string.library_count_bpm', this.visibleRecords().length, this.searchBpmTarget())
          : $r('app.string.library_count', this.visibleRecords().length))
          .fontSize(12)
          .fontColor($r('app.color.app_text_hint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.genreOptions().length > 0) {
        Scroll() {
          Row({ space: 6 }) {
            this.genreChip($r('app.string.library_filter_all'), '')
            ForEach(this.genreOptions(), (item: string) => {
              this.genreChip(item, item)
            }, (item: string) => item)
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 4 })
  }

  @Builder
  sortChip(label: Resource, mode: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.sortMode === mode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.sortMode === mode ? Color.White : $r('app.color.app_text_secondary'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.sortMode === mode ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_card'))
      .borderRadius(999)
      .onClick(() => {
        this.sortMode = mode;
      })
  }

  @Builder
  genreChip(label: ResourceStr, value: string) {
    Text(label)
      .fontSize(13)
      .fontColor(this.genreFilter === value ? Color.White : $r('app.color.app_text_secondary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.genreFilter === value ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_card'))
      .borderRadius(999)
      .onClick(() => {
        this.genreFilter = value;
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
          Column({ space: 3 }) {
            Text(record.songName)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text(record.artistName)
              .fontSize(13)
              .fontColor($r('app.color.app_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .flexGrow(1)
          .flexShrink(1)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 2 }) {
            Text(record.bpm > 0 ? record.bpm.toString() : '--')
              .fontSize(23)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_brand_blue'))
            Text('BPM')
              .fontSize(11)
              .fontColor($r('app.color.app_text_hint'))
          }
          .margin({ left: 14 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 8 })

        Row({ space: 6 }) {
          if (record.musicalKey.length > 0) {
            MetaChip({ label: `${record.musicalKey} ${camelotNoteName(record.musicalKey)}` })
          }
          if (record.genre.length > 0) {
            MetaChip({ label: record.genre })
          }
          if (record.energy > 0) {
            MetaChip({ label: `E${record.energy}` })
          }
          Blank()
          Text(formatDuration(record.durationSec))
            .fontSize(12)
            .fontColor($r('app.color.app_text_hint'))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 18, right: 18 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#10000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      if (this.isMultiSelectMode) {
        this.toggleSelect(record.id);
      } else {
        this.openEditor(record);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
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
          EmptyView({
            icon: $r('sys.symbol.music'),
            title: $r('app.string.record_no_data'),
            hint: $r('app.string.record_empty_hint')
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.app_bg_primary'))
      } else if (this.visibleRecords().length === 0) {
        Column() {
          EmptyView({
            icon: $r('sys.symbol.magnifyingglass'),
            title: $r('app.string.library_no_match'),
            hint: $r('app.string.library_no_match_hint')
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.app_bg_primary'))
      } else {
        Scroll(this.scroller) {
          Column({ space: 10 }) {
            ForEach(this.visibleRecords(), (record: SongRecord) => {
              this.recordCard(record)
            }, (record: SongRecord) => songRecordKey(record))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: this.listTopPadding(), bottom: 130 })
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

      // 搜索入口/搜索框 + 排序/筛选：随内容上滑一起移出屏幕（下拉到顶时固定不跟随）。
      // 位移上限取"自身实测高度 + 顶部留白"，保证整块彻底滑出，不会在屏幕最上方留一截。
      if (this.records.length > 0) {
        Column() {
          this.searchBar()
          this.filterRow()
        }
        .width('100%')
        .margin({ top: this.SEARCH_BAR_TOP })
        .onAreaChange((oldValue: Area, newValue: Area) => {
          this.headerHeight = Number(newValue.height);
        })
        .translate({ y: -Math.min(Math.max(this.searchOffset, 0), this.searchHideDistance()) })
      }

    }
    .width('100%')
    .height('100%')
  }
}

