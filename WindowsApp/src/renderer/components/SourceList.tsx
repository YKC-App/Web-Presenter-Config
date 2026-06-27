import React from 'react';
import { useAppStore } from '../store/appStore';
import type { NdiSource } from '../../shared/types';

export function SourceList(): React.JSX.Element {
  const sources          = useAppStore((s) => s.sources);
  const selectedId       = useAppStore((s) => s.selectedSourceId);
  const setSelectedId    = useAppStore((s) => s.setSelectedSourceId);
  const slots            = useAppStore((s) => s.slots);
  const setSlotSource    = useAppStore((s) => s.setSlotSource);
  const tally            = useAppStore((s) => s.tally);

  const firstEmptySlot = slots.findIndex((s) => s.sourceId === null);

  const handleAdd = (src: NdiSource): void => {
    if (firstEmptySlot >= 0) {
      setSlotSource(firstEmptySlot, src.id);
    }
    setSelectedId(src.id);
  };

  return (
    <>
      <div className="section-title">Sources ({sources.length})</div>
      <div className="source-list">
        {sources.length === 0 && (
          <div style={{ padding: '20px 12px', color: 'var(--text-muted)', fontSize: 11 }}>
            Discovering NDI sources…
          </div>
        )}
        {sources.map((src) => {
          const t = tally[src.id];
          const isLive = t?.program;
          const isPvw  = t?.preview;
          const dotCls = isLive ? 'live' : isPvw ? 'preview' : '';
          return (
            <div
              key={src.id}
              className={`source-item${selectedId === src.id ? ' selected' : ''}`}
              onClick={() => setSelectedId(src.id)}
              onDoubleClick={() => handleAdd(src)}
              title="Double-click to add to grid"
            >
              <div className={`source-dot ${dotCls}`} />
              <div style={{ minWidth: 0 }}>
                <div className="source-name">{src.streamName}</div>
                <div className="source-host">{src.machineName}</div>
              </div>
              {src.hasPtz && (
                <span style={{ fontSize: 9, color: 'var(--accent)', marginLeft: 'auto', flexShrink: 0 }}>PTZ</span>
              )}
            </div>
          );
        })}
      </div>
      {sources.length > 0 && (
        <div style={{ padding: '6px 8px', borderTop: '1px solid var(--border)' }}>
          <div style={{ fontSize: 10, color: 'var(--text-muted)' }}>
            Double-click source to add to grid
          </div>
        </div>
      )}
    </>
  );
}
