# 工厂识别、凭证与操作体验实施计划

> For agentic workers: use the executing-plans skill to implement the tasks inline. Each task is independently reviewable.

**Goal:** 完成用户确认的工厂单据、收付、资料、库存工资和侧栏调整，并通过 Git 推送触发线上部署。

**Architecture:** 延用现有工厂云端 RPC 和 Supabase Storage。图片在浏览器预处理并 OCR；收款凭证存入独立私有桶，由 owner-only RPC 关联流水；其他视图沿用现有角色过滤与数据表。

**Tech Stack:** JavaScript、CSS、PowerShell 静态同步脚本、Supabase Postgres/Storage、Netlify Git CD。

**Spec:** docs/superpowers/specs/2026-10-17-factory-scan-cash-layout-design.md

## Global Constraints

- 厂长主要操作采购成本；识别不得跳过人工核对或自动入账。
- 订单、采购附件及收款凭证留在 Supabase 云端，不改写现有真实业务账。
- owner 可读写金额与收款凭证；factory_manager 不获得利润/工资或收款凭证读取权限；designer/foreman 维持现有只读范围。
- 不提交 .env、账号密码、token 或真实附件。
- 生产站点通过推送 main 触发 Git 连续部署；不使用一次性手工部署覆盖 Git CD。

## Review Focus

- 低清/旋转图片与零识别结果仍可人工补录，且不会误入账。
- 多页采购单移除、重复选择、部分上传失败均保留可恢复状态。
- 保存后订单档案和当前锚点不丢失。
- 现金凭证不可经 Storage URL 或工厂订单 API 被厂长/设计师/工长读取。
- 工资调整、固定人工、成本与现金付款不重复计算。

### Task 1: 采购 OCR 和逐张校对布局

Files: app/renovation-workflow.inc.js, app/factory-cloud.inc.js, app/factory-cloud.css

- [x] 在线上同一解析链中保留 Excel/CSV 结构读取和 PDF 文本优先流程。
- [x] 图片按旋转设置绘制为高分辨率灰度/对比度增强图，识别并返回置信度。
- [x] 低置信、漏明细和零结果提示人工核对；不得自动保存。
- [x] 把横向超宽明细改成响应式行卡片；保留图片预览、手动金额核对和文件/单据删除。
- [x] 核对生成的框架脚本语法。

### Task 2: 保存后回到当前订单档案与附件可访问

Files: app/factory-cloud.inc.js, app/factory-cloud.css

- [x] 采购保存前记录订单 ID、路由、滚动和锚点；成功后重载并恢复档案。
- [x] 本户资料/配置表单采用窄屏自适应布局；“规格工艺”改为“备注”，字段仍与已存 JSON 兼容。
- [x] 核对角色可见的附件操作沿用私有文件访问。

### Task 3: 收款凭证云端存储

Files: 新增 Supabase migration、app/factory-cloud.inc.js、app/factory-cloud.css

- [x] 新建私有凭证 bucket 与受限的 Storage read/upload/delete policy；老板读取凭证，厂长只上传且只能清理自己订单下未关联的失败上传，已关联凭证不可从 Storage 删除。
- [x] 为现金流水增加凭证元数据；新增角色受限写 RPC 与 owner-only 流水读 RPC。
- [x] 表单上传后才提交关联 RPC；失败时尽力删除未关联孤立上传，允许继续手工登记。
- [x] 流水提供短期签名预览/下载；非 owner 不渲染且后端拒绝访问。
- [x] 使用项目既有 tools/run_sql.py 路径应用生产 DDL，并通过 Supabase 查询确认表、函数、桶和策略存在。

### Task 4: 完工欠款、现金与利润说明

Files: app/factory-cloud.inc.js, app/factory-cloud.css

- [x] 完工订单按累计实收计算尾款待收并标红。
- [x] 放大阶段/类型/客户/约定金额/实收/应收/操作的视觉层级。
- [x] 标出订单成本、现金付款、预计毛利和实收现金各自口径，保持互不自动改账。

### Task 5: 库存和工资边界

Files: app/factory-cloud.inc.js, app/factory-cloud.css

- [x] 五金扫描将未匹配名称保留为可编辑行；可以跳转创建物资档案再继续入库，并清除重复添加行监听。
- [x] 工资页提供特殊情况增减项，调用现有 owner_adjust_factory_payroll，显示本月合计。
- [x] 保持月薪/日薪/计件规则及公共费用的按月、按年、一次性分摊口径；净利仅展示月度固定人工汇总。

### Task 6: 清理摘要与侧栏入口

Files: app/factory-cloud.inc.js, app/factory-cloud.css, app/auth-gate.css

- [x] 删除重复且不能编辑的摘要卡/标签。
- [x] 把“设置”“管理账号”改为侧栏内纵向全宽按钮，按角色显示，不裁切标签。

### Task 7: 打包、迁移、上线

Files: generated app/framework-preview.js, app/framework-preview.css, share-preview-site/dist/*

- [x] 运行既有同步脚本；读取输出并确认 JavaScript 语法检查成功。
- [x] 确认 migration 内容与新增权限规则一致，不含敏感值。
- [x] 将实现提交推送到 GitHub `main`，留作代码备份。
- [x] 确认 Netlify 部署 `6ad306c5708229a03591ec05` 状态为 ready，并通过生产 URL 核对新资源版本可访问。

## 部署记录

2026-10-17：GitHub `main` 更新至实现提交 `d41c8a1`。推送后生产站点仍返回旧资源版本，因此本次从同一仓库工作目录上传到已连接的 Netlify 站点完成发布；新部署状态为 `ready`，生产资源版本为 `20261017132149`。本次网站内容已发布；Netlify 是否会对今后的 Git 提交自动构建，仍需在项目控制台核实。

## Verification note

项目规则禁止我在未被要求时增加或运行测试；使用既有同步脚本的 JavaScript 语法检查、Supabase 查询和部署状态作为本次验证证据。
