"use client";

import Link from "next/link";
import { Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  formatDuration,
  meanHeartRate,
  minMaxHeartRate,
} from "@/lib/hrv";
import { deleteSession } from "@/lib/storage";
import type { SavedSession } from "@/lib/types";

type SessionListProps = {
  sessions: SavedSession[];
  ready: boolean;
};

export function SessionList({ sessions, ready }: SessionListProps) {
  if (!ready) {
    return (
      <div className="rounded-2xl border border-white/10 bg-white/5 px-4 py-10 text-center text-sm text-white/50">
        Loading saved sessions…
      </div>
    );
  }

  if (sessions.length === 0) {
    return (
      <div className="rounded-2xl border border-dashed border-white/15 bg-white/5 px-6 py-12 text-center">
        <p className="text-lg font-medium">No sessions yet</p>
        <p className="mx-auto mt-2 max-w-md text-sm text-white/50">
          Recordings stay in this browser. Connect a Polar Verity Sense or run
          a demo from the Live page, then stop the session to save it here.
        </p>
        <Button className="mt-5" render={<Link href="/" />}>
          Go to live session
        </Button>
      </div>
    );
  }

  return (
    <ul className="space-y-3">
      {sessions.map((session) => {
        const avg = meanHeartRate(session.samples);
        const { min, max } = minMaxHeartRate(session.samples);
        const duration = formatDuration(session.endedAt - session.startedAt);
        return (
          <li
            key={session.id}
            className="flex flex-col gap-3 rounded-2xl bg-white/5 p-4 ring-1 ring-white/10 sm:flex-row sm:items-center sm:justify-between"
          >
            <div>
              <div className="flex flex-wrap items-center gap-2">
                <p className="font-medium">{session.deviceName}</p>
                <Badge variant="outline">
                  {session.source === "demo" ? "Demo" : "Sensor"}
                </Badge>
              </div>
              <p className="mt-1 text-sm text-white/50">
                {new Date(session.startedAt).toLocaleString()} · {duration} ·{" "}
                {session.samples.length} samples
                {avg != null ? ` · avg ${avg}` : ""}
                {min != null && max != null ? ` · ${min}–${max} bpm` : ""}
              </p>
            </div>
            <div className="flex gap-2">
              <Button
                variant="outline"
                render={<Link href={`/sessions/${session.id}`} />}
              >
                Open
              </Button>
              <Button
                variant="ghost"
                size="icon"
                aria-label="Delete session"
                onClick={() => deleteSession(session.id)}
              >
                <Trash2 />
              </Button>
            </div>
          </li>
        );
      })}
    </ul>
  );
}
