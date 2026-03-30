# vps-bootstrap

用于新 VPS 的标准初始化仓库，当前聚焦：

- 非 root 管理用户
- SSH-only 登录
- 默认 sudo 免密码
- UFW 防火墙
- Fail2Ban
- Xray（VLESS + REALITY）

当前设计目标是：

1. 先把一台全新 VPS 快速拉到“可稳定使用”的状态。
2. 把所有操作固化为脚本和模板。
3. 后续让 agent 只改这个仓库，而不是直接在 VPS 上即兴操作。

## 使用前提醒

这是一个公开仓库，里面的用户名、端口、域名和配置值都是示例。

首次部署到真实 VPS 前，请至少确认这些内容已经按你的环境调整：

- 管理用户名，例如 `user`
- SSH 端口，例如 `22` 或 `2222`
- `.env` 中的 Xray 参数与密钥材料
- `REALITY_DEST` 和 `REALITY_SERVER_NAME`

更多说明见 [SECURITY.md](/Users/Zq/vps-bootstrap/SECURITY.md)。

## 一、工程定位

这是一个“首阶段可落地”的 VPS bootstrap 工程，不是大而全的运维平台。

当前只解决两件事：

1. 新机基础安全初始化
2. Xray VLESS REALITY 部署

边界刻意收紧：

- 不安装 Docker
- 不直接引入 Ansible
- 不做多主机 inventory
- 不在生产机上长期手改配置

这样做的目的是先把最小闭环跑通，再逐步演进。

## 二、目录结构

```text
vps-bootstrap/
├─ Makefile
├─ README.md
├─ .gitignore
├─ .env.example
├─ scripts/
│  ├─ initial.sh
│  ├─ harden-ssh.sh
│  ├─ install-xray.sh
│  ├─ gen-reality-secrets.sh
│  └─ generate-xray-config.sh
└─ templates/
   └─ xray-config.json.tpl
```

## 三、脚本职责

### `scripts/initial.sh`

负责新机底座初始化：

- 更新系统包
- 安装基础工具
- 创建 sudo 管理用户
- 配置免密码 sudo
- 写入 SSH 公钥
- 关闭 SSH 密码认证
- 启用 UFW
- 启用 Fail2Ban

它的目标是把机器一次拉到“安全可登录、可继续操作”的状态：

- 管理用户默认 `sudo` 免密码
- SSH 默认改为 key-only 登录

因此运行时必须传入可用的 SSH 公钥。

### `scripts/harden-ssh.sh`

负责第二阶段 SSH 加固：

- 可禁用 root SSH 登录
- 可选修改 SSH 端口
- 改端口时同步 UFW 和 Fail2Ban
- 先校验配置，再重启 SSH

由于 `initial.sh` 已默认禁用密码认证，因此这个脚本现在主要负责：

- 禁 root SSH 登录
- 调整 SSH 端口
- 同步 SSH 端口相关防护规则
- 做进一步收紧

### `scripts/install-xray.sh`

负责安装或升级 Xray，并启用 systemd 服务。

### `scripts/gen-reality-secrets.sh`

负责生成 REALITY 所需材料：

- UUID
- X25519 Private/Public key
- Short ID

### `scripts/generate-xray-config.sh`

负责把变量渲染成最终 Xray 配置，并执行：

- 变量校验
- 模板渲染
- Xray 配置测试
- 重启服务

它支持两种来源：

- 环境变量直接传入
- 从 `.env` 文件加载

## 四、推荐流程

### 0. 常用入口

仓库现在提供一个轻量 `Makefile`，用于统一执行入口。

先查看可用命令：

```bash
make help
```

本地快速检查脚本语法：

```bash
make check
```

### 1. 新机重装系统

建议重装成：

- Ubuntu 24.04
- 或 Debian 12

### 2. 本地准备 SSH key

如果你已经有 SSH key，可以跳过。

```bash
ssh-keygen -t ed25519 -C "user-vps"
cat ~/.ssh/id_ed25519.pub
```

复制输出的整行公钥，后面会用到。

### 3. 用 root 登录 VPS

```bash
ssh root@YOUR_VPS_IP
```

### 4. 拉仓库并执行底座初始化

```bash
git clone <YOUR_REPO_URL>.git
cd vps-bootstrap
make chmod
sudo make init USER=user PUBKEY="<你的SSH公钥整行内容>"
```

执行完成后，不要立刻关闭当前 root 会话，先新开一个终端验证管理用户登录。

### 5. 用管理用户重新登录

```bash
ssh user@YOUR_VPS_IP
```

### 6. 执行 SSH 加固

`initial.sh` 已经默认切到 SSH key-only 登录。

如果你还要进一步禁用 root SSH 登录，先确认你已经能用管理用户 + SSH key 正常登录，再执行：

```bash
cd vps-bootstrap
sudo make harden-ssh SSH_PORT=22 DISABLE_ROOT_LOGIN=true DISABLE_PASSWORD_AUTH=true
```

如果要顺便改 SSH 端口，比如改到 `2222`：

```bash
cd vps-bootstrap
sudo make harden-ssh SSH_PORT=2222 DISABLE_ROOT_LOGIN=true DISABLE_PASSWORD_AUTH=true
```

执行后请用新端口重新登录验证：

```bash
ssh -p 2222 user@YOUR_VPS_IP
```

### 7. 安装 Xray

```bash
cd vps-bootstrap
sudo make xray-install
```

### 8. 生成 REALITY 所需密钥材料

```bash
cd vps-bootstrap
sudo make xray-secrets
```

记录输出的：

- UUID
- Private key
- Public key
- Short ID

其中：

- 服务端配置需要：UUID、Private key、Short ID
- 客户端配置需要：UUID、Public key、Short ID

### 9. 使用环境变量生成服务端配置

```bash
cd vps-bootstrap

sudo XRAY_UUID="你的UUID" \
  REALITY_PRIVATE_KEY="你的PrivateKey" \
  REALITY_SHORT_ID="你的ShortID" \
  REALITY_DEST="www.cloudflare.com:443" \
  REALITY_SERVER_NAME="www.cloudflare.com" \
  make xray-config
```

### 10. 使用 `.env` 生成服务端配置

先基于样板生成本地配置：

```bash
cd vps-bootstrap
cp .env.example .env
```

编辑 `.env` 后执行：

```bash
cd vps-bootstrap
sudo make xray-config ENV_FILE=.env
```

### 11. 检查服务状态

```bash
sudo systemctl status xray --no-pager
sudo journalctl -u xray -n 50 --no-pager
```

## 五、客户端连接参数

服务端部署完成后，客户端通常需要这些参数：

- 地址：你的 VPS IP 或域名
- 端口：443
- 协议：VLESS
- UUID：你生成的 UUID
- Flow：xtls-rprx-vision
- 传输：tcp
- 安全：reality
- SNI / Server Name：你配置的 `REALITY_SERVER_NAME`
- Public Key：`xray x25519` 生成的 Public key
- Short ID：你生成的 Short ID

## 六、环境变量说明

`generate-xray-config.sh` 支持以下变量：

- `ENV_FILE`，默认不加载；若存在 `.env` 会优先自动加载
- `XRAY_PORT`，默认 `443`
- `XRAY_UUID`
- `REALITY_DEST`，默认 `www.cloudflare.com:443`
- `REALITY_SERVER_NAME`，默认 `www.cloudflare.com`
- `REALITY_PRIVATE_KEY`
- `REALITY_SHORT_ID`

示例：

```bash
sudo ENV_FILE=.env bash scripts/generate-xray-config.sh
```

或：

```bash
sudo XRAY_UUID="..." \
  REALITY_PRIVATE_KEY="..." \
  REALITY_SHORT_ID="..." \
  REALITY_DEST="www.cloudflare.com:443" \
  REALITY_SERVER_NAME="www.cloudflare.com" \
  bash scripts/generate-xray-config.sh
```

## 七、架构理解

这个工程当前的核心架构很简单：

- `scripts/` 放操作逻辑
- `templates/` 放配置模板
- `.env.example` 放参数样板
- `Makefile` 放统一入口
- `README.md` 放运行手册

也就是说：

- 人负责提供参数和执行时机
- 仓库负责承载可审计的自动化步骤
- agent 负责修改仓库，不直接长期操作生产机

这是一个“脚本仓库优先”的模型，而不是“临时登录服务器修机器”的模型。

## 八、迭代路线图

### Phase 1：先跑通

- `initial.sh`
- `install-xray.sh`
- `gen-reality-secrets.sh`
- `generate-xray-config.sh`

目标是让一台新机从裸机到 Xray 可用。

### Phase 2：补安全和配置管理

- `harden-ssh.sh`
- `.env` 加载
- 更明确的输入校验

目标是降低误操作风险，让 SSH 和配置管理更稳定。

### Phase 3：补工程化入口

- `Makefile`
- `check` / `lint` / `validate` 命令
- 配置样例拆分

目标是让执行入口更统一。

### Phase 4：多机与声明式

- `inventory`
- `hosts/<name>.env`
- Ansible 目录

目标是从单机脚本升级到多主机管理。

## 九、agent 使用原则

后续建议固定成这个原则：

- 所有变更都只改本仓库
- agent 负责改脚本、模板、文档、提交 PR
- 你负责审查 diff 并执行

不要让 agent 长期直接在生产 VPS 上“现改现配”。

这样整台 VPS 才是可重建、可审计、可回滚的。
