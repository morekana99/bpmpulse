import { HarmonyLevel, harmonyRank, camelotNoteName } from '../utils/MusicTheory';

/** 衔接等级对应的文字资源 */
export function harmonyText(level: number): Resource {
  if (level === HarmonyLevel.SAME) {
    return $r('app.string.harmony_same');
  }
  if (level === HarmonyLevel.PERFECT) {
    return $r('app.string.harmony_perfect');
  }
  if (level === HarmonyLevel.DRAMATIC) {
    return $r('app.string.harmony_dramatic');
  }
  if (level === HarmonyLevel.CLASH) {
    return $r('app.string.harmony_clash');
  }
  return $r('app.string.harmony_unknown');
}

/** 衔接等级对应的前景色（写在白底标签上的强调色） */
export function harmonyColor(level: number): Resource {
  if (level === HarmonyLevel.SAME || level === HarmonyLevel.PERFECT) {
    return $r('app.color.app_accent_green');
  }
  if (level === HarmonyLevel.DRAMATIC) {
    return $r('app.color.app_accent_orange');
  }
  if (level === HarmonyLevel.CLASH) {
    return $r('app.color.app_accent_red');
  }
  return $r('app.color.app_text_hint');
}

/** 能量等级 1-10 对应的颜色 */
export function energyColor(energy: number): Resource {
  if (energy <= 0) {
    return $r('app.color.app_text_hint');
  }
  if (energy <= 3) {
    return $r('app.color.app_accent_green');
  }
  if (energy <= 6) {
    return $r('app.color.app_brand_blue');
  }
  if (energy <= 8) {
    return $r('app.color.app_accent_orange');
  }
  return $r('app.color.app_accent_red');
}

/** 通用小标签 */
@Component
export struct MetaChip {
  @Prop label: ResourceStr = '';
  @Prop chipBg: Resource = $r('app.color.app_chip_bg');
  @Prop chipFg: Resource = $r('app.color.app_text_secondary');
  @Prop fontSize: number = 11;

  build() {
    Text(this.label)
      .fontSize(this.fontSize)
      .fontColor(this.chipFg)
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(this.chipBg)
      .borderRadius(6)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 130 })
  }
}

/** 分区标题 */
@Component
export struct SectionTitle {
  @Prop title: ResourceStr = '';

  build() {
    Row() {
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 18, right: 16, top: 18, bottom: 8 })
  }
}

/** 统计单元格 */
@Component
export struct StatCell {
  @Prop label: ResourceStr = '';
  @Prop value: string = '';

  build() {
    Column() {
      Text(this.value)
        .fontSize(19)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .maxLines(1)
      Text(this.label)
        .fontSize(11)
        .fontColor($r('app.color.app_text_hint'))
        .margin({ top: 3 })
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}

/** 空状态占位 */
@Component
export struct EmptyView {
  @Prop icon: Resource = $r('sys.symbol.music');
  @Prop title: ResourceStr = '';
  @Prop hint: ResourceStr = '';
  @Prop iconSize: number = 56;

  build() {
    Column() {
      SymbolGlyph(this.icon)
        .fontSize(this.iconSize)
        .fontColor([$r('app.color.app_text_hint')])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .opacity(0.45)
        .margin({ bottom: 18 })
      Text(this.title)
        .fontSize(17)
        .fontColor($r('app.color.app_text_hint'))
        .margin({ bottom: 6 })
      Text(this.hint)
        .fontSize(13)
        .fontColor($r('app.color.app_text_hint'))
        .textAlign(TextAlign.Center)
        .padding({ left: 40, right: 40 })
    }
    .width('100%')
    .padding({ top: 60, bottom: 40 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 歌单 BPM 曲线：横轴为曲目顺序，纵轴为该曲 BPM。
 * 用于直观看出整段 Set 的速度走向与突变位置。
 */
@Component
export struct BpmCurveChart {
  @Prop @Watch('onValuesChanged') values: number[] = [];
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);
  private chartWidth: number = 0;
  private chartHeight: number = 0;

  onValuesChanged(): void {
    this.draw();
  }

  private draw(): void {
    const ctx: CanvasRenderingContext2D = this.ctx;
    const w: number = this.chartWidth > 0 ? this.chartWidth : Number(ctx.width);
    const h: number = this.chartHeight > 0 ? this.chartHeight : Number(ctx.height);
    if (w <= 0 || h <= 0 || this.values.length === 0) {
      return;
    }
    ctx.clearRect(0, 0, w, h);

    const padLeft: number = 10;
    const padRight: number = 10;
    const padTop: number = 18;
    const padBottom: number = 14;
    const plotW: number = w - padLeft - padRight;
    const plotH: number = h - padTop - padBottom;

    let min: number = this.values[0];
    let max: number = this.values[0];
    for (let i = 1; i < this.values.length; i++) {
      if (this.values[i] < min) {
        min = this.values[i];
      }
      if (this.values[i] > max) {
        max = this.values[i];
      }
    }
    const span: number = Math.max(max - min, 6);
    min = min - span * 0.15;
    max = max + span * 0.15;

    const points: number[][] = [];
    for (let i = 0; i < this.values.length; i++) {
      const x: number = this.values.length === 1
        ? padLeft + plotW / 2
        : padLeft + (plotW * i) / (this.values.length - 1);
      const y: number = padTop + plotH * (1 - (this.values[i] - min) / (max - min));
      points.push([x, y]);
    }

    ctx.save();
    ctx.strokeStyle = '#1F000000';
    ctx.lineWidth = 1;
    for (let g = 0; g <= 2; g++) {
      const y: number = padTop + (plotH * g) / 2;
      ctx.beginPath();
      ctx.moveTo(padLeft, y);
      ctx.lineTo(padLeft + plotW, y);
      ctx.stroke();
    }
    ctx.restore();

    ctx.save();
    ctx.beginPath();
    ctx.moveTo(points[0][0], padTop + plotH);
    for (let i = 0; i < points.length; i++) {
      ctx.lineTo(points[i][0], points[i][1]);
    }
    ctx.lineTo(points[points.length - 1][0], padTop + plotH);
    ctx.closePath();
    ctx.fillStyle = '#26007DFF';
    ctx.fill();
    ctx.restore();

    ctx.save();
    ctx.strokeStyle = '#007DFF';
    ctx.lineWidth = 2.2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(points[0][0], points[0][1]);
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(points[i][0], points[i][1]);
    }
    ctx.stroke();
    ctx.restore();

    ctx.save();
    for (let i = 0; i < points.length; i++) {
      ctx.fillStyle = '#007DFF';
      ctx.beginPath();
      ctx.arc(points[i][0], points[i][1], 3, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();

    ctx.save();
    ctx.fillStyle = '#99000000';
    ctx.font = '11px sans-serif';
    ctx.textAlign = 'center';
    const step: number = points.length > 8 ? Math.ceil(points.length / 6) : 1;
    for (let i = 0; i < points.length; i += step) {
      ctx.fillText(this.values[i].toString(), points[i][0], points[i][1] - 8);
    }
    ctx.restore();
  }

  build() {
    Column() {
      Canvas(this.ctx)
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.chartWidth = Number(this.ctx.width);
          this.chartHeight = Number(this.ctx.height);
          this.draw();
        })
        .onAreaChange((newValue: Area) => {
          this.chartWidth = Number(newValue.width);
          this.chartHeight = Number(newValue.height);
        })
    }
    .width('100%')
    .height('100%')
  }
}

interface WheelRingLayout {
  letter: string;
  radius: number;
}

interface WheelKeyVM {
  code: string;
  x: number;
  y: number;
  bg: ResourceColor;
  fg: ResourceColor;
  weight: FontWeight;
}

/**
 * Camelot 调性轮盘可视化：内圈 12 个 A（小调）、外圈 12 个 B（大调），按钟面均匀分布。
 * 选中某调性后，和声兼容（SAME/PERFECT）的键以绿色高亮，戏剧性衔接（DRAMATIC）以橙色，
 * 其余为灰色。点击任意键即选中，便于在轮盘上直观规划衔接走向。
 */
@Component
export struct CamelotWheel {
  @Prop selectedKey: string = '';
  onSelect: (code: string) => void = () => {};

  private wheelKeys(): WheelKeyVM[] {
    const result: WheelKeyVM[] = [];
    const layout: WheelRingLayout[] = [
      { letter: 'A', radius: 82 },
      { letter: 'B', radius: 124 }
    ];
    for (let l = 0; l < layout.length; l++) {
      const letter: string = layout[l].letter;
      const radius: number = layout[l].radius;
      for (let n = 1; n <= 12; n++) {
        const code: string = `${n}${letter}`;
        const angle: number = (n / 12) * Math.PI * 2;
        const x: number = 150 + radius * Math.sin(angle) - 20;
        const y: number = 150 - radius * Math.cos(angle) - 20;
        let bg: ResourceColor = $r('app.color.app_bg_primary');
        let fg: ResourceColor = $r('app.color.app_text_secondary');
        let weight: FontWeight = FontWeight.Medium;
        const selected: boolean = this.selectedKey === code;
        if (selected) {
          bg = $r('app.color.app_brand_blue');
          fg = Color.White;
          weight = FontWeight.Bold;
        } else if (this.selectedKey.length > 0) {
          const rank: number = harmonyRank(this.selectedKey, code);
          if (rank === HarmonyLevel.SAME || rank === HarmonyLevel.PERFECT) {
            bg = $r('app.color.app_accent_green');
            fg = Color.White;
          } else if (rank === HarmonyLevel.DRAMATIC) {
            bg = $r('app.color.app_accent_orange');
            fg = Color.White;
          }
        }
        result.push({ code: code, x: x, y: y, bg: bg, fg: fg, weight: weight });
      }
    }
    return result;
  }

  build() {
    Stack() {
      Column({ space: 2 }) {
        Text(this.selectedKey.length > 0 ? this.selectedKey : '--')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
        Text(this.selectedKey.length > 0 ? camelotNoteName(this.selectedKey) : 'Camelot')
          .fontSize(11)
          .fontColor($r('app.color.app_text_hint'))
      }
      ForEach(this.wheelKeys(), (k: WheelKeyVM) => {
        Column() {
          Text(k.code)
            .fontSize(12)
            .fontWeight(k.weight)
            .fontColor(k.fg)
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(k.bg)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .position({ x: k.x, y: k.y })
        .onClick(() => {
          this.onSelect(k.code);
        })
        // 键值必须带上当前选中调性：每个圆片的配色由 selectedKey 决定，
        // 只用 k.code 的话选中变化时 24 个键值都不变，圆片会被复用、高亮不刷新（中心文字却会变）。
      }, (k: WheelKeyVM) => `${k.code}|${this.selectedKey}`)
    }
    .width(300)
    .height(300)
  }
}
