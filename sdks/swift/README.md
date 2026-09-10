<!-- This file is auto-generated from docs/doc/developer/sdk/swift.mdx. Do not edit manually. -->
## Overview

An easy-to-install Swift package for connecting to Omi devices. Get started in seconds with local Whisper-based transcription - no cloud API required.

<CardGroup cols={3}>
  <Card title="Swift Package" icon="swift">
    Native iOS/macOS support
  </Card>
  <Card title="Local Transcription" icon="microphone">
    Whisper runs on-device
  </Card>
  <Card title="Simple API" icon="code">
    Connect in minutes
  </Card>
</CardGroup>


## Quick Start

Get transcription working in 2 minutes:

<Steps>
  <Step title="Copy This Code">
    Replace your `ViewController.swift` with:

    ```swift
    import UIKit
    import omi_lib

    class ViewController: UIViewController {

        override func viewDidLoad() {
            super.viewDidLoad()
            self.lookForDevice()
        }

        func lookForDevice() {
            OmiManager.startScan { device, error in
                print("starting scan")
                if let device = device {
                    print("got device ", device)
                    self.connectToOmiDevice(device: device)
                    OmiManager.endScan()
                }
            }
        }

        func connectToOmiDevice(device: Device) {
            OmiManager.connectToDevice(device: device)
            self.listenToLiveTranscript(device: device)
            self.reconnectIfDisconnects()
        }

        func reconnectIfDisconnects() {
            OmiManager.connectionUpdated { connected in
                if connected == false {
                    self.lookForDevice()
                }
            }
        }

        func listenToLiveTranscript(device: Device) {
            OmiManager.getLiveTranscription(device: device) { transcription in
                print("transcription:", transcription ?? "no transcription")
            }
        }
    }
    ```
  </Step>
  <Step title="Build and Run">
    1. Select your development team
    2. Connect your iPhone via cable (simulators don't support Bluetooth)
    3. Run the project
  </Step>
  <Step title="Test It">
    1. Turn on your Omi device
    2. The app should connect automatically
    3. Speak - you'll see transcription in the Xcode console

    <Note>
    There's no UI in this example - transcription appears in the Xcode logs.
    </Note>

    <img
      src="https://github.com/user-attachments/assets/636b33ac-7ea7-4e1c-b490-8ec99b1feef8"
      alt="Xcode Console Output"
      style={{maxWidth: '600px'}}
    />
  </Step>
</Steps>


## OmiManager Methods

| Method | Description |
|--------|-------------|
| `startScan(callback)` | Start scanning for Omi devices |
| `endScan()` | Stop scanning |
| `connectToDevice(device)` | Connect to a discovered or previously paired device |
| `knownDevice(id:)` | Prepare a saved peripheral UUID for reconnection |
| `connectionUpdated(callback)` | Monitor connection state changes |
| `getLiveTranscription(device, callback)` | Receive real-time transcription |
| `getLiveAudio(device, callback)` | Receive audio file URLs |


## Related

<CardGroup cols={2}>
  <Card title="SDK Overview" icon="cube" href="/doc/developer/sdk/sdk">
    Compare all available SDKs
  </Card>
  <Card title="GitHub Source" icon="github" href="https://github.com/BasedHardware/omi">
    View source code and contribute
  </Card>
</CardGroup>


## Background audio capture (Claire fork)

`getLiveAudio` delivers finalized mono PCM WAV files at packet boundaries about
30 seconds apart. `stopLiveTranscription` delivers the remaining partial file
before disconnecting. The caller owns each file and must persist/upload it and
then delete it. Raw capture does not load Whisper.

For automatic power-on capture, save the UUID from explicit initial pairing.
On later launches, register connection/audio callbacks, obtain `knownDevice(id:)`,
and call `connectToDevice`. Core Bluetooth waits for that exact peripheral;
unknown UUIDs use service-filtered discovery. Codec notifications start recording
without readiness timers. Stop cancels both pending connections and capture.

The host app must declare `bluetooth-central` background mode, recreate its
listening owner on launch, and persist the user's enabled/paused intent. The BLE
manager uses restoration identifier `omi.listen.connection`; this SDK manages
one capture device at a time. Force-quitting the app requires reopening it.
See [Apple background processing](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).

Focused verification: `swift test --filter 'OmiRecording|OmiPacket'` exercises
WAV rotation/frame preservation, packet scheduling, codec-triggered recording,
and cancellation before another codec event. These are functional software
tests, not evidence of a real iPhone/Omi background power cycle or battery life.

### Temporary capture suspension

`OmiManager.setAudioCapturePolicy(device:shouldCapture:)` evaluates the predicate
on BLE audio notifications. False skips decoding and WAV writes while retaining
BLE notifications for background wakeups. Raw capture finalizes the pre-pause
WAV once, drops the in-flight partial packet, and starts a new interval on resume.
Stop still disconnects and clears the policy. Caller owns call/meeting detection.

Verification: `swift test --filter Omi` includes a PCM packet → WAV pause/resume
check. It exercises the production BLE subject/recorder boundary, not physical
Bluetooth delivery or locked-iPhone scheduling.
