# Polar Verity Sense

Dedicated home for Polar Verity Sense work, kept separate from AlphaTrend.

This repo is a browser companion for the Polar Verity Sense optical heart-rate sensor. Pair the armband over Web Bluetooth (standard Heart Rate + RR intervals), or run a demo stream when no sensor is attached. Sessions stay in the browser and can be exported as CSV.

## Why this repo exists

Polar Verity Sense work does not belong in the AlphaTrend repository. This project is the place to host that sensor work on its own.

## Run locally

```bash
npm install
npm run dev
```

The app listens on [http://127.0.0.1:43147](http://127.0.0.1:43147).

## Using a real Polar Verity Sense

1. Open the app in Chrome or Edge (Web Bluetooth is required).
2. Wear the sensor and put it in **sensor / heart mode**.
3. Click **Connect Verity Sense** and pick the Polar device from the browser picker.
4. Stop the session when you are done. It appears under **Sessions**.

Web Bluetooth only works on `https` or `localhost` / `127.0.0.1`. If the picker is unavailable, use **Start demo**.

## What is stored

Sessions are written to `localStorage` in this browser only. Nothing is uploaded. There is no backend and no Polar Flow login.

## Scripts

| Command | Purpose |
| --- | --- |
| `npm run dev` | Development server on port 43147 |
| `npm run build` | Production build |
| `npm run start` | Serve the production build |
| `npm run lint` | ESLint |

## Polar features this slice uses

- BLE Heart Rate service (`0x180D`) for BPM
- RR intervals when the sensor includes them in the HR measurement
- Battery service when the device exposes it
- Demo mode that synthesizes HR + RR so the UI can be used without hardware
