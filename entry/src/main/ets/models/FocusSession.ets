/*
 * FocusSession - 专注会话数据模型
 */
export enum FocusState {
  IDLE = 'IDLE',
  RUNNING = 'RUNNING',
  PAUSED = 'PAUSED',
  COMPLETED = 'COMPLETED',
  INTERRUPTED = 'INTERRUPTED'
}

export enum SessionType {
  POMODORO = 'POMODORO',
  DEEP_FOCUS = 'DEEP_FOCUS',
  CUSTOM = 'CUSTOM'
}

export interface InterruptionRecord {
  id: string
  timestamp: number
  duration: number
  reason: string
}

export interface FocusSession {
  id: string
  taskName: string
  tag: string
  startTime: number
  endTime: number
  plannedDuration: number
  actualDuration: number
  state: FocusState
  sessionType: SessionType
  interruptions: InterruptionRecord[]
  flowScore: number
  notes: string
}

export const DEFAULT_POMODORO_DURATION = 25 * 60
export const DEFAULT_DEEP_FOCUS_DURATION = 45 * 60
