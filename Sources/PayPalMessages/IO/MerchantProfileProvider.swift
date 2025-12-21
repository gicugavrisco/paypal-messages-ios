import Foundation

protocol MerchantProfileHashGetable {
    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (String?) -> Void
    )

    /// Returns a cached hash synchronously if available and within hard TTL.
    /// Returns `nil` if not cached, expired, or explicitly disabled.
    func cachedMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?
    ) -> String?
}

final class MerchantProfileProvider: MerchantProfileHashGetable {

    private let merchantProfileRequest: MerchantProfileRequestable

    // De-dup in-flight requests (MerchantProfileData-level)
    private let stateQueue = DispatchQueue(
        label: "com.paypalmessages.MerchantProfileProvider.state",
        attributes: .concurrent
    )

    private var inFlightCompletions: [String: [(MerchantProfileData?) -> Void]] = [:]

    init(
        merchantProfileRequest: MerchantProfileRequestable = MerchantProfileRequest()
    ) {
        self.merchantProfileRequest = merchantProfileRequest
    }

    deinit {}

    // MARK: - Merchant Hash Methods

    func cachedMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?
    ) -> String? {
        let currentDate = Date()

        // hash must be inside ttlHard and non-null
        guard let merchantProfileData = getCachedMerchantProfileData(clientID: clientID, merchantID: merchantID),
              currentDate < merchantProfileData.ttlHard else {
            return nil
        }

        // if date is outside soft-ttl window, re-request data (deduped)
        if currentDate > merchantProfileData.ttlSoft {
            requestMerchantProfileDeduped(environment: environment, clientID: clientID, merchantID: merchantID) { _ in }
        }

        return merchantProfileData.disabled ? nil : merchantProfileData.hash
    }

    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (String?) -> Void
    ) {
        // Fast synchronous path if cached and valid
        if let cached = cachedMerchantProfileHash(environment: environment, clientID: clientID, merchantID: merchantID) {
            onCompletion(cached)
            return
        }

        // Cache miss/expired => fetch (deduped)
        requestMerchantProfileDeduped(environment: environment, clientID: clientID, merchantID: merchantID) { merchantProfileData in
            guard let merchantProfileData else {
                onCompletion(nil)
                return
            }

            onCompletion(merchantProfileData.disabled ? nil : merchantProfileData.hash)
        }
    }

    // MARK: - API Fetch Methods (dedup wrapper)

    private func requestMerchantProfileDeduped(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (MerchantProfileData?) -> Void
    ) {
        let key = makeInFlightKey(environment: environment, clientID: clientID, merchantID: merchantID)

        enum Action {
            case joinInFlight
            case startNew
        }

        let action: Action = stateQueue.sync(flags: .barrier) {
            if var list = inFlightCompletions[key] {
                list.append(onCompletion)
                inFlightCompletions[key] = list
                return .joinInFlight
            }

            inFlightCompletions[key] = [onCompletion]
            return .startNew
        }

        switch action {
        case .joinInFlight:
            return
        case .startNew:
            break
        }

        requestMerchantProfile(environment: environment, clientID: clientID, merchantID: merchantID) { [weak self] merchantProfileData in
            guard let self else { return }

            let completions: [(MerchantProfileData?) -> Void] = self.stateQueue.sync(flags: .barrier) {
                self.inFlightCompletions.removeValue(forKey: key) ?? []
            }

            completions.forEach { $0(merchantProfileData) }
        }
    }

    private func makeInFlightKey(environment: Environment, clientID: String, merchantID: String?) -> String {
        "\(environment)|\(clientID)|\(merchantID ?? "")"
    }

    private func requestMerchantProfile(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (MerchantProfileData?) -> Void
    ) {
        merchantProfileRequest.fetchMerchantProfile(
            environment: environment,
            clientID: clientID,
            merchantID: merchantID
        ) { [weak self] result in
            switch result {
            case .success(let merchantProfileData):
                log(.debug, "Merchant Request Hash succeeded with \(merchantProfileData.hash)", for: environment)
                self?.setCachedMerchantProfileData(merchantProfileData, clientID: clientID, merchantID: merchantID)
                onCompletion(merchantProfileData)

            case .failure(let error):
                log(.debug, "Merchant Request Hash failed with \(error.localizedDescription)", for: environment)
                onCompletion(nil)
            }
        }
    }

    // MARK: - User Defaults Methods

    private func getCachedMerchantProfileData(clientID: String, merchantID: String?) -> MerchantProfileData? {
        guard let cachedData = UserDefaults.getMerchantProfileData(forClientID: clientID, merchantID: merchantID) else {
            return nil
        }

        return try? JSONDecoder().decode(MerchantProfileData.self, from: cachedData)
    }

    private func setCachedMerchantProfileData(_ data: MerchantProfileData, clientID: String, merchantID: String?) {
        let encodedData = try? JSONEncoder().encode(data)
        UserDefaults.setMerchantProfileData(encodedData, forClientID: clientID, merchantID: merchantID)
    }
}

