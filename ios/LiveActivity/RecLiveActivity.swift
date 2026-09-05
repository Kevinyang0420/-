import ActivityKit
import SwiftUI
import WidgetKit

/// 灵动岛上的那一小条。**内容故意做到最简** ——
/// 它的价值是「让主 App 有一个持续存在」，不是好看。
@available(iOS 16.1, *)
struct RecLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecActivityAttributes.self) { ctx in
            // 锁屏 / 通知中心 / 刚弹出的横幅：做成一个**大按钮**，他一眼能点。
            //    测 B：用户【点】这个 AudioRecordingIntent，看后台给不给麦克风
            //    （push-to-start 自动 begin 已证伪＝输入源0；这一版专测「人点一下」这条正门）。
            if #available(iOS 18.0, *) {
                Button(intent: StartRecIntent()) {
                    HStack(spacing: 12) {
                        Image(systemName: "mic.circle.fill")
                            .font(.system(size: 34))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("点这里开始录音").font(.headline)
                            Text("Transless · 不离开当前 App").font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(ctx.state.seconds) + "s").font(.title3).monospacedDigit()
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                }
                .tint(.red)
            } else {
                HStack {
                    Image(systemName: "mic.fill")
                    Text(ctx.state.phase)
                    Spacer()
                    Text(String(ctx.state.seconds) + "s")
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
            }
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "mic.fill")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(ctx.state.phase)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(String(ctx.state.seconds) + "s")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // 🚨 这个按钮是**验证用的触发点**：它跑的 Intent 会在
                    //    「App 在后台」的情况下起录 —— 正是要验的那件事。
                    //    产品形态里这一步将由 push-to-start 自动完成，不用他点。
                    if #available(iOS 18.0, *) {
                        Button(intent: StartRecIntent()) {
                            Label("点这里开始录音", systemImage: "mic.circle.fill").font(.title3)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
            } compactTrailing: {
                Text(String(ctx.state.seconds) + "s")
            } minimal: {
                Image(systemName: "mic.fill")
            }
        }
    }
}

@main
struct TranslessWidgets: WidgetBundle {
    var body: some Widget {
        if #available(iOS 16.1, *) { RecLiveActivity() }
    }
}
