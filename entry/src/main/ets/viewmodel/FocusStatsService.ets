import { DatabaseHelper } from '../database/DatabaseHelper'
import { FocusSession } from '../models/FocusSession'

export interface DailyStats {
  date: string
  totalMinutes: number
  sessionCount: number
  avgFlowScore: number
}

export interface WeeklyReport {
  weekLabel: string
  totalMinutes: number
  dailyAvg: number
  sessionCount: number
  bestDay: string
  topTag: string
  streakDays: number
}

export interface UsageOverview {
  totalMinutesAll: number
  totalSessionsAll: number
  daysSinceFirstUse: number
  averageDailyMinutes: number
  averageSessionMinutes: number
  mostProductiveHour: number
  currentStreak: number
  longestStreak: number
}

export class FocusStatsService {
  private db: DatabaseHelper = DatabaseHelper.getInstance()
  private static instance: FocusStatsService

  static getInstance(): FocusStatsService {
    if (!FocusStatsService.instance) {
      FocusStatsService.instance = new FocusStatsService()
    }
    return FocusStatsService.instance
  }

  async getUsageOverview(): Promise<UsageOverview> {
    const now = new Date()
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime()
    const todayEnd = todayStart + 24 * 60 * 60 * 1000
    const allSessions = await this.db.querySessionsByRange(0, todayEnd)

    if (allSessions.length === 0) {
      return {
        totalMinutesAll: 0, totalSessionsAll: 0, daysSinceFirstUse: 0,
        averageDailyMinutes: 0, averageSessionMinutes: 0,
        mostProductiveHour: 0, currentStreak: 0, longestStreak: 0
      }
    }

    let totalSeconds = 0
    for (let i = 0; i < allSessions.length; i++) {
      totalSeconds += allSessions[i].actualDuration
    }
    const totalMinutesAll = Math.floor(totalSeconds / 60)
    const avgSessionMin = Math.floor(totalSeconds / allSessions.length / 60)

    const firstSession = allSessions[allSessions.length - 1]
    const firstDay = new Date(firstSession.startTime)
    firstDay.setHours(0, 0, 0, 0)
    const daysSinceFirst = Math.max(1, Math.ceil((todayStart - firstDay.getTime()) / 86400000) + 1)
    const avgDailyMin = Math.floor(totalMinutesAll / daysSinceFirst)

    const hourMap: Map<number, number> = new Map()
    for (let i = 0; i < allSessions.length; i++) {
      const h = new Date(allSessions[i].startTime).getHours()
      const cur = hourMap.get(h)
      hourMap.set(h, (cur ? cur : 0) + allSessions[i].actualDuration)
    }
    let bestHour = 0
    let bestVal = 0
    hourMap.forEach((val: number, key: number) => {
      if (val > bestVal) { bestVal = val; bestHour = key }
    })

    const currentStreak = await this.calcCurrentStreak()
    const longestStreak = await this.calcLongestStreak()

    return {
      totalMinutesAll, totalSessionsAll: allSessions.length,
      daysSinceFirstUse: daysSinceFirst, averageDailyMinutes: avgDailyMin,
      averageSessionMinutes: avgSessionMin, mostProductiveHour: bestHour,
      currentStreak: currentStreak, longestStreak: longestStreak
    }
  }

  async getDailyStats(days: number): Promise<DailyStats[]> {
    const result: DailyStats[] = []
    const now = new Date()
    for (let i = days - 1; i >= 0; i--) {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
      d.setHours(0, 0, 0, 0)
      const from = d.getTime()
      const to = from + 86400000
      const sessions = await this.db.querySessionsByRange(from, to)
      let sec = 0
      let flow = 0
      for (let j = 0; j < sessions.length; j++) {
        sec += sessions[j].actualDuration
        flow += sessions[j].flowScore
      }
      const dateStr = `${d.getFullYear()}-${(d.getMonth() + 1).toString().padStart(2, '0')}-${d.getDate().toString().padStart(2, '0')}`
      result.push({
        date: dateStr,
        totalMinutes: Math.floor(sec / 60),
        sessionCount: sessions.length,
        avgFlowScore: sessions.length > 0 ? Math.floor(flow / sessions.length) : 0
      })
    }
    return result
  }

  async getWeeklyReports(weeks: number): Promise<WeeklyReport[]> {
    const result: WeeklyReport[] = []
    const now = new Date()
    for (let w = weeks - 1; w >= 0; w--) {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - w * 7)
      const dayOfWeek = d.getDay()
      const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((dayOfWeek + 6) % 7))
      monday.setHours(0, 0, 0, 0)
      const sunday = new Date(monday.getTime() + 7 * 86400000)

      const sessions = await this.db.querySessionsByRange(monday.getTime(), sunday.getTime())
      let sec = 0
      const dayMap: Map<string, number> = new Map()
      const tagMap: Map<string, number> = new Map()
      for (let i = 0; i < sessions.length; i++) {
        const s = sessions[i]
        sec += s.actualDuration
        const dayKey = new Date(s.startTime).toDateString()
        const dv = dayMap.get(dayKey)
        dayMap.set(dayKey, (dv ? dv : 0) + s.actualDuration)
        const tv = tagMap.get(s.tag)
        tagMap.set(s.tag, (tv ? tv : 0) + s.actualDuration)
      }

      let bestDay = '-'
      let bestSec = 0
      dayMap.forEach((v: number, k: string) => { if (v > bestSec) { bestSec = v; bestDay = k } })
      let topTag = '-'
      let topSec = 0
      tagMap.forEach((v: number, k: string) => { if (v > topSec) { topSec = v; topTag = k } })

      result.push({
        weekLabel: `${monday.getFullYear()}-W${this.getWeekNumber(monday).toString().padStart(2, '0')}`,
        totalMinutes: Math.floor(sec / 60),
        dailyAvg: sessions.length > 0 ? Math.floor(sec / 7 / 60) : 0,
        sessionCount: sessions.length,
        bestDay: bestDay,
        topTag: topTag,
        streakDays: this.countActiveDays(monday.getTime(), sunday.getTime(), sessions)
      })
    }
    return result
  }

  async getTagStats(from: number, to: number): Promise<Record<string, number>> {
    return this.db.getTagDistribution(from, to)
  }

  async getHourlyDistribution(from: number, to: number): Promise<number[]> {
    const sessions = await this.db.querySessionsByRange(from, to)
    const hours = new Array<number>(24).fill(0)
    for (let i = 0; i < sessions.length; i++) {
      const h = new Date(sessions[i].startTime).getHours()
      hours[h] += sessions[i].actualDuration
    }
    // 统一转换为分钟，确保与其他统计方法一致
    for (let i = 0; i < hours.length; i++) {
      hours[i] = Math.floor(hours[i] / 60)
    }
    return hours
  }

  private async calcCurrentStreak(): Promise<number> {
    let streak = 0
    const now = new Date()
    for (let i = 0; i < 365; i++) {
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate() - i)
      d.setHours(0, 0, 0, 0)
      const from = d.getTime()
      const count = await this.db.getSessionCount(from, from + 86400000)
      if (count > 0) { streak++ }
      else if (i === 0) { continue }
      else { break }
    }
    return streak
  }

  private async calcLongestStreak(): Promise<number> {
    const all = await this.db.querySessionsByRange(0, Date.now() + 86400000)
    if (all.length === 0) return 0
    const daySet: Set<string> = new Set()
    for (let i = 0; i < all.length; i++) {
      const d = new Date(all[i].startTime)
      d.setHours(0, 0, 0, 0)
      daySet.add(d.toISOString().split('T')[0])
    }
    const sorted = Array.from(daySet).sort()
    let longest = 0
    let cur = 1
    for (let i = 1; i < sorted.length; i++) {
      const prev = new Date(sorted[i - 1]).getTime()
      const curr = new Date(sorted[i]).getTime()
      if (curr - prev <= 86400000) { cur++ }
      else { longest = Math.max(longest, cur); cur = 1 }
    }
    return Math.max(longest, cur)
  }

  private getWeekNumber(d: Date): number {
    const jan1 = new Date(d.getFullYear(), 0, 1)
    return Math.ceil(((d.getTime() - jan1.getTime()) / 86400000 + jan1.getDay() + 1) / 7)
  }

  private countActiveDays(from: number, to: number, sessions: FocusSession[]): number {
    const set: Set<string> = new Set()
    for (let i = 0; i < sessions.length; i++) {
      const s = sessions[i]
      if (s.startTime >= from && s.startTime < to) {
        set.add(new Date(s.startTime).toDateString())
      }
    }
    return set.size
  }
}
