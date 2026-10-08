/**
 * Camelot 调性轮盘工具（Harmonic Mixing）。
 *
 * Camelot 编码规则：数字 1-12 表示音高位置，字母 A 表示小调、B 表示大调。
 * 轮盘上相邻的调性可以无缝衔接，规则如下：
 *   - 同调（8A -> 8A）：完全无缝
 *   - 同数字换字母（8A -> 8B，关系大小调）：和声兼容
 *   - 同字母 ±1（8A -> 9A / 7A）：和声兼容，能量上升/下降
 *   - 数字 ±1 且换字母（8A -> 9B / 7B）：可衔接但有明显转调感
 *   - 其余组合：调性冲突
 */

export interface CamelotKeyInfo {
  code: string;
  name: string;
}

export interface CamelotParts {
  num: number;
  letter: string;
}

export enum HarmonyLevel {
  UNKNOWN = -1,
  SAME = 0,
  PERFECT = 1,
  DRAMATIC = 2,
  CLASH = 3
}

const CAMELOT_LIST: CamelotKeyInfo[] = [
  { code: '1A', name: 'A♭m' },
  { code: '1B', name: 'B' },
  { code: '2A', name: 'E♭m' },
  { code: '2B', name: 'F♯' },
  { code: '3A', name: 'B♭m' },
  { code: '3B', name: 'D♭' },
  { code: '4A', name: 'Fm' },
  { code: '4B', name: 'A♭' },
  { code: '5A', name: 'Cm' },
  { code: '5B', name: 'E♭' },
  { code: '6A', name: 'Gm' },
  { code: '6B', name: 'B♭' },
  { code: '7A', name: 'Dm' },
  { code: '7B', name: 'F' },
  { code: '8A', name: 'Am' },
  { code: '8B', name: 'C' },
  { code: '9A', name: 'Em' },
  { code: '9B', name: 'G' },
  { code: '10A', name: 'Bm' },
  { code: '10B', name: 'D' },
  { code: '11A', name: 'F♯m' },
  { code: '11B', name: 'A' },
  { code: '12A', name: 'C♯m' },
  { code: '12B', name: 'E' }
];

export const GENRE_PRESETS: string[] = [
  'House',
  'Tech House',
  'Techno',
  'Trance',
  'Psytrance',
  'Drum & Bass',
  'Dubstep',
  'Hardstyle',
  'Trap',
  'Hip Hop',
  'Disco',
  'Funk',
  'Afro House',
  'Latin',
  'Pop',
  'R&B',
  'Rock',
  'Ambient'
];

export function camelotKeys(): CamelotKeyInfo[] {
  return CAMELOT_LIST;
}

/** 返回调性的乐理音名，如 8A -> Am；未设置或非法返回空串 */
export function camelotNoteName(code: string): string {
  for (let i = 0; i < CAMELOT_LIST.length; i++) {
    if (CAMELOT_LIST[i].code === code) {
      return CAMELOT_LIST[i].name;
    }
  }
  return '';
}

/** 解析 Camelot 编码，非法输入返回 num = -1 */
export function parseCamelot(code: string): CamelotParts {
  if (code.length < 2) {
    return { num: -1, letter: '' };
  }
  const letter: string = code.slice(code.length - 1);
  const num: number = parseInt(code.slice(0, code.length - 1), 10);
  if (Number.isNaN(num) || num < 1 || num > 12 || (letter !== 'A' && letter !== 'B')) {
    return { num: -1, letter: '' };
  }
  return { num: num, letter: letter };
}

/**
 * 计算两个调性的衔接等级。
 * 返回 HarmonyLevel，UNKNOWN 表示任一曲目未设置调性。
 */
export function harmonyRank(from: string, to: string): number {
  if (from.length === 0 || to.length === 0) {
    return HarmonyLevel.UNKNOWN;
  }
  if (from === to) {
    return HarmonyLevel.SAME;
  }
  const a: CamelotParts = parseCamelot(from);
  const b: CamelotParts = parseCamelot(to);
  if (a.num < 0 || b.num < 0) {
    return HarmonyLevel.UNKNOWN;
  }
  const diff: number = Math.abs(a.num - b.num);
  const step: number = Math.min(diff, 12 - diff);
  if (step === 0) {
    // 同数字换字母：关系大小调
    return HarmonyLevel.PERFECT;
  }
  if (step === 1) {
    return a.letter === b.letter ? HarmonyLevel.PERFECT : HarmonyLevel.DRAMATIC;
  }
  return HarmonyLevel.CLASH;
}

/** 返回与给定调性可衔接的全部调性（按衔接质量从好到差排序） */
export function compatibleKeys(code: string): string[] {
  const parts: CamelotParts = parseCamelot(code);
  if (parts.num < 0) {
    return [];
  }
  const perfect: string[] = [];
  const dramatic: string[] = [];
  const other: string = parts.letter === 'A' ? 'B' : 'A';
  perfect.push(parts.num.toString() + other);
  const up: number = parts.num === 12 ? 1 : parts.num + 1;
  const down: number = parts.num === 1 ? 12 : parts.num - 1;
  perfect.push(up.toString() + parts.letter);
  perfect.push(down.toString() + parts.letter);
  dramatic.push(up.toString() + other);
  dramatic.push(down.toString() + other);
  return perfect.concat(dramatic);
}
