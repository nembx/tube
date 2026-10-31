# Tube App

本目录包含 iOS 17+ / macOS 14+ 原生应用和共享 TubeKit。

在仓库根目录执行 `bash scripts/build.sh project`，然后打开 `app/Tube.xcodeproj`。选择 `Tube-iOS` 或 `Tube-macOS` scheme。

构建与测试见 `scripts/build.sh`，发版流程见 `.github/workflows/build.yml` 与 `scripts/bump_version.sh`；DanDanPlay / Bangumi 凭证填入 `app/LocalSecrets.xcconfig`（参考同目录 example 文件）。
