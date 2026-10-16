# 一江金融平台

艺匠全屋定制经营与工厂协同平台。本仓库包含本地预览源码、Netlify 静态发布目录、Supabase 数据库迁移和工厂端操作说明。

## 目录

- `app/`：应用源文件与本地预览构建脚本
- `share-preview-site/dist/`：静态网站发布文件
- `supabase/migrations/`：数据库结构、RPC 和权限策略迁移
- `docs/factory-portal-guide.md`：工厂端角色权限、订单档案和费用流程
- `netlify.toml`：Netlify 静态发布目录与基础安全响应头
- `.env.example`：本地 Supabase 工具所需变量模板

## 本地预览

在 Windows PowerShell 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File app/sync-quote-preview.ps1
```

该脚本将应用源文件同步到 `share-preview-site/dist/` 并检查 JavaScript 语法。若本地预览服务已启动，刷新页面即可查看。

## 数据库迁移

Supabase 项目通过受控迁移维护。新迁移先使用 Supabase CLI 创建文件，再审核 SQL 的授权范围，最后通过已连接的 Supabase 项目应用。不要把 `.env`、访问令牌、服务角色密钥或真实客户资料提交到仓库。`.env` 已加入忽略规则；只提交 `.env.example`。

本版工厂端新增迁移：

- `20261017013000_factory_recurring_public_costs_and_documents.sql`
- `20261017021000_factory_purchase_storage_policy_guard.sql`

## 部署

Netlify 发布目录为 `share-preview-site/dist`。连接 Git 后由受控生产部署发布；部署后检查生产站点和权限。数据库迁移需先完成，再发布依赖新 RPC 的前端版本。

## 安全

- 不提交 `.env`、密钥、个人文件、缓存目录或临时截图。
- 私有工厂附件按订单授权读取；不要将 `factory-files` 存储桶改为公开。
- 生产部署前保留代码备份和 Supabase 迁移记录。
