import UIKit

protocol PayPalMessageViewModelDelegate: AnyObject {
    /// Requests the delegate to perform a content refresh.
    func refreshContent(messageParameters: PayPalMessageViewParameters?)
}

/// Simplified ViewModel:
/// - One stored config
/// - No proxy properties, no debounce timer
/// - Style-only changes refresh UI without refetch (if we already have a response)
/// - Data changes refetch (cache + dedup should live in MessageRequest.shared)
final class PayPalMessageViewModel: PayPalMessageModalEventDelegate {

    // MARK: - External hooks

    weak var delegate: PayPalMessageViewModelDelegate?
    weak var stateDelegate: PayPalMessageViewStateDelegate?
    weak var eventDelegate: PayPalMessageViewEventDelegate?
    weak var messageView: PayPalMessageView?

    // MARK: - State

    private(set) var config: PayPalMessageConfig
    private var messageResponse: MessageResponse?
    private var merchantProfileHash: String?
    private var isMessageViewInteractive = false
    private var modal: PayPalMessageModal?
    private var renderStart: Date?

    // Keys to decide whether we need fetch vs UI-only refresh
    private var lastFetchKey: FetchKey
    private var lastStyleKey: StyleKey

    // MARK: - Dependencies

    private let requester: MessageRequestable
    private let merchantProfileProvider: MerchantProfileHashGetable
    private let parameterBuilder = PayPalMessageViewParametersBuilder()
    private let logger: AnalyticsLogger

    // MARK: - Derived

    var messageParameters: PayPalMessageViewParameters? {
        guard let response = messageResponse else { return nil }

        return parameterBuilder.makeParameters(
            message: response.defaultMainContent,
            messageAlternative: response.defaultMainAlternative,
            offerType: response.offerType,
            linkDescription: response.defaultDisclaimer,
            logoPlaceholder: response.logoPlaceholder,
            logoType: config.style.logoType,
            payPalAlign: config.style.textAlign,
            payPalColor: config.style.color,
            productGroup: response.productGroup
        )
    }

    // MARK: - Init

    init(
        config: PayPalMessageConfig,
        requester: MessageRequestable,
        merchantProfileProvider: MerchantProfileHashGetable,
        stateDelegate: PayPalMessageViewStateDelegate? = nil,
        eventDelegate: PayPalMessageViewEventDelegate? = nil,
        delegate: PayPalMessageViewModelDelegate? = nil,
        messageView: PayPalMessageView
    ) {
        self.config = config
        self.requester = requester
        self.merchantProfileProvider = merchantProfileProvider
        self.stateDelegate = stateDelegate
        self.eventDelegate = eventDelegate
        self.delegate = delegate
        self.messageView = messageView

        self.logger = AnalyticsLogger(.message(Weak(messageView)))

        self.lastFetchKey = FetchKey(config: config)
        self.lastStyleKey = StyleKey(config: config)

        // Initial load.
        applyConfig(config)
    }

    // MARK: - Public API

    /// Apply a new config.
    func applyConfig(_ newConfig: PayPalMessageConfig) {

        let oldFetchKey = lastFetchKey
        let oldStyleKey = lastStyleKey

        let newFetchKey = FetchKey(config: newConfig)
        let newStyleKey = StyleKey(config: newConfig)

        let fetchChanged = (newFetchKey != oldFetchKey)
        let styleChanged = (newStyleKey != oldStyleKey)

        // Store new config + keys
        config = newConfig
        lastFetchKey = newFetchKey
        lastStyleKey = newStyleKey

        // If identity changed (env/client/merchant), previous hash becomes invalid.
        if newFetchKey.identityChanged(vs: oldFetchKey) {
            merchantProfileHash = nil
        }

        // If nothing changed and not forced -> already satisfied (sync).
        if !fetchChanged, !styleChanged {
            return
        }

        // Style-only update: if we already have a response, we can refresh UI without fetching.
        if !fetchChanged, styleChanged, messageResponse != nil {
            delegate?.refreshContent(messageParameters: self.messageParameters)
            return
        }

        // Start fetching
        fetchMessageContent()
    }

    func showModal() {
        guard isMessageViewInteractive else { return }

        if let eventDelegate, let messageView {
            eventDelegate.onClick(messageView)
        }

        logger.addEvent(.messageClick(
            linkName: messageResponse?.defaultDisclaimer ?? "Learn more",
            linkSrc: "learn_more"
        ))

        if modal == nil {
            modal = PayPalMessageModal(config: makeModalConfig(), eventDelegate: self)
        }

        if let modal {
            modal.merchantProfileHash = merchantProfileHash
            modal.show()
        }
    }

    // MARK: - Fetch

    private func fetchMessageContent() {
        renderStart = Date()

        let fetchKeySnapshot = lastFetchKey

        if let stateDelegate, let messageView {
            stateDelegate.onLoading(messageView)
        }

        merchantProfileProvider.getMerchantProfileHash(
            environment: config.data.environment,
            clientID: config.data.clientID,
            merchantID: config.data.merchantID,
            onCompletion: { [weak self] hash in
                guard
                    let self,
                    self.lastFetchKey == fetchKeySnapshot
                else { return }

                self.merchantProfileHash = hash

                let params = self.makeRequestParameters(merchantProfileHash: hash)

                requester.fetchMessage(parameters: params) { result in

                    switch result {
                    case .success(let response):
                        self.onMessageRequestReceived(response: response)
                    case .failure(let error):
                        self.onMessageRequestFailed(error: error)
                    }
                }
            })
    }

    // MARK: - Response handling

    private func onMessageRequestFailed(error: PayPalMessageError) {
        messageResponse = nil

        logger.addEvent(.messageError(
            errorName: error.issue ?? "\(error)",
            errorDescription: error.description ?? ""
        ))

        if let stateDelegate, let messageView {
            stateDelegate.onError(messageView, error: error)
        }

        isMessageViewInteractive = false
        delegate?.refreshContent(messageParameters: messageParameters)
    }

    private func onMessageRequestReceived(response: MessageResponse) {
        messageResponse = response
        logger.dynamicData = response.trackingData

        if let stateDelegate, let messageView {
            stateDelegate.onSuccess(messageView)
        }

        delegate?.refreshContent(messageParameters: messageParameters)

        logger.addEvent(.messageRender(
            renderDuration: Int((renderStart?.timeIntervalSinceNow ?? 1 / 1000) * -1000),
            requestDuration: Int((messageResponse?.requestDuration ?? 1 / 1000) * -1000)
        ))

        isMessageViewInteractive = true

        if let modal {
            modal.merchantProfileHash = merchantProfileHash
            modal.setConfig(makeModalConfig())
        }

        log(.debug, "onMessageRequestReceived: \(String(describing: response.defaultMainContent))", for: config.data.environment)
    }

    // MARK: - Build request parameters

    private func makeRequestParameters(merchantProfileHash: String?) -> MessageRequestParameters {
        .init(
            environment: config.data.environment,
            clientID: config.data.clientID,
            merchantID: config.data.merchantID,
            partnerAttributionID: config.data.partnerAttributionID,
            logoType: config.style.logoType,
            buyerCountry: config.data.buyerCountry,
            pageType: config.data.pageType,
            amount: config.data.amount,
            offerType: config.data.offerType,
            merchantProfileHash: merchantProfileHash,
            ignoreCache: config.data.ignoreCache,
            instanceID: logger.instanceId
        )
    }

    // MARK: - Modal config

    private func makeModalConfig() -> PayPalMessageModalConfig {
        let offerType = PayPalMessageOfferType(rawValue: messageResponse?.offerType.rawValue ?? "")

        var uiColor: UIColor?
        if let colorString = messageResponse?.modalCloseButtonColor {
            uiColor = UIColor(hexString: colorString)
        }

        let modalCloseButton = ModalCloseButtonConfig(
            width: messageResponse?.modalCloseButtonWidth,
            height: messageResponse?.modalCloseButtonHeight,
            availableWidth: messageResponse?.modalCloseButtonAvailWidth,
            availableHeight: messageResponse?.modalCloseButtonAvailHeight,
            color: uiColor,
            colorType: messageResponse?.modalCloseButtonColorType,
            alternativeText: messageResponse?.modalCloseButtonAlternativeText
        )

        let amount: Double? = {
            if let amount = config.data.amount {
                return Double(amount)
            } else {
                return nil
            }
        }()

        let modalConfig = PayPalMessageModalConfig(
            data: .init(
                clientID: config.data.clientID,
                environment: config.data.environment,
                amount: amount,
                pageType: config.data.pageType,
                offerType: offerType,
                modalCloseButton: modalCloseButton
            )
        )

        modalConfig.data.merchantID = config.data.merchantID
        modalConfig.data.partnerAttributionID = config.data.partnerAttributionID
        modalConfig.data.buyerCountry = config.data.buyerCountry
        modalConfig.data.modalCloseButton = modalCloseButton
        modalConfig.data.ignoreCache = config.data.ignoreCache

        return modalConfig
    }

    // MARK: - Modal event delegate

    func onClick(_ modal: PayPalMessageModal, data: PayPalMessageModalClickData) {
        if let eventDelegate, let messageView, data.linkName.contains("Apply Now") {
            eventDelegate.onApply(messageView)
        }
    }

    func onCalculate(_ modal: PayPalMessageModal, data: PayPalMessageModalCalculateData) {}
    func onShow(_ modal: PayPalMessageModal) {}
    func onClose(_ modal: PayPalMessageModal) {}

    // MARK: - Helpers

    private struct FetchKey: Equatable {
        let environment: Environment
        let clientID: String
        let merchantID: String?
        let partnerAttributionID: String?
        let amount: String?
        let pageType: PayPalMessagePageType?
        let offerType: PayPalMessageOfferType?
        let buyerCountry: String?
        let channel: String
        let logoType: PayPalMessageLogoType
        // Intentionally excluding ignoreCache for local cache semantics.

        init(config: PayPalMessageConfig) {
            environment = config.data.environment
            clientID = config.data.clientID
            merchantID = config.data.merchantID
            partnerAttributionID = config.data.partnerAttributionID
            amount = config.data.amount
            pageType = config.data.pageType
            offerType = config.data.offerType
            buyerCountry = config.data.buyerCountry
            channel = config.data.channel
            logoType = config.style.logoType
        }

        func identityChanged(vs other: FetchKey) -> Bool {
            environment != other.environment
                || clientID != other.clientID
                || merchantID != other.merchantID
        }
    }

    private struct StyleKey: Equatable {
        let color: PayPalMessageColor
        let textAlign: PayPalMessageTextAlign

        init(config: PayPalMessageConfig) {
            color = config.style.color
            textAlign = config.style.textAlign
        }
    }
}

