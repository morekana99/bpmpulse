import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { HdsNavDestination, HdsNavDestinationTitleMode, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { SongRecord, songRecordKey } from '../models/SongRecord';
import { TrackPickerParam } from '../models/Setlist';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { EmptyView, MetaChip, harmonyColor, harmonyText } from '../components/DjWidgets';
import { camelotNoteName, harmonyRank } from '../utils/MusicTheory';
import { bpmDiffPercent, formatDuration, normalizeBpm } from '../utils/DjUtils';

/** HDS 导航标题栏（MINI 模式）高度，用于让顶部悬浮工具条避开状态栏与标题栏 */
const TITLE_BAR_HEIGHT: number = 56;

const FILTER_ALL: number = 0;
const FILTER_BPM: number = 1;
const FILTER_KEY: number = 2;

/** BPM 相近的判定容差（百分比），与常见混音台 pitch 范围一致 */
const BPM_TOLERANCE: number = 6;

/**
 * 选曲页：从曲库里挑歌加入歌单。
 * 提供「BPM 相近」「调性兼容」两个筛选，直接服务于 DJ 排歌时的接续需求。
 */
@Component
export struct TrackPickerPage {
  setlistId: number = 0;
  anchorBpm: number = 0;
  anchorKey: string = '';
  stack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  @State keyword: string = '';
  @State filterMode: number = FILTER_ALL;
  @State all: SongRecord[] = [];
  @State existingIds: number[] = [];
  @State selected: number[] = [];
  @State statusBarHeight: number = 0;

  aboutToAppear(): void {
    this.loadData();
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

  loadData(): void {
    const db: DatabaseHelper = DatabaseHelper.getInstance();
    db.queryAll().then((data: SongRecord[]) => {
      this.all = data;
    }).catch((err: Error) => {
      console.error('加载曲库失败:', err.message);
    });
    db.querySetlistTracks(this.setlistId).then((tracks) => {
      const ids: number[] = [];
      for (let i = 0; i < tracks.length; i++) {
        ids.push(tracks[i].recordId);
      }
      this.existingIds = ids;
    }).catch((err: Error) => {
      console.error('加载歌单曲目失败:', err.message);
    });
  }

  candidates(): SongRecord[] {
    let list: SongRecord[] = this.all.filter((r: SongRecord) => this.existingIds.indexOf(r.id) < 0);
    const kw: string = this.keyword.trim();
    if (kw.length > 0) {
      list = list.filter((r: SongRecord) =>
        r.songName.indexOf(kw) >= 0 || r.artistName.indexOf(kw) >= 0 || r.genre.indexOf(kw) >= 0);
    }
    if (this.filterMode === FILTER_BPM && this.anchorBpm > 0) {
      list = list.filter((r: SongRecord) => bpmDiffPercent(this.anchorBpm, r.bpm) <= BPM_TOLERANCE);
    } else if (this.filterMode === FILTER_KEY && this.anchorKey.length > 0) {
      list = list.filter((r: SongRecord) => {
        const rank: number = harmonyRank(this.anchorKey, r.musicalKey);
        return rank >= 0 && rank <= 1;
      });
    }
    const anchor: number = this.anchorBpm;
    const anchorKey: string = this.anchorKey;
    const copy: SongRecord[] = [...list];
    copy.sort((a: SongRecord, b: SongRecord) => {
      const ra: number = anchorKey.length > 0 ? harmonyRank(anchorKey, a.musicalKey) : 0;
      const rb: number = anchorKey.length > 0 ? harmonyRank(anchorKey, b.musicalKey) : 0;
      if (ra !== rb) {
        return ra - rb;
      }
      if (anchor > 0) {
        return bpmDiffPercent(anchor, a.bpm) - bpmDiffPercent(anchor, b.bpm);
      }
      return normalizeBpm(a.bpm) - normalizeBpm(b.bpm);
    });
    return copy;
  }

  anchorText(): ResourceStr {
    if (this.anchorBpm <= 0 && this.anchorKey.length === 0) {
      return $r('app.string.picker_anchor_empty');
    }
    if (this.anchorKey.length > 0) {
      return $r('app.string.picker_anchor_key', this.anchorBpm, this.anchorKey);
    }
    return $r('app.string.picker_anchor', this.anchorBpm);
  }

  toggle(recordId: number): void {
    const next: number[] = [...this.selected];
    const idx: number = next.indexOf(recordId);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(recordId);
    }
    this.selected = next;
  }

  showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      // 提示失败不阻断主流程
    }
  }

  confirm(): void {
    if (this.selected.length === 0) {
      this.showToast($r('app.string.toast_no_selection'));
      return;
    }
    DatabaseHelper.getInstance().addTracksToSetlist(this.setlistId, this.selected).then((added: number) => {
      this.showToast($r('app.string.toast_added_tracks', added));
      this.stack.pop();
    }).catch((err: Error) => {
      console.error('加入歌单失败:', err.message);
    });
  }

  @Builder
  filterChip(label: Resource, mode: number) {
    Text(label)
      .fontSize(13)
      .fontWeight(this.filterMode === mode ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.filterMode === mode ? Color.White : $r('app.color.app_text_secondary'))
      .padding({ left: 14, right: 14, top: 6, bottom: 6 })
      .backgroundColor(this.filterMode === mode ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_card'))
      .borderRadius(999)
      .onClick(() => {
        this.filterMode = mode;
      })
  }

  @Builder
  trackRow(record: SongRecord) {
    Row() {
      Checkbox({ name: record.id.toString() })
        .select(this.selected.indexOf(record.id) >= 0)
        .selectedColor($r('app.color.app_brand_blue'))
        .width(22)
        .height(22)
        .margin({ right: 12 })
        .alignSelf(ItemAlign.Center)
        .hitTestBehavior(HitTestMode.None)

      Column({ space: 3 }) {
        Row() {
          Text(record.songName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.app_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .flexShrink(1)
            .alignSelf(ItemAlign.Start)
          Text(record.bpm > 0 ? record.bpm.toString() : '--')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_brand_blue'))
            .margin({ left: 10 })
        }
        .width('100%')

        Row({ space: 6 }) {
          Text(record.artistName)
            .fontSize(12)
            .fontColor($r('app.color.app_text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 130 })
          if (record.musicalKey.length > 0) {
            MetaChip({ label: `${record.musicalKey} ${camelotNoteName(record.musicalKey)}` })
          }
          if (record.genre.length > 0) {
            MetaChip({ label: record.genre })
          }
          Blank()
          Text(formatDuration(record.durationSec))
            .fontSize(11)
            .fontColor($r('app.color.app_text_hint'))
        }
        .width('100%')

        if (this.anchorBpm > 0 || this.anchorKey.length > 0) {
          Row({ space: 8 }) {
            if (this.anchorBpm > 0) {
              Text(`Δ${bpmDiffPercent(this.anchorBpm, record.bpm).toFixed(1)}%`)
                .fontSize(11)
                .fontColor($r('app.color.app_text_hint'))
            }
            if (this.anchorKey.length > 0) {
              Text(harmonyText(harmonyRank(this.anchorKey, record.musicalKey)))
                .fontSize(11)
                .fontColor(harmonyColor(harmonyRank(this.anchorKey, record.musicalKey)))
            }
          }
          .width('100%')
          .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12, left: 14, right: 14 })
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
    .onClick(() => {
      this.toggle(record.id);
    })
  }

  build() {
    HdsNavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.candidates().length === 0) {
          Column() {
            EmptyView({
              icon: $r('sys.symbol.magnifyingglass'),
              title: $r('app.string.picker_empty'),
              hint: $r('app.string.picker_empty_hint')
            })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.app_bg_primary'))
        } else {
          Scroll(this.scroller) {
            Column({ space: 10 }) {
              ForEach(this.candidates(), (record: SongRecord) => {
                this.trackRow(record)
              }, (record: SongRecord) => songRecordKey(record))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 132 + this.statusBarHeight + TITLE_BAR_HEIGHT, bottom: 130 })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.Top)
          .clipContent(ContentClipMode.SAFE_AREA)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .backgroundColor($r('app.color.app_bg_primary'))
        }

        Column({ space: 10 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([$r('app.color.app_text_hint')])
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
            TextInput({ placeholder: $r('app.string.picker_search_placeholder'), text: this.keyword })
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

          Row({ space: 8 }) {
            this.filterChip($r('app.string.picker_filter_all'), FILTER_ALL)
            this.filterChip($r('app.string.picker_filter_bpm'), FILTER_BPM)
            this.filterChip($r('app.string.picker_filter_key'), FILTER_KEY)
          }
          .width('100%')

          Text(this.anchorText())
            .fontSize(12)
            .fontColor($r('app.color.app_text_hint'))
            .alignSelf(ItemAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 10 })
        .margin({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
        .backgroundColor($r('app.color.app_bg_primary'))

        if (this.selected.length > 0) {
          Row() {
            Button($r('app.string.picker_confirm', this.selected.length), { type: ButtonType.Capsule })
              .width('100%')
              .height(48)
              .backgroundColor($r('app.color.app_brand_blue'))
              .fontColor(Color.White)
              .onClick(() => {
                this.confirm();
              })
          }
          .width('100%')
          .height(48)
          .padding({ left: 16, right: 16 })
          .position({ x: 0, y: '100%' })
          .translate({ y: -164 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .titleBar({
      content: {
        title: { mainTitle: $r('app.string.picker_title') }
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
