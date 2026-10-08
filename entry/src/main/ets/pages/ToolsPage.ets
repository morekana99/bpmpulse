import { common } from '@kit.AbilityKit';
import { CamelotKeyInfo, HarmonyLevel, camelotKeys, camelotNoteName, harmonyRank } from '../utils/MusicTheory';
import { SongRecord } from '../models/SongRecord';
import { BackupSetlist, ImportPreview, ImportResult, ParsedBackup } from '../models/Backup';
import { DatabaseHelper } from '../database/DatabaseHelper';
import { SectionTitle, CamelotWheel } from '../components/DjWidgets';
import { BackupImportDialog } from '../components/BackupImportDialog';
import { buildBackupJson, computePreview, parseBackup } from '../utils/BackupFormat';
import { pickBackupText } from '../utils/BackupIO';
import { shareTextFile } from '../utils/ShareUtils';
import { formatLongDuration } from '../utils/DjUtils';

const PITCH_PRESETS: number[] = [-8, -6, -4, -2, 2, 4, 6, 8];

/**
 * 工具页：把 DJ 现场常用的小计算集中起来。
 * 速度微调（BPM ↔ 音高百分比）、调性轮盘与兼容查询、BPM 换算（含半速/倍速/小节/乐句）、
 * 按 BPM 找歌（自动匹配半速与倍速）、Set 时长规划，以及数据管理（JSON 备份导出 / 导入）。
 */
@Component
export struct ToolsPage {
  stack: NavPathStack = new NavPathStack();
  scroller: Scroller = new Scroller();
  @State bpmText: string = '';
  /** 目标 BPM：反向算出"要接到这个速度需要拨多少" */
  @State targetBpmText: string = '';
  @State pitch: number = 0;
  @State selectedKey: string = '';
  @State planMinutesText: string = '';
  @State library: SongRecord[] = [];
  /** 曲库或歌单被改动（含导入完成）后重新载入，匹配/规划结果跟着刷新 */
  @StorageProp('recordsNeedRefresh') @Watch('loadLibrary') recordRefresh: number = 0;
  @StorageProp('setlistsNeedRefresh') @Watch('loadLibrary') setlistRefresh: number = 0;
  private keys: CamelotKeyInfo[] = camelotKeys();
  private importController: CustomDialogController = new CustomDialogController({ builder: '' });

  aboutToAppear(): void {
    this.loadLibrary();
  }

  loadLibrary(): void {
    DatabaseHelper.getInstance().queryAll().then((data: SongRecord[]) => {
      this.library = data;
    }).catch((err: Error) => {
      console.error('ToolsPage: 加载曲库失败:', err.message);
    });
  }

  showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (err) {
      // 提示失败不阻断主流程
    }
  }

  // ---------------- 数据管理 ----------------

  /** 导出 JSON 备份（曲库 + 歌单），走系统分享面板，用户可保存到文件或发给另一台设备 */
  async exportBackup(): Promise<void> {
    try {
      const db: DatabaseHelper = DatabaseHelper.getInstance();
      const records: SongRecord[] = await db.queryAll();
      const setlists: BackupSetlist[] = await db.queryBackupSetlists();
      if (records.length === 0 && setlists.length === 0) {
        this.showToast($r('app.string.toast_no_selection'));
        return;
      }
      const json: string = buildBackupJson(records, setlists);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const title: string = context.resourceManager.getStringSync($r('app.string.backup_export_title').id);
      const desc: string = context.resourceManager.getStringSync($r('app.string.backup_export_desc').id,
        records.length, setlists.length);
      await shareTextFile(context, `BPMPulse备份_${Date.now()}.json`, json, title, desc);
    } catch (err) {
      console.error('ToolsPage: 导出备份失败:', JSON.stringify(err));
      this.showToast($r('app.string.toast_share_failed'));
    }
  }

  /** 选文件 → 解析 → 预览（新增/重复/歌单）→ 用户确认后执行导入 */
  async startImport(): Promise<void> {
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const text: string | null = await pickBackupText(context);
      if (text === null) {
        return;
      }
      const parsed: ParsedBackup = parseBackup(text);
      if (parsed.records.length === 0 && parsed.setlists.length === 0) {
        this.showToast($r('app.string.toast_import_empty'));
        return;
      }
      const existing: SongRecord[] = await DatabaseHelper.getInstance().queryAll();
      const preview: ImportPreview = computePreview(parsed, existing);
      this.importController = new CustomDialogController({
        builder: BackupImportDialog({
          preview: preview,
          onConfirm: (skipDuplicates: boolean) => {
            this.importController.close();
            this.runImport(parsed, skipDuplicates);
          },
          onCancel: () => {
            this.importController.close();
          }
        }),
        alignment: DialogAlignment.Center,
        customStyle: true,
        autoCancel: false
      });
      this.importController.open();
    } catch (err) {
      console.error('ToolsPage: 解析备份失败:', JSON.stringify(err));
      this.showToast($r('app.string.toast_import_failed'));
    }
  }

  /** 执行导入；导入完成后由 recordsNeedRefresh 通知本页与其它页面刷新 */
  runImport(parsed: ParsedBackup, skipDuplicates: boolean): void {
    DatabaseHelper.getInstance().importBackup(parsed, skipDuplicates).then((result: ImportResult) => {
      this.showToast($r('app.string.toast_import_done', result.inserted, result.setlists));
    }).catch((err: Error) => {
      console.error('ToolsPage: 导入备份失败:', err.message);
      this.showToast($r('app.string.toast_import_failed'));
    });
  }

  currentBpm(): number {
    const n: number = parseInt(this.bpmText, 10);
    return Number.isNaN(n) ? 0 : n;
  }

  adjustedBpm(percent: number): number {
    const bpm: number = this.currentBpm();
    if (bpm <= 0) {
      return 0;
    }
    return Math.round(bpm * (1 + percent / 100));
  }

  /**
   * pitch 百分比带来的音高偏移（半音）。
   * 变速杆同时改速度和音高（没有 keylock 时），换算公式 12 × log2(1 + p/100)：
   * +6% ≈ +1 个半音，这就是 DJ 说"±6% 以内基本听不出变调"的由来。
   */
  pitchSemitones(): number {
    return 12 * Math.log2(1 + this.pitch / 100);
  }

  /** 带符号的半音数，如 "+0.68" / "-0.35" */
  pitchSignedSemitones(): string {
    const s: number = this.pitchSemitones();
    return `${s >= 0 ? '+' : ''}${s.toFixed(2)}`;
  }

  /** 半音换算成音分（1 半音 = 100 音分），整数便于口播 */
  pitchCents(): number {
    return Math.round(this.pitchSemitones() * 100);
  }

  /** 目标 BPM 输入值（非法或超出 40–300 时返回 0） */
  targetBpm(): number {
    const n: number = parseInt(this.targetBpmText, 10);
    if (Number.isNaN(n) || n < 40 || n > 300) {
      return 0;
    }
    return n;
  }

  /** 是否具备反算条件：源 BPM（输入框）与目标 BPM 都有效 */
  showRequiredPitch(): boolean {
    return this.currentBpm() > 0 && this.targetBpm() > 0;
  }

  /** 把当前 BPM 拨到目标 BPM 所需的 pitch 百分比（如 -3.1） */
  requiredPitchPercent(): number {
    if (!this.showRequiredPitch()) {
      return 0;
    }
    return (this.targetBpm() / this.currentBpm() - 1) * 100;
  }

  /** 带符号、保留一位小数 */
  requiredPitchText(): string {
    const p: number = this.requiredPitchPercent();
    return `${p >= 0 ? '+' : ''}${p.toFixed(1)}`;
  }

  /** 所需位移是否落在滑条可拨范围内（±12%） */
  requiredPitchInRange(): boolean {
    return Math.abs(this.requiredPitchPercent()) <= 12;
  }

  /** 滑条是整档拨的（步进 1%），取最接近的可拨档位 */
  appliedPitch(): number {
    return Math.max(-12, Math.min(12, Math.round(this.requiredPitchPercent())));
  }

  appliedPitchText(): string {
    const p: number = this.appliedPitch();
    return `${p > 0 ? '+' : ''}${p}%`;
  }

  /** 把滑条直接拨到反算出的档位，省去手动凑 */
  applyRequiredPitch(): void {
    this.pitch = this.appliedPitch();
  }

  beatSeconds(): string {
    const bpm: number = this.currentBpm();
    if (bpm <= 0) {
      return '--';
    }
    return (60 / bpm).toFixed(3);
  }

  beatMs(): string {
    const bpm: number = this.currentBpm();
    if (bpm <= 0) {
      return '--';
    }
    return Math.round(60000 / bpm).toString();
  }

  halfBpm(): number {
    const bpm: number = this.currentBpm();
    return bpm > 0 ? Math.round(bpm / 2) : 0;
  }

  doubleBpm(): number {
    const bpm: number = this.currentBpm();
    return bpm > 0 ? Math.round(bpm * 2) : 0;
  }

  barSeconds(): string {
    const bpm: number = this.currentBpm();
    return bpm > 0 ? ((60 / bpm) * 4).toFixed(2) : '--';
  }

  phraseSeconds(): string {
    const bpm: number = this.currentBpm();
    return bpm > 0 ? ((60 / bpm) * 32).toFixed(1) : '--';
  }

  mixLow(): number {
    const bpm: number = this.currentBpm();
    return bpm > 0 ? Math.round(bpm * 0.92) : 0;
  }

  mixHigh(): number {
    const bpm: number = this.currentBpm();
    return bpm > 0 ? Math.round(bpm * 1.08) : 0;
  }

  compatibleKeys(): CamelotKeyInfo[] {
    if (this.selectedKey.length === 0) {
      return [];
    }
    const result: CamelotKeyInfo[] = [];
    for (let i = 0; i < this.keys.length; i++) {
      const rank: number = harmonyRank(this.selectedKey, this.keys[i].code);
      if (rank === HarmonyLevel.SAME || rank === HarmonyLevel.PERFECT || rank === HarmonyLevel.DRAMATIC) {
        result.push(this.keys[i]);
      }
    }
    return result;
  }

  planMinutes(): number {
    const n: number = parseInt(this.planMinutesText, 10);
    return Number.isNaN(n) ? 0 : n;
  }

  avgTrackSec(): number {
    if (this.library.length === 0) {
      return 0;
    }
    let sum: number = 0;
    let cnt: number = 0;
    for (let i = 0; i < this.library.length; i++) {
      if (this.library[i].durationSec > 0) {
        sum += this.library[i].durationSec;
        cnt++;
      }
    }
    return cnt > 0 ? Math.round(sum / cnt) : 0;
  }

  planCount(): number {
    const target: number = this.planMinutes();
    const avg: number = this.avgTrackSec();
    if (target <= 0 || avg <= 0) {
      return 0;
    }
    return Math.max(1, Math.round((target * 60) / avg));
  }

  planTotalSec(): number {
    return this.planCount() * this.avgTrackSec();
  }

  /**
   * BPM 基准卡：一个输入框统管「速度微调」与「换算」。
   * 原先这两块是上下两张卡片、却只有上面那张带输入框：滚到「换算」时输入框早已滑出屏幕，
   * 整张卡都是 `--`，看起来像功能坏了。合并成一张卡后，输入与结果始终在同一屏。
   */
  @Builder
  bpmCard() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text($r('app.string.tool_bpm_input'))
          .fontSize(14)
          .fontColor($r('app.color.app_text_secondary'))
          .alignSelf(ItemAlign.Center)
        TextInput({ placeholder: '128', text: this.bpmText })
          .layoutWeight(1)
          .height(44)
          .type(InputType.Number)
          .backgroundColor($r('app.color.app_bg_primary'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.bpmText = value;
          })
        Column({ space: 2 }) {
          Text(this.currentBpm() > 0 ? this.adjustedBpm(this.pitch).toString() : '--')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_brand_blue'))
          Text(`±${this.pitch > 0 ? '+' : ''}${this.pitch}%`)
            .fontSize(11)
            .fontColor($r('app.color.app_text_hint'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .color('#14000000')

      Text($r('app.string.tool_section_pitch'))
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))
        .alignSelf(ItemAlign.Start)

      Row() {
        Text($r('app.string.tool_pitch', this.pitch > 0 ? `+${this.pitch}%` : `${this.pitch}%`))
          .fontSize(12)
          .fontColor($r('app.color.app_text_hint'))
          .layoutWeight(1)
        Text($r('app.string.tool_pitch_reset'))
          .fontSize(12)
          .fontColor($r('app.color.app_brand_blue'))
          .onClick(() => {
            this.pitch = 0;
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Slider({ value: this.pitch, min: -12, max: 12, step: 1, style: SliderStyle.InSet })
        .width('100%')
        .selectedColor($r('app.color.app_brand_blue'))
        .onChange((value: number, mode: SliderChangeMode) => {
          this.pitch = Math.round(value);
        })

      Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
        ForEach(PITCH_PRESETS, (p: number) => {
          Text(p > 0 ? `+${p}` : `${p}`)
            .fontSize(12)
            .fontColor(this.pitch === p ? Color.White : $r('app.color.app_text_secondary'))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.pitch === p ? $r('app.color.app_brand_blue') : $r('app.color.app_bg_primary'))
            .borderRadius(999)
            .margin({ right: 6, bottom: 6 })
            .onClick(() => {
              this.pitch = p;
            })
        }, (p: number) => p.toString())
      }
      .width('100%')

      // 音高偏移：拨速会同时带动音高，用半音/音分比百分比更贴近 DJ 的判断习惯
      // （原来这里是一列 8 行的预设 BPM 映射，与滑条 + 大号数字 + 预设芯片信息重复，已删）
      Text($r('app.string.tool_pitch_semitones', this.pitchSignedSemitones(), this.pitchCents()))
        .fontSize(12)
        .fontColor($r('app.color.app_text_hint'))
        .alignSelf(ItemAlign.Start)

      Divider()
        .color('#14000000')

      // 反向计算：现场的真实想法是"我要接到 124"，而不是"我要拨 -3.1%"
      Text($r('app.string.tool_target_label'))
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))
        .alignSelf(ItemAlign.Start)

      Row({ space: 10 }) {
        Text($r('app.string.tool_target_bpm'))
          .fontSize(14)
          .fontColor($r('app.color.app_text_secondary'))
          .alignSelf(ItemAlign.Center)
        TextInput({ placeholder: '124', text: this.targetBpmText })
          .layoutWeight(1)
          .height(44)
          .type(InputType.Number)
          .backgroundColor($r('app.color.app_bg_primary'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.targetBpmText = value;
          })
        Column({ space: 2 }) {
          Text(this.showRequiredPitch() ? `${this.requiredPitchText()}%` : '--')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.requiredPitchInRange() ? $r('app.color.app_brand_blue') : '#E84040')
          Text($r('app.string.tool_target_need'))
            .fontSize(11)
            .fontColor($r('app.color.app_text_hint'))
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.showRequiredPitch()) {
        Row() {
          if (this.requiredPitchInRange()) {
            // 滑条只能整档拨，这里标出实际会拨到的档位
            Text($r('app.string.tool_target_apply', this.appliedPitchText()))
              .fontSize(12)
              .fontColor($r('app.color.app_brand_blue'))
              .onClick(() => {
                this.applyRequiredPitch();
              })
          } else {
            Text($r('app.string.tool_target_range'))
              .fontSize(12)
              .fontColor('#E84040')
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }

      Divider()
        .color('#14000000')

      Text($r('app.string.tool_section_conv'))
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))
        .alignSelf(ItemAlign.Start)

      Column({ space: 10 }) {
        ValueRow({ label: $r('app.string.tool_bpm_label'), value: this.currentBpm() > 0 ? `${this.currentBpm()} BPM` : '--' })
        ValueRow({ label: $r('app.string.tools_half'), value: this.halfBpm() > 0 ? `${this.halfBpm()} BPM` : '--' })
        ValueRow({ label: $r('app.string.tools_double'), value: this.doubleBpm() > 0 ? `${this.doubleBpm()} BPM` : '--' })
        ValueRow({ label: $r('app.string.tool_per_beat_sec'), value: `${this.beatSeconds()} s` })
        ValueRow({ label: $r('app.string.tool_per_beat_ms'), value: `${this.beatMs()} ms` })
        ValueRow({ label: $r('app.string.tools_bar'), value: `${this.barSeconds()} s` })
        ValueRow({ label: $r('app.string.tools_phrase'), value: `${this.phraseSeconds()} s` })
        ValueRow({
          label: $r('app.string.tools_mix_range'),
          value: this.currentBpm() > 0 ? `${this.mixLow()}-${this.mixHigh()} BPM` : '--'
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
  }

  @Builder
  keyCard() {
    Column({ space: 12 }) {
      Text($r('app.string.tools_wheel'))
        .fontSize(13)
        .fontColor($r('app.color.app_text_secondary'))
        .alignSelf(ItemAlign.Start)

      CamelotWheel({
        selectedKey: this.selectedKey,
        onSelect: (code: string) => {
          this.selectedKey = this.selectedKey === code ? '' : code;
        }
      })
        .alignSelf(ItemAlign.Center)

      if (this.selectedKey.length > 0) {
        Column({ space: 8 }) {
          Text($r('app.string.tool_compat_with', this.selectedKey, camelotNoteName(this.selectedKey)))
            .fontSize(13)
            .fontColor($r('app.color.app_text_secondary'))
            .alignSelf(ItemAlign.Start)
          Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
            ForEach(this.compatibleKeys(), (k: CamelotKeyInfo) => {
              Text(`${k.code} ${k.name}`)
                .fontSize(12)
                .fontColor(Color.White)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                .backgroundColor($r('app.color.app_brand_blue'))
                .borderRadius(999)
                .margin({ right: 6, bottom: 6 })
            }, (k: CamelotKeyInfo) => k.code)
          }
          .width('100%')
        }
        .width('100%')
      } else {
        Text($r('app.string.tools_wheel_hint'))
          .fontSize(12)
          .fontColor($r('app.color.app_text_hint'))
          .alignSelf(ItemAlign.Start)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
  }

  @Builder
  plannerCard() {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text($r('app.string.tools_planner_target'))
          .fontSize(14)
          .fontColor($r('app.color.app_text_secondary'))
          .alignSelf(ItemAlign.Center)
        TextInput({ placeholder: '60', text: this.planMinutesText })
          .layoutWeight(1)
          .height(44)
          .type(InputType.Number)
          .backgroundColor($r('app.color.app_bg_primary'))
          .borderRadius(8)
          .padding({ left: 12, right: 12 })
          .onChange((value: string) => {
            this.planMinutesText = value;
          })
        Text('min')
          .fontSize(13)
          .fontColor($r('app.color.app_text_hint'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.avgTrackSec() > 0) {
        ValueRow({ label: $r('app.string.tools_planner_avg'), value: formatLongDuration(this.avgTrackSec()) })
      } else {
        Text($r('app.string.tools_matcher_empty'))
          .fontSize(12)
          .fontColor($r('app.color.app_text_hint'))
          .alignSelf(ItemAlign.Start)
      }

      if (this.planMinutes() > 0 && this.avgTrackSec() > 0) {
        Column({ space: 8 }) {
          Text($r('app.string.tools_planner_result', this.planCount()))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.app_text_primary'))
            .alignSelf(ItemAlign.Start)
          Text($r('app.string.tools_planner_total', formatLongDuration(this.planTotalSec())))
            .fontSize(13)
            .fontColor($r('app.color.app_text_secondary'))
            .alignSelf(ItemAlign.Start)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
  }

  /**
   * 数据管理卡片。
   * 备份/恢复统一收口在这里：曲库多选导出与歌单导出仍是"分享给谁"的上下文快捷操作，
   * 这里负责"整机备份 / 换机恢复"。
   */
  @Builder
  backupCard() {
    Column({ space: 12 }) {
      Text($r('app.string.backup_hint'))
        .fontSize(12)
        .fontColor($r('app.color.app_text_hint'))
        .alignSelf(ItemAlign.Start)

      Row({ space: 10 }) {
        Button($r('app.string.action_export_backup'), { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.app_brand_blue'))
          .fontColor(Color.White)
          .onClick(() => {
            this.exportBackup();
          })

        Button($r('app.string.action_import_backup'), { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(44)
          .backgroundColor($r('app.color.app_bg_primary'))
          .fontColor($r('app.color.app_text_primary'))
          .border({ width: 1, color: '#1F000000' })
          .onClick(() => {
            this.startImport();
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.app_bg_card'))
    .borderRadius(12)
  }

  build() {
    Scroll(this.scroller) {
      Column({ space: 10 }) {
        SectionTitle({ title: $r('app.string.tool_section_bpm') })
        this.bpmCard()
        SectionTitle({ title: $r('app.string.tool_section_key') })
        this.keyCard()
        SectionTitle({ title: $r('app.string.tools_planner') })
        this.plannerCard()
        SectionTitle({ title: $r('app.string.backup_section_title') })
        this.backupCard()
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

/**
 * 「标签 — 数值」一行（换算与时长规划共用）。
 *
 * 必须做成 @Component 而不是 @Builder：@Builder 是**按值传参**，形参在首次渲染时就被捕获，
 * 之后父组件重渲染也不会更新传入的实参——换算行传进去的是 `${this.beatSeconds()} s` 这类
 * 提前算好的字符串，于是输入 BPM 后那 8 行永远停在初始的 `--`。
 * @Component + @Prop 才会跟着新值刷新。
 */
@Component
struct ValueRow {
  @Prop label: ResourceStr = '';
  @Prop value: string = '';

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor($r('app.color.app_text_secondary'))
        .layoutWeight(1)
      Text(this.value)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
    }
    .width('100%')
  }
}
