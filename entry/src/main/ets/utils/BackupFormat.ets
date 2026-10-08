import {
  BACKUP_APP_TAG,
  BACKUP_VERSION,
  BackupFile,
  BackupSetlist,
  ImportPreview,
  ParsedBackup
} from '../models/Backup';
import { SongRecord } from '../models/SongRecord';
import { CamelotKeyInfo, camelotKeys } from './MusicTheory';

/**
 * 备份文件的生成与解析。
 *
 * 备份文件可能被用户手工编辑过，也可能选错文件，所以解析全程只做「类型防御 + 丢弃坏数据」，
 * 不做任何隐式信任：字段类型不对就取默认值，曲目缺少歌名则整条丢弃并计数，
 * 歌单若没有任何可解析的曲目则整条丢弃。
 */

/** 宽松的原始曲目：字段允许缺失或类型不对，由 toRecord 兜底 */
interface RawRecord {
  id?: number | string;
  songName?: number | string;
  artistName?: number | string;
  bpm?: number | string;
  timestamp?: number | string;
  tapCount?: number | string;
  averageInterval?: number | string;
  musicalKey?: number | string;
  genre?: number | string;
  energy?: number | string;
  durationSec?: number | string;
  note?: number | string;
}

interface RawSetlist {
  name?: number | string;
  note?: number | string;
  recordIds?: Array<number | string>;
}

interface RawBackup {
  app?: number | string;
  version?: number | string;
  exportedAt?: number | string;
  records?: RawRecord[];
  setlists?: RawSetlist[];
}

let camelotCodeCache: string[] | null = null;

function camelotCodes(): string[] {
  if (camelotCodeCache === null) {
    const list: CamelotKeyInfo[] = camelotKeys();
    const codes: string[] = [];
    for (let i = 0; i < list.length; i++) {
      codes.push(list[i].code);
    }
    camelotCodeCache = codes;
  }
  return camelotCodeCache;
}

/** 备份中的调性只接受合法 Camelot 代码，非法值直接落空，避免污染 wheel/兼容性计算 */
function normalizeCamelot(value: string): string {
  const code: string = value.trim().toUpperCase();
  if (code.length === 0) {
    return '';
  }
  return camelotCodes().indexOf(code) >= 0 ? code : '';
}

function asText(value: number | string | undefined): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number') {
    return value.toString();
  }
  return '';
}

function asNumber(value: number | string | undefined, fallback: number): number {
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : fallback;
  }
  if (typeof value === 'string') {
    const parsed: number = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}

function asInt(value: number | string | undefined, fallback: number, min: number, max: number): number {
  const n: number = Math.round(asNumber(value, fallback));
  return Math.min(Math.max(n, min), max);
}

/**
 * 判断 JSON 值是否为数组。
 * 不用 Array.isArray 是为了避免把值收窄成 any（ArkTS 严格模式禁止 any 参与后续访问）。
 */
function isJsonArray(value: Object | undefined): boolean {
  if (value === undefined) {
    return false;
  }
  const serialized: string = JSON.stringify(value);
  return serialized.length > 0 && serialized.charAt(0) === '[';
}

/** 判重键：歌名 + 歌手，去掉首尾空白并忽略大小写 */
export function recordDuplicateKey(record: SongRecord): string {
  return `${record.songName.trim().toLowerCase()}|${record.artistName.trim().toLowerCase()}`;
}

/** 把宽松对象转成合法曲目；缺少歌名视为非法，返回 null */
function toRecord(raw: RawRecord): SongRecord | null {
  const songName: string = asText(raw.songName).trim();
  if (songName.length === 0) {
    return null;
  }
  return {
    id: asInt(raw.id, 0, 0, Number.MAX_SAFE_INTEGER),
    songName: songName,
    artistName: asText(raw.artistName).trim(),
    bpm: asInt(raw.bpm, 0, 0, 400),
    timestamp: asInt(raw.timestamp, 0, 0, Number.MAX_SAFE_INTEGER),
    tapCount: asInt(raw.tapCount, 0, 0, 100000),
    averageInterval: asNumber(raw.averageInterval, 0),
    musicalKey: normalizeCamelot(asText(raw.musicalKey)),
    genre: asText(raw.genre).trim(),
    energy: asInt(raw.energy, 0, 0, 10),
    durationSec: asInt(raw.durationSec, 0, 0, 24 * 3600),
    note: asText(raw.note).trim()
  };
}

/**
 * 把宽松对象转成合法歌单；缺少歌名才返回 null。
 * 空歌单（没有曲目）保留下来，保证"导出再导入"能还原空歌单。
 */
function toSetlist(raw: RawSetlist): BackupSetlist | null {
  const name: string = asText(raw.name).trim();
  if (name.length === 0) {
    return null;
  }
  const ids: number[] = [];
  if (isJsonArray(raw.recordIds)) {
    const list: Array<number | string> = raw.recordIds as Array<number | string>;
    for (let i = 0; i < list.length; i++) {
      const id: number = asInt(list[i], 0, 0, Number.MAX_SAFE_INTEGER);
      if (id > 0) {
        ids.push(id);
      }
    }
  }
  return { name: name, note: asText(raw.note).trim(), recordIds: ids };
}

/** 生成备份 JSON 文本 */
export function buildBackupJson(records: SongRecord[], setlists: BackupSetlist[]): string {
  const file: BackupFile = {
    app: BACKUP_APP_TAG,
    version: BACKUP_VERSION,
    exportedAt: Date.now(),
    records: records,
    setlists: setlists
  };
  return JSON.stringify(file);
}

/**
 * 解析备份 JSON。格式完全不合法时抛错（错误信息用于日志），
 * 单条数据有问题则丢弃并计数，不整包失败。
 */
export function parseBackup(text: string): ParsedBackup {
  const trimmed: string = text.trim();
  if (trimmed.length === 0) {
    throw new Error('备份文件为空');
  }
  let raw: RawBackup;
  try {
    raw = JSON.parse(trimmed) as RawBackup;
  } catch (err) {
    throw new Error('备份文件不是合法的 JSON');
  }
  if (raw === null || raw === undefined) {
    throw new Error('备份文件不是合法的 JSON');
  }
  const recordsValue: Object | undefined = raw.records;
  const setlistsValue: Object | undefined = raw.setlists;
  const hasRecords: boolean = isJsonArray(recordsValue);
  const hasSetlists: boolean = isJsonArray(setlistsValue);
  if (!hasRecords && !hasSetlists) {
    throw new Error('备份文件缺少 records / setlists 字段');
  }

  const records: SongRecord[] = [];
  let invalid: number = 0;
  if (hasRecords) {
    const rawRecords: RawRecord[] = raw.records as RawRecord[];
    for (let i = 0; i < rawRecords.length; i++) {
      const converted: SongRecord | null = toRecord(rawRecords[i]);
      if (converted === null) {
        invalid++;
        continue;
      }
      records.push(converted);
    }
  }

  const setlists: BackupSetlist[] = [];
  let dropped: number = 0;
  if (hasSetlists) {
    const rawSetlists: RawSetlist[] = raw.setlists as RawSetlist[];
    for (let i = 0; i < rawSetlists.length; i++) {
      const converted: BackupSetlist | null = toSetlist(rawSetlists[i]);
      if (converted === null) {
        dropped++;
        continue;
      }
      setlists.push(converted);
    }
  }

  return {
    version: asInt(raw.version, BACKUP_VERSION, 1, 999),
    exportedAt: asInt(raw.exportedAt, 0, 0, Number.MAX_SAFE_INTEGER),
    records: records,
    invalidRecords: invalid,
    setlists: setlists,
    droppedSetlists: dropped
  };
}

/** 统计导入预览：newRecords / duplicateRecords 对应「跳过重复」模式下的结果 */
export function computePreview(parsed: ParsedBackup, existing: SongRecord[]): ImportPreview {
  const known: string[] = [];
  for (let i = 0; i < existing.length; i++) {
    known.push(recordDuplicateKey(existing[i]));
  }
  let duplicate: number = 0;
  for (let i = 0; i < parsed.records.length; i++) {
    const key: string = recordDuplicateKey(parsed.records[i]);
    if (known.indexOf(key) >= 0) {
      duplicate++;
    } else {
      known.push(key);
    }
  }
  let tracks: number = 0;
  for (let i = 0; i < parsed.setlists.length; i++) {
    tracks += parsed.setlists[i].recordIds.length;
  }
  return {
    totalRecords: parsed.records.length,
    newRecords: parsed.records.length - duplicate,
    duplicateRecords: duplicate,
    invalidRecords: parsed.invalidRecords,
    setlistCount: parsed.setlists.length,
    setlistTrackCount: tracks
  };
}
