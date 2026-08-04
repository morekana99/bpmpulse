import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SongRecord } from '../models/SongRecord';

const DB_NAME = 'BpmPulse.db';
const TABLE_NAME = 'song_records';

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

    this.initPromise = new Promise<void>(async (resolve, reject) => {
      try {
        this.rdbStore = await relationalStore.getRdbStore(context, STORE_CONFIG);
        await this.rdbStore.executeSql(CREATE_TABLE_SQL);
        console.info('DatabaseHelper: 数据库初始化成功');
        resolve();
      } catch (err) {
        const error = err as BusinessError;
        console.error(`DatabaseHelper: 数据库初始化失败, code=${error.code}, msg=${error.message}`);
        this.initPromise = null;
        reject(err);
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
   * 插入一条记录
   */
  async insert(record: SongRecord): Promise<number> {
    const store = this.ensureStore();
    const valueBucket: relationalStore.ValuesBucket = {
      id: record.id,
      song_name: record.songName,
      artist_name: record.artistName,
      bpm: record.bpm,
      timestamp: record.timestamp,
      tap_count: record.tapCount,
      average_interval: record.averageInterval
    };
    const rowId = await store.insert(TABLE_NAME, valueBucket);
    console.info(`DatabaseHelper: 插入记录成功, rowId=${rowId}`);
    return rowId;
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
        records.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          songName: resultSet.getString(resultSet.getColumnIndex('song_name')),
          artistName: resultSet.getString(resultSet.getColumnIndex('artist_name')),
          bpm: resultSet.getLong(resultSet.getColumnIndex('bpm')),
          timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp')),
          tapCount: resultSet.getLong(resultSet.getColumnIndex('tap_count')),
          averageInterval: resultSet.getDouble(resultSet.getColumnIndex('average_interval'))
        });
        resultSet.goToNextRow();
      }
    }
    resultSet.close();
    console.info(`DatabaseHelper: 查询到 ${records.length} 条记录`);
    return records;
  }

  /**
   * 按 ID 数组批量删除
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
      console.error(`DatabaseHelper: 批量删除失败, ids=${ids.join(',')}, error=${JSON.stringify(err)}`);
      throw err as Error;
    }
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
   * 说明：歌曲名本身也可能是纯数字，contains('song_name') 已覆盖该场景，
   * 因此数字输入既匹配同名歌曲，也匹配对应 BPM 的记录。
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
    // 纯数字：按 BPM 精确匹配（歌曲名含数字已由上方 contains 覆盖）
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

  private mapResultSet(resultSet: relationalStore.ResultSet): SongRecord[] {
    const records: SongRecord[] = [];
    const count = resultSet.rowCount;
    if (count > 0) {
      resultSet.goToFirstRow();
      for (let i = 0; i < count; i++) {
        records.push({
          id: resultSet.getLong(resultSet.getColumnIndex('id')),
          songName: resultSet.getString(resultSet.getColumnIndex('song_name')),
          artistName: resultSet.getString(resultSet.getColumnIndex('artist_name')),
          bpm: resultSet.getLong(resultSet.getColumnIndex('bpm')),
          timestamp: resultSet.getLong(resultSet.getColumnIndex('timestamp')),
          tapCount: resultSet.getLong(resultSet.getColumnIndex('tap_count')),
          averageInterval: resultSet.getDouble(resultSet.getColumnIndex('average_interval'))
        });
        resultSet.goToNextRow();
      }
    }
    resultSet.close();
    return records;
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
