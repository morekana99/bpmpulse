import { SongRecord } from '../models/SongRecord';
import { SetlistStats } from '../models/Setlist';
import { harmonyRank } from './MusicTheory';

/**
 * DJ 常用 BPM 与排歌算法。
 * normalizeBpm 把 BPM 折算到 80-159 区间，从而识别 140 与 70（半速）、
 * 87 与 174（倍速）这类在传统数值上差距巨大、但实际可以混音的曲目。
 */
export function normalizeBpm(bpm: number): number {
  if (bpm <= 0) {
    return 0;
  }
  let v: number = bpm;
  while (v >= 160) {
    v = v / 2;
  }
  while (v < 80) {
    v = v * 2;
  }
  return v;
}

/** 两个 BPM 折算后的绝对差值；任一无效返回 999 */
export function bpmGap(a: number, b: number): number {
  const na: number = normalizeBpm(a);
  const nb: number = normalizeBpm(b);
  if (na <= 0 || nb <= 0) {
    return 999;
  }
  return Math.abs(na - nb);
}

/** 两个 BPM 折算后的相对差（百分比），用于判断是否落在混音容差内 */
export function bpmDiffPercent(a: number, b: number): number {
  const na: number = normalizeBpm(a);
  const nb: number = normalizeBpm(b);
  if (na <= 0 || nb <= 0) {
    return 100;
  }
  return Math.abs(na - nb) / Math.max(na, nb) * 100;
}

/** 判断两个 BPM 是否存在半速 / 倍速关系 */
export function isHalfOrDouble(a: number, b: number): boolean {
  if (a <= 0 || b <= 0) {
    return false;
  }
  const ratio: number = Math.max(a, b) / Math.min(a, b);
  return Math.abs(ratio - 2) < 0.08;
}

/** 每一拍的毫秒数 */
export function beatMs(bpm: number): number {
  return bpm > 0 ? Math.round(60000 / bpm) : 0;
}

/** 指定拍数对应的秒数 */
export function beatsSeconds(bpm: number, beats: number): number {
  return bpm > 0 ? (60 / bpm) * beats : 0;
}

/** 秒数格式化为 m:ss，<= 0 返回 -- */
export function formatDuration(sec: number): string {
  if (sec <= 0) {
    return '--';
  }
  const m: number = Math.floor(sec / 60);
  const s: number = Math.floor(sec % 60);
  return `${m}:${s.toString().padStart(2, '0')}`;
}

/**
 * 解析用户输入的时长文本，支持 "3:45" 与纯数字分钟两种写法。
 * 空串返回 0（未设置），格式非法返回 -1。
 */
export function parseDurationInput(text: string): number {
  const raw: string = text.trim();
  if (raw.length === 0) {
    return 0;
  }
  if (raw.indexOf(':') >= 0) {
    const parts: string[] = raw.split(':');
    if (parts.length === 2) {
      const m: number = Number(parts[0]);
      const s: number = Number(parts[1]);
      if (Number.isFinite(m) && Number.isFinite(s) && m >= 0 && s >= 0 && s < 60) {
        return Math.round(m * 60 + s);
      }
    }
    return -1;
  }
  const minutes: number = Number(raw);
  if (Number.isFinite(minutes) && minutes > 0) {
    return Math.round(minutes * 60);
  }
  return -1;
}

/** 分钟数格式化为 xh ym / ym */
export function formatLongDuration(sec: number): string {
  if (sec <= 0) {
    return '--';
  }
  const totalMin: number = Math.round(sec / 60);
  const h: number = Math.floor(totalMin / 60);
  const m: number = totalMin % 60;
  if (h > 0) {
    return `${h}h${m.toString().padStart(2, '0')}m`;
  }
  return `${m}m`;
}

/**
 * 两首歌衔接的代价，越低越顺滑。
 * 代价 = BPM 折算差值 + 调性惩罚 + 能量跳变惩罚。
 */
export function transitionCost(from: SongRecord, to: SongRecord): number {
  const gap: number = bpmGap(from.bpm, to.bpm);
  const rank: number = harmonyRank(from.musicalKey, to.musicalKey);
  let keyPenalty: number = 4;
  if (rank === 0) {
    keyPenalty = 0;
  } else if (rank === 1) {
    keyPenalty = 1.5;
  } else if (rank === 2) {
    keyPenalty = 7;
  } else if (rank === 3) {
    keyPenalty = 20;
  }
  let energyPenalty: number = 0;
  if (from.energy > 0 && to.energy > 0) {
    energyPenalty = Math.abs(from.energy - to.energy) * 0.5;
  }
  return gap + keyPenalty + energyPenalty;
}

/**
 * 智能排序：以 BPM 最低的曲目为起点，每次贪心选择衔接代价最小的下一首，
 * 得到一条 BPM 平滑过渡、调性和声、能量渐进的 Set 路径。
 */
export function smartOrder(tracks: SongRecord[]): SongRecord[] {
  if (tracks.length <= 2) {
    return tracks;
  }
  const pool: SongRecord[] = [...tracks];
  pool.sort((a: SongRecord, b: SongRecord) => normalizeBpm(a.bpm) - normalizeBpm(b.bpm));
  const result: SongRecord[] = [];
  let current: SongRecord = pool[0];
  result.push(current);
  pool.splice(0, 1);
  while (pool.length > 0) {
    let bestIdx: number = 0;
    let bestCost: number = 1e9;
    for (let i = 0; i < pool.length; i++) {
      const cost: number = transitionCost(current, pool[i]);
      if (cost < bestCost) {
        bestCost = cost;
        bestIdx = i;
      }
    }
    current = pool[bestIdx];
    result.push(current);
    pool.splice(bestIdx, 1);
  }
  return result;
}

/** 折算后的 BPM 升序 */
export function sortByBpmAsc(tracks: SongRecord[]): SongRecord[] {
  const copy: SongRecord[] = [...tracks];
  copy.sort((a: SongRecord, b: SongRecord) => normalizeBpm(a.bpm) - normalizeBpm(b.bpm));
  return copy;
}

/** 折算后的 BPM 降序 */
export function sortByBpmDesc(tracks: SongRecord[]): SongRecord[] {
  const copy: SongRecord[] = [...tracks];
  copy.sort((a: SongRecord, b: SongRecord) => normalizeBpm(b.bpm) - normalizeBpm(a.bpm));
  return copy;
}

/** 统计歌单的 BPM 区间、总时长与平均能量 */
export function computeStats(tracks: SongRecord[]): SetlistStats {
  const stats: SetlistStats = {
    count: tracks.length,
    totalDuration: 0,
    minBpm: 0,
    maxBpm: 0,
    avgBpm: 0,
    avgEnergy: 0
  };
  if (tracks.length === 0) {
    return stats;
  }
  let min: number = 9999;
  let max: number = 0;
  let bpmSum: number = 0;
  let bpmCount: number = 0;
  let energySum: number = 0;
  let energyCount: number = 0;
  for (let i = 0; i < tracks.length; i++) {
    const t: SongRecord = tracks[i];
    stats.totalDuration += t.durationSec;
    if (t.bpm > 0) {
      if (t.bpm < min) {
        min = t.bpm;
      }
      if (t.bpm > max) {
        max = t.bpm;
      }
      bpmSum += t.bpm;
      bpmCount++;
    }
    if (t.energy > 0) {
      energySum += t.energy;
      energyCount++;
    }
  }
  stats.minBpm = min === 9999 ? 0 : min;
  stats.maxBpm = max;
  stats.avgBpm = bpmCount > 0 ? Math.round(bpmSum / bpmCount) : 0;
  stats.avgEnergy = energyCount > 0 ? Math.round(energySum / energyCount) : 0;
  return stats;
}
