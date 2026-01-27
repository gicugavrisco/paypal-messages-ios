import Foundation

public class PayPalMessageConfigData: NSObject {

    public let offerType: PayPalMessageResponseOfferType
    public let productGroup: PayPalMessageResponseProductGroup

    public let modalCloseButtonWidth: Int
    public let modalCloseButtonHeight: Int
    public let modalCloseButtonAvailWidth: Int
    public let modalCloseButtonAvailHeight: Int
    public let modalCloseButtonColor: String
    public let modalCloseButtonColorType: String
    public let modalCloseButtonAlternativeText: String

    public let defaultMainContent: String
    public let defaultMainAlternative: String?
    public let defaultDisclaimer: String

    public let genericMainContent: String
    public let genericMainAlternative: String?
    public let genericDisclaimer: String

    public let logoPlaceholder: String

    public init(
        offerType: PayPalMessageResponseOfferType,
        productGroup: PayPalMessageResponseProductGroup,
        modalCloseButtonWidth: Int,
        modalCloseButtonHeight: Int,
        modalCloseButtonAvailWidth: Int,
        modalCloseButtonAvailHeight: Int,
        modalCloseButtonColor: String,
        modalCloseButtonColorType: String,
        modalCloseButtonAlternativeText: String,
        defaultMainContent: String,
        defaultMainAlternative: String?,
        defaultDisclaimer: String,
        genericMainContent: String,
        genericMainAlternative: String?,
        genericDisclaimer: String,
        logoPlaceholder: String
    ) {
        self.offerType = offerType
        self.productGroup = productGroup
        self.modalCloseButtonWidth = modalCloseButtonWidth
        self.modalCloseButtonHeight = modalCloseButtonHeight
        self.modalCloseButtonAvailWidth = modalCloseButtonAvailWidth
        self.modalCloseButtonAvailHeight = modalCloseButtonAvailHeight
        self.modalCloseButtonColor = modalCloseButtonColor
        self.modalCloseButtonColorType = modalCloseButtonColorType
        self.modalCloseButtonAlternativeText = modalCloseButtonAlternativeText
        self.defaultMainContent = defaultMainContent
        self.defaultMainAlternative = defaultMainAlternative
        self.defaultDisclaimer = defaultDisclaimer
        self.genericMainContent = genericMainContent
        self.genericMainAlternative = genericMainAlternative
        self.genericDisclaimer = genericDisclaimer
        self.logoPlaceholder = logoPlaceholder
    }
}
