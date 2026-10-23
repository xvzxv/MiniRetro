// Hints.swift — 统一的说明文字与内置资源清单（v1.10）
//
// 目的：设置项、危险操作、需要额外文件的流程，都在原地给一句话解释，
// 而不是让用户去翻 README 或者靠猜。
import SwiftUI

/// 设置页/表单里的补充说明（小号灰字，紧跟在对应控件或分组下方）
struct HintText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 带图标的提示块：用于「必须知道」的信息（缺文件、版权说明等）
struct NoticeRow: View {
    enum Kind {
        case info, warning, success

        var symbol: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .success: return "checkmark.circle"
            }
        }

        var color: Color {
            switch self {
            case .info: return .accentColor
            case .warning: return .orange
            case .success: return .green
            }
        }
    }

    let kind: Kind
    let title: String
    let detail: String?

    init(kind: Kind, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: kind.symbol)
                .foregroundStyle(kind.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// 内置 / 未内置资源清单（设置页「关于」与首次导入提示复用同一份文案）
enum BuiltInResources {
    struct Item: Identifiable {
        let name: String
        let detail: String
        let isIncluded: Bool
        var id: String { name }
    }

    /// 四个内核全部随 App 一起打包，不需要用户额外下载
    static let cores: [Item] = [
        Item(name: "fceumm", detail: "FC / NES / FDS", isIncluded: true),
        Item(name: "SameBoy 1.0.4", detail: "GB / GBC", isIncluded: true),
        Item(name: "mGBA 0.10.5", detail: "GBA", isIncluded: true),
        Item(name: "FBNeo", detail: "街机 CPS1/CPS2/Neo Geo/PGM", isIncluded: true),
    ]

    /// BIOS 属于厂商版权内容，不随 App 分发
    static let biosNotice = """
    BIOS（neogeo.zip / pgm.zip）是街机厂商的版权数据，App 不内置、也不会内置。
    它们通常就在你下载的 MAME/FBNeo romset 压缩包里；拿到后用游戏库右上角「+」导入，
    App 会自动装到 System 目录。缺少时游戏会显示内核自带的缺失清单。
    """

    static let romNotice = """
    本 App 不含任何游戏 ROM。请使用你自己合法拥有的卡带/主板备份，或 homebrew 作品。
    """
}
