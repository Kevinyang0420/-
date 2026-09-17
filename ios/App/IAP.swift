import Foundation
import StoreKit

/// **iOS 内购的唯一实现点** —— StoreKit 2。
///
/// 规格 `_规格_试用与付费链路_20260911.md` §2③：
/// 商品 `com.kevin.transless.pro.monthly`，US$9.99/月，试用**不用苹果的
/// introductory offer**（那个已经删了并加了挡板）——我们自己的 7 天试用
/// **完全是服务端按设备算的**，跟这个商品的价格/试用配置无关，
/// 这里只管"钱怎么收"，不管"免费期怎么算"。
///
/// 🚨🚨 **绝不能只信客户端"购买成功"这个信号就当作已经是会员** ——
///    这里的 `finish()` 只是告诉苹果"这笔交易我处理完了，别再重复推给我"，
///    **真正的会员状态永远以 `ProStatus.refresh()` 读到的服务端结果为准**。
///    购买成功后调 `ProStatus.refreshSoonAfterPurchase()`，不是自己在本地翻一个 flag。
///
/// 🚨🚨 **`appAccountToken` 契约（2026-09-12 报给 1.1，09-13 已接上）**：
///    服务端按 `user_id` 确定性算出一个 UUID，通过 `GET /api/pro` 的
///    `purchase_uuid` 字段发给客户端——**客户端只管拿来用，绝不自己生成/派生**。
///    这个值传给 `Product.purchase(options:)` 的 `.appAccountToken`；
///    苹果的服务器通知会把它原样带回来，后端 `resolve_purchase_uuid()`
///    拿它反查回真实 `user_id`，才打得上会员标记。
///    🚨 拿不到这个值（未登录/网络问题）就**不发起购买**——传一个随机瞎编的
///    UUID 会被后端新加的判据拒绝并返回 `unresolvable_purchase_uuid`，
///    表现成"钱扣了、会员没开通"，比直接不让购买更糟。
enum IAP {
    static let proMonthlyId = "com.kevin.transless.pro.monthly"

    // MARK: - 价格缓存（09-17 `_规格_价格呈现口径_20260917.md`）
    //
    // 🚨🚨 进付费页**之前**（账户页那一行）就要看到价格，不能等用户点进去
    // 才发起 StoreKit 请求——那时候异步请求还没开始，用户会先看到空白/占位。
    // 落盘（不只是内存）是因为**冷启动**时这个值必须立刻可读：App 刚起来、
    // 用户还没进设置页，`prefetch()` 的网络请求多半还没回来，这时候读的
    // 是上一次成功拉到的那份缓存，不是这次的。

    private static let kCachedPrice = "ios.iap.cachedDisplayPrice"

    /// 账户页/设置页渲染时读这个——**不发起网络请求**，只读上次缓存。
    /// 没有缓存（比如全新安装、从没成功拉到过商品）就是 `nil`，
    /// 调用方自己决定怎么退化（多半是不显示价格那一段，不是显示空字符串）。
    static var cachedDisplayPrice: String? {
        UserDefaults.standard.string(forKey: kCachedPrice)
    }

    /// 应用启动时调一次，**预热缓存**，不关心结果、不通知任何人——
    /// 真正等结果的地方（`SubscribeViewController`）自己会再调一次
    /// `fetchProduct` 拿权威值。这次调用纯粹是为了让 `cachedDisplayPrice`
    /// 尽早从 `nil` 变成有值，账户页第一次出现时大概率已经不是空的。
    static func prefetchProduct() {
        fetchProduct { _ in }
    }

    enum PurchaseError: Error {
        case productNotFound
        case userCancelled
        case pending
        case verificationFailed
        case noPurchaseToken   // 拿不到 purchase_uuid（未登录/网络问题）
        case unknown(Error)
    }

    /// 拉商品信息（价格、本地化文案）。**失败要说清是什么失败**，
    /// 不许统一说"网络错误"——网络错误和"苹果那边商品还没配好"
    /// (`MISSING_METADATA`) 对用户和对我们排查是完全不同的两件事。
    static func fetchProduct(onResult: @escaping (Result<Product, Error>) -> Void) {
        Task {
            do {
                let products = try await Product.products(for: [proMonthlyId])
                guard let p = products.first else {
                    KbBridge.note("内购：拉不到商品 " + proMonthlyId
                                  + " —— 商店后台没配好，或者还在 MISSING_METADATA")
                    return DispatchQueue.main.async {
                        onResult(.failure(PurchaseError.productNotFound))
                    }
                }
                // 🚨 拿到就存——`displayPrice` 已经是 StoreKit 按这台设备的
                //    区域本地化好的字符串，跟 `SubscribeViewController` 用的
                //    是同一个字段，两处不会显示不一致的价格。
                UserDefaults.standard.set(p.displayPrice, forKey: kCachedPrice)
                DispatchQueue.main.async { onResult(.success(p)) }
            } catch {
                KbBridge.note("内购：拉商品失败 —— " + error.localizedDescription)
                DispatchQueue.main.async { onResult(.failure(error)) }
            }
        }
    }

    /// 发起购买。**成功只代表"这笔交易本身合法"**，不代表会员已经生效——
    /// 生效与否永远看 `ProStatus`。
    static func purchase(_ product: Product,
                         onResult: @escaping (Result<Void, PurchaseError>) -> Void) {
        // 🚨 先拿服务端签发的 purchase_uuid，拿不到就**不发起购买**——
        //    理由见文件顶部注释：瞎编一个 UUID 会让钱扣了但会员打不上标记。
        ProStatus.fetchPurchaseUUID { token in
            guard let token = token else {
                KbBridge.note("内购：拿不到 purchase_uuid，中止购买（未登录或网络问题）")
                return onResult(.failure(.noPurchaseToken))
            }
            purchaseWithToken(product, token: token, onResult: onResult)
        }
    }

    private static func purchaseWithToken(
        _ product: Product, token: UUID,
        onResult: @escaping (Result<Void, PurchaseError>) -> Void) {
        Task {
            do {
                let result = try await product.purchase(
                    options: [.appAccountToken(token)])
                switch result {
                case .success(let verification):
                    switch verification {
                    case .verified(let tx):
                        await tx.finish()
                        KbBridge.note("内购：交易验签通过，id=" + String(tx.id))
                        DispatchQueue.main.async { onResult(.success(())) }
                    case .unverified(_, let err):
                        // 🚨 **不完成这笔交易**——unverified 说明签名对不上，
                        //    finish() 了等于承认这笔来路不明的交易，别这么做。
                        KbBridge.note("内购：交易未通过 StoreKit 本地验签 —— "
                                      + err.localizedDescription)
                        DispatchQueue.main.async { onResult(.failure(.verificationFailed)) }
                    }
                case .userCancelled:
                    DispatchQueue.main.async { onResult(.failure(.userCancelled)) }
                case .pending:
                    // 🚨 家长同意等待中这类情况——不是失败，也不是成功，
                    //    真正生效时会走下面 `observeTransactionUpdates` 那条监听。
                    KbBridge.note("内购：交易待处理（比如家长同意），不是失败")
                    DispatchQueue.main.async { onResult(.failure(.pending)) }
                @unknown default:
                    DispatchQueue.main.async { onResult(.failure(.unknown(
                        NSError(domain: "IAP", code: -1)))) }
                }
            } catch {
                KbBridge.note("内购：购买流程抛错 —— " + error.localizedDescription)
                DispatchQueue.main.async { onResult(.failure(.unknown(error))) }
            }
        }
    }

    /// 🚨🚨 **恢复购买必须有**，苹果审核会明确检查这一项——
    ///    换设备/重装之后没有入口找回已购买的订阅，是**必拒审**的理由之一。
    static func restore(onResult: @escaping (Bool) -> Void) {
        Task {
            do {
                try await AppStore.sync()
                KbBridge.note("内购：已触发 AppStore.sync() 恢复购买")
                DispatchQueue.main.async { onResult(true) }
            } catch {
                KbBridge.note("内购：恢复购买失败 —— " + error.localizedDescription)
                DispatchQueue.main.async { onResult(false) }
            }
        }
    }

    /// 🚨 **必须监听 `Transaction.updates`**，不是只处理 `purchase()` 那一次的返回值——
    ///    续订、退款、家长同意延迟批准，这些事件都从这条流出来，不从购买调用本身出来。
    ///    在 App 启动时挂一次，整个生命周期只挂一次（重复挂会重复处理同一笔交易）。
    private static var updatesTask: Task<Void, Never>?

    static func startObservingTransactionUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let tx) = result else { continue }
                await tx.finish()
                KbBridge.note("内购：后台收到交易更新，id=" + String(tx.id)
                              + "，去问服务端最新会员状态")
                ProStatus.refreshSoonAfterPurchase()
            }
        }
    }
}
