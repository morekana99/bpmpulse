import { window, uiMaterial } from '@kit.ArkUI';
import { HdsNavigation, HdsNavigationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { RecentSearchStore } from '../database/RecentSearchStore';

@Component
export struct SearchPage {
  private searchController: SearchController = new SearchController();
  @State keyword: string = '';
  @State recentSearches: string[] = [];
  @State results: SongRecord[] = [];

  // 最近搜索条目错落浮现
  @State reveal: boolean = false;
  // 最近搜索编辑模式（点击垃圾桶进入，可逐条删除或清空）
  @State isEditMode: boolean = false;
  // 导航栏总高度（状态栏 + MINI标题栏），供内容区避让，避免被系统状态栏/导航栏遮挡
  @State navBarTop: number = 96;
  // 状态栏高度，供悬浮标题栏顶部定位
  @State statusBarTop: number = 24;

  private resultScroller: Scroller = new Scroller();

  aboutToAppear(): void {
    RecentSearchStore.getInstance().getAll().then((list: string[]) => {
      this.recentSearches = list;
    }).catch(() => {
      this.recentSearches = [];
    });
    // 计算状态栏高度，供内容区避让导航栏
    this.computeNavBarTop();
    // 最近搜索条目错落浮现（页面切换的精美动画由 RecordPage -> SearchPage 过渡负责，此处仅列表内容轻微浮现）
    this.getUIContext()?.animateTo({ duration: 380, curve: Curve.EaseOut }, () => {
      this.reveal = true;
    });
    // 自动聚焦搜索框并弹出软键盘
    setTimeout(() => {
      try {
        this.getUIContext()?.getFocusController().requestFocus('searchInput');
      } catch (e) {
        // 聚焦失败不影响搜索功能
      }
    }, 80);
  }

  private computeNavBarTop(): void {
    try {
      window.getLastWindow(getContext(this)).then((win: window.Window) => {
        const area: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
        const statusBarHeight: number = px2vp(area.topRect.height);
        this.statusBarTop = statusBarHeight;
        // 状态栏 + 标题栏(56vp) + 少量间距
        this.navBarTop = statusBarHeight + 56 + 8;
      }).catch(() => {});
    } catch (e) {
      // 获取窗口信息失败时使用默认值
    }
  }

  closeSearch(): void {
    this.searchController.stopEditing();
    this.isEditMode = false;
    AppStorage.setOrCreate('isSearching', false);
  }

  onKeywordChanged(value: string): void {
    this.isEditMode = false;
    this.keyword = value;
    const kw = value.trim();
    if (kw === '') {
      this.results = [];
      return;
    }
    DatabaseHelper.getInstance().queryByKeywordOrBpm(kw).then((data: SongRecord[]) => {
      this.results = data;
    }).catch((err: Error) => {
      console.error('SearchPage: 搜索失败:', err.message);
      this.results = [];
    });
  }

  commitSearch(value: string): void {
    const kw = value.trim();
    if (kw === '') {
      return;
    }
    this.keyword = kw;
    this.searchController.caretPosition(kw.length);
    this.saveRecent(kw);
    DatabaseHelper.getInstance().queryByKeywordOrBpm(kw).then((data: SongRecord[]) => {
      this.results = data;
    }).catch((err: Error) => {
      console.error('SearchPage: 搜索失败:', err.message);
      this.results = [];
    });
  }

  onRecentItemClick(item: string): void {
    this.keyword = item;
    this.searchController.caretPosition(item.length);
    this.saveRecent(item);
    DatabaseHelper.getInstance().queryByKeywordOrBpm(item).then((data: SongRecord[]) => {
      this.results = data;
    }).catch((err: Error) => {
      console.error('SearchPage: 搜索失败:', err.message);
      this.results = [];
    });
  }

  private saveRecent(kw: string): void {
    RecentSearchStore.getInstance().add(kw).then((list: string[]) => {
      this.recentSearches = list;
    }).catch(() => {});
  }

  deleteRecent(item: string): void {
    RecentSearchStore.getInstance().remove(item).then((list: string[]) => {
      this.recentSearches = list;
    }).catch(() => {});
  }

  clearAllRecent(): void {
    RecentSearchStore.getInstance().clear().then(() => {
      this.recentSearches = [];
      try {
        this.getUIContext().getPromptAction().showToast({ message: '已清空搜索记录', duration: 1500 });
      } catch (e) {
        // 提示失败不影响清空结果
      }
    }).catch(() => {});
  }

  enterEditMode(): void {
    this.isEditMode = true;
  }

  exitEditMode(): void {
    this.isEditMode = false;
  }

  confirmClearAll(): void {
    AlertDialog.show({
      title: '清空搜索记录',
      message: '确定要清空全部最近搜索记录吗？此操作不可恢复。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        fontColor: '#007DFF',
        action: (): void => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: '#E84040',
        action: (): void => {
          this.clearAllRecent();
          this.isEditMode = false;
        }
      }
    });
  }

  @Builder
  searchBarBuilder() {
    // 与返回按钮同处标题栏（stackBuilder）：搜索栏挂载官方 systemMaterial 沉浸光感材质（THIN 薄样式），
    // 获得 HDS 同源的沉浸光感玻璃质感，与标题栏 systemMaterialEffect 材质体系一致；
    // Search 组件完全透明，可编辑，输入内容后右侧自动出现清除按钮。
    Row() {
      Row() {
        Search({ value: this.keyword, placeholder: '搜索歌曲、歌手或BPM', controller: this.searchController })
          .id('searchInput')
          .layoutWeight(1)
          .height(40)
          .backgroundColor(Color.Transparent)
          .searchIcon({ size: 16, color: $r('app.color.app_text_hint') })
          .placeholderColor($r('app.color.app_text_hint'))
          .placeholderFont({ size: 15 })
          .textFont({ size: 15 })
          .fontColor($r('app.color.app_text_primary'))
          .cancelButton({
            style: CancelButtonStyle.INPUT,
            icon: { size: 16, color: $r('app.color.app_text_hint') }
          })
          .onChange((value: string) => {
            this.onKeywordChanged(value);
          })
          .onSubmit((value: string) => {
            this.commitSearch(value);
          })
      }
      .width('100%')
      .height(40)
      .padding({ left: 8, right: 8 })
      .alignItems(VerticalAlign.Center)
      // API 26 沉浸光感：挂载官方 systemMaterial 沉浸材质（THIN 薄样式，官方指定用于搜索框场景），
      // 材质由系统统一接管背景/边框/阴影并随算力与深浅色自适应，无需手写模糊；背景保持透明以透出材质。
      .borderRadius(22)
      .backgroundColor(Color.Transparent)
      .systemMaterial(new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.THIN
      }))
    }
    .width('100%')
    .height('100%')
    // 左侧预留返回按钮空间（HDS 返回键占位约 56vp），避免遮挡
    .padding({ left: 60, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  recentPill(item: string, index: number) {
    Row({ space: 6 }) {
      Text(item)
        .fontSize(14)
        .fontColor($r('app.color.app_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isEditMode) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(14)
          .fontColor([$r('app.color.app_text_hint')])
      }
    }
    // 药丸形态：圆角随内容自适应宽度；编辑模式下右侧更紧凑以容纳叉号
    .padding({ left: 14, right: this.isEditMode ? 10 : 14, top: 8, bottom: 8 })
    .margin({ right: 10, bottom: 10 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(999)
    .onClick(() => {
      if (this.isEditMode) {
        this.deleteRecent(item);
      } else {
        this.onRecentItemClick(item);
      }
    })
    .opacity(this.reveal ? 1 : 0)
    .translate({ y: this.reveal ? 0 : 8 })
    .animation({ duration: 300, curve: Curve.EaseOut, delay: index * 30 })
  }

  @Builder
  recentSection() {
    Column() {
      Row() {
        Text('最近搜索')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary'))
        Blank()
        if (this.recentSearches.length > 0) {
          if (this.isEditMode) {
            // 编辑模式：垃圾桶按钮变为「清空 | 完成」
            Row({ space: 20 }) {
              Text('清空')
                .fontSize(14)
                .fontColor($r('app.color.app_brand_blue'))
                .onClick(() => {
                  this.confirmClearAll();
                })
              Text('完成')
                .fontSize(14)
                .fontColor($r('app.color.app_text_primary'))
                .onClick(() => {
                  this.exitEditMode();
                })
            }
          } else {
            // 普通模式：垃圾桶按钮进入编辑模式
            SymbolGlyph($r('sys.symbol.trash'))
              .fontSize(18)
              .fontColor([$r('app.color.app_text_hint')])
              .onClick(() => {
                this.enterEditMode();
              })
          }
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 12 })

      if (this.recentSearches.length === 0) {
        Column() {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(40)
            .fontColor([$r('app.color.app_text_hint')])
            .opacity(0.5)
            .margin({ bottom: 12 })
          Text('暂无搜索记录')
            .fontSize(14)
            .fontColor($r('app.color.app_text_hint'))
        }
        .width('100%')
        .padding({ top: 60 })
        .alignItems(HorizontalAlign.Center)
      } else {
        // 药丸流布局：从左到右、从上到下自动换行，宽度随文字长度自适应
        // 用 Scroll 包裹，并给内部 Flex 设 minHeight:100%，保证内容顶部对齐（不垂直居中），
        // 同时当记录过多超出一屏时仍可滚动
        Scroll() {
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignContent: FlexAlign.Start }) {
            ForEach(this.recentSearches, (item: string, index: number) => {
              this.recentPill(item, index)
            }, (item: string) => item)
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .layoutWeight(1)
        .clipContent(ContentClipMode.SAFE_AREA)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.navBarTop })
    .backgroundColor($r('app.color.app_bg_primary'))
  }

  @Builder
  resultCard(record: SongRecord) {
    Row() {
      Column({ space: 4 }) {
        Text(record.songName)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.app_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(record.artistName)
          .fontSize(13)
          .fontColor($r('app.color.app_text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 2 }) {
        Text(record.bpm.toString())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_brand_blue'))
        Text('BPM')
          .fontSize(11)
          .fontColor($r('app.color.app_text_hint'))
      }
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
  }

  @Builder
  resultsSection() {
    if (this.results.length === 0) {
      Column() {
        SymbolGlyph($r('sys.symbol.magnifyingglass'))
          .fontSize(40)
          .fontColor([$r('app.color.app_text_hint')])
          .opacity(0.5)
          .margin({ bottom: 12 })
        Text('未找到相关记录')
          .fontSize(15)
          .fontColor($r('app.color.app_text_hint'))
        Text(`没有与"${this.keyword}"匹配的歌曲、歌手或BPM`)
          .fontSize(13)
          .fontColor($r('app.color.app_text_hint'))
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ top: this.navBarTop + 40 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.app_bg_primary'))
    } else {
      // 与 RecordPage 一致：Scroll 直接铺满全屏，内容从标题栏下方开始，滚动时卡片穿过标题栏形成沉浸光感
      Scroll(this.resultScroller) {
        Column({ space: 12 }) {
          ForEach(this.results, (record: SongRecord) => {
            this.resultCard(record)
          }, (record: SongRecord) => record.id.toString())
        }
        .width('100%')
        .padding({ top: this.navBarTop + 8, left: 16, right: 16, bottom: 120 })
        .alignItems(HorizontalAlign.Start)
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

  build() {
    // 官方 HDS 沉浸光感导航：标题栏由 HDS 提供 systemMaterialEffect 沉浸材质 + GRADIENT_BLUR 滚动光效，
    // 材质与 RecordPage 一致（ADAPTIVE），保证浅色模式下返回按钮/状态栏为深色图标。
    // 不再手动实现磨砂玻璃效果
    HdsNavigation() {
      if (this.keyword.trim() === '') {
        this.recentSection()
      } else {
        this.resultsSection()
      }
    }
    .titleBar({
      content: {
        title: { mainTitle: '' },
        backIcon: {
          // 不自定义 icon，使用 HDS 默认返回按钮（与 RecordPage 一致的外观/尺寸/位置）
          action: (): void => this.closeSearch()
        },
        // 搜索栏与返回按钮同一行（stackBuilder），融入 HDS 标题栏沉浸材质，
        // 左侧预留返回按钮空间，避免遮挡
        stackBuilder: (): void => this.searchBarBuilder()
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
    .hideBackButton(false)
    .bindToScrollable([this.resultScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
