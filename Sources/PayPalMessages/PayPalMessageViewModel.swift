import UIKit

protocol PayPalMessageViewModelDelegate: AnyObject {
    func refreshContent(messageParameters: PayPalMessageViewParameters?)
}

final class PayPalMessageViewModel: PayPalMessageModalEventDelegate {

    weak var delegate: PayPalMessageViewModelDelegate?
    weak var stateDelegate: PayPalMessageViewStateDelegate?
    weak var eventDelegate: PayPalMessageViewEventDelegate?
    weak var messageView: PayPalMessageView?

    private var source: PayPalMessageSource
    private var fetchedResponse: PayPalMessageResponse?

    private var messageResponse: PayPalMessageResponse? {
        switch source {
        case .config:
            return fetchedResponse

        case let .data(data, _):
            return PayPalMessageResponse(
                offerType: data.offerType,
                productGroup: data.productGroup,
                defaultMainContent: data.defaultMainContent,
                defaultMainAlternative: data.defaultMainAlternative,
                defaultDisclaimer: data.defaultDisclaimer,
                genericMainContent: data.genericMainContent,
                genericMainAlternative: data.genericMainAlternative,
                genericDisclaimer: data.genericDisclaimer,
                logoPlaceholder: data.logoPlaceholder,
                modalCloseButtonWidth: data.modalCloseButtonWidth,
                modalCloseButtonHeight: data.modalCloseButtonHeight,
                modalCloseButtonAvailWidth: data.modalCloseButtonAvailWidth,
                modalCloseButtonAvailHeight: data.modalCloseButtonAvailHeight,
                modalCloseButtonColor: data.modalCloseButtonColor,
                modalCloseButtonColorType: data.modalCloseButtonColorType,
                modalCloseButtonAlternativeText: data.modalCloseButtonAlternativeText)

        default:
            return nil
        }
    }

    private var config: PayPalMessageConfig {
        switch source {
        case let .config(config):
            return config

        case let .data(_, config):
            return config
        }
    }

    private var merchantProfileHash: String?
    private var isMessageViewInteractive = false
    private var modal: PayPalMessageModal?
    private var renderStart: Date?

    private let requester: MessageRequestable
    private let merchantProfileProvider: MerchantProfileHashGetable
    private let parameterBuilder = PayPalMessageViewParametersBuilder()
    private let logger: AnalyticsLogger

    var messageParameters: PayPalMessageViewParameters? {

        switch (source, fetchedResponse) {
        case let (.config(config), .some(response)):
            return parameterBuilder.makeParameters(
                message: response.defaultMainContent,
                messageAlternative: response.defaultMainAlternative,
                offerType: response.offerType,
                linkDescription: response.defaultDisclaimer,
                logoPlaceholder: response.logoPlaceholder,
                logoType: config.style.logoType,
                payPalAlign: config.style.textAlign,
                payPalColor: config.style.color,
                productGroup: response.productGroup)

        case let (.data(data, config), _):
            return parameterBuilder.makeParameters(
                message: data.defaultMainContent,
                messageAlternative: data.defaultMainAlternative,
                offerType: data.offerType,
                linkDescription: data.defaultDisclaimer,
                logoPlaceholder: data.logoPlaceholder,
                logoType: config.style.logoType,
                payPalAlign: config.style.textAlign,
                payPalColor: config.style.color,
                productGroup: data.productGroup)

        default:
            return nil
        }
    }

    // MARK: - Init

    init(
        source: PayPalMessageSource,
        requester: MessageRequestable,
        merchantProfileProvider: MerchantProfileHashGetable,
        stateDelegate: PayPalMessageViewStateDelegate? = nil,
        eventDelegate: PayPalMessageViewEventDelegate? = nil,
        delegate: PayPalMessageViewModelDelegate? = nil,
        messageView: PayPalMessageView
    ) {
        self.source = source
        self.requester = requester
        self.merchantProfileProvider = merchantProfileProvider
        self.stateDelegate = stateDelegate
        self.eventDelegate = eventDelegate
        self.delegate = delegate
        self.messageView = messageView
        self.logger = AnalyticsLogger(.message(Weak(messageView)))

        applySource(source, force: true)
    }

    // MARK: - Public API

    func applyConfig(_ config: PayPalMessageConfig) {
        applySource(.config(config))
    }

    func applyData(
        _ data: PayPalMessageConfigData,
        config: PayPalMessageConfig
    ) {
        applySource(.data(data, config: config))
    }

    func applySource(_ newSource: PayPalMessageSource, force: Bool = false) {

        let oldSourceKey = ApplySourceKey(source)
        let newSourceKey = ApplySourceKey(newSource)

        guard newSourceKey != oldSourceKey || force else {
            return
        }

        source = newSource

        switch source {
        case .config:
            fetchMessageContent()

        case .data:
            delegate?.refreshContent(messageParameters: messageParameters)

            isMessageViewInteractive = true

            if let modal {
                // `merchantProfileHash` is expected to be nil when the source is `.response`.
                // This is safe for now because the model currently doesn't use `merchantProfileHash`.
                modal.merchantProfileHash = nil
                modal.setConfig(makeModalConfig())
            }
        }
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

    func getConfig() -> PayPalMessageConfig {
        switch source {
        case let .config(config):
            return config
        case let .data(_, config):
            return config
        }
    }

    // MARK: - Fetch

    private func fetchMessageContent() {
        guard case let .config(config) = source else {
            return
        }

        renderStart = Date()

        let keySnapshot = ApplySourceKey(source)

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
                    keySnapshot == ApplySourceKey(self.source) // check if makes sense to continue
                else { return }

                self.merchantProfileHash = hash
                let params = self.makeRequestParameters(merchantProfileHash: hash)

                requester.fetchMessage(parameters: params) { [weak self] result in
                    guard
                        let self,
                        keySnapshot == ApplySourceKey(self.source)
                    else { return }

                    switch result {
                    case let .success(response):
                        self.onMessageRequestReceived(response: response)

                    case let .failure(error):
                        self.onMessageRequestFailed(error: error)
                    }
                }
            })
    }

    // MARK: - Response handling

    private func onMessageRequestFailed(error: PayPalMessageError) {
        fetchedResponse = nil

        logger.addEvent(.messageError(
            errorName: error.issue ?? "\(error)",
            errorDescription: error.description ?? ""
        ))

        isMessageViewInteractive = false
        delegate?.refreshContent(messageParameters: messageParameters)

        if let stateDelegate, let messageView {
            stateDelegate.onError(messageView, error: error)
        }
    }

    private func onMessageRequestReceived(response: PayPalMessageResponse) {
        fetchedResponse = response
        logger.dynamicData = response.trackingData

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

        if let stateDelegate, let messageView {
            stateDelegate.onSuccess(messageView)
        }

        if case let .config(config) = source {
            log(
                .debug,
                "onMessageRequestReceived: \(String(describing: response.defaultMainContent))",
                for: config.data.environment)
        }
    }

    // MARK: - Build request parameters

    private func makeRequestParameters(
        merchantProfileHash: String?
    ) -> MessageRequestParameters {

        switch source {
        case let .config(config):
            return MessageRequestParameters(
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
                instanceID: logger.instanceId)

        case let .data(_, config):
            return MessageRequestParameters(
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
                instanceID: logger.instanceId)
        }
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
}

// MARK: -

fileprivate struct ApplySourceKey: Equatable {
    var config_clientID: String
    var config_merchantID: String?
    var config_partnerAttributionID: String?
    var config_environment: Environment
    var config_amount: String?
    var config_pageType: PayPalMessagePageType?
    var config_offerType: PayPalMessageOfferType?
    var config_buyerCountry: String?
    var config_channel: String

    var config_logoType: PayPalMessageLogoType?
    var config_color: PayPalMessageColor?
    var config_textAlign: PayPalMessageTextAlign?

    var response_offerType: PayPalMessageResponseOfferType? = nil
    var response_productGroup: PayPalMessageResponseProductGroup? = nil

    var response_modalCloseButtonWidth: Int? = nil
    var response_modalCloseButtonHeight: Int? = nil
    var response_modalCloseButtonAvailWidth: Int? = nil
    var response_modalCloseButtonAvailHeight: Int? = nil
    var response_modalCloseButtonColor: String? = nil
    var response_modalCloseButtonColorType: String? = nil
    var response_modalCloseButtonAlternativeText: String? = nil

    var response_defaultMainContent: String? = nil
    var response_defaultMainAlternative: String? = nil
    var response_defaultDisclaimer: String? = nil

    var response_genericMainContent: String?
    var response_genericMainAlternative: String? = nil
    var response_genericDisclaimer: String? = nil

    var response_logoPlaceholder: String? = nil

    init(_ source: PayPalMessageSource) {

        switch source {
        case let .config(config):
            config_clientID = config.data.clientID
            config_merchantID = config.data.merchantID
            config_partnerAttributionID = config.data.partnerAttributionID
            config_environment = config.data.environment
            config_amount = config.data.amount
            config_pageType = config.data.pageType
            config_offerType = config.data.offerType
            config_buyerCountry = config.data.buyerCountry
            config_channel = config.data.channel

            config_logoType = config.style.logoType
            config_color = config.style.color
            config_textAlign = config.style.textAlign

        case let .data(data, config):
            config_clientID = config.data.clientID
            config_merchantID = config.data.merchantID
            config_partnerAttributionID = config.data.partnerAttributionID
            config_environment = config.data.environment
            config_amount = config.data.amount
            config_pageType = config.data.pageType
            config_offerType = config.data.offerType
            config_buyerCountry = config.data.buyerCountry
            config_channel = config.data.channel

            config_logoType = config.style.logoType
            config_color = config.style.color
            config_textAlign = config.style.textAlign

            response_offerType = data.offerType
            response_productGroup = data.productGroup

            response_modalCloseButtonWidth = data.modalCloseButtonWidth
            response_modalCloseButtonHeight = data.modalCloseButtonHeight
            response_modalCloseButtonAvailWidth = data.modalCloseButtonAvailWidth
            response_modalCloseButtonAvailHeight = data.modalCloseButtonAvailHeight
            response_modalCloseButtonColor = data.modalCloseButtonColor
            response_modalCloseButtonColorType = data.modalCloseButtonColorType
            response_modalCloseButtonAlternativeText = data.modalCloseButtonAlternativeText

            response_defaultMainContent = data.defaultMainContent
            response_defaultMainAlternative = data.defaultMainAlternative
            response_defaultDisclaimer = data.defaultDisclaimer

            response_genericMainContent = data.genericMainContent
            response_genericMainAlternative = data.genericMainAlternative
            response_genericDisclaimer = data.genericDisclaimer

            response_logoPlaceholder = data.logoPlaceholder
        }
    }
}
