# Android permissions

Chuchula asks only for what online and Bluetooth play need. Offline play
needs no permissions.

| Permission | Android versions | Why |
|---|---|---|
| `INTERNET` | All | Online play through Firebase. Normal permission, no prompt. |
| `BLUETOOTH`, `BLUETOOTH_ADMIN` | 11 and lower (`maxSdkVersion 30`) | Classic Bluetooth on older Android. Install-time, no prompt. |
| `ACCESS_FINE_LOCATION` | 11 and lower (`maxSdkVersion 30`) | Older Android requires location to discover nearby Bluetooth devices. The app never reads location. |
| `BLUETOOTH_SCAN` | 12 and higher | Find a host phone. Declared `neverForLocation`, so it cannot be used to derive location. |
| `BLUETOOTH_CONNECT` | 12 and higher | Connect to paired phones and read their names. |
| `BLUETOOTH_ADVERTISE` | 12 and higher | Make the host phone discoverable. |

`android.hardware.bluetooth` is declared `required="false"`, so the app
installs on devices without Bluetooth. The Bluetooth button then explains
that the device has no Bluetooth.

## When the app asks

Runtime permissions are requested only when the player opens **Bluetooth
play** and taps **Allow Bluetooth**, after a screen that explains why. If
the player declines, the screen says so and offers **Open settings**.
Turning Bluetooth on uses the system dialog.

No camera, microphone, contacts, storage, notifications or background
location permissions are requested.
