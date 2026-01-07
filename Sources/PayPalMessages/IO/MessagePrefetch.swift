import Foundation

public final class MessagePrefetch {

    static let shared = MessagePrefetch(
        requester: MessageRequest.shared,
        merchantProfileProvider: MerchantProfileProvider.shared)

    private let requester: MessageRequestable
    private let merchantProfileProvider: MerchantProfileHashGetable

    private init(
        requester: MessageRequestable,
        merchantProfileProvider: MerchantProfileHashGetable
    ) {
        self.requester = requester
        self.merchantProfileProvider = merchantProfileProvider
    }

    public func prefetch(
        configs: [PayPalMessageConfig],
        completion: @escaping () -> Void
    ) {
        guard !configs.isEmpty else {
            completion()
            return
        }

        let group = DispatchGroup()

        for config in configs {
            group.enter()

            merchantProfileProvider.getMerchantProfileHash(
                environment: config.data.environment,
                clientID: config.data.clientID,
                merchantID: config.data.merchantID
            ) { [weak self] hash in

                guard let self else {
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
                    ignoreCache: false,
                    instanceID: "prefetch"
                )

                self.requester.fetchMessage(parameters: params) { _ in
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            completion()
        }
    }
}
