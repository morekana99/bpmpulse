import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial, IconStyleMode } from '@kit.UIDesignKit';
import { SongRecord, songRecordKey } from '../models/SongRecord';
import { Setlist, SetlistPickerParam, SetlistStats, SetlistTrack, TrackPickerParam } from '../models/Setlist';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { EmptyView, MetaChip, StatCell, BpmCurveChart, harmonyColor, harmonyText } from '../components/DjWidgets';
import { NameInputDialog } from '../components/NameInputDialog';
import { TrackEditDialog } from '../components/TrackEditDialog';
import { camelotNoteName, harmonyRank } from '../utils/MusicTheory';
import { computeStats, formatDuration, formatLongDuration, smartOrder, sortByBpmAsc, sortByBpmDesc } from '../utils/DjUtils';
import { buildSetlistText } from '../utils/ExportText';
import { shareTextFile } from '../utils/ShareUtils';

/** HDS 导航标题栏（MINI 模式）高度，用于让顶部悬浮工具条避开状态栏与标题栏 */
const TITLE_BAR_HEIGHT: number = 56;
/** 工具条与标题栏之间的留白 */
const TOOLBAR_TOP_GAP: number = 12;
/** 工具条高度（上下各 8 内边距 + 单行内容，与 toolbarChip 的 padding 对应） */
const TOOLBAR_HEIGHT: number = 34;
/** 「更多」面板行左右内边距 */
const SHEET_ROW_PADDING: number = 20;
/** 「更多」面板行内图标占位宽度（固定值，保证分割线左端与文字左边缘精确对齐） */
const SHEET_ICON_SIZE: number = 24;
/** 「更多」面板行内图标与文字的间距 */
const SHEET_ICON_GAP: number = 14;

/**
 * 歌单详情：一段 Set 的完整编排视图。
 * 顶部统计 + BPM 曲线给出整段走向，下方曲目可拖拽排序、一键智能排序，
 * 每首歌都会标出与上一首的 BPM 差和调性衔接等级。
 */
@Component
export struct SetlistDetailPage {
  setlistId: number = 0;
  stack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  @State name: string = '';
  @State tracks: SetlistTrack[] = [];
  @StorageProp('setlistsNeedRefresh') @Watch('loadTracks') refreshFlag: number = 0;
  @StorageProp('recordsNeedRefresh') @Watch('loadTracks') recordRefresh: number = 0;
  @State statusBarHeight: number = 0;
  /** 0=手动排序 1=智能排序 2=BPM升序 3=BPM降序 */
  @State sortMode: number = 0;
  /** 多选模式：批量移除歌单曲目，选中项用关联表 id（itemId）标识 */
  @State isMultiSelectMode: boolean = false;
  @State selectedItemIds: number[] = [];
  /** 拖动排序模式：卡片最左侧出现三条横线把手，按住它上下滑动即可换位 */
  @State isReorderMode: boolean = false;
  /** 正在拖动的行下标，-1 表示没有 */
  @State dragIndex: number = -1;
  /** 拖动中手指相对按下点的位移（vp），被拖卡片跟手 */
  @State dragOffsetY: number = 0;
  /** 拖动将要落入的槽位，其它卡片据此向反方向让位 */
  @State hoverIndex: number = -1;
  /** 每行的基准 y 与高度：拖动中行带位移，会污染基准值，所以只在非拖动状态记录 */
  private rowTops: number[] = [];
  private rowHeights: number[] = [];
  /** 「更多」操作面板是否展开（用系统半模态 bindSheet 承载） */
  @State actionsShown: boolean = false;

  private nameController: CustomDialogController = new CustomDialogController({
    builder: NameInputDialog({
      onConfirm: () => {
        this.nameController.close();
      },
      onCancel: () => {
        this.nameController.close();
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    autoCancel: false
  });

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
    // 乐观更新：同步替换歌单曲目里对应曲目的 record，界面立即刷新，
    // 不再单纯依赖异步重新查询。
    this.tracks = this.tracks.map((t: SetlistTrack) =>
      t.recordId === record.id ? { itemId: t.itemId, recordId: t.recordId, record: record } : t);
    DatabaseHelper.getInstance().updateSong(record).then(() => {
      this.loadTracks();
      AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    }).catch((err: Error) => {
      console.error('更新曲目失败:', err.message);
    });
    this.editController.close();
  }

  aboutToAppear(): void {
    this.loadTracks();
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusBarHeight = px2vp(area.topRect.height);
      }).catch(() => {});
    } catch (err) {
      // 获取状态栏高度失败时退化为 0，布局回到默认顶部留白
    }
  }

  loadTracks(): void {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    db.querySetlists().then((list: Setlist[]) => {
      const found: Setlist | undefined = list.find((s: Setlist) => s.id === this.setlistId);
      if (found) {
        this.name = found.name;
      }
    }).catch(() => {
      // 歌单可能已被删除，忽略名称加载失败
    });
    db.querySetlistTracks(this.setlistId).then((data: SetlistTrack[]) => {
      this.tracks = data;
    }).catch((err: Error) => {
      console.error('加载歌单曲目失败:', err.message);
    });
  }

  /**
   * ForEach 行键值。
   * 自身内容变化（编辑保存）必须触发重建；另外该行还会显示与「上一首」的
   * BPM 差与调性衔接等级，所以上一首的内容也要计入键值，否则改完第 N 首后
   * 第 N+1 行的衔接信息仍会停留在旧值。
   */
  trackKey(item: SetlistTrack, index: number): string {
    const prev: string = index > 0 ? songRecordKey(this.tracks[index - 1].record) : '';
    return `${item.itemId}|${songRecordKey(item.record)}|${prev}`;
  }

  recordList(): SongRecord[] {
    const list: SongRecord[] = [];
    for (let i = 0; i < this.tracks.length; i++) {
      list.push(this.tracks[i].record);
    }
    return list;
  }

  stats(): SetlistStats {
    return computeStats(this.recordList());
  }

  curveValues(): number[] {
    const values: number[] = [];
    for (let i = 0; i < this.tracks.length; i++) {
      values.push(this.tracks[i].record.bpm);
    }
    return values;
  }

  showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      // 提示失败不阻断主流程
    }
  }

  applyOrder(ordered: SongRecord[], toast: boolean): void {
    const ids: number[] = [];
    for (let i = 0; i < ordered.length; i++) {
      ids.push(ordered[i].id);
    }
    DatabaseHelper.getInstance().reorderSetlist(this.setlistId, ids).then(() => {
      this.loadTracks();
      if (toast) {
        this.showToast($r('app.string.toast_sorted'));
      }
    }).catch((err: Error) => {
      console.error('重排失败:', err.message);
    });
  }

  smartSort(): void {
    this.sortMode = 1;
    this.applyOrder(smartOrder(this.recordList()), true);
  }

  sortAsc(): void {
    this.sortMode = 2;
    this.applyOrder(sortByBpmAsc(this.recordList()), false);
  }

  sortDesc(): void {
    this.sortMode = 3;
    this.applyOrder(sortByBpmDesc(this.recordList()), false);
  }

  removeTrack(item: SetlistTrack): void {
    DatabaseHelper.getInstance().removeTrackFromSetlist(item.itemId, this.setlistId).then(() => {
      this.loadTracks();
    }).catch((err: Error) => {
      console.error('移除曲目失败:', err.message);
    });
  }

  // ---------------- 多选 ----------------

  enterMultiSelect(): void {
    this.selectedItemIds = [];
    this.isMultiSelectMode = true;
  }

  exitMultiSelect(): void {
    this.isMultiSelectMode = false;
    this.selectedItemIds = [];
  }

  isSelected(item: SetlistTrack): boolean {
    return this.selectedItemIds.indexOf(item.itemId) >= 0;
  }

  toggleSelect(item: SetlistTrack): void {
    const ids: number[] = [...this.selectedItemIds];
    const at: number = ids.indexOf(item.itemId);
    if (at >= 0) {
      ids.splice(at, 1);
    } else {
      ids.push(item.itemId);
    }
    this.selectedItemIds = ids;
  }

  allSelected(): boolean {
    return this.tracks.length > 0 && this.selectedItemIds.length === this.tracks.length;
  }

  toggleSelectAll(): void {
    if (this.allSelected()) {
      this.selectedItemIds = [];
      return;
    }
    const ids: number[] = [];
    for (let i = 0; i < this.tracks.length; i++) {
      ids.push(this.tracks[i].itemId);
    }
    this.selectedItemIds = ids;
  }

  /** 批量移除选中曲目：先确认再执行，避免误删 */
  confirmRemoveSelected(): void {
    const count: number = this.selectedItemIds.length;
    if (count === 0) {
      this.showToast($r('app.string.toast_no_selection'));
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.action_remove'),
      message: $r('app.string.setlist_remove_msg', count),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        fontColor: '#007DFF',
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.dialog_confirm'),
        fontColor: '#E84040',
        action: () => {
          DatabaseHelper.getInstance().removeTracksFromSetlist(this.selectedItemIds, this.setlistId)
            .then((rows: number) => {
              this.exitMultiSelect();
              this.loadTracks();
              this.showToast($r('app.string.toast_removed_tracks', rows));
            }).catch((err: Error) => {
              console.error('批量移除曲目失败:', err.message);
              this.showToast($r('app.string.toast_delete_failed'));
            });
        }
      }
    });
  }

  moveTrack(from: number, to: number): void {
    if (from === to || to < 0 || to >= this.tracks.length) {
      return;
    }
    this.sortMode = 0;
    const list: SongRecord[] = this.recordList();
    const moved: SongRecord = list[from];
    list.splice(from, 1);
    list.splice(to, 0, moved);
    this.applyOrder(list, false);
  }

  openPicker(): void {
    const anchorBpm: number = this.tracks.length > 0 ? this.tracks[this.tracks.length - 1].record.bpm : 0;
    const anchorKey: string = this.tracks.length > 0 ? this.tracks[this.tracks.length - 1].record.musicalKey : '';
    const param: TrackPickerParam = {
      setlistId: this.setlistId,
      anchorBpm: anchorBpm,
      anchorKey: anchorKey
    };
    this.stack.pushPath({ name: 'TrackPicker', param: param });
  }

  exportSetlist(): void {
    if (this.tracks.length === 0) {
      this.showToast($r('app.string.toast_no_selection'));
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const text: string = buildSetlistText(this.name, this.recordList(), this.stats());
      const title: string = context.resourceManager.getStringSync($r('app.string.setlist_export_title').id);
      const descRes: Resource = this.tracks.length === 1
        ? $r('app.string.setlist_share_desc_one')
        : $r('app.string.setlist_share_desc_other');
      const desc: string = context.resourceManager.getStringSync(descRes.id, this.tracks.length);
      shareTextFile(context, `歌单_${this.name}_${Date.now()}.txt`, text, title, desc).catch(() => {
        // 用户取消分享不处理
      });
    } catch (err) {
      console.error('导出歌单失败:', JSON.stringify(err));
      this.showToast($r('app.string.toast_share_failed'));
    }
  }

  rename(): void {
    this.nameController = new CustomDialogController({
      builder: NameInputDialog({
        title: $r('app.string.setlist_rename'),
        placeholder: $r('app.string.setlist_name_placeholder'),
        initial: this.name,
        onConfirm: (value: string) => {
          this.nameController.close();
          DatabaseHelper.getInstance().renameSetlist(this.setlistId, value).then(() => {
            this.name = value;
          }).catch((err: Error) => {
            console.error('重命名失败:', err.message);
          });
        },
        onCancel: () => {
          this.nameController.close();
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      autoCancel: false
    });
    this.nameController.open();
  }

  /**
   * 标题栏「更多」：展开歌单操作面板。
   * 歌单级操作（重命名 / 复制 / 清空 / 删除）统一收在这里，标题栏只留最高频的「分享」。
   */
  openActions(): void {
    this.actionsShown = true;
  }

  /** 复制当前歌单：改个名字，作为新歌单导入（不影响当前页面） */
  duplicateSetlist(): void {
    this.nameController = new CustomDialogController({
      builder: NameInputDialog({
        title: $r('app.string.setlist_duplicate'),
        placeholder: $r('app.string.setlist_name_placeholder'),
        initial: `${this.name} 2`,
        onConfirm: (value: string) => {
          this.nameController.close();
          DatabaseHelper.getInstance().duplicateSetlist(this.setlistId, value).then(() => {
            this.showToast($r('app.string.toast_setlist_copied'));
          }).catch((err: Error) => {
            console.error('复制歌单失败:', err.message);
          });
        },
        onCancel: () => {
          this.nameController.close();
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      autoCancel: false
    });
    this.nameController.open();
  }

  /** 删除整个歌单：确认后回到歌单列表 */
  confirmDeleteSetlist(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.setlist_delete_title'),
      message: $r('app.string.setlist_delete_msg', this.name),
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
          DatabaseHelper.getInstance().deleteSetlist(this.setlistId).then(() => {
            this.stack.pop();
          }).catch((err: Error) => {
            console.error('删除歌单失败:', err.message);
          });
        }
      }
    });
  }

  confirmClear(): void {
    if (this.tracks.length === 0) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.setlist_clear'),
      message: $r('app.string.setlist_clear_msg'),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.dialog_cancel'),
        fontColor: '#007DFF',
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.dialog_confirm'),
        fontColor: '#E84040',
        action: () => {
          DatabaseHelper.getInstance().clearSetlist(this.setlistId).then(() => {
            this.loadTracks();
          }).catch((err: Error) => {
            console.error('清空歌单失败:', err.message);
          });
        }
      }
    });
  }

  // ---------------- 拖动排序 / 长按多选 ----------------

  /** 进入拖动排序模式：卡片最左侧出现拖动把手，长按卡片即可拖动调整 */
  enterReorderMode(): void {
    this.exitMultiSelect();
    this.sortMode = 0;
    this.isReorderMode = true;
  }

  exitReorderMode(): void {
    this.resetDrag();
    this.isReorderMode = false;
  }

  /** 长按曲目卡片：进入多选并选中该曲目（拖动排序模式下由拖动接管，不响应） */
  onTrackLongPress(item: SetlistTrack): void {
    if (this.isReorderMode) {
      return;
    }
    vibrator.startVibration(
      { type: 'time', duration: 20 },
      { id: 0, usage: 'touch' }
    ).catch((err: Error) => {
      console.error('振动失败:', err.message);
    });
    if (!this.isMultiSelectMode) {
      this.enterMultiSelect();
    }
    if (!this.isSelected(item)) {
      this.toggleSelect(item);
    }
  }

  // ---------------- 拖动换位：按住左侧把手上下滑动 ----------------

  /** 记录每行基准位置；拖动过程中行的位置带位移，忽略以免污染基准值 */
  onRowArea(index: number, area: Area): void {
    if (this.dragIndex >= 0) {
      return;
    }
    this.rowTops[index] = Number(area.position.y);
    this.rowHeights[index] = Number(area.height);
  }

  private rowTop(index: number): number {
    return index >= 0 && index < this.rowTops.length ? this.rowTops[index] : 0;
  }

  private rowHeight(index: number): number {
    return index >= 0 && index < this.rowHeights.length ? this.rowHeights[index] : 0;
  }

  beginDrag(index: number): void {
    if (!this.isReorderMode || this.tracks.length < 2) {
      return;
    }
    this.dragIndex = index;
    this.hoverIndex = index;
    this.dragOffsetY = 0;
  }

  updateDrag(offsetY: number): void {
    if (this.dragIndex < 0) {
      return;
    }
    this.dragOffsetY = offsetY;
    this.hoverIndex = this.computeHoverIndex();
  }

  /** 松手：落到目标槽位并持久化；位置没变则只复位 */
  finishDrag(): void {
    const from: number = this.dragIndex;
    const to: number = this.hoverIndex;
    if (from < 0) {
      return;
    }
    if (to < 0 || to === from) {
      this.resetDrag();
      return;
    }
    this.commitReorder(from, to);
  }

  cancelDrag(): void {
    this.resetDrag();
  }

  private resetDrag(): void {
    this.dragIndex = -1;
    this.hoverIndex = -1;
    this.dragOffsetY = 0;
  }

  /** 被拖卡片中心压在哪一行之间 → 目标槽位 */
  private computeHoverIndex(): number {
    const draggedMid: number =
      this.rowTop(this.dragIndex) + this.rowHeight(this.dragIndex) / 2 + this.dragOffsetY;
    let slot: number = 0;
    for (let i = 0; i < this.tracks.length; i++) {
      if (i === this.dragIndex) {
        continue;
      }
      if (this.rowTop(i) + this.rowHeight(i) / 2 < draggedMid) {
        slot++;
      }
    }
    const last: number = this.tracks.length - 1;
    return slot < 0 ? 0 : (slot > last ? last : slot);
  }

  /**
   * 其它卡片的让位位移：向下拖时中间的行整体上移一个槽位，向上拖则下移。
   * 槽位高度取「被拖卡片高度 + 行间距」，因为原位置腾出的空档正好是这么大。
   */
  rowTranslateY(index: number): number {
    if (this.dragIndex < 0) {
      return 0;
    }
    if (index === this.dragIndex) {
      return this.dragOffsetY;
    }
    const slot: number = this.rowHeight(this.dragIndex) + 10;
    if (this.hoverIndex > this.dragIndex && index > this.dragIndex && index <= this.hoverIndex) {
      return -slot;
    }
    if (this.hoverIndex < this.dragIndex && index >= this.hoverIndex && index < this.dragIndex) {
      return slot;
    }
    return 0;
  }

  /** 本地先按新顺序渲染（立即反馈），再异步持久化，避免等查询返回造成回跳 */
  private commitReorder(from: number, to: number): void {
    const list: SetlistTrack[] = [...this.tracks];
    const moved: SetlistTrack = list[from];
    list.splice(from, 1);
    list.splice(to, 0, moved);
    this.sortMode = 0;
    this.resetDrag();
    this.tracks = list;
    const ids: number[] = [];
    for (let i = 0; i < list.length; i++) {
      ids.push(list[i].recordId);
    }
    DatabaseHelper.getInstance().reorderSetlist(this.setlistId, ids).catch((err: Error) => {
      console.error('拖动排序持久化失败:', err.message);
      this.loadTracks();
    });
  }

  /** 把曲目加进另一个歌单（复用「选歌单」页，当前歌单会被排除，不会误加到歌单自己身上） */
  addToOtherSetlist(item: SetlistTrack): void {
    const param: SetlistPickerParam = {
      recordIds: [item.recordId],
      excludeSetlistId: this.setlistId,
      onDone: (added: number, name: string) => {
        if (added > 0) {
          this.showToast($r('app.string.toast_added_tracks', added));
        } else {
          this.showToast($r('app.string.toast_already_in_setlist'));
        }
      }
    };
    this.stack.pushPath({ name: 'SetlistPicker', param: param });
  }

  // ---------------- UI ----------------

  @Builder
  transitionRow(prev: SongRecord, cur: SongRecord, index: number) {
    Row({ space: 6 }) {
      Text(`BPM ${cur.bpm - prev.bpm >= 0 ? '+' : ''}${cur.bpm - prev.bpm}`)
        .fontSize(11)
        .fontColor($r('app.color.app_text_secondary'))
      Text(harmonyText(harmonyRank(prev.musicalKey, cur.musicalKey)))
        .fontSize(11)
        .fontColor(harmonyColor(harmonyRank(prev.musicalKey, cur.musicalKey)))
    }
    .width('100%')
    // 与曲目标题左边缘对齐：卡片左内边距 14 + 序号宽度 24
    .padding({ left: 38 })
    .margin({ top: 4 })
    // 该行仍是原高度（不影响布局），只是被拖动时淡出，避免跟着卡片一起浮起来
    .opacity(this.dragIndex === index ? 0 : 1)
    .animation({ duration: 160, curve: Curve.Friction })
  }

  /**
   * 曲目行右侧的「更多」按钮：三个竖向排列的圆点。
   * 用基础组件绘制而非系统 symbol（系统 more 图标在小字号下呈现为方块），
   * 容器固定 28x28 并以 alignSelf 居中，保证图标贴卡片最右侧且上下居中。
   */
  @Builder
  moreDots(item: SetlistTrack) {
    Column({ space: 3 }) {
      Circle({ width: 3, height: 3 }).fill($r('app.color.app_text_hint'))
      Circle({ width: 3, height: 3 }).fill($r('app.color.app_text_hint'))
      Circle({ width: 3, height: 3 }).fill($r('app.color.app_text_hint'))
    }
    .width(28)
    .height(28)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .alignSelf(ItemAlign.Center)
    .margin({ left: 4 })
    .bindMenu([
      {
        value: $r('app.string.action_add_to_set'),
        action: () => {
          this.addToOtherSetlist(item);
        }
      },
      {
        value: $r('app.string.setlist_remove_from'),
        action: () => {
          this.removeTrack(item);
        }
      }
    ])
  }

  @Builder
  trackRow(item: SetlistTrack, index: number) {
    Column() {
      if (index > 0) {
        this.transitionRow(this.tracks[index - 1].record, item.record, index)
      }
      Row() {
        if (this.isReorderMode) {
          // 拖动把手：按住它上下滑动即可换位；卡片其余区域仍是正常滚动列表
          Row() {
            SymbolGlyph($r('sys.symbol.line_3_horizontal'))
              .fontSize(18)
              .fontColor([$r('app.color.app_text_hint')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }
          .padding({ left: 2, right: 10, top: 10, bottom: 10 })
          .alignSelf(ItemAlign.Center)
          .gesture(
            PanGesture({ fingers: 1, direction: PanDirection.Vertical, distance: 1 })
              .onActionStart(() => {
                this.beginDrag(index);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.updateDrag(event.offsetY);
              })
              .onActionEnd(() => {
                this.finishDrag();
              })
              .onActionCancel(() => {
                this.cancelDrag();
              })
          )
        }
        if (this.isMultiSelectMode) {
          Checkbox({ name: item.itemId.toString() })
            .select(this.isSelected(item))
            .selectedColor($r('app.color.app_brand_blue'))
            .width(22)
            .height(22)
            .margin({ right: 10 })
            .alignSelf(ItemAlign.Center)
            .hitTestBehavior(HitTestMode.None)
        }
        // 序号贴卡片最左、整行上下居中；个位数不补 0
        Text((index + 1).toString())
          .fontSize(13)
          .fontColor($r('app.color.app_text_hint'))
          .width(24)
          .textAlign(TextAlign.Start)
          .alignSelf(ItemAlign.Center)

        Column({ space: 3 }) {
          Text(item.record.songName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(item.record.artistName)
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Row({ space: 6 }) {
            if (item.record.musicalKey.length > 0) {
              MetaChip({ label: `${item.record.musicalKey} ${camelotNoteName(item.record.musicalKey)}` })
            }
            if (item.record.genre.length > 0) {
              MetaChip({ label: item.record.genre })
            }
            if (item.record.energy > 0) {
              MetaChip({ label: `E${item.record.energy}` })
            }
            Text(formatDuration(item.record.durationSec))
              .fontSize(11)
              .fontColor($r('app.color.app_text_hint'))
          }
          .width('100%')
          .margin({ top: 2 })
        }
        .layoutWeight(1)
        .flexShrink(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          if (this.isReorderMode) {
            return;
          }
          if (this.isMultiSelectMode) {
            this.toggleSelect(item);
          } else {
            this.openEditor(item.record);
          }
        })

        Column({ space: 2 }) {
          Text(item.record.bpm > 0 ? item.record.bpm.toString() : '--')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_brand_blue'))
          Text('BPM')
            .fontSize(10)
            .fontColor($r('app.color.app_text_hint'))
        }
        .margin({ left: 10 })

        if (!this.isMultiSelectMode && !this.isReorderMode) {
          this.moreDots(item)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
      .padding({ top: 12, bottom: 12, left: 14, right: 14 })
      .backgroundColor($r('app.color.app_bg_card'))
      .borderRadius(12)
      // 浮起效果挂在卡片自身上：卡片有圆角，阴影跟着圆角走；
      // 挂在外层容器上会因为容器包含上端「BPM 差」那行透明区域而画出方形阴影。
      .scale(this.dragIndex === index ? { x: 1.02, y: 1.02 } : { x: 1.0, y: 1.0 })
      .shadow(this.dragIndex === index
        ? { radius: 18, color: '#40000000', offsetX: 0, offsetY: 8 }
        : { radius: 4, color: '#10000000', offsetX: 0, offsetY: 2 })
      .animation({ duration: this.dragIndex === index ? 0 : 220, curve: Curve.Friction })
    }
    .width('100%')
    // 拖动换位：整行（含上端差值提示）跟手位移并置顶；被拖行 duration 0 保证跟手不延迟
    .zIndex(this.dragIndex === index ? 2 : 1)
    .translate({ y: this.rowTranslateY(index) })
    .animation({ duration: this.dragIndex === index ? 0 : 220, curve: Curve.Friction })
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.onRowArea(index, newValue);
    })
    .gesture(
      LongPressGesture({ repeat: false, duration: 500 })
        .onAction(() => {
          this.onTrackLongPress(item);
        })
    )
  }

  @Builder
  summaryCard() {
    Column() {
      Row() {
        StatCell({ label: $r('app.string.stat_tracks'), value: this.stats().count.toString() })
        StatCell({ label: $r('app.string.stat_duration'), value: formatLongDuration(this.stats().totalDuration) })
        StatCell({
          label: $r('app.string.stat_bpm_range'),
          value: this.stats().count > 0 ? `${this.stats().minBpm}-${this.stats().maxBpm}` : '--'
        })
        StatCell({
          label: $r('app.string.stat_avg_energy'),
          value: this.stats().avgEnergy > 0 ? this.stats().avgEnergy.toString() : '--'
        })
      }
      .width('100%')

      if (this.tracks.length >= 2) {
        Column() {
          Row() {
            Text($r('app.string.setlist_curve_title'))
              .fontSize(13)
              .fontColor($r('app.color.app_text_hint'))
            Blank()
            Text($r('app.string.setlist_avg_bpm', this.stats().avgBpm))
              .fontSize(12)
              .fontColor($r('app.color.app_text_secondary'))
          }
          .width('100%')
          .margin({ bottom: 4 })

          BpmCurveChart({ values: this.curveValues() })
            .width('100%')
            .height(110)
        }
        .width('100%')
        .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#10000000', offsetX: 0, offsetY: 2 })
  }

  /** 排序模式 → 图标：每种排序都有自己的图标，一眼看出当前用的是哪种 */
  sortIcon(): Resource {
    if (this.sortMode === 1) {
      return $r('sys.symbol.wand_and_stars');
    }
    if (this.sortMode === 2) {
      return $r('sys.symbol.arrow_up');
    }
    if (this.sortMode === 3) {
      return $r('sys.symbol.arrow_down');
    }
    return $r('sys.symbol.line_3_horizontal');
  }

  /** 排序按钮：显示当前排序模式（手动顺序也是一种模式），末尾的箭头表示可以点开菜单 */
  @Builder
  sortChip() {
    Row({ space: 6 }) {
      SymbolGlyph(this.sortIcon())
        .fontSize(15)
        .fontColor([this.sortMode === 0 ? $r('app.color.app_text_primary') : Color.White])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text(this.sortLabel())
        .fontSize(13)
        .fontColor(this.sortMode === 0 ? $r('app.color.app_text_primary') : Color.White)
        .maxLines(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(11)
        .fontColor([this.sortMode === 0 ? $r('app.color.app_text_hint') : Color.White])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .padding({ left: 14, right: 12, top: 8, bottom: 8 })
    .backgroundColor(this.sortMode === 0 ? $r('app.color.app_bg_card') : $r('app.color.app_brand_blue'))
    .border({ width: 1, color: this.sortMode === 0 ? '#1F000000' : Color.Transparent })
    .borderRadius(999)
    .bindMenu([
      {
        value: $r('app.string.setlist_reorder_start'),
        action: () => {
          this.enterReorderMode();
        }
      },
      {
        value: $r('app.string.setlist_smart_sort'),
        action: () => {
          this.smartSort();
        }
      },
      {
        value: $r('app.string.setlist_bpm_asc'),
        action: () => {
          this.sortAsc();
        }
      },
      {
        value: $r('app.string.setlist_bpm_desc'),
        action: () => {
          this.sortDesc();
        }
      }
    ])
  }

  /** 工具条胶囊按钮：多选模式下的全选 / 移除 / 完成，以及普通模式的"多选"入口共用 */
  @Builder
  toolbarChip(icon: Resource, label: ResourceStr, active: boolean, danger: boolean, action: () => void) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(15)
        .fontColor([danger ? '#E84040' : (active ? Color.White : $r('app.color.app_text_primary'))])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text(label)
        .fontSize(13)
        .fontColor(danger ? '#E84040' : (active ? Color.White : $r('app.color.app_text_primary')))
        .maxLines(1)
    }
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(active ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_card'))
    .border({ width: 1, color: active ? Color.Transparent : '#1F000000' })
    .borderRadius(999)
    .onClick(() => {
      action();
    })
  }

  /** 纯文字胶囊：多选按钮（按要求不带图标） */
  @Builder
  plainChip(label: ResourceStr, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.app_text_primary'))
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.app_bg_card'))
      .border({ width: 1, color: '#1F000000' })
      .borderRadius(999)
      .onClick(() => {
        action();
      })
  }

  @Builder
  toolbarView() {
    Row({ space: 8 }) {
      if (this.isMultiSelectMode) {
        // 多选：左侧全选，右侧批量移除 + 完成
        this.toolbarChip(
          this.allSelected() ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'),
          this.allSelected() ? $r('app.string.multiselect_deselect_all') : $r('app.string.multiselect_select_all'),
          false,
          false,
          () => {
            this.toggleSelectAll();
          }
        )
        Blank()
        this.toolbarChip(
          $r('sys.symbol.trash'),
          $r('app.string.setlist_remove_selected', this.selectedItemIds.length),
          false,
          true,
          () => {
            this.confirmRemoveSelected();
          }
        )
        this.toolbarChip(
          $r('sys.symbol.checkmark'),
          $r('app.string.action_done'),
          false,
          false,
          () => {
            this.exitMultiSelect();
          }
        )
      } else if (this.isReorderMode) {
        // 拖动排序：左侧只是提示文案，右侧完成
        Text($r('app.string.setlist_reorder_hint'))
          .fontSize(12)
          .fontColor($r('app.color.app_text_secondary'))
          .maxLines(1)
        Blank()
        this.toolbarChip(
          $r('sys.symbol.checkmark'),
          $r('app.string.action_done'),
          false,
          false,
          () => {
            this.exitReorderMode();
          }
        )
      } else {
        this.sortChip()
        // 多选按钮靠右，与排序按钮分开
        Blank()
        this.plainChip($r('app.string.multiselect_multi'), () => {
          this.enterMultiSelect();
        })
      }
    }
    .width('100%')
    .height(TOOLBAR_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  sortLabel(): Resource {
    if (this.sortMode === 1) {
      return $r('app.string.setlist_smart_sort');
    }
    if (this.sortMode === 2) {
      return $r('app.string.setlist_bpm_asc');
    }
    if (this.sortMode === 3) {
      return $r('app.string.setlist_bpm_desc');
    }
    return $r('app.string.setlist_sort_manual');
  }

  /** 多选模式下标题显示已选数量，与曲库页保持一致 */
  titleText(): ResourceStr {
    if (!this.isMultiSelectMode) {
      return this.name;
    }
    return this.selectedItemIds.length === 0
      ? $r('app.string.multiselect_none')
      : $r('app.string.multiselect_selected', this.selectedItemIds.length);
  }

  // ---------------- 「更多」操作面板 ----------------

  /** 面板里的一行：左侧单色线条图标 + 中间中文文字，整行可点，右侧不放箭头或其它内容 */
  @Builder
  sheetRow(icon: Resource, label: Resource, danger: boolean, action: () => void) {
    Row({ space: SHEET_ICON_GAP }) {
      SymbolGlyph(icon)
        .fontSize(22)
        .fontColor([danger ? '#E84040' : $r('app.color.app_text_primary')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .width(SHEET_ICON_SIZE)
      Text(label)
        .fontSize(16)
        .fontColor(danger ? '#E84040' : $r('app.color.app_text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(54)
    .padding({ left: SHEET_ROW_PADDING, right: SHEET_ROW_PADDING })
    .onClick(() => {
      action();
    })
  }

  /** 行与行之间的细浅灰分割线：左端缩进到与文字左边缘齐平，不顶到面板最左侧 */
  @Builder
  sheetDivider() {
    Divider()
      .strokeWidth(0.5)
      .color('#1A000000')
      .margin({ left: SHEET_ROW_PADDING + SHEET_ICON_SIZE + SHEET_ICON_GAP })
  }

  /**
   * 操作面板内容。
   * 承载在系统半模态（bindSheet）上：顶部左右大圆角、底部贴屏幕边缘、
   * 从下向上滑入 / 向下滑出的动画都由系统提供，不需要自己写过渡。
   */
  @Builder
  actionsSheet() {
    Column() {
      Row({ space: 6 }) {
        Text(this.name)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text($r('app.string.setlist_track_count', this.tracks.length))
          .fontSize(13)
          .fontColor($r('app.color.app_text_hint'))
      }
      .width('100%')
      // 顶部留出足够留白，标题不再紧贴面板上边缘
      .padding({ left: SHEET_ROW_PADDING, right: SHEET_ROW_PADDING, top: 20, bottom: 18 })
      .alignItems(VerticalAlign.Center)

      // 标题与第一个选项之间不放分割线（标题不属于选项列表）
      this.sheetRow($r('sys.symbol.pencil_line'), $r('app.string.setlist_rename'), false, () => {
        this.actionsShown = false;
        this.rename();
      })
      this.sheetDivider()
      this.sheetRow($r('sys.symbol.plus_square_on_square'), $r('app.string.setlist_duplicate'), false, () => {
        this.actionsShown = false;
        this.duplicateSetlist();
      })
      this.sheetDivider()
      this.sheetRow($r('sys.symbol.arrow_counterclockwise'), $r('app.string.setlist_clear_tracks'), false, () => {
        this.actionsShown = false;
        this.confirmClear();
      })
      this.sheetDivider()
      this.sheetRow($r('sys.symbol.trash'), $r('app.string.setlist_delete'), true, () => {
        this.actionsShown = false;
        this.confirmDeleteSetlist();
      })
      this.sheetDivider()
      Row() {
        Text($r('app.string.dialog_cancel'))
          .fontSize(16)
          .fontColor($r('app.color.app_text_primary'))
      }
      .width('100%')
      .height(54)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.actionsShown = false;
      })
    }
    .width('100%')
    .padding({ bottom: 12 })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.tracks.length === 0) {
          Column() {
            EmptyView({
              icon: $r('sys.symbol.music'),
              title: $r('app.string.setlist_no_tracks'),
              hint: $r('app.string.setlist_no_tracks_hint')
            })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.app_bg_primary'))
        } else {
          Scroll(this.scroller) {
            Column({ space: 10 }) {
              // 工具条随内容一起滚动：上滑时和卡片一样滑走，不再固定悬浮
              this.toolbarView()
              this.summaryCard()
              ForEach(this.tracks, (item: SetlistTrack, index: number) => {
                this.trackRow(item, index)
              }, (item: SetlistTrack, index: number) => this.trackKey(item, index))
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              bottom: 160,
              // 只需让出「状态栏 + 标题栏 + 与工具条的间距」，工具条本身已在滚动内容里
              top: this.statusBarHeight + TITLE_BAR_HEIGHT + TOOLBAR_TOP_GAP
            })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          .clipContent(ContentClipMode.SAFE_AREA)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor($r('app.color.app_bg_primary'))
        }

        if (!this.isMultiSelectMode) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(24)
              .fontColor([Color.White])
              .fontWeight(FontWeight.Bolder)
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
          }
          .width(56)
          .height(56)
          .backgroundColor($r('app.color.app_brand_blue'))
          .shadow({ radius: 12, color: '#30000000', offsetX: 0, offsetY: 6 })
          .position({ x: '100%', y: '100%' })
          .translate({ x: -72, y: -152 })
          .onClick(() => {
            this.openPicker();
          })
        }
      }
      .width('100%')
      .height('100%')
      // 「更多」操作面板：系统半模态，自带"从下向上滑入 / 向下滑出"动画、顶部大圆角、底部贴合屏幕
      .bindSheet(this.actionsShown, this.actionsSheet(), {
        height: SheetSize.FIT_CONTENT,
        showClose: false,
        dragBar: true,
        backgroundColor: $r('app.color.app_glass_bg'),
        blurStyle: BlurStyle.Thick,
        onDisappear: () => {
          this.actionsShown = false;
        }
      })
    }
    .titleBar({
      content: {
        title: { mainTitle: this.titleText() },
        menu: {
          maxCount: 2,
          value: [
            {
              content: {
                icon: $r('sys.symbol.arrowshape_turn_up_right'),
                type: IconStyleMode.NORMAL,
                action: (): void => {
                  this.exportSetlist();
                }
              }
            },
            {
              content: {
                // 华为官方「更多」图标（2×2 四点），比 circle_grid_2x2 的点更舒展
                icon: $r('sys.symbol.dot_grid_2x2'),
                type: IconStyleMode.NORMAL,
                action: (): void => {
                  this.openActions();
                }
              }
            }
          ]
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      avoidLayoutSafeArea: true,
      enableComponentSafeArea: false
    })
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(false)
    .bindToScrollable([this.scroller])
    // 多选 / 拖动排序模式下，系统返回（含左右滑动返回）先退出该模式，而不是直接退回歌单列表
    .onBackPressed((): boolean => {
      if (this.isMultiSelectMode) {
        this.exitMultiSelect();
        return true;
      }
      if (this.isReorderMode) {
        this.exitReorderMode();
        return true;
      }
      return false;
    })
  }
}
