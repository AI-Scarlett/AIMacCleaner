import React, { useEffect, useMemo, useState } from "react";
import type { Caption } from "@remotion/captions";
import {
  AbsoluteFill,
  Audio,
  Easing,
  Img,
  cancelRender,
  continueRender,
  delayRender,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";

export const VIDEO_FPS = 30;
export const VIDEO_WIDTH = 1920;
export const VIDEO_HEIGHT = 1080;
export const VIDEO_SECONDS = 216;

type Scene = {
  start: number;
  end: number;
  eyebrow: string;
  title: string;
  titleZh: string;
  body: string;
  bodyZh: string;
  image?: string;
  accent: string;
  mode: "hero" | "quota" | "reset" | "overview" | "tokens" | "guard" | "toolkit" | "privacy" | "cta";
};

const scenes: Scene[] = [
  {
    start: 0,
    end: 29.4,
    eyebrow: "AI OPERATIONS COCKPIT",
    title: "TraceFence",
    titleZh: "AI Coding 的本机指挥中心",
    body: "Sessions, provider quota, reset credits, tokens, agent activity, and safety signals in one native macOS console.",
    bodyZh: "会话、Provider 额度、重置次数、Token、Agent 活动和安全信号，集中在一个 macOS 原生控制台。",
    image: "article-cover.jpg",
    accent: "#77a8ff",
    mode: "hero",
  },
  {
    start: 29.4,
    end: 47.9,
    eyebrow: "PROVIDER QUOTA MONITOR",
    title: "Know your capacity before the sprint starts.",
    titleZh: "开工前，就知道额度水位。",
    body: "TraceFence reads provider signals and shows five-hour, weekly, Spark, and reset windows directly from the menu bar.",
    bodyZh: "TraceFence 读取 provider 信号，在菜单栏展示 5 小时、每周、Spark 与重置窗口。",
    image: "menubar-quota.jpg",
    accent: "#5d93ff",
    mode: "quota",
  },
  {
    start: 47.9,
    end: 64.2,
    eyebrow: "CODEX RESET CREDITS",
    title: "Manual resets finally have an expiration clock.",
    titleZh: "Codex 手动重置终于有了到期时钟。",
    body: "See how many reset credits remain, which one expires next, and when each opportunity should be used.",
    bodyZh: "查看剩余重置次数、最近到期机会，以及每一次重置的使用窗口。",
    accent: "#8a7cff",
    mode: "reset",
  },
  {
    start: 64.2,
    end: 81.8,
    eyebrow: "COMMAND CENTER",
    title: "Turn local AI activity into a single readable picture.",
    titleZh: "把本机 AI 活动变成一张看得懂的图。",
    body: "Overview aggregates sessions, active agents, projects, token volume, live activity, and data source status.",
    bodyZh: "概览页聚合会话、活跃 Agent、项目、Token 总量、实时活动和数据源状态。",
    image: "overview.jpg",
    accent: "#6ca5ff",
    mode: "overview",
  },
  {
    start: 81.8,
    end: 107.9,
    eyebrow: "TOKEN ANALYTICS",
    title: "Make cost and model usage observable.",
    titleZh: "让成本和模型使用可观察。",
    body: "Trace tokens by input, output, cache, model, project, and session. Find what burns capacity before it becomes a bill.",
    bodyZh: "按输入、输出、缓存、模型、项目和会话追踪 Token，在账单出现前看见消耗来源。",
    image: "token-analytics.jpg",
    accent: "#58d5ff",
    mode: "tokens",
  },
  {
    start: 107.9,
    end: 130.4,
    eyebrow: "AGENT GUARD",
    title: "Watch what agents do on your Mac.",
    titleZh: "看见 Agent 在本机做了什么。",
    body: "File changes, command execution, sensitive paths, protected folders, and high-risk operations become visible alerts.",
    bodyZh: "文件变更、命令执行、敏感路径、保护目录和高风险操作，都会变成可见告警。",
    image: "guard-popover.jpg",
    accent: "#42e6c8",
    mode: "guard",
  },
  {
    start: 130.4,
    end: 147.4,
    eyebrow: "AGENT TOOLKIT",
    title: "Backup, diagnose, audit, and recover.",
    titleZh: "备份、诊断、审计与恢复。",
    body: "Back up selected sessions without credentials, run health checks, analyze trends, and control stuck local agents with confirmation.",
    bodyZh: "备份选定会话且不含凭证，执行健康检查、趋势分析，并在确认后控制卡住的本机 Agent。",
    accent: "#75f5a7",
    mode: "toolkit",
  },
  {
    start: 147.4,
    end: 188.7,
    eyebrow: "LOCAL FIRST",
    title: "A developer-aware maintenance layer.",
    titleZh: "面向开发者的本机维护层。",
    body: "Clean caches and dependencies carefully. Prefer Trash. Read authorized folders, local logs, metadata, and system state without uploading private conversations.",
    bodyZh: "谨慎清理缓存和依赖，优先移入废纸篓。读取授权目录、本机日志、元数据和系统状态，不上传私密会话。",
    accent: "#ffd166",
    mode: "privacy",
  },
  {
    start: 188.7,
    end: 216,
    eyebrow: "TRACEFENCE.COM",
    title: "Build faster. Keep the cockpit lit.",
    titleZh: "更快构建，也让驾驶舱保持亮起。",
    body: "Download the direct edition, monitor your AI quota, and turn agent work into something visible, controllable, and recoverable.",
    bodyZh: "下载官网版，监控 AI 额度，把 Agent 工作变成可见、可控、可恢复的系统。",
    accent: "#7aa7ff",
    mode: "cta",
  },
];

const clamp = {
  extrapolateLeft: "clamp" as const,
  extrapolateRight: "clamp" as const,
};

const ease = Easing.bezier(0.16, 1, 0.3, 1);

const sceneAt = (second: number) =>
  scenes.find((scene) => second >= scene.start && second < scene.end) ?? scenes[scenes.length - 1];

const appear = (frame: number, fps: number, start: number, duration = 1) =>
  interpolate(frame, [start * fps, (start + duration) * fps], [0, 1], {
    ...clamp,
    easing: ease,
  });

const sceneProgress = (second: number, scene: Scene) =>
  Math.max(0, Math.min(1, (second - scene.start) / (scene.end - scene.start)));

export const TraceFencePromo: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const second = frame / fps;
  const activeScene = sceneAt(second);
  const progress = sceneProgress(second, activeScene);
  const sceneEnter = appear(frame, fps, activeScene.start, 1.2);
  const globalPulse = Math.sin(frame / 24) * 0.5 + 0.5;

  return (
    <AbsoluteFill style={styles.stage}>
      <Audio src={staticFile("audio/tech-bed.m4a")} volume={0.16} />
      <Audio src={staticFile("audio/narration.m4a")} volume={1} />
      <TechBackground accent={activeScene.accent} pulse={globalPulse} />
      <Header scene={activeScene} second={second} />
      <AbsoluteFill style={styles.content}>
        <SceneVisual scene={activeScene} progress={progress} enter={sceneEnter} />
      </AbsoluteFill>
      <SceneCopy scene={activeScene} enter={sceneEnter} progress={progress} />
      <BilingualCaptions />
      <Timeline second={second} />
    </AbsoluteFill>
  );
};

const Header: React.FC<{ scene: Scene; second: number }> = ({ scene, second }) => {
  const time = Math.max(0, Math.round(VIDEO_SECONDS - second));
  return (
    <div style={styles.header}>
      <div style={styles.brand}>
        <Img src={staticFile("images/tracefence-icon.png")} style={styles.icon} />
        <div>
          <div style={styles.brandName}>TraceFence</div>
          <div style={styles.brandSub}>AI Agent visibility and quota control</div>
        </div>
      </div>
      <div style={styles.headerRight}>
        <span style={{ ...styles.statusDot, background: scene.accent }} />
        <span>{scene.eyebrow}</span>
        <span style={styles.timePill}>{Math.floor(time / 60)}:{String(time % 60).padStart(2, "0")}</span>
      </div>
    </div>
  );
};

const TechBackground: React.FC<{ accent: string; pulse: number }> = ({ accent, pulse }) => {
  const frame = useCurrentFrame();
  const drift = (frame % 240) / 240;
  const particles = useMemo(() => Array.from({ length: 34 }, (_, index) => index), []);

  return (
    <AbsoluteFill style={styles.background}>
      <div style={styles.grid} />
      <div
        style={{
          ...styles.scanPlane,
          transform: `translateY(${interpolate(drift, [0, 1], [-180, 1180])}px)`,
          borderColor: accent,
        }}
      />
      <div style={{ ...styles.glowA, background: accent, opacity: 0.18 + pulse * 0.08 }} />
      <div style={{ ...styles.glowB, background: "#0bd6ff", opacity: 0.12 + pulse * 0.05 }} />
      {particles.map((item) => {
        const x = (item * 131) % VIDEO_WIDTH;
        const y = ((item * 79 + frame * (0.25 + (item % 4) * 0.08)) % VIDEO_HEIGHT) - 40;
        const size = 2 + (item % 4);
        return (
          <div
            key={item}
            style={{
              ...styles.particle,
              left: x,
              top: y,
              width: size,
              height: size,
              background: item % 3 === 0 ? accent : "#ffffff",
              opacity: 0.18 + (item % 5) * 0.08,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

const SceneVisual: React.FC<{ scene: Scene; progress: number; enter: number }> = ({ scene, progress, enter }) => {
  switch (scene.mode) {
    case "hero":
      return <HeroVisual enter={enter} progress={progress} />;
    case "quota":
      return <QuotaVisual enter={enter} progress={progress} scene={scene} />;
    case "reset":
      return <ResetVisual enter={enter} progress={progress} scene={scene} />;
    case "overview":
    case "tokens":
    case "guard":
      return <ScreenshotVisual scene={scene} enter={enter} progress={progress} />;
    case "toolkit":
      return <ToolkitVisual enter={enter} progress={progress} />;
    case "privacy":
      return <PrivacyVisual enter={enter} progress={progress} />;
    case "cta":
      return <CtaVisual enter={enter} progress={progress} />;
  }
};

const HeroVisual: React.FC<{ enter: number; progress: number }> = ({ enter, progress }) => {
  const scale = interpolate(enter, [0, 1], [0.92, 1]);
  return (
    <div style={{ ...styles.heroShell, transform: `scale(${scale}) translateY(${(1 - enter) * 36}px)`, opacity: enter }}>
      <div style={styles.heroOrbit} />
      <Img src={staticFile("images/tracefence-icon.png")} style={styles.heroIcon} />
      <div style={styles.heroTitle}>TraceFence</div>
      <div style={styles.heroLine}>Provider Quota • Codex Reset Credits • Token Ledger • Agent Guard</div>
      <div style={styles.heroCards}>
        {[
          ["5h quota", "71%", "#6498ff"],
          ["Weekly", "95%", "#65c8ff"],
          ["Reset credits", "4", "#8a7cff"],
          ["Agent events", "Live", "#42e6c8"],
        ].map(([label, value, color], index) => (
          <div key={label} style={{ ...styles.heroMetric, transform: `translateY(${Math.sin(progress * 8 + index) * 8}px)` }}>
            <span style={{ color }}>{value}</span>
            <small>{label}</small>
          </div>
        ))}
      </div>
    </div>
  );
};

const QuotaVisual: React.FC<{ enter: number; progress: number; scene: Scene }> = ({ enter, progress, scene }) => (
  <div style={{ ...styles.visualTwoCol, opacity: enter }}>
    <div style={styles.quotaPanel}>
      <div style={styles.panelTitle}>Provider Quota Monitor</div>
      <div style={styles.accountRow}>
        <div style={styles.providerIcon}>›_</div>
        <div>
          <strong>Codex</strong>
          <span>PRO • official provider API</span>
        </div>
        <b>Credits 0</b>
      </div>
      {[
        ["5-hour quota", "Resets in 2 hr • 16:49", 71, "#6498ff"],
        ["Weekly quota", "Resets in 6 days • 11:49", 95, "#65a2ff"],
        ["Codex Spark 5-hour", "Resets in 4 hr • 19:30", 100, "#7c7aff"],
        ["Codex Spark Weekly", "Resets in 6 days • 14:30", 100, "#7aa7ff"],
      ].map(([label, sub, value, color], index) => (
        <QuotaBar
          key={label}
          label={String(label)}
          sub={String(sub)}
          value={Number(value)}
          color={String(color)}
          delay={index * 0.08}
          progress={progress}
        />
      ))}
    </div>
    <FloatingShot image={scene.image ?? "menubar-quota.jpg"} progress={progress} />
  </div>
);

const ResetVisual: React.FC<{ enter: number; progress: number; scene: Scene }> = ({ enter, progress, scene }) => (
  <div style={{ ...styles.resetStage, opacity: enter }}>
    <div style={styles.resetCore}>
      <div style={styles.resetNumber}>4</div>
      <div>
        <div style={styles.panelTitle}>Manual reset credits</div>
        <p style={styles.resetCopy}>Every reset has a window. TraceFence shows what remains before it quietly expires.</p>
      </div>
    </div>
    <div style={styles.resetRail}>
      {[
        ["Available", "Expires in 2d 04h", "#75f5a7"],
        ["Available", "Expires in 6d 12h", "#77a8ff"],
        ["Available", "Expires in 13d", "#8a7cff"],
        ["Used", "Redeemed yesterday", "#738199"],
      ].map(([state, date, color], index) => (
        <div
          key={`${state}-${index}`}
          style={{
            ...styles.resetCard,
            borderColor: String(color),
            transform: `translateY(${interpolate(progress, [0, 0.25 + index * 0.1], [40, 0], clamp)}px)`,
          }}
        >
          <span style={{ background: String(color) }} />
          <strong>{state}</strong>
          <small>{date}</small>
        </div>
      ))}
    </div>
    <div style={styles.resetRadar}>
      <div style={{ ...styles.radarNeedle, transform: `rotate(${progress * 430}deg)` }} />
    </div>
    <div style={styles.smallPreview}>
      <Img src={staticFile(`images/${scene.image ?? "menubar-quota.jpg"}`)} style={styles.smallPreviewImage} />
    </div>
  </div>
);

const ScreenshotVisual: React.FC<{ scene: Scene; enter: number; progress: number }> = ({ scene, enter, progress }) => (
  <div style={{ ...styles.screenshotScene, opacity: enter }}>
    <div style={styles.screenFrame}>
      <div style={styles.windowDots}>
        <span />
        <span />
        <span />
      </div>
      <Img
        src={staticFile(`images/${scene.image ?? "overview.jpg"}`)}
        style={{
          ...styles.mainScreenshot,
          transform: `scale(${1.04 - progress * 0.045}) translateY(${interpolate(progress, [0, 1], [22, -18])}px)`,
        }}
      />
    </div>
    <MetricStack mode={scene.mode} progress={progress} accent={scene.accent} />
  </div>
);

const ToolkitVisual: React.FC<{ enter: number; progress: number }> = ({ enter, progress }) => (
  <div style={{ ...styles.toolkitGrid, opacity: enter }}>
    {[
      ["Session Keeper", "Back up selected agent sessions without credentials.", "archivebox.fill", "#77a8ff"],
      ["Health Diagnostics", "Check folders, session integrity, disk space, and runtime state.", "stethoscope", "#65c8ff"],
      ["Usage Analyst", "Detect abnormal token and session trends.", "chart.line.uptrend.xyaxis", "#8a7cff"],
      ["Safety Auditor", "Verify config and credential status without exposing secrets.", "checkmark.shield.fill", "#75f5a7"],
    ].map(([title, body, icon, color], index) => (
      <div
        key={title}
        style={{
          ...styles.toolCard,
          borderColor: String(color),
          transform: `translateY(${interpolate(progress, [0, 0.22 + index * 0.06], [50, 0], clamp)}px)`,
        }}
      >
        <div style={{ ...styles.toolIcon, background: `${color}22`, color: String(color) }}>{icon}</div>
        <strong>{title}</strong>
        <p>{body}</p>
      </div>
    ))}
  </div>
);

const PrivacyVisual: React.FC<{ enter: number; progress: number }> = ({ enter, progress }) => (
  <div style={{ ...styles.privacyStage, opacity: enter }}>
    <div style={styles.localCore}>
      <div style={styles.lockRing} />
      <Img src={staticFile("images/tracefence-icon.png")} style={styles.lockIcon} />
      <strong>Local-first by design</strong>
    </div>
    <div style={styles.policyGrid}>
      {[
        "Authorized folders",
        "Local logs",
        "No secret display",
        "Trash-first cleanup",
        "Metadata analysis",
        "User confirmation",
      ].map((item, index) => (
        <div key={item} style={{ ...styles.policyItem, opacity: interpolate(progress, [index * 0.08, index * 0.08 + 0.2], [0, 1], clamp) }}>
          <span />
          {item}
        </div>
      ))}
    </div>
  </div>
);

const CtaVisual: React.FC<{ enter: number; progress: number }> = ({ enter, progress }) => (
  <div style={{ ...styles.ctaStage, opacity: enter }}>
    <Img src={staticFile("images/tracefence-icon.png")} style={styles.ctaIcon} />
    <div style={styles.ctaText}>tracefence.com</div>
    <div style={styles.ctaSub}>Direct edition • Provider quota • Codex reset credits • Agent safety</div>
    <div style={styles.ctaBeam} />
    <div style={{ ...styles.ctaRing, transform: `scale(${1 + progress * 0.25})`, opacity: 0.5 - progress * 0.2 }} />
  </div>
);

const QuotaBar: React.FC<{ label: string; sub: string; value: number; color: string; delay: number; progress: number }> = ({
  label,
  sub,
  value,
  color,
  delay,
  progress,
}) => {
  const shown = interpolate(progress, [delay, delay + 0.42], [0, value], clamp);
  return (
    <div style={styles.quotaRow}>
      <div style={styles.quotaLabel}>
        <strong>{label}</strong>
        <span>{sub}</span>
      </div>
      <b style={{ color }}>{Math.round(shown)}%</b>
      <div style={styles.barTrack}>
        <div style={{ ...styles.barFill, width: `${shown}%`, background: color }} />
      </div>
    </div>
  );
};

const FloatingShot: React.FC<{ image: string; progress: number }> = ({ image, progress }) => (
  <div
    style={{
      ...styles.floatingShot,
      transform: `perspective(1200px) rotateY(-12deg) rotateX(5deg) translateY(${Math.sin(progress * Math.PI * 2) * 16}px)`,
    }}
  >
    <Img src={staticFile(`images/${image}`)} style={styles.floatingImage} />
  </div>
);

const MetricStack: React.FC<{ mode: Scene["mode"]; progress: number; accent: string }> = ({ mode, progress, accent }) => {
  const rows =
    mode === "tokens"
      ? [
          ["Total Token", "613.4M"],
          ["Cache Token", "572.5M"],
          ["Estimated Cost", "$136.54"],
        ]
      : mode === "guard"
        ? [
            ["Operations", "Live"],
            ["Risk Alerts", "Guarded"],
            ["Protected Paths", "On"],
          ]
        : [
            ["Sessions", "249"],
            ["Active Agents", "5"],
            ["Projects", "22"],
          ];
  return (
    <div style={styles.metricStack}>
      {rows.map(([label, value], index) => (
        <div key={label} style={{ ...styles.sideMetric, transform: `translateX(${interpolate(progress, [0, 0.35 + index * 0.08], [80, 0], clamp)}px)` }}>
          <span style={{ background: accent }} />
          <strong>{value}</strong>
          <small>{label}</small>
        </div>
      ))}
    </div>
  );
};

const SceneCopy: React.FC<{ scene: Scene; enter: number; progress: number }> = ({ scene, enter, progress }) => (
  scene.mode === "hero" ? null : <div
    style={{
      ...styles.copyBlock,
      opacity: enter,
      transform: `translateY(${(1 - enter) * 30}px)`,
      borderColor: `${scene.accent}66`,
    }}
  >
    <div style={{ ...styles.eyebrow, color: scene.accent }}>{scene.eyebrow}</div>
    <h1>{scene.title}</h1>
    <h2>{scene.titleZh}</h2>
    <p>{scene.body}</p>
    <p style={styles.zhBody}>{scene.bodyZh}</p>
    <div style={styles.progressPills}>
      {["Quota", "Reset", "Token", "Guard"].map((label, index) => (
        <span key={label} style={{ opacity: 0.35 + (index + 1) / 6, borderColor: scene.accent }}>
          {label}
        </span>
      ))}
      <b style={{ width: `${progress * 100}%`, background: scene.accent }} />
    </div>
  </div>
);

const BilingualCaptions: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const [captions, setCaptions] = useState<{ en: Caption[]; zh: Caption[] } | null>(null);
  const [handle] = useState(() => delayRender("Load bilingual captions"));

  useEffect(() => {
    Promise.all([
      fetch(staticFile("data/captions-en.json")).then((response) => response.json() as Promise<Caption[]>),
      fetch(staticFile("data/captions-zh.json")).then((response) => response.json() as Promise<Caption[]>),
    ])
      .then(([en, zh]) => {
        setCaptions({ en, zh });
        continueRender(handle);
      })
      .catch((error) => cancelRender(error));
  }, [handle]);

  const currentMs = (frame / fps) * 1000;
  const en = captions?.en.find((caption) => currentMs >= caption.startMs && currentMs < caption.endMs);
  const zh = captions?.zh.find((caption) => currentMs >= caption.startMs && currentMs < caption.endMs);

  if (!en || !zh) {
    return null;
  }

  return (
    <div style={styles.captionBox}>
      <div style={styles.captionEn}>{en.text}</div>
      <div style={styles.captionZh}>{zh.text}</div>
    </div>
  );
};

const Timeline: React.FC<{ second: number }> = ({ second }) => (
  <div style={styles.timeline}>
    {scenes.map((scene) => {
      const active = second >= scene.start && second < scene.end;
      return (
        <div
          key={scene.mode}
          style={{
            ...styles.timelineSegment,
            flexGrow: scene.end - scene.start,
            background: active ? scene.accent : "rgba(255,255,255,0.16)",
          }}
        />
      );
    })}
  </div>
);

const styles: Record<string, React.CSSProperties> = {
  stage: {
    background: "#030816",
    color: "#f7fbff",
    fontFamily: "Inter, ui-sans-serif, -apple-system, BlinkMacSystemFont, 'PingFang SC', 'Microsoft YaHei', sans-serif",
    overflow: "hidden",
  },
  background: {
    background:
      "radial-gradient(circle at 18% 20%, rgba(86, 135, 255, 0.24), transparent 26%), radial-gradient(circle at 75% 30%, rgba(50, 224, 201, 0.14), transparent 25%), linear-gradient(135deg, #030816 0%, #091528 48%, #040611 100%)",
  },
  grid: {
    position: "absolute",
    inset: 0,
    backgroundImage:
      "linear-gradient(rgba(116,165,255,.13) 1px, transparent 1px), linear-gradient(90deg, rgba(116,165,255,.13) 1px, transparent 1px)",
    backgroundSize: "80px 80px",
    maskImage: "linear-gradient(to bottom, transparent, black 12%, black 82%, transparent)",
  },
  scanPlane: {
    position: "absolute",
    left: -120,
    right: -120,
    height: 180,
    borderTop: "2px solid",
    background: "linear-gradient(to bottom, rgba(124,168,255,0.18), transparent)",
    filter: "blur(1px)",
  },
  glowA: { position: "absolute", width: 620, height: 620, right: -90, top: 80, filter: "blur(120px)", borderRadius: 999 },
  glowB: { position: "absolute", width: 520, height: 520, left: -100, bottom: -80, filter: "blur(120px)", borderRadius: 999 },
  particle: { position: "absolute", borderRadius: 99, boxShadow: "0 0 18px currentColor" },
  header: {
    position: "absolute",
    top: 42,
    left: 58,
    right: 58,
    zIndex: 20,
    display: "flex",
    alignItems: "center",
    justifyContent: "space-between",
  },
  brand: { display: "flex", alignItems: "center", gap: 18 },
  icon: { width: 64, height: 64, borderRadius: 16, boxShadow: "0 0 32px rgba(92,142,255,.4)" },
  brandName: { fontSize: 32, fontWeight: 900, letterSpacing: 0 },
  brandSub: { fontSize: 15, color: "#99a9c1", marginTop: 4 },
  headerRight: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    padding: "14px 18px",
    border: "1px solid rgba(255,255,255,.15)",
    borderRadius: 999,
    background: "rgba(9,18,36,.62)",
    backdropFilter: "blur(18px)",
    fontSize: 14,
    fontWeight: 800,
    color: "#d9e8ff",
  },
  statusDot: { width: 10, height: 10, borderRadius: 99, boxShadow: "0 0 18px currentColor" },
  timePill: { padding: "5px 9px", background: "rgba(255,255,255,.12)", borderRadius: 999, color: "#fff" },
  content: { zIndex: 4, padding: "130px 58px 205px" },
  copyBlock: {
    position: "absolute",
    left: 72,
    bottom: 178,
    zIndex: 30,
    width: 650,
    padding: "30px 34px 28px",
    border: "1px solid",
    borderRadius: 28,
    background: "rgba(5, 12, 26, .72)",
    backdropFilter: "blur(22px)",
    boxShadow: "0 30px 80px rgba(0,0,0,.34)",
  },
  eyebrow: { fontSize: 15, fontWeight: 900, letterSpacing: 3, marginBottom: 14 },
  zhBody: { color: "#d7e4f7", marginTop: 10 },
  progressPills: { position: "relative", display: "flex", gap: 10, marginTop: 22, paddingTop: 18, overflow: "hidden" },
  heroShell: {
    position: "absolute",
    inset: "120px 150px 190px",
    display: "flex",
    flexDirection: "column",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 44,
    background: "linear-gradient(135deg, rgba(18,39,82,.78), rgba(5,10,22,.72))",
    border: "1px solid rgba(134,173,255,.35)",
    boxShadow: "0 40px 110px rgba(0,0,0,.35)",
  },
  heroOrbit: {
    position: "absolute",
    width: 680,
    height: 680,
    border: "1px solid rgba(116,165,255,.26)",
    borderRadius: 999,
    boxShadow: "inset 0 0 80px rgba(88,148,255,.12)",
  },
  heroIcon: { width: 190, height: 190, borderRadius: 44, zIndex: 2, boxShadow: "0 0 70px rgba(116,165,255,.45)" },
  heroTitle: { zIndex: 2, marginTop: 34, fontSize: 116, fontWeight: 950, letterSpacing: -2 },
  heroLine: { zIndex: 2, marginTop: 8, fontSize: 28, color: "#b9cdf1", fontWeight: 700 },
  heroCards: { zIndex: 2, display: "grid", gridTemplateColumns: "repeat(4, 1fr)", gap: 16, marginTop: 48, width: 980 },
  heroMetric: {
    padding: "22px 20px",
    borderRadius: 20,
    border: "1px solid rgba(255,255,255,.14)",
    background: "rgba(255,255,255,.06)",
    display: "flex",
    flexDirection: "column",
    gap: 6,
  },
  visualTwoCol: { position: "absolute", inset: "116px 42px 20px 720px", display: "flex", alignItems: "center", gap: 38 },
  quotaPanel: {
    width: 650,
    padding: 34,
    borderRadius: 34,
    background: "rgba(255,255,255,.09)",
    border: "1px solid rgba(151,187,255,.28)",
    boxShadow: "0 40px 100px rgba(0,0,0,.35)",
  },
  panelTitle: { fontSize: 30, fontWeight: 950, marginBottom: 22 },
  accountRow: { display: "grid", gridTemplateColumns: "70px 1fr auto", alignItems: "center", gap: 18, marginBottom: 30 },
  providerIcon: {
    width: 58,
    height: 58,
    borderRadius: 16,
    background: "linear-gradient(135deg,#4878db,#6ea1ff)",
    display: "grid",
    placeItems: "center",
    fontSize: 24,
    fontWeight: 950,
  },
  quotaRow: { marginTop: 25 },
  quotaLabel: { display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 20 },
  barTrack: { height: 13, marginTop: 10, borderRadius: 99, background: "rgba(255,255,255,.13)", overflow: "hidden" },
  barFill: { height: "100%", borderRadius: 99, boxShadow: "0 0 28px currentColor" },
  floatingShot: {
    width: 440,
    height: 650,
    borderRadius: 34,
    overflow: "hidden",
    border: "1px solid rgba(255,255,255,.2)",
    boxShadow: "0 48px 120px rgba(0,0,0,.45)",
    background: "#fff",
  },
  floatingImage: { width: "100%", height: "100%", objectFit: "cover" },
  resetStage: { position: "absolute", inset: "140px 80px 160px 790px" },
  resetCore: {
    display: "flex",
    alignItems: "center",
    gap: 30,
    padding: 36,
    borderRadius: 34,
    background: "rgba(255,255,255,.08)",
    border: "1px solid rgba(255,255,255,.14)",
  },
  resetNumber: { fontSize: 140, fontWeight: 950, color: "#8a7cff", lineHeight: 0.9 },
  resetCopy: { color: "#b9c9e8", fontSize: 22, lineHeight: 1.35, margin: 0 },
  resetRail: { display: "grid", gridTemplateColumns: "repeat(4,1fr)", gap: 16, marginTop: 26 },
  resetCard: { padding: 22, borderRadius: 22, border: "1px solid", background: "rgba(255,255,255,.07)" },
  resetRadar: {
    position: "absolute",
    right: 36,
    bottom: 28,
    width: 270,
    height: 270,
    borderRadius: 999,
    border: "1px solid rgba(138,124,255,.35)",
    background: "radial-gradient(circle, rgba(138,124,255,.18), transparent 58%)",
  },
  radarNeedle: {
    position: "absolute",
    left: "50%",
    top: "50%",
    width: 2,
    height: 124,
    transformOrigin: "bottom center",
    background: "linear-gradient(to top, #8a7cff, transparent)",
  },
  smallPreview: { position: "absolute", right: 340, bottom: 18, width: 270, height: 340, borderRadius: 22, overflow: "hidden", opacity: 0.65 },
  smallPreviewImage: { width: "100%", height: "100%", objectFit: "cover" },
  screenshotScene: { position: "absolute", inset: "122px 62px 132px 760px" },
  screenFrame: {
    position: "absolute",
    inset: 0,
    borderRadius: 36,
    overflow: "hidden",
    border: "1px solid rgba(196,215,255,.28)",
    background: "#eaf1ff",
    boxShadow: "0 46px 110px rgba(0,0,0,.42)",
  },
  windowDots: { position: "absolute", top: 20, left: 24, zIndex: 4, display: "flex", gap: 9 },
  mainScreenshot: { width: "100%", height: "100%", objectFit: "cover" },
  metricStack: { position: "absolute", right: 40, top: 88, width: 250, display: "grid", gap: 16 },
  sideMetric: {
    padding: 20,
    borderRadius: 20,
    background: "rgba(3,8,22,.72)",
    border: "1px solid rgba(255,255,255,.13)",
    boxShadow: "0 16px 40px rgba(0,0,0,.24)",
  },
  toolkitGrid: { position: "absolute", inset: "150px 76px 172px 760px", display: "grid", gridTemplateColumns: "repeat(2,1fr)", gap: 20 },
  toolCard: { padding: 30, borderRadius: 28, border: "1px solid", background: "rgba(255,255,255,.08)" },
  toolIcon: { width: 70, height: 70, borderRadius: 18, display: "grid", placeItems: "center", marginBottom: 24, fontWeight: 950 },
  privacyStage: { position: "absolute", inset: "148px 80px 168px 770px", display: "grid", gridTemplateColumns: "420px 1fr", gap: 30 },
  localCore: {
    borderRadius: 34,
    background: "rgba(255,255,255,.08)",
    border: "1px solid rgba(255,255,255,.14)",
    display: "grid",
    placeItems: "center",
    position: "relative",
    overflow: "hidden",
    fontSize: 30,
    fontWeight: 950,
  },
  lockRing: { position: "absolute", width: 290, height: 290, borderRadius: 999, border: "1px solid rgba(255,209,102,.42)" },
  lockIcon: { width: 146, height: 146, borderRadius: 32, boxShadow: "0 0 70px rgba(255,209,102,.25)" },
  policyGrid: { display: "grid", gridTemplateColumns: "repeat(2, 1fr)", gap: 16 },
  policyItem: { padding: 24, borderRadius: 22, background: "rgba(255,255,255,.07)", border: "1px solid rgba(255,255,255,.14)", fontSize: 24, fontWeight: 850 },
  ctaStage: { position: "absolute", inset: "130px 140px 190px", display: "grid", placeItems: "center" },
  ctaIcon: { width: 180, height: 180, borderRadius: 42, boxShadow: "0 0 90px rgba(122,167,255,.55)", zIndex: 2 },
  ctaText: { marginTop: 250, position: "absolute", fontSize: 86, fontWeight: 950, zIndex: 2 },
  ctaSub: { marginTop: 390, position: "absolute", fontSize: 27, color: "#b9c9e8", fontWeight: 750, zIndex: 2 },
  ctaBeam: { position: "absolute", width: 1000, height: 2, background: "linear-gradient(90deg, transparent, #7aa7ff, transparent)", boxShadow: "0 0 44px #7aa7ff" },
  ctaRing: { position: "absolute", width: 680, height: 680, borderRadius: 999, border: "1px solid rgba(122,167,255,.35)" },
  captionBox: {
    position: "absolute",
    left: "50%",
    bottom: 34,
    transform: "translateX(-50%)",
    zIndex: 50,
    width: 1280,
    padding: "18px 26px 20px",
    borderRadius: 22,
    background: "rgba(2,7,18,.74)",
    border: "1px solid rgba(255,255,255,.14)",
    backdropFilter: "blur(18px)",
    textAlign: "center",
    boxShadow: "0 20px 60px rgba(0,0,0,.34)",
  },
  captionEn: { fontSize: 26, lineHeight: 1.22, fontWeight: 850, color: "#ffffff" },
  captionZh: { fontSize: 24, lineHeight: 1.3, marginTop: 8, color: "#bcd2f6", fontWeight: 750 },
  timeline: { position: "absolute", left: 58, right: 58, bottom: 14, height: 5, display: "flex", gap: 5, zIndex: 60 },
  timelineSegment: { height: "100%", borderRadius: 999 },
};
