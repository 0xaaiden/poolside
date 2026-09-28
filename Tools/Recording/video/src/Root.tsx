import {Composition, Still} from 'remotion';
import {Demo, DemoCrop, Shot, DEMO_FRAMES} from './Scene';

export const Root: React.FC = () => (
  <>
    <Composition id="PoolsideDemo" component={Demo} durationInFrames={DEMO_FRAMES} fps={60} width={1920} height={1080} />
    <Composition id="PoolsideDemoGif" component={DemoCrop} durationInFrames={DEMO_FRAMES} fps={60} width={1440} height={1080} />
    <Still id="PoolsideShot" component={Shot} width={1440} height={860} />
  </>
);
