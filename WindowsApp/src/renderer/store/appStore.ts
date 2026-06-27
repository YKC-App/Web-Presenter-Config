import { create } from 'zustand';
import type {
  NdiSource, TallyState, MultiViewSlot, GridLayout, NDIPTZStatus,
} from '../../shared/types';

interface AppState {
  // Discovery
  sources: NdiSource[];
  setSources: (s: NdiSource[]) => void;

  // Multi-view grid
  layout: GridLayout;
  setLayout: (l: GridLayout) => void;
  slots: MultiViewSlot[];
  setSlotSource: (index: number, sourceId: string | null) => void;

  // Selected source for the PTZ panel
  selectedSourceId: string | null;
  setSelectedSourceId: (id: string | null) => void;

  // PTZ status per source (last-known, write-only protocol)
  ptzStatus: Record<string, NDIPTZStatus>;
  updatePtzStatus: (sourceId: string, patch: Partial<NDIPTZStatus>) => void;

  // Tally
  tally: Record<string, TallyState>;
  setTally: (t: TallyState) => void;

  // Panels
  showPtzPanel: boolean;
  togglePtzPanel: () => void;
  showTrackingPanel: boolean;
  toggleTrackingPanel: () => void;
}

const DEFAULT_PTZ: NDIPTZStatus = {
  autoFocus: true,
  iris: 0.5,
  autoIris: true,
  whiteBalance: 'auto',
  wbRed: 0.5,
  wbBlue: 0.5,
};

const makeSlots = (layout: GridLayout): MultiViewSlot[] => {
  const counts: Record<GridLayout, number> = { '1x1': 1, '2x2': 4, '3x2': 6, '4x2': 8 };
  return Array.from({ length: counts[layout] }, (_, i) => ({ index: i, sourceId: null }));
};

export const useAppStore = create<AppState>((set) => ({
  sources: [],
  setSources: (sources) => set({ sources }),

  layout: '2x2',
  setLayout: (layout) => set({ layout, slots: makeSlots(layout) }),

  slots: makeSlots('2x2'),
  setSlotSource: (index, sourceId) =>
    set((s) => ({
      slots: s.slots.map((sl) => (sl.index === index ? { ...sl, sourceId } : sl)),
    })),

  selectedSourceId: null,
  setSelectedSourceId: (id) => set({ selectedSourceId: id }),

  ptzStatus: {},
  updatePtzStatus: (sourceId, patch) =>
    set((s) => ({
      ptzStatus: {
        ...s.ptzStatus,
        [sourceId]: { ...(s.ptzStatus[sourceId] ?? DEFAULT_PTZ), ...patch },
      },
    })),

  tally: {},
  setTally: (t) =>
    set((s) => ({ tally: { ...s.tally, [t.sourceId]: t } })),

  showPtzPanel: true,
  togglePtzPanel: () => set((s) => ({ showPtzPanel: !s.showPtzPanel })),

  showTrackingPanel: false,
  toggleTrackingPanel: () => set((s) => ({ showTrackingPanel: !s.showTrackingPanel })),
}));
