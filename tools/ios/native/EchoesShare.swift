// ECHOES on iPhone/iPad: opens the iOS share sheet for the score card.
// Godot has no share sheet on iOS, so the game writes Documents/share_request.txt (the share text)
// next to Documents/echoes_score.png, and this code, running inside the app, picks it up.
import UIKit

@_cdecl("echoes_share_boot")
public func echoes_share_boot() {
    DispatchQueue.main.async { EchoesShare.shared.start() }
}

final class EchoesShare: NSObject {
    static let shared = EchoesShare()
    private var timer: Timer?
    private var busy = false
    private let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    func start() {
        guard timer == nil else { return }
        // tells the game the share sheet is available
        try? "1".write(to: docs.appendingPathComponent(".share_ready"), atomically: true, encoding: .utf8)
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let req = docs.appendingPathComponent("share_request.txt")
        guard !busy, FileManager.default.fileExists(atPath: req.path) else { return }
        let text = (try? String(contentsOf: req, encoding: .utf8)) ?? ""
        try? FileManager.default.removeItem(at: req)
        var items: [Any] = []
        if let img = UIImage(contentsOfFile: docs.appendingPathComponent("echoes_score.png").path) { items.append(img) }
        if !text.isEmpty { items.append(text) }
        guard !items.isEmpty, let top = topController() else { NSLog("ECHOES share: nothing to show"); return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {   // iPad shows it as a popover
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        sheet.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.busy = false }
        busy = true
        top.present(sheet, animated: true) { NSLog("ECHOES share: sheet shown") }
    }

    private func topController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        var c = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let p = c?.presentedViewController { c = p }
        return c
    }
}
