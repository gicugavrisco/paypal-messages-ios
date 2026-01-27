import Foundation

public enum PayPalMessageSource {
    case config(PayPalMessageConfig)
    case data(PayPalMessageConfigData, config: PayPalMessageConfig)
}

extension PayPalMessageSource {

    public var config: PayPalMessageConfig {
        switch self {
        case let .config(config):
            return config
        case let .data(_, config):
            return config
        }
    }
}
