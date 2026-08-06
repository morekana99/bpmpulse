import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, ScrollEffectType, hdsMaterial, TextStyleMode } from '@kit.UIDesignKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { BpmPage } from './BpmPage';
import { RecordPage } from './RecordPage';
import { SearchPage } from './SearchPage';
import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';

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
        // 多选操作图标也用系统符号：SINGLE 渲染为扁平纯色，随深浅色适配
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
        // 使用系统符号图标（SymbolGlyph）：renderingStrategy(SINGLE) 渲染为扁平纯色矢量图标，
        // 随深浅色自动适配；fontColor 传入颜色数组，选中时切换品牌蓝实现变色。
        // 图标与下方文字在 Column 内均水平居中，共用同一中心轴保证对齐。
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
      }
    })
  }
}

@Entry
@Component
struct Index {
  private tabsController: HdsTabsController = new HdsTabsController();
  @StorageLink('currentTabIndex') currentTabIndex: number = 0;
  @StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
  @StorageLink('multiSelectIds') multiSelectIds: number[] = [];
  @StorageLink('allRecordIds') allRecordIds: number[] = [];
  @StorageLink('isSearching') isSearching: boolean = false;

  private scrollerForBpm: Scroller = new Scroller();
  private scrollerForRecord: Scroller = new Scroller();

  onBackPress(): boolean {
    if (this.isSearching) {
      this.getUIContext()?.animateTo({ duration: 300, curve: Curve.EaseInOut }, () => {
        AppStorage.setOrCreate('isSearching', false);
      });
      return true;
    }
    if (this.isMultiSelectMode) {
      AppStorage.setOrCreate('isMultiSelectMode', false);
      AppStorage.setOrCreate('multiSelectIds', [] as number[]);
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
        if (this.allRecordIds && this.allRecordIds.length > 0) {
          AppStorage.setOrCreate('multiSelectIds', [...this.allRecordIds]);
        }
      }
    }
  }

  @Builder
  bpmTabBar() {
    TabBarItem({
      idx: 0,
      icon: $r('sys.symbol.music_fill'),
      label: $r('app.string.tab_bpm'),
      multiIcon: $r('sys.symbol.trash'),
      multiLabel: $r('app.string.dialog_delete'),
      multiAction: (): void => this.deleteSelectedRecords()
    })
  }

  @Builder
  recordTabBar() {
    TabBarItem({
      idx: 1,
      icon: $r('sys.symbol.heart_fill'),
      label: $r('app.string.tab_record'),
      multiIcon: $r('sys.symbol.arrowshape_turn_up_right'),
      multiLabel: $r('app.string.share'),
      multiAction: (): Promise<void> => this.shareSelectedRecords()
    })
  }

  toggleMultiSelect(): void {
    if (this.isMultiSelectMode) {
      AppStorage.setOrCreate('isMultiSelectMode', false);
      AppStorage.setOrCreate('multiSelectIds', [] as number[]);
    } else {
      AppStorage.setOrCreate('isMultiSelectMode', true);
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
            AppStorage.setOrCreate('recordsNeedRefresh', Date.now());
            try {
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_deleted_count', rows), duration: 2000 });
            } catch (error) {
              // TODO: Implement error handling.
            }
          }).catch((err: Error) => {
            console.error('删除记录失败:', err.message, JSON.stringify(err));
            try {
              this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_delete_failed'), duration: 2000 });
            } catch (error) {
              // TODO: Implement error handling.
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
      const selectedRecords = allRecords.filter(r => ids.includes(r.id));

      let text = 'BPM记录\n' + '='.repeat(36) + '\n\n';
      selectedRecords.forEach((record, index) => {
        const date = new Date(record.timestamp);
        const timeStr = `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')} ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
        text += `【${index + 1}】${record.songName} - ${record.artistName}\n`;
        text += `     BPM: ${record.bpm}  |  点击: ${record.tapCount}次  |  间隔: ${record.averageInterval.toFixed(2)}秒\n`;
        text += `     时间: ${timeStr}\n\n`;
      });
      text += '='.repeat(36) + '\n';
      text += `导出时间: ${new Date().toLocaleString()}\n`;

      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const fileName = `BPM记录_${Date.now()}.txt`;
      const filePath = `${context.cacheDir}/${fileName}`;
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);

      const uri = fileUri.getUriFromPath(filePath);
      const shareTitle: string = context.resourceManager.getStringSync($r('app.string.share_sheet_title').id);
      const descRes: Resource = selectedRecords.length === 1 ? $r('app.string.share_sheet_desc_one') : $r('app.string.share_sheet_desc_other');
      const shareDesc: string = context.resourceManager.getStringSync(descRes.id, selectedRecords.length);
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.TEXT,
        uri: uri,
        title: shareTitle,
        description: shareDesc
      });

      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).catch(() => {
        // TODO: Implement error handling.
      });

    } catch (err) {
      console.error('分享失败:', JSON.stringify(err));
      try {
        this.getUIContext().getPromptAction().showToast({ message: $r('app.string.toast_share_failed'), duration: 2000 });
      } catch (error) {
        // TODO: Implement error handling.
      }
    }
  }

  build() {
    // Stack 常驻主树方案：主页面（含 HdsTabs 底栏）始终存在、不被销毁重建，
    // 搜索页作为顶层覆盖层叠加。避免 HdsTabs 底栏 ADAPTIVE 材质在重建时重新采样背景引发闪烁。
    Stack() {
      // 底层：常驻主页面
      HdsNavigation() {
        HdsTabs({ controller: this.tabsController, index: this.currentTabIndex }) {
          TabContent() {
            BpmPage({ scroller: this.scrollerForBpm })
          }
          .tabBar(this.bpmTabBar)

          TabContent() {
            RecordPage({ scroller: this.scrollerForRecord })
          }
          .tabBar(this.recordTabBar)
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
          title: this.currentTabIndex === 0
            ? { mainTitle: '' }
            : { mainTitle: !this.isMultiSelectMode ? $r('app.string.title_song_info') : (this.multiSelectIds.length === 0 ? $r('app.string.multiselect_none') : $r('app.string.multiselect_selected', this.multiSelectIds.length)) },
          menu: this.currentTabIndex === 1 ? {
            value: [
              {
                content: {
                  label: this.isMultiSelectMode ? (this.isAllSelected() ? $r('app.string.multiselect_deselect_all') : $r('app.string.multiselect_select_all')) : $r('app.string.multiselect_multi'),
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
      .bindToScrollable([this.scrollerForBpm, this.scrollerForRecord])
      .hideBackButton(!(this.isMultiSelectMode || this.isSearching))
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      // 搜索打开时底层不响应触摸，避免点击穿透到被覆盖的主页面
      .hitTestBehavior(this.isSearching ? HitTestMode.None : HitTestMode.Default)

      // 顶层：搜索覆盖层（仅搜索时显示，进入淡入放大、退出反向淡出缩小，主页面全程不销毁）
      if (this.isSearching) {
        SearchPage()
          .transition(
            TransitionEffect.opacity(0)
              .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }))
              .animation({ duration: 320, curve: Curve.Friction })
          )
      }
    }
    .width('100%')
    .height('100%')
  }
}
