import type { HeartReading } from "@/lib/types";

type DemoOptions = {
  onReading: (reading: HeartReading) => void;
};

/**
 * Synthetic Polar Verity Sense stream: optical HR plus RR intervals.
 * Walks through an easy warm-up into aerobic work so the dashboard
 * is usable without a sensor attached.
 */
export function startDemoSensor({ onReading }: DemoOptions): () => void {
  let elapsed = 0;
  let phase = 0;

  const tick = () => {
    elapsed += 1;
    phase += 0.12;

    const warmup = Math.min(1, elapsed / 45);
    const base = 68 + warmup * 42;
    const wobble = Math.sin(phase) * 4 + Math.sin(phase * 0.37) * 3;
    const hr = Math.round(clamp(base + wobble, 54, 168));

    const beatMs = 60000 / hr;
    const rrMs = [
      Math.round(beatMs + randBetween(-18, 18)),
      Math.round(beatMs + randBetween(-18, 18)),
    ].filter((value) => value > 280);

    onReading({
      t: Date.now(),
      hr,
      rrMs,
      contact: "detected",
    });
  };

  tick();
  const id = window.setInterval(tick, 1000);
  return () => window.clearInterval(id);
}

function clamp(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, value));
}

function randBetween(min: number, max: number): number {
  return min + Math.random() * (max - min);
}
