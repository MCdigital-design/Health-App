"use client";

import { useState } from "react";
import { ConnectPanel } from "@/components/connect-panel";
import { LiveHeart } from "@/components/live-heart";
import { Input } from "@/components/ui/input";
import { DEFAULT_MAX_HR } from "@/lib/hrv";
import { useVeritySession } from "@/hooks/use-verity-session";

export default function LivePage() {
  const session = useVeritySession();
  const [maxHr, setMaxHr] = useState(DEFAULT_MAX_HR);

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8">
      <div className="max-w-2xl">
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-cyan-200/70">
          Polar Verity Sense
        </p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight sm:text-4xl">
          Live optical heart rate
        </h1>
        <p className="mt-2 text-sm text-white/55 sm:text-base">
          Dedicated Verity Sense workspace — keep Polar sensor work here,
          separate from AlphaTrend. Pair the armband over Web Bluetooth or
          preview the dashboard with a demo stream.
        </p>
      </div>

      <div className="grid gap-4 lg:grid-cols-[minmax(0,1.4fr)_minmax(18rem,0.8fr)]">
        <LiveHeart
          samples={session.samples}
          elapsedMs={session.elapsedMs}
          maxHr={maxHr}
        />
        <div className="space-y-4">
          <ConnectPanel
            status={session.status}
            source={session.source}
            deviceName={session.deviceName}
            batteryPercent={session.batteryPercent}
            error={session.error}
            bluetoothSupported={session.bluetoothSupported}
            onConnect={() => void session.connectSensor()}
            onDemo={session.startDemo}
            onStop={session.stop}
          />
          <label className="block rounded-xl bg-white/5 p-4 ring-1 ring-white/10">
            <span className="text-sm font-medium">Max HR for zones</span>
            <span className="mt-1 block text-xs text-white/45">
              Used only to color Polar-style training zones. Default 185.
            </span>
            <Input
              className="mt-3"
              type="number"
              min={120}
              max={220}
              value={maxHr}
              onChange={(event) =>
                setMaxHr(Number(event.target.value) || DEFAULT_MAX_HR)
              }
            />
          </label>
        </div>
      </div>
    </div>
  );
}
