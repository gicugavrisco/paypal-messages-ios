/// Preferred message offer to display
public enum PayPalMessageOfferType: String, Decodable, CaseIterable {
    /// Pay Later short term installment
    case payLaterShortTerm = "PAY_LATER_SHORT_TERM"
    /// Pay Later long term installments
    case payLaterLongTerm = "PAY_LATER_LONG_TERM"
    /// Pay Later deferred payment
    case payLaterPayIn1 = "PAY_LATER_PAY_IN_1"
    /// PayPal Credit No Interest
    case payPalCreditNoInterest = "PAYPAL_CREDIT_NO_INTEREST"
}

/// Preferred message offer to display. The response is different from the request type, since it allows for Generic responses.
public enum PayPalMessageResponseOfferType: String, Decodable {
    /// Pay Later short term installment
    case payLaterShortTerm = "PAY_LATER_SHORT_TERM"
    /// Pay Later long term installments
    case payLaterLongTerm = "PAY_LATER_LONG_TERM"
    /// Pay Later deferred payment
    case payLaterPayIn1 = "PAY_LATER_PAY_IN_1"
    /// PayPal Credit No Interest
    case payPalCreditNoInterest = "PAYPAL_CREDIT_NO_INTEREST"
    /// Generic case
    case generic = "GENERIC"
}

/// Top level product group
public enum PayPalMessageResponseProductGroup: String, Decodable {
    /// Pay Later
    case payLater = "PAY_LATER"
    /// PayPal Credit
    case paypalCredit = "PAYPAL_CREDIT"
}
