import Foundation
import UIKit

/// 「旁听」功能首次开启前的一次性确认屏。
///
/// 规格：`_规格_面对面旁听实时字幕_20260918.md` §8.4。
///
/// 🚨🚨 这次录的是**别人**说的话，不是用户自己说的话——产品够不着"在场人员
/// 是否真的知情"这件事（面对面场景就算提示再显眼，用户是不是把手机亮出来给
/// 别人看是他自己的行为；电脑外放场景对方在视频会议另一端，物理上根本看不到
/// 屏幕）。0 已裁定处置方式：**不假装能做到，把责任明确交出去并留痕**——
/// 首次开启弹一次确认屏，用户必须点确认才能放行，状态存本地，下次不再弹。
///
/// 🚨 **四端统一文案，字面意思不能改写**——这不是普通提示，润色措辞会削弱
/// "让使用者真的意识到这件事"这个目的。别在调用方那边自己再包一层说明文字。
enum EavesdropConsent {
    private static let key = "transless.eavesdrop.consented"

    /// 已经确认过，不用再弹。
    static var confirmed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// 还没确认过就弹一次并等用户点确认；确认过直接放行。
    /// 🚨 没有「取消」——这不是可以绕过去的功能开关询问，是必须先看到才能继续的
    ///    责任声明。想放弃就是不开始录，不是弹出来又能悄悄点掉。
    static func ensure(on vc: UIViewController, then: @escaping () -> Void) {
        if confirmed {
            then()
            return
        }
        let a = UIAlertController(title: L.eavesdrop_consent_title,
                                  message: L.eavesdrop_consent_body,
                                  preferredStyle: .alert)
        a.addAction(UIAlertAction(title: L.eavesdrop_consent_confirm,
                                  style: .default) { _ in
            UserDefaults.standard.set(true, forKey: key)
            then()
        })
        vc.present(a, animated: true)
    }
}
