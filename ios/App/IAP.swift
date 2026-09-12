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
/// 🚨🚨 **`appAccountToken` 那道契约还没接上**（2026-09-12 报给 1.1）：
///    服务端 `user_id` 是 `u_` 前缀字符串，StoreKit 2 这个参数要的是 `Foundation.UUID`，
///    两边格式对不上。**在服务端把"给我一个可以用的 UUID"这个字段加进 `/api/pro` 之前，
///    这里先不传 `appAccountToken`**——不传的后果是苹果通知里没有这个字段，
///    后端 `_apple_webhook` 会落进 `no_appAccountToken` 分支、不打会员标记。
///    **这意味着现在这版购买了但服务端认不出是谁，不能上线**，
///    等 1.1 那边给了字段，把 `appAccountTokenPlaceholder` 换成真值就行——
///    改动只在这一处，其余流程不用动。
enum IAP {
    static let proMonthlyId = "com.kevin.transless.pro.monthly"

    enum PurchaseError: Error {
        case productNotFound
        case userCancelled
        case pending
        case verificationFailed
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
        Task {
            do {
                // 🚨 appAccountToken 暂不传，理由见文件顶部注释。
                let result = try await product.purchase()
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
