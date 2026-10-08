import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

/**
 * 备份文件的读写。
 * 导出复用 ShareUtils.shareTextFile（系统分享面板里可选"保存到文件"），
 * 导入走系统文件选择器 + 沙箱授权 URI 读取，不需要任何额外权限。
 */

/** 读取授权 URI 的 UTF-8 文本 */
export function readTextFromUri(uri: string): string {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const size: number = fs.statSync(file.fd).size;
    if (size <= 0) {
      return '';
    }
    const buffer: ArrayBuffer = new ArrayBuffer(size);
    fs.readSync(file.fd, buffer);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer));
  } finally {
    fs.closeSync(file);
  }
}

/**
 * 让用户选择一个 JSON 备份文件并读出文本。
 * 用户取消选择时返回 null（不是错误）。
 */
export async function pickBackupText(context: common.UIAbilityContext): Promise<string | null> {
  const options = new picker.DocumentSelectOptions();
  options.maxSelectNumber = 1;
  options.fileSuffixFilters = ['备份文件 (.json)|.json'];
  const documentPicker = new picker.DocumentViewPicker(context);
  const uris: string[] = await documentPicker.select(options);
  if (uris.length === 0) {
    return null;
  }
  return readTextFromUri(uris[0]);
}
