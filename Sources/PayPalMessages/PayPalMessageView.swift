import UIKit
import SwiftUI

public final class PayPalMessageView: UIControl {

    // MARK: - Public delegates

    public weak var stateDelegate: PayPalMessageViewStateDelegate? {
        didSet { viewModel?.stateDelegate = stateDelegate }
    }

    public weak var eventDelegate: PayPalMessageViewEventDelegate? {
        didSet { viewModel?.eventDelegate = eventDelegate }
    }

    // MARK: - Private

    private var viewModel: PayPalMessageViewModel!

    // MARK: - Subviews

    private let containerView: UIView = {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        return view
    }()

    private let messageLabel: UILabel = {
        let view = UILabel(frame: .zero)
        view.backgroundColor = .clear
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.adjustsFontForContentSizeCategory = true
        view.numberOfLines = 0
        view.textColor = .clear
        return view
    }()

    // MARK: - Init

    public convenience init(
        config: PayPalMessageConfig,
        stateDelegate: PayPalMessageViewStateDelegate? = nil,
        eventDelegate: PayPalMessageViewEventDelegate? = nil
    ) {
        self.init(
            config: config,
            stateDelegate: stateDelegate,
            eventDelegate: eventDelegate,
            requester: MessageRequest.shared,
            merchantProfileProvider: MerchantProfileProvider.shared
        )
    }

    internal init(
        config: PayPalMessageConfig,
        stateDelegate: PayPalMessageViewStateDelegate? = nil,
        eventDelegate: PayPalMessageViewEventDelegate? = nil,
        requester: MessageRequestable,
        merchantProfileProvider: MerchantProfileHashGetable
    ) {
        super.init(frame: .zero)

        self.stateDelegate = stateDelegate
        self.eventDelegate = eventDelegate

        configViews()
        configTouchTarget()

        viewModel = PayPalMessageViewModel(
            config: config,
            requester: requester,
            merchantProfileProvider: merchantProfileProvider,
            stateDelegate: stateDelegate,
            eventDelegate: eventDelegate,
            delegate: self,
            messageView: self
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Config

    /// Applies a new config.
    public func setConfig(_ config: PayPalMessageConfig) {
        viewModel.applyConfig(config)
    }

    public func getConfig() -> PayPalMessageConfig {
        viewModel.config
    }

    // MARK: - Layout

    override public func awakeFromNib() {
        super.awakeFromNib()
        refreshContent(messageParameters: viewModel.messageParameters)
    }

    override public var intrinsicContentSize: CGSize {
        messageLabel.intrinsicContentSize
    }

    override public func sizeThatFits(_ size: CGSize) -> CGSize {
        messageLabel.sizeThatFits(size)
    }

    // MARK: - Highlight

    override public var isHighlighted: Bool {
        didSet { configHighlight() }
    }

    private func configHighlight() {
        UIView.animate(
            withDuration: Constants.highlightedAnimationDuration,
            delay: 0,
            options: isHighlighted ? .curveEaseOut : .curveEaseIn,
            animations: {
                self.alpha = self.isHighlighted ? Constants.highlightedAlpha : Constants.regularAlpha
            },
            completion: nil
        )
    }

    // MARK: - View setup

    private func configViews() {
        backgroundColor = .clear
        layer.masksToBounds = true

        containerView.addSubview(messageLabel)
        addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            messageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            messageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            messageLabel.topAnchor.constraint(equalTo: containerView.topAnchor),
            messageLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    private func configTouchTarget() {
        addTarget(self, action: #selector(onTapLearnMore), for: .touchUpInside)
    }

    // MARK: - Actions

    @objc private func onTapLearnMore() {
        viewModel.showModal()
    }
}

// MARK: - PayPalMessageViewModelDelegate

extension PayPalMessageView: PayPalMessageViewModelDelegate {

    func refreshContent(messageParameters: PayPalMessageViewParameters?) {
        messageLabel.attributedText = PayPalMessageAttributedStringBuilder().makeMessageString(messageParameters)

        // Force recalculation for layout
        invalidateIntrinsicContentSize()

        // Accessibility
        accessibilityLabel = messageParameters?.accessibilityLabel ?? ""
        accessibilityTraits = messageParameters?.accessibilityTraits ?? .none
        isAccessibilityElement = messageParameters?.isAccessibilityElement ?? false
    }
}

// MARK: - Trait changes

extension PayPalMessageView {

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        refreshContent(messageParameters: viewModel.messageParameters)
    }
}

// MARK: - Constants

extension PayPalMessageView {
    private enum Constants {
        static let highlightedAnimationDuration: CGFloat = 1.0
        static let highlightedAlpha: CGFloat = 0.75
        static let regularAlpha: CGFloat = 1.0
    }
}

// MARK: - SwiftUI

@available(iOS 13.0, *)
extension PayPalMessageView {

    public struct Representable: UIViewRepresentable {

        private let config: PayPalMessageConfig
        private let stateDelegate: PayPalMessageViewStateDelegate?
        private let eventDelegate: PayPalMessageViewEventDelegate?

        public init(
            config: PayPalMessageConfig,
            stateDelegate: PayPalMessageViewStateDelegate? = nil,
            eventDelegate: PayPalMessageViewEventDelegate? = nil
        ) {
            self.config = config
            self.stateDelegate = stateDelegate
            self.eventDelegate = eventDelegate
        }

        public func makeUIView(context: Context) -> PayPalMessageView {
            PayPalMessageView(config: config, stateDelegate: stateDelegate, eventDelegate: eventDelegate)
        }

        public func updateUIView(_ view: PayPalMessageView, context: Context) {
            view.stateDelegate = stateDelegate
            view.eventDelegate = eventDelegate
            _ = view.setConfig(config)
        }
    }
}

