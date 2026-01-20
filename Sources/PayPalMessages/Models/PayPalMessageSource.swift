import Foundation

public enum PayPalMessageSource {
    case config(PayPalMessageConfig)
    case response(PayPalMessageResponse, config: PayPalMessageConfig)
}

public extension PayPalMessageSource {

    public var config: PayPalMessageConfig {
        switch self {
        case let .config(config):
            return config
        case let .response(_, config):
            return config
        }
    }
}
