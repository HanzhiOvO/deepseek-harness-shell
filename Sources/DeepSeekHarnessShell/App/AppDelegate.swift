import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // 回前台时同步一次本地历史会话（SessionStore 内部有 5 秒节流与变更缓存）。
        Task { @MainActor in
            await AppModel.shared?.sessionStore.sync()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 默认关闭窗口即退出并停掉 Node 服务，避免后台能耗；
        // 用户可在设置里改为「关闭窗口后保持服务」。
        AppModel.shared?.settings.stopWhenClosed ?? true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
