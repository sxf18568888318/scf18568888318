# 艺匠全屋定制经营台 · 开发手册

> 本手册说明如何正确修改本项目，避免"改生成文件被覆盖"的问题。

## 一、重要原则

1. **不要直接改 `framework-preview.js` 和 `framework-preview.css`**
   - 这两个文件是 `sync-quote-preview.ps1` 脚本拼接生成的。
   - 改完源文件后必须重新运行脚本，生成文件才会更新。

2. **改功能，改 `.inc.js` / `.logic.js` / `.css` 源文件**
   - 每个源文件顶部已有注释，写明它属于哪个业务域。
   - 修改前先定位到正确的源文件，不要在生成文件里找。

3. **改完必须跑构建脚本**
   - PowerShell: `powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-quote-preview.ps1`
   - npm: `npm run build`

## 二、项目结构

```
app/
  framework-preview.html      # 入口 HTML（可直接改）
  framework-preview.js        # 【生成文件】JS 产物，不要手动改
  framework-preview.css       # 【生成文件】CSS 产物，不要手动改
  sync-quote-preview.ps1      # 构建脚本：拼接 JS/CSS 并发布到 dist
  start-local-preview.ps1     # 本地预览脚本
  package.json                # npm 脚本入口

  # === 源文件（按业务域分组）===
  # 公共 / 跨模块
  business-accounts.inc.js
  practical-usability.inc.js
  requested-refinements.inc.js
  screenshot-navigation.inc.js
  role-gates.inc.js
  workflow-restoration.logic.js
  cloud-draft.logic.js

  # 整装业务
  quote-workshop.inc.js
  custom-quote-workshop.inc.js       # 报价引擎（整装/定制共用）
  renovation-workflow.inc.js
  reno-cloud-owner.inc.js
  reno-cloud-staff.inc.js
  bill-workbench.inc.js              # 采购单/账单（工厂/整装共用）

  # 全屋定制业务
  custom-quote-refinements.inc.js
  custom-catalog-bom.logic.js
  custom-catalog-bom.inc.js
  custom-procurement.inc.js
  custom-cloud-drafts.inc.js

  # 工厂业务
  factory-operations.inc.js
  factory-refinements.inc.js
  factory-efficiency.inc.js
  factory-document-versions.inc.js
  factory-cloud.inc.js

  # 独立入口（不参与拼接）
  auth-gate.js                       # 登录认证
  account-admin.js                   # 账号管理
  app.js                             # 单机试用版入口
  index.html                         # 单机试用版
  styles.css                         # 单机试用版样式

docs/                                # 文档
supabase/                            # 数据库迁移
share-preview-site/dist/             # 发布目录
```

## 三、构建流程

```
修改 .inc.js / .logic.js / .css 源文件
           |
           v
  运行 sync-quote-preview.ps1
           |
           v
  生成 framework-preview.js
  生成 framework-preview.css
  语法检查通过
           |
           v
  同步到 share-preview-site/dist/
  替换 __ASSET_VERSION__ 缓存戳
           |
           v
  本地预览 / Netlify 发布
```

### 运行方式

**方式一：PowerShell（推荐）**

```powershell
cd app
powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-quote-preview.ps1
```

**方式二：npm**

```bash
cd app
npm run build
```

**方式三：本地预览（构建 + 启动 http-server）**

```powershell
cd app
.\start-local-preview.ps1
```

## 四、文件归属速查表

| 如果你想改... | 找这个源文件 | 说明 |
|--------------|------------|------|
| 经营总览 / 月净利看板 | `business-accounts.inc.js` | 老板首页数据卡片 |
| 整装报价工作台 | `quote-workshop.inc.js` | 基础报价 / 主材报价 |
| 整装工地流程 / 节点 | `renovation-workflow.inc.js` | 工地阶段、照片 |
| 整装云端业主视图 | `reno-cloud-owner.inc.js` | 老板看整装云端数据 |
| 整装云端员工视图 | `reno-cloud-staff.inc.js` | 设计师/工长视图 |
| 全屋定制报价 | `custom-quote-workshop.inc.js` | 定制柜体报价核心 |
| 全屋定制产品库 / BOM | `custom-catalog-bom.inc.js` + `.logic.js` | 材料、五金目录 |
| 全屋定制采购 | `custom-procurement.inc.js` | 采购单管理 |
| 工厂订单 / 生产任务 | `factory-cloud.inc.js` | 工厂核心，最大文件 |
| 工厂库存 | `factory-cloud.inc.js` | 五金与辅料 |
| 工厂考勤 / 工资 | `factory-cloud.inc.js` | 工人、薪资 |
| 工厂费用 / 利润 | `factory-cloud.inc.js` + `business-accounts.inc.js` | 成本、收款、利润 |
| 采购单识别 / 录入 | `bill-workbench.inc.js` | 单据 OCR、核对 |
| 登录界面 / 权限 | `auth-gate.js` + `role-gates.inc.js` | 不参与拼接 |
| 账号管理弹窗 | `account-admin.js` | 不参与拼接 |

## 五、修改规范

1. **小步修改，一次只改一个功能点**
2. **改前先定位源文件**：先看文件顶部的 `Domain:` 注释
3. **不要删除或移动 marker 注释**：
   - `app/framework-preview.js` 中的：
     - `// Included inside the preview`
     - `// Give owners explicit split views`
   - `app/framework-preview.css` 中的：
     - `/* Room-based quotation workspace. */`
4. **改完后必跑构建脚本**，确认 JS 语法检查通过
5. **提交前检查 git status**：只应看到源文件改动，不要手动编辑 `framework-preview.js`

## 六、给 Codex / AI 的提示模板

以后让 Codex 改功能时，可以这样描述：

> 修改 `app/xxx.inc.js`（业务域：xxx）中的 `functionName` 函数，实现 xxx 功能。
> 不要改 `framework-preview.js`。
> 改完后提醒我运行 `npm run build`。

## 七、常见问题

### Q: 为什么改了代码，刷新页面没变化？

A: 大概率是没跑 `sync-quote-preview.ps1`。源文件改动不会自动同步到 `framework-preview.js` 和 `dist/`。

### Q: 可以只改 `framework-preview.js` 吗？

A: 不可以。下次跑脚本时，你的改动会被源文件重新覆盖。

### Q: 想在生成文件里临时调试怎么办？

A: 可以临时在浏览器开发者工具里改，或者临时改 `framework-preview.js` 看效果。但确认方案后，**必须**把改动回写到对应的 `.inc.js` 源文件，否则下次构建会丢失。

### Q: `factory-cloud.inc.js` 太大了，能不能拆？

A: 这是后续重构目标。当前阶段先用本手册规范修改流程；等业务稳定后，再考虑把它拆成更小的模块文件。

## 八、后续优化方向

1. **短期**：继续按本手册规范开发，减少改错文件的情况。
2. **中期**：将 `factory-cloud.inc.js` 等超大文件按功能拆小（生产、库存、考勤、财务）。
3. **长期**：引入 ES modules + Vite，彻底替换 PowerShell 拼接脚本。
