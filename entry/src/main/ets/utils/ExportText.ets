import { SongRecord } from '../models/SongRecord';
import { SetlistStats } from '../models/Setlist';
import { formatDuration, formatLongDuration } from './DjUtils';
import { HarmonyLevel, camelotNoteName, harmonyRank } from './MusicTheory';

const HARMONY_MARK: string[] = ['-', '=', '~', '!', '?'];

function harmonyMark(level: number): string {
  if (level === HarmonyLevel.SAME) {
    return HARMONY_MARK[0];
  }
  if (level === HarmonyLevel.PERFECT) {
    return HARMONY_MARK[1];
  }
  if (level === HarmonyLevel.DRAMATIC) {
    return HARMONY_MARK[2];
  }
  if (level === HarmonyLevel.CLASH) {
    return HARMONY_MARK[3];
  }
  return HARMONY_MARK[4];
}

function trackLine(index: number, track: SongRecord): string {
  const keyText: string = track.musicalKey.length > 0
    ? `${track.musicalKey}(${camelotNoteName(track.musicalKey)})`
    : '-';
  const genreText: string = track.genre.length > 0 ? track.genre : '-';
  const energyText: string = track.energy > 0 ? `E${track.energy}` : '-';
  return `${(index + 1).toString().padStart(2, '0')}. ${track.songName} - ${track.artistName}\n` +
    `    BPM ${track.bpm} | Key ${keyText} | ${genreText} | ${energyText} | ${formatDuration(track.durationSec)}`;
}

/** 曲库导出文本 */
export function buildLibraryText(records: SongRecord[]): string {
  let text: string = 'BPM 曲库\n' + '='.repeat(36) + '\n\n';
  for (let i = 0; i < records.length; i++) {
    text += trackLine(i, records[i]) + '\n\n';
  }
  text += '='.repeat(36) + '\n';
  text += `共 ${records.length} 首  |  导出时间: ${new Date().toLocaleString()}\n`;
  return text;
}

/** 歌单导出文本：额外输出每两首之间的过渡提示，方便现场按提示混音 */
export function buildSetlistText(name: string, tracks: SongRecord[], stats: SetlistStats): string {
  let text: string = `歌单: ${name}\n` + '='.repeat(36) + '\n\n';
  for (let i = 0; i < tracks.length; i++) {
    text += trackLine(i, tracks[i]) + '\n';
    if (i > 0) {
      const prev: SongRecord = tracks[i - 1];
      const delta: number = tracks[i].bpm - prev.bpm;
      const sign: string = delta >= 0 ? '+' : '';
      const mark: string = harmonyMark(harmonyRank(prev.musicalKey, tracks[i].musicalKey));
      text += `    <-> BPM ${sign}${delta} | key ${mark}\n`;
    }
    text += '\n';
  }
  text += '='.repeat(36) + '\n';
  text += `共 ${stats.count} 首  |  总时长 ${formatLongDuration(stats.totalDuration)}  |  ` +
    `BPM ${stats.minBpm}-${stats.maxBpm} (均值 ${stats.avgBpm})\n`;
  text += `导出时间: ${new Date().toLocaleString()}\n`;
  return text;
}
