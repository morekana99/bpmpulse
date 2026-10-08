import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri, fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

/**
 * 把文本写入缓存文件并唤起系统分享面板。
 * 曲库导出与歌单导出共用同一套逻辑。
 */
export async function shareTextFile(
  context: common.UIAbilityContext,
  fileName: string,
  content: string,
  title: string,
  description: string
): Promise<void> {
  const filePath: string = `${context.cacheDir}/${fileName}`;
  const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
  fs.writeSync(file.fd, content);
  fs.closeSync(file);
  const uri: string = fileUri.getUriFromPath(filePath);
  const shareData: systemShare.SharedData = new systemShare.SharedData({
    utd: utd.UniformDataType.TEXT,
    uri: uri,
    title: title,
    description: description
  });
  const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
  await controller.show(context, {
    previewMode: systemShare.SharePreviewMode.DETAIL,
    selectionMode: systemShare.SelectionMode.SINGLE
  });
}
