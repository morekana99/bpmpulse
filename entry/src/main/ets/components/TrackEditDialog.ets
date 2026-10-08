import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SongRecord } from '../models/SongRecord';
import { GENRE_PRESETS, camelotKeys, camelotNoteName, CamelotKeyInfo } from '../utils/MusicTheory';
import { parseDurationInput } from '../utils/DjUtils';

/**
 * 曲目编辑弹窗：新建（测速后保存）与编辑（曲库中修改）共用。
 * 除基础的歌名/歌手/BPM 外，提供 DJ 排歌所需的调性、风格、能量、时长与备注。
 */
@CustomDialog
export struct TrackEditDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  record: SongRecord = {
    id: 0,
    songName: '',
    artistName: '',
    bpm: 0,
    timestamp: 0,
    tapCount: 0,
    averageInterval: 0,
    musicalKey: '',
    genre: '',
    energy: 0,
    durationSec: 0,
    note: ''
  };
  isNew: boolean = true;
  onSave: (record: SongRecord) => void = () => {
  };
  onCancel: () => void = () => {
  };
  @State songName: string = '';
  @State artistName: string = '';
  @State bpmText: string = '';
  @State durationText: string = '';
  @State musicalKey: string = '';
  @State genre: string = '';
  @State energy: number = 0;
  @State note: string = '';
  @State showKeyGrid: boolean = false;
  @State showGenreChips: boolean = false;
  /** 软键盘高度（px）：0 表示键盘未弹出 */
  @State keyboardHeight: number = 0;
  /**
   * 键盘弹出时把弹窗整体下移的比例（相对弹窗自身高度，纯视觉位移、不参与布局）。
   * 键盘弹出时系统会把弹窗容器收缩到键盘上方，弹窗若仍按"容器居中"排布会悬在偏上位置，
   * 这里用一个 GPU 动画的位移把弹窗压到贴近键盘，避免再次引入布局跳变（抽搐）。
   */
  private readonly KEYBOARD_OFFSET: string = '21%';
  private minorKeys: CamelotKeyInfo[] = [];
  private majorKeys: CamelotKeyInfo[] = [];
  private hostWindow: window.Window | null = null;
  private keyboardCallback: ((height: number) => void) | null = null;

  /** 订阅主窗口软键盘高度，仅用于决定是否施加下移位移 */
  private bindKeyboard(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      window.getLastWindow(ctx).then((win: window.Window) => {
        const cb: (height: number) => void = (height: number) => {
          this.keyboardHeight = height;
        };
        this.hostWindow = win;
        this.keyboardCallback = cb;
        win.on('keyboardHeightChange', cb);
      }).catch((err: Error) => {
        console.error('TrackEditDialog: 获取窗口失败，弹窗保持居中:', err.message);
      });
    } catch (err) {
      // 取不到窗口时保持居中布局即可，不阻断编辑流程
    }
  }

  private unbindKeyboard(): void {
    const win: window.Window | null = this.hostWindow;
    const cb: ((height: number) => void) | null = this.keyboardCallback;
    if (win && cb) {
      try {
        win.off('keyboardHeightChange', cb);
      } catch (err) {
        // 取消订阅失败不影响弹窗关闭
      }
    }
    this.hostWindow = null;
    this.keyboardCallback = null;
  }

  aboutToAppear(): void {
    this.bindKeyboard();
    const all: CamelotKeyInfo[] = camelotKeys();
    for (let i = 0; i < all.length; i++) {
      const code: string = all[i].code;
      if (code.slice(code.length - 1) === 'A') {
        this.minorKeys.push(all[i]);
      } else {
        this.majorKeys.push(all[i]);
      }
    }
    this.songName = this.record.songName;
    this.artistName = this.record.artistName;
    this.bpmText = this.record.bpm > 0 ? this.record.bpm.toString() : '';
    this.durationText = this.record.durationSec > 0
      ? `${Math.floor(this.record.durationSec / 60)}:${(this.record.durationSec % 60).toString().padStart(2, '0')}`
      : '';
    this.musicalKey = this.record.musicalKey;
    this.genre = this.record.genre;
    this.energy = this.record.energy > 0 ? this.record.energy : 5;
    this.note = this.record.note;
  }

  aboutToDisappear(): void {
    this.unbindKeyboard();
  }

  canSave(): boolean {
    return this.songName.trim().length > 0;
  }

  buildResult(): SongRecord {
    const parsedBpm: number = parseInt(this.bpmText, 10);
    const result: SongRecord = {
      id: this.record.id,
      songName: this.songName.trim(),
      artistName: this.artistName.trim(),
      bpm: Number.isNaN(parsedBpm) ? 0 : parsedBpm,
      timestamp: this.record.timestamp,
      tapCount: this.record.tapCount,
      averageInterval: this.record.averageInterval,
      musicalKey: this.musicalKey,
      genre: this.genre.trim(),
      energy: this.energy,
      durationSec: parseDurationInput(this.durationText),
      note: this.note.trim()
    };
    if (result.durationSec < 0) {
      result.durationSec = 0;
    }
    return result;
  }

  @Builder
  keyChip(code: string, note: string) {
    Column({ space: 1 }) {
      Text(code)
        .fontSize(13)
        .fontWeight(this.musicalKey === code ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.musicalKey === code ? Color.White : $r('app.color.app_text_primary'))
      Text(note)
        .fontSize(10)
        .fontColor(this.musicalKey === code ? Color.White : $r('app.color.app_text_hint'))
    }
    .width(46)
    .padding({ top: 6, bottom: 6 })
    .borderRadius(8)
    .backgroundColor(this.musicalKey === code ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_card'))
    .alignItems(HorizontalAlign.Center)
    .margin({ right: 6 })
    .onClick(() => {
      this.musicalKey = this.musicalKey === code ? '' : code;
    })
  }

  @Builder
  keyRow(keys: CamelotKeyInfo[]) {
    Row() {
      ForEach(keys, (info: CamelotKeyInfo) => {
        this.keyChip(info.code, info.name)
      }, (info: CamelotKeyInfo) => info.code)
    }
    .margin({ bottom: 6 })
  }

  @Builder
  fieldLabel(text: Resource) {
    Text(text)
      .fontSize(12)
      .fontColor($r('app.color.app_text_hint'))
      .margin({ bottom: 6, top: 10 })
      .alignSelf(ItemAlign.Start)
  }

  build() {
    Column() {
      Scroll() {
        Column() {
          Text(this.isNew ? $r('app.string.bpm_save_info') : $r('app.string.song_edit_title'))
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .margin({ top: 20, bottom: 12 })

          TextInput({ placeholder: $r('app.string.song_name_placeholder'), text: this.songName })
            .width('100%')
            .height(46)
            .backgroundColor($r('app.color.app_bg_card'))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .defaultFocus(this.isNew)
            .onChange((value: string) => {
              this.songName = value;
            })

          TextInput({ placeholder: $r('app.string.artist_placeholder'), text: this.artistName })
            .width('100%')
            .height(46)
            .backgroundColor($r('app.color.app_bg_card'))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .margin({ top: 10 })
            .onChange((value: string) => {
              this.artistName = value;
            })

          Row({ space: 10 }) {
            Column() {
              this.fieldLabel($r('app.string.field_bpm'))
              TextInput({ placeholder: '128', text: this.bpmText })
                .height(46)
                .type(InputType.Number)
                .backgroundColor($r('app.color.app_bg_card'))
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.bpmText = value;
                })
            }
            .layoutWeight(1)

            Column() {
              this.fieldLabel($r('app.string.field_duration'))
              TextInput({ placeholder: $r('app.string.duration_placeholder'), text: this.durationText })
                .height(46)
                .backgroundColor($r('app.color.app_bg_card'))
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.durationText = value;
                })
            }
            .layoutWeight(1)
          }
          .width('100%')

          this.fieldLabel($r('app.string.field_key'))
          Row() {
            Text(this.musicalKey.length > 0
              ? `${this.musicalKey} · ${camelotNoteName(this.musicalKey)}`
              : $r('app.string.field_unset'))
              .fontSize(15)
              .fontColor(this.musicalKey.length > 0
                ? $r('app.color.app_brand_blue')
                : $r('app.color.app_text_hint'))
              .layoutWeight(1)
            Text(this.showKeyGrid ? $r('app.string.search_done') : $r('app.string.action_select'))
              .fontSize(13)
              .fontColor($r('app.color.app_brand_blue'))
              .onClick(() => {
                this.showKeyGrid = !this.showKeyGrid;
              })
          }
          .width('100%')

          if (this.showKeyGrid) {
            Scroll() {
              Column() {
                this.keyRow(this.minorKeys)
                this.keyRow(this.majorKeys)
              }
              .alignItems(HorizontalAlign.Start)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .height(84)
            .margin({ top: 8 })
          }

          this.fieldLabel($r('app.string.field_genre'))
          TextInput({ placeholder: $r('app.string.genre_placeholder'), text: this.genre })
            .width('100%')
            .height(46)
            .backgroundColor($r('app.color.app_bg_card'))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.genre = value;
            })

          Row() {
            Text($r('app.string.action_select'))
              .fontSize(12)
              .fontColor($r('app.color.app_brand_blue'))
              .onClick(() => {
                this.showGenreChips = !this.showGenreChips;
              })
          }
          .width('100%')
          .padding({ top: 8 })

          if (this.showGenreChips) {
            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
              ForEach(GENRE_PRESETS, (item: string) => {
                Text(item)
                  .fontSize(12)
                  .fontColor(this.genre === item ? Color.White : $r('app.color.app_text_secondary'))
                  .padding({
                    left: 10,
                    right: 10,
                    top: 5,
                    bottom: 5
                  })
                  .backgroundColor(this.genre === item ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_card'))
                  .borderRadius(999)
                  .margin({ right: 6, bottom: 6 })
                  .onClick(() => {
                    this.genre = this.genre === item ? '' : item;
                  })
              }, (item: string) => item)
            }
            .width('100%')
          }

          this.fieldLabel($r('app.string.field_energy'))
          Row() {
            Slider({
              value: this.energy,
              min: 1,
              max: 10,
              step: 1,
              style: SliderStyle.InSet
            })
              .layoutWeight(1)
              .selectedColor($r('app.color.app_brand_blue'))
              .onChange((value: number, mode: SliderChangeMode) => {
                this.energy = Math.round(value);
              })
            Text(this.energy.toString())
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
              .width(26)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          this.fieldLabel($r('app.string.field_note'))
          TextInput({ placeholder: $r('app.string.note_placeholder'), text: this.note })
            .width('100%')
            .height(46)
            .backgroundColor($r('app.color.app_bg_card'))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.note = value;
            })

          Row() {
            Button($r('app.string.dialog_cancel'), { type: ButtonType.Capsule })
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('app.color.app_bg_card'))
              .fontColor($r('app.color.app_text_primary'))
              .onClick(() => {
                this.onCancel();
              })
              .margin({ right: 10 })

            Button($r('app.string.dialog_save'), { type: ButtonType.Capsule })
              .layoutWeight(1)
              .height(44)
              .backgroundColor(this.canSave() ? $r('app.color.app_brand_blue') : $r('app.color.app_text_hint'))
              .fontColor(Color.White)
              .enabled(this.canSave())
              .onClick(() => {
                this.onSave(this.buildResult());
              })
          }
          .width('100%')
          .margin({ top: 20, bottom: 20 })
        }
        .width('100%')
        .padding({ left: 20, right: 20 })
      }
      .width('92%')
      .constraintSize({ maxHeight: '76%' })
      .backgroundColor($r('app.color.app_glass_bg'))
      .border({ width: 1, color: $r('app.color.app_glass_border') })
      .borderRadius(18)
      .shadow({
        radius: 20,
        color: '#40000000',
        offsetX: 0,
        offsetY: 4
      })
      .backgroundBlurStyle(BlurStyle.Thick)
      // 键盘弹出时向下位移贴近键盘；位移走 translate（GPU、不触发布局重排）并带过渡动画，
      // 与系统收缩容器动画并行进行，不会出现"切换对齐方式"那种瞬时跳变。
      .translate({ y: this.keyboardHeight > 0 ? this.KEYBOARD_OFFSET : '0%' })
      .animation({ duration: 260, curve: Curve.Friction })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    // 始终居中：键盘弹出时系统会把弹窗容器收缩到键盘上方（RESIZE 避让），
    // 此时居中同样不会被遮挡；不做 align 切换就不会出现键盘升降时的上下抽搐。
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 24 })
  }
}