import React from 'react';
import { useAppStore } from '../store/appStore';
import { VideoTile } from './VideoTile';
import type { GridLayout } from '../../shared/types';

const GRID_CLASS: Record<GridLayout, string> = {
  '1x1': 'grid-1x1',
  '2x2': 'grid-2x2',
  '3x2': 'grid-3x2',
  '4x2': 'grid-4x2',
};

export function MultiView(): React.JSX.Element {
  const layout         = useAppStore((s) => s.layout);
  const slots          = useAppStore((s) => s.slots);
  const selectedId     = useAppStore((s) => s.selectedSourceId);
  const setSelectedId  = useAppStore((s) => s.setSelectedSourceId);
  const tally          = useAppStore((s) => s.tally);
  const setSlotSource  = useAppStore((s) => s.setSlotSource);

  const handleDrop = (slotIndex: number, e: React.DragEvent): void => {
    const id = e.dataTransfer.getData('sourceId');
    if (id) setSlotSource(slotIndex, id);
  };

  return (
    <div className={`multiview-grid ${GRID_CLASS[layout]}`}>
      {slots.map((slot) => {
        const t = slot.sourceId ? tally[slot.sourceId] : undefined;
        return (
          <VideoTile
            key={slot.index}
            sourceId={slot.sourceId}
            selected={slot.sourceId === selectedId}
            tallyProgram={t?.program ?? false}
            tallyPreview={t?.preview ?? false}
            onSelect={() => slot.sourceId && setSelectedId(slot.sourceId)}
            onDrop={(e) => handleDrop(slot.index, e)}
            onClear={() => setSlotSource(slot.index, null)}
          />
        );
      })}
    </div>
  );
}
