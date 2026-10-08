import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { SetlistSummary } from '../models/Setlist';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { NameInputDialog } from '../components/NameInputDialog';

/** HDS 导航标题栏（MINI 模式）高度，用于让顶部固定区避开状态栏与标题栏 */
const TITLE_BAR_HEIGHT: number = 56;
/** 歌单数量超过该值才显示搜索框：只有几个歌单时不必在顶部多堆一个控件 */
const SEARCH_THRESHOLD: number = 8;

/**
 * 选歌单页：把选中的曲目加进某个歌单。
 * 曲库多选的「加入歌单」与歌单详情里的「加入其它歌单」共用本页。
 *
 * 为什么做成整页而不是弹窗：
 * - 歌单数量不可控，列表需要能整页滚动 + 顶部搜索，弹窗高度有限、歌单一多只能在很小的区域里翻；
 * - 「新建歌单」要弹输入框，整页布局下键盘避让由系统负责，不会像底部弹窗那样被键盘顶住或抖动；
 * - 与「选曲目」（TrackPickerPage）对称：都是"挑东西"的场景，做成同一套页面观感才统一。
 */
@Component
export struct SetlistPickerPage {
  recordIds: number[] = [];
  /** 需要隐藏的歌单（从歌单详情进来时排除当前歌单），-1 表示不排除 */
  excludeSetlistId: number = -1;
  /** 加入完成后回调调用方（弹提示 / 退出多选），随后本页自动返回 */
  onDone: (added: number, name: string) => void = () => {};
  stack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  @State summaries: SetlistSummary[] = [];
  @State keyword: string = '';
  @State statusBarHeight: number = 0;

  private nameController: CustomDialogController = new CustomDialogController({
    builder: NameInputDialog({
      title: $r('app.string.setlist_new'),
      placeholder: $r('app.string.setlist_name_placeholder'),
      initial: '',
      onConfirm: (value: string) => {
        this.nameController.close();
        this.createAndAdd(value);
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
    this.loadSetlists();
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        this.statusBarHeight = px2vp(area.topRect.height);
      }).catch(() => {
        // 取不到状态栏高度时按 0 兜底，顶部留白退化为默认值
      });
    } catch (err) {
      // 同上：布局兜底，不影响功能
    }
  }

  loadSetlists(): void {
    DatabaseHelper.getInstance().queryAllSetlistSummaries().then((list: SetlistSummary[]) => {
      this.summaries = list;
    }).catch((err: Error) => {
      console.error('SetlistPicker: 加载歌单失败:', err.message);
    });
  }

  /** 候选歌单：排除当前歌单（从歌单详情进入时），再按名称关键字过滤 */
  candidates(): SetlistSummary[] {
    const kw: string = this.keyword.trim();
    const exclude: number = this.excludeSetlistId;
    return this.summaries.filter((item: SetlistSummary) =>
    item.setlist.id !== exclude && (kw.length === 0 || item.setlist.name.indexOf(kw) >= 0));
  }

  /** 歌单多到需要翻的时候才显示搜索框 */
  showSearch(): boolean {
    return this.summaries.length > SEARCH_THRESHOLD;
  }

  /** 顶部固定区高度：只有搜索框（歌单多时才出现），「已选 N 首」已移入标题栏副标题 */
  headerHeight(): number {
    return this.showSearch() ? 8 + 38 + 10 : 0;
  }

  showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      // 提示失败不阻断主流程
    }
  }

  /** 加入已有歌单：结果回调给调用方，本页返回上一级 */
  addTo(setlistId: number, name: string): void {
    DatabaseHelper.getInstance().addTracksToSetlist(setlistId, this.recordIds).then((added: number) => {
      this.onDone(added, name);
      this.stack.pop();
    }).catch((err: Error) => {
      console.error('SetlistPicker: 加入歌单失败:', err.message);
      this.onDone(0, name);
      this.stack.pop();
    });
  }

  /** 新建歌单，并把选中的曲目一次性放进去 */
  createAndAdd(name: string): void {
    DatabaseHelper.getInstance().insertSetlist(name).then((newId: number) => {
      return DatabaseHelper.getInstance().addTracksToSetlist(newId, this.recordIds);
    }).then((added: number) => {
      this.onDone(added, name);
      this.stack.pop();
    }).catch((err: Error) => {
      console.error('SetlistPicker: 新建歌单失败:', err.message);
      this.onDone(0, name);
      this.stack.pop();
    });
  }

  /** 顶部固定区：只剩搜索框（歌单多到需要翻的时候才出现） */
  @Builder
  headerView() {
    Column() {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(16)
          .fontColor([$r('app.color.app_text_hint')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        TextInput({ placeholder: $r('app.string.setlist_picker_search_placeholder'), text: this.keyword })
          .layoutWeight(1)
          .height(38)
          .backgroundColor(Color.Transparent)
          .fontSize(14)
          .onChange((value: string) => {
            this.keyword = value;
          })
      }
      .width('100%')
      .height(38)
      .padding({ left: 12, right: 12 })
      .backgroundColor($r('app.color.app_bg_card'))
      .borderRadius(8)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 10 })
    .margin({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
    .backgroundColor($r('app.color.app_bg_primary'))
  }

  /**
   * 首行固定为「新建歌单」。
   * 从曲库多选过来时目标歌单常常还不存在，把它放在最上面可以一步直达，
   * 不用先返回歌单页新建、再回来重选一遍。
   */
  @Builder
  newSetlistRow() {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(20)
        .fontColor([$r('app.color.app_brand_blue')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .width(24)
      Text($r('app.string.setlist_new'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_brand_blue'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 14, right: 14 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .onClick(() => {
      this.nameController.open();
    })
  }

  /** 一个可选歌单：名称 + 已有曲目数，整行可点，右侧加号表示"放进去" */
  @Builder
  targetRow(item: SetlistSummary) {
    Row({ space: 12 }) {
      SymbolGlyph($r('sys.symbol.list_bullet'))
        .fontSize(20)
        .fontColor([$r('app.color.app_brand_blue')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .width(24)

      Column({ space: 3 }) {
        Text(item.setlist.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)
        Text($r('app.string.setlist_track_count', item.trackCount))
          .fontSize(12)
          .fontColor($r('app.color.app_text_hint'))
          .alignSelf(ItemAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.plus'))
        .fontSize(18)
        .fontColor([$r('app.color.app_text_hint')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 14, right: 14 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .onClick(() => {
      this.addTo(item.setlist.id, item.setlist.name);
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        Scroll(this.scroller) {
          Column({ space: 10 }) {
            this.newSetlistRow()

            if (this.candidates().length === 0) {
              // 一个歌单都没有 → 提示新建；有歌单但被搜索词过滤空 → 提示没有匹配项
              Text(this.summaries.length === 0
                ? $r('app.string.setlist_picker_empty_hint')
                : $r('app.string.setlist_picker_no_match'))
                .fontSize(13)
                .fontColor($r('app.color.app_text_hint'))
                .textAlign(TextAlign.Center)
                .width('100%')
                .padding({ top: 24, left: 20, right: 20 })
            } else {
              ForEach(this.candidates(), (item: SetlistSummary) => {
                this.targetRow(item)
              }, (item: SetlistSummary) =>
              `${item.setlist.id}|${item.setlist.name}|${item.trackCount}`)
            }
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            bottom: 130,
            // 顶部让出「状态栏 + 标题栏 + 固定头区」，避免首行被压在固定区下面
            top: this.statusBarHeight + TITLE_BAR_HEIGHT + this.headerHeight()
          })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .clipContent(ContentClipMode.SAFE_AREA)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .backgroundColor($r('app.color.app_bg_primary'))

        if (this.showSearch()) {
          this.headerView()
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.action_add_to_set'),
          // 「已选 N 首」放进标题栏副标题，不再单独占一行浮在标题栏下方
          subTitle: $r('app.string.setlist_picker_subtitle', this.recordIds.length)
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
  }
}
