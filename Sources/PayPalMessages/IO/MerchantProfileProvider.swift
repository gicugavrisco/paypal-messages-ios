import Foundation

protocol MerchantProfileHashGetable {

    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (String?) -> Void)
}

final class MerchantProfileProvider: MerchantProfileHashGetable {
    static let shared = MerchantProfileProvider(request: MerchantProfileRequest())

    private let request: MerchantProfileRequestable
    private var cachedResults: [String : Result<MerchantProfileData, Error>] = [:]
    private var inFlightCompletions: [String: [(String?) -> Void]] = [:]

    private init(request: MerchantProfileRequestable) {
        self.request = request
    }

    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (String?) -> Void
    ) {

        let cacheKey = makeRequestKey(environment, clientID, merchantID)

        if let cached = cachedResults[cacheKey] {
            if let value = try? cached.get(), Date() < value.ttlHard {

                if Date() > value.ttlSoft {
                    requestMerchantProfile(
                        environment: environment,
                        clientID: clientID,
                        merchantID: merchantID,
                        cacheKey: cacheKey)
                }

                onCompletion(value.disabled ? nil : value.hash)
                return

            } else {
                onCompletion(nil)
                return
            }
        }

        // De-dup: join existing request or start a new one.
        if inFlightCompletions[cacheKey] != nil {
            inFlightCompletions[cacheKey]?.append(onCompletion)
            return

        } else {
            inFlightCompletions[cacheKey] = [onCompletion]
        }

        requestMerchantProfile(
            environment: environment,
            clientID: clientID,
            merchantID: merchantID,
            cacheKey: cacheKey)
    }

    // MARK: - API Fetch Methods (dedup wrapper)

    private func requestMerchantProfile(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        cacheKey: String
    ) {

        request.fetchMerchantProfile(
            environment: environment,
            clientID: clientID,
            merchantID: merchantID,
            onCompletion: { [weak self] result in
                guard let self else { return }

                switch result {
                case let .success(merchantProfileData):
                    log(.debug, "Merchant Request Hash succeeded with \(merchantProfileData.hash)", for: environment)

                case let .failure(error):
                    log(.debug, "Merchant Request Hash failed with \(error.localizedDescription)", for: environment)
                }

                self.cachedResults[cacheKey] = result

                let completions = self.inFlightCompletions.removeValue(forKey: cacheKey) ?? []

                completions.forEach {
                    if let value = try? result.get() {
                        $0(value.disabled ? nil : value.hash)
                    } else {
                        $0(nil)
                    }
                }
            })
    }

    private func makeRequestKey(
        _ environment: Environment,
        _ clientID: String,
        _ merchantID: String?
    ) -> String {

        "\(environment)|\(clientID)|\(merchantID ?? "")"
    }
}
