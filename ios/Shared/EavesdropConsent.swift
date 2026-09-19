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
/// 🚨 **四端统一文案，字面意思不能改写**——这不是普通提示，别在调用方那边
/// 自己再包一层说明文字。
///
/// 🚨🚨 09-19 二次更新：文案本身改过一版——Kevin 嫌旧版"一堆什么可能违法
/// 什么什么"吓人（原话），4（合规）出了更平实的终稿换掉。**旧版那句"提可能
/// 违法"从来不是条款要求**——苹果 2.5.14 要的是 explicit user consent +
/// 录音指示，这两条本来就由系统麦克风权限弹窗和 iOS 橙点满足，法律免责声明
/// 式的措辞是我们自己加的，不是合规红线；换成平实说法**不影响合规边界**，
/// 只是别再把用户吓跑。这次改动没碰这个机制本身（一次性、`confirmed` 状态、
/// 键名 `transless.eavesdrop.consented`）——那些三端统一，不能改。
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
