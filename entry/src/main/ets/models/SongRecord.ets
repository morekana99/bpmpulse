/**
 * 曲库曲目模型。
 * 在原有测速记录字段基础上扩展了 DJ 打碟所需的元数据：
 * musicalKey 采用 Camelot 调性代码（1A-12B），genre 为风格标签，
 * energy 为 1-10 能量等级，durationSec 为单曲时长（秒）。
 */
export interface SongRecord {
  id: number;
  songName: string;
  artistName: string;
  bpm: number;
  timestamp: number;
  tapCount: number;
  averageInterval: number;
  musicalKey: string;
  genre: string;
  energy: number;
  durationSec: number;
  note: string;
}

/**
 * ForEach 行键值：必须包含会被编辑的字段。
 *
 * SongRecord 是普通 interface（非 @Observed），而 RecordPage / SetlistDetailPage /
 * TrackPickerPage 的 ForEach 若只用 id 作为键值，编辑保存后 id 不变，
 * ArkUI 会复用旧子组件且不重新渲染内容，表现为「保存后列表不更新，
 * 退出重进才更新」。把可编辑字段拼进键值后，内容一变该行即被重建，界面立即刷新。
 */
export function songRecordKey(record: SongRecord): string {
  return `${record.id}|${record.songName}|${record.artistName}|${record.bpm}|${record.musicalKey}` +
    `|${record.genre}|${record.energy}|${record.durationSec}|${record.note}`;
}

export function createSongRecord(
  songName: string,
  artistName: string,
  bpm: number,
  tapCount: number,
  averageInterval: number
): SongRecord {
  return {
    id: Date.now(),
    songName: songName,
    artistName: artistName,
    bpm: bpm,
    timestamp: Date.now(),
    tapCount: tapCount,
    averageInterval: averageInterval,
    musicalKey: '',
    genre: '',
    energy: 0,
    durationSec: 0,
    note: ''
  };
}
