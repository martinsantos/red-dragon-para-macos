// SPDX-License-Identifier: MIT
import Foundation

public struct Endpoint: Identifiable, Codable, Hashable, Sendable {
  public let registryID: UInt64
  public let productID: Int
  public let target: UInt8
  public let product: String
  public init(registryID: UInt64, productID: Int, target: UInt8, product: String) {
    self.registryID = registryID
    self.productID = productID
    self.target = target
    self.product = product
  }
  public var id: String { "\(registryID)-\(target)" }
  public var isKeyboard: Bool { target == 1 || (target == 0 && productID == 0x509d) }
  public var supportsLiveLighting: Bool { target == 0 && productID == 0x509d }
  public var title: String {
    if supportsLiveLighting { return "Teclado K628 · cable USB" }
    if target == 1 { return "Teclado · receptor 2,4 GHz" }
    if target == 2 { return "Mouse · receptor 2,4 GHz" }
    return "\(product) · USB"
  }
}
