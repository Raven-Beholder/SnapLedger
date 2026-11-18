import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    private static let appGroupIdentifier = "group.com.chenxuanchi.SnapLedger"
    private static let deepLink = URL(string: "snapledger://import-shared-images")!

    private let statusLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let doneButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        importSharedImages()
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        statusLabel.text = "正在接收图片…"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0

        activityIndicator.startAnimating()

        var configuration = UIButton.Configuration.filled()
        configuration.title = "完成"
        doneButton.configuration = configuration
        doneButton.isHidden = true
        doneButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [activityIndicator, statusLabel, doneButton])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            doneButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    private func importSharedImages() {
        let providers = extensionContext?.inputItems
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) } ?? []

        guard !providers.isEmpty else {
            showFailure("没有找到可导入的图片。")
            return
        }

        loadImages(from: providers, index: 0, collected: [])
    }

    private func loadImages(from providers: [NSItemProvider], index: Int, collected: [Data]) {
        guard index < providers.count else {
            saveAndOpenApp(collected)
            return
        }

        providers[index].loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            var updated = collected
            if let data {
                updated.append(data)
            }
            DispatchQueue.main.async {
                self?.loadImages(from: providers, index: index + 1, collected: updated)
            }
        }
    }

    private func saveAndOpenApp(_ images: [Data]) {
        guard !images.isEmpty else {
            showFailure("图片读取失败，请重试。")
            return
        }

        do {
            try save(images)
            statusLabel.text = "已发送到 SnapLedger，正在打开 App…"
            extensionContext?.open(Self.deepLink) { [weak self] opened in
                DispatchQueue.main.async {
                    if opened {
                        self?.extensionContext?.completeRequest(returningItems: nil)
                    } else {
                        self?.showReadyFallback()
                    }
                }
            }
        } catch {
            showFailure("无法保存图片，请重试。")
        }
    }

    private func save(_ images: [Data]) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let fileManager = FileManager.default
        let inboxURL = containerURL.appending(path: "SharedImportInbox", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: inboxURL, withIntermediateDirectories: true)

        let identifier = UUID().uuidString
        let stagingURL = inboxURL.appending(path: "staging-\(identifier)", directoryHint: .isDirectory)
        let batchURL = inboxURL.appending(path: "batch-\(identifier)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)

        do {
            for (index, image) in images.enumerated() {
                let fileURL = stagingURL.appending(path: String(format: "%03d.image", index))
                try image.write(to: fileURL, options: .atomic)
            }
            try fileManager.moveItem(at: stagingURL, to: batchURL)
        } catch {
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func showReadyFallback() {
        activityIndicator.stopAnimating()
        statusLabel.text = "图片已准备好。请打开 SnapLedger，解析会自动开始。"
        doneButton.isHidden = false
    }

    private func showFailure(_ message: String) {
        activityIndicator.stopAnimating()
        statusLabel.text = message
        doneButton.isHidden = false
    }

    @objc private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
