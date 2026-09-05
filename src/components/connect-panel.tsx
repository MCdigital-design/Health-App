"use client";

import { Bluetooth, PlayCircle, Unplug } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import type { ConnectionStatus, SessionSource } from "@/lib/types";

type ConnectPanelProps = {
  status: ConnectionStatus;
  source: SessionSource | null;
  deviceName: string | null;
  batteryPercent: number | null;
  error: string | null;
  bluetoothSupported: boolean;
  onConnect: () => void;
  onDemo: () => void;
  onStop: () => void;
};

export function ConnectPanel({
  status,
  source,
  deviceName,
  batteryPercent,
  error,
  bluetoothSupported,
  onConnect,
  onDemo,
  onStop,
}: ConnectPanelProps) {
  const live = status === "live";

  return (
    <Card className="border-0 bg-white/5 ring-white/10">
      <CardHeader>
        <CardTitle>Sensor</CardTitle>
        <CardDescription>
          Pair a Polar Verity Sense over Bluetooth, or run a demo stream
          without hardware.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="rounded-xl bg-black/25 px-3 py-3">
          <p className="text-xs uppercase tracking-wide text-white/40">
            Status
          </p>
          <p className="mt-1 text-sm font-medium">
            {statusLabel(status, source)}
          </p>
          {deviceName ? (
            <p className="mt-1 text-sm text-white/65">
              {deviceName}
              {batteryPercent != null ? ` · ${batteryPercent}% battery` : ""}
            </p>
          ) : (
            <p className="mt-1 text-sm text-white/45">
              No sensor connected
            </p>
          )}
        </div>

        {status === "error" && error ? (
          <p className="rounded-lg bg-rose-500/10 px-3 py-2 text-sm text-rose-200">
            {error}
          </p>
        ) : null}

        {status === "disconnected" && error ? (
          <p className="rounded-lg bg-amber-500/10 px-3 py-2 text-sm text-amber-100">
            {error}
          </p>
        ) : null}

        {!bluetoothSupported && !live ? (
          <p className="text-sm text-white/50">
            This browser cannot open a Web Bluetooth picker. Chrome or Edge on
            localhost works. Use demo mode to exercise the dashboard now.
          </p>
        ) : null}

        <div className="flex flex-col gap-2 sm:flex-row">
          {live ? (
            <Button
              variant="destructive"
              className="sm:flex-1"
              onClick={onStop}
            >
              <Unplug data-icon="inline-start" />
              Stop session
            </Button>
          ) : (
            <>
              <Button
                className="sm:flex-1"
                onClick={onConnect}
                disabled={status === "connecting"}
              >
                <Bluetooth data-icon="inline-start" />
                {status === "connecting"
                  ? "Connecting…"
                  : "Connect Verity Sense"}
              </Button>
              <Button
                variant="outline"
                className="sm:flex-1"
                onClick={onDemo}
                disabled={status === "connecting"}
              >
                <PlayCircle data-icon="inline-start" />
                Start demo
              </Button>
            </>
          )}
        </div>
      </CardContent>
    </Card>
  );
}

function statusLabel(
  status: ConnectionStatus,
  source: SessionSource | null,
): string {
  if (status === "connecting") return "Looking for Polar Verity Sense…";
  if (status === "live" && source === "demo") return "Demo stream live";
  if (status === "live") return "Sensor live";
  if (status === "disconnected") return "Disconnected";
  if (status === "error") return "Connection failed";
  return "Idle";
}
