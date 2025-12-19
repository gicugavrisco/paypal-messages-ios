import Foundation
import UIKit

final class Weak<T: AnyObject> {
    weak var value: T?

    init(_ value: T?) {
        self.value = value
    }
}

final class AnalyticsLogger: Encodable {

    // MARK: - Global Details

    static var integrationVersion: String?
    static var integrationName: String?

    // MARK: - Instance Details

    var component: Component
    var instanceId: String

    // Includes things like fdata, experience IDs, debug IDs, and the like
    var dynamicData: [String: AnyCodable] = [:]

    // Events tied to the component
    var events: [AnalyticsEvent] = []

    enum Component {
        case message(Weak<PayPalMessageView>)
        case modal(Weak<PayPalMessageModal>)
    }

    init(_ component: Component) {
        self.instanceId = UUID().uuidString
        self.component = component
        AnalyticsService.shared.addLogger(self)
    }

    deinit {}

    // MARK: - Encoding

    enum StaticKey: String, CodingKey {
        // Integration Details
        case offerType = "offer_type"
        case amount = "amount"
        case pageType = "page_type"
        case buyerCountryCode = "buyer_country_code"
        case channel = "presentment_channel"

        // Message Only (style)
        case styleLogoType = "style_logo_type"
        case styleColor = "style_color"
        case styleTextAlign = "style_text_align"

        // Other Details
        case type = "type"
        case instanceId = "instance_id"

        // Component Events
        case events = "component_events"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StaticKey.self)

        try container.encode(instanceId, forKey: .instanceId)
        try container.encode(events, forKey: .events)

        // Encode dynamic data (relies on your existing AnyCodable dictionary encoding support)
        try dynamicData.encode(to: encoder)

        switch component {
        case .message(let weakMessage):
            guard let messageView = weakMessage.value else { return }

            // After refactor, PayPalMessageView no longer exposes individual fields.
            // Use the view's config as the single source of truth.
            let config = messageView.getConfig()

            try container.encode("message", forKey: .type)

            try container.encodeIfPresent(config.data.offerType?.rawValue, forKey: .offerType)
            try container.encodeIfPresent(config.data.amount?.description, forKey: .amount)
            try container.encodeIfPresent(config.data.pageType?.rawValue, forKey: .pageType)
            try container.encodeIfPresent(config.data.buyerCountry, forKey: .buyerCountryCode)
            try container.encodeIfPresent(config.data.channel, forKey: .channel)

            try container.encode(config.style.logoType.rawValue, forKey: .styleLogoType)
            try container.encode(config.style.color.rawValue, forKey: .styleColor)
            try container.encode(config.style.textAlign.rawValue, forKey: .styleTextAlign)

        case .modal(let weakModal):
            guard let modal = weakModal.value else { return }

            try container.encode("modal", forKey: .type)
            try container.encodeIfPresent(modal.offerType?.rawValue, forKey: .offerType)
            try container.encodeIfPresent(modal.amount?.description, forKey: .amount)
            try container.encodeIfPresent(modal.pageType?.rawValue, forKey: .pageType)
            try container.encodeIfPresent(modal.buyerCountry, forKey: .buyerCountryCode)
            try container.encodeIfPresent(modal.channel, forKey: .channel)
        }
    }

    // MARK: - Events

    func addEvent(_ event: AnalyticsEvent) {
        events.append(event)
    }

    func clearEvents() {
        events.removeAll()
    }
}
