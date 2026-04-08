const API_URL = process.env.NEXT_PUBLIC_API_URL || "";
export type ApiGetEndpoint =
  | "alerts"
  | "commands"
  | "config"
  | "containers"
  | "emergencyAudio"
  | "status";
export type ApiPostEndpoint =
  | "commandsRun"
  | "emergencyAudioDelete"
  | "emergencyAudioUpload";

function resolveApiUrl(path: string): string {
  if (!API_URL) {
    return path;
  }

  const normalizedBase = API_URL.endsWith("/") ? API_URL : `${API_URL}/`;
  const apiBaseUrl = new URL(normalizedBase);
  const url = new URL(path.slice(1), normalizedBase);

  if (url.origin !== apiBaseUrl.origin) {
    throw new Error(`Cross-origin API path is not allowed: ${path}`);
  }

  return url.toString();
}

function getRequest(
  endpoint: ApiGetEndpoint,
  headers: HeadersInit
): Promise<Response> {
  switch (endpoint) {
    case "alerts":
      return fetch(resolveApiUrl("/api/alerts"), { headers });
    case "commands":
      return fetch(resolveApiUrl("/api/commands"), { headers });
    case "config":
      return fetch(resolveApiUrl("/api/config"), { headers });
    case "containers":
      return fetch(resolveApiUrl("/api/containers"), { headers });
    case "emergencyAudio":
      return fetch(resolveApiUrl("/api/emergency-audio"), { headers });
    case "status":
      return fetch(resolveApiUrl("/api/status"), { headers });
  }
}

function postRequest(
  endpoint: ApiPostEndpoint,
  init: RequestInit
): Promise<Response> {
  switch (endpoint) {
    case "commandsRun":
      return fetch(resolveApiUrl("/api/commands/run"), init);
    case "emergencyAudioDelete":
      return fetch(resolveApiUrl("/api/emergency-audio/delete"), init);
    case "emergencyAudioUpload":
      return fetch(resolveApiUrl("/api/emergency-audio/upload"), init);
  }
}

export async function apiFetch<T>(
  endpoint: ApiGetEndpoint,
  jwt: string
): Promise<T> {
  const res = await getRequest(endpoint, {
    Authorization: `Bearer ${jwt}`,
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function apiPost<T>(
  endpoint: ApiPostEndpoint,
  jwt: string,
  body?: Record<string, unknown> | FormData
): Promise<T> {
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

  const res = await postRequest(endpoint, {
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
