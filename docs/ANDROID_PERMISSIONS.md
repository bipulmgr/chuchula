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

Added automatically by libraries (normal permissions, no prompt):

| Permission | From | Why |
|---|---|---|
| `ACCESS_NETWORK_STATE` | Firebase | Lets Firestore detect when the connection drops and comes back. |
| `WAKE_LOCK` | Firebase / AndroidX | Lets background work finish a short task. |
| `com.bipulmgr.chuchula.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` | AndroidX | Internal signature permission that keeps the app's own broadcasts private. |
| `com.google.android.gms.permission.AD_ID` | Google Mobile Ads | Rewarded ads for cash points. Google requires it to serve and measure ads; the Play Console data safety form must declare it. |
| `ACCESS_ADSERVICES_AD_ID`, `ACCESS_ADSERVICES_ATTRIBUTION` | Google Mobile Ads | Android's Privacy Sandbox versions of the ad id and ad measurement, used on Android 13 and higher. |

Firebase also asks for `com.google.android.c2dm.permission.RECEIVE` and
`READ_GSERVICES` (push messaging). The app does not use push, so the
manifest removes both. Google Mobile Ads also asks for
`ACCESS_ADSERVICES_TOPICS` (interest-based ad topics), which rewarded ads
do not need, so the manifest removes it too. CI fails if the release APK gains any permission
not listed on this page.

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
