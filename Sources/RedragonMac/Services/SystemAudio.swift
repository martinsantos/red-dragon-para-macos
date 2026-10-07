// SPDX-License-Identifier: MIT
import AVFoundation
import Combine
import ScreenCaptureKit
import RedragonCore

/// Only an audio output is registered: no screen/video output, recording, or microphone.
@MainActor
final class SystemAudio: ObservableObject {
  @Published private(set) var connected = false
  @Published private(set) var starting = false
  @Published private(set) var bands = [Float](repeating: 0, count: 18)
  @Published private(set) var message = "Conectá el audio del sistema para reaccionar a la música."
  private var stream: SCStream?
  private var output: AudioOutput?
  private var generation = 0
  func start() async {
    guard !connected, !starting else { return }
    starting = true; generation += 1; let revision = generation
    defer { starting = false }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
      guard let display = content.displays.first else { throw S136Error.message("No hay una pantalla disponible para el audio del sistema.") }
      let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
      let config = SCStreamConfiguration()
      config.width = 2; config.height = 2; config.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 1)
      config.capturesAudio = true; config.sampleRate = 48000; config.channelCount = 2
      config.excludesCurrentProcessAudio = true
      if #available(macOS 15, *) { config.captureMicrophone = false }
      let output = AudioOutput { [weak self] values in
        Task { @MainActor in
          guard let self, self.generation == revision else { return }
          self.bands = values
          self.message = values.contains(where: { $0 > 0 }) ? "Audio del sistema detectado" : "En silencio · esperando música"
        }
      } stopped: { [weak self] error in
        Task { @MainActor in
          guard let self, self.generation == revision else { return }
          self.connected = false; self.bands = [Float](repeating: 0, count: 18)
          self.message = "Audio detenido: \(error)"
        }
      }
      let stream = SCStream(filter: filter, configuration: config, delegate: output)
      try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: DispatchQueue(label: "redragon.audio.levels"))
      self.output = output; self.stream = stream
      try await stream.startCapture()
      guard revision == generation else { try? await stream.stopCapture(); return }
      connected = true; message = "Audio conectado · esperando música"
    } catch {
      message = "No se pudo conectar el audio: \(error.localizedDescription). Revisá Grabación de pantalla y audio del sistema."
      stream = nil; output = nil
    }
  }
  func stop() async {
    generation += 1
    let previous = stream; stream = nil; output = nil
    connected = false; bands = [Float](repeating: 0, count: 18)
    try? await previous?.stopCapture()
    message = "Audio desconectado."
  }
}

private final class AudioOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
  let received: @Sendable ([Float]) -> Void
  let stopped: @Sendable (String) -> Void
  private var samples: [Float] = []
  private var lastUpdate = Date.distantPast
  init(received: @escaping @Sendable ([Float]) -> Void, stopped: @escaping @Sendable (String) -> Void) {
    self.received = received; self.stopped = stopped
  }
  func stream(_ stream: SCStream, didStopWithError error: Error) { stopped(error.localizedDescription) }
  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer),
      let format = CMSampleBufferGetFormatDescription(sampleBuffer),
      let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
      description.mFormatID == kAudioFormatLinearPCM, description.mBitsPerChannel == 32,
      description.mFormatFlags & kAudioFormatFlagIsFloat != 0 else { return }
    var needed = 0
    var block: CMBlockBuffer?
    CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &needed,
      bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
      flags: 0, blockBufferOut: &block)
    guard needed > 0, needed <= 4096 else { return }
    let memory = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { memory.deallocate() }
    let list = memory.bindMemory(to: AudioBufferList.self, capacity: 1)
    guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil,
      bufferListOut: list, bufferListSize: needed, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
      flags: 0, blockBufferOut: &block) == noErr else { return }
    let buffers = UnsafeMutableAudioBufferListPointer(list)
    let frames = CMSampleBufferGetNumSamples(sampleBuffer)
    guard frames > 0, frames <= 65536 else { return }
    var mono = [Float](repeating: 0, count: frames)
    var channels = 0
    for buffer in buffers {
      guard let data = buffer.mData, buffer.mNumberChannels > 0 else { continue }
      let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
      let channelCount = Int(buffer.mNumberChannels)
      guard count >= frames * channelCount else { continue }
      let values = data.assumingMemoryBound(to: Float.self)
      for frame in 0..<frames { for channel in 0..<channelCount { mono[frame] += values[frame*channelCount+channel] } }
      channels += channelCount
    }
    guard channels > 0 else { return }
    samples += mono.map { $0 / Float(channels) }
    if samples.count > 2048 { samples.removeFirst(samples.count - 2048) }
    guard samples.count >= 1024, Date().timeIntervalSince(lastUpdate) >= 0.1 else { return }
    lastUpdate = Date()
    received(AudioSpectrum.bands(samples, sampleRate: description.mSampleRate))
    samples.removeAll(keepingCapacity: true)
  }
}
