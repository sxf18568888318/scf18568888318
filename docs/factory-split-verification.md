# 工厂端拆分验证记录

验证日期：2026-11-11

## 改动内容

把原来的 `app/factory-cloud.inc.js`（126 KB / 294 行）按函数边界切成 6 个拼接片段：

| 顺序 | 文件 | 职责 |
|------|------|------|
| 1 | `factory-cloud.inc.js` | 核心状态、云端数据加载、公共工具函数 |
| 2 | `factory-cloud-orders.inc.js` | 首页看板、订单分类、订单详情档案 |
| 3 | `factory-cloud-attendance.inc.js` | 旧库存页、考勤登记、人员工资 |
| 4 | `factory-cloud-finance.inc.js` | 月 / 年净利、经营账户 |
| 5 | `factory-cloud-forms.inc.js` | 弹窗表单、板材单 / 五金单识别上传、提交、导出 |
| 6 | `factory-cloud-runtime.inc.js` | 库存与固定费用页、路由、权限、事件监听 |

同时更新：
- `app/sync-quote-preview.ps1`：把 1 个源文件替换为 6 个，按原顺序相邻排列
- `app/DEVELOPMENT.md`：更新项目结构、文件归属速查表、常见问题

## 为什么不用全局命名空间

最初方案考虑把 `fc` 状态和工具函数挂到 `window.__ANJU_FACTORY__`。
实际实施时改为**保留原有代码块结构**：Part 1 打开 `{`，Part 6 闭合 `}`，
中间片段只包含原来的代码行。这样不需要修改任何变量引用、不需要改函数名、
不需要调整作用域，风险最低。

代价：这 6 个文件是**拼接片段**，不是独立 JS 文件，单独打开会显示语法不完整。
这是正常的，构建脚本会把它们拼成完整代码。

## 验证结果

| 检查项 | 结果 |
|--------|------|
| 6 个片段按序拼接 vs 原文件 | 字节级完全一致（291 行正文逐行相同） |
| 代码块花括号配平 | 通过（0） |
| `npm run build` / 构建脚本 | 通过，输出 `[5/5] Build complete` |
| Node.js 语法检查 | 通过 |
| 拆分前构建 vs 拆分后构建（两份全新解压副本） | 可执行代码 **7243 行完全一致** |

结论：**本次拆分零业务改动**，页面效果、数据接口、按钮行为均保持不变。

## 重要约束

`sync-quote-preview.ps1` 的 `$jsSources` 中，这 6 个工厂片段**必须相邻且保持顺序**。
Part 1 打开代码块，Part 6 闭合；中间插入其他文件或调换顺序会导致构建失败。

## 遗留发现（本次未改动，需单独处理）

仓库中 `app/framework-preview.js` 与 `share-preview-site/dist/framework-preview.js`
与当前源文件**不同步**：生成产物里缺少 `cloud-draft.logic.js` 等一大段代码
（约 98 行可执行代码）。推测是之前修改源文件后没有重新运行构建脚本。

这意味着线上（Netlify 发布 `share-preview-site/dist`）跑的可能是较旧的代码。
建议单独安排一次"重新构建 + 发布产物"的提交，并在合并前确认线上行为没有异常。

另外，构建脚本 `Copy-StaticAsset` 使用 `Copy-Item -Recurse` 复制到已存在的目标目录，
重复构建会生成 `dist/vendor/vendor/`、`dist/assets/brand/brand/` 这类嵌套目录。
本次已清理，建议后续修一下脚本。
