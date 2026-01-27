import Foundation

protocol MerchantProfileHashGetable {

    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        timeout: TimeInterval?,
        onCompletion: @escaping (String?) -> Void)
}

extension MerchantProfileHashGetable {

    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        onCompletion: @escaping (String?) -> Void
    ) {
        getMerchantProfileHash(
            environment: environment,
            clientID: clientID,
            merchantID: merchantID,
            timeout: nil,
            onCompletion: onCompletion)
    }
}

class MerchantProfileProvider: MerchantProfileHashGetable {
    private let merchantProfileRequest: MerchantProfileRequestable

    init(merchantProfileRequest: MerchantProfileRequestable = MerchantProfileRequest()) {
        self.merchantProfileRequest = merchantProfileRequest
    }

    func getMerchantProfileHash(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        timeout: TimeInterval?,
        onCompletion: @escaping (String?) -> Void
    ) {
        let currentDate = Date()

        // hash must be inside ttl and non-null
        guard
            let merchantProfileData = getCachedMerchantProfileData(
                clientID: clientID,
                merchantID: merchantID),
            currentDate < merchantProfileData.ttlHard
        else {

            requestMerchantProfile(
                environment: environment,
                clientID: clientID,
                merchantID: merchantID,
                timeout: timeout,
                onCompletion: { merchantProfiledData in
                    guard let merchantProfiledData = merchantProfiledData else {
                        onCompletion(nil)
                        return
                    }

                    onCompletion(merchantProfiledData.disabled ? nil : merchantProfiledData.hash)
                })

            return
        }

        // if date is outside soft-ttl window, re-request data
        if currentDate > merchantProfileData.ttlSoft {
            // ignores the response as it will return hashed value
            requestMerchantProfile(
                environment: environment,
                clientID: clientID,
                merchantID: merchantID,
                timeout: nil, // doen't make sense to have a timeout
                onCompletion: { _ in })
        }

        onCompletion(merchantProfileData.disabled ? nil : merchantProfileData.hash)
    }

    private func requestMerchantProfile(
        environment: Environment,
        clientID: String,
        merchantID: String?,
        timeout: TimeInterval?,
        onCompletion: @escaping (MerchantProfileData?) -> Void
    ) {
        merchantProfileRequest.fetchMerchantProfile(
            environment: environment,
            clientID: clientID,
            merchantID: merchantID,
            timeout: timeout,
            onCompletion: { [weak self] result in

                switch result {
                case let .success(merchantProfileData):
                    log(
                        .debug,
                        "Merchant Request Hash succeeded with \(merchantProfileData.hash)",
                        for: environment)

                    self?.setCachedMerchantProfileData(
                        merchantProfileData,
                        clientID: clientID,
                        merchantID: merchantID)

                    onCompletion(merchantProfileData)

                case let .failure(error):
                    log(
                        .debug,
                        "Merchant Request Hash failed with \(error.localizedDescription)",
                        for: environment)
                    
                    onCompletion(nil)
                }
            })
    }

    // MARK: - User Defaults Methods

    private func getCachedMerchantProfileData(
        clientID: String,
        merchantID: String?
    ) -> MerchantProfileData? {

        guard
            let cachedData = UserDefaults.getMerchantProfileData(
                forClientID: clientID,
                merchantID: merchantID)
        else { return nil }

        return try? JSONDecoder().decode(MerchantProfileData.self, from: cachedData)
    }

    private func setCachedMerchantProfileData(
        _ data: MerchantProfileData,
        clientID: String,
        merchantID: String?
    ) {
        let encodedData = try? JSONEncoder().encode(data)

        UserDefaults.setMerchantProfileData(
            encodedData,
            forClientID: clientID,
            merchantID: merchantID)
    }
}
