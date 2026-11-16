import Defaults
import Foundation
import T3IsleCore

extension QuotaWindowChoice: Defaults.Serializable {}

extension Defaults.Keys {
    static let t3Enabled = Key<Bool>("t3Enabled", default: true)
    static let t3AttentionBorder = Key<Bool>("t3AttentionBorder", default: true)
    static let t3AttentionBorderHex = Key<String>("t3AttentionBorderHex", default: BorderPalette.standardHex)
    static let t3OpenOnQuestion = Key<Bool>("t3OpenOnQuestion", default: true)
    static let t3QuestionSound = Key<Bool>("t3QuestionSound", default: false)
    static let t3KeepFinishedPinned = Key<Bool>("t3KeepFinishedPinned", default: true)
    static let t3QuotaWindow = Key<QuotaWindowChoice>("t3QuotaWindow", default: .session)
    static let t3ThreadActions = Key<Bool>("t3ThreadActions", default: true)
    static let t3ShowSubagents = Key<Bool>("t3ShowSubagents", default: false)
    static let t3ShowQuotaLeft = Key<Bool>("t3ShowQuotaLeft", default: true)
    static let t3QuotaWarnAt = Key<Int>("t3QuotaWarnAt", default: 40)
    static let t3QuotaCriticalAt = Key<Int>("t3QuotaCriticalAt", default: 15)
    static let t3FacesPerGroup = Key<Int>("t3FacesPerGroup", default: 3)
    static let t3HeadphonesActivity = Key<Bool>("t3HeadphonesActivity", default: true)
    static let t3CollapsedSections = Key<Set<String>>("t3CollapsedSections", default: ["snoozed"])
}
