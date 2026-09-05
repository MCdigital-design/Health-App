import { heartZones, zoneForHeartRate, zoneTone } from "@/lib/hrv";

type ZoneBarProps = {
  hr: number | null;
  maxHr: number;
};

export function ZoneBar({ hr, maxHr }: ZoneBarProps) {
  const zones = heartZones(maxHr);
  const active = hr == null ? null : zoneForHeartRate(hr, maxHr);

  return (
    <div className="space-y-2">
      <div className="flex h-2 overflow-hidden rounded-full">
        {zones.map((zone) => (
          <div
            key={zone.id}
            className={`${zoneTone(zone.id)} flex-1 ${
              active?.id === zone.id ? "opacity-100" : "opacity-35"
            }`}
          />
        ))}
      </div>
      <div className="flex justify-between text-[11px] text-white/45">
        {zones.map((zone) => (
          <span
            key={zone.id}
            className={active?.id === zone.id ? "text-white" : undefined}
          >
            {zone.label}
          </span>
        ))}
      </div>
    </div>
  );
}
