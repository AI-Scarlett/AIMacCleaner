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

function remainingColor(percent) {
  if (percent <= 15) return "190,63,70,255";
  if (percent <= 35) return "182,104,35,255";
  return "35,92,150,255";
}

function resetText(value) {
  if (!value) return "";
  const resetAt = new Date(value);
  if (Number.isNaN(resetAt.getTime())) return "";
  const remaining = Math.max(0, resetAt.getTime() - Date.now());
  const hours = Math.floor(remaining / 3_600_000);
  const minutes = Math.floor((remaining % 3_600_000) / 60_000);
  if (hours >= 24) return `${Math.ceil(hours / 24)}天`;
  if (hours > 0) return `${hours}h${String(minutes).padStart(2, "0")}`;
  return `${Math.max(1, minutes)}m`;
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
  const ranked = providers
    .flatMap((provider) => (Array.isArray(provider.windows) ? provider.windows : []).map((window) => ({ provider, window })))
    .filter(({ window }) => Number.isFinite(Number(window.remainingPercent)))
    .sort((left, right) => Number(left.window.remainingPercent) - Number(right.window.remainingPercent));

  if (ranked.length === 0) {
    return {
      text: state.isRefreshing ? "正在读取额度…" : "暂无额度数据",
      background_color: "71,76,87,255",
      font_color: "238,240,244,255",
      font_size: 12,
    };
  }

  const { provider, window } = ranked[0];
  const remaining = Math.max(0, Math.min(100, Math.round(Number(window.remainingPercent))));
  const reset = resetText(window.resetsAt);
  const freshness = provider.freshness === "stale" ? " ~" : "";
  return {
    text: `${provider.name} ${labelForKind(window.kind)} ${remaining}%${reset ? ` · ${reset}` : ""}${freshness}`,
    background_color: remainingColor(remaining),
    font_color: "255,255,255,255",
    font_size: 13,
  };
}

const output = render();
if (args.has("--text")) {
  process.stdout.write(`${output.text}\n`);
} else {
  process.stdout.write(`${JSON.stringify(output)}\n`);
}
