// SPDX-License-Identifier: MIT
import Accelerate
import Foundation

/// Mono PCM to 18 logarithmic bands. Silence returns zeros; no audio is retained.
public enum AudioSpectrum {
  public static func bands(_ samples: [Float], sampleRate: Double) -> [Float] {
    let n = 1024
    guard samples.count >= n, sampleRate > 0 else { return [Float](repeating: 0, count: 18) }
    let input = Array(samples.suffix(n))
    let rms = sqrt(input.reduce(Float(0)) { $0 + $1*$1 } / Float(n))
    guard rms > 0.001 else { return [Float](repeating: 0, count: 18) }
    guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(n), .FORWARD) else { return [Float](repeating: 0, count: 18) }
    defer { vDSP_DFT_DestroySetup(setup) }
    var window = [Float](repeating: 0, count: n)
    vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
    var real = zip(input, window).map(*)
    var imag = [Float](repeating: 0, count: n)
    var outR = imag, outI = imag
    vDSP_DFT_Execute(setup, &real, &imag, &outR, &outI)
    var bands: [Float] = []
    for band in 0..<18 {
      let low = 60 * pow(16000.0/60, Double(band)/18)
      let high = 60 * pow(16000.0/60, Double(band+1)/18)
      let start = max(1, min(n/2-1, Int(low * Double(n)/sampleRate)))
      let end = max(start+1, min(n/2, Int(high * Double(n)/sampleRate)))
      var magnitude: Float = 0
      for index in start..<end {
        let power = outR[index]*outR[index] + outI[index]*outI[index]
        magnitude = max(magnitude, sqrt(power) / Float(n))
      }
      let decibels: Float = 20 * log10(max(magnitude, 0.00001))
      bands.append(min(1, max(0, (decibels + 65)/55)))
    }
    return bands
  }
}
