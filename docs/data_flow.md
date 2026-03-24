# 数据流设计文档

## 集合内容加载流程

进入集合页面时，采用「本地优先 + 后台同步」策略：

1. 读取本地缓存的 BID 列表，立即渲染已有内容
2. 后台调 `/block/link/main/bids_by_targets` 拉取最新 BID 列表，更新本地缓存
3. 找出本地缺失的 block 详情，分批调 `/block/block/multiple` 补全
4. 同步完成后刷新列表，右上角转圈指示同步中

同时，后台调 `/block/block/get` 拉取集合自身最新数据（含 `link_tag` 等字段），更新本地缓存。

---

## link_tag 筛选流程

集合详情页标题下方展示 `link_tag`（链接标签），点击标签触发筛选：

### Step 1 — 本地即时筛选（瞬间响应）

- 从本地已缓存的全量 BID 列表中，遍历每个 block 的 `link_tag` 字段
- 筛选出包含目标 tag 的 BID，立即渲染列表
- 用户点击后无需等待网络，UI 瞬间更新

### Step 2 — 后台服务器同步（保证准确）

- 以 `unawaited` 方式异步调用 `/block/link/main/bids_by_targets`，传入 `tag` 参数
- 服务器返回最新筛选结果后，补全本地缺失的 block 详情
- 再次刷新列表，右上角转圈指示同步中
- 筛选结果不覆盖本地全量 BID 缓存

### 取消筛选

再次点击已激活的 tag，恢复全量列表（重新走集合内容加载流程）。

---

## 相关接口

| 接口 | 用途 |
|------|------|
| `GET /block/block/get` | 获取单个 block 最新数据 |
| `POST /block/link/main/bids_by_targets` | 批量获取集合外链 BID 列表，支持 `tag` 筛选 |
| `POST /block/block/multiple` | 批量获取 block 详情 |
| `POST /block/write/simple` | 创建或更新 block |

---

## 相关文件

| 文件 | 职责 |
|------|------|
| `lib/providers/note_provider.dart` | 状态管理，协调本地与远端数据 |
| `lib/services/note_service.dart` | 网络请求与本地缓存操作封装 |
| `lib/services/note_local_store.dart` | SharedPreferences 持久化 |
| `lib/screens/notes_list_screen.dart` | 集合详情页 UI |
