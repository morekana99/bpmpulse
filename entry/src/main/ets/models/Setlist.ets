import { SongRecord } from './SongRecord';

/**
 * 歌单（DJ 的一个 Set）
 */
export interface Setlist {
  id: number;
  name: string;
  note: string;
  createdAt: number;
  updatedAt: number;
}

/**
 * 歌单中的一条曲目（含关联表自增 id，用于删除与排序）
 */
export interface SetlistTrack {
  itemId: number;
  recordId: number;
  record: SongRecord;
}

/**
 * 歌单列表卡片需要的汇总信息
 */
export interface SetlistSummary {
  setlist: Setlist;
  trackCount: number;
  totalDuration: number;
  minBpm: number;
  maxBpm: number;
  avgBpm: number;
  avgEnergy: number;
  keyList: string[];
}

/**
 * 歌单统计信息
 */
export interface SetlistStats {
  count: number;
  totalDuration: number;
  minBpm: number;
  maxBpm: number;
  avgBpm: number;
  avgEnergy: number;
}

/**
 * 路由参数：歌单详情
 */
export interface SetlistDetailParam {
  setlistId: number;
}

/**
 * 路由参数：从曲库挑选曲目加入歌单
 */
export interface TrackPickerParam {
  setlistId: number;
  anchorBpm: number;
  anchorKey: string;
}

/**
 * 路由参数：选择目标歌单（曲库多选的「加入歌单」与歌单详情的「加入其它歌单」共用）
 */
export interface SetlistPickerParam {
  /** 要加入的曲目 id */
  recordIds: number[];
  /** 需要隐藏的歌单（歌单详情里排除当前歌单），-1 表示不排除 */
  excludeSetlistId: number;
  /** 加入完成后回调：added 为实际新增条数，name 为目标歌单名 */
  onDone: (added: number, name: string) => void;
}
