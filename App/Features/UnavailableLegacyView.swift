// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct UnavailableLegacyView: View {
    var body: some View {
        List {
            Section("受保护的设备配置") {
                Text("真实 MobileGestalt 本机读写、实时监控、系统备份与系统回滚：普通应用不能访问受保护的系统缓存。")
                Text("国行一键解锁、Apple 智能与 Siri 能力写入、eSIM、地区、WAPI、设备身份及显示标记：原操作依赖受保护缓存写入。")
            }
            Section("系统外观及其他应用") {
                Text("锁屏文字、系统壁纸包、钱包卡面、拨号盘或密码键盘资源写入：没有适用于本应用的 Apple 公开写入权限。")
                Text("其他应用启动图和通知音替换、跨应用文件浏览和缓存清理：原路径依赖访问其他应用的受保护容器。")
            }
            Section("设备连接") {
                Text("设备自配对及其通知音捕获流程未接入。此构建不会生成、使用或导入用于提高权限的配对记录。")
            }
        }
        .navigationTitle("不支持的旧版功能")
    }
}
