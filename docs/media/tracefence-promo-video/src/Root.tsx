import "./index.css";
import { Composition } from "remotion";
import { TraceFencePromo, VIDEO_FPS, VIDEO_HEIGHT, VIDEO_SECONDS, VIDEO_WIDTH } from "./Composition";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="TraceFencePromo"
        component={TraceFencePromo}
        durationInFrames={VIDEO_SECONDS * VIDEO_FPS}
        fps={VIDEO_FPS}
        width={VIDEO_WIDTH}
        height={VIDEO_HEIGHT}
      />
    </>
  );
};
