import Foundation

public final class MessagePrefetch {

    public static let shared = MessagePrefetch(
        requester: MessageRequest.shared,
        merchantProfileProvider: MerchantProfileProvider.shared
    )

    private let requester: MessageRequestable
    private let merchantProfileProvider: MerchantProfileHashGetable

    private init(
        requester: MessageRequestable,
        merchantProfileProvider: MerchantProfileHashGetable
    ) {
        self.requester = requester
        self.merchantProfileProvider = merchantProfileProvider
    }

    /// Results are aligned by index with the input `configs`.
    /// `results.count == configs.count`
    public func prefetch(
        configs: [PayPalMessageConfig],
        completion: @escaping ([Result<Void, Error>]) -> Void
    ) {
        guard !configs.isEmpty else {
            completion([])
            return
        }

        // Index-aligned results
        var results = Array<Result<Void, Error>?>(repeating: nil, count: configs.count)
        let group = DispatchGroup()

        for (index, config) in configs.enumerated() {
            group.enter()

            merchantProfileProvider.getMerchantProfileHash(
                environment: config.data.environment,
                clientID: config.data.clientID,
                merchantID: config.data.merchantID
            ) { [weak self] hash in

                guard let self else {
                    DispatchQueue.main.async {
                        results[index] = .failure(PrefetchError.deallocated)
                        group.leave()
                    }
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

                self.requester.fetchMessage(parameters: params) { fetchResult in
                    // Preserve PayPalMessageError as Error
                    let mapped: Result<Void, Error> = fetchResult
                        .map { _ in () }
                        .mapError { $0 as Error }

                    DispatchQueue.main.async {
                        results[index] = mapped
                        group.leave()
                    }
                }
            }
        }

        group.notify(queue: .main) {
            // Defensive fallback: any missing entry becomes an error
            let finalized = results.map { $0 ?? .failure(PrefetchError.incomplete) }
            completion(finalized)
        }
    }
}

private extension MessagePrefetch {
    enum PrefetchError: Error {
        case deallocated
        case incomplete
    }
}
