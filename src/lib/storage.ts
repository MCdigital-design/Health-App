import type { SavedSession } from "@/lib/types";

const STORAGE_KEY = "polar-verity-sense.sessions.v1";
export const SESSIONS_CHANGED = "verity-sessions-changed";

function canUseStorage(): boolean {
  return typeof window !== "undefined" && typeof localStorage !== "undefined";
}

export function loadSessions(): SavedSession[] {
  if (!canUseStorage()) return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as SavedSession[];
    if (!Array.isArray(parsed)) return [];
    return parsed.sort((a, b) => b.startedAt - a.startedAt);
  } catch {
    return [];
  }
}

export function saveSession(session: SavedSession): void {
  if (!canUseStorage()) return;
  const next = [session, ...loadSessions().filter((item) => item.id !== session.id)];
  localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  window.dispatchEvent(new Event(SESSIONS_CHANGED));
}

export function deleteSession(id: string): void {
  if (!canUseStorage()) return;
  const next = loadSessions().filter((item) => item.id !== id);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
  window.dispatchEvent(new Event(SESSIONS_CHANGED));
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
