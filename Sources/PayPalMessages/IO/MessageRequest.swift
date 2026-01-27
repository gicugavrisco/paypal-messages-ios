import Foundation

typealias MessageRequestCompletion = (Result<PayPalMessageResponse, PayPalMessageError>) -> Void

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
        timeout: TimeInterval?,
        onCompletion: @escaping MessageRequestCompletion)
}

extension MessageRequestable {

    func fetchMessage(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion
    ) {
        fetchMessage(
            parameters: parameters,
            timeout: nil,
            onCompletion: onCompletion)
    }
}

final class MessageRequest: MessageRequestable {

    private let headers: [HTTPHeader: String] = [
        .acceptLanguage: "en_US",
        .requestedBy: "native-checkout-sdk",
        .accept: "application/json"
    ]

    func fetchMessage(
        parameters: MessageRequestParameters,
        onCompletion: @escaping MessageRequestCompletion
    ) {
        fetchMessage(parameters: parameters, timeout: nil, onCompletion: onCompletion)
    }

    func fetchMessage(
        parameters: MessageRequestParameters,
        timeout: TimeInterval? = nil,
        onCompletion: @escaping MessageRequestCompletion
    ) {

        guard let url = makeURL(from: parameters) else {
            onCompletion(.failure(.invalidURL))
            return
        }

        log(.debug, "fetchMessage URL: \(url)", for: parameters.environment)

        fetch(
            url,
            headers: headers,
            session: parameters.environment.urlSession,
            timeoutInterval: timeout,
            completionQueue: .main
        ) { [weak self] data, response, _ in

            guard let self else { return }

            let result: Result<PayPalMessageResponse, PayPalMessageError> = self.decodeResult(
                data: data,
                response: response)

            onCompletion(result)
        }
    }

    private func decodeResult(
        data: Data?,
        response: URLResponse?
    ) -> Result<PayPalMessageResponse, PayPalMessageError> {

        guard let http = response as? HTTPURLResponse else {
            return .failure(.invalidResponse())
        }

        switch http.statusCode {
        case 200:
            guard
                let data,
                let messageResponse = try? JSONDecoder().decode(PayPalMessageResponse.self, from: data)
            else { return .failure(.invalidResponse(paypalDebugID: http.paypalDebugID)) }

            return .success(messageResponse)

        default:
            guard
                let data,
                let responseError = try? JSONDecoder().decode(ResponseError.self, from: data)
            else { return .failure(.invalidResponse(paypalDebugID: http.paypalDebugID)) }

            return .failure(.invalidResponse(
                paypalDebugID: responseError.paypalDebugID,
                issue: responseError.issue,
                description: responseError.description
            ))
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
            "amount": parameters.amount,
            "offer": parameters.offerType?.rawValue,
            "merchant_config": parameters.merchantProfileHash,
            "ignore_cache": parameters.ignoreCache.description,
            "instance_id": parameters.instanceID,
            "version": BuildInfo.version,
            "integration_type": BuildInfo.integrationType,
            "integration_version": AnalyticsLogger.integrationVersion,
            "integration_name": AnalyticsLogger.integrationName
        ]
        .filter {
            guard let value = $0.value else { return false }
            return !value.isEmpty && value.lowercased() != "false"
        }

        return parameters.environment.url(.message, queryParams)
    }
}

// MARK: -

fileprivate struct MessageRequestIdentityKey: Equatable {
    let environmentKey: String
    let clientID: String
    let merchantID: String?
    let partnerAttributionID: String?
    let logoType: String
    let buyerCountry: String?
    let pageType: String?
    let amount: String?
    let offerType: String?
    let merchantProfileHash: String?
    let ignoreCache: Bool
    let instanceID: String

    init(_ parameters: MessageRequestParameters) {
        self.environmentKey = parameters.environment.rawValue
        self.clientID = parameters.clientID
        self.merchantID = parameters.merchantID
        self.partnerAttributionID = parameters.partnerAttributionID
        self.logoType = parameters.logoType.rawValue
        self.buyerCountry = parameters.buyerCountry
        self.pageType = parameters.pageType?.rawValue
        self.amount = parameters.amount
        self.offerType = parameters.offerType?.rawValue
        self.merchantProfileHash = parameters.merchantProfileHash
        self.ignoreCache = parameters.ignoreCache
        self.instanceID = parameters.instanceID
    }
}
