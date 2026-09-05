import type { HeartSample, HeartZone, HeartZoneId } from "@/lib/types";

export const DEFAULT_MAX_HR = 185;

export function zoneForHeartRate(hr: number, maxHr = DEFAULT_MAX_HR): HeartZone {
  const zones = heartZones(maxHr);
  return (
    zones.find((zone) => hr >= zone.minBpm && hr < zone.maxBpm) ??
    zones[zones.length - 1]
  );
}

export function heartZones(maxHr = DEFAULT_MAX_HR): HeartZone[] {
  const bound = (ratio: number) => Math.round(maxHr * ratio);
  return [
    { id: "recovery", label: "Recovery", minBpm: 0, maxBpm: bound(0.6) },
    { id: "easy", label: "Easy", minBpm: bound(0.6), maxBpm: bound(0.7) },
    { id: "aerobic", label: "Aerobic", minBpm: bound(0.7), maxBpm: bound(0.8) },
    {
      id: "threshold",
      label: "Threshold",
      minBpm: bound(0.8),
      maxBpm: bound(0.9),
    },
    { id: "vo2", label: "VO2", minBpm: bound(0.9), maxBpm: maxHr + 40 },
  ];
}

export function zoneTone(id: HeartZoneId): string {
  switch (id) {
    case "recovery":
      return "bg-sky-400";
    case "easy":
      return "bg-emerald-400";
    case "aerobic":
      return "bg-amber-400";
    case "threshold":
      return "bg-orange-500";
    case "vo2":
      return "bg-rose-500";
  }
}

export function meanHeartRate(samples: HeartSample[]): number | null {
  if (samples.length === 0) return null;
  const sum = samples.reduce((total, sample) => total + sample.hr, 0);
  return Math.round(sum / samples.length);
}

export function minMaxHeartRate(samples: HeartSample[]): {
  min: number | null;
  max: number | null;
} {
  if (samples.length === 0) return { min: null, max: null };
  return {
    min: Math.min(...samples.map((sample) => sample.hr)),
    max: Math.max(...samples.map((sample) => sample.hr)),
  };
}

export function flattenRr(samples: HeartSample[]): number[] {
  return samples.flatMap((sample) => sample.rrMs);
}

/** RMSSD in milliseconds from RR intervals. */
export function rmssdMs(rrMs: number[]): number | null {
  if (rrMs.length < 2) return null;
  let sumSquares = 0;
  let count = 0;
  for (let i = 1; i < rrMs.length; i += 1) {
    const delta = rrMs[i] - rrMs[i - 1];
    sumSquares += delta * delta;
    count += 1;
  }
  if (count === 0) return null;
  return Math.round(Math.sqrt(sumSquares / count));
}

export function formatDuration(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

export function sessionToCsv(samples: HeartSample[]): string {
  const header = "timestamp_iso,elapsed_s,heart_rate_bpm,rr_intervals_ms";
  if (samples.length === 0) return `${header}\n`;
  const start = samples[0].t;
  const rows = samples.map((sample) => {
    const iso = new Date(sample.t).toISOString();
    const elapsed = ((sample.t - start) / 1000).toFixed(1);
    const rr = sample.rrMs.join("|");
    return `${iso},${elapsed},${sample.hr},${rr}`;
  });
  return `${header}\n${rows.join("\n")}\n`;
}
