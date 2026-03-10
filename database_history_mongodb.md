# MongoDB 技术路线与四数据库对比

## 1. MongoDB 发展历程

### 1.1 发展时间线

| 年份 | 版本 | 里程碑 | 技术意义 |
|------|------|--------|----------|
| **2009** | 1.0 | 首个稳定版发布 | 文档数据库概念正式诞生，BSON 格式确立 |
| **2012** | 2.2 | 成为最流行 NoSQL 数据库 | 超越 CouchDB、Redis 等，获得开发者广泛采用 |
| **2015** | 3.0 | WiredTiger 存储引擎 | 引入文档级锁，性能提升 10 倍，支持压缩 |
| **2017** | 3.6 | 窗口函数、聚合优化 | 增强分析能力，管道性能提升 40% |
| **2018** | 4.0 | 多文档事务 | 支持 ACID 多文档事务，弥补 NoSQL 短板 |
| **2020** | 4.4 | 持久化事务日志 | 事务性能提升 10 倍，支持分布式事务 |
| **2023** | 7.0 | 查询优化、性能提升 | 查询性能提升 32%，引入时间旅行查询 |

### 1.2 关键技术演进详解

#### 2009 年：文档数据库概念的诞生

**背景**：
- 关系数据库的 schema 固定性无法适应快速迭代的互联网应用
- ORM 映射复杂，JSON 对象到关系表的转换损耗大
- 水平扩展需求迫切，但关系数据库分片困难

**MongoDB 的创新**：
```javascript
// 传统关系型需要预定义表结构
// CREATE TABLE users (id INT, name VARCHAR(50), email VARCHAR(100)...)

// MongoDB 直接存储文档
{
  _id: ObjectId("507f1f77bcf86cd799439011"),
  name: "张三",
  email: "zhangsan@example.com",
  addresses: [  // 原生支持嵌套数组
    { type: "home", city: "北京" },
    { type: "work", city: "上海" }
  ],
  created_at: ISODate("2009-10-01")
}
```

#### 2015 年：WiredTiger 存储引擎

**技术突破**：
- **文档级锁**：替代之前的集合级锁，并发性能提升 10 倍
- **LSM-Tree 变种**：写性能优化，适合高吞吐场景
- **压缩算法**：支持 Snappy、GZIP、ZSTD，存储节省 50-80%

**配置示例**：
```yaml
storage:
  wiredTiger:
    engineConfig:
      cacheSizeGB: 4
      journalCompressor: snappy  # snappy | gzip | zlib | zstd
    collectionConfig:
      blockCompressor: snappy
```

#### 2018 年：多文档事务

**实现原理**：
```javascript
// MongoDB 4.0+ 支持多文档 ACID 事务
const session = client.startSession();
session.startTransaction({
  readConcern: { level: "snapshot" },
  writeConcern: { w: "majority" }
});

try {
  await accounts.updateOne(
    { _id: "A" },
    { $inc: { balance: -100 } },
    { session }
  );
  await accounts.updateOne(
    { _id: "B" },
    { $inc: { balance: 100 } },
    { session }
  );
  await session.commitTransaction();
} catch (error) {
  await session.abortTransaction();
}
```

**技术细节**：
- 使用 MVCC（多版本并发控制）实现快照隔离
- 事务日志记录在 `local.system.sessions` 集合
- 支持跨分片事务（4.2+）

---

## 2. 四数据库完整对比

### 2.1 综合对比表格

| 维度 | MongoDB | MySQL | PostgreSQL | Redis |
|------|---------|-------|------------|-------|
| **数据模型** | BSON 文档 | 关系表 | 关系表+JSONB+ 数组 | 键值 + 数据结构 |
| **存储引擎** | WiredTiger | InnoDB | Heap+TOAST | 内存 |
| **事务支持** | 4.0+ 多文档 ACID | 完整 ACID | 完整 ACID+ 可串行化 | 单命令原子性 |
| **锁机制** | 文档级锁 | 行锁/表锁/元数据锁 | 谓词锁/行锁 | 单线程无锁 |
| **持久化** | Journal+WAL | Redo Log+Binlog | WAL | RDB+AOF |
| **扩展方式** | 分片 + 副本集 | 主从 + 分库分表 | 主从 + 插件 | Cluster 分片 |
| **典型延迟** | 1-10ms | 1-10ms | 1-10ms | 0.1-1ms |
| **最大数据量** | PB 级 | TB-PB 级 | TB-PB 级 | GB-100GB |
| **索引类型** | B-Tree、地理、文本 | B+Tree、全文 | B-Tree、GIN、GiST | 无索引 (键即索引) |

---

## 3. 数据模型对比

### 3.1 对比表格

| 数据库 | 数据模型 | Schema | 嵌套支持 | 类型系统 |
|--------|----------|--------|----------|----------|
| **MongoDB** | BSON 文档 | 动态/可选 | 原生支持 | 丰富 (数组、对象、日期等) |
| **MySQL** | 关系表 | 严格预定义 | 不支持 (需 JSON 列) | 标准 SQL 类型 |
| **PostgreSQL** | 关系表+JSONB | 严格 + 灵活 | JSONB 支持 | 最丰富 (数组、JSONB、自定义) |
| **Redis** | 键值 + 数据结构 | 无 | 不支持 | String/List/Set/Hash/ZSet |

### 3.2 详细分析

#### MongoDB：文档模型设计哲学

**设计哲学**：
- **数据局部性**：相关数据存储在同一个文档中，减少连接查询
- **灵活 Schema**：字段可随时添加，适合快速迭代
- **开发者友好**：BSON 格式与编程语言对象天然映射

**嵌套结构示例**：
```javascript
// 订单文档 - 所有相关信息存储在一起
{
  _id: ObjectId("..."),
  order_id: "ORD-2024-001",
  customer: {
    id: "CUST-001",
    name: "张三",
    email: "zhangsan@example.com"
  },
  items: [  // 订单项数组
    {
      product_id: "PROD-001",
      name: "iPhone 15",
      quantity: 1,
      price: 7999
    }
  ],
  shipping_address: {
    city: "北京",
    district: "朝阳区",
    detail: "xxx 街道 xxx 号"
  },
  status: "pending",
  created_at: ISODate("2024-01-01")
}
```

**适用场景**：
- ✅ 内容管理系统（CMS）
- ✅ 用户配置/偏好设置
- ✅ 物联网设备数据
- ✅ 快速原型开发

**不适用场景**：
- ❌ 需要复杂连接查询的场景
- ❌ 高度规范化的财务数据
- ❌ 需要严格数据完整性的场景

#### MySQL：关系模型设计哲学

**设计哲学**：
- **数据规范化**：消除冗余，保证数据一致性
- **ACID 优先**：事务完整性高于一切
- **成熟稳定**：30 年技术积累，生态完善

**规范化示例**：
```sql
-- 需要多表关联
CREATE TABLE customers (
  customer_id INT PRIMARY KEY,
  name VARCHAR(100),
  email VARCHAR(100)
);

CREATE TABLE orders (
  order_id INT PRIMARY KEY,
  customer_id INT,
  status VARCHAR(20),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
  item_id INT PRIMARY KEY,
  order_id INT,
  product_id INT,
  quantity INT,
  price DECIMAL(10,2),
  FOREIGN KEY (order_id) REFERENCES orders(order_id)
);
```

#### PostgreSQL：混合模型设计哲学

**设计哲学**：
- **对象关系型**：关系模型 + 面向对象特性
- **扩展性**：支持自定义类型、函数、索引
- **JSONB 支持**：关系与文档模型的完美结合

**混合模型示例**：
```sql
-- 关系表 + JSONB 灵活字段
CREATE TABLE products (
  id SERIAL PRIMARY KEY,
  name VARCHAR(200),
  price DECIMAL(10,2),
  attributes JSONB,  -- 灵活的属性存储
  tags TEXT[],       -- 原生数组支持
  created_at TIMESTAMP DEFAULT NOW()
);

-- 插入数据
INSERT INTO products (name, price, attributes, tags)
VALUES (
  '笔记本电脑',
  8999.00,
  '{"brand": "Apple", "cpu": "M2", "ram": "16GB"}',
  ARRAY['电子产品', '办公', '热门']
);

-- JSONB 查询
SELECT * FROM products
WHERE attributes->>'brand' = 'Apple'
  AND attributes->'cpu' = '"M2"';
```

#### Redis：内存数据结构哲学

**设计哲学**：
- **内存优先**：微秒级响应速度
- **简单直接**：键值模型，无复杂查询
- **数据结构丰富**：String/List/Set/Hash/ZSet

**数据结构示例**：
```redis
# String - 缓存
SET user:1001:profile "{\"name\":\"张三\",\"email\":\"xxx@example.com\"}"

# Hash - 对象存储
HSET user:1001 name "张三" email "xxx@example.com" age 25

# List - 队列
LPUSH queue:tasks "task1" "task2" "task3"

# Set - 去重
SADD online:users "user1" "user2" "user3"

# Sorted Set - 排行榜
ZADD leaderboard:global 1000 "user1" 900 "user2" 950 "user3"

# 获取排行榜前 3 名
ZREVRANGE leaderboard:global 0 2 WITHSCORES
```

---

## 4. 存储引擎对比

### 4.1 对比表格

| 特性 | MongoDB WiredTiger | MySQL InnoDB | PostgreSQL Heap | Redis |
|------|-------------------|--------------|-----------------|-------|
| **数据结构** | LSM-Tree 变种 | B+Tree | Heap 文件 | 内存哈希表 |
| **锁粒度** | 文档级 | 行级 | 行级 | 无锁 (单线程) |
| **压缩** | Snappy/GZIP/ZSTD | 不支持 | 不支持 | 不支持 |
| **空间占用** | 小 (压缩后) | 中 | 大 | 大 (内存) |
| **写性能** | 高 | 中 | 中 | 极高 |
| **读性能** | 高 | 高 | 高 | 极高 |

### 4.2 详细分析

#### MongoDB WiredTiger 存储引擎

**核心架构**：
```
┌─────────────────────────────────────────────┐
│              MongoDB Server                 │
├─────────────────────────────────────────────┤
│              WiredTiger Engine              │
│  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Cache     │  │    Checkpoint       │  │
│  │  (内存池)   │  │    (定期刷盘)       │  │
│  └─────────────┘  └─────────────────────┘  │
│  ┌─────────────┐  ┌─────────────────────┐  │
│  │  LSM-Tree   │  │      Journal        │  │
│  │  (写优化)   │  │    (事务日志)       │  │
│  └─────────────┘  └─────────────────────┘  │
└─────────────────────────────────────────────┘
```

**LSM-Tree 写流程**：
```
1. 写入 → MemTable (内存)
2. MemTable 满 → 刷盘为 SSTable (磁盘)
3. 多个 SSTable → Compaction 合并

优势：随机写变顺序写，写放大降低
劣势：读可能需要合并多个文件
```

**压缩效果对比**：
| 压缩算法 | 压缩比 | CPU 开销 | 适用场景 |
|----------|--------|----------|----------|
| Snappy | 2-3x | 低 | 写密集型 |
| GZIP | 4-5x | 中 | 读密集型 |
| ZSTD | 3-4x | 中低 | 平衡型 |
| ZLIB | 3-4x | 高 | 存储受限 |

#### MySQL InnoDB 存储引擎

**B+Tree 结构**：
```
         Root
       /  |  \
      /   |   \
   Index Index Index  (非叶子节点)
    / \   / \   / \
   L1 L2 L3 L4 L5 L6  (叶子节点，存储数据)
```

**聚簇索引特点**：
- 主键索引的叶子节点就是数据本身
- 辅助索引的叶子节点存储主键值
- 主键查询最快，二次查询需要回表

**行锁实现**：
```sql
-- InnoDB 行锁基于索引实现
-- 如果没有索引，行锁会退化为表锁

-- 正确使用 (走索引，行锁)
UPDATE orders
SET status = 'shipped'
WHERE order_id = 12345;  -- order_id 有索引

-- 错误使用 (不走索引，表锁)
UPDATE orders
SET status = 'cancelled'
WHERE YEAR(created_at) = 2024;  -- 函数导致索引失效
```

#### PostgreSQL Heap 存储

**Heap 文件结构**：
```
┌─────────────────────────────────────┐
│             Heap File               │
│  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐  │
│  │Tuple│ │Tuple│ │Tuple│ │Tuple│  │
│  │  1  │ │  2  │ │  3  │ │  4  │  │
│  └─────┘ └─────┘ └─────┘ └─────┘  │
│  (每行数据独立存储，无排序)          │
└─────────────────────────────────────┘
         ▲
         │
    ┌────┴────┐
    │  Index  │ (索引指向 Heap 中的元组)
    │  B-Tree │
    └─────────┘
```

**TOAST 大对象存储**：
```sql
-- 超过 2KB 的字段自动存储到 TOAST 表
CREATE TABLE documents (
  id SERIAL PRIMARY KEY,
  title VARCHAR(200),
  content TEXT  -- 大文本自动 TOAST 存储
);

-- 查询时按需获取
SELECT id, title FROM documents;           -- 不获取 content
SELECT id, title, LEFT(content, 100) ...;  -- 部分获取
SELECT id, title, content FROM ...;        -- 完整获取
```

**MVCC 实现**：
```
PostgreSQL 元组头部存储：
- xmin: 插入事务 ID
- xmax: 删除事务 ID
- ctid: 物理位置指针

查询可见性判断：
IF (xmin <= current_tx AND (xmax = 0 OR xmax > current_tx))
  THEN 可见
```

#### Redis 内存存储

**内存数据结构**：
```
┌─────────────────────────────────────┐
│          Redis Dict (哈希表)        │
│  ┌──────┐    ┌──────┐    ┌──────┐  │
│  │ key1 │───▶│ data │    │ ... │  │
│  └──────┘    └──────┘    └──────┘  │
│                                    │
│  对象编码优化：                     │
│  - int (整数)                       │
│  - embstr (小字符串)                │
│  - raw (大字符串)                   │
│  - listpack (压缩列表)              │
└─────────────────────────────────────┘
```

**持久化对比**：
| 方式 | 原理 | 优点 | 缺点 |
|------|------|------|------|
| **RDB** | 定期快照 | 文件小、恢复快 | 可能丢失数据 |
| **AOF** | 记录每条写命令 | 数据更安全 | 文件大、恢复慢 |
| **混合** | RDB+AOF | 平衡性能与安全 | 配置复杂 |

---

## 5. 事务能力对比

### 5.1 对比表格

| 特性 | MongoDB | MySQL | PostgreSQL | Redis |
|------|---------|-------|------------|-------|
| **单文档/行事务** | ✅ 完整支持 | ✅ 完整支持 | ✅ 完整支持 | ✅ 原子性 |
| **多文档/行事务** | ✅ 4.0+ | ✅ | ✅ | ❌ (Lua 脚本) |
| **隔离级别** | 快照隔离 | READ COMMITTED/REPEATABLE READ/SERIALIZABLE | READ COMMITTED/REPEATABLE READ/SERIALIZABLE | 无 |
| **分布式事务** | ✅ 4.2+ | ❌ (需外部方案) | ❌ (需外部方案) | ❌ |
| **事务日志** | Journal | Redo Log | WAL | AOF |

### 5.2 详细分析

#### MongoDB 事务实现

**架构设计**：
```
┌──────────────────────────────────────────────┐
│              Transaction Coordinator         │
├──────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────────────┐   │
│  │  Participant│  │  Transaction Log    │   │
│  │  (分片节点) │  │  (local 库)         │   │
│  └─────────────┘  └─────────────────────┘   │
└──────────────────────────────────────────────┘
```

**两阶段提交流程**：
```javascript
// 1. Prepare 阶段
Coordinator → Participants: "准备提交？"
Participants → Coordinator: "OK" / "Abort"

// 2. Commit 阶段
Coordinator → Participants: "提交"
Participants → Coordinator: "确认"

// 如果任一参与者失败，全部回滚
```

**使用示例**：
```javascript
// MongoDB 多文档事务
session.startTransaction({
  readConcern: { level: "snapshot" },
  writeConcern: { w: "majority" },
  maxCommitTimeMS: 5000
});

try {
  await db.orders.insertOne(order, { session });
  await db.inventory.updateOne(
    { sku: "item1", stock: { $gt: 0 } },
    { $inc: { stock: -1 } },
    { session }
  );
  await session.commitTransaction();
} catch (error) {
  await session.abortTransaction();
  throw error;
}
```

#### MySQL 事务实现

**ACID 保证机制**：
```
┌─────────────────────────────────────────┐
│              MySQL InnoDB               │
├─────────────────────────────────────────┤
│  Atomicity: Undo Log (回滚日志)        │
│  Consistency: 约束 + 触发器            │
│  Isolation: MVCC + 锁                  │
│  Durability: Redo Log + 双写缓冲       │
└─────────────────────────────────────────┘
```

**隔离级别对比**：
| 级别 | 脏读 | 不可重复读 | 幻读 | MySQL 默认 |
|------|------|------------|------|----------|
| READ UNCOMMITTED | ✅ | ✅ | ✅ | ❌ |
| READ COMMITTED | ❌ | ✅ | ✅ | ❌ (Oracle 默认) |
| REPEATABLE READ | ❌ | ❌ | ❌* | ✅ (MySQL 默认) |
| SERIALIZABLE | ❌ | ❌ | ❌ | ❌ |

*MySQL 通过 Next-Key Lock 解决幻读

#### PostgreSQL 事务实现

**完整 ACID+ 可串行化**：
```sql
-- 可串行化隔离级别
SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

BEGIN;
-- 真正的串行化，不是快照隔离
-- 如果检测到冲突，自动回滚并报错
SELECT * FROM accounts WHERE balance < 0;
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
COMMIT;
```

**SSI (Serializable Snapshot Isolation)**：
- 基于快照隔离
- 检测序列化冲突
- 自动回滚冲突事务

#### Redis 事务

**单命令原子性**：
```redis
# 单个命令是原子的
INCR counter  # 原子操作

# MULTI/EXEC 不提供隔离性
MULTI
  INCR counter
  INCR counter
EXEC
# 注意：其他命令可能在中间执行
```

**Lua 脚本实现原子性**：
```lua
-- Lua 脚本中原子执行
EVAL "
  local current = redis.call('GET', KEYS[1])
  if current and tonumber(current) >= tonumber(ARGV[1]) then
    redis.call('DECRBY', KEYS[1], ARGV[1])
    return 1
  end
  return 0
" 1 inventory_key 5
```

---

## 6. 锁机制对比

### 6.1 对比表格

| 特性 | MongoDB | MySQL | PostgreSQL | Redis |
|------|---------|-------|------------|-------|
| **锁粒度** | 文档级 | 行/表/元数据 | 行/表/谓词 | 无锁 |
| **死锁检测** | ✅ | ✅ | ✅ | N/A |
| **锁升级** | ❌ | ✅ | ✅ | N/A |
| **意向锁** | ❌ | ✅ | ✅ | N/A |
| **并发模型** | MVCC | MVCC+ 锁 | MVCC+ 锁 | 单线程 |

### 6.2 详细分析

#### MongoDB 锁机制

**文档级锁实现**：
```
MongoDB 使用 WiredTiger 引擎的文档级锁：

写操作：获取文档的排他锁 (X 锁)
读操作：无锁 (MVCC 快照读)

优势：
- 高并发下性能好
- 不会发生锁升级

劣势：
- 不支持表级锁优化批量操作
```

**锁等待监控**：
```javascript
// 查看当前锁状态
db.currentOp({
  "locks.acquireWaitCount": { $gt: 0 }
});

// 查看长时间运行的操作
db.currentOp({
  "secs_running": { $gt: 5 }
});
```

#### MySQL 锁机制

**多层级锁体系**：
```
┌─────────────────────────────────────────┐
│           MySQL 锁体系                  │
├─────────────────────────────────────────┤
│  元数据锁 (MDL)                          │
│    ▲                                    │
│    │                                    │
│  表锁 (表级)                             │
│    ▲                                    │
│    │                                    │
│  意向锁 (IS/IX)                          │
│    ▲                                    │
│    │                                    │
│  行锁 (记录锁/间隙锁/临键锁)             │
└─────────────────────────────────────────┘
```

**行锁类型**：
```sql
-- 记录锁 (Record Lock)
SELECT * FROM t WHERE id = 1 FOR UPDATE;

-- 间隙锁 (Gap Lock)
SELECT * FROM t WHERE id > 5 FOR UPDATE;

-- 临键锁 (Next-Key Lock = 记录锁 + 间隙锁)
-- 用于防止幻读
```

**锁等待查询**：
```sql
-- MySQL 8.0+ 锁等待
SELECT
  requesting_trx_id,
  requested_lock_id,
  blocking_trx_id,
  blocking_lock_id
FROM performance_schema.data_lock_waits;
```

#### PostgreSQL 锁机制

**谓词锁 (Predicate Lock)**：
```sql
-- PostgreSQL 支持谓词锁用于可串行化隔离
-- 锁定满足特定条件的行集合

-- 查看当前锁
SELECT
  locktype,
  mode,
  relation::regclass,
  granted
FROM pg_locks
WHERE NOT granted;
```

**表锁模式**：
| 模式 | 描述 | 冲突锁模式 |
|------|------|------------|
| ACCESS SHARE | SELECT | ACCESS EXCLUSIVE |
| ROW SHARE | SELECT FOR UPDATE | EXCLUSIVE, ACCESS EXCLUSIVE |
| ROW EXCLUSIVE | UPDATE/DELETE/INSERT | SHARE, EXCLUSIVE, ACCESS EXCLUSIVE |
| SHARE | CREATE INDEX | ROW EXCLUSIVE, EXCLUSIVE, ACCESS EXCLUSIVE |
| EXCLUSIVE | 阻止其他写 | 所有写锁 |
| ACCESS EXCLUSIVE | ALTER TABLE | 所有锁 |

#### Redis 单线程模型

**无锁设计**：
```
Redis 使用单线程处理命令：

┌─────────────────────────────────────────┐
│           Redis Server                  │
│                                         │
│  ┌─────────────────────────────────┐   │
│  │      Command Queue (FIFO)       │   │
│  └─────────────────────────────────┘   │
│                  │                     │
│                  ▼                     │
│  ┌─────────────────────────────────┐   │
│  │      Single Thread Executor     │   │
│  └─────────────────────────────────┘   │
└─────────────────────────────────────────┘

优势：
- 无锁竞争开销
- 无死锁可能
- 实现简单

劣势：
- 单核性能瓶颈
- 慢命令阻塞所有请求
```

---

## 7. 扩展方式对比

### 7.1 对比表格

| 特性 | MongoDB | MySQL | PostgreSQL | Redis |
|------|---------|-------|------------|-------|
| **主从复制** | ✅ 副本集 | ✅ 主从 | ✅ 流复制 | ✅ 主从 |
| **自动故障转移** | ✅ | ❌ (需 MHA/Orchestrator) | ❌ (需 Patroni) | ✅ (Sentinel) |
| **分片** | ✅ 内置 | ❌ (需中间件) | ❌ (需插件) | ✅ Cluster |
| **读写分离** | ✅ 自动 | ✅ 应用层 | ✅ 应用层 | ✅ 只读副本 |
| **弹性扩缩容** | ✅ | ❌ | ❌ | ⚠️ 有限 |

### 7.2 详细分析

#### MongoDB 分片架构

**组件说明**：
```
┌─────────────────────────────────────────────────────────┐
│                    Mongos (路由层)                      │
│                    (查询路由器)                          │
└────────────────────────┬────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   Config Server │ │   Config Server │ │   Config Server │
│   (元数据)      │ │   (元数据)      │ │   (元数据)      │
└─────────────────┘ └─────────────────┘ └─────────────────┘
         │               │               │
         ▼               ▼               ▼
┌─────────────────────────────────────────────────────────┐
│                    Shard 0                               │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐     │
│  │  Primary    │  │  Secondary  │  │  Secondary  │     │
│  └─────────────┘  └─────────────┘  └─────────────┘     │
└─────────────────────────────────────────────────────────┘
```

**分片键选择策略**：
```javascript
// 范围分片 - 适合时间序列数据
sh.shardCollection("db.logs", { timestamp: 1 });

// 哈希分片 - 均匀分布，适合写密集
sh.shardCollection("db.users", { _id: "hashed" });

// 标签感知分片 - 数据本地化
sh.addShardTag("shard01", "region:us-east");
sh.updateZoneKeyRange("db.users", { country: "US" }, { country: "US" }, "zone-us");
```

#### MySQL 扩展方案

**主从复制架构**：
```
┌──────────┐
│  Master  │
│  (读写)  │
└────┬─────┘
     │ Binlog
     ├──────────────┬──────────────┐
     ▼              ▼              ▼
┌──────────┐  ┌──────────┐  ┌──────────┐
│  Slave1  │  │  Slave2  │  │  Slave3  │
│  (只读)  │  │  (只读)  │  │  (只读)  │
└──────────┘  └──────────┘  └──────────┘
```

**分库分表中间件**：
| 中间件 | 特点 | 适用场景 |
|--------|------|----------|
| ShardingSphere | 功能全面，生态完善 | 复杂分片需求 |
| MyCAT | 轻量级，易部署 | 简单分片 |
| Vitess | YouTube 开源，K8s 友好 | 云原生 |

#### PostgreSQL 扩展方案

**流复制架构**：
```sql
-- 主库配置
ALTER SYSTEM SET wal_level = replica;
ALTER SYSTEM SET max_wal_senders = 3;

-- 从库配置
primary_conninfo = 'host=primary_host port=5432 user=replicator';
```

**Citus 分布式扩展**：
```sql
-- 安装 Citus 扩展
CREATE EXTENSION citus;

-- 创建分布式表
SELECT create_distributed_table('orders', 'customer_id');

-- 自动分片和数据分布
```

#### Redis Cluster

**分片原理**：
```
Redis Cluster 使用 16384 个哈希槽：

key → CRC16(key) % 16384 → 槽位

┌─────────────────────────────────────────────────┐
│  Node A (槽位 0-5499)                           │
│  ┌─────────┬─────────┬─────────┐               │
│  │ Master  │         │         │               │
│  └─────────┴─────────┴─────────┘               │
│  ┌─────────┬─────────┬─────────┐               │
│  │ Replica │         │         │               │
│  └─────────┴─────────┴─────────┘               │
└─────────────────────────────────────────────────┘
```

---

## 8. 典型应用场景对比

### 8.1 场景对比表格

| 场景 | 最佳选择 | 原因 | 替代方案 |
|------|----------|------|----------|
| 内容管理系统 | MongoDB | 灵活 schema，嵌套文档 | PostgreSQL+JSONB |
| 电商订单 | MySQL | 事务支持，生态成熟 | PostgreSQL |
| 复杂分析 | PostgreSQL | 窗口函数，CTE | MySQL 8.0+ |
| 缓存会话 | Redis | 微秒响应，数据结构 | MongoDB |
| 实时排行榜 | Redis | Sorted Set | PostgreSQL |
| 用户配置 | MongoDB | 文档模型，灵活 | Redis Hash |
| 消息队列 | Redis | List 结构，高性能 | RabbitMQ/Kafka |
| 地理位置 | MongoDB | 原生 Geo 索引 | PostgreSQL+PostGIS |
| 全文搜索 | PostgreSQL | 内置全文索引 | Elasticsearch |
| 时间序列 | MongoDB | 时间序列集合 | InfluxDB/TimescaleDB |

### 8.2 实际案例

#### 案例 1：博客平台 Schema 设计对比

**MongoDB 方案**：
```javascript
// 单文档存储所有博客信息
{
  _id: ObjectId("..."),
  title: "MongoDB 技术深度解析",
  content: "...",
  author: {
    id: "user123",
    name: "张三",
    avatar: "https://..."
  },
  tags: ["MongoDB", "NoSQL", "数据库"],
  comments: [  // 评论内嵌
    {
      user: "李四",
      content: "写得很好！",
      created_at: ISODate("2024-01-01")
    }
  ],
  views: 1024,
  likes: 89,
  created_at: ISODate("2024-01-01"),
  updated_at: ISODate("2024-01-02")
}

// 查询简单
db.posts.findOne({ _id: postId });
```

**MySQL 方案**：
```sql
-- 规范化设计
CREATE TABLE posts (
  id INT PRIMARY KEY AUTO_INCREMENT,
  title VARCHAR(200),
  content TEXT,
  author_id INT,
  views INT DEFAULT 0,
  likes INT DEFAULT 0,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  FOREIGN KEY (author_id) REFERENCES users(id)
);

CREATE TABLE post_tags (
  post_id INT,
  tag_id INT,
  PRIMARY KEY (post_id, tag_id)
);

CREATE TABLE comments (
  id INT PRIMARY KEY AUTO_INCREMENT,
  post_id INT,
  user_id INT,
  content TEXT,
  created_at TIMESTAMP,
  FOREIGN KEY (post_id) REFERENCES posts(id)
);

-- 查询需要连接
SELECT p.*, u.name as author_name,
       GROUP_CONCAT(t.name) as tags
FROM posts p
JOIN users u ON p.author_id = u.id
LEFT JOIN post_tags pt ON p.id = pt.post_id
LEFT JOIN tags t ON pt.tag_id = t.id
WHERE p.id = ?;
```

**PostgreSQL 方案**：
```sql
-- 混合设计
CREATE TABLE posts (
  id SERIAL PRIMARY KEY,
  title VARCHAR(200),
  content TEXT,
  author_id INT,
  tags TEXT[],  -- 数组类型
  metadata JSONB,  -- 灵活元数据
  views INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);

-- 灵活查询
SELECT p.*, u.name as author_name
FROM posts p, jsonb_array_elements(p.metadata->'related') as related
JOIN users u ON p.author_id = u.id
WHERE p.id = 1;
```

**选型建议**：
| 因素 | 选择 MongoDB | 选择 MySQL/PostgreSQL |
|------|-------------|---------------------|
| 数据模型变化频繁 | ✅ | ❌ |
| 需要复杂连接查询 | ❌ | ✅ |
| 评论数量大 | ❌ (文档过大) | ✅ |
| 快速原型开发 | ✅ | ⚠️ |
| 数据一致性强要求 | ❌ | ✅ |

#### 案例 2：电商库存扣减对比

**MySQL 方案（推荐）**：
```sql
-- 事务保证一致性
START TRANSACTION;

-- 检查库存
SELECT stock FROM inventory
WHERE sku = 'SKU001' FOR UPDATE;

-- 扣减库存
UPDATE inventory
SET stock = stock - 1
WHERE sku = 'SKU001' AND stock >= 1;

-- 检查影响行数
-- ROW_COUNT() = 0 表示库存不足

-- 创建订单
INSERT INTO orders (order_id, sku, quantity, status)
VALUES ('ORD001', 'SKU001', 1, 'pending');

COMMIT;
```

**MongoDB 方案**：
```javascript
// 原子操作
const result = await db.inventory.findOneAndUpdate(
  { sku: "SKU001", stock: { $gte: 1 } },
  { $inc: { stock: -1 } },
  { returnDocument: "after" }
);

if (result.value === null) {
  throw new Error("库存不足");
}

// 创建订单
await db.orders.insertOne({
  order_id: "ORD001",
  sku: "SKU001",
  quantity: 1,
  status: "pending",
  created_at: new Date()
});
```

**Redis 方案（高性能场景）**：
```redis
# 使用 Lua 脚本保证原子性
EVAL "
  local stock = redis.call('GET', KEYS[1])
  if not stock or tonumber(stock) < tonumber(ARGV[1]) then
    return 0  -- 库存不足
  end
  redis.call('DECRBY', KEYS[1], ARGV[1])
  return 1  -- 成功
" 1 inventory:SKU001 1

# 返回 1 则继续创建订单，返回 0 则提示库存不足
```

**选型对比**：
| 方案 | 并发能力 | 一致性 | 复杂度 | 适用场景 |
|------|----------|--------|--------|----------|
| MySQL | 1000 TPS | 强 | 低 | 一般电商 |
| MongoDB | 5000 TPS | 中 | 中 | 高并发 |
| Redis | 50000+ TPS | 最终 | 高 | 秒杀场景 |

#### 案例 3：实时排行榜对比

**Redis 方案（最佳）**：
```redis
# 添加分数
ZADD leaderboard:global 1000 "user1"
ZADD leaderboard:global 900 "user2"
ZADD leaderboard:global 950 "user3"

# 获取前 10 名
ZREVRANGE leaderboard:global 0 9 WITHSCORES

# 获取用户排名
ZREVRANK leaderboard:global "user1"

# 获取用户分数
ZSCORE leaderboard:global "user1"
```

**PostgreSQL 方案**：
```sql
-- 使用窗口函数
SELECT
  user_id,
  score,
  RANK() OVER (ORDER BY score DESC) as rank
FROM leaderboard
WHERE game_id = 'global'
ORDER BY score DESC
LIMIT 10;

-- 获取特定用户排名
SELECT rank FROM (
  SELECT user_id, RANK() OVER (ORDER BY score DESC) as rank
  FROM leaderboard
  WHERE game_id = 'global'
) t WHERE user_id = 'user1';
```

**MongoDB 方案**：
```javascript
// 使用聚合管道
db.leaderboard.aggregate([
  { $match: { game_id: "global" } },
  { $sort: { score: -1 } },
  { $limit: 10 },
  {
    $addFields: {
      rank: { $add: [{ $indexOfArray: ["$sorted_ids", "$_id"] }, 1] }
    }
  }
]);
```

**性能对比**：
| 方案 | 写入延迟 | 查询延迟 | 内存占用 | 适用规模 |
|------|----------|----------|----------|----------|
| Redis | 0.1ms | 0.1ms | 高 | 百万级 |
| PostgreSQL | 5ms | 50ms | 中 | 十万级 |
| MongoDB | 5ms | 100ms | 中 | 十万级 |

---

## 9. 总结与选型建议

### 9.1 快速选型指南

```
                    ┌─────────────────┐
                    │   需求分析      │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  需要事务吗？  │   │  高并发读？   │   │  数据结构复杂？│
└───────┬───────┘   └───────┬───────┘   └───────┬───────┘
        │                   │                   │
    是  │ 否                │ 是  否            │ 是  否
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  需要复杂查询？│   │  需要缓存？   │   │  需要灵活     │
└───────┬───────┘   └───────┬───────┘   │  Schema？     │
        │                   │           └───────┬───────┘
    是  │ 否                │ 是  否            │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│ PostgreSQL    │   │  Redis        │   │  MongoDB      │
│ (功能最全)    │   │  (性能最高)   │   │  (最灵活)     │
└───────────────┘   └───────────────┘   └───────────────┘
        │
    否  │
        ▼
┌───────────────┐
│ MySQL         │
│ (最简单)      │
└───────────────┘
```

### 9.2 组合使用模式

**典型架构**：
```
┌─────────────────────────────────────────────────────────┐
│                    应用层                               │
└─────────────────────────────────────────────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   MySQL/PG      │ │   MongoDB       │ │   Redis         │
│   (核心业务)    │ │   (内容/日志)   │ │   (缓存/队列)   │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

**数据同步**：
- MySQL → Redis：缓存预热
- MySQL → MongoDB：数据分析
- MongoDB → Elasticsearch：全文搜索

### 9.3 未来趋势

| 趋势 | 影响 | 建议 |
|------|------|------|
| 多模型融合 | 边界模糊 | 关注 PostgreSQL、MongoDB |
| 云原生数据库 | 弹性扩展 | 优先选择云托管服务 |
| HTAP | 事务 + 分析 | 评估 TiDB、Aurora |
| AI 集成 | 向量检索 | 关注 pgvector、MongoDB 向量 |

---

## 附录：参考资料

1. MongoDB 官方文档：https://www.mongodb.com/docs/
2. MySQL 官方文档：https://dev.mysql.com/doc/
3. PostgreSQL 官方文档：https://www.postgresql.org/docs/
4. Redis 官方文档：https://redis.io/docs/
5. WiredTiger 存储引擎：https://source.wiredtiger.com/
6. 《MongoDB 权威指南》
7. 《高性能 MySQL》
8. 《PostgreSQL 修炼之道》
