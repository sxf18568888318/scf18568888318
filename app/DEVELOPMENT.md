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
  # 工厂云端块：以下 6 个是【拼接片段】，必须相邻且按此顺序排列
  # Part 1 打开代码块，Part 6 闭合代码块；单独打开某个文件语法不完整属于正常现象
  factory-cloud.inc.js               # Part 1/6 核心状态、数据加载、公共工具
  factory-cloud-orders.inc.js        # Part 2/6 首页看板、订单分类、订单详情
  factory-cloud-attendance.inc.js    # Part 3/6 旧库存页、考勤登记、人员工资
  factory-cloud-finance.inc.js       # Part 4/6 月/年净利、经营账户
  factory-cloud-forms.inc.js         # Part 5/6 弹窗表单、采购单识别、提交、导出
  factory-cloud-runtime.inc.js       # Part 6/6 库存/固定费用页、路由、权限、事件监听

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
| 工厂首页 / 生产总览 | `factory-cloud-orders.inc.js` | fcHome、今日待办 |
| 工厂订单分类 / 订单详情档案 | `factory-cloud-orders.inc.js` | fcProduction、fcOrderDetail |
| 工厂云端数据加载 / 公共工具 | `factory-cloud.inc.js` | fcLoad、fcRpc、fcMoney 等 |
| 工厂库存（五金 / 辅料） | `factory-cloud-runtime.inc.js` | fcInventory；旧版在 `factory-cloud-attendance.inc.js` |
| 工厂批量入库 / 板材单 / 五金单 | `factory-cloud-forms.inc.js` | fcBulk*、fcPurchase* 全套 |
| 工厂考勤 / 人员工资 | `factory-cloud-attendance.inc.js` | fcAttendance、fcPayroll |
| 工厂固定费用登记 | `factory-cloud-runtime.inc.js` | fcFixedCosts |
| 工厂月 / 年净利 | `factory-cloud-finance.inc.js` | fcFinance |
| 工厂收付款 / 凭证 / 导出 | `factory-cloud-forms.inc.js` | fcCashUploadProofs、fcExport |
| 工厂菜单 / 权限 / 按钮事件 | `factory-cloud-runtime.inc.js` | pages.factory、render、事件监听 |
| 采购单识别 / 录入（整装） | `bill-workbench.inc.js` | 单据 OCR、核对 |
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
6. **工厂端 6 个片段文件必须相邻且保持顺序**（见 `sync-quote-preview.ps1` 的 `$jsSources`），
   Part 1 打开代码块、Part 6 闭合；中间插入其他文件或调换顺序会导致构建失败

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

### Q: 单独打开某个 `factory-cloud-*.inc.js` 文件，编辑器报语法错误？

A: 正常现象。这 6 个文件是**同一个代码块的拼接片段**，不是独立 JS 文件：
Part 1 里有一个 `{` 开头，Part 6 末尾才有对应的 `}`。只有按 `sync-quote-preview.ps1`
的顺序拼接后才是完整代码。不要单独对它们跑 `node --check`，构建脚本会检查最终产物。

### Q: 工厂端已经拆好了吗？

A: 已拆分。原 `factory-cloud.inc.js`（126KB）按函数边界切成 6 个片段，
拼接顺序不变、可执行代码零改动。改功能时按第四节速查表定位对应片段即可。

## 八、后续优化方向

1. **短期**：按本手册规范开发；工厂端已拆分，接下来可继续规范门店端。
2. **中期**：门店端（整装 / 全屋定制）同样存在超大文件，可按相同方式拆分。
3. **长期**：引入 ES modules + Vite，彻底替换 PowerShell 拼接脚本。
