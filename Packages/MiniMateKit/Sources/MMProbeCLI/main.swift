import Foundation

#if os(macOS)
let usageText = """
mm-probe — MiniMate M2a 厂商验证命令行工具（占位入口，具体子命令将在 Phase 3 T020 实现）

计划子命令：
  realtime        测试实时语音会话（只出文字 + VAD + 打断）
  tone-suite      运行 9 条语气样本套件评估语气理解准确率与延迟
  tts             测试情感 TTS 流式合成与情绪映射
  record-fixture  录制厂商协议回放夹具（自动脱敏鉴权头）

选项：
  -h, --help      显示此帮助信息
"""

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args == ["--help"] || args == ["-h"] {
    print(usageText)
    exit(0)
} else {
    fputs("未知参数：\(args.joined(separator: " "))\n请使用 --help 查看说明（子命令将在 Phase 3 T020 实现）。\n", stderr)
    exit(2)
}
#endif
