// ---- Chat types ----

export interface ChatAction {
  label: string;
  command: string;         // e.g. "didio blackhawk promote WR-001"
  confirmed: boolean;      // whether operator has clicked it
}

export interface ChatMessage {
  id: string;              // UUID
  role: 'operator' | 'alpha';
  content: string;
  actions: ChatAction[];   // only on alpha messages
  timestamp: string;       // ISO-8601
}

export interface ChatHistory {
  messages: ChatMessage[];
  date: string;            // YYYY-MM-DD
}

// ---- Alert types ----

export type AlertSeverity = 'critical' | 'warning' | 'info';
export type AlertStatus = 'active' | 'resolved';

export interface Alert {
  id: string;
  feature: string;
  task: string | null;
  severity: AlertSeverity;
  status: AlertStatus;
  message: string;
  created_at: string;
  resolved_at: string | null;
}

// ---- Board mini types ----

export type BoardColumn = 'BACKLOG' | 'PLANNING' | 'RUNNING' | 'REVIEW' | 'DONE';

export interface BoardCard {
  feature: string;
  column: BoardColumn;
  progress: number;        // 0-100
  taskTotal: number;
  taskDone: number;
  hasBlockage: boolean;
  currentPhase: string | null;
}

export interface BoardState {
  cards: BoardCard[];
  lastUpdated: string;
}

// ---- Settings types ----

export interface BlackHawkSettings {
  silentMode: boolean;
  autoLaunch: boolean;
  notificationSound: boolean;
  avatarPath: string;
  chatHistoryDays: number;
  triageIntervalMinutes: number;
  desktopWidth: number;
  desktopHeight: number;
  desktopPosition: 'bottom-right' | 'bottom-left' | 'top-right' | 'top-left' | 'center';
}

// ---- Tray state ----

export type TrayStatus = 'nominal' | 'alert' | 'muted';

export interface TrayState {
  status: TrayStatus;
  tooltip: string;
  alertCount: number;
}

// ---- Squad health types ----

export type ScannerStatus = 'ok' | 'warning' | 'critical' | 'disabled';

export interface SquadCorrelation {
  type: string;
  detail: string;
  severity: 'warning' | 'critical';
  scanners: string[];
}

export interface SquadReport {
  report_id: string;
  timestamp: string;
  squad_status: {
    bravo: ScannerStatus;
    charlie: ScannerStatus;
    delta: ScannerStatus;
  };
  correlations: SquadCorrelation[];
  overall_status: ScannerStatus;
  cards_created: string[];
}

// ---- Tauri event payloads ----

export interface BoardUpdateEvent {
  state: BoardState;
}

export interface AlertUpdateEvent {
  alerts: Alert[];
}

export interface ChatResponseEvent {
  message: ChatMessage;
}

export interface TrayUpdateEvent {
  state: TrayState;
}
