import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SongRecord } from '../models/SongRecord';
import { Setlist, SetlistSummary, SetlistTrack } from '../models/Setlist';
import { BackupSetlist, ImportResult, ParsedBackup } from '../models/Backup';
import { computeStats } from '../utils/DjUtils';
import { recordDuplicateKey } from '../utils/BackupFormat';

const DB_NAME = 'BpmPulse.db';
const TABLE_NAME = 'song_records';
const TABLE_SETLIST = 'setlists';
const TABLE_SETLIST_ITEM = 'setlist_items';

const STORE_CONFIG: relationalStore.StoreConfig = {
  name: DB_NAME,
  securityLevel: relationalStore.SecurityLevel.S1
};

const CREATE_TABLE_SQL = `
  CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (
    id INTEGER PRIMARY KEY,
    song_name TEXT NOT NULL,
    artist_name TEXT NOT NULL,
    bpm INTEGER NOT NULL,
    timestamp INTEGER NOT NULL,
    tap_count INTEGER NOT NULL,
    average_interval REAL NOT NULL
  )
`;

const CREATE_SETLIST_SQL = `
  CREATE TABLE IF NOT EXISTS ${TABLE_SETLIST} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )
`;

const CREATE_SETLIST_ITEM_SQL = `
  CREATE TABLE IF NOT EXISTS ${TABLE_SETLIST_ITEM} (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    setlist_id INTEGER NOT NULL,
    record_id INTEGER NOT NULL,
    sort_order INTEGER NOT NULL,
    added_at INTEGER NOT NULL
  )
`;

/** 需要增量迁移到 song_records 上的列（DJ 元数据） */
interface ColumnMigration {
  column: string;
  type: string;
  defaultValue: string;
}

const SONG_MIGRATIONS: ColumnMigration[] = [
  { column: 'musical_key', type: 'TEXT', defaultValue: "''" },
  { column: 'genre', type: 'TEXT', defaultValue: "''" },
  { column: 'energy', type: 'INTEGER', defaultValue: '0' },
  { column: 'duration_sec', type: 'INTEGER', defaultValue: '0' },
  { column: 'note', type: 'TEXT', defaultValue: "''" }
];

interface RecordIdPair {
  itemId: number;
  recordId: number;
}

interface SetlistRecordGroup {
  setlistId: number;
  recordIds: number[];
}

export class DatabaseHelper {
  private static instance: DatabaseHelper;
  private rdbStore: relationalStore.RdbStore | null = null;
  private initPromise: Promise<void> | null = null;

  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  /**
   * 初始化数据库，应在应用启动时调用一次
   */
  async init(context: common.Context): Promise<void> {
    if (this.rdbStore) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }

    this.initPromise = new Promise<void>(async (resolve: () => void, reject: (err: Error) => void) => {
      try {
        this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
        await this.rdbStore.executeSql(CREATE_TABLE_SQL);
        await this.rdbStore.executeSql(CREATE_SETLIST_SQL);
        await this.rdbStore.executeSql(CREATE_SETLIST_ITEM_SQL);
        await this.migrateSongColumns();
        console.info('DatabaseHelper: 数据库初始化成功');
        resolve();
      } catch (err) {
        const error = err as BusinessError;
        console.error(`DatabaseHelper: 数据库初始化失败, code=${error.code}, msg=${error.message}`);
        this.initPromise = null;
        reject(err as Error);
      }
    });

    return this.initPromise;
  }

  private ensureStore(): relationalStore.RdbStore {
    if (!this.rdbStore) {
      throw new Error('DatabaseHelper: 数据库未初始化，请先调用 init()');
    }
    return this.rdbStore;
  }

  /**
   * 增量升级 song_records 表：为老版本数据补上 DJ 元数据列。
   * 通过 PRAGMA table_info 判断列是否已存在，避免重复 ALTER。
   */
  private async migrateSongColumns(): Promise<void> {
    const store: relationalStore.RdbStore = this.ensureStore();
    for (let i = 0; i < SONG_MIGRATIONS.length; i++) {
      const item: ColumnMigration = SONG_MIGRATIONS[i];
      try {
        const exists: boolean = await this.hasColumn(store, TABLE_NAME, item.column);
        if (!exists) {
          await store.executeSql(
            `ALTER TABLE ${TABLE_NAME} ADD COLUMN ${item.column} ${item.type} NOT NULL DEFAULT ${item.defaultValue}`
          );
          console.info(`DatabaseHelper: 已新增列 ${item.column}`);
        }
      } catch (err) {
        console.error(`DatabaseHelper: 迁移列 ${item.column} 失败: ${JSON.stringify(err)}`);
      }
    }
  }

  private async hasColumn(
    store: relationalStore.RdbStore,
    table: string,
    column: string
  ): Promise<boolean> {
    const resultSet: relationalStore.ResultSet = await store.querySql(`PRAGMA table_info(${table})`);
    let exists: boolean = false;
    try {
      const count: number = resultSet.rowCount;
      if (count > 0) {
        resultSet.goToFirstRow();
        for (let i = 0; i < count; i++) {
          const name: string = resultSet.getString(resultSet.getColumnIndex('name'));
          if (name === column) {
            exists = true;
            break;
          }
          resultSet.goToNextRow();
        }
      }
    } finally {
      resultSet.close();
    }
    return exists;
  }

  /** 曲目 → ValuesBucket，插入与备份导入共用，避免两处字段漂移 */
  private recordBucket(record: SongRecord): relationalStore.ValuesBucket {
    return {
      id: record.id,
      song_name: record.songName,
      artist_name: record.artistName,
      bpm: record.bpm,
      timestamp: record.timestamp,
      tap_count: record.tapCount,
      average_interval: record.averageInterval,
      musical_key: record.musicalKey,
      genre: record.genre,
      energy: record.energy,
      duration_sec: record.durationSec,
      note: record.note
    };
  }

  /**
   * 插入一条记录
   */
  async insert(record: SongRecord): Promise<number> {
    const store = this.ensureStore();
    const rowId = await store.insert(TABLE_NAME, this.recordBucket(record));
    console.info(`DatabaseHelper: 插入记录成功, rowId=${rowId}`);
    return rowId;
  }

  /**
   * 更新曲目的可编辑字段（不含测速统计）
   */
  async updateSong(record: SongRecord): Promise<number> {
    const store = this.ensureStore();
    const valueBucket: relationalStore.ValuesBucket = {
      song_name: record.songName,
      artist_name: record.artistName,
      bpm: record.bpm,
      musical_key: record.musicalKey,
      genre: record.genre,
      energy: record.energy,
      duration_sec: record.durationSec,
      note: record.note
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', record.id);
    const rows = await store.update(valueBucket, predicates);
    AppStorage.setOrCreate('recordsNeedRefresh', Date.now());
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return rows;
  }

  /**
   * 查询所有记录，按时间戳降序
   */
  async queryAll(): Promise<SongRecord[]> {
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.orderByDesc('timestamp');

    const resultSet = await store.query(predicates);
    const records: SongRecord[] = [];
    let count = resultSet.rowCount;

    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        records.push(this.mapRow(resultSet));
        resultSet.goToNextRow();
      }
    }
    resultSet.close();
    console.info(`DatabaseHelper: 查询到 ${records.length} 条记录`);
    return records;
  }

  /**
   * 按 ID 数组批量删除；同时清理歌单中的关联曲目，保证数据一致
   */
  async deleteByIds(ids: number[]): Promise<number> {
    if (ids.length === 0) {
      return 0;
    }
    const store = this.ensureStore();
    let totalRows = 0;
    await store.beginTransaction();
    try {
      for (const id of ids) {
        const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
        predicates.equalTo('id', id);
        const rows = await store.delete(predicates);
        totalRows += rows;
      }
      await store.commit();
      console.info(`DatabaseHelper: 删除 ${totalRows} 条记录, ids=${ids.join(',')}`);
    } catch (err) {
      await store.rollBack();
      console.error(`DatabaseHelper: 批量删除 song_records 失败, ids=${ids.join(',')}, error=${JSON.stringify(err)}`);
      throw err as Error;
    }
    // 清理歌单中的关联曲目：尽力而为，失败不影响主删除结果
    try {
      const itemPredicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
      itemPredicates.in('record_id', ids);
      await store.delete(itemPredicates);
    } catch (err) {
      console.error(`DatabaseHelper: 清理 setlist_items 失败（已忽略）, ids=${ids.join(',')}, error=${JSON.stringify(err)}`);
    }
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return totalRows;
  }

  /**
   * 关键字模糊查询（歌名或歌手匹配），按时间戳降序
   */
  async queryByKeyword(keyword: string): Promise<SongRecord[]> {
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.contains('song_name', keyword)
      .or()
      .contains('artist_name', keyword);
    predicates.orderByDesc('timestamp');
    const resultSet = await store.query(predicates);
    return this.mapResultSet(resultSet);
  }

  /**
   * BPM 范围查询，按与中心 BPM 的距离升序排序
   */
  async queryByBpmRange(center: number, range: number): Promise<SongRecord[]> {
    const store = this.ensureStore();
    const low = center - range;
    const high = center + range;
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.between('bpm', low, high);
    predicates.orderByAsc('bpm');
    const resultSet = await store.query(predicates);
    const records = this.mapResultSet(resultSet);
    records.sort((a: SongRecord, b: SongRecord) => Math.abs(a.bpm - center) - Math.abs(b.bpm - center));
    return records;
  }

  /**
   * 综合搜索：歌曲名/歌手名模糊匹配；若输入为纯数字，则同时按 BPM 精确匹配。
   */
  async queryByKeywordOrBpm(keyword: string): Promise<SongRecord[]> {
    const kw = keyword.trim();
    if (!kw) {
      return [];
    }
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.contains('song_name', kw)
      .or()
      .contains('artist_name', kw);
    if (/^\d+$/.test(kw)) {
      const num = Number(kw);
      if (Number.isFinite(num)) {
        predicates.or().equalTo('bpm', num);
      }
    }
    predicates.orderByDesc('timestamp');
    const resultSet = await store.query(predicates);
    return this.mapResultSet(resultSet);
  }

  // ---------------- 歌单 ----------------

  async querySetlists(): Promise<Setlist[]> {
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
    // 按**创建时间**倒序：列表最上面永远是最新创建的歌单。
    // 之前用的是 updated_at，于是重命名 / 加歌 / 清空都会把歌单顶到最前，看起来顺序毫无规律
    // （复制歌单走 insertSetlist，也会带上新的 created_at）。同一时刻创建的（例如导入备份）
    // 再用 id 倒序做次级排序，保证顺序稳定可预期。
    predicates.orderByDesc('created_at');
    predicates.orderByDesc('id');
    const resultSet = await store.query(predicates);
    const list: Setlist[] = [];
    const count: number = resultSet.rowCount;
    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        list.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          name: resultSet.getString(resultSet.getColumnIndex('name')),
          note: resultSet.getString(resultSet.getColumnIndex('note')),
          createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
          updatedAt: resultSet.getLong(resultSet.getColumnIndex('updated_at'))
        });
        resultSet.goToNextRow();
      }
    }
    resultSet.close();
    return list;
  }

  async insertSetlist(name: string): Promise<number> {
    const store = this.ensureStore();
    const now: number = Date.now();
    const valueBucket: relationalStore.ValuesBucket = {
      name: name,
      note: '',
      created_at: now,
      updated_at: now
    };
    const rowId: number = await store.insert(TABLE_SETLIST, valueBucket);
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return rowId;
  }

  async renameSetlist(id: number, name: string): Promise<void> {
    const store = this.ensureStore();
    const valueBucket: relationalStore.ValuesBucket = {
      name: name,
      updated_at: Date.now()
    };
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
    predicates.equalTo('id', id);
    await store.update(valueBucket, predicates);
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
  }

  async deleteSetlist(id: number): Promise<void> {
    const store = this.ensureStore();
    await store.beginTransaction();
    try {
      const itemPredicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
      itemPredicates.equalTo('setlist_id', id);
      await store.delete(itemPredicates);
      const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
      predicates.equalTo('id', id);
      await store.delete(predicates);
      await store.commit();
    } catch (err) {
      await store.rollBack();
      throw err as Error;
    }
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
  }

  /** 复制歌单（含曲目顺序），返回新歌单 id */
  async duplicateSetlist(id: number, newName: string): Promise<number> {
    const tracks: SetlistTrack[] = await this.querySetlistTracks(id);
    const newId: number = await this.insertSetlist(newName);
    if (tracks.length > 0) {
      const ids: number[] = [];
      for (let i = 0; i < tracks.length; i++) {
        ids.push(tracks[i].recordId);
      }
      await this.addTracksToSetlist(newId, ids);
    }
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return newId;
  }

  async clearSetlist(setlistId: number): Promise<void> {
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
    predicates.equalTo('setlist_id', setlistId);
    await store.delete(predicates);
    const setPredicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
    setPredicates.equalTo('id', setlistId);
    const stamp: relationalStore.ValuesBucket = { updated_at: Date.now() };
    await store.update(stamp, setPredicates);
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
  }

  /** 查询歌单内的曲目（按 sort_order 升序），已按曲库数据补全曲目信息 */
  async querySetlistTracks(setlistId: number): Promise<SetlistTrack[]> {
    const pairs: RecordIdPair[] = await this.queryItemPairs(setlistId);
    if (pairs.length === 0) {
      return [];
    }
    const all: SongRecord[] = await this.queryAll();
    const tracks: SetlistTrack[] = [];
    for (let i = 0; i < pairs.length; i++) {
      const found: SongRecord | undefined = all.find((r: SongRecord) => r.id === pairs[i].recordId);
      if (found) {
        tracks.push({ itemId: pairs[i].itemId, recordId: pairs[i].recordId, record: found });
      }
    }
    return tracks;
  }

  private async queryItemPairs(setlistId: number): Promise<RecordIdPair[]> {
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
    predicates.equalTo('setlist_id', setlistId);
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const resultSet = await store.query(predicates);
    const pairs: RecordIdPair[] = [];
    const count: number = resultSet.rowCount;
    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        pairs.push({
          itemId: resultSet.getLong(resultSet.getColumnIndex('id')),
          recordId: resultSet.getLong(resultSet.getColumnIndex('record_id'))
        });
        resultSet.goToNextRow();
      }
    }
    resultSet.close();
    return pairs;
  }

  /** 批量追加曲目到歌单末尾，已存在的曲目会被跳过，返回实际新增数量 */
  async addTracksToSetlist(setlistId: number, recordIds: number[]): Promise<number> {
    if (recordIds.length === 0) {
      return 0;
    }
    const existing: SetlistTrack[] = await this.querySetlistTracks(setlistId);
    const existingIds: number[] = existing.map((t: SetlistTrack) => t.recordId);
    const store = this.ensureStore();
    const now: number = Date.now();
    let order: number = existing.length;
    let added: number = 0;
    await store.beginTransaction();
    try {
      for (let i = 0; i < recordIds.length; i++) {
        if (existingIds.includes(recordIds[i])) {
          continue;
        }
        const valueBucket: relationalStore.ValuesBucket = {
          setlist_id: setlistId,
          record_id: recordIds[i],
          sort_order: order,
          added_at: now
        };
        await store.insert(TABLE_SETLIST_ITEM, valueBucket);
        order++;
        added++;
      }
      const setPredicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
      setPredicates.equalTo('id', setlistId);
      const stamp: relationalStore.ValuesBucket = { updated_at: Date.now() };
      await store.update(stamp, setPredicates);
      await store.commit();
    } catch (err) {
      await store.rollBack();
      throw err as Error;
    }
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return added;
  }

  async removeTrackFromSetlist(itemId: number, setlistId: number): Promise<void> {
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
    predicates.equalTo('id', itemId);
    await store.delete(predicates);
    const setPredicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
    setPredicates.equalTo('id', setlistId);
    const stamp: relationalStore.ValuesBucket = { updated_at: Date.now() };
    await store.update(stamp, setPredicates);
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
  }

  /** 按 itemId 批量移除歌单曲目（多选批量操作），并刷新歌单时间戳 */
  async removeTracksFromSetlist(itemIds: number[], setlistId: number): Promise<number> {
    if (itemIds.length === 0) {
      return 0;
    }
    const store: relationalStore.RdbStore = this.ensureStore();
    let rows: number = 0;
    await store.beginTransaction();
    try {
      const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
      predicates.equalTo('setlist_id', setlistId);
      predicates.in('id', itemIds);
      rows = await store.delete(predicates);
      const setPredicates = new relationalStore.RdbPredicates(TABLE_SETLIST);
      setPredicates.equalTo('id', setlistId);
      const stamp: relationalStore.ValuesBucket = { updated_at: Date.now() };
      await store.update(stamp, setPredicates);
      await store.commit();
    } catch (err) {
      await store.rollBack();
      console.error(`DatabaseHelper: 批量移除曲目失败, error=${JSON.stringify(err)}`);
      throw err as Error;
    }
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return rows;
  }

  /** 按给定的曲目 id 顺序重排歌单 */
  async reorderSetlist(setlistId: number, recordIds: number[]): Promise<void> {
    const pairs: RecordIdPair[] = await this.queryItemPairs(setlistId);
    const store = this.ensureStore();
    await store.beginTransaction();
    try {
      for (let i = 0; i < recordIds.length; i++) {
        const target: RecordIdPair | undefined =
          pairs.find((p: RecordIdPair) => p.recordId === recordIds[i]);
        if (!target) {
          continue;
        }
        const valueBucket: relationalStore.ValuesBucket = { sort_order: i };
        const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
        predicates.equalTo('id', target.itemId);
        await store.update(valueBucket, predicates);
      }
      await store.commit();
    } catch (err) {
      await store.rollBack();
      throw err as Error;
    }
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
  }

  /**
   * 一次性读取全部歌单的汇总信息（曲目数、总时长、BPM 区间、调性分布）。
   * 只查一次曲目表与关联表，避免歌单数量增多时产生 N 次查询。
   */
  async queryAllSetlistSummaries(): Promise<SetlistSummary[]> {
    const setlists: Setlist[] = await this.querySetlists();
    const allRecords: SongRecord[] = await this.queryAll();
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
    predicates.orderByAsc('setlist_id');
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const resultSet = await store.query(predicates);
    const grouped: SetlistRecordGroup[] = [];
    const count: number = resultSet.rowCount;
    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        const setlistId: number = resultSet.getLong(resultSet.getColumnIndex('setlist_id'));
        const recordId: number = resultSet.getLong(resultSet.getColumnIndex('record_id'));
        let group: SetlistRecordGroup | undefined =
          grouped.find((g: SetlistRecordGroup) => g.setlistId === setlistId);
        if (!group) {
          group = { setlistId: setlistId, recordIds: [] };
          grouped.push(group);
        }
        group.recordIds.push(recordId);
        resultSet.goToNextRow();
      }
    }
    resultSet.close();

    const summaries: SetlistSummary[] = [];
    for (let i = 0; i < setlists.length; i++) {
      const group: SetlistRecordGroup | undefined =
        grouped.find((g: SetlistRecordGroup) => g.setlistId === setlists[i].id);
      const tracks: SongRecord[] = [];
      if (group) {
        for (let j = 0; j < group.recordIds.length; j++) {
          const found: SongRecord | undefined =
            allRecords.find((r: SongRecord) => r.id === group.recordIds[j]);
          if (found) {
            tracks.push(found);
          }
        }
      }
      const stats = computeStats(tracks);
      const keyList: string[] = [];
      for (let j = 0; j < tracks.length; j++) {
        const key: string = tracks[j].musicalKey;
        if (key.length > 0 && keyList.indexOf(key) < 0) {
          keyList.push(key);
        }
      }
      summaries.push({
        setlist: setlists[i],
        trackCount: stats.count,
        totalDuration: stats.totalDuration,
        minBpm: stats.minBpm,
        maxBpm: stats.maxBpm,
        avgBpm: stats.avgBpm,
        avgEnergy: stats.avgEnergy,
        keyList: keyList
      });
    }
    return summaries;
  }

  // ---------------- 备份 / 恢复 ----------------

  /**
   * 导出备份用：读出全部歌单及其曲目 id 顺序。
   * 只查歌单表与关联表，不查曲目表，避免歌单数量增多时产生 N 次查询。
   */
  async queryBackupSetlists(): Promise<BackupSetlist[]> {
    const setlists: Setlist[] = await this.querySetlists();
    if (setlists.length === 0) {
      return [];
    }
    const store = this.ensureStore();
    const predicates = new relationalStore.RdbPredicates(TABLE_SETLIST_ITEM);
    predicates.orderByAsc('setlist_id');
    predicates.orderByAsc('sort_order');
    predicates.orderByAsc('id');
    const resultSet = await store.query(predicates);
    const grouped: SetlistRecordGroup[] = [];
    const count: number = resultSet.rowCount;
    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        const setlistId: number = resultSet.getLong(resultSet.getColumnIndex('setlist_id'));
        const recordId: number = resultSet.getLong(resultSet.getColumnIndex('record_id'));
        let group: SetlistRecordGroup | undefined =
          grouped.find((g: SetlistRecordGroup) => g.setlistId === setlistId);
        if (!group) {
          group = { setlistId: setlistId, recordIds: [] };
          grouped.push(group);
        }
        group.recordIds.push(recordId);
        resultSet.goToNextRow();
      }
    }
    resultSet.close();

    const result: BackupSetlist[] = [];
    for (let i = 0; i < setlists.length; i++) {
      const group: SetlistRecordGroup | undefined =
        grouped.find((g: SetlistRecordGroup) => g.setlistId === setlists[i].id);
      result.push({
        name: setlists[i].name,
        note: setlists[i].note,
        recordIds: group ? group.recordIds : []
      });
    }
    return result;
  }

  /** 新歌单名去重：重名时依次追加 (2)、(3)…，绝不覆盖已有歌单 */
  private uniqueSetlistName(base: string, used: string[]): string {
    if (used.indexOf(base) < 0) {
      return base;
    }
    let index: number = 2;
    while (used.indexOf(`${base} (${index})`) >= 0) {
      index++;
    }
    return `${base} (${index})`;
  }

  /**
   * 导入备份。
   *
   * 关键约定：
   * - 曲目一律重新分配 id（现有 id 由 Date.now() 生成，直接沿用会主键冲突）；
   * - 歌单一律作为新歌单创建，重名自动加序号，不修改/覆盖任何现有歌单；
   * - skipDuplicates 为真时按「歌名 + 歌手」跳过已有曲目，此时歌单里对这些曲目的引用
   *   会重定向到已有记录，所以歌单不会因为跳过而缺歌。
   */
  async importBackup(parsed: ParsedBackup, skipDuplicates: boolean): Promise<ImportResult> {
    const store: relationalStore.RdbStore = this.ensureStore();
    const existing: SongRecord[] = await this.queryAll();

    // 判重表：keys 与 ids 按下标一一对应（先放现有曲库，再放本次新插入的）
    const keys: string[] = [];
    const ids: number[] = [];
    let nextId: number = Date.now();
    for (let i = 0; i < existing.length; i++) {
      keys.push(recordDuplicateKey(existing[i]));
      ids.push(existing[i].id);
      if (existing[i].id >= nextId) {
        nextId = existing[i].id + 1;
      }
    }

    // 旧 id → 新 id 映射，供歌单曲目重定向
    const idMap = new Map<number, number>();
    const toInsert: SongRecord[] = [];
    let skipped: number = 0;
    for (let i = 0; i < parsed.records.length; i++) {
      const incoming: SongRecord = parsed.records[i];
      const key: string = recordDuplicateKey(incoming);
      const at: number = keys.indexOf(key);
      const duplicateId: number = at >= 0 ? ids[at] : 0;
      if (duplicateId > 0 && skipDuplicates) {
        skipped++;
        if (incoming.id > 0) {
          idMap.set(incoming.id, duplicateId);
        }
        continue;
      }
      const fresh: SongRecord = {
        id: nextId,
        songName: incoming.songName,
        artistName: incoming.artistName,
        bpm: incoming.bpm,
        timestamp: incoming.timestamp > 0 ? incoming.timestamp : Date.now(),
        tapCount: incoming.tapCount,
        averageInterval: incoming.averageInterval,
        musicalKey: incoming.musicalKey,
        genre: incoming.genre,
        energy: incoming.energy,
        durationSec: incoming.durationSec,
        note: incoming.note
      };
      nextId++;
      toInsert.push(fresh);
      keys.push(key);
      ids.push(fresh.id);
      if (incoming.id > 0) {
        idMap.set(incoming.id, fresh.id);
      }
    }

    const existingSetlists: Setlist[] = await this.querySetlists();
    const usedNames: string[] = [];
    for (let i = 0; i < existingSetlists.length; i++) {
      usedNames.push(existingSetlists[i].name);
    }

    const now: number = Date.now();
    let setlistCount: number = 0;
    let setlistTracks: number = 0;
    await store.beginTransaction();
    try {
      for (let i = 0; i < toInsert.length; i++) {
        await store.insert(TABLE_NAME, this.recordBucket(toInsert[i]));
      }
      for (let i = 0; i < parsed.setlists.length; i++) {
        const source: BackupSetlist = parsed.setlists[i];
        const trackIds: number[] = [];
        for (let j = 0; j < source.recordIds.length; j++) {
          const mapped: number | undefined = idMap.get(source.recordIds[j]);
          if (mapped !== undefined) {
            trackIds.push(mapped);
          }
        }
        const name: string = this.uniqueSetlistName(source.name, usedNames);
        usedNames.push(name);
        const setlistRow: number = await store.insert(TABLE_SETLIST, {
          name: name,
          note: source.note,
          created_at: now,
          updated_at: now
        });
        for (let j = 0; j < trackIds.length; j++) {
          await store.insert(TABLE_SETLIST_ITEM, {
            setlist_id: setlistRow,
            record_id: trackIds[j],
            sort_order: j,
            added_at: now
          });
        }
        setlistCount++;
        setlistTracks += trackIds.length;
      }
      await store.commit();
    } catch (err) {
      await store.rollBack();
      console.error(`DatabaseHelper: 导入备份失败, error=${JSON.stringify(err)}`);
      throw err as Error;
    }

    console.info(`DatabaseHelper: 导入完成, 曲目 ${toInsert.length} 条, 跳过 ${skipped} 条, 歌单 ${setlistCount} 个`);
    AppStorage.setOrCreate('recordsNeedRefresh', Date.now());
    AppStorage.setOrCreate('setlistsNeedRefresh', Date.now());
    return {
      inserted: toInsert.length,
      skipped: skipped,
      setlists: setlistCount,
      setlistTracks: setlistTracks
    };
  }

  private mapResultSet(resultSet: relationalStore.ResultSet): SongRecord[] {
    const records: SongRecord[] = [];
    const count = resultSet.rowCount;
    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        records.push(this.mapRow(resultSet));
        resultSet.goToNextRow();
      }
    }
    resultSet.close();
    return records;
  }

  private mapRow(resultSet: relationalStore.ResultSet): SongRecord {
    return {
      id: resultSet.getLong(resultSet.getColumnIndex('id')),
      songName: resultSet.getString(resultSet.getColumnIndex('song_name')),
      artistName: resultSet.getString(resultSet.getColumnIndex('artist_name')),
      bpm: resultSet.getLong(resultSet.getColumnIndex('bpm')),
      timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp')),
      tapCount: resultSet.getLong(resultSet.getColumnIndex('tap_count')),
      averageInterval: resultSet.getDouble(resultSet.getColumnIndex('average_interval')),
      musicalKey: this.safeString(resultSet, 'musical_key'),
      genre: this.safeString(resultSet, 'genre'),
      energy: this.safeLong(resultSet, 'energy'),
      durationSec: this.safeLong(resultSet, 'duration_sec'),
      note: this.safeString(resultSet, 'note')
    };
  }

  /** 兼容尚未完成迁移的旧数据：列不存在时返回默认值 */
  private safeString(resultSet: relationalStore.ResultSet, column: string): string {
    const idx: number = resultSet.getColumnIndex(column);
    if (idx < 0) {
      return '';
    }
    try {
      return resultSet.getString(idx);
    } catch (err) {
      return '';
    }
  }

  private safeLong(resultSet: relationalStore.ResultSet, column: string): number {
    const idx: number = resultSet.getColumnIndex(column);
    if (idx < 0) {
      return 0;
    }
    try {
      return resultSet.getLong(idx);
    } catch (err) {
      return 0;
    }
  }

  /**
   * 关闭数据库（应用退出时调用）
   */
  async close(): Promise<void> {
    if (this.rdbStore) {
      await this.rdbStore.close();
      this.rdbStore = null;
      this.initPromise = null;
      console.info('DatabaseHelper: 数据库已关闭');
    }
  }
}
