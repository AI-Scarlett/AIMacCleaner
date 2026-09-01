#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const args = new Map();
for (let index = 2; index < process.argv.length; index += 1) {
  const key = process.argv[index];
  if (!key.startsWith("--")) continue;
  const value = process.argv[index + 1];
  if (value && !value.startsWith("--")) {
    args.set(key, value);
    index += 1;
  } else {
    args.set(key, true);
  }
}

const defaultStateFile = path.join(
  os.homedir(),
  "Library",
  "Application Support",
  "TraceFence",
  "TouchBar",
  "quota-status.json",
);
const stateFile = args.get("--state-file") || process.env.TRACEFENCE_TOUCHBAR_QUOTA_STATE || defaultStateFile;

function loadState() {
  try {
    const state = JSON.parse(fs.readFileSync(stateFile, "utf8"));
    return state && state.schemaVersion === 1 ? state : null;
  } catch {
    return null;
  }
}

function labelForKind(kind) {
  switch (kind) {
    case "fiveHour": return "5h";
    case "weekly": return "周";
    case "monthly": return "月";
    default: return "额度";
  }
}

function shortLabelForKind(kind) {
  const label = labelForKind(kind);
  return label === "额度" ? "" : label;
}

function remainingColor(percent) {
  if (percent <= 15) return "190,63,70,255";
  if (percent <= 35) return "182,104,35,255";
  return "35,92,150,255";
}

function render() {
  const state = loadState();
  if (!state) {
    return {
      text: "额度监控未启用",
      background_color: "71,76,87,255",
      font_color: "238,240,244,255",
      font_size: 12,
    };
  }

  const providers = Array.isArray(state.providers) ? state.providers : [];
  const agents = providers
    .map((provider) => {
      const windows = (Array.isArray(provider.windows) ? provider.windows : [])
        .filter((window) => Number.isFinite(Number(window.remainingPercent)))
        .sort((left, right) => Number(left.remainingPercent) - Number(right.remainingPercent));
      const window = windows[0];
      if (!window) return null;
      return {
        provider,
        window,
        remaining: Math.max(0, Math.min(100, Math.round(Number(window.remainingPercent)))),
      };
    })
    .filter(Boolean)
    .sort((left, right) => left.provider.name.localeCompare(right.provider.name));

  if (agents.length === 0) {
    return {
      text: state.isRefreshing ? "正在读取额度…" : "暂无额度数据",
      background_color: "71,76,87,255",
      font_color: "238,240,244,255",
      font_size: 12,
    };
  }

  const lowestRemaining = Math.min(...agents.map((agent) => agent.remaining));
  const text = agents.map(({ provider, window, remaining }) => {
    const kind = shortLabelForKind(window.kind);
    const freshness = provider.freshness === "stale" ? " ~" : "";
    return `${provider.name}${kind ? ` ${kind}` : ""} ${remaining}%${freshness}`;
  }).join(" · ");
  return {
    text,
    background_color: remainingColor(lowestRemaining),
    font_color: "255,255,255,255",
    font_size: agents.length >= 4 ? 12 : 13,
  };
}

const output = render();
if (args.has("--text")) {
  process.stdout.write(`${output.text}\n`);
} else {
  process.stdout.write(`${JSON.stringify(output)}\n`);
}
