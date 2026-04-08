const API_URL = process.env.NEXT_PUBLIC_API_URL || "";

function resolveApiUrl(path: string): string {
  if (!API_URL) {
    return path;
  }

  const apiBaseUrl = new URL(API_URL);
  const url = new URL(path, apiBaseUrl);

  if (url.origin !== apiBaseUrl.origin) {
    throw new Error(`Cross-origin API path is not allowed: ${path}`);
  }

  return url.toString();
}

function buildJsonHeaders(jwt: string): HeadersInit {
  return {
    Authorization: `Bearer ${jwt}`,
  };
}

function buildPostBody(
  jwt: string,
  body?: Record<string, unknown> | FormData
): { headers: Record<string, string>; reqBody: string | FormData | undefined } {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${jwt}`,
  };
  let reqBody: string | FormData | undefined;

  if (body instanceof FormData) {
    reqBody = body;
  } else if (body) {
    headers["Content-Type"] = "application/json";
    reqBody = JSON.stringify(body);
  }

  return { headers, reqBody };
}

export async function fetchStatus(jwt: string): Promise<StreamStatus> {
  const res = await fetch(resolveApiUrl("/api/status"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function fetchAlerts(jwt: string): Promise<Alert[]> {
  const res = await fetch(resolveApiUrl("/api/alerts"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function fetchContainers(jwt: string): Promise<Container[]> {
  const res = await fetch(resolveApiUrl("/api/containers"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function fetchEmergencyAudio(
  jwt: string
): Promise<EmergencyFile[]> {
  const res = await fetch(resolveApiUrl("/api/emergency-audio"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function fetchConfig(jwt: string): Promise<StackConfig> {
  const res = await fetch(resolveApiUrl("/api/config"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function fetchCommandsConfig(
  jwt: string
): Promise<CommandsConfig> {
  const res = await fetch(resolveApiUrl("/api/commands"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function verifyApiAccess(jwt: string): Promise<StreamStatus> {
  const res = await fetch(resolveApiUrl("/api/status"), {
    headers: buildJsonHeaders(jwt),
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function uploadEmergencyAudio(
  jwt: string,
  body: FormData
): Promise<unknown> {
  const { headers, reqBody } = buildPostBody(jwt, body);
  const res = await fetch(resolveApiUrl("/api/emergency-audio/upload"), {
    method: "POST",
    headers,
    body: reqBody,
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function deleteEmergencyAudio(
  jwt: string,
  body: Record<string, unknown>
): Promise<unknown> {
  const { headers, reqBody } = buildPostBody(jwt, body);
  const res = await fetch(resolveApiUrl("/api/emergency-audio/delete"), {
    method: "POST",
    headers,
    body: reqBody,
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function runCommandRequest(
  jwt: string,
  body: Record<string, unknown>
): Promise<CommandResult> {
  const { headers, reqBody } = buildPostBody(jwt, body);
  const res = await fetch(resolveApiUrl("/api/commands/run"), {
    method: "POST",
    headers,
    body: reqBody,
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

// Types
export interface Mount {
  mount: string;
  listeners: number;
  peak_listeners: number;
  name: string;
  description: string;
  audio_info: string;
  genre: string;
  title: string;
  content_type: string;
  stream_start: string;
}

export interface StreamStatus {
  status: string;
  station_name: string;
  server_id: string;
  total_listeners: number;
  mounts: Mount[];
  timestamp: number;
  error?: string;
}

export interface StackConfig {
  station_name: string;
  icecast_url: string;
  hostname: string;
  harbor_primary_port: string;
  harbor_fallback_port: string;
  silence_threshold_db: string;
  silence_duration_s: string;
  max_listeners: string;
  posthog_enabled: boolean;
  pushover_enabled: boolean;
  can_manage_emergency_audio: boolean;
  can_run_risky_commands: boolean;
}

export interface Alert {
  type: string;
  message: string;
  timestamp: number;
}

export interface Container {
  name: string;
  status: string;
  image: string;
  ports: string;
}

export interface EmergencyFile {
  filename: string;
  size_bytes: number;
  size_mb: number;
  modified: number;
}

export interface CommandDef {
  id: string;
  label: string;
  requires_service: boolean;
}

export interface CommandsConfig {
  commands: CommandDef[];
  services: string[];
}

export interface CommandResult {
  ok?: boolean;
  output?: string;
  exit_code?: number;
  error?: string;
}
