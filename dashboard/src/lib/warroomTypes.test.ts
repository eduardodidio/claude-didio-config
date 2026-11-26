import { describe, it, expect } from 'vitest';
import type {
  WarRoomStatus,
  CardSource,
  Priority,
  OverlordRecommendation,
  OverlordAssessment,
  WarRoomCard,
  WarRoomBoardState,
  CreateCardInput,
} from './warroomTypes';
import { WARROOM_COLUMNS, WARROOM_COLUMN_LABELS } from './warroomTypes';

describe('warroomTypes', () => {
  it('WarRoomStatus accepts all valid statuses', () => {
    const statuses: WarRoomStatus[] = [
      'incoming', 'triaging', 'promoted', 'deferred', 'archived',
    ];
    expect(statuses).toHaveLength(5);
  });

  it('WARROOM_COLUMNS is a readonly array of 5 columns in order', () => {
    expect(WARROOM_COLUMNS).toEqual([
      'incoming', 'triaging', 'promoted', 'deferred', 'archived',
    ]);
    expect(WARROOM_COLUMNS).toHaveLength(5);
  });

  it('WARROOM_COLUMN_LABELS maps every status to a label', () => {
    expect(WARROOM_COLUMN_LABELS.incoming).toBe('Incoming');
    expect(WARROOM_COLUMN_LABELS.triaging).toBe('Triaging');
    expect(WARROOM_COLUMN_LABELS.promoted).toBe('Promoted');
    expect(WARROOM_COLUMN_LABELS.deferred).toBe('Deferred');
    expect(WARROOM_COLUMN_LABELS.archived).toBe('Archived');
    expect(Object.keys(WARROOM_COLUMN_LABELS)).toHaveLength(5);
  });

  it('CardSource accepts all valid sources', () => {
    const sources: CardSource[] = ['operator', 'agent', 'external'];
    expect(sources).toHaveLength(3);
  });

  it('Priority accepts all valid priority levels', () => {
    const priorities: Priority[] = ['low', 'medium', 'high', 'max'];
    expect(priorities).toHaveLength(4);
  });

  it('OverlordRecommendation accepts all valid recommendations', () => {
    const recs: OverlordRecommendation[] = [
      'promote', 'defer', 'archive', 'needs_input',
    ];
    expect(recs).toHaveLength(4);
  });

  it('accepts a well-formed OverlordAssessment literal', () => {
    const assessment: OverlordAssessment = {
      assessed_at: '2026-11-26T10:00:00Z',
      recommendation: 'promote',
      priority: 'high',
      rationale: 'Aligns with Q1 OKRs',
      promoted_as: 'F32',
    };
    expect(assessment.recommendation).toBe('promote');
    expect(assessment.promoted_as).toBe('F32');
  });

  it('accepts a well-formed WarRoomCard literal', () => {
    const card: WarRoomCard = {
      card_id: 'WR-20261126-001',
      title: 'Auth refactor',
      body: 'Need to refactor authentication module',
      source: 'operator',
      created_at: '2026-11-26T10:00:00Z',
      updated_at: null,
      status: 'incoming',
      priority_suggestion: 'high',
      overlord_assessment: null,
      promoted_to: null,
      tags: ['auth', 'q1'],
      source_agent: null,
      source_feature: null,
    };
    expect(card.card_id).toBe('WR-20261126-001');
    expect(card.tags).toEqual(['auth', 'q1']);
    expect(card.overlord_assessment).toBeNull();
  });

  it('accepts a WarRoomCard with full overlord_assessment', () => {
    const card: WarRoomCard = {
      card_id: 'WR-20261126-002',
      title: 'Strategic item',
      body: 'Body text',
      source: 'agent',
      created_at: '2026-11-26T10:00:00Z',
      updated_at: '2026-11-26T11:00:00Z',
      status: 'promoted',
      priority_suggestion: null,
      overlord_assessment: {
        assessed_at: '2026-11-26T10:30:00Z',
        recommendation: 'promote',
        priority: 'high',
        rationale: 'Strategic fit',
        promoted_as: 'F33',
      },
      promoted_to: 'F33',
      tags: [],
      source_agent: 'overlord-monitor',
      source_feature: 'F30',
    };
    expect(card.overlord_assessment?.recommendation).toBe('promote');
    expect(card.promoted_to).toBe('F33');
  });

  it('accepts a well-formed WarRoomBoardState literal', () => {
    const state: WarRoomBoardState = {
      cards: [],
      columns: {
        incoming: [],
        triaging: [],
        promoted: [],
        deferred: [],
        archived: [],
      },
      total: 0,
      incoming_count: 0,
      generated_at: '2026-11-26T10:00:00Z',
    };
    expect(state.total).toBe(0);
    expect(Object.keys(state.columns)).toHaveLength(5);
  });

  it('accepts a well-formed CreateCardInput literal', () => {
    const input: CreateCardInput = {
      title: 'New idea',
      body: 'Description of the idea',
      source: 'operator',
      priority_suggestion: 'medium',
      tags: ['brainstorm'],
    };
    expect(input.title).toBe('New idea');
  });

  it('CreateCardInput works with minimal fields (title + body only)', () => {
    const input: CreateCardInput = {
      title: 'Minimal',
      body: 'Just title and body',
    };
    expect(input.source).toBeUndefined();
    expect(input.priority_suggestion).toBeUndefined();
    expect(input.tags).toBeUndefined();
  });
});
