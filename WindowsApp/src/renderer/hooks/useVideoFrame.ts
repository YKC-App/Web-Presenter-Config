/**
 * Subscribes to NDI video frames for a given sourceId and draws them onto
 * the provided canvas ref at the native frame rate.
 */

import { useEffect, useRef } from 'react';
import type { VideoFrame } from '../../shared/types';

export function useVideoFrame(
  canvasRef: React.RefObject<HTMLCanvasElement>,
  sourceId: string | null,
): void {
  const frameRef = useRef<VideoFrame | null>(null);
  const rafRef   = useRef<number>(0);

  useEffect(() => {
    if (!sourceId) return;

    // Subscribe in main process.
    void window.ndiAPI.subscribe(sourceId);

    // Register frame listener.
    const off = window.ndiAPI.onFrame((frame) => {
      if (frame.sourceId === sourceId) frameRef.current = frame;
    });

    // Drive canvas via rAF — decoupled from IPC rate.
    const paint = (): void => {
      const canvas = canvasRef.current;
      const frame  = frameRef.current;
      if (canvas && frame) {
        const ctx = canvas.getContext('2d');
        if (ctx) {
          if (canvas.width !== frame.width || canvas.height !== frame.height) {
            canvas.width  = frame.width;
            canvas.height = frame.height;
          }
          const imgData = new ImageData(
            new Uint8ClampedArray(frame.data.buffer, frame.data.byteOffset, frame.data.byteLength),
            frame.width,
            frame.height,
          );
          ctx.putImageData(imgData, 0, 0);
        }
      }
      rafRef.current = requestAnimationFrame(paint);
    };
    rafRef.current = requestAnimationFrame(paint);

    return () => {
      off();
      cancelAnimationFrame(rafRef.current);
      frameRef.current = null;
      void window.ndiAPI.unsubscribe(sourceId);
    };
  }, [sourceId, canvasRef]);
}
