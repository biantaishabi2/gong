import Config

# 关闭 tzdata 自动轮询更新，避免 CLI 会话中输出无关日志噪音。
# 需要手动更新时可在运维流程中显式开启并执行更新。
config :tzdata, :autoupdate, :disabled
