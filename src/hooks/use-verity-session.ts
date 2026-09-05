"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { startDemoSensor } from "@/lib/demo-sensor";
import {
  isWebBluetoothSupported,
  readBatteryPercent,
  requestPolarDevice,
  subscribeHeartRate,
} from "@/lib/heart-rate-ble";
import { newSessionId, saveSession } from "@/lib/storage";
import type {
  ConnectionStatus,
  HeartSample,
  SessionSource,
} from "@/lib/types";

type LiveState = {
  status: ConnectionStatus;
  source: SessionSource | null;
  deviceName: string | null;
  batteryPercent: number | null;
  error: string | null;
  samples: HeartSample[];
  startedAt: number | null;
};

const idleState: LiveState = {
  status: "idle",
  source: null,
  deviceName: null,
  batteryPercent: null,
  error: null,
  samples: [],
  startedAt: null,
};

export function useVeritySession() {
  const [state, setState] = useState<LiveState>(idleState);
  const [now, setNow] = useState(() => Date.now());
  const stopRef = useRef<(() => void) | null>(null);
  const samplesRef = useRef<HeartSample[]>([]);
  const metaRef = useRef({
    source: null as SessionSource | null,
    deviceName: null as string | null,
    startedAt: null as number | null,
  });

  const persistIfNeeded = useCallback(() => {
    const { source, deviceName, startedAt } = metaRef.current;
    const samples = samplesRef.current;
    if (!source || !deviceName || !startedAt || samples.length === 0) return;
    saveSession({
      id: newSessionId(),
      startedAt,
      endedAt: Date.now(),
      deviceName,
      source,
      samples,
    });
  }, []);

  const teardown = useCallback(
    (nextStatus: ConnectionStatus, error?: string) => {
      stopRef.current?.();
      stopRef.current = null;
      persistIfNeeded();
      samplesRef.current = [];
      metaRef.current = { source: null, deviceName: null, startedAt: null };
      setState({
        ...idleState,
        status: nextStatus,
        error: error ?? null,
      });
    },
    [persistIfNeeded],
  );

  useEffect(() => {
    return () => {
      stopRef.current?.();
      persistIfNeeded();
    };
  }, [persistIfNeeded]);

  useEffect(() => {
    if (state.status !== "live") return;
    const id = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(id);
  }, [state.status]);

  const pushSample = useCallback((sample: HeartSample) => {
    samplesRef.current = [...samplesRef.current, sample];
    setState((current) => ({
      ...current,
      status: "live",
      samples: samplesRef.current,
    }));
  }, []);

  const startDemo = useCallback(() => {
    stopRef.current?.();
    persistIfNeeded();
    const startedAt = Date.now();
    samplesRef.current = [];
    metaRef.current = {
      source: "demo",
      deviceName: "Polar Verity Sense (demo)",
      startedAt,
    };
    setState({
      status: "live",
      source: "demo",
      deviceName: "Polar Verity Sense (demo)",
      batteryPercent: 81,
      error: null,
      samples: [],
      startedAt,
    });
    stopRef.current = startDemoSensor({ onReading: pushSample });
  }, [persistIfNeeded, pushSample]);

  const connectSensor = useCallback(async () => {
    stopRef.current?.();
    persistIfNeeded();
    samplesRef.current = [];
    metaRef.current = { source: null, deviceName: null, startedAt: null };
    setState({
      ...idleState,
      status: "connecting",
    });

    if (!isWebBluetoothSupported()) {
      setState({
        ...idleState,
        status: "error",
        error:
          "Web Bluetooth is not available here. Use Chrome or Edge on localhost, or start a demo session.",
      });
      return;
    }

    let device: BluetoothDevice | null = null;
    try {
      device = await requestPolarDevice();
      if (!device.gatt) {
        throw new Error("This device does not expose a GATT server.");
      }

      const onDisconnected = () => {
        teardown("disconnected", "The Polar Verity Sense disconnected.");
      };
      device.addEventListener("gattserverdisconnected", onDisconnected);

      const server = await device.gatt.connect();
      const batteryPercent = await readBatteryPercent(server);
      const subscription = await subscribeHeartRate(server, pushSample);
      const startedAt = Date.now();
      const deviceName = device.name || "Polar Verity Sense";

      metaRef.current = { source: "ble", deviceName, startedAt };
      setState({
        status: "live",
        source: "ble",
        deviceName,
        batteryPercent,
        error: null,
        samples: [],
        startedAt,
      });

      stopRef.current = () => {
        device?.removeEventListener("gattserverdisconnected", onDisconnected);
        void subscription.stop();
        if (device?.gatt?.connected) {
          device.gatt.disconnect();
        }
      };
    } catch (error) {
      const message =
        error instanceof DOMException && error.name === "NotFoundError"
          ? "No Polar device was selected."
          : error instanceof Error
            ? error.message
            : "Could not connect to Polar Verity Sense.";
      setState({
        ...idleState,
        status: "error",
        error: message,
      });
    }
  }, [persistIfNeeded, pushSample, teardown]);

  const stop = useCallback(() => {
    teardown("idle");
  }, [teardown]);

  const latest = state.samples.at(-1) ?? null;
  const elapsedMs =
    state.status === "live" && state.startedAt ? now - state.startedAt : 0;

  return useMemo(
    () => ({
      ...state,
      latest,
      elapsedMs,
      bluetoothSupported:
        typeof navigator !== "undefined" && isWebBluetoothSupported(),
      startDemo,
      connectSensor,
      stop,
    }),
    [state, latest, elapsedMs, startDemo, connectSensor, stop],
  );
}
