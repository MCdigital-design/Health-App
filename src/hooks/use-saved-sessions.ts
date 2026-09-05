"use client";

import { useSyncExternalStore } from "react";
import { SESSIONS_CHANGED, loadSessions } from "@/lib/storage";
import type { SavedSession } from "@/lib/types";

function subscribe(onStoreChange: () => void) {
  window.addEventListener(SESSIONS_CHANGED, onStoreChange);
  window.addEventListener("storage", onStoreChange);
  return () => {
    window.removeEventListener(SESSIONS_CHANGED, onStoreChange);
    window.removeEventListener("storage", onStoreChange);
  };
}

function clientMounted() {
  return true;
}

function serverNotMounted() {
  return false;
}

export function useSavedSessions() {
  const ready = useSyncExternalStore(
    () => () => undefined,
    clientMounted,
    serverNotMounted,
  );
  const sessions = useSyncExternalStore(
    subscribe,
    loadSessions,
    (): SavedSession[] => [],
  );

  return { sessions: ready ? sessions : [], ready };
}
