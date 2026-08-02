import { relationalStore } from '@kit.ArkData'
import { Context } from '@kit.AbilityKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { FocusSession, FocusState, SessionType } from '../models/FocusSession'

const TAG = 'KnowTimeDB'
const DOMAIN = 0x0002

/*
 * 数据库存储配置
 *
 * ★ 安全级别说明：
 *   S1 = 设备解锁后可用，卸载后数据删除
 *   S2 = 设备解锁后可用，卸载后数据删除
 *   S3 = 设备解锁后可用，卸载后数据保留（需用户确认）
 *   S4 = 设备解锁后可用，卸载后数据保留（最安全）
 *
 * 改用 S4 确保卸载重装后数据不丢失
 */
const DB_NAME = 'KnowTime.db'
const DB_SECURITY = relationalStore.SecurityLevel.S4

const TABLE_SESSIONS = 'focus_sessions'
const TABLE_INTERRUPTIONS = 'interruptions'

export class DatabaseHelper {
  private static instance: DatabaseHelper
  private store: relationalStore.RdbStore | null = null

  static getInstance(): DatabaseHelper {
    if (!DatabaseHelper.instance) {
      DatabaseHelper.instance = new DatabaseHelper()
    }
    return DatabaseHelper.instance
  }

  async init(context: Context): Promise<void> {
    if (this.store) return
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: DB_SECURITY
    }
    hilog.info(DOMAIN, TAG, 'init() store with security=S4')
    this.store = await relationalStore.getRdbStore(context, config)
    await this.createTables()
    hilog.info(DOMAIN, TAG, 'DB init done (data persists across uninstall)')
  }

  private async createTables(): Promise<void> {
    if (!this.store) return
    const sql1 = `CREATE TABLE IF NOT EXISTS ${TABLE_SESSIONS} (
      id TEXT PRIMARY KEY, task_name TEXT, tag TEXT,
      start_time INTEGER, end_time INTEGER, planned_duration INTEGER,
      actual_duration INTEGER, state TEXT, session_type TEXT,
      flow_score INTEGER, notes TEXT)`
    const sql2 = `CREATE TABLE IF NOT EXISTS ${TABLE_INTERRUPTIONS} (
      id TEXT PRIMARY KEY, session_id TEXT, timestamp INTEGER,
      duration INTEGER, reason TEXT)`
    await this.store.executeSql(sql1)
    await this.store.executeSql(sql2)
  }

  async insertSession(session: FocusSession): Promise<void> {
    if (!this.store) return
    const vb: relationalStore.ValuesBucket = {
      id: session.id, task_name: session.taskName, tag: session.tag,
      start_time: session.startTime, end_time: session.endTime,
      planned_duration: session.plannedDuration, actual_duration: session.actualDuration,
      state: session.state, session_type: session.sessionType,
      flow_score: session.flowScore, notes: session.notes
    }
    await this.store.insert(TABLE_SESSIONS, vb)
    for (let i = 0; i < session.interruptions.length; i++) {
      const ir = session.interruptions[i]
      await this.store.insert(TABLE_INTERRUPTIONS, {
        id: ir.id, session_id: session.id, timestamp: ir.timestamp,
        duration: ir.duration, reason: ir.reason
      })
    }
  }

  async queryTodaySessions(): Promise<FocusSession[]> {
    if (!this.store) return []
    const todayStart = this.startOfDay()
    const p = new relationalStore.RdbPredicates(TABLE_SESSIONS)
    p.greaterThanOrEqualTo('start_time', todayStart)
    p.orderByDesc('start_time')
    return this.queryList(p)
  }

  async querySessionsByRange(from: number, to: number): Promise<FocusSession[]> {
    if (!this.store) return []
    const p = new relationalStore.RdbPredicates(TABLE_SESSIONS)
    p.greaterThanOrEqualTo('start_time', from)
    p.lessThan('start_time', to)
    p.orderByDesc('start_time')
    return this.queryList(p)
  }

  async getTotalMinutes(from: number, to: number): Promise<number> {
    const list = await this.querySessionsByRange(from, to)
    let total = 0
    for (let i = 0; i < list.length; i++) {
      total += list[i].actualDuration
    }
    return Math.floor(total / 60)
  }

  async getSessionCount(from: number, to: number): Promise<number> {
    const list = await this.querySessionsByRange(from, to)
    return list.length
  }

  async getTagDistribution(from: number, to: number): Promise<Record<string, number>> {
    const list = await this.querySessionsByRange(from, to)
    const dist: Record<string, number> = {}
    for (let i = 0; i < list.length; i++) {
      const tag = list[i].tag
      dist[tag] = (dist[tag] || 0) + list[i].actualDuration
    }
    // 统一转换为分钟，确保与getTotalMinutes逻辑一致
    for (const tag in dist) {
      dist[tag] = Math.floor(dist[tag] / 60)
    }
    return dist
  }

  async getRecentSessions(limit: number): Promise<FocusSession[]> {
    if (!this.store) return []
    const p = new relationalStore.RdbPredicates(TABLE_SESSIONS)
    p.orderByDesc('start_time')
    p.limitAs(limit)
    return this.queryList(p)
  }

  private async queryList(predicates: relationalStore.RdbPredicates): Promise<FocusSession[]> {
    if (!this.store) return []
    const resultSet = await this.store.query(predicates)
    const list: FocusSession[] = []
    while (resultSet.goToNextRow()) {
      list.push({
        id: resultSet.getString(resultSet.getColumnIndex('id')),
        taskName: resultSet.getString(resultSet.getColumnIndex('task_name')),
        tag: resultSet.getString(resultSet.getColumnIndex('tag')),
        startTime: resultSet.getLong(resultSet.getColumnIndex('start_time')),
        endTime: resultSet.getLong(resultSet.getColumnIndex('end_time')),
        plannedDuration: resultSet.getLong(resultSet.getColumnIndex('planned_duration')),
        actualDuration: resultSet.getLong(resultSet.getColumnIndex('actual_duration')),
        state: resultSet.getString(resultSet.getColumnIndex('state')) as FocusState,
        sessionType: resultSet.getString(resultSet.getColumnIndex('session_type')) as SessionType,
        flowScore: resultSet.getLong(resultSet.getColumnIndex('flow_score')),
        notes: resultSet.getString(resultSet.getColumnIndex('notes')),
        interruptions: []
      })
    }
    resultSet.close()
    return list
  }

  private startOfDay(): number {
    const d = new Date()
    d.setHours(0, 0, 0, 0)
    return d.getTime()
  }

  close(): void {
    if (this.store) {
      this.store.close()
      this.store = null
    }
  }
}
