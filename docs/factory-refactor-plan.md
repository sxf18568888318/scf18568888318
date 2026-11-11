# 工厂端拆分方案

## 一、现状

`app/factory-cloud.inc.js` 当前 **294 行**，约 126KB，是工厂端的核心文件。它包含了：

| 功能区域    | 主要内容                      | 大致行数         |
| ------- | ------------------------- | ------------ |
| 公共基础设施  | `fc` 状态对象、数据加载、工具函数、UI 辅助 | 1-52         |
| 订单 / 生产 | 首页看板、订单列表、订单详情            | 53-126       |
| 库存      | 五金/辅料库存、批量入库、库存流水         | 127, 230-231 |
| 考勤 / 工资 | 考勤登记、人员与工资                | 128-141      |
| 财务 / 利润 | 月年净利、固定费用、收付款流水           | 142-160, 231 |
| 表单与事件   | 所有弹窗表单、提交逻辑、事件监听、路由       | 161-294      |

问题：

- 所有功能挤在一个文件，改订单时容易误触考勤代码
- Codex 找相关函数困难
- 文件过大，IDE/编辑器加载慢

---

## 二、拆分目标

1. 按业务域把工厂端拆成多个文件
2. 每个文件职责单一，改哪里就找哪个文件
3. 保持现有页面效果、功能、数据接口完全不变
4. 构建流程不变，仍然用 `sync-quote-preview.ps1` 拼接

---

## 三、拆分后的文件结构

```
app/
  factory-cloud.inc.js              # 工厂端入口（保留公共状态 + 路由注册）
  factory-cloud-orders.inc.js       # 订单 / 生产
  factory-cloud-inventory.inc.js    # 库存 / 五金 / 辅料
  factory-cloud-attendance.inc.js   # 考勤 / 工资
  factory-cloud-finance.inc.js      # 财务 / 利润 / 固定费用
  factory-cloud-forms.inc.js        # 弹窗表单 / 事件监听 / 提交逻辑
```

---

## 四、每个文件的职责

### 1. factory-cloud.inc.js（入口 + 公共状态）

保留内容：

- `fc` 状态对象
- `fcClient`, `fcRpc`, `fcRead`, `fcLoad`, `fcLoadCosts` 等数据层
- `fcIsOwner`, `fcSafeRole`, `fcDateVal`, `fcMoney`, `fcHead`, `fcTable`, `fcEntry` 等公共工具
- `fcStageList`, `fcStageForProcess` 工序常量
- 页面路由注册：`pages.factory` 和 `render()` 工厂分支
- 权限控制：`canAccessPage` 工厂分支

不再包含：

- 具体的 `fcHome`, `fcProduction`, `fcOrderDetail` 等页面渲染函数
- 表单事件监听

### 2. factory-cloud-orders.inc.js（订单 / 生产）

包含函数：

- `fcDashboardOrders()` - 首页生产中订单
- `fcDashboardTasks()` - 首页待处理任务
- `fcHome()` - 工厂首页
- `fcProduction()` - 订单分类列表
- `fcOrderDetail()` - 订单详情页

### 3. factory-cloud-inventory.inc.js（库存）

包含函数：

- `fcInventoryLegacy()` - 旧库存页面
- `fcInventory()` - 新库存页面
- `fcBulkInventoryRow`, `fcBulkAppendRow`, `fcBulkCapture`, `fcBulkRestore` - 批量入库辅助

### 4. factory-cloud-attendance.inc.js（考勤 / 工资）

包含函数：

- `fcAttendance()` - 考勤登记
- `fcPayroll()` - 人员与工资

### 5. factory-cloud-finance.inc.js（财务 / 利润）

包含函数：

- `fcFinance()` - 月年净利、收付款
- `fcFixedCosts()` - 固定费用登记

### 6. factory-cloud-forms.inc.js（表单 / 事件）

包含函数：

- `fcDenied()` - 无权限提示
- `fcForm`, `fcField`, `fcSelect` - 表单基础
- `fcOpenForm()` - 所有弹窗分发
- `fcPurchaseFileKey`, `fcPurchaseAttachFiles`, `fcPurchaseBlankInvoice`, `fcPurchaseNew`, `fcPurchaseMaterials`, `fcPurchaseRow`, `fcPurchaseActive`, `fcPurchasePreview`, `fcPurchaseRelease`, `fcPurchaseRenderQueue`, `fcPurchaseRenderStatus`, `fcPurchaseSyncForm`, `fcPurchaseReadLines`, `fcPurchaseUpdateTotal`, `fcPurchaseValidate`, `fcPurchaseMime`, `fcPurchaseRead`, `fcPurchaseReadInvoice`, `fcPurchaseUpload`, `fcPurchaseSubmit` - 采购单相关
- `fcConfigRequest`, `fcSaveConfigProfile` - 材料配置
- `fcOrdersOpts` - 订单选项
- `fcCashUploadProofs`, `fcSubmitRpc`, `fcExport` - 提交与导出
- 所有 `document.addEventListener` 事件监听
- 预览入口逻辑

---

## 五、状态共享策略

`factory-cloud.inc.js` 中定义的状态对象 `fc` 和工具函数目前都在一个块级作用域 `{...}` 内。拆成多个文件后，需要让它们能互相访问。

### 推荐做法：把核心状态挂到全局命名空间

把：

```javascript
const fc = { ... };
```

改成：

```javascript
window.__ANJU_FACTORY__ = window.__ANJU_FACTORY__ || {};
const fc = window.__ANJU_FACTORY__;
if(!fc.initialized){ Object.assign(fc, { ...初始状态... }); fc.initialized=true; }
```

所有工厂文件都通过 `const fc = window.__ANJU_FACTORY__;` 访问同一个状态对象。

公共工具函数也挂到全局：

```javascript
window.__ANJU_FACTORY_UTILS__ = {
  fcClient, fcRpc, fcRead, fcFail, fcToday, fcMonth, fcReq,
  fcIsOwner, fcSafeRole, fcDateVal, fcMoney, fcHead, fcTable, fcEntry,
  fcStageList, fcStageForProcess, fcProofButtons
};
```

其他文件使用时：

```javascript
const { fcIsOwner, fcMoney, fcTable } = window.__ANJU_FACTORY_UTILS__;
const fc = window.__ANJU_FACTORY__;
```

### 好处

- 文件之间可以独立存在
- 不破坏现有拼接架构
- 后续如果迁移到 ES modules，也容易改造

### 风险

- 全局变量增加，需要确保命名不冲突
- 需要一次性改动多个地方

---

## 六、构建脚本调整

`app/sync-quote-preview.ps1` 中，把 `factory-cloud.inc.js` 的拼接顺序从单个文件改为按顺序拼接 6 个文件：

```powershell
$jsFiles = @(
    'factory-cloud.inc.js',
    'factory-cloud-orders.inc.js',
    'factory-cloud-inventory.inc.js',
    'factory-cloud-attendance.inc.js',
    'factory-cloud-finance.inc.js',
    'factory-cloud-forms.inc.js',
    # ... 其他文件
)
```

---

## 七、实施步骤

1. 创建 5 个新文件
2. 把 `factory-cloud.inc.js` 中的内容按上述方案迁移
3. 把 `fc` 和工具函数改为全局命名空间访问
4. 更新 `sync-quote-preview.ps1` 源文件清单
5. 更新 `DEVELOPMENT.md` 文件归属说明
6. 运行 `npm run build` 验证
7. 本地预览测试工厂端所有页面
8. 提交到 GitHub 新分支

---

## 八、注意事项

1. **不要改业务逻辑**：这次拆分只是搬家，不改功能
2. **保持函数名不变**：确保事件监听和路由调用能找得到函数
3. **测试覆盖**：首页、订单列表、订单详情、库存、考勤、工资、财务、固定费用、所有弹窗表单都要点一遍
4. **权限测试**：老板账号、厂长账号、设计师/工长账号都要测试
5. **工厂端页面入口不变**：仍然是 `module='factory'`, `page='home'` 等

---

## 九、预期效果

拆完后：

- 每个文件 40-80 行，大小可控
- 改订单找 `factory-cloud-orders.inc.js`
- 改库存找 `factory-cloud-inventory.inc.js`
- 改考勤工资找 `factory-cloud-attendance.inc.js`
- 改财务利润找 `factory-cloud-finance.inc.js`
- 改表单交互找 `factory-cloud-forms.inc.js`

Codex 以后改工厂端功能时，定位源文件会清晰很多。
