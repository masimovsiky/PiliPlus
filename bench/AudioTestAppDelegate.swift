import AVFoundation
import Flutter
import MediaPlayer
import UIKit

// Minimal background-audio host used to test one system behaviour:
// can iOS open THIS app by tapping the Now Playing entry (lock screen artwork /
// Dynamic Island) when the app is a sideloaded, background-audio player?
//
// It deliberately mirrors PiliPlus's iOS setup (FlutterAppDelegate with an
// implicit engine) and publishes Now Playing info the same way audio_service
// does, without any PiliPlus code.

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var player: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    startAudio()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func startAudio() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default)
    try? session.setActive(true)

    let url = FileManager.default
      .urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("tone.wav")
    if !FileManager.default.fileExists(atPath: url.path) {
      try? Self.makeToneData().write(to: url)
    }
    player = try? AVAudioPlayer(contentsOf: url)
    player?.numberOfLoops = -1
    player?.volume = 0.05
    player?.play()

    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      self?.player?.play()
      self?.publish()
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.player?.pause()
      self?.publish()
      return .success
    }
    publish()
  }

  private func publish() {
    let playing = player?.isPlaying ?? false
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: "Audio test",
      MPMediaItemPropertyArtist: "sideload diagnostics",
      MPMediaItemPropertyPlaybackDuration: player?.duration ?? 0,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? 0,
      MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
    ]
    MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
  }

  /// 30s mono 16-bit WAV: a quiet 440Hz tone so it is obvious that audio plays.
  private static func makeToneData() -> Data {
    let sampleRate = 44100
    let seconds = 30
    let frames = sampleRate * seconds
    let amplitude = Double(Int16.max) * 0.05
    let dataBytes = frames * 2

    var data = Data()
    func put(_ bytes: [UInt8]) { data.append(contentsOf: bytes) }
    func put32(_ v: UInt32) { put([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]) }
    func put16(_ v: UInt16) { put([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }

    put(Array("RIFF".utf8))
    put32(UInt32(36 + dataBytes))
    put(Array("WAVEfmt ".utf8))
    put32(16)
    put16(1)                       // PCM
    put16(1)                       // mono
    put32(UInt32(sampleRate))
    put32(UInt32(sampleRate * 2))  // byte rate
    put16(2)                       // block align
    put16(16)                      // bits per sample
    put(Array("data".utf8))
    put32(UInt32(dataBytes))

    for i in 0..<frames {
      let phase = 2.0 * Double.pi * 440.0 * Double(i) / Double(sampleRate)
      let value = Int16(amplitude * sin(phase))
      put16(UInt16(bitPattern: value))
    }
    return data
  }
}
