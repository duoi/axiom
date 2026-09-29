import Foundation

enum SendFailureCopy {
    static func message(for error: Error) -> String {
        if let grab = error as? ScreenGrabError {
            switch grab {
            case .permission:
                return HUDErrorLip.screenPermission
            case .accessibility:
                return HUDErrorLip.accessibilityPermission
            case .failed:
                return HUDErrorLip.screenFailed
            }
        }
        if let auth = error as? ChatGPTAuthError {
            if case .message(let message) = auth {
                return message
            }
            return "Sign in to ChatGPT in Settings"
        }
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "The request timed out."
        }
        return "The request failed."
    }
}
