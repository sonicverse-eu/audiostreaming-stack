const API_URL = process.env.NEXT_PUBLIC_API_URL || "";

export async function apiFetch<T>(path: string, jwt: string): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    headers: { Authorization: `Bearer ${jwt}` },
  });
  if (res.status === 401) throw new Error("Unauthorized");
  if (!res.ok) throw new Error(`API error: ${res.status}`);
  return res.json();
}

export async function apiPost<T>(
  path: string,
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

  const res = await fetch(`${API_URL}${path}`, {
    method: "POST",
    headers,
    body: reqBody,
  });
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
