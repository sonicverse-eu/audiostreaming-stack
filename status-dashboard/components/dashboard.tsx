"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useAuth } from "@/lib/auth";
import {
  apiFetch,
  apiPost,
  type StreamStatus,
  type StackConfig,
  type Alert,
  type Container,
  type EmergencyFile,
} from "@/lib/api";
import { Card } from "./card";
import { StatusDot } from "./status-dot";

const REFRESH_MS = 5000;

export function Dashboard() {
  const { user, jwt, logout } = useAuth();
  const [status, setStatus] = useState<StreamStatus | null>(null);
  const [config, setConfig] = useState<StackConfig | null>(null);
  const [alerts, setAlerts] = useState<Alert[]>([]);
  const [containers, setContainers] = useState<Container[]>([]);
  const [emergencyFiles, setEmergencyFiles] = useState<EmergencyFile[]>([]);
  const [uploadStatus, setUploadStatus] = useState("");
  const progressRef = useRef<HTMLDivElement>(null);

  const refresh = useCallback(async () => {
    if (!jwt) return;
    const [s, a, c, e] = await Promise.allSettled([
      apiFetch<StreamStatus>("/api/status", jwt),
      apiFetch<Alert[]>("/api/alerts", jwt),
      apiFetch<Container[]>("/api/containers", jwt),
      apiFetch<EmergencyFile[]>("/api/emergency-audio", jwt),
    ]);
    if (s.status === "fulfilled") setStatus(s.value);
    if (a.status === "fulfilled") setAlerts(a.value);
    if (c.status === "fulfilled" && Array.isArray(c.value))
      setContainers(c.value);
    if (e.status === "fulfilled") setEmergencyFiles(e.value);
  }, [jwt]);

  // Load config once
  useEffect(() => {
    if (!jwt) return;
    apiFetch<StackConfig>("/api/config", jwt).then(setConfig).catch(() => {});
  }, [jwt]);

  // Refresh loop
  useEffect(() => {
    refresh();
    const id = setInterval(() => {
      refresh();
      // Animate progress bar
      if (progressRef.current) {
        progressRef.current.style.transition = "none";
        progressRef.current.style.width = "0%";
        requestAnimationFrame(() => {
          if (progressRef.current) {
            progressRef.current.style.transition = `width ${REFRESH_MS}ms linear`;
            progressRef.current.style.width = "100%";
          }
        });
      }
    }, REFRESH_MS);
    return () => clearInterval(id);
  }, [refresh]);

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file || !jwt) return;
    setUploadStatus(`Uploading ${file.name}...`);
    try {
      const form = new FormData();
      form.append("file", file);
      await apiPost("/api/emergency-audio/upload", jwt, form);
      setUploadStatus("Uploaded successfully");
      refresh();
    } catch {
      setUploadStatus("Upload failed");
    }
    e.target.value = "";
    setTimeout(() => setUploadStatus(""), 5000);
  }

  async function handleDelete(filename: string) {
    if (!jwt || !confirm(`Remove ${filename}? Stream will have no fallback.`))
      return;
    await apiPost("/api/emergency-audio/delete", jwt, { filename });
    refresh();
  }

  function copyCmd(text: string, el: HTMLElement) {
    navigator.clipboard.writeText(text);
    el.classList.add("!text-amber-400");
    setTimeout(() => el.classList.remove("!text-amber-400"), 600);
  }

  const hostname = config?.hostname || "<host>";

  const commands = [
    ["View all logs", "docker compose logs -f"],
    ["Liquidsoap logs", "docker compose logs -f liquidsoap"],
    ["Icecast logs", "docker compose logs -f icecast"],
    ["Restart all", "docker compose restart"],
    ["Restart Liquidsoap", "docker compose restart liquidsoap"],
    ["Stop everything", "docker compose down"],
    ["Rebuild & restart", "docker compose up -d --build"],
    ["Renew SSL", "docker compose run --rm certbot renew"],
    ["Test stream (VLC)", `vlc https://${hostname}/listen/stream-mp3-128`],
    ["Container status", "docker ps --filter name=breezeradio-"],
    ["Icecast stats", "curl http://localhost:8000/status-json.xsl"],
    ["Disk usage", "docker system df"],
  ];

  return (
    <>
      {/* Progress bar */}
      <div
        ref={progressRef}
        className="fixed top-0 left-0 h-0.5 bg-[#4f8ff7] z-50"
        style={{ width: "100%" }}
      />

      {/* Header */}
      <header className="flex items-center justify-between px-6 py-4 border-b border-[#2a2e3d] bg-[#1a1d27]">
        <h1 className="text-base font-semibold">
          {config?.station_name || "Broadcast"} — Status Panel
        </h1>
        <div className="flex items-center gap-4">
          <span className="text-[#8b90a0] text-xs">{user?.email}</span>
          <button
            onClick={logout}
            className="px-3 py-1.5 bg-[#22263a] border border-[#2a2e3d] rounded-md text-[#8b90a0] text-xs hover:text-[#e1e4ed] hover:border-[#8b90a0]"
          >
            Sign Out
          </button>
        </div>
      </header>

      {/* Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 p-6 max-w-[1400px] mx-auto">
        {/* Total listeners */}
        <Card title="Total Listeners">
          <div className="text-4xl font-bold leading-none mb-1">
            {status?.total_listeners ?? "—"}
          </div>
          <div className="text-[#8b90a0] text-xs">across all mounts</div>
        </Card>

        {/* Stream health */}
        <Card title="Stream Health">
          {!status ? (
            <p className="text-sm text-[#8b90a0]">Loading...</p>
          ) : status.status === "ok" && status.mounts.length > 0 ? (
            <>
              <p className="text-sm">
                <StatusDot color="green" /> All systems operational
              </p>
              <p className="text-xs text-[#8b90a0] mt-1">
                {status.mounts.length} active mounts
              </p>
            </>
          ) : status.status === "ok" ? (
            <p className="text-sm">
              <StatusDot color="yellow" /> No active mounts
            </p>
          ) : (
            <>
              <p className="text-sm">
                <StatusDot color="red" /> Icecast unreachable
              </p>
              {status.error && (
                <p className="text-xs text-[#8b90a0] mt-1">{status.error}</p>
              )}
            </>
          )}
        </Card>

        {/* Emergency audio */}
        <Card title="Emergency Audio">
          <div className="mb-3">
            {emergencyFiles.length === 0 ? (
              <p className="text-sm text-red-400">
                <StatusDot color="red" /> No fallback audio — upload one!
              </p>
            ) : (
              emergencyFiles.map((f) => (
                <div
                  key={f.filename}
                  className="flex items-center justify-between py-1.5 border-b border-[#2a2e3d] text-sm last:border-0"
                >
                  <div>
                    <StatusDot color="green" />
                    <span className="font-mono text-xs">{f.filename}</span>
                    <span className="text-[#8b90a0] ml-2 text-xs">
                      {f.size_mb} MB
                    </span>
                  </div>
                  <button
                    onClick={() => handleDelete(f.filename)}
                    className="px-2 py-1 text-xs border border-red-400/50 text-red-400 rounded hover:bg-red-400/10"
                  >
                    Remove
                  </button>
                </div>
              ))
            )}
          </div>
          <div className="border-2 border-dashed border-[#2a2e3d] rounded-lg p-4 text-center">
            <p className="text-[#8b90a0] text-xs mb-2">
              Upload fallback audio (.mp3, .flac, .wav, .ogg)
            </p>
            <label className="px-3 py-1.5 bg-[#22263a] border border-[#2a2e3d] rounded-md text-[#8b90a0] text-xs cursor-pointer hover:text-[#e1e4ed]">
              Choose File
              <input
                type="file"
                accept=".mp3,.flac,.wav,.ogg"
                onChange={handleUpload}
                className="hidden"
              />
            </label>
            {uploadStatus && (
              <p
                className={`text-xs mt-2 ${
                  uploadStatus.includes("success")
                    ? "text-emerald-400"
                    : uploadStatus.includes("fail")
                    ? "text-red-400"
                    : "text-[#4f8ff7]"
                }`}
              >
                {uploadStatus}
              </p>
            )}
          </div>
        </Card>

        {/* Mount points */}
        <Card title="Mount Points" fullWidth>
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="text-left text-[0.7rem] uppercase tracking-wider text-[#8b90a0]">
                  <th className="px-3 py-2 border-b border-[#2a2e3d]">
                    Mount
                  </th>
                  <th className="px-3 py-2 border-b border-[#2a2e3d]">
                    Format
                  </th>
                  <th className="px-3 py-2 border-b border-[#2a2e3d]">
                    Listeners
                  </th>
                  <th className="px-3 py-2 border-b border-[#2a2e3d]">Peak</th>
                  <th className="px-3 py-2 border-b border-[#2a2e3d]">
                    Now Playing
                  </th>
                </tr>
              </thead>
              <tbody>
                {!status || status.mounts.length === 0 ? (
                  <tr>
                    <td
                      colSpan={5}
                      className="px-3 py-3 text-sm text-[#8b90a0]"
                    >
                      No active mounts
                    </td>
                  </tr>
                ) : (
                  status.mounts.map((m) => (
                    <tr
                      key={m.mount}
                      className="border-b border-[#2a2e3d] last:border-0"
                    >
                      <td className="px-3 py-2.5 font-mono text-xs">
                        {m.mount}
                      </td>
                      <td className="px-3 py-2.5 text-sm">
                        {m.content_type || m.audio_info || "—"}
                      </td>
                      <td className="px-3 py-2.5 text-sm">{m.listeners}</td>
                      <td className="px-3 py-2.5 text-sm text-[#8b90a0]">
                        {m.peak_listeners}
                      </td>
                      <td className="px-3 py-2.5 text-sm text-[#8b90a0]">
                        {m.title || "—"}
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </Card>

        {/* Configuration */}
        <Card title="Configuration">
          {config ? (
            <ul>
              {[
                ["Hostname", config.hostname],
                ["Primary Port (FLAC)", config.harbor_primary_port],
                ["Fallback Port (Ogg)", config.harbor_fallback_port],
                ["Max Listeners", config.max_listeners],
                ["Silence Threshold", `${config.silence_threshold_db} dB`],
                ["Silence Duration", `${config.silence_duration_s}s`],
                ["PostHog", config.posthog_enabled ? "Enabled" : "Disabled"],
                [
                  "Pushover Alerts",
                  config.pushover_enabled ? "Enabled" : "Disabled",
                ],
              ].map(([k, v]) => (
                <li
                  key={k}
                  className="flex justify-between py-2 border-b border-[#2a2e3d] text-sm last:border-0"
                >
                  <span className="text-[#8b90a0]">{k}</span>
                  <span className="font-mono text-[#4f8ff7]">{v}</span>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-[#8b90a0]">Loading...</p>
          )}
        </Card>

        {/* Containers */}
        <Card title="Containers">
          {containers.length > 0 ? (
            containers.map((c) => {
              const isUp = c.status.toLowerCase().includes("up");
              return (
                <div
                  key={c.name}
                  className="flex items-center gap-3 py-2 border-b border-[#2a2e3d] text-sm last:border-0"
                >
                  <StatusDot color={isUp ? "green" : "red"} />
                  <span className="font-mono text-xs">{c.name}</span>
                  <span className="text-[#8b90a0] text-xs ml-auto">
                    {c.status}
                  </span>
                </div>
              );
            })
          ) : (
            <p className="text-sm text-[#8b90a0]">No containers found</p>
          )}
        </Card>

        {/* Databases & Storage */}
        <Card title="Databases & Storage">
          <ul>
            {[
              ["PostHog", config?.posthog_enabled ? "Connected" : "Not configured"],
              ["Appwrite", "Connected (auth)"],
              ["Icecast Logs", "Docker volume"],
              ["HLS Segments", "Shared volume"],
              ["Alert History", "In-memory (50 events)"],
            ].map(([k, v]) => (
              <li
                key={k}
                className="flex justify-between py-2 border-b border-[#2a2e3d] text-sm last:border-0"
              >
                <span className="text-[#8b90a0]">{k}</span>
                <span className="font-mono text-[#4f8ff7] text-xs">{v}</span>
              </li>
            ))}
          </ul>
        </Card>

        {/* Alerts */}
        <Card title="Recent Alerts" fullWidth>
          <div className="max-h-72 overflow-y-auto">
            {alerts.length === 0 ? (
              <p className="text-sm text-[#8b90a0]">No alerts — all clear</p>
            ) : (
              alerts.map((a, i) => (
                <div
                  key={i}
                  className="flex items-start gap-2 py-2 border-b border-[#2a2e3d] text-xs last:border-0"
                >
                  <span className="text-[#8b90a0] font-mono whitespace-nowrap">
                    {new Date(a.timestamp * 1000).toLocaleTimeString()}
                  </span>
                  <span
                    className={`font-semibold ${
                      a.type.includes("silence_start") || a.type.includes("disconnected")
                        ? "text-red-400"
                        : a.type.includes("silence_end") || a.type.includes("connected")
                        ? "text-emerald-400"
                        : "text-amber-400"
                    }`}
                  >
                    {a.type.replace(/_/g, " ")}
                  </span>
                  {a.message && (
                    <span className="text-[#8b90a0]">{a.message}</span>
                  )}
                </div>
              ))
            )}
          </div>
        </Card>

        {/* Commands */}
        <Card title="Useful Commands" fullWidth>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            {commands.map(([label, cmd]) => (
              <div
                key={label}
                className="bg-[#0f1117] border border-[#2a2e3d] rounded-lg p-3"
              >
                <div className="text-[#8b90a0] text-[0.7rem] mb-1">
                  {label}
                </div>
                <div
                  className="font-mono text-xs text-emerald-400 cursor-pointer hover:underline transition-colors"
                  onClick={(e) => copyCmd(cmd, e.currentTarget)}
                >
                  {cmd}
                </div>
              </div>
            ))}
          </div>
        </Card>
      </div>
    </>
  );
}
