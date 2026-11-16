import SwiftUI

extension View {
    /// What every parent-code field shares, so the prompts all behave the same: a number pad on
    /// iPhone and iPad. A modifier rather than a wrapper view, because some of these fields sit
    /// inside alerts, which only show plain text fields and buttons.
    func parentCodeEntry() -> some View {
        #if os(iOS)
        self.keyboardType(.numberPad).textContentType(.oneTimeCode)
        #else
        self
        #endif
    }
}
