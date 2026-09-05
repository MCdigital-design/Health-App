import type { HeartReading } from "@/lib/types";

export const HEART_RATE_SERVICE = "heart_rate";
export const HEART_RATE_MEASUREMENT = "heart_rate_measurement";
export const BATTERY_SERVICE = "battery_service";
export const BATTERY_LEVEL = "battery_level";

export function isWebBluetoothSupported(): boolean {
  return typeof navigator !== "undefined" && Boolean(navigator.bluetooth);
}

export function parseHeartRateMeasurement(data: DataView): HeartReading {
  const flags = data.getUint8(0);
  const hr16 = (flags & 0x01) === 0x01;
  const contactBits = (flags >> 1) & 0x03;
  const energyPresent = (flags & 0x08) === 0x08;
  const rrPresent = (flags & 0x10) === 0x10;

  let offset = 1;
  const hr = hr16 ? data.getUint16(offset, true) : data.getUint8(offset);
  offset += hr16 ? 2 : 1;

  let energyExpendedKj: number | undefined;
  if (energyPresent && offset + 2 <= data.byteLength) {
    energyExpendedKj = data.getUint16(offset, true);
    offset += 2;
  }

  const rrMs: number[] = [];
  if (rrPresent) {
    while (offset + 2 <= data.byteLength) {
      const raw = data.getUint16(offset, true);
      rrMs.push(Math.round((raw / 1024) * 1000));
      offset += 2;
    }
  }

  let contact: HeartReading["contact"] = "unsupported";
  if (contactBits === 2) contact = "not-detected";
  if (contactBits === 3) contact = "detected";

  return {
    t: Date.now(),
    hr,
    rrMs,
    contact,
    energyExpendedKj,
  };
}

export async function requestPolarDevice(): Promise<BluetoothDevice> {
  if (!isWebBluetoothSupported()) {
    throw new Error(
      "Web Bluetooth is not available in this browser. Use Chrome or Edge on https or localhost.",
    );
  }

  return navigator.bluetooth.requestDevice({
    filters: [
      { namePrefix: "Polar Sense" },
      { namePrefix: "Polar Verity" },
      { namePrefix: "Polar" },
    ],
    optionalServices: [HEART_RATE_SERVICE, BATTERY_SERVICE],
  });
}

export async function readBatteryPercent(
  server: BluetoothRemoteGATTServer,
): Promise<number | null> {
  try {
    const service = await server.getPrimaryService(BATTERY_SERVICE);
    const characteristic = await service.getCharacteristic(BATTERY_LEVEL);
    const value = await characteristic.readValue();
    return value.getUint8(0);
  } catch {
    return null;
  }
}

export async function subscribeHeartRate(
  server: BluetoothRemoteGATTServer,
  onReading: (reading: HeartReading) => void,
): Promise<{
  characteristic: BluetoothRemoteGATTCharacteristic;
  stop: () => Promise<void>;
}> {
  const service = await server.getPrimaryService(HEART_RATE_SERVICE);
  const characteristic = await service.getCharacteristic(HEART_RATE_MEASUREMENT);

  const listener = (event: Event) => {
    const target = event.target as BluetoothRemoteGATTCharacteristic;
    if (!target.value) return;
    onReading(parseHeartRateMeasurement(target.value));
  };

  characteristic.addEventListener("characteristicvaluechanged", listener);
  await characteristic.startNotifications();

  return {
    characteristic,
    stop: async () => {
      try {
        characteristic.removeEventListener(
          "characteristicvaluechanged",
          listener,
        );
        await characteristic.stopNotifications();
      } catch {
        // Device may already be gone.
      }
    },
  };
}
