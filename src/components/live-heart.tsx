import { Badge } from "@/components/ui/badge";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { HrSparkline } from "@/components/hr-sparkline";
import { ZoneBar } from "@/components/zone-bar";
import {
  formatDuration,
  meanHeartRate,
  minMaxHeartRate,
  rmssdMs,
  flattenRr,
  zoneForHeartRate,
} from "@/lib/hrv";
import type { HeartSample } from "@/lib/types";

type LiveHeartProps = {
  samples: HeartSample[];
  elapsedMs: number;
  maxHr: number;
};

export function LiveHeart({ samples, elapsedMs, maxHr }: LiveHeartProps) {
  const latest = samples.at(-1) ?? null;
  const avg = meanHeartRate(samples);
  const { min, max } = minMaxHeartRate(samples);
  const hrv = rmssdMs(flattenRr(samples));
  const zone = latest ? zoneForHeartRate(latest.hr, maxHr) : null;

  if (!latest) {
    return (
      <Card className="border-0 bg-white/5 ring-white/10">
        <CardHeader>
          <CardTitle>Heart rate</CardTitle>
          <CardDescription>
            Connect a Polar Verity Sense or start a demo to begin a session.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="flex min-h-56 flex-col items-center justify-center rounded-2xl border border-dashed border-white/15 bg-black/20 px-6 text-center">
            <p className="text-5xl font-semibold tracking-tight text-white/20">
              — —
            </p>
            <p className="mt-3 max-w-sm text-sm text-white/45">
              Optical HR from Polar Verity Sense appears here, including RR
              intervals when the sensor publishes them.
            </p>
          </div>
        </CardContent>
      </Card>
    );
  }

  return (
    <Card className="border-0 bg-white/5 ring-white/10">
      <CardHeader>
        <div className="flex items-start justify-between gap-3">
          <div>
            <CardTitle>Heart rate</CardTitle>
            <CardDescription>
              Session {formatDuration(elapsedMs)}
              {latest.contact === "detected"
                ? " · skin contact"
                : latest.contact === "not-detected"
                  ? " · no contact"
                  : ""}
            </CardDescription>
          </div>
          {zone ? (
            <Badge variant="secondary" className="capitalize">
              {zone.label}
            </Badge>
          ) : null}
        </div>
      </CardHeader>
      <CardContent className="space-y-6">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="text-[11px] uppercase tracking-[0.18em] text-rose-200/70">
              BPM
            </p>
            <p className="font-heading text-7xl leading-none font-semibold tracking-tight text-rose-100 sm:text-8xl">
              {latest.hr}
            </p>
          </div>
          <HrSparkline
            samples={samples}
            className="h-20 w-full max-w-sm sm:h-24"
          />
        </div>
        <ZoneBar hr={latest.hr} maxHr={maxHr} />
        <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <Stat label="Average" value={avg != null ? String(avg) : "—"} />
          <Stat
            label="Range"
            value={min != null && max != null ? `${min}–${max}` : "—"}
          />
          <Stat label="RMSSD" value={hrv != null ? `${hrv} ms` : "—"} />
          <Stat
            label="Last RR"
            value={
              latest.rrMs.length > 0
                ? `${latest.rrMs[latest.rrMs.length - 1]} ms`
                : "—"
            }
          />
        </dl>
      </CardContent>
    </Card>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-xl bg-black/25 px-3 py-3">
      <dt className="text-[11px] uppercase tracking-wide text-white/40">
        {label}
      </dt>
      <dd className="mt-1 text-lg font-medium">{value}</dd>
    </div>
  );
}
