import AppKit
import HaluMeCore
import SwiftUI
import UniformTypeIdentifiers

extension BudgetStore {
    /// Saves any image as a centred square JPEG (up to 800 px) and returns its file name.
    func storePhoto(from source: URL, for wish: UUID) -> String? {
        guard let image = NSImage(contentsOf: source), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = min(cg.width, cg.height)
        let crop = CGRect(x: (cg.width - side) / 2, y: (cg.height - side) / 2, width: side, height: side)
        guard let square = cg.cropping(to: crop) else { return nil }
        let size = min(side, 800)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSGraphicsContext.current?.cgContext.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return nil }
        let name = "\(wish.uuidString)-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try FileManager.default.createDirectory(at: imagesFolder, withIntermediateDirectories: true)
            try data.write(to: imagesFolder.appending(path: name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    func photo(named name: String?) -> NSImage? {
        name.flatMap { NSImage(contentsOf: imagesFolder.appending(path: $0)) }
    }
}

/// A square photo, or a soft placeholder.
struct WishImage: View {
    @Environment(BudgetStore.self) private var store
    let name: String?
    var size: CGFloat? = nil

    var body: some View {
        Group {
            if let image = store.photo(named: name) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Palette.orange.opacity(0.1))
                    Image(systemName: "gift").font(.system(size: 28, weight: .light)).foregroundStyle(Palette.orange)
                }
            }
        }
        .frame(width: size, height: size)
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Pick or drop a photo for a wish.
struct WishPhotoField: View {
    @Environment(BudgetStore.self) private var store
    @Binding var wish: Wish
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 14) {
            WishImage(name: wish.photo, size: 84)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.orange, lineWidth: targeted ? 2 : 0))
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    _ = providers.first?.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in if let name = store.storePhoto(from: url, for: wish.id) { wish.photo = name } }
                    }
                    return true
                }
            VStack(alignment: .leading, spacing: 6) {
                Button("Choose Photo…") { choose() }.buttonStyle(SecondaryButtonStyle())
                if wish.photo != nil {
                    Button("Remove Photo") { wish.photo = nil }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                Text("Or drop a picture here. It's cropped to a square.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let name = store.storePhoto(from: url, for: wish.id) else { return }
        wish.photo = name
    }
}

/// "Save for it": by when, and what that takes from each payday.
struct SaveForWishSheet: View {
    @Environment(BudgetStore.self) private var store
    let wishID: UUID
    @State private var by = Calendar.current.date(byAdding: .month, value: 6, to: Date())!

    var body: some View {
        let budget = store.budget!
        let wish = budget.wishes.first { $0.id == wishID }!
        let price = budget.convert(wish.price, from: wish.currency)
        let count = store.me.flatMap { me in store.planner?.paydays(of: me, from: Date(), to: by).count } ?? 1
        SheetFrame(title: "Save for \(wish.name)", subtitle: "A goal with its price by the date you choose; part of each pay goes there.",
                   action: "Start Saving", canSave: by > Date(), save: { store.startSaving(for: wish, by: by) }) {
            Field("By") { DateField(date: $by, range: Date() ... .distantFuture) }.frame(width: 260, alignment: .leading)
            Label(String(localized: "About \((price / Decimal(max(count, 1))).rounded(.up).money(budget.currency)) from each of \(count) paydays"),
                  systemImage: "calendar")
                .font(.callout.weight(.medium))
        }
    }
}
