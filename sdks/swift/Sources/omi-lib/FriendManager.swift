//
//  FriendManager.swift
//  scribehardware
//
//  Created by Ash Bhat on 9/28/24.
//

import CoreBluetooth
import Speech
import AVFoundation
import SwiftWhisper
import AudioKit

func makeOmiAudioSnapshot(from sourceURL: URL) throws -> URL {
    let snapshotURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("wav")
    do {
        try FileManager.default.copyItem(at: sourceURL, to: snapshotURL)
        return snapshotURL
    } catch {
        try? FileManager.default.removeItem(at: snapshotURL)
        throw error
    }
}

struct OmiTranscriptionGate {
    private(set) var generation = UUID()
    private(set) var active = false
    private(set) var intervalInFlight = false

    mutating func start() -> UUID {
        generation = UUID()
        active = true
        intervalInFlight = false
        return generation
    }

    mutating func beginInterval(for candidate: UUID) -> Bool {
        guard active, candidate == generation, !intervalInFlight else {
            return false
        }
        intervalInFlight = true
        return true
    }

    mutating func finishInterval(for candidate: UUID) -> Bool {
        guard active, candidate == generation else { return false }
        intervalInFlight = false
        return true
    }

    mutating func stop() {
        active = false
        intervalInFlight = false
        generation = UUID()
    }
}

struct OmiPacketChunkScheduler {
    let interval: TimeInterval
    private var intervalStart: TimeInterval?

    init(interval: TimeInterval) {
        self.interval = interval
    }

    mutating func observePacket(at uptime: TimeInterval) -> Bool {
        guard let intervalStart else {
            self.intervalStart = uptime
            return false
        }

        guard uptime >= intervalStart else {
            self.intervalStart = uptime
            return false
        }

        guard uptime - intervalStart >= interval else { return false }
        self.intervalStart = uptime
        return true
    }

    mutating func reset() {
        intervalStart = nil
    }
}

class FriendManager {
    
    static var singleton = FriendManager()
   
    var bluetoothScanner: BluetoothScanner!
    var friendDevice: Friend?  // Retain Friend object
    var bleManager: BLEManager?  // Retain BLEManager
    var audioPlayer: AVAudioPlayer?

    var deviceCompletion: ((Friend?, Error?) -> Void)?
    var transcriptCompletion: ((String?) -> Void)?
    
    var connectionCompletion: ((Bool) -> Void)?
    let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    let whisper: Whisper?
    
    var audioFileTimer: Timer?
    var transcriptionGate = OmiTranscriptionGate()
    var transcriptionScheduler = OmiPacketChunkScheduler(interval: 8.0)

    init() {
        let modelURL = Bundle.module.url(forResource: "ggml-tiny.en", withExtension: "bin")!
        whisper = Whisper(fromFileURL: modelURL)
        // whisper = nil
        bluetoothScanner = BluetoothScanner()
        bluetoothScanner.delegate = self
    }
    
    @objc func transcribeAudio(url: URL, completion: @escaping (String?, Error?) ->Void) {
        self.extractTextFromAudio(url) { result, error in
            if let result = result {
                completion(result, error)
            }
            else {
                print("error")
                completion(result, error)
            }
        }
    }
    
    func extractTextFromAudio(_ audioURL: URL, completionHandler: @escaping (String?, Error?) ->Void) {
        
        let originalStderr = dup(fileno(stderr))
        let nullDevice = open("/dev/null", O_WRONLY)
        dup2(nullDevice, fileno(stderr))
        close(nullDevice)
        
        convertAudioFileToPCMArray(fileURL: audioURL) { result in
            guard let whisper = self.whisper else {
                completionHandler(nil, nil)
                return
            }
            switch result {
                case .success(let success):
                    Task {
                        do {
                            let segments = try await whisper.transcribe(audioFrames: success)
                            completionHandler(segments.map(\.text).joined(), nil)
                        } catch {
                            completionHandler(nil, error)
                        }
                    }
                case .failure(_):
                    completionHandler(nil, nil)
            }
            
            // Restore stdout after function execution
            // Restore the original stderr
            fflush(stderr)
            dup2(originalStderr, fileno(stderr))
            close(originalStderr)
        }
    }
    
    func getLiveTranscription(device: Friend, completion: @escaping (String?) -> Void) {
        transcriptCompletion = completion
        device.onAudioPacketBoundary = nil
        transcriptionScheduler.reset()
        let transcriptionGeneration = transcriptionGate.start()
        print("[Omi] audio-driven live transcription started")
        device.onAudioPacketBoundary = { [weak self, weak device] uptime in
            guard let self, let device else { return }
            guard !self.transcriptionGate.intervalInFlight else { return }
            guard self.transcriptionScheduler.observePacket(at: uptime) else { return }
            guard self.transcriptionGate.beginInterval(for: transcriptionGeneration) else {
                return
            }

            print("[Omi] packet-driven transcription interval fired")
            do {
                guard let snapshotURL = try device.snapshotRecording() else {
                    _ = self.transcriptionGate.finishInterval(for: transcriptionGeneration)
                    print("[Omi] no active recording to snapshot")
                    completion(nil)
                    return
                }
                if self.fileHasData(url: snapshotURL) {
                    print("file has data")
                } else {
                    print("no data in file")
                }

                self.transcribeAudio(url: snapshotURL, completion: { result, error in
                    DispatchQueue.main.async {
                        try? FileManager.default.removeItem(at: snapshotURL)
                        let shouldDeliver = self.transcriptionGate.finishInterval(
                            for: transcriptionGeneration
                        )
                        print("[Omi] transcription completed characters=\(result?.count ?? 0) error=\(error?.localizedDescription ?? "none") deliver=\(shouldDeliver)")
                        if shouldDeliver {
                            completion(result)
                        }
                    }
                })
            } catch {
                _ = self.transcriptionGate.finishInterval(for: transcriptionGeneration)
                print("Failed to snapshot Omi audio: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }

    func stopLiveTranscription(device: Friend) {
        print("[Omi] stopping live transcription")
        device.onAudioPacketBoundary = nil
        transcriptionScheduler.reset()
        audioFileTimer?.invalidate()
        audioFileTimer = nil
        transcriptCompletion = nil
        transcriptionGate.stop()
        device.stopRecording()
        device.bleManager.disconnect()
    }
    
    /// Provides audio chunks from the Omi device every 8 seconds.
    ///
    /// Each completed segment is flushed and copied before the active recording rotates.
    func getRawAudio(device: Friend, completion: @escaping (URL?) -> Void) {
        audioFileTimer?.invalidate()
        audioFileTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: true, block: { timer in
            do {
                guard let snapshotURL = try device.snapshotRecording() else {
                    completion(nil)
                    return
                }
                let attributes = try? FileManager.default.attributesOfItem(
                    atPath: snapshotURL.path
                )
                let fileSize = attributes?[.size] as? UInt64 ?? 0
                guard fileSize > 44 else {
                    try? FileManager.default.removeItem(at: snapshotURL)
                    completion(nil)
                    return
                }
                completion(snapshotURL)
            } catch {
                completion(nil)
            }
        })
    }
    
    func getCurrentTranscription(completion: @escaping (String?) -> Void) {
        guard let friendDevice = self.friendDevice else {
            completion(nil)
            return
        }
        do {
            guard let snapshotURL = try friendDevice.snapshotRecording() else {
                completion(nil)
                return
            }
            if self.fileHasData(url: snapshotURL) {
                print("file has data")
            } else {
                print("no data in file")
            }

            self.transcribeAudio(url: snapshotURL, completion: { result, error in
                try? FileManager.default.removeItem(at: snapshotURL)
                completion(result)
            })
        } catch {
            completion(nil)
        }
    }
    
    func fileHasData(url: URL) -> Bool {
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = fileAttributes[FileAttributeKey.size] as? UInt64 {
                return fileSize > 0
            }
        } catch {
            print("Error checking file size: \(error.localizedDescription)")
        }
        return false
    }
    
    func replayAudio(from url: URL) {
        do {
            // Initialize the audio player with the file URL
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch let error {
            print("Failed to play audio: \(error.localizedDescription)")
        }
    }

    func connectionStatus(completion: @escaping(Bool) -> Void) {
        self.connectionCompletion = completion
    }
    
    func startScan() {
        print("[Omi] scan requested")
        bluetoothScanner.startScan()
    }
    
    func startRecordingWhenReady() {
        switch self.friendDevice?.status {
            case .ready:
                let uuidString = UUID().uuidString
                let recording = Recording(filename: "\(uuidString).wav")  // Your custom recording handler
                self.friendDevice!.start(recording: recording)
            case .error(_):
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
                    self.startRecordingWhenReady()
                })
            case .none:
                print("should not reach here")
        }
    }
    
    func startRecordingWhenReady(device: Friend) {
        switch device.status {
            case .ready:
                print("[Omi] device ready; starting recording")
                let uuidString = UUID().uuidString
                let recording = Recording(filename: "\(uuidString).wav")  // Your custom recording handler
                device.start(recording: recording)
            case .error(_):
                print("[Omi] waiting for device codec")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: {
                    self.startRecordingWhenReady(device: device)
                })
        }
    }
    
    
    func startRealTimeTranscription(from url: URL) {
        guard let recognizer = recognizer else {
            print("Speech recognizer is not available")
            return
        }
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        
        request.requiresOnDeviceRecognition = false // Change this to true if you want on-device recognition
        request.taskHint = .dictation  // Hints that this is conversational speech
        
        recognizer.recognitionTask(with: request) { (result, error) in
            if let error = error {
                print("Error transcribing audio: \(error.localizedDescription)")
                // Handle error
            } else if let result = result {
                // Print the transcribed text in real time
                print("Real-time Transcription: \(result.bestTranscription.formattedString)")
            }
        }
        
        if friendDevice?.isRecording == true, let fileURL = friendDevice?.recording?.fileURL {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: {
                self.startRealTimeTranscription(from: fileURL)
            })
        }
        
    }
    
    func transcribeAudioFile(url: URL, completion: @escaping (String?) -> Void) {
        // Create a recognizer for the user's current locale
        
        let request = SFSpeechURLRecognitionRequest(url: url)
        
        request.requiresOnDeviceRecognition = false // Change this to true if you want on-device recognition
        request.taskHint = .dictation  // Hints that this is conversational speech

        // Check if the recognizer is available
        guard recognizer?.isAvailable == true else {
            completion(nil)
            return
        }

        // Perform the recognition
        recognizer?.recognitionTask(with: request) { (result, error) in
            if let error = error {
                print("Error transcribing audio: \(error.localizedDescription)")
                completion(nil)
            } else if let result = result, result.isFinal {
                // Return the transcribed text
                completion(result.bestTranscription.formattedString)
            }
        }
    }
}

extension FriendManager: BluetoothScannerDelegate {
    func deviceFound(device: CBPeripheral) {
        print("[Omi] discovered supported device name=\(device.name ?? "unknown")")
        WearableDeviceRegistry.shared.registerDevice(wearable: Friend.self)
        self.bleManager = BLEManager(deviceRegistry: WearableDeviceRegistry.shared)
        self.bleManager?.delegate = self
        let friend_device = Friend(bleManager: bleManager!, name: "Friend")
        friend_device.id = device.identifier
        self.deviceCompletion?(friend_device, nil)
    }
    
    func connectToDevice(device: Friend) {
        print("[Omi] connecting to discovered device")
        let deviceUUID = device.id
        bleManager!.reconnect(to: deviceUUID)
        self.connectionCompletion?(true)
        self.startRecordingWhenReady(device: device)
    }
}

extension FriendManager: BLEManagerDelegate {
    func lostConnection() {
        connectionCompletion?(false)
    }
}

extension FriendManager {
    func convertAudioFileToPCMArray(fileURL: URL, completionHandler: @escaping (Result<[Float], Error>) -> Void) {
        var options = FormatConverter.Options()
        options.format = .wav
        options.sampleRate = 16000
        options.bitDepth = 16
        options.channels = 1
        options.isInterleaved = false

        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let converter = FormatConverter(inputURL: fileURL, outputURL: tempURL, options: options)
        converter.start { error in
            if let error {
                completionHandler(.failure(error))
                return
            }

            let data = try! Data(contentsOf: tempURL) // Handle error here

            let floats = stride(from: 44, to: data.count, by: 2).map {
                return data[$0..<$0 + 2].withUnsafeBytes {
                    let short = Int16(littleEndian: $0.load(as: Int16.self))
                    return max(-1.0, min(Float(short) / 32767.0, 1.0))
                }
            }

            try? FileManager.default.removeItem(at: tempURL)

            completionHandler(.success(floats))
        }
    }

}

protocol BluetoothScannerDelegate: AnyObject {
    func deviceFound(device: CBPeripheral)
}

private let supportedOmiPeripheralNames: Set<String> = [
    "Friend",
    "Friend DevKit 2",
    "Omi",
    "Omi DevKit 2",
]

func shouldRunOmiScan(scanRequested: Bool, bluetoothPoweredOn: Bool) -> Bool {
    scanRequested && bluetoothPoweredOn
}

func isSupportedOmiPeripheralName(_ name: String?) -> Bool {
    guard let name else { return false }
    return supportedOmiPeripheralNames.contains(name)
}

func isSupportedOmiPeripheral(
    peripheralName: String?,
    advertisedName: String?
) -> Bool {
    isSupportedOmiPeripheralName(peripheralName)
        || isSupportedOmiPeripheralName(advertisedName)
}

class BluetoothScanner: NSObject, CBCentralManagerDelegate {
    weak var delegate: BluetoothScannerDelegate?
    var centralManager: CBCentralManager!
    private var scanRequested = false
    
    override init() {
        super.init()
        // Initialize CBCentralManager with self as the delegate
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScan() {
        scanRequested = true
        print("[Omi] scanner request registered")
        updateScanState()
    }

    func stopScan() {
        scanRequested = false
        print("[Omi] scanner stopped")
        centralManager.stopScan()
    }

    private func updateScanState() {
        guard shouldRunOmiScan(
            scanRequested: scanRequested,
            bluetoothPoweredOn: centralManager.state == .poweredOn
        ) else { return }
        print("[Omi] BLE scan started")
        centralManager.stopScan()
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    // This is called when the central manager's state is updated (e.g., Bluetooth is turned on/off)
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("[Omi] Bluetooth powered on")
            updateScanState()
        case .poweredOff:
            print("Bluetooth is off.")
        case .resetting, .unauthorized, .unknown, .unsupported:
            print("Bluetooth not available.")
        @unknown default:
            print("Unknown state.")
        }
    }

    // This is called when a new peripheral (device) is discovered during scanning
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        if isSupportedOmiPeripheral(
            peripheralName: peripheral.name,
            advertisedName: advertisedName
        ), scanRequested {
            print("[Omi] requested scan matched supported device")
            scanRequested = false
            centralManager.stopScan()
            self.delegate?.deviceFound(device: peripheral)
        }
    }
}
