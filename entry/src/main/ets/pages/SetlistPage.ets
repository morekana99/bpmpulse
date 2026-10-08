import { common } from '@kit.AbilityKit';
import { Setlist, SetlistDetailParam, SetlistSummary, SetlistTrack } from '../models/Setlist';
import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { EmptyView, MetaChip } from '../components/DjWidgets';
import { NameInputDialog } from '../components/NameInputDialog';
import { buildSetlistText } from '../utils/ExportText';
import { shareTextFile } from '../utils/ShareUtils';
import { computeStats, formatLongDuration } from '../utils/DjUtils';

/**
 * 歌单列表页：一个歌单就是 DJ 的一段 Set。
 * 卡片上直接展示曲目数、总时长、BPM 区间与调性分布，方便挑出适合某个场次的 Set。
 */
@Component
export struct SetlistPage {
  scroller: Scroller = new Scroller();
  @State summaries: SetlistSummary[] = [];
  @StorageProp('setlistsNeedRefresh') @Watch('loadSummaries') setlistRefresh: number = 0;
  @StorageProp('recordsNeedRefresh') @Watch('loadSummaries') recordRefresh: number = 0;
  stack: NavPathStack = new NavPathStack();

  private nameController: CustomDialogController = new CustomDialogController({
    builder: NameInputDialog({
      onConfirm: (value: string) => {
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

  aboutToAppear(): void {
    this.loadSummaries();
  }

  loadSummaries(): void {
    DatabaseHelper.getInstance().queryAllSetlistSummaries().then((list: SetlistSummary[]) => {
      this.summaries = list;
    }).catch((err: Error) => {
      console.error('SetlistPage: 加载歌单失败:', err.message);
    });
  }

  /**
   * ForEach 行键值：必须把卡片上"会变"的字段全拼进去。
   *
   * 只用歌单 id 的话，重命名 / 加歌 / 清空 / 导入之后 id 都不变，ArkUI 会按相同键值复用旧卡片
   * 且不重新渲染内容——表现就是"在歌单详情里改了名字，退回歌单列表卡片还是旧名字"。
   * 与曲库那次"编辑保存后列表不刷新"、详情页"改完第 N 首第 N+1 行衔接信息不刷新"是同一类问题。
   */
  summaryKey(item: SetlistSummary): string {
    return `${item.setlist.id}|${item.setlist.name}|${item.trackCount}|${item.totalDuration}` +
      `|${item.minBpm}|${item.maxBpm}|${item.avgBpm}|${item.avgEnergy}|${item.keyList.join(',')}`;
  }

  showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      // 提示失败不阻断主流程
    }
  }

  openNameDialog(title: Resource, initial: string, onConfirm: (value: string) => void): void {
    this.nameController = new CustomDialogController({
      builder: NameInputDialog({
        title: title,
        placeholder: $r('app.string.setlist_name_placeholder'),
        initial: initial,
        onConfirm: (value: string) => {
          this.nameController.close();
          onConfirm(value);
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

  createSetlist(): void {
    this.openNameDialog($r('app.string.setlist_new'), '', (value: string) => {
      DatabaseHelper.getInstance().insertSetlist(value).then(() => {
        this.loadSummaries();
      }).catch((err: Error) => {
        console.error('新建歌单失败:', err.message);
      });
    });
  }

  renameSetlist(item: Setlist): void {
    this.openNameDialog($r('app.string.setlist_rename'), item.name, (value: string) => {
      DatabaseHelper.getInstance().renameSetlist(item.id, value).then(() => {
        this.loadSummaries();
      }).catch((err: Error) => {
        console.error('重命名失败:', err.message);
      });
    });
  }

  duplicateSetlist(item: Setlist): void {
    const suggested: string = `${item.name} 2`;
    this.openNameDialog($r('app.string.setlist_duplicate'), suggested, (value: string) => {
      DatabaseHelper.getInstance().duplicateSetlist(item.id, value).then(() => {
        this.loadSummaries();
      }).catch((err: Error) => {
        console.error('复制歌单失败:', err.message);
      });
    });
  }

  confirmDelete(item: Setlist): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.setlist_delete_title'),
      message: $r('app.string.setlist_delete_msg', item.name),
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
          DatabaseHelper.getInstance().deleteSetlist(item.id).then(() => {
            this.loadSummaries();
          }).catch((err: Error) => {
            console.error('删除歌单失败:', err.message);
          });
        }
      }
    });
  }

  /**
   * 直接从列表分享歌单文本（与详情页导出同一套内容：曲目顺序 + 每两首的衔接提示）。
   * 主流 App 里"分享"是列表上的高频操作，不必先点进详情。
   */
  exportSetlist(item: Setlist): void {
    DatabaseHelper.getInstance().querySetlistTracks(item.id).then((tracks: SetlistTrack[]) => {
      if (tracks.length === 0) {
        this.showToast($r('app.string.toast_no_selection'));
        return;
      }
      const records: SongRecord[] = [];
      for (let i = 0; i < tracks.length; i++) {
        records.push(tracks[i].record);
      }
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const text: string = buildSetlistText(item.name, records, computeStats(records));
      const title: string = context.resourceManager.getStringSync($r('app.string.setlist_export_title').id);
      const descRes: Resource = records.length === 1
        ? $r('app.string.setlist_share_desc_one')
        : $r('app.string.setlist_share_desc_other');
      const desc: string = context.resourceManager.getStringSync(descRes.id, records.length);
      shareTextFile(context, `歌单_${item.name}_${Date.now()}.txt`, text, title, desc).catch(() => {
        // 用户取消分享不处理
      });
    }).catch((err: Error) => {
      console.error('SetlistPage: 导出歌单失败:', err.message);
      this.showToast($r('app.string.toast_share_failed'));
    });
  }

  openDetail(id: number): void {
    const param: SetlistDetailParam = { setlistId: id };
    this.stack.pushPath({ name: 'SetlistDetail', param: param });
  }



  @Builder
  createEntry() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([$r('app.color.app_brand_blue')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      Text($r('app.string.setlist_new'))
        .fontSize(16)
        .fontColor($r('app.color.app_brand_blue'))
    }
    .width('100%')
    .height(54)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .margin({ bottom: 10 })
    .onClick(() => {
      this.createSetlist();
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.summaries.length === 0) {
        Column() {
          EmptyView({
            icon: $r('sys.symbol.list_bullet'),
            title: $r('app.string.setlist_empty'),
            hint: $r('app.string.setlist_empty_hint')
          })
          this.createEntry()
        }
        .width('100%')
        // 必须撑满整屏：否则容器高度等于内容高度，justifyContent 居中不生效（图标会顶到最上方），
        // 且下方未被覆盖的区域会露出窗口默认白底而不是页面背景色
        .height('100%')
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r('app.color.app_bg_primary'))
      } else {
        Scroll(this.scroller) {
          Column({ space: 10 }) {
            this.createEntry()
            ForEach(this.summaries, (item: SetlistSummary) => {
              SetlistCard({
                item: item,
                onOpen: (id: number): void => this.openDetail(id),
                onRename: (s: Setlist): void => this.renameSetlist(s),
                onDuplicate: (s: Setlist): void => this.duplicateSetlist(s),
                onShare: (s: Setlist): void => this.exportSetlist(s),
                onDelete: (s: Setlist): void => this.confirmDelete(s)
              })
            }, (item: SetlistSummary) => this.summaryKey(item))
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 108, bottom: 130 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clipContent(ContentClipMode.SAFE_AREA)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor($r('app.color.app_bg_primary'))
      }
    }
    .width('100%')
    .height('100%')
    // 兜底：任何未被子内容覆盖的区域都用页面背景色，不要露出默认白底
    .backgroundColor($r('app.color.app_bg_primary'))
  }
}

/**
 * 歌单卡片：整张卡片支持长按呼出上下文菜单（重命名 / 复制 / 删除），卡片点击进入歌单详情。
 * 卡片右侧只保留 BPM 数据，不再放置「更多」等图标。
 */
@Component
struct SetlistCard {
  @Prop item: SetlistSummary = {
    setlist: { id: 0, name: '', note: '', createdAt: 0, updatedAt: 0 },
    trackCount: 0,
    totalDuration: 0,
    minBpm: 0,
    maxBpm: 0,
    avgBpm: 0,
    avgEnergy: 0,
    keyList: []
  };
  onOpen: (id: number) => void = () => {};
  onRename: (item: Setlist) => void = () => {};
  onDuplicate: (item: Setlist) => void = () => {};
  onShare: (item: Setlist) => void = () => {};
  onDelete: (item: Setlist) => void = () => {};

  bpmText(): string {
    if (this.item.trackCount === 0) {
      return '--';
    }
    if (this.item.minBpm === this.item.maxBpm) {
      return `${this.item.minBpm}`;
    }
    return `${this.item.minBpm}-${this.item.maxBpm}`;
  }

  @Builder
  menuContent() {
    Column() {
      this.menuRow($r('app.string.setlist_rename'), false, (): void => {
        this.onRename(this.item.setlist);
      })
      Divider()
        .color('#1F000000')
        .margin({ left: 16, right: 16 })
      this.menuRow($r('app.string.setlist_duplicate'), false, (): void => {
        this.onDuplicate(this.item.setlist);
      })
      Divider()
        .color('#1F000000')
        .margin({ left: 16, right: 16 })
      // 分享放在常规操作里，删除单独隔开并标红（主流分层方式）
      this.menuRow($r('app.string.action_share'), false, (): void => {
        this.onShare(this.item.setlist);
      })
      Divider()
        .color('#1F000000')
        .margin({ left: 16, right: 16 })
      this.menuRow($r('app.string.setlist_delete'), true, (): void => {
        this.onDelete(this.item.setlist);
      })
    }
    .width(180)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .padding({ top: 6, bottom: 6 })
  }

  @Builder
  menuRow(label: Resource, danger: boolean, action: () => void) {
    Text(label)
      .fontSize(16)
      .fontColor(danger ? '#E84040' : $r('app.color.app_text_primary'))
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        action();
      })
  }

  build() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          Text(this.item.setlist.name)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .alignSelf(ItemAlign.Start)

          Row({ space: 8 }) {
            Text($r('app.string.setlist_track_count', this.item.trackCount))
              .fontSize(13)
              .fontColor($r('app.color.app_text_secondary'))
            if (this.item.trackCount > 0) {
              Text($r('app.string.setlist_total_time', formatLongDuration(this.item.totalDuration)))
                .fontSize(13)
                .fontColor($r('app.color.app_text_secondary'))
            }
          }
          .alignSelf(ItemAlign.Start)
        }
        .layoutWeight(1)
        .flexShrink(1)
        .alignItems(HorizontalAlign.Start)

        Column({ space: 2 }) {
          Text(this.item.trackCount > 0 ? this.bpmText() : '--')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_brand_blue'))
          Text('BPM')
            .fontSize(11)
            .fontColor($r('app.color.app_text_hint'))
        }
        .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.item.keyList.length > 0) {
        Row({ space: 6 }) {
          ForEach(this.item.keyList.slice(0, 6), (key: string) => {
            MetaChip({ label: key })
          }, (key: string) => key)
          if (this.item.keyList.length > 6) {
            Text(`+${this.item.keyList.length - 6}`)
              .fontSize(11)
              .fontColor($r('app.color.app_text_hint'))
          }
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: 18, right: 18 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .shadow({ radius: 4, color: '#10000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      this.onOpen(this.item.setlist.id);
    })
    .bindContextMenu(this.menuContent, ResponseType.LongPress)
  }
}
