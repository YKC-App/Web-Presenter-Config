import React, { useRef } from 'react';
import { useVideoFrame } from '../hooks/useVideoFrame';
import { useAppStore } from '../store/appStore';

interface Props {
  sourceId: string | null;
  selected: boolean;
  tallyProgram: boolean;
  tallyPreview: boolean;
  onSelect: () => void;
  onDrop: (e: React.DragEvent) => void;
  onClear: () => void;
}

export function VideoTile({
  sourceId, selected, tallyProgram, tallyPreview,
  onSelect, onDrop, onClear,
}: Props): React.JSX.Element {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  useVideoFrame(canvasRef, sourceId);

  const sources = useAppStore((s) => s.sources);
  const src = sources.find((s) => s.id === sourceId);

  const tileClass = [
    'video-tile',
    selected ? 'selected' : '',
    tallyProgram ? 'tally-pgm' : tallyPreview ? 'tally-pvw' : '',
  ].filter(Boolean).join(' ');

  const handleDragOver = (e: React.DragEvent): void => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
  };

  return (
    <div
      className={tileClass}
      onClick={onSelect}
      onDragOver={handleDragOver}
      onDrop={onDrop}
      onContextMenu={(e) => {
        e.preventDefault();
        if (sourceId) onClear();
      }}
      title={sourceId ? `${src?.streamName} — right-click to remove` : 'Drag a source here'}
    >
      {sourceId ? (
        <>
          <canvas ref={canvasRef} />
          {src && <div className="tile-label">{src.streamName}</div>}
          {tallyProgram && <div className="tally-badge pgm">PGM</div>}
          {!tallyProgram && tallyPreview && <div className="tally-badge pvw">PVW</div>}
        </>
      ) : (
        <div className="tile-empty">
          <span style={{ fontSize: 24, opacity: 0.3 }}>+</span>
          <span>Drop source here</span>
        </div>
      )}
    </div>
  );
}
