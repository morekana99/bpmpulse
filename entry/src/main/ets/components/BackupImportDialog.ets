import { ImportPreview } from '../models/Backup';

/**
 * 备份导入预览弹窗。
 *
 * 导入是"不可一眼回退"的操作，所以先把结果讲清楚（新增多少、跳过多少、歌单怎么处理），
 * 再让用户确认；重复曲目的处理方式在这里切换，默认最安全的"跳过重复"。
 */
@CustomDialog
export struct BackupImportDialog {
  controller: CustomDialogController = new CustomDialogController({ builder: '' });
  preview: ImportPreview = {
    totalRecords: 0,
    newRecords: 0,
    duplicateRecords: 0,
    invalidRecords: 0,
    setlistCount: 0,
    setlistTrackCount: 0
  };
  onConfirm: (skipDuplicates: boolean) => void = () => {};
  onCancel: () => void = () => {};
  /** 默认跳过重复曲目，避免导入产生同名同歌手的重复记录 */
  @State skipDuplicates: boolean = true;

  @Builder
  infoRow(label: ResourceStr, value: ResourceStr) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.app_text_secondary'))
        .layoutWeight(1)
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.app_text_primary'))
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 8 })
  }

  @Builder
  hintRow(text: ResourceStr) {
    Text(text)
      .fontSize(11)
      .fontColor($r('app.color.app_text_hint'))
      .width('100%')
      .margin({ top: 2, bottom: 8 })
  }

  build() {
    Column() {
      Column() {
        Text($r('app.string.import_preview_title'))
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.app_text_primary'))
          .margin({ top: 20, bottom: 16 })

        this.infoRow(
          $r('app.string.import_preview_records_label'),
          $r('app.string.import_preview_records',
            this.preview.totalRecords, this.preview.newRecords, this.preview.duplicateRecords)
        )
        if (this.preview.setlistCount > 0) {
          this.infoRow(
            $r('app.string.import_preview_setlists_label'),
            $r('app.string.import_preview_setlists', this.preview.setlistCount, this.preview.setlistTrackCount)
          )
        }
        if (this.preview.invalidRecords > 0) {
          this.infoRow(
            $r('app.string.import_preview_invalid_label'),
            $r('app.string.import_preview_invalid', this.preview.invalidRecords)
          )
        }

        Row() {
          Column({ space: 2 }) {
            Text($r('app.string.import_skip_duplicates'))
              .fontSize(14)
              .fontColor($r('app.color.app_text_primary'))
              .alignSelf(ItemAlign.Start)
            Text($r('app.string.import_skip_duplicates_hint'))
              .fontSize(11)
              .fontColor($r('app.color.app_text_hint'))
              .alignSelf(ItemAlign.Start)
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Toggle({ type: ToggleType.Switch, isOn: this.skipDuplicates })
            .selectedColor($r('app.color.app_brand_blue'))
            .onChange((isOn: boolean) => {
              this.skipDuplicates = isOn;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 4, bottom: 4 })

        this.hintRow($r('app.string.import_setlist_hint'))

        Row({ space: 10 }) {
          Button($r('app.string.dialog_cancel'), { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.app_bg_card'))
            .fontColor($r('app.color.app_text_primary'))
            .onClick(() => {
              this.onCancel();
            })

          Button($r('app.string.action_import'), { type: ButtonType.Capsule })
            .layoutWeight(1)
            .height(44)
            .backgroundColor($r('app.color.app_brand_blue'))
            .fontColor(Color.White)
            .onClick(() => {
              this.onConfirm(this.skipDuplicates);
            })
        }
        .width('100%')
        .margin({ top: 8, bottom: 4 })
      }
      .width('92%')
      .padding(20)
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
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 24 })
  }
}
