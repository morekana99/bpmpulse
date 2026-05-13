1. 首先，确保你的工程引入了 UIDesignKit 相关的模块。我们需要 HdsTabs、HdsTabsController 以及 hdsMaterial
2.同时，我们定义好 Tab 栏的菜单配置（使用系统 Symbol 图标，支持多色渲染）：
interface MenuItem {
  symbolGlyph: SymbolGlyphModifier;
  symbolGlyph1: SymbolGlyphModifier;
  label: string;
}

const MENU_CONFIG: MenuItem[] = [
  {
    symbolGlyph: new SymbolGlyphModifier($r("sys.symbol.clock"))
      .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([
        $r("sys.color.ohos_id_color_bottom_tab_icon_off"),
        $r("sys.color.ohos_id_color_bottom_tab_icon_auxcolor_off02"),
      ]),
    symbolGlyph1: new SymbolGlyphModifier($r("sys.symbol.clock_fill"))
      .renderingStrategy(SymbolRenderingStrategy.MULTIPLE_COLOR)
      .fontColor([
        $r("app.color.primary_blue"),
        $r("sys.color.ohos_id_color_primary_contrary"),
      ]),
    label: "待取",
  },
  // ... 其他 Tab 项配置
];

3.在绝大多数场景下，我们推荐使用 ADAPTIVE（自适应）模式。系统会根据当前设备的算力和性能状态，自动为你选择最佳的光效表现，保证流畅度的同时达到最优的视觉效果。
@Entry
@Component
struct Index {
  private hdsTabsController: HdsTabsController = new HdsTabsController();

  build() {
    HdsTabs({ controller: this.hdsTabsController }) {
      ForEach(MENU_CONFIG, (item: MenuItem, index: number) => {
        TabContent() {
          // 这里放你的页面内容，比如 PackagesPage()
        }
        .tabBar(new BottomTabBarStyle({
          normal: item.symbolGlyph,
          selected: item.symbolGlyph1
        }, item.label).labelStyle({
          selectedColor: $r('app.color.primary_blue') // 设置文字高亮色
        }))
      })
    }
    .barOverlap(true) // 允许内容延伸到 Tab 栏底部
    .barPosition(BarPosition.End)
    // 核心配置：开启悬浮样式并设置自适应材质
    .barFloatingStyle({
      barBottomMargin: 28,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
  }
}
