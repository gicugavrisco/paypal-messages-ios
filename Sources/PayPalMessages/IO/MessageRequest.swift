import Foundation

typealias MessageRequestCompletion =
    (Result<MessageResponse, PayPalMessageError>) -> Void

struct MessageRequestParameters {

    let environment: Environment
    let clientID: String
    let merchantID: String?
    let partnerAttributionID: String?
    let logoType: PayPalMessageLogoType
    let buyerCountry: String?
    let pageType: PayPalMessagePageType?
    let amount: Double?
    let offerType: PayPalMessageOfferType?
    let merchantProfileHash: String?
    let ignoreCache: Bool
    let instanceID: String
}

protocol MessageRequestable {
    func fetchMessage(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion
    )

    func cachedMessage(parameters: MessageRequestParameters) -> MessageResponse?
    func clearCache()
}

final class MessageRequest: MessageRequestable {

    // MARK: - Singleton

    static let shared = MessageRequest()
    private init() {}

    // MARK: - Constants

    private let headers: [HTTPHeader: String] = [
        .acceptLanguage: "en_US",
        .requestedBy: "native-checkout-sdk",
        .accept: "application/json"
    ]

    // MARK: - Cache / De-dup State

    /// Protects `cachedResponses` and `inFlightCompletions`.
    private let stateQueue = DispatchQueue(label: "com.paypalmessages.MessageRequest.state", attributes: .concurrent)

    /// Cache key -> decoded response
    private var cachedResponses: [String: MessageResponse] = [:]

    /// Cache key -> completions waiting for the same request
    private var inFlightCompletions: [String: [MessageRequestCompletion]] = [:]

    // MARK: - MessageRequestable

    /// Returns a cached response synchronously (no network).
    func cachedMessage(parameters: MessageRequestParameters) -> MessageResponse? {
        guard let key = makeCacheKey(from: parameters) else { return nil }
        return stateQueue.sync {
            cachedResponses[key]
        }
    }

    /// Optional: clear cache (handy for debugging / tests).
    func clearCache() {
        stateQueue.async(flags: .barrier) {
            self.cachedResponses.removeAll()
            self.inFlightCompletions.removeAll()
        }
    }

    func fetchMessage(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion
    ) {
        // If caller explicitly disables cache: do the simplest thing.
        if parameters.ignoreCache {
            fetchFromNetwork(parameters: parameters, onCompletion: onCompletion)
            return
        }

        guard let url = makeURL(from: parameters) else {
            onCompletion(.failure(.invalidURL))
            return
        }

        // IMPORTANT:
        // We exclude instance_id from the cache key, otherwise every view instance becomes a unique key,
        // and caching becomes ineffective in a scrolling list.
        guard let cacheKey = makeCacheKey(from: parameters) else {
            // Fallback: no stable key => no caching/dedup
            fetchFromNetwork(parameters: parameters, onCompletion: onCompletion)
            return
        }

        enum Action {
            case returnCached(MessageResponse)
            case joinInFlight
            case startNew
        }

        let action: Action = stateQueue.sync(flags: .barrier) {
            if let cached = cachedResponses[cacheKey] {
                return .returnCached(cached)
            }

            if var list = inFlightCompletions[cacheKey] {
                list.append(onCompletion)
                inFlightCompletions[cacheKey] = list
                return .joinInFlight
            }

            inFlightCompletions[cacheKey] = [onCompletion]
            return .startNew
        }

        switch action {
        case .returnCached(var cached):
            // Keep behavior similar to network path: set requestDuration to ~0
            cached.requestDuration = 0
            onCompletion(.success(cached))
            return

        case .joinInFlight:
            // Someone else is already fetching the same request; our completion will be called when it finishes.
            return

        case .startNew:
            // Proceed below.
            break
        }

        let startingTimestamp = Date()
        log(.debug, "fetchMessage URL is \(url)", for: parameters.environment)

        fetch(url, headers: headers, session: parameters.environment.urlSession) { [weak self] data, response, _ in
            guard let self else { return }

            let requestDuration = startingTimestamp.timeIntervalSinceNow

            let result: Result<MessageResponse, PayPalMessageError> = {
                guard let response = response as? HTTPURLResponse else {
                    return .failure(.invalidResponse())
                }

                switch response.statusCode {
                case 200:
                    guard let data, var messageResponse = try? JSONDecoder().decode(MessageResponse.self, from: data) else {
                        return .failure(.invalidResponse(paypalDebugID: response.paypalDebugID))
                    }

                    messageResponse.requestDuration = requestDuration
                    return .success(messageResponse)

                default:
                    guard let data,
                          let responseError = try? JSONDecoder().decode(ResponseError.self, from: data) else {
                        return .failure(.invalidResponse(paypalDebugID: response.paypalDebugID))
                    }

                    return .failure(.invalidResponse(
                        paypalDebugID: responseError.paypalDebugID,
                        issue: responseError.issue,
                        description: responseError.description
                    ))
                }
            }()

            // Drain in-flight completions and update cache (success only).
            let completions: [MessageRequestCompletion] = self.stateQueue.sync(flags: .barrier) {
                let list = self.inFlightCompletions.removeValue(forKey: cacheKey) ?? []

                if case .success(let response) = result {
                    self.cachedResponses[cacheKey] = response
                }

                return list
            }

            completions.forEach { $0(result) }
        }
    }

    // MARK: - Internals

    private func fetchFromNetwork(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion
    ) {
        guard let url = makeURL(from: parameters) else {
            onCompletion(.failure(.invalidURL))
            return
        }

        let startingTimestamp = Date()
        log(.debug, "fetchMessage URL is \(url)", for: parameters.environment)

        fetch(url, headers: headers, session: parameters.environment.urlSession) { data, response, _ in
            let requestDuration = startingTimestamp.timeIntervalSinceNow

            guard let response = response as? HTTPURLResponse else {
                onCompletion(.failure(.invalidResponse()))
                return
            }

            switch response.statusCode {
            case 200:
                guard let data, var messageResponse = try? JSONDecoder().decode(MessageResponse.self, from: data) else {
                    onCompletion(.failure(.invalidResponse(paypalDebugID: response.paypalDebugID)))
                    return
                }

                messageResponse.requestDuration = requestDuration
                onCompletion(.success(messageResponse))

            default:
                guard let data, let responseError = try? JSONDecoder().decode(ResponseError.self, from: data) else {
                    onCompletion(.failure(.invalidResponse(paypalDebugID: response.paypalDebugID)))
                    return
                }

                onCompletion(.failure(.invalidResponse(
                    paypalDebugID: responseError.paypalDebugID,
                    issue: responseError.issue,
                    description: responseError.description
                )))
            }
        }
    }

    private func makeURL(from parameters: MessageRequestParameters) -> URL? {
        let queryParams: [String: String?] = [
            "client_id": parameters.clientID,
            "merchant_id": parameters.merchantID,
            "partner_attribution_id": parameters.partnerAttributionID,
            "logo_type": parameters.logoType.rawValue,
            "buyer_country": parameters.buyerCountry,
            "page_type": parameters.pageType?.rawValue,
            "amount": parameters.amount?.description,
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

    /// Produces a stable cache key for a message request.
    /// Intentionally excludes `instance_id` and `ignore_cache`.
    private func makeCacheKey(from parameters: MessageRequestParameters) -> String? {
        let queryParams: [String: String?] = [
            "client_id": parameters.clientID,
            "merchant_id": parameters.merchantID,
            "partner_attribution_id": parameters.partnerAttributionID,
            "logo_type": parameters.logoType.rawValue,
            "buyer_country": parameters.buyerCountry,
            "page_type": parameters.pageType?.rawValue,
            "amount": parameters.amount?.description,
            "offer": parameters.offerType?.rawValue,
            "merchant_config": parameters.merchantProfileHash,
            // NOTE: do not include ignore_cache / instance_id
            "version": BuildInfo.version,
            "integration_type": BuildInfo.integrationType,
            "integration_version": AnalyticsLogger.integrationVersion,
            "integration_name": AnalyticsLogger.integrationName
        ].filter {
            guard let value = $0.value else { return false }
            return !value.isEmpty && value.lowercased() != "false"
        }

        // Using URL string as the key gives a canonical ordering via URLComponents creation in Environment.url(...)
        return parameters.environment.url(.message, queryParams)?.absoluteString
    }
}
