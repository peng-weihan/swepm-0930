# 修复后的 82 个 Harbor instance

`harbor/` 保存 2026-10-07 发布的完整任务，每题包含题面、task.toml、环境 Dockerfile、verifier、测试资产和 Oracle 参考补丁。

本次发布与开发区当前 82 个任务逐文件一致。53 题有逐题专项修改；全部 82 题都应用了共用 verifier 流程修复。执行健康评估为 **60 题没问题、1 题有问题、21 题待定**。这个判断只覆盖明确的环境和 verifier 执行阻断，不等于所有测试契约均已认证。

- [逐题修改与健康报告](../verifier_repair/reports/20261007-instance-health/REPORT.md)
- [逐题 CSV](../verifier_repair/reports/20261007-instance-health/instances.csv)
- [发布任务索引与当前文件指纹](task-index.json)
- [发布校验](../verifier_repair/github-release-validation.json)
- [Docker Hub 镜像与拉取验证](../verifier_repair/image_publish/README.md)

## 镜像

两题使用已公开发布的环境修复镜像：

```text
docker.io/raymone23/swepm-0930:aimee-1c60c9c-env-20261003-r2
docker.io/raymone23/swepm-0930:devlake-8877-env-20261003-r2
```

其余 80 题保持既有镜像引用；完整列表见 `task-index.json`。Docker 镜像不存入 Git。两个新引用均验证了匿名拉取，并与原本地已验证镜像的内容、digest 一致。

镜像地址替换只改变了两题的配置文本指纹。[迁移证明](../verifier_repair/image_publish/image-reference-migration.json) 对应报告中的旧指纹；历史 Oracle/no-op 快照没有被改写，本次发布没有重跑求解或 verifier。

## 运行前准备

验证环境使用 Harbor 0.23.0；任务配置已有 `/testbed`、32 GiB 内存及独立 verifier。仍应按所选模型/harness准备认证与运行配置。

任务的 Compose 配置使用外部 Docker network `swepm-verifier-r1`，并指定 `pull_policy: never`。新执行机需要先准备镜像和该 network；请在实际 Docker 执行机上操作。下载全部镜像会占用较多空间，请先确认该机器的 Docker 数据目录与容量。

```bash
docker network inspect swepm-verifier-r1 >/dev/null 2>&1 || docker network create swepm-verifier-r1
python3 -c 'import json; print("\n".join(json.load(open("v2-0930-verifier-r1/task-index.json"))["unique_images"]))'
# 按打印出的列表拉取计划运行的镜像。
```

Enola-50 还挂载了一个固定版本的离线 Go 缓存。发布包内附带原 `regexp2 v1.12.0` 下载文件，准备脚本按任务中已有的绝对挂载路径安装；新增约 1.24 MB，不调用网络或包管理器。

```bash
python3 -B scripts/prepare_enola_cache.py              # 只检查包和显示写入位置
python3 -B scripts/prepare_enola_cache.py --install    # 在 Docker 执行机写入 /data 下的指定目录
```

安装会核对 SHA-256、Go module h1、全部展开文件；遇到内容不同的已有缓存会停止。此补充保持任务文件原样，避免发布时遗漏原执行机上已存在的必需缓存。

## 文件与历史记录

原始 `v2-0930/` 和已有实验轨迹仍保留为历史快照。报告中的远端绝对路径是证据来源，不表示全部历史验证 job 都随本次发布打包；本次包含逐题结果、343 条验证记录、207 条 Luna 记录的读取摘要与关键失败片段。

测试资产保持校验要求的原字节。凭据扫描中识别到的 Dex 固定 RSA 测试夹具已核对为上游公开测试文件中的同一内容；Free-Claude-Code-883 的字符串属于日志脱敏测试的合成输入。两者不是本次运行账号的认证凭据，详情见发布校验。
