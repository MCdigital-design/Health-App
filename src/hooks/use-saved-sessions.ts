"use client";

import { useSyncExternalStore } from "react";
import {
  EMPTY_SESSIONS,
  SESSIONS_CHANGED,
  loadSessions,
} from "@/lib/storage";

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

function getServerSessions() {
  return EMPTY_SESSIONS;
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
    getServerSessions,
  );

  return { sessions: ready ? sessions : EMPTY_SESSIONS, ready };
}
