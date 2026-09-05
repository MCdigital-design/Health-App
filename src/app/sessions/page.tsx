"use client";

import { SessionList } from "@/components/session-list";
import { useSavedSessions } from "@/hooks/use-saved-sessions";

export default function SessionsPage() {
  const { sessions, ready } = useSavedSessions();

  return (
    <div className="mx-auto flex w-full max-w-6xl flex-col gap-6 px-4 py-6 sm:px-6 sm:py-8">
      <div>
        <p className="text-xs font-medium uppercase tracking-[0.2em] text-cyan-200/70">
          History
        </p>
        <h1 className="mt-2 text-3xl font-semibold tracking-tight">
          Saved sessions
        </h1>
        <p className="mt-2 max-w-2xl text-sm text-white/55 sm:text-base">
          Sessions are stored in this browser only. Stopping a live or demo
          recording writes it here so you can reopen or export CSV.
        </p>
      </div>
      <SessionList sessions={sessions} ready={ready} />
    </div>
  );
}
