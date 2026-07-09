import { HdsNavigation, HdsNavigationTitleMode, HdsTabs, HdsTabsController, HdsNavigationMenuContentOptions, ScrollEffectType, hdsMaterial, TextStyleMode } from '@kit.UIDesignKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { BpmPage } from './BpmPage';
import { RecordPage } from './RecordPage';
import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';

@Component
struct TabBarItem {
  @StorageLink('currentTabIndex') currentTabIndex: number = 0;
  @StorageLink('isMultiSelectMode') isMultiSelectMode: boolean = false;
  @Prop idx: number = 0;
  @Prop icon: string = '';
  @Prop label: string = '';
  @Prop multiIcon: string = '';
  @Prop multiLabel: string = '';
  multiAction?: () => void;

  build() {
    Column({ space: 2 }) {
      if (this.isMultiSelectMode) {
        Text(this.multiIcon)
          .fontSize(22)
          .lineHeight(24)
          .fontColor($r('app.color.app_text_primary'))
        Text(this.multiLabel)
          .fontSize(11)
          .lineHeight(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
      } else {
        Text(this.icon)
          .fontSize(22)
          .lineHeight(24)
          .fontColor(this.idx === this.currentTabIndex ? $r('app.color.app_brand_blue') : $r('app.color.app_text_hint'))
        Text(this.label)
          .fontSize(11)
          .lineHeight(14)
          .fontWeight(this.idx === this.currentTabIndex ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.idx === this.currentTabIndex ? $r('app.color.app_brand_blue') : $r('app.color.app_text_hint'))
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

  private scrollerForBpm: Scroller = new Scroller();
  private scrollerForRecord: Scroller = new Scroller();

  onBackPress(): boolean {
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
      icon: '\u266A',
      label: 'BPM',
      multiIcon: '\u2296',
      multiLabel: '删除',
      multiAction: (): void => this.deleteSelectedRecords()
    })
  }

  @Builder
  recordTabBar() {
    TabBarItem({
      idx: 1,
      icon: '\u2630',
      label: '记录',
      multiIcon: '\u2191',
      multiLabel: '分享',
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
    AlertDialog.show({
      title: '确认删除',
      message: `确定要删除选中的 ${ids.length} 条记录吗？\n此操作不可恢复。`,
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        fontColor: '#007DFF',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: '#E84040',
        action: () => {
          DatabaseHelper.getInstance().deleteByIds(ids).then((rows: number) => {
            AppStorage.setOrCreate('isMultiSelectMode', false);
            AppStorage.setOrCreate('multiSelectIds', [] as number[]);
            AppStorage.setOrCreate('recordsNeedRefresh', Date.now());
            promptAction.showToast({ message: `已删除 ${rows} 条记录`, duration: 2000 });
          }).catch((err: Error) => {
            console.error('删除记录失败:', err.message, JSON.stringify(err));
            promptAction.showToast({ message: '删除失败，请重试', duration: 2000 });
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

      const context = getContext(this) as common.UIAbilityContext;
      const fileName = `BPM记录_${Date.now()}.txt`;
      const filePath = `${context.cacheDir}/${fileName}`;
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(file.fd, text);
      fs.closeSync(file);

      const uri = fileUri.getUriFromPath(filePath);
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.TEXT,
        uri: uri,
        title: 'BPM记录',
        description: `共 ${selectedRecords.length} 条BPM记录`
      });

      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      });

    } catch (err) {
      console.error('分享失败:', JSON.stringify(err));
      promptAction.showToast({ message: '分享失败', duration: 2000 });
    }
  }

  build() {
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
          : { mainTitle: !this.isMultiSelectMode ? '歌曲信息' : (this.multiSelectIds.length === 0 ? '未选择' : `已选择${this.multiSelectIds.length}项`) },
        menu: this.currentTabIndex === 1 ? {
          value: [
            {
              content: {
                label: this.isMultiSelectMode ? (this.isAllSelected() ? '取消全选' : '全选') : '多选',
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
    .hideBackButton(!this.isMultiSelectMode)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
