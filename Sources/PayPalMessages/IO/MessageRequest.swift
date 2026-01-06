import Foundation

typealias MessageRequestCompletion = (Result<MessageResponse, PayPalMessageError>) -> Void

struct MessageRequestParameters {
    let environment: Environment
    let clientID: String
    let merchantID: String?
    let partnerAttributionID: String?
    let logoType: PayPalMessageLogoType
    let buyerCountry: String?
    let pageType: PayPalMessagePageType?
    let amount: String?
    let offerType: PayPalMessageOfferType?
    let merchantProfileHash: String?
    let ignoreCache: Bool
    let instanceID: String
}

protocol MessageRequestable {

    func fetchMessage(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion)
}

/// Contract:
/// - `fetchMessage` is expected to be called on the main thread.
/// - Local cache + in-flight de-dup state is main-thread confined (no locks / queues).
/// - Network callback may arrive off-main; we hop to main before touching state and before calling completions.
final class MessageRequest: MessageRequestable {

    static let shared = MessageRequest()
    private init() {}

    private let headers: [HTTPHeader: String] = [
        .acceptLanguage: "en_US",
        .requestedBy: "native-checkout-sdk",
        .accept: "application/json"
    ]

    /// Cache key -> last result (success OR failure)
    private var cachedResults: [String: Result<MessageResponse, PayPalMessageError>] = [:]

    /// Cache key -> completions waiting for the same request
    private var inFlightCompletions: [String: [MessageRequestCompletion]] = [:]

    func fetchMessage(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion
    ) {

        guard let url = makeURL(from: parameters) else {
            onCompletion(.failure(.invalidURL))
            return
        }

        // If we cannot build a stable cache key, we cannot cache or de-dup.
        guard let cacheKey = makeCacheKey(from: parameters) else {
            startNetwork(url: url, parameters: parameters, cacheKey: nil, onCompletion: onCompletion)
            return
        }

        // Synchronous cache hit (success OR failure).
        if let cached = cachedResults[cacheKey] {
            onCompletion(cached)
            return
        }

        // De-dup: join existing request or start a new one.
        if inFlightCompletions[cacheKey] != nil {
            inFlightCompletions[cacheKey]!.append(onCompletion)
            return
        } else {
            inFlightCompletions[cacheKey] = [onCompletion]
        }

        startNetwork(url: url, parameters: parameters, cacheKey: cacheKey, onCompletion: onCompletion)
    }

    // MARK: - Network + Decode

    private func startNetwork(
        url: URL,
        parameters: MessageRequestParameters,
        cacheKey: String?,
        onCompletion: @escaping MessageRequestCompletion
    ) {
        log(.debug, "fetchMessage URL is \(url)", for: parameters.environment)

        fetch(url, headers: headers, session: parameters.environment.urlSession) { [weak self] data, response, _ in
            guard let self else { return }

            let result: Result<MessageResponse, PayPalMessageError> = self.decodeResult(
                data: data,
                response: response
            )

            DispatchQueue.main.async {
                // If no cacheKey, no caching/dedup – just return result to this caller.
                guard let cacheKey else {
                    onCompletion(result)
                    return
                }

                // Drain all callers waiting for this request.
                let completions = self.inFlightCompletions.removeValue(forKey: cacheKey) ?? []

                // Cache success OR failure.
                self.cachedResults[cacheKey] = result

                // Fan-out.
                completions.forEach { $0(result) }
            }
        }
    }

    private func decodeResult(
        data: Data?,
        response: URLResponse?
    ) -> Result<MessageResponse, PayPalMessageError> {
        guard let http = response as? HTTPURLResponse else {
            return .failure(.invalidResponse())
        }

        switch http.statusCode {
        case 200:
            guard let data, let messageResponse = try? JSONDecoder().decode(MessageResponse.self, from: data) else {
                return .failure(.invalidResponse(paypalDebugID: http.paypalDebugID))
            }
            return .success(messageResponse)

        default:
            guard let data,
                  let responseError = try? JSONDecoder().decode(ResponseError.self, from: data) else {
                return .failure(.invalidResponse(paypalDebugID: http.paypalDebugID))
            }

            return .failure(.invalidResponse(
                paypalDebugID: responseError.paypalDebugID,
                issue: responseError.issue,
                description: responseError.description
            ))
        }
    }

    // MARK: - URL / Keys

    private func makeURL(from parameters: MessageRequestParameters) -> URL? {
        let queryParams: [String: String?] = [
            "client_id": parameters.clientID,
            "merchant_id": parameters.merchantID,
            "partner_attribution_id": parameters.partnerAttributionID,
            "logo_type": parameters.logoType.rawValue,
            "buyer_country": parameters.buyerCountry,
            "page_type": parameters.pageType?.rawValue,
            "amount": parameters.amount,
            "offer": parameters.offerType?.rawValue,
            "merchant_config": parameters.merchantProfileHash,
            "ignore_cache": parameters.ignoreCache.description,
            "instance_id": parameters.instanceID,
            "version": BuildInfo.version,
            "integration_type": BuildInfo.integrationType,
            "integration_version": AnalyticsLogger.integrationVersion,
            "integration_name": AnalyticsLogger.integrationName
        ].filter {
            guard let value = $0.value else { return false }
            return !value.isEmpty && value.lowercased() != "false"
        }

        return parameters.environment.url(.message, queryParams)
    }

    /// Local cache key excludes: instance_id, ignore_cache, merchant_config (hash).
    private func makeCacheKey(from parameters: MessageRequestParameters) -> String? {
        let queryParams: [String: String?] = [
            "client_id": parameters.clientID,
            "merchant_id": parameters.merchantID,
            "partner_attribution_id": parameters.partnerAttributionID,
            "logo_type": parameters.logoType.rawValue,
            "buyer_country": parameters.buyerCountry,
            "page_type": parameters.pageType?.rawValue,
            "amount": parameters.amount,
            "offer": parameters.offerType?.rawValue,
            "version": BuildInfo.version,
            "integration_type": BuildInfo.integrationType,
            "integration_version": AnalyticsLogger.integrationVersion,
            "integration_name": AnalyticsLogger.integrationName
        ].filter {
            guard let value = $0.value else { return false }
            return !value.isEmpty && value.lowercased() != "false"
        }

        return parameters.environment.url(.message, queryParams)?.absoluteString
    }
}
