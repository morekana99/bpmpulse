/**
 * 单行文本输入弹窗：新建歌单、重命名、复制歌单共用。
 */
@CustomDialog
export struct NameInputDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  title: ResourceStr = '';
  placeholder: ResourceStr = '';
  initial: string = '';
  onConfirm: (value: string) => void = () => {};
  onCancel: () => void = () => {};
  @State text: string = '';

  aboutToAppear(): void {
    this.text = this.initial;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.app_text_primary'))
        .margin({ top: 22, bottom: 16 })

      TextInput({ placeholder: this.placeholder, text: this.text })
        .width('100%')
        .height(46)
        .backgroundColor($r('app.color.app_bg_card'))
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .defaultFocus(true)
        .onChange((value: string) => {
          this.text = value;
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

        Button($r('app.string.dialog_confirm'), { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(44)
          .backgroundColor(this.text.trim().length > 0 ? $r('app.color.app_brand_blue') : $r('app.color.app_text_hint'))
          .fontColor(Color.White)
          .enabled(this.text.trim().length > 0)
          .onClick(() => {
            this.onConfirm(this.text.trim());
          })
      }
      .width('100%')
      .margin({ top: 18, bottom: 20 })
    }
    .width('82%')
    .padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.app_glass_bg'))
    .border({ width: 1, color: $r('app.color.app_glass_border') })
    .borderRadius(18)
    .shadow({ radius: 20, color: '#40000000', offsetX: 0, offsetY: 4 })
    .backgroundBlurStyle(BlurStyle.Thick)
  }
}
