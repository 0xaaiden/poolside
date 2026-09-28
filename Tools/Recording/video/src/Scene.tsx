import React from 'react';
import {AbsoluteFill, Easing, Img, interpolate, staticFile, useCurrentFrame} from 'remotion';
import {FRAMES} from './frames.gen';

/**
 * Real captured frames of the running app (Tools/Recording/record-demo.sh), placed 1:1 on a MacBook
 * stage at the display's 2x scale, so every pixel of the panel is the app's own. The menu bar,
 * wallpaper, pointer and captions are drawn around it. Timings mirror DemoRecording.timeline.
 */
const S = 2; // stage px per screen point, the capture's native scale
const BEZEL = 40;
const TOP = 32 * S;
const SANS = '-apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif';
export const START = 0.2; // demo seconds at the first video frame
export const DEMO_FRAMES = Math.round((15.0 - START) * 60);

const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'} as const;
const inOut = Easing.bezier(0.65, 0, 0.35, 1);
const ramp = (t: number, a: number, b: number) => interpolate(t, [a, b], [0, 1], clamp);

/** Latest captured frame at or before demo time t. */
function frameAt(t: number) {
  let lo = 0, hi = FRAMES.length - 1, best = 0;
  while (lo <= hi) { const mid = (lo + hi) >> 1; if (FRAMES[mid][0] <= t) { best = mid; lo = mid + 1; } else hi = mid - 1; }
  return FRAMES[best][1];
}

/** Pointer path in screen points relative to the display's top center: [t, dx, y]. */
const PATH: number[][] = [
  [0.2, 330, 250], [1.0, 135, 20], [1.6, 135, 20], [2.45, 126, 144], [2.95, 126, 144], [3.45, 163, 144], [3.75, 163, 144], [4.25, 89, 144],
  [4.6, 89, 144], [5.25, -40, 226], [5.55, -40, 226], [6.2, 300, 330], [7.6, 300, 330], [8.2, -152, 65], [8.6, -152, 65], [9.05, -119, 184], [9.4, -119, 184], [10.6, -161, 184],
  [11.0, -161, 184], [11.45, 136, 56], [13.0, 136, 56], [13.45, 146, 17], [13.8, 146, 17], [14.6, 300, 230],
];
const CLICKS = [2.8, 3.6, 4.4, 5.4, 8.4, 9.2, 10.8, 11.6, 12.8, 13.6];
const CAPTIONS: [number, number, string][] = [
  [0.5, 2.6, 'Hover the notch to open'],
  [2.6, 5.2, 'Lifetime P&L against USD, HOLD or ETH'],
  [5.2, 8.9, 'Range, fees and P&L for each position'],
  [8.9, 11.3, 'Closed positions with realized P&L'],
  [11.3, 13.3, 'Privacy mask for screen sharing'],
  [13.3, 14.9, 'Click or press Esc to close'],
];

function pointer(t: number) {
  if (t <= PATH[0][0]) return PATH[0].slice(1);
  for (let i = 1; i < PATH.length; i++) {
    const [t0, x0, y0] = PATH[i - 1], [t1, x1, y1] = PATH[i];
    if (t <= t1) { const p = inOut((t - t0) / (t1 - t0)); return [x0 + (x1 - x0) * p, y0 + (y1 - y0) * p]; }
  }
  return PATH[PATH.length - 1].slice(1);
}

const MenuBar: React.FC<{inset: number}> = ({inset}) => {
  const item = (s: string, bold = false) => <span style={{fontFamily: SANS, fontSize: 26, fontWeight: bold ? 700 : 400, color: 'rgba(255,255,255,0.93)'}}>{s}</span>;
  return (
    <div style={{position: 'absolute', left: 0, top: BEZEL, width: 1920, height: TOP, display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: `0 ${34 + inset}px`, boxSizing: 'border-box',
      background: 'rgba(22,14,12,0.38)', backdropFilter: 'blur(24px)'}}>
      <div style={{display: 'flex', gap: 38}}>{item('Finder', true)}{item('File')}{item('Edit')}{!inset && item('View')}{!inset && item('Go')}</div>
      <div style={{display: 'flex', gap: 30, alignItems: 'center'}}>
{!inset && (<>
        <svg width="32" height="22" viewBox="0 0 24 16"><path d="M2 6a15 15 0 0 1 20 0M5.5 9.5a10 10 0 0 1 13 0M9 13a5 5 0 0 1 6 0" stroke="#fff" strokeOpacity="0.92" strokeWidth="2" fill="none" strokeLinecap="round" /></svg>
        <svg width="40" height="20" viewBox="0 0 30 15"><rect x="1" y="1" width="25" height="13" rx="4" stroke="#fff" strokeOpacity="0.5" fill="none" /><rect x="3" y="3" width="18" height="9" rx="2" fill="#fff" fillOpacity="0.92" /><rect x="27.5" y="5" width="2" height="5" rx="1" fill="#fff" fillOpacity="0.5" /></svg>
        </>)}
        {item('Sun Sep 27  9:41 PM')}
      </div>
    </div>
  );
};

const Stage: React.FC<{t: number; cursor: boolean; captions: boolean; height: number; width?: number}> = ({t, cursor, captions, height, width = 1920}) => {
  const [dx, py] = pointer(t);
  let press = 0, ripple = -1;
  for (const c of CLICKS) { press = Math.max(press, ramp(t, c - 0.07, c) * (1 - ramp(t, c, c + 0.13))); if (t >= c && t < c + 0.36) ripple = (t - c) / 0.36; }
  const cursorOpacity = ramp(t, 0.2, 0.45) * (1 - ramp(t, 14.55, 14.8));
  const cap = CAPTIONS.find(([a, b]) => t >= a && t < b);
  const capIn = cap ? ramp(t, cap[0], cap[0] + 0.22) * (1 - ramp(t, cap[1] - 0.2, cap[1])) : 0;
  return (
    <AbsoluteFill style={{background: '#000', overflow: 'hidden'}}>
      <div style={{position: 'absolute', left: -(1920 - width) / 2, top: 0, width: 1920, height}}>
      {/* Screen: wallpaper under a soft vignette */}
      <div style={{position: 'absolute', left: 0, top: BEZEL, width: 1920, height: height - BEZEL, overflow: 'hidden'}}>
        <Img src={staticFile('backdrop.webp')} style={{position: 'absolute', left: -60, top: -40, width: 2040, height: 1360, objectFit: 'cover', filter: 'brightness(0.78) saturate(1.05)'}} />
        <div style={{position: 'absolute', inset: 0, background: 'radial-gradient(ellipse 60% 70% at 50% 18%, rgba(0,0,0,0) 40%, rgba(0,0,0,0.35) 100%)'}} />
      </div>
      <MenuBar inset={(1920 - width) / 2} />
      {/* The app, exactly as captured: a 640 x 540 pt region under the notch at 2x */}
      <Img src={staticFile(`frames/f${String(frameAt(t)).padStart(5, '0')}.png`)} style={{position: 'absolute', left: 960 - 640, top: BEZEL, width: 1280, height: 1080}} />
      {/* Bezel, camera and notch */}
      <div style={{position: 'absolute', left: 0, top: 0, width: 1920, height: BEZEL, background: 'linear-gradient(180deg, #1d1d20 0, #050505 5px, #000 100%)'}} />
      <div style={{position: 'absolute', left: 960 - 5, top: 15, width: 10, height: 10, borderRadius: 10, background: '#0c0f16', boxShadow: 'inset 0 0 2px 1px rgba(70,90,140,0.35)'}} />
      <div style={{position: 'absolute', left: 960 - 180 * S / 2, top: BEZEL - 1, width: 180 * S, height: TOP + 1, background: '#000', borderBottomLeftRadius: 20, borderBottomRightRadius: 20}}>
        <div style={{position: 'absolute', left: -14, top: 0, width: 14, height: 14, background: 'radial-gradient(circle at 0 100%, transparent 13.5px, #000 14px)'}} />
        <div style={{position: 'absolute', right: -14, top: 0, width: 14, height: 14, background: 'radial-gradient(circle at 100% 100%, transparent 13.5px, #000 14px)'}} />
      </div>
      {cursor && cursorOpacity > 0 && (
        <div style={{position: 'absolute', left: 960 + dx * S, top: BEZEL + py * S, opacity: cursorOpacity}}>
          {ripple >= 0 && <div style={{position: 'absolute', left: -34 * ripple, top: -34 * ripple, width: 68 * ripple, height: 68 * ripple, borderRadius: '50%',
            border: `2px solid rgba(255,255,255,${0.6 * (1 - ripple)})`, background: `rgba(255,255,255,${0.12 * (1 - ripple)})`}} />}
          <svg width="34" height="50" viewBox="0 0 17 25" style={{position: 'absolute', left: -3, top: -3, transform: `scale(${1 - 0.14 * press})`, transformOrigin: '3px 3px', filter: 'drop-shadow(0 3px 4px rgba(0,0,0,0.5))'}}>
            <path d="M1.5 1.5v19.2l4.6-4.4 3 6.9 3.1-1.3-3-6.8h6.4z" fill="#000" stroke="#fff" strokeWidth="1.3" strokeLinejoin="round" />
          </svg>
        </div>
      )}
      {captions && cap && (
        <div style={{position: 'absolute', left: 0, top: 968, width: 1920, display: 'flex', justifyContent: 'center', opacity: capIn, transform: `translateY(${(1 - capIn) * 12}px)`}}>
          <div style={{fontFamily: SANS, fontSize: 30, fontWeight: 500, color: '#fff', letterSpacing: -0.2, padding: '14px 28px', borderRadius: 40,
            background: 'rgba(20,16,16,0.62)', backdropFilter: 'blur(20px)', border: '1px solid rgba(255,255,255,0.14)'}}>{cap[2]}</div>
        </div>
      )}
      </div>
    </AbsoluteFill>
  );
};

export const Demo: React.FC = () => {
  const f = useCurrentFrame();
  return <Stage t={START + f / 60} cursor captions height={1080} />;
};
/** README still: the dashboard at rest, no pointer or captions. */
export const Shot: React.FC = () => <Stage t={2.5} cursor={false} captions={false} height={860} width={1440} />;
