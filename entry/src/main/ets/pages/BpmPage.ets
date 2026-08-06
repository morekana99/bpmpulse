import { motion } from '@kit.MultimodalAwarenessKit';
import { uiMaterial } from '@kit.ArkUI';
import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SongRecord } from '../models/SongRecord';
import { DatabaseHelper } from '../database/DatabaseHelper';

@Component
export struct BpmPage {
  scroller: Scroller = new Scroller();
  @State tapTimes: number[] = [];
  @State bpm: number = 0;
  @State tapCount: number = 0;
  @State averageInterval: number = 0;
  @State lastTapTime: number = 0;
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: BpmRecordDialog({
      bpm: this.bpm,
      onSave: (songName: string, artistName: string) => {
        this.doSaveRecord(songName, artistName);
      },
      onCancel: () => {
        this.dialogController.close();
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: true,
    // 仅允许点击"取消"按钮或系统返回键关闭，点击弹窗外其它区域不消失
    autoCancel: false
  });
  @State isRightHanded: boolean = true;
  @State beatTrigger: number = 0;
  @State debugStatus: string = '初始化...';

  private pollTimerId: number = -1;
  private latestHolding: number = 2;

  handleTap() {
    const now = Date.now();
    this.beatTrigger++;
    this.tapTimes.push(now);
    this.tapCount++;  // 独立递增，不受 tapTimes 截断影响

    // 触觉反馈：短促跟手振动，usage=touch 低延迟优先级
    vibrator.startVibration(
      { type: 'time', duration: 20 },
      { id: 0, usage: 'touch' }
    ).catch((err: Error) => {
      console.error('振动失败:', err.message);
    });

    if (this.tapTimes.length >= 2) {
      const intervals: number[] = [];
      for (let i = 1; i < this.tapTimes.length; i++) {
        intervals.push((this.tapTimes[i] - this.tapTimes[i - 1]) / 1000);
      }
      const sum = intervals.reduce((acc, val) => acc + val, 0);
      this.averageInterval = sum / intervals.length;
      if (this.averageInterval > 0) {
        this.bpm = Math.round(60 / this.averageInterval);
      } else {
        this.bpm = 0;
      }
    }

    if (this.tapTimes.length > 10) {
      this.tapTimes = this.tapTimes.slice(-10);
    }
    this.lastTapTime = now;
  }

  resetData() {
    this.tapTimes = [];
    this.bpm = 0;
    this.tapCount = 0;
    this.averageInterval = 0;
    this.lastTapTime = 0;
  }

  // 长按重置振动：实体按钮强反馈（按下）+ 延迟回弹短震（弹起），与点击的轻触区分
  vibrateReset(): void {
    vibrator.isSupportEffect('haptic.effect.hard').then((supported: boolean) => {
      if (supported) {
        vibrator.startVibration(
          { type: 'preset', effectId: 'haptic.effect.hard' },
          { id: 0, usage: 'physicalFeedback' }
        ).catch((err: Error) => {
          console.error('重置振动失败:', err.message);
        });
      } else {
        // 设备不支持时降级：比点击更强更长的振动
        vibrator.startVibration(
          { type: 'time', duration: 45 },
          { id: 0, usage: 'physicalFeedback' }
        ).catch((err: Error) => {
          console.error('重置振动失败:', err.message);
        });
      }
      // 回弹短震：强震后延迟触发，模拟实体按钮弹起
      setTimeout(() => {
        vibrator.startVibration(
          { type: 'time', duration: 15 },
          { id: 0, usage: 'touch' }
        ).catch((err: Error) => {
          console.error('回弹振动失败:', err.message);
        });
      }, 120);
    }).catch((err: Error) => {
      console.error('查询振动效果失败:', err.message);
    });
  }

  // 由自定义弹窗回调：保存一条记录
  doSaveRecord(songName: string, artistName: string) {
    if (!songName.trim() || !artistName.trim()) {
      return;
    }

    const record: SongRecord = {
      id: Date.now(),
      songName: songName,
      artistName: artistName,
      bpm: this.bpm,
      timestamp: Date.now(),
      tapCount: this.tapCount,
      averageInterval: this.averageInterval
    };

    DatabaseHelper.getInstance().insert(record).then(() => {
      // 通知 RecordPage 刷新数据
      AppStorage.setOrCreate('recordsNeedRefresh', Date.now());
    }).catch((err: Error) => {
      console.error('保存记录失败:', err.message);
    });

    this.dialogController.close();
    console.log('记录已保存:', JSON.stringify(record));
  }

  openRecordDialog() {
    // 每次打开用当前 bpm 重建控制器，避免字段初始化时捕获的初始值（0）
    this.dialogController = new CustomDialogController({
      builder: BpmRecordDialog({
        bpm: this.bpm,
        onSave: (songName: string, artistName: string) => {
          this.doSaveRecord(songName, artistName);
        },
        onCancel: () => {
          this.dialogController.close();
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      // 仅允许点击"取消"按钮或系统返回键关闭，点击弹窗外其它区域不消失
      autoCancel: false
    });
    this.dialogController.open();
  }

  aboutToAppear(): void {
    this.isRightHanded = true;
    this.latestHolding = 2;
    this.debugStatus = '启动智感握持...';
    this.startSmartHold();
  }

  aboutToDisappear(): void {
    this.stopSmartHold();
  }

  private startSmartHold(): void {
    try {
      motion.on('holdingHandChanged', (data: motion.HoldingHandStatus) => {
        console.log('holdingHandChanged:', data);
        this.latestHolding = data;
        if (data === motion.HoldingHandStatus.RIGHT_HAND_HELD) {
          this.debugStatus = '握持: 右手';
        } else if (data === motion.HoldingHandStatus.LEFT_HAND_HELD) {
          this.debugStatus = '握持: 左手';
        } else if (data === motion.HoldingHandStatus.BOTH_HANDS_HELD) {
          this.debugStatus = '握持: 双手';
        } else if (data === motion.HoldingHandStatus.NOT_HELD) {
          this.debugStatus = '握持: 未持握';
        } else {
          this.debugStatus = '握持: 未识别(' + data + ')';
        }
      });
      this.debugStatus = '智感握持已订阅';
    } catch (err) {
      const error = err as BusinessError;
      this.debugStatus = 'holdingHandChanged错误: code=' + error.code;
      console.error('智感握持订阅失败:', JSON.stringify(error));
    }
    this.pollTimerId = setInterval(() => {
      if (this.latestHolding === motion.HoldingHandStatus.LEFT_HAND_HELD && this.isRightHanded) {
        this.isRightHanded = false;
      } else if (this.latestHolding === motion.HoldingHandStatus.RIGHT_HAND_HELD && !this.isRightHanded) {
        this.isRightHanded = true;
      }
    }, 100);
  }

  private stopSmartHold(): void {
    try {
      motion.off('holdingHandChanged');
    } catch (err) {
      console.error('智感握持取消订阅失败:', JSON.stringify(err));
    }
    if (this.pollTimerId > 0) {
      clearInterval(this.pollTimerId);
    }
  }

  build() {
    Stack() {
      // 主内容区域
      Column() {
        Text('Tempocurvegram')
          .fontSize(28)
          .fontStyle(FontStyle.Italic)
          .fontWeight(FontWeight.Bold)
          .fontFamily('cursive')
          .margin({ top: 100, bottom: 4 })
          .fontColor($r('app.color.app_text_primary'))
          .letterSpacing(0.5)
          

        Text('TCG')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_secondary'))
          .margin({ bottom: 16 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          
        // Text(this.debugStatus)
        //   .fontSize(10)
        //   .fontColor('#FF6B35')
        //   .margin({ bottom: 4 })
        //   .maxLines(1)
        //   .textOverflow({ overflow: TextOverflow.Ellipsis })

        // Text('握持: ' + (this.isRightHanded ? '右手' : '左手') + ' | BPM: ' + (this.bpm > 0 ? this.bpm.toString() : '--'))
        //   .fontSize(10)
        //   .fontColor('#007DFF')
        //   .margin({ bottom: 16 })
        //   .maxLines(1)
        //   .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.bpm > 0 ? this.bpm.toString() : '--')
          .fontSize(72)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_brand_blue'))
          .margin({ top: 40, bottom: 10 })

        Text('BPM')
          .fontSize(20)
          .fontColor($r('app.color.app_text_secondary'))
          .margin({ bottom: 16 })

        HeartbeatWave({ beatTrigger: this.beatTrigger })
          .width('100%')
          .height(90)
          .margin({ bottom: 16 })

        Row() {
          Column() {
            Text($r('app.string.bpm_tap_count_label'))
              .fontSize(16)
              .fontColor($r('app.color.app_text_hint'))
            Text(this.tapCount.toString())
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
          }
          .margin({ right: 40 })

          Column() {
            Text($r('app.string.bpm_avg_interval_label'))
              .fontSize(16)
              .fontColor($r('app.color.app_text_hint'))
            Text(this.averageInterval > 0 ? $r('app.string.bpm_avg_interval_value', this.averageInterval.toFixed(2)) : '--')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
          }
        }
        .margin({ bottom: 40 })

        Text($r('app.string.bpm_tap_hint'))
          .fontSize(14)
          .fontColor($r('app.color.app_text_hint'))
          .margin({ bottom: 10 })
          .textAlign(TextAlign.Center)

        Text($r('app.string.bpm_longpress_hint'))
          .fontSize(12)
          .fontColor('#AAAAAA')
          .margin({ bottom: 40 })
          .textAlign(TextAlign.Center)

        Blank()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.app_bg_primary'))
      .onClick(() => {
        this.handleTap();
      })
      .gesture(
        LongPressGesture({ repeat: false, duration: 400 })
          .onAction(() => {
            this.vibrateReset();
            this.resetData();
          })
      )

      // 圆形浮动按钮 — HDS 沉浸光感 + 主题蓝色 + 图形加号
      Row() {
        Column() {
          SymbolGlyph($r('sys.symbol.plus'))
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor([$r('app.color.app_brand_blue')])
            .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        // 保留 HDS 沉浸材质（THICK 厚样式），背景透明以透出材质，
        // 加号图形使用主题蓝色呈现。
        .backgroundColor(Color.Transparent)
        .systemMaterial(new uiMaterial.ImmersiveMaterial({
          style: uiMaterial.ImmersiveStyle.THICK
        }))
        .onClick(() => {
          this.openRecordDialog();
        })
      }
      .constraintSize({ minWidth: '100%' })
      .padding({ left: 14, right: 14 })
      .justifyContent(this.isRightHanded ? FlexAlign.End : FlexAlign.Start)
      .position({ x: 0, y: '78%' })
      .animation({
        duration: 400,
        curve: Curve.EaseInOut
      })
      .zIndex(100)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }
}

// 添加记录弹窗：采用官方 CustomDialog 组件，模态居中卡片。
// 整体使用 HDS 沉浸材质（systemMaterial 模糊背景，透出底层内容）；
// 输入框与按钮无边框，使用 app_bg_card 纯色块（浅色纯白 / 深色 #242424）与模糊背景形成对比，深浅模式均清晰。
// autoCancel: false，仅点击"取消"按钮或系统返回键才会关闭，点击弹窗外其它区域不消失。
// 由 CustomDialogController 原生避让软键盘，首个输入框 defaultFocus 自动弹出键盘。
@CustomDialog
struct BpmRecordDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  bpm: number = 0;
  onSave: (songName: string, artistName: string) => void = () => {};
  onCancel: () => void = () => {};
  @State songName: string = '';
  @State artistName: string = '';

  // 每次打开重置输入，避免上次内容残留
  aboutToAppear(): void {
    this.songName = '';
    this.artistName = '';
  }

  build() {
    Column() {
      Text($r('app.string.bpm_save_info'))
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .margin({ top: 24, bottom: 20 })

      TextInput({ placeholder: $r('app.string.song_name_placeholder') })
        .width('80%')
        .height(48)
        // 无边框：用 app_bg_card 纯色块（浅色纯白 / 深色 #242424）与 HDS 模糊半透明背景形成对比
        .backgroundColor($r('app.color.app_bg_card'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 16 })
        .defaultFocus(true)
        .onChange((value: string) => {
          this.songName = value;
        })

      TextInput({ placeholder: $r('app.string.artist_placeholder') })
        .width('80%')
        .height(48)
        .backgroundColor($r('app.color.app_bg_card'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 16 })
        .onChange((value: string) => {
          this.artistName = value;
        })

      Row() {
        Text('BPM: ')
          .fontSize(16)
          .fontColor($r('app.color.app_text_secondary'))
        Text(this.bpm.toString())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_brand_blue'))
      }
      .margin({ bottom: 24 })

      Row() {
        Button($r('app.string.dialog_cancel'), { type: ButtonType.Capsule })
          .width(100)
          .height(40)
          // 无边框：用 app_bg_card 纯色块与 HDS 模糊背景区分，深色模式下同样清晰
          .backgroundColor($r('app.color.app_bg_card'))
          .fontColor($r('app.color.app_text_primary'))
          .onClick(() => {
            this.onCancel();
          })
          .margin({ right: 16 })

        Button($r('app.string.dialog_save'), { type: ButtonType.Capsule })
          .width(100)
          .height(40)
          .backgroundColor(this.songName.trim().length > 0 && this.artistName.trim().length > 0 ? $r('app.color.app_brand_blue') : $r('app.color.app_text_hint'))
          .fontColor(this.songName.trim().length > 0 && this.artistName.trim().length > 0 ? Color.White : $r('app.color.app_bg_card'))
          .enabled(this.songName.trim().length > 0 && this.artistName.trim().length > 0)
          .onClick(() => {
            this.onSave(this.songName, this.artistName);
          })
      }
      .margin({ bottom: 24 })
    }
    .width('82%')
    // HDS 沉浸材质：弹窗整体使用系统 material 模糊背景，透出底层内容，
    // 仅输入框与按钮区域保持纯色不透明（见上方 TextInput 与按钮 Row）。
    .backgroundColor(Color.Transparent)
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THICK
    }))
    .borderRadius(16)
    .shadow({ radius: 20, color: '#40000000', offsetX: 0, offsetY: 4 })
    .alignItems(HorizontalAlign.Center)
  }
}

@Component
struct HeartbeatWave {
  private renderSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.renderSettings);
  @Prop @Watch('onBeatTriggerChanged') beatTrigger: number = 0;

  private readonly bufferSize: number = 300;
  private canvasWidth: number = 0;
  private canvasHeight: number = 0;
  private timerId: number = -1;
  private frameCount: number = 0;

  private scanHead: number = 0;
  private readonly scanSpeed: number = 2;
  private buffer: number[] = [];

  private beatWaveform: number[] = [];

  aboutToAppear(): void {
    for (let i = 0; i < this.bufferSize; i++) {
      this.buffer.push(0);
    }
    this.precomputeBeatWaveform();
  }

  aboutToDisappear(): void {
    this.stopTimer();
  }

  // 启动绘制定时器（仅当画布尺寸有效时），应在 onReady 后调用
  private startTimer(): void {
    this.stopTimer();
    this.timerId = setInterval(() => this.tick(), 32);
  }

  private stopTimer(): void {
    if (this.timerId > 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  precomputeBeatWaveform(): void {
    const steps: number = 25;
    for (let i = 0; i < steps; i++) {
      const t: number = i / steps;
      const p: number = Math.exp(-((t - 0.10) * (t - 0.10)) / (2 * 0.020 * 0.020)) * 0.25;
      const q: number = -Math.exp(-((t - 0.25) * (t - 0.25)) / (2 * 0.015 * 0.015)) * 1.2;
      const r: number = Math.exp(-((t - 0.35) * (t - 0.35)) / (2 * 0.020 * 0.020)) * 2.4;
      const s: number = -Math.exp(-((t - 0.45) * (t - 0.45)) / (2 * 0.020 * 0.020)) * 0.9;
      this.beatWaveform.push(p + q + s + r);
    }
  }

  onBeatTriggerChanged(): void {
    const idx: number = Math.floor(this.scanHead);
    // 点击波形增益：抬高绘制高度约 15%，增强跟手反馈（不影响水面基线）
    const gain: number = 1.15;
    for (let i = 0; i < 25; i++) {
      const writeIdx: number = (idx + i) % this.bufferSize;
      this.buffer[writeIdx] = this.beatWaveform[i] * gain;
    }
  }

  tick(): void {
    this.frameCount++;

    this.scanHead += this.scanSpeed;
    if (this.scanHead >= this.bufferSize) {
      this.scanHead = 0;
    }

    // beat 贡献衰减，逐渐回归水面基线。
    // 水面波动在 draw 中按空间位置渲染，保证连续平滑，避免单点噪声造成的密集抖动
    for (let i = 0; i < this.bufferSize; i++) {
      this.buffer[i] *= 0.961;
    }

    this.draw();
  }

  draw(): void {
    const ctx: CanvasRenderingContext2D = this.canvasContext;
    // 优先使用 onAreaChange 设置的尺寸；若其未触发/异常，则回退到 CanvasRenderingContext2D 自带宽高（onReady 后确定可用）
    const w: number = this.canvasWidth > 0 ? this.canvasWidth : (this.canvasContext?.width ?? 0);
    const h: number = this.canvasHeight > 0 ? this.canvasHeight : (this.canvasContext?.height ?? 0);
    if (w <= 0 || h <= 0) {
      return;
    }

    ctx.clearRect(0, 0, w, h);

    const stepX: number = w / (this.bufferSize - 1);
    const marginTop: number = h * 0.35;
    const marginBottom: number = h * 0.08;
    const drawableHeight: number = h - marginTop - marginBottom;
    const midY: number = marginTop + drawableHeight / 2;
    const scale: number = drawableHeight * 0.42;

    const headIdx: number = Math.floor(this.scanHead);
    const headX: number = headIdx * stepX;

    // 平稳状态水面波动：基于空间位置 i 与时间 frameCount 的超低频正弦叠加
    // 波长长（粗看近似直线）、幅度极小（细看可见轻微起伏），空间连续平滑
    const waterPhase = (i: number): number => {
      return Math.sin(i * 0.025 + this.frameCount * 0.02) * 0.028
           + Math.sin(i * 0.017 + this.frameCount * 0.013) * 0.016;
    };

    ctx.save();
    ctx.shadowColor = '#007DFF';
    ctx.shadowBlur = 6;
    ctx.strokeStyle = '#007DFF';
    ctx.lineWidth = 2.2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';

    ctx.beginPath();
    let started: boolean = false;
    for (let i = headIdx; i < this.bufferSize; i++) {
      const val: number = this.buffer[i];
      const x: number = i * stepX;
      const y: number = midY - val * scale + waterPhase(i) * scale;
      if (!started) {
        ctx.moveTo(x, y);
        started = true;
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();

    ctx.beginPath();
    started = false;
    for (let i = 0; i < headIdx; i++) {
      const val: number = this.buffer[i];
      const x: number = i * stepX;
      const y: number = midY - val * scale + waterPhase(i) * scale;
      if (!started) {
        ctx.moveTo(x, y);
        started = true;
      } else {
        ctx.lineTo(x, y);
      }
    }
    ctx.stroke();
    ctx.restore();

    ctx.save();
    ctx.shadowColor = '#007DFF';
    ctx.shadowBlur = 12;
    ctx.fillStyle = '#007DFF';
    ctx.beginPath();
    ctx.arc(headX, midY - this.buffer[headIdx] * scale + waterPhase(headIdx) * scale, 3.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  build() {
    Column() {
      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        // onReady 是画布宽高确定、可绘制且已清空的官方时机，在此启动动画最可靠（SDK 升级后 onAreaChange 时序不再稳定）
        .onReady(() => {
          this.canvasWidth = Number(this.canvasContext.width);
          this.canvasHeight = Number(this.canvasContext.height);
          this.startTimer();
        })
        .onAreaChange((newValue: Area) => {
          this.canvasWidth = Number(newValue.width);
          this.canvasHeight = Number(newValue.height);
        })
        // HdsTabs 切到其它页签时本页内容被移出窗口，Canvas 进入"不可见不响应绘制"；切回时需恢复绘制
        .onVisibleAreaChange([0.0, 1.0], (isVisible: boolean, currentRatio: number) => {
          if (isVisible && currentRatio > 0) {
            if (this.timerId <= 0) {
              this.startTimer();
            }
          } else {
            this.stopTimer();
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
