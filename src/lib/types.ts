export type SessionSource = "ble" | "demo";

export type ConnectionStatus =
  | "idle"
  | "connecting"
  | "live"
  | "disconnected"
  | "error";

export type HeartSample = {
  t: number;
  hr: number;
  rrMs: number[];
  contact?: "detected" | "not-detected" | "unsupported";
};

export type HeartReading = HeartSample & {
  energyExpendedKj?: number;
};

export type SavedSession = {
  id: string;
  startedAt: number;
  endedAt: number;
  deviceName: string;
  source: SessionSource;
  samples: HeartSample[];
  notes?: string;
};

export type HeartZoneId =
  | "recovery"
  | "easy"
  | "aerobic"
  | "threshold"
  | "vo2";

export type HeartZone = {
  id: HeartZoneId;
  label: string;
  minBpm: number;
  maxBpm: number;
};
