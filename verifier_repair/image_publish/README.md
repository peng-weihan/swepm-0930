# Docker Hub 镜像发布记录

2026-10-07：两个修复镜像已发布到公开仓库 [raymone23/swepm-0930](https://hub.docker.com/r/raymone23/swepm-0930)。

| 题目 | 新镜像引用 |
| --- | --- |
| `RakuenSoftware__aimee-c_1c60c9c` | `docker.io/raymone23/swepm-0930:aimee-1c60c9c-env-20261003-r2` |
| `apache__devlake-8877` | `docker.io/raymone23/swepm-0930:devlake-8877-env-20261003-r2` |

## 验证

- 两个镜像均推送成功，并使用空 Docker 登录配置实际拉取成功。
- 匿名访问检查覆盖镜像 manifest、配置和全部 layer 的存在性。
- 拉取后的镜像 ID、root filesystem layer 列表与本地已验证的修复镜像一致。
- SHA256 digest、推拉记录见 [publication-result.json](publication-result.json) 和 [anonymous-pull-verification.json](anonymous-pull-verification.json)。

## Benchmark 更新范围

本地 `v2-0930-verifier-r1/harbor/` 和物理机 `/data/swepmv2-harbor-runtime/datasets/v2-0930-verifier-r1/tasks/` 中，两题的 `task.toml` 与 `environment/Dockerfile` 已更新。

本地与物理机的 `verifier_repair/build_tasks.py` 对应生成逻辑已同步为新引用。其他 80 题的全部文件指纹保持不变。

两题的测试、参考答案、题面和镜像内容保持原样。本次没有重跑 Oracle/no-op；已有验证对应同一镜像内容。镜像地址文本变化导致任务文件指纹变化，前后映射见 [image-reference-migration.json](image-reference-migration.json)。历史验证快照未改写。

本地与物理机的 82 题文件指纹、TOML 解析、生成脚本一致性检查见 [migration-checks.json](migration-checks.json)。

## 拉取

```bash
docker pull raymone23/swepm-0930:aimee-1c60c9c-env-20261003-r2
docker pull raymone23/swepm-0930:devlake-8877-env-20261003-r2
```

## 凭据与维护

Docker Hub 用户名为 `raymone23`。推送凭据保存在 `10.161.41.9` 的 `/root/.docker/config.json`，权限为 `0600`。公开拉取无需此凭据。本目录不包含令牌。

发布操作脚本是 [publish_dockerhub.py](publish_dockerhub.py)，使用物理机已保存的 Docker 登录配置；发布过程与日志保存在物理机 `/data/swepmv2-harbor-runtime/repairs/v2-0930-verifier-r1/image_publish/`。原本地镜像标签仍保留。
