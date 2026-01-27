import Foundation

public final class MessagePrefetch {

    private let requester: MessageRequestable
    private let profileProvider: MerchantProfileHashGetable
    private let perRequestTimeout: TimeInterval?

    internal init(
        requester: MessageRequestable,
        profileProvider: MerchantProfileHashGetable,
        perRequestTimeout: TimeInterval? = nil
    ) {
        self.requester = requester
        self.profileProvider = profileProvider
        self.perRequestTimeout = perRequestTimeout
    }

    public convenience init(perRequestTimeout: TimeInterval? = nil) {
        self.init(
            requester: MessageRequest(),
            profileProvider: MerchantProfileProvider(),
            perRequestTimeout: perRequestTimeout)
    }

    public func prefetch(
        configs: [PayPalMessageConfig],
        onCompletion: @escaping ([Result<PayPalMessageConfigData, Error>]) -> Void
    ) {
        guard !configs.isEmpty else {
            onCompletion([])
            return
        }

        // Pre-fill with defensive fallback.
        // Will be overwritten on success/failure per config.
        var results: [Result<PayPalMessageConfigData, Error>] = Array(
            repeating: .failure(PrefetchError.incomplete),
            count: configs.count)

        let group = DispatchGroup()

        configs.enumerated().forEach { index, config in
            group.enter()

            profileProvider.getMerchantProfileHash(
                environment: config.data.environment,
                clientID: config.data.clientID,
                merchantID: config.data.merchantID,
                timeout: perRequestTimeout,
                onCompletion: { [weak self] hash in

                    guard let self else {
                        results[index] = .failure(PrefetchError.deallocated)
                        group.leave()
                        return
                    }

                    let params = MessageRequestParameters(
                        environment: config.data.environment,
                        clientID: config.data.clientID,
                        merchantID: config.data.merchantID,
                        partnerAttributionID: config.data.partnerAttributionID,
                        logoType: config.style.logoType,
                        buyerCountry: config.data.buyerCountry,
                        pageType: config.data.pageType,
                        amount: config.data.amount,
                        offerType: config.data.offerType,
                        merchantProfileHash: hash,
                        ignoreCache: true,
                        instanceID: "prefetch"
                    )

                    self.requester.fetchMessage(
                        parameters: params,
                        timeout: perRequestTimeout,
                        onCompletion: { fetchResult in

                            // Preserve PayPalMessageError as Error
                            let mapped: Result<PayPalMessageConfigData, Error> = fetchResult
                                .map { PayPalMessageConfigData(response: $0) }
                                .mapError { $0 as Error }

                            results[index] = mapped
                            group.leave()
                        })
                })
        }

        group.notify(queue: .main) {
            onCompletion(results)
        }
    }
}

private extension MessagePrefetch {

    enum PrefetchError: Error {
        case deallocated
        case incomplete
    }
}

private extension PayPalMessageConfigData {

    convenience init(response: PayPalMessageResponse) {
        self.init(
            offerType: response.offerType,
            productGroup: response.productGroup,
            modalCloseButtonWidth: response.modalCloseButtonWidth,
            modalCloseButtonHeight: response.modalCloseButtonHeight,
            modalCloseButtonAvailWidth: response.modalCloseButtonAvailWidth,
            modalCloseButtonAvailHeight: response.modalCloseButtonAvailHeight,
            modalCloseButtonColor: response.modalCloseButtonColor,
            modalCloseButtonColorType: response.modalCloseButtonColorType,
            modalCloseButtonAlternativeText: response.modalCloseButtonAlternativeText,
            defaultMainContent: response.defaultMainContent,
            defaultMainAlternative: response.defaultMainAlternative,
            defaultDisclaimer: response.defaultDisclaimer,
            genericMainContent: response.genericMainContent,
            genericMainAlternative: response.genericMainAlternative,
            genericDisclaimer: response.genericDisclaimer,
            logoPlaceholder: response.logoPlaceholder)
    }
}
