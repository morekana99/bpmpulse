import { SongRecord } from './SongRecord';

/**
 * 备份文件模型。
 *
 * 备份是「无损、可回导」的 JSON，与给人看的 TXT 导出分工不同：
 * - records 字段与 SongRecord 完全一致（含 id/timestamp/tapCount/averageInterval/note 等）；
 * - setlists 只保存歌单名、备注与「原曲目 id 的顺序列表」，导入时重新分配 id 并建立映射。
 *
 * 这样一份文件即可完整还原曲库与歌单，且导入不依赖任何正则解析。
 */
export const BACKUP_APP_TAG: string = 'BpmPulse';
export const BACKUP_VERSION: number = 1;

/** 备份中的歌单：recordIds 为原曲目 id，顺序即歌单顺序 */
export interface BackupSetlist {
  name: string;
  note: string;
  recordIds: number[];
}

/** 备份文件根结构 */
export interface BackupFile {
  app: string;
  version: number;
  exportedAt: number;
  records: SongRecord[];
  setlists: BackupSetlist[];
}

/** 解析并逐条校验后的备份数据 */
export interface ParsedBackup {
  version: number;
  exportedAt: number;
  records: SongRecord[];
  /** 字段非法（如缺少歌名）被丢弃的曲目数 */
  invalidRecords: number;
  setlists: BackupSetlist[];
  /** 曲目全部无法解析而被丢弃的歌单数 */
  droppedSetlists: number;
}

/** 导入预览：导入前告诉用户会发生什么 */
export interface ImportPreview {
  totalRecords: number;
  newRecords: number;
  duplicateRecords: number;
  invalidRecords: number;
  setlistCount: number;
  setlistTrackCount: number;
}

/** 导入执行结果 */
export interface ImportResult {
  inserted: number;
  skipped: number;
  setlists: number;
  setlistTracks: number;
}
