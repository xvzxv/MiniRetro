// CrossImage.swift — 跨平台图片类型（iOS: UIImage / macOS: NSImage）
// 目的：App 层主体代码可在 macOS target 下做类型检查验证（iOS 专属 API 一律条件编译）
#if canImport(UIKit)
import UIKit
public typealias CrossImage = UIImage
#else
import AppKit
public typealias CrossImage = NSImage
#endif

import SwiftUI

extension Image {
    init(crossImage: CrossImage) {
        #if canImport(UIKit)
        self.init(uiImage: crossImage)
        #else
        self.init(nsImage: crossImage)
        #endif
    }

    init(crossImage: CrossImage?, placeholder: String) {
        if let crossImage {
            self.init(crossImage: crossImage)
        } else {
            self.init(systemName: placeholder)
        }
    }
}

extension CrossImage {
    /// 跨平台 PNG 编码（iOS: pngData / macOS: NSBitmapImageRep）
    func pngDataCompat() -> Data? {
        #if canImport(UIKit)
        return pngData()
        #else
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}

extension CrossImage {
    /// 跨平台 CGImage 构造
    static func fromCGImage(_ cgImage: CGImage) -> CrossImage {
        #if canImport(UIKit)
        return UIImage(cgImage: cgImage)
        #else
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #endif
    }
}
