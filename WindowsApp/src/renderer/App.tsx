import React, { useEffect } from 'react';
import { useNDIBootstrap } from './hooks/useNDI';
import { useAppStore } from './store/appStore';
import { SourceList } from './components/SourceList';
import { MultiView } from './components/MultiView';
import { PTZControlPanel } from './components/PTZControlPanel';

export default function App(): React.JSX.Element {
  useNDIBootstrap();

  const showPtzPanel       = useAppStore((s) => s.showPtzPanel);
  const togglePtzPanel     = useAppStore((s) => s.togglePtzPanel);
  const selectedSourceId   = useAppStore((s) => s.selectedSourceId);
  const layout             = useAppStore((s) => s.layout);
  const setLayout          = useAppStore((s) => s.setLayout);

  return (
    <div className="app-layout">
      {/* ---- Left sidebar: source list ---- */}
      <aside className="sidebar">
        <Toolbar
          layout={layout}
          onLayoutChange={setLayout}
          showPtzPanel={showPtzPanel}
          onTogglePtz={togglePtzPanel}
        />
        <SourceList />
      </aside>

      {/* ---- Main area: multi-view grid ---- */}
      <main className="main-area">
        <MultiView />
      </main>

      {/* ---- Right panel: PTZ controls ---- */}
      {showPtzPanel && (
        <aside className="control-panel">
          <PTZControlPanel sourceId={selectedSourceId} />
        </aside>
      )}
    </div>
  );
}

// ---- Toolbar ----

interface ToolbarProps {
  layout: string;
  onLayoutChange: (l: 'from-store') => void;
  showPtzPanel: boolean;
  onTogglePtz: () => void;
}

function Toolbar({ layout, onLayoutChange, showPtzPanel, onTogglePtz }: {
  layout: string;
  onLayoutChange: (l: '1x1' | '2x2' | '3x2' | '4x2') => void;
  showPtzPanel: boolean;
  onTogglePtz: () => void;
}): React.JSX.Element {
  const layouts: ('1x1' | '2x2' | '3x2' | '4x2')[] = ['1x1', '2x2', '3x2', '4x2'];
  return (
    <div className="toolbar">
      <span className="toolbar-title">NDI Monitor</span>
      <div style={{ display: 'flex', gap: 2 }}>
        {layouts.map((l) => (
          <button
            key={l}
            className={`btn btn-icon${layout === l ? ' active' : ''}`}
            onClick={() => onLayoutChange(l)}
            title={`${l} grid`}
          >
            <GridIcon layout={l} />
          </button>
        ))}
      </div>
      <button
        className={`btn${showPtzPanel ? ' active' : ''}`}
        onClick={onTogglePtz}
        title="PTZ panel"
      >
        PTZ
      </button>
    </div>
  );
}

function GridIcon({ layout }: { layout: string }): React.JSX.Element {
  const s: React.CSSProperties = { display: 'grid', gap: 1, width: 14, height: 14 };
  if (layout === '1x1') return <div style={{ ...s, gridTemplateColumns: '1fr', background: '#4488aa', borderRadius: 1 }} />;
  if (layout === '2x2') return <div style={{ ...s, gridTemplateColumns: '1fr 1fr' }}><Sq/><Sq/><Sq/><Sq/></div>;
  if (layout === '3x2') return <div style={{ ...s, gridTemplateColumns: '1fr 1fr 1fr' }}><Sq/><Sq/><Sq/><Sq/><Sq/><Sq/></div>;
  return <div style={{ ...s, gridTemplateColumns: '1fr 1fr 1fr 1fr' }}><Sq/><Sq/><Sq/><Sq/><Sq/><Sq/><Sq/><Sq/></div>;
}
function Sq(): React.JSX.Element {
  return <div style={{ background: '#4488aa', borderRadius: 1 }} />;
}
