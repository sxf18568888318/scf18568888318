# 安居经营台 Supabase 后端

项目：`quindxekbhpgymxfzixs`（`https://quindxekbhpgymxfzixs.supabase.co`）

> 说明：这是新建的 Supabase 项目。旧项目 `folyrnwwxbtcejsavgpf` 仍保留，但不再作为网站默认连接。

## 已完成

- PostgreSQL 业务表、角色视图和 RLS 策略
- `project-files` 私有 Storage 桶
- 设计师、工长、厂长、老板的数据库访问边界
- 登录后按 `app_metadata.role` 进入预览

## 创建测试账号

打开：<https://supabase.com/dashboard/project/quindxekbhpgymxfzixs/auth/users>

选择 **Add user → Create new user**，不要选邀请邮件。四个账号使用下面的邮箱，密码可统一填一个仅供验收的测试密码，并勾选 **Auto Confirm User**：

| 账号邮箱 | 角色 |
|---|---|
| `anju.owner@qq.com` | 老板 |
| `anju.designer@qq.com` | 设计师 |
| `anju.foreman@qq.com` | 工长 |
| `anju.factory@qq.com` | 厂长 |

数据库触发器会按邮箱自动写入 `app_metadata.role` 和 `public.profiles.role`，不需要在前端选择角色。创建完成后可在用户详情的 App Metadata 中核对 `role`。

## 预览

- 云端权限预览：`http://127.0.0.1:8765/index.html`
- 旧演示模式（仅本机样例数据）：`http://127.0.0.1:8765/index.html?demo=1`

业务记录从 localStorage 迁移到云端的工作会在四个账号权限验收通过后继续，避免在权限未确认时扩展报价和业务页面。

## Excel 口径确认（2026-10-09）

字段、下拉选项和公式以两份 Excel 模板中实际可见的表头、数据验证和公式为准。

库存结存暂按表内实际公式执行：

`期末结存 = 期初库存 + 本期入库 - 本期出库`

`结存金额 = 期末结存 × 参考单价`

说明页提到的“移动加权平均”以及退料、盘盈、盘亏的自动计入，暂不覆盖实际表内公式；如以后启用，需要单独升级库存成本口径并重新验收。
