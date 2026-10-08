import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, ScrollEffectType, hdsMaterial, TextStyleMode } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { SongRecord } from '../models/SongRecord';
import { SetlistDetailParam, SetlistPickerParam, TrackPickerParam } from '../models/Setlist';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { buildLibraryText } from '../utils/ExportText';
import { shareTextFile } from '../utils/ShareUtils';
import { BpmPage } from './BpmPage';
import { RecordPage } from './RecordPage';
import { SetlistPage } from './SetlistPage';
import { SetlistDetailPage } from './SetlistDetailPage';
import { TrackPickerPage } from './TrackPickerPage';
import { SetlistPickerPage } from './SetlistPickerPage';
import { ToolsPage } from './ToolsPage';

@Component
struct TabBarItem {
  @StorageLink('currentTabIndex') currentTabIndex: number = 0;
  @StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
  @Prop idx: number = 0;
  @Prop icon: Resource = $r('sys.symbol.music_fill');
  @Prop label: ResourceStr = '';
  @Prop multiIcon: Resource = $r('sys.symbol.trash');
  @Prop multiLabel: ResourceStr = '';
  multiAction?: () => void;

  build() {
    Column({ space: 2 }) {
      if (this.isMultiSelectMode) {
        // 多选模式下，tab 项直接切换为操作按钮，复用 HDS tab 栏位置，而不是新增独立栏
        SymbolGlyph(this.multiIcon)
          .fontSize(24)
          .fontColor([$r('app.color.app_text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        Text(this.multiLabel)
          .fontSize(11)
          .lineHeight(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(24)
          .fontColor([this.idx === this.currentTabIndex ? $r('app.color.app_brand_blue') : $r('app.color.app_text_primary')])
          .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        Text(this.label)
          .fontSize(11)
          .lineHeight(14)
          .fontWeight(this.idx === this.currentTabIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.idx === this.currentTabIndex ? $r('app.color.app_brand_blue') : $r('app.color.app_text_primary'))
          .maxLines(1)
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(this.isMultiSelectMode ? HitTestMode.Block : HitTestMode.Default)
    .onClick(() => {
      if (this.isMultiSelectMode && this.multiAction) {
        this.multiAction();
      } else {
        AppStorage.setOrCreate('currentTabIndex', this.idx);
      }
    })
  }
}

@Entry
@Component
struct Index {
  private tabsController: HdsTabsController = new HdsTabsController();
  navPathStack: NavPathStack = new NavPathStack();
  @StorageLink('currentTabIndex') currentTabIndex: number = 0;
  @StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
  @StorageLink('multiSelectIds') multiSelectIds: number[] = [];
  @StorageLink('allRecordIds') allRecordIds: number[] = [];
  @StorageLink('isSearching') isSearching: boolean = false;

  private scrollerForBpm: Scroller = new Scroller();
  private scrollerForRecord: Scroller = new Scroller();
  private scrollerForSetlist: Scroller = new Scroller();
  private scrollerForTools: Scroller = new Scroller();
  private scrollerForRecordMS1: Scroller = new Scroller();
  private scrollerForRecordMS2: Scroller = new Scroller();
  private scrollerForRecordMS3: Scroller = new Scroller();

  onBackPress(): boolean {
    if (this.navPathStack.size() > 0) {
      this.navPathStack.pop();
      return true;
    }
    if (this.isSearching) {
      this.getUIContext()?.animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        AppStorage.setOrCreate('isSearching', false);
      });
      return true;
    }
    if (this.isMultiSelectMode) {
      AppStorage.setOrCreate('isMultiSelectMode', false);
      AppStorage.setOrCreate('multiSelectIds', [] as number[]);
      AppStorage.setOrCreate('currentTabIndex', 1);
      return true;
    }
    return false;
  }

  aboutToAppear(): void {
    AppStorage.setOrCreate('currentTabIndex', 0);
    AppStorage.setOrCreate('isMultiSelectMode', false);
    AppStorage.setOrCreate('multiSelectIds', [] as number[]);
    AppStorage.setOrCreate('isSearching', false);
    DatabaseHelper.getInstance().queryAll().then((data: SongRecord[]) => {
      AppStorage.setOrCreate('allRecordIds', data.map(r => r.id));
    }).catch((err: Error) => {
      console.error('Index: 加载记录ID失败:', err.message);
    });
  }

  isAllSelected(): boolean {
    if (!this.allRecordIds || !this.multiSelectIds) {
      return false;
    }
    if (this.allRecordIds.length === 0 || this.multiSelectIds.length === 0) {
      return false;
    }
    return this.allRecordIds.every(id => this.multiSelectIds.includes(id));
  }

  multiSelectAction(): void {
    if (!this.isMultiSelectMode) {
      AppStorage.setOrCreate('isMultiSelectMode', true);
    } else {
      if (this.isAllSelected()) {
        AppStorage.setOrCreate('multiSelectIds', []);
      } else {
        AppStorage.setOrCreate('multiSelectIds', [...this.allRecordIds]);
      }
    }
  }

  deleteSelectedRecords() {
    const ids: number[] = AppStorage.get<number[]>('multiSelectIds') || [];
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
            AppStorage.setOrCreate('isMultiSelectMode', false);
            AppStorage.setOrCreate('multiSelectIds', [] as number[]);
            AppStorage.setOrCreate('currentTabIndex', 1);
            AppStorage.setOrCreate('recordsNeedRefresh', Date.now());
            try {
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_deleted_count', rows), duration: 2000 });
            } catch (error) {
              // 提示失败不阻断主流程
            }
          }).catch((err: Error) => {
            console.error('删除记录失败:', err.message, JSON.stringify(err));
            try {
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_delete_failed'), duration: 2000 });
            } catch (error) {
              // 提示失败不阻断主流程
            }
          });
        }
      }
    });
  }

  async shareSelectedRecords() {
    const ids: number[] = AppStorage.get<number[]>('multiSelectIds') || [];
    if (ids.length === 0) {
      return;
    }
    try {
      const allRecords = await DatabaseHelper.getInstance().queryAll();
      const selected: SongRecord[] = allRecords.filter((r: SongRecord) => ids.includes(r.id));
      const content: string = buildLibraryText(selected);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const title: string = context.resourceManager.getStringSync($r('app.string.share_sheet_title').id);
      const descRes: Resource = selected.length === 1 ? $r('app.string.share_sheet_desc_one') : $r('app.string.share_sheet_desc_other');
      const description: string = context.resourceManager.getStringSync(descRes.id, selected.length);
      await shareTextFile(context, `BPM记录_${Date.now()}.txt`, content, title, description);
    } catch (err) {
      console.error('分享失败:', JSON.stringify(err));
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_share_failed'), duration: 2000 });
      } catch (error) {
        // 提示失败不阻断主流程
      }
    }
  }

  addToSetlist() {
    const ids: number[] = AppStorage.get<number[]>('multiSelectIds') || [];
    if (ids.length === 0) {
      return;
    }
    // 选歌单是整页（与「选曲目」页对称），歌单多时可整页滚动 + 搜索
    const param: SetlistPickerParam = {
      recordIds: ids,
      excludeSetlistId: -1,
      onDone: (added: number, name: string) => {
        if (added > 0) {
          AppStorage.setOrCreate('isMultiSelectMode', false);
          AppStorage.setOrCreate('multiSelectIds', [] as number[]);
          AppStorage.setOrCreate('currentTabIndex', 1);
          try {
            this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_added_tracks', added), duration: 1800 });
          } catch (error) {
            // 提示失败不阻断主流程
          }
        }
      }
    };
    this.navPathStack.pushPath({ name: 'SetlistPicker', param: param });
  }

  @Builder
  bpmTabBar() {
    TabBarItem({
      idx: 0,
      icon: $r('sys.symbol.waveform'),
      label: $r('app.string.tab_bpm'),
      multiIcon: $r('sys.symbol.trash'),
      multiLabel: $r('app.string.dialog_delete'),
      multiAction: (): void => this.deleteSelectedRecords()
    })
  }

  @Builder
  libraryTabBar() {
    TabBarItem({
      idx: 1,
      icon: $r('sys.symbol.music'),
      label: $r('app.string.tab_library'),
      multiIcon: $r('sys.symbol.arrowshape_turn_up_right'),
      multiLabel: $r('app.string.action_export'),
      multiAction: (): void => { this.shareSelectedRecords(); }
    })
  }

  @Builder
  setlistTabBar() {
    TabBarItem({
      idx: 2,
      icon: $r('sys.symbol.list_bullet'),
      label: $r('app.string.tab_setlist'),
      multiIcon: $r('sys.symbol.plus'),
      multiLabel: $r('app.string.action_add_to_set'),
      multiAction: (): void => this.addToSetlist()
    })
  }

  @Builder
  toolsTabBar() {
    TabBarItem({
      idx: 3,
      icon: $r('sys.symbol.gearshape'),
      label: $r('app.string.tab_tools')
    })
  }

  @Builder
  pageMap(name: string, param: Object) {
    if (name === 'SetlistDetail') {
      SetlistDetailPage({ setlistId: (param as SetlistDetailParam).setlistId, stack: this.navPathStack });
    } else if (name === 'TrackPicker') {
      TrackPickerPage({
        setlistId: (param as TrackPickerParam).setlistId,
        anchorBpm: (param as TrackPickerParam).anchorBpm,
        anchorKey: (param as TrackPickerParam).anchorKey,
        stack: this.navPathStack
      });
    } else if (name === 'SetlistPicker') {
      SetlistPickerPage({
        recordIds: (param as SetlistPickerParam).recordIds,
        excludeSetlistId: (param as SetlistPickerParam).excludeSetlistId,
        onDone: (param as SetlistPickerParam).onDone,
        stack: this.navPathStack
      });
    }
  }

  titleMain(): ResourceStr {
    if (this.isMultiSelectMode) {
      return this.multiSelectIds.length === 0
        ? $r('app.string.multiselect_none')
        : $r('app.string.multiselect_selected', this.multiSelectIds.length);
    }
    if (this.currentTabIndex === 1) {
      if (this.isMultiSelectMode) {
        return this.multiSelectIds.length === 0
          ? $r('app.string.multiselect_none')
          : $r('app.string.multiselect_selected', this.multiSelectIds.length);
      }
      return $r('app.string.title_library');
    }
    if (this.currentTabIndex === 2) {
      return $r('app.string.title_setlist');
    }
    if (this.currentTabIndex === 3) {
      return $r('app.string.title_tools');
    }
    return '';
  }

  build() {
    HdsNavigation(this.navPathStack) {
      HdsTabs({ controller: this.tabsController, index: this.isMultiSelectMode ? 0 : this.currentTabIndex }) {
        if (this.isMultiSelectMode) {
          // 多选模式：底部栏变为 3 个官方 HDS tab 操作按钮（删除 / 添加歌单 / 导出），栏长相应缩短为 3
          TabContent() {
            RecordPage({ scroller: this.scrollerForRecordMS1, stack: this.navPathStack })
          }
          .tabBar(this.bpmTabBar)

          TabContent() {
            RecordPage({ scroller: this.scrollerForRecordMS2, stack: this.navPathStack })
          }
          .tabBar(this.setlistTabBar)

          TabContent() {
            RecordPage({ scroller: this.scrollerForRecordMS3, stack: this.navPathStack })
          }
          .tabBar(this.libraryTabBar)
        } else {
          TabContent() {
            BpmPage({ scroller: this.scrollerForBpm })
          }
          .tabBar(this.bpmTabBar)

          TabContent() {
            RecordPage({ scroller: this.scrollerForRecord, stack: this.navPathStack })
          }
          .tabBar(this.libraryTabBar)

          TabContent() {
            SetlistPage({ stack: this.navPathStack, scroller: this.scrollerForSetlist })
          }
          .tabBar(this.setlistTabBar)

          TabContent() {
            ToolsPage({ stack: this.navPathStack, scroller: this.scrollerForTools })
          }
          .tabBar(this.toolsTabBar)
        }
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .animationDuration(0)
      .scrollable(false)
      .onChange((index: number) => {
        AppStorage.set('currentTabIndex', index);
      })
      .barFloatingStyle({
        barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        barOpacity: 0.99,
        lightColor: '#4CFFFFFF',
        adaptToHandedness: true,
        gradientMask: {
          maskColor: '#00FFFFFF',
          maskHeight: 92
        }
      })
    }
    .mode(NavigationMode.Stack)
    .titleBar({
      content: {
        title: { mainTitle: this.titleMain() },
        menu: this.isMultiSelectMode || this.currentTabIndex === 1 ? {
          value: [
            {
              content: {
                label: this.isMultiSelectMode
                  ? (this.isAllSelected() ? $r('app.string.multiselect_deselect_all') : $r('app.string.multiselect_select_all'))
                  : $r('app.string.multiselect_multi'),
                type: TextStyleMode.NORMAL,
                action: (): void => { this.multiSelectAction(); }
              }
            }
          ],
          maxCount: 1
        } : undefined
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
    .titleMode(HdsNavigationTitleMode.MINI)
    // BPM 页（首页）自带大标题，顶部那条空 HDS 标题栏只是白占一条，按当前 tab 隐藏；
    // 曲库 / 歌单 / 工具 以及多选模式不变（多选时三个 tab 都是曲库页，需要标题栏显示已选数量与全选按钮）。
    .hideTitleBar(!this.isMultiSelectMode && this.currentTabIndex === 0, false)
    .navDestination(this.pageMap)
    .bindToScrollable([this.scrollerForBpm, this.scrollerForRecord, this.scrollerForSetlist, this.scrollerForTools])
    .hideBackButton(!(this.isMultiSelectMode || this.isSearching || this.navPathStack.size() > 0))
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
