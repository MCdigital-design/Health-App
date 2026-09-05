import type { SavedSession } from "@/lib/types";

const STORAGE_KEY = "polar-verity-sense.sessions.v1";
export const SESSIONS_CHANGED = "verity-sessions-changed";
export const EMPTY_SESSIONS: SavedSession[] = [];

let cachedRaw: string | null | undefined;
let cachedSessions: SavedSession[] = EMPTY_SESSIONS;

function canUseStorage(): boolean {
  return typeof window !== "undefined" && typeof localStorage !== "undefined";
}

export function loadSessions(): SavedSession[] {
  if (!canUseStorage()) return EMPTY_SESSIONS;
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw === cachedRaw) return cachedSessions;
    cachedRaw = raw;
    if (!raw) {
      cachedSessions = EMPTY_SESSIONS;
      return cachedSessions;
    }
    const parsed = JSON.parse(raw) as SavedSession[];
    if (!Array.isArray(parsed)) {
      cachedSessions = EMPTY_SESSIONS;
      return cachedSessions;
    }
    cachedSessions = [...parsed].sort((a, b) => b.startedAt - a.startedAt);
    return cachedSessions;
  } catch {
    cachedRaw = undefined;
    cachedSessions = EMPTY_SESSIONS;
    return cachedSessions;
  }
}

function writeSessions(next: SavedSession[]): void {
  const sorted = [...next].sort((a, b) => b.startedAt - a.startedAt);
  const raw = JSON.stringify(sorted);
  localStorage.setItem(STORAGE_KEY, raw);
  cachedRaw = raw;
  cachedSessions = sorted;
  window.dispatchEvent(new Event(SESSIONS_CHANGED));
}

export function saveSession(session: SavedSession): void {
  if (!canUseStorage()) return;
  writeSessions([
    session,
    ...loadSessions().filter((item) => item.id !== session.id),
  ]);
}

export function deleteSession(id: string): void {
  if (!canUseStorage()) return;
  writeSessions(loadSessions().filter((item) => item.id !== id));
}

export function getSession(id: string): SavedSession | null {
  return loadSessions().find((item) => item.id === id) ?? null;
}

export function newSessionId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `session-${Date.now()}-${Math.round(Math.random() * 1e6)}`;
}
