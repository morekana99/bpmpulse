import { motion } from '@kit.MultimodalAwarenessKit';
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
  @State showRecordDialog: boolean = false;
  @State songName: string = '';
  @State artistName: string = '';
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

  saveRecord() {
    if (!this.songName.trim() || !this.artistName.trim()) {
      return;
    }

    const record: SongRecord = {
      id: Date.now(),
      songName: this.songName,
      artistName: this.artistName,
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

    this.songName = '';
    this.artistName = '';
    this.showRecordDialog = false;
    console.log('记录已保存:', JSON.stringify(record));
  }

  openRecordDialog() {
    this.showRecordDialog = true;
  }

  closeRecordDialog() {
    this.showRecordDialog = false;
    this.songName = '';
    this.artistName = '';
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
            Text('点击次数')
              .fontSize(16)
              .fontColor($r('app.color.app_text_hint'))
            Text(this.tapCount.toString())
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
          }
          .margin({ right: 40 })

          Column() {
            Text('平均间隔')
              .fontSize(16)
              .fontColor($r('app.color.app_text_hint'))
            Text(this.averageInterval > 0 ? this.averageInterval.toFixed(2) + ' 秒' : '--')
              .fontSize(24)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.app_text_primary'))
          }
        }
        .margin({ bottom: 40 })

        Text('点击屏幕任意位置，跟随音乐节奏点击')
          .fontSize(14)
          .fontColor($r('app.color.app_text_hint'))
          .margin({ bottom: 10 })
          .textAlign(TextAlign.Center)

        Text('长按屏幕可以重置数据')
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

      // 圆形浮动按钮 — 沉浸光感
      Row() {
        Column() {
          Text('+')
            .fontSize(36)
            .fontWeight(FontWeight.Lighter)
            .fontColor($r('app.color.app_text_primary'))
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundBlurStyle(BlurStyle.Regular, {
          colorMode: ThemeColorMode.SYSTEM,
          adaptiveColor: AdaptiveColor.DEFAULT,
          scale: 1.0
        })
        .backgroundColor('#44F2F2F7')
        .border({
          width: 0.5,
          color: '#80FFFFFF',
          style: BorderStyle.Solid
        })
        .shadow({
          radius: 16,
          color: '#18000000',
          offsetX: 0,
          offsetY: 6
        })
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

      // 记录弹窗
      if (this.showRecordDialog) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('#80000000')
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.closeRecordDialog();
            })

          Column() {
            Text('记录歌曲信息')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.app_text_primary'))
              .margin({ top: 24, bottom: 20 })

            TextInput({ placeholder: '歌曲名称' })
              .width('80%')
              .height(48)
              .backgroundColor($r('app.color.app_bg_primary'))
              .borderRadius(8)
              .padding({ left: 12, right: 12 })
              .margin({ bottom: 16 })
              .onChange((value: string) => {
                this.songName = value;
              })

            TextInput({ placeholder: '歌手' })
              .width('80%')
              .height(48)
              .backgroundColor($r('app.color.app_bg_primary'))
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
              Button('取消', { type: ButtonType.Capsule })
                .width(100)
                .height(40)
                .backgroundColor($r('app.color.app_bg_primary'))
                .fontColor($r('app.color.app_text_primary'))
                .onClick(() => {
                  this.closeRecordDialog();
                })
                .margin({ right: 16 })

              Button('保存', { type: ButtonType.Capsule })
                .width(100)
                .height(40)
                .backgroundColor(this.songName.trim().length > 0 && this.artistName.trim().length > 0 ? $r('app.color.app_brand_blue') : '#CCCCCC')
                .fontColor('#FFFFFF')
                .enabled(this.songName.trim().length > 0 && this.artistName.trim().length > 0)
                .onClick(() => {
                  this.saveRecord();
                })
            }
            .margin({ bottom: 24 })
          }
          .width('82%')
          .backgroundColor($r('app.color.app_bg_card'))
          .borderRadius(16)
          .shadow({ radius: 20, color: '#40000000', offsetX: 0, offsetY: 4 })
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(200)
      }
    }
    .width('100%')
    .height('100%')
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
    this.timerId = setInterval(() => this.tick(), 32);
  }

  aboutToDisappear(): void {
    if (this.timerId > 0) {
      clearInterval(this.timerId);
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
    for (let i = 0; i < 25; i++) {
      const writeIdx: number = (idx + i) % this.bufferSize;
      this.buffer[writeIdx] = this.beatWaveform[i];
    }
  }

  tick(): void {
    this.frameCount++;

    this.scanHead += this.scanSpeed;
    if (this.scanHead >= this.bufferSize) {
      this.scanHead = 0;
    }

    // beat 贡献温和衰减，逐渐回归水面基线
    // 水面波动在 draw 中按空间位置渲染，保证连续平滑，避免单点噪声造成的密集抖动
    for (let i = 0; i < this.bufferSize; i++) {
      this.buffer[i] *= 0.985;
    }

    this.draw();
  }

  draw(): void {
    const ctx: CanvasRenderingContext2D = this.canvasContext;
    const w: number = this.canvasWidth;
    const h: number = this.canvasHeight;
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
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldValue, newValue) => {
      this.canvasWidth = Number(newValue.width);
      this.canvasHeight = Number(newValue.height);
    })
  }
}
