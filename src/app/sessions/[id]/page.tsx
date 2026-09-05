"use client";

import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import { useMemo } from "react";
import { HrSparkline } from "@/components/hr-sparkline";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { useSavedSessions } from "@/hooks/use-saved-sessions";
import {
  flattenRr,
  formatDuration,
  meanHeartRate,
  minMaxHeartRate,
  rmssdMs,
  sessionToCsv,
} from "@/lib/hrv";
import { deleteSession } from "@/lib/storage";

export default function SessionDetailPage() {
  const params = useParams<{ id: string }>();
  const router = useRouter();
  const { sessions, ready } = useSavedSessions();
  const session = useMemo(
    () => sessions.find((item) => item.id === params.id) ?? null,
    [params.id, sessions],
  );

  if (!ready) {
    return (
      <div className="mx-auto max-w-6xl px-4 py-16 text-center text-sm text-white/50">
        Loading session…
      </div>
    );
  }

  if (!session) {
    return (
      <div className="mx-auto max-w-xl px-4 py-16 text-center">
        <h1 className="text-2xl font-semibold">Session not found</h1>
        <p className="mt-2 text-sm text-white/50">
          It may have been deleted from this browser, or the link is stale.
        </p>
        <Button className="mt-5" render={<Link href="/sessions" />}>
          Back to sessions
        </Button>
      </div>
    );
  }

  const avg = meanHeartRate(session.samples);
  const { min, max } = minMaxHeartRate(session.samples);
  const hrv = rmssdMs(flattenRr(session.samples));

  const exportCsv = () => {
    const blob = new Blob([sessionToCsv(session.samples)], {
      type: "text/csv;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = `verity-sense-${session.id.slice(0, 8)}.csv`;
    anchor.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8">
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div>
          <p className="text-xs font-medium uppercase tracking-[0.2em] text-cyan-200/70">
            Session
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight">
            {session.deviceName}
          </h1>
          <p className="mt-2 text-sm text-white/55">
            {new Date(session.startedAt).toLocaleString()} ·{" "}
            {formatDuration(session.endedAt - session.startedAt)}
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Badge variant="outline">
            {session.source === "demo" ? "Demo" : "Sensor"}
          </Badge>
          <Button variant="outline" onClick={exportCsv}>
            Export CSV
          </Button>
          <Button
            variant="destructive"
            onClick={() => {
              deleteSession(session.id);
              router.push("/sessions");
            }}
          >
            Delete
          </Button>
        </div>
      </div>

      <Card className="border-0 bg-white/5 ring-white/10">
        <CardHeader>
          <CardTitle>Summary</CardTitle>
          <CardDescription>
            {session.samples.length} heart-rate samples stored locally
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-5">
          <HrSparkline samples={session.samples} className="h-24 w-full" />
          <dl className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <div className="rounded-xl bg-black/25 px-3 py-3">
              <dt className="text-[11px] uppercase tracking-wide text-white/40">
                Average
              </dt>
              <dd className="mt-1 text-lg font-medium">
                {avg != null ? `${avg} bpm` : "—"}
              </dd>
            </div>
            <div className="rounded-xl bg-black/25 px-3 py-3">
              <dt className="text-[11px] uppercase tracking-wide text-white/40">
                Range
              </dt>
              <dd className="mt-1 text-lg font-medium">
                {min != null && max != null ? `${min}–${max}` : "—"}
              </dd>
            </div>
            <div className="rounded-xl bg-black/25 px-3 py-3">
              <dt className="text-[11px] uppercase tracking-wide text-white/40">
                RMSSD
              </dt>
              <dd className="mt-1 text-lg font-medium">
                {hrv != null ? `${hrv} ms` : "—"}
              </dd>
            </div>
            <div className="rounded-xl bg-black/25 px-3 py-3">
              <dt className="text-[11px] uppercase tracking-wide text-white/40">
                Last HR
              </dt>
              <dd className="mt-1 text-lg font-medium">
                {session.samples.at(-1)?.hr ?? "—"}
              </dd>
            </div>
          </dl>
        </CardContent>
      </Card>

      <Button variant="ghost" render={<Link href="/sessions" />}>
        Back to sessions
      </Button>
    </div>
  );
}
