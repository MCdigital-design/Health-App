import type { HeartSample } from "@/lib/types";

type HrSparklineProps = {
  samples: HeartSample[];
  className?: string;
};

export function HrSparkline({ samples, className }: HrSparklineProps) {
  const windowed = samples.slice(-90);
  if (windowed.length < 2) {
    return (
      <div
        className={`flex items-center justify-center text-sm text-white/40 ${className ?? ""}`}
      >
        Waiting for a few more beats…
      </div>
    );
  }

  const values = windowed.map((sample) => sample.hr);
  const min = Math.min(...values) - 4;
  const max = Math.max(...values) + 4;
  const range = Math.max(1, max - min);
  const width = 320;
  const height = 88;
  const points = values
    .map((value, index) => {
      const x = (index / (values.length - 1)) * width;
      const y = height - ((value - min) / range) * height;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");

  return (
    <svg
      viewBox={`0 0 ${width} ${height}`}
      className={className}
      role="img"
      aria-label="Heart rate over the last 90 samples"
    >
      <polyline
        fill="none"
        stroke="rgba(251,113,133,0.95)"
        strokeWidth="2.5"
        strokeLinejoin="round"
        strokeLinecap="round"
        points={points}
      />
    </svg>
  );
}
