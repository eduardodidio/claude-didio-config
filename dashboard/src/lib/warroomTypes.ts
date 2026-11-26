// War Room status columns
export type WarRoomStatus = 'incoming' | 'triaging' | 'promoted' | 'deferred' | 'archived';

export const WARROOM_COLUMNS: readonly WarRoomStatus[] = [
  'incoming', 'triaging', 'promoted', 'deferred', 'archived',
] as const;

export const WARROOM_COLUMN_LABELS: Record<WarRoomStatus, string> = {
  incoming: 'Incoming',
  triaging: 'Triaging',
  promoted: 'Promoted',
  deferred: 'Deferred',
  archived: 'Archived',
};

// Card source
export type CardSource = 'operator' | 'agent' | 'external';

// Priority levels (shared with Black Hawk Alpha assessment)
export type Priority = 'low' | 'medium' | 'high' | 'max';

// Black Hawk Alpha recommendation (type name kept as OverlordRecommendation for backward compat with card JSON)
export type OverlordRecommendation = 'promote' | 'defer' | 'archive' | 'needs_input';

// Black Hawk Alpha assessment object (type name kept as OverlordAssessment for backward compat with card JSON)
export interface OverlordAssessment {
  assessed_at: string;
  recommendation: OverlordRecommendation;
  priority: Priority;
  rationale: string;
  promoted_as: string | null;
}

// War Room card
export interface WarRoomCard {
  card_id: string;
  title: string;
  body: string;
  source: CardSource;
  created_at: string;
  updated_at: string | null;
  status: WarRoomStatus;
  priority_suggestion: Priority | null;
  overlord_assessment: OverlordAssessment | null;
  promoted_to: string | null;
  tags: string[];
  source_agent: string | null;
  source_feature: string | null;
}

// Board state aggregation
export interface WarRoomBoardState {
  cards: WarRoomCard[];
  columns: Record<WarRoomStatus, WarRoomCard[]>;
  total: number;
  incoming_count: number;
  generated_at: string;
}

// Create-card input (subset of fields the operator provides)
export interface CreateCardInput {
  title: string;
  body: string;
  source?: CardSource;
  priority_suggestion?: Priority | null;
  tags?: string[];
}
