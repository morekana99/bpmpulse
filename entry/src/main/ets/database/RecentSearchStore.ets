import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME = 'recent_search';
const KEY = 'keywords';
const MAX_COUNT = 10;

/**
 * 最近搜索词持久化（基于 preferences）
 */
export class RecentSearchStore {
  private static instance: RecentSearchStore;
  private prefs: preferences.Preferences | null = null;

  static getInstance(): RecentSearchStore {
    if (!RecentSearchStore.instance) {
      RecentSearchStore.instance = new RecentSearchStore();
    }
    return RecentSearchStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.prefs) {
      return;
    }
    this.prefs = await preferences.getPreferences(context, STORE_NAME);
  }

  private ensure(): preferences.Preferences {
    if (!this.prefs) {
      throw new Error('RecentSearchStore: 未初始化，请先调用 init()');
    }
    return this.prefs;
  }

  async getAll(): Promise<string[]> {
    const p = this.ensure();
    const raw = await p.get(KEY, '[]') as string;
    try {
      const arr = JSON.parse(raw) as string[];
      return Array.isArray(arr) ? arr : [];
    } catch {
      return [];
    }
  }

  async add(keyword: string): Promise<string[]> {
    const kw = keyword.trim();
    if (!kw) {
      return await this.getAll();
    }
    let list = await this.getAll();
    list = list.filter(k => k !== kw);
    list.unshift(kw);
    if (list.length > MAX_COUNT) {
      list = list.slice(0, MAX_COUNT);
    }
    const p = this.ensure();
    await p.put(KEY, JSON.stringify(list));
    await p.flush();
    return list;
  }

  async remove(keyword: string): Promise<string[]> {
    let list = await this.getAll();
    list = list.filter(k => k !== keyword);
    const p = this.ensure();
    await p.put(KEY, JSON.stringify(list));
    await p.flush();
    return list;
  }

  async clear(): Promise<void> {
    const p = this.ensure();
    await p.delete(KEY);
    await p.flush();
  }
}
