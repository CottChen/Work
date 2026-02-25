# PM2 完整指南：配置参数与 K8s 容器部署详解

> 文档版本：1.0 | 更新日期：2026-02-25

## 目录

1. [核心概念](#一核心概念)
2. [完整配置参数详解](#二完整配置参数详解)
3. [Docker / K8s 集成](#三docker-k8s-集成)
4. [常见坑与最佳实践](#四常见坑与最佳实践)
5. [常用命令速查](#五常用命令速查)

---

## 一、核心概念

### 1.1 两种运行模式

| 模式 | 参数值 | 说明 |
|------|--------|------|
| **Fork** | `fork` (默认) | 单进程 fork 模式，适合非 HTTP 服务如 worker、定时任务 |
| **Cluster** | `cluster` | 集群模式，基于 Node.js cluster 模块，支持负载均衡 |

> ⚠️ **K8s 注意事项**：在 K8s 中通常每个 Pod 只运行一个容器，每个容器内使用 PM2 管理单或多实例。如果需要多实例分散负载，优先考虑 K8s Deployment 的多副本而非 PM2 cluster 模式。

---

## 二、完整配置参数详解

### 2.1 基础配置

```javascript
module.exports = {
  apps: [{
    // ========== 必填项 ==========
    name: 'my-app',           // 应用名称，用于 pm2 list 显示
    script: './server.js',    // 启动脚本路径

    // ========== 进程管理 ==========
    instances: 1,             // 实例数量：数字 | 'max' | 0 (max = CPU 核心数)
    exec_mode: 'fork',        // 模式：'fork' | 'cluster'
    cwd: '/path/to/app',     // 工作目录

    // ========== 启动参数 ==========
    args: ['--arg1', 'value'],  // 传递给 script 的命令行参数
    node_args: '--harmony --max-old-space-size=2048',  // Node.js 参数
    interpreter: 'node',     // 解释器，默认 node
    script_args: '--port 8080',  // 直接追加到脚本后的字符串参数
  }]
};
```

> **坑 1**：`script` 和 `args` 的区别
> - `script`: 要执行的入口文件
> - `args`: 传递给脚本的参数（作为 process.argv 的一部分）
> - `script_args`: 直接追加到脚本后的字符串

> **坑 2**：`instances: 'max'` 在 K8s 中的行为
> - PM2 会尝试使用所有可用 CPU 核心
> - 在 K8s 中，如果设置了 CPU limit，可能导致资源争抢
> - **建议**：在 K8s 中明确设置实例数，或结合 K8s HPA 横向扩展

---

### 2.2 重启策略

```javascript
{
  // ========== 自动重启 ==========
  autorestart: true,          // 崩溃后自动重启，默认 true
  max_restarts: 10,           // 最大重启次数，默认 15
  min_uptime: '5s',          // 进程稳定运行最短时间，低于此值视为频繁重启
  restart_delay: 4000,       // 重启延迟（毫秒），默认 0

  // ========== 定时重启 (Cron) ==========
  cron_restart: '0 0 * * *', // Cron 表达式，每天午夜重启

  // ========== 内存重启 ==========
  max_memory_restart: '1G',  // 内存超过阈值时重启，支持单位：G/M/K/字节
}
```

> **坑 3**：内存检查间隔
> - PM2 内部每 **30 秒**检查一次内存
> - 触发重启前可能有 30 秒延迟
> - 适用于检测内存泄漏，但不适合实时保护

> **坑 4**：频繁重启循环（CrashLoopBackOff）
> - `min_uptime` 过短 + `restart_delay` 过短 → 快速重启循环
> - K8s 中会触发 CrashLoopBackOff 状态
> - **解决**：设置合理的 `min_uptime: '10s'` 和 `restart_delay: 1000`

---

### 2.3 优雅停止（Graceful Shutdown）

```javascript
{
  // ========== 优雅停止 ==========
  kill_timeout: 5000,         // 收到停止信号后等待退出的时间（毫秒），默认 1600
  wait_ready: true,           // 等待应用发送 'ready' 信号后才标记为在线
  listen_timeout: 3000,      // 等待应用监听端口的超时时间（需要 wait_ready: true）
  shutdown_with_message: false,  // 收到 SIGINT 时向子进程发送 'shutdown' 消息
}
```

> **坑 5**：K8s 优雅停止时间不足
> - K8s 默认 `terminationGracePeriodSeconds: 30`
> - PM2 默认 `kill_timeout: 1600` (1.6s)
> - 如果应用清理耗时 > kill_timeout，K8s 会发送 SIGKILL
> - **解决**：
>   ```yaml
>   # K8s Deployment
>   spec:
>     terminationGracePeriodSeconds: 60  # 延长等待时间
>     containers:
>     - lifecycle:
>         preStop:
>           exec:
>             command: ["/bin/sh", "-c", "sleep 10"]
>   ```

> **坑 6**：wait_ready 与 K8s 健康检查冲突
> - 启用 `wait_ready: true` 后，PM2 不会标记进程为 online，直到应用发送 `process.send('ready')`
> - 需要配合 K8s readinessProbe：
>   ```yaml
>   readinessProbe:
>     httpGet:
>       path: /health
>       port: 3000
>     initialDelaySeconds: 5
>     periodSeconds: 5
>   ```

---

### 2.4 文件监控（Watch Mode）

```javascript
{
  watch: true,               // 开启文件监控，文件变化时自动重启
  // watch: ['src', 'config'], // 指定监控目录/文件数组

  ignore_watch: [            // 忽略的文件/目录
    'node_modules',
    'logs',
    '*.log',
    '[/\\\\]\\.'  // 正则：隐藏文件
  ],

  watch_options: {           // 高级监控选项
    followSymlinks: false,  // 不跟随符号链接
    persistent: true,        // 持续监控
    usePolling: false,      // 使用轮询（适合 NFS）
    interval: 1000          // 轮询间隔（毫秒）
  }
}
```

> ⚠️ **生产环境警告**：永远不要在生产环境启用 `watch: true`！
>
> **坑 7**：watch 模式导致生产环境重启风暴
> - 代码自动部署时可能触发无限重启
> - **解决**：生产环境显式设置 `watch: false`

---

### 2.5 日志管理

```javascript
{
  // ========== 日志文件 ==========
  out_file: './logs/out.log',     // 标准输出日志
  error_file: './logs/err.log',    // 错误日志
  log_file: './logs/combined.log', // 合并日志（out + err）

  // ========== 日志格式 ==========
  log_date_format: 'YYYY-MM-DD HH:mm:ss Z',  // 时间戳格式
  merge_logs: true,               // 合并多实例日志（不添加进程 ID 后缀）

  // ========== 日志轮转 (需要 pm2-logrotate) ==========
  // pm2 install pm2-logrotate
}
```

> **坑 8**：日志文件无限增长
> - 默认 PM2 不自动轮转日志
> - **解决**：安装 `pm2-logrotate`
>   ```bash
>   pm2 install pm2-logrotate
>   ```

> **坑 9**：K8s 中日志收集
> - 建议将日志输出到 stdout/stderr（Docker 标准输出）
>   ```javascript
>   out_file: '/dev/stdout',
>   error_file: '/dev/stderr',
>   ```
> - 配合 K8s 日志收集（fluentd、logstash 等）

---

### 2.6 环境变量

```javascript
{
  // ========== 基础环境变量 ==========
  env: {
    NODE_ENV: 'development',
    PORT: 3000,
    LOG_LEVEL: 'debug'
  },

  // ========== 环境特定变量 ==========
  env_production: {
    NODE_ENV: 'production',
    PORT: 8080,
    LOG_LEVEL: 'info'
  },

  env_staging: {
    NODE_ENV: 'staging',
    PORT: 8000
  },

  // ========== 实例变量 ==========
  instance_var: 'INSTANCE_ID',  // 自动注入环境变量 PM2_INSTANCE_ID (0, 1, 2...)
}
```

> 使用方式：
> ```bash
> pm2 start ecosystem.config.js --env production
> ```

---

### 2.7 其他高级选项

```javascript
{
  // ========== 进程唯一标识 ==========
  instance_var: 'INSTANCE_ID',  // 环境变量名，默认 PM2_INSTANCE_ID

  // ========== 源码映射 (Source Map) ==========
  source_map_support: true,   // 启用源码映射支持（生产环境错误堆栈）

  // ========== 版本控制集成 ==========
  vizion: false,              // 禁用版本控制特性（如果不需要）

  // ========== PID 文件 ==========
  pid_file: './app.pid',      // PID 文件路径

  // ========== 自动启动 ==========
  autorestart: true,          // 崩溃后自动重启
  keep_alive: true,          // 保持进程运行（即使脚本退出码为 0）

  // ========== Windows 兼容 ==========
  windowsHide: true,          // Windows 下隐藏控制台窗口
}
```

---

## 三、Docker / K8s 集成

### 3.1 基础 Dockerfile

```dockerfile
FROM node:18-alpine

# 安装 PM2（全局）
RUN npm install pm2 -g

WORKDIR /app

# 复制依赖文件
COPY package*.json ./
RUN npm ci --only=production

# 复制应用代码
COPY . .

# 暴露端口
EXPOSE 3000

# 方式一：使用 pm2-runtime（推荐）
CMD ["pm2-runtime", "start", "ecosystem.config.js", "--env", "production"]

# 方式二：直接运行脚本
# CMD ["pm2-runtime", "server.js"]
```

### 3.2 K8s Deployment 完整示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: my-app
  # 延长优雅终止时间
  terminationGracePeriodSeconds: 60
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
      - name: my-app
        image: my-app:latest
        ports:
        - containerPort: 3000

        # ========== 资源限制 ==========
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"

        # ========== 环境变量 ==========
        env:
        - name: NODE_ENV
          value: "production"
        - name: PORT
          value: "3000"

        # ========== 健康检查 ==========
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 15
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3

        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3

        # ========== 优雅停止 Hook ==========
        lifecycle:
          preStop:
            exec:
              # 等待现有请求处理完成
              command: ["/bin/sh", "-c", "sleep 10"]
```

### 3.3 PM2 配置文件 (ecosystem.config.js)

```javascript
module.exports = {
  apps: [
    {
      name: 'api-server',
      script: './server.js',

      // K8s 中通常使用单实例或少量实例
      instances: process.env.INSTANCE_COUNT || 1,
      exec_mode: 'cluster',

      // 生产环境必须关闭 watch
      watch: false,

      // 内存限制（与 K8s limits 配合）
      max_memory_restart: '400M',

      // 重启策略
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      restart_delay: 1000,

      // 优雅停止（与 K8s terminationGracePeriodSeconds 协调）
      wait_ready: true,
      listen_timeout: 3000,
      kill_timeout: 5000,

      // 日志
      out_file: '/dev/stdout',
      error_file: '/dev/stderr',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,

      // 环境变量
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      }
    }
  ]
};
```

### 3.4 应用中发送 Ready 信号

```javascript
// server.js
const http = require('http');

const server = http.createServer((req, res) => {
  if (req.url === '/health') {
    res.writeHead(200);
    res.end('OK');
  } else if (req.url === '/ready') {
    // 检查依赖服务是否就绪
    if (dbConnected && redisConnected) {
      res.writeHead(200);
      res.end('Ready');
    } else {
      res.writeHead(503);
      res.end('Not Ready');
    }
  } else {
    res.writeHead(404);
    res.end('Not Found');
  }
});

server.listen(3000, () => {
  console.log('Server started on port 3000');

  // 通知 PM2 应用已就绪（需要 wait_ready: true）
  if (process.send) {
    process.send('ready');
  }
});

// 优雅关闭处理
process.on('SIGINT', () => {
  console.log('Received SIGINT, shutting down gracefully...');
  server.close(() => {
    console.log('HTTP server closed');
    // 清理数据库连接等资源
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully...');
  server.close(() => {
    console.log('HTTP server closed');
    process.exit(0);
  });
});
```

---

## 四、常见坑与最佳实践

### 4.1 信号处理相关

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| **容器收不到 SIGTERM** | 使用 shell 脚本作为入口 | 直接使用 `pm2-runtime` 或 `["/bin/sh", "-c", "..."]` |
| **优雅停止时间不足** | kill_timeout < 应用清理时间 | 增加 `terminationGracePeriodSeconds` 和 `kill_timeout` |
| **K8s 驱逐太快** | 内存 limit 设置过低 | 合理设置 memory requests/limits |

### 4.2 重启循环问题

> **坑 10**：PM2 重启循环 + K8s CrashLoopBackOff
>
> 常见原因：
> 1. 应用启动失败（端口占用、配置错误）
> 2. 内存不足被 OOM Killer
> 3. 数据库连接失败
> 4. 依赖服务不可用
>
> 排查步骤：
> ```bash
> # 查看 PM2 日志
> pm2 logs --lines 100
>
> # 查看进程状态
> pm2 show <app-name>
>
> # 手动启动测试
> node server.js
> ```

### 4.3 生产环境检查清单

```bash
# 1. 禁止 watch 模式
watch: false

# 2. 合理设置内存限制
max_memory_restart: '512M'  # 根据应用实际需求

# 3. 启用优雅停止
wait_ready: true
kill_timeout: 5000  # 与 K8s terminationGracePeriodSeconds 协调

# 4. 日志输出到 stdout
out_file: '/dev/stdout'
error_file: '/dev/stderr'

# 5. 设置合理的 min_uptime
min_uptime: '10s'

# 6. 限制重启次数
max_restarts: 10

# 7. 生产环境 NODE_ENV
env_production: {
  NODE_ENV: 'production'
}
```

### 4.4 K8s 特定注意事项

1. **不要在 K8s 中使用 PM2 集群模式做负载均衡**
   - 使用 K8s Service + Ingress 做负载均衡
   - PM2 实例数应与 Pod 副本数匹配

2. **配置与 K8s 资源限制协调**
   ```javascript
   // 如果 K8s memory limit = 512Mi
   // PM2 max_memory_restart 应 < 512Mi，如 400Mi
   max_memory_restart: '400M'
   ```

3. **使用 K8s ConfigMap 存储环境特定配置**
   ```yaml
   # K8s ConfigMap
   data:
    ecosystem.config.js: |
      module.exports = { ... }
   ```

4. **多副本部署时的 instance_var**
   ```javascript
   instance_var: 'PM2_INSTANCE_ID'  // 每个实例有唯一 ID
   ```

### 4.5 完整配置示例

```javascript
// ecosystem.config.js
module.exports = {
  apps: [
    {
      // 基本信息
      name: 'api-server',
      script: './server.js',

      // 执行模式
      instances: 'max',
      exec_mode: 'cluster',

      // 文件监控（生产环境关闭）
      watch: ['server', 'config'],
      ignore_watch: ['node_modules', 'logs'],

      // 内存管理
      max_memory_restart: '1G',

      // 重启行为
      autorestart: true,
      max_restarts: 10,
      min_uptime: '5s',
      restart_delay: 4000,

      // 优雅关闭
      kill_timeout: 5000,
      wait_ready: true,
      listen_timeout: 3000,

      // 日志
      error_file: './logs/api-err.log',
      out_file: './logs/api-out.log',
      log_date_format: 'YYYY-MM-DD HH:mm Z',
      merge_logs: true,

      // Cron 重启
      cron_restart: '0 0 * * *',

      // 参数
      args: '--production',
      script_args: ['--port', '8080'],

      // Node.js 特定
      node_args: '--max-old-space-size=2048',
      interpreter: 'node',

      // 环境变量
      env: {
        NODE_ENV: 'development',
        PORT: 3000,
        LOG_LEVEL: 'debug'
      },
      env_production: {
        NODE_ENV: 'production',
        PORT: 8080,
        LOG_LEVEL: 'info'
      },

      // Source map 支持
      source_map_support: true,

      // 实例变量
      instance_var: 'INSTANCE_ID'
    },
    {
      name: 'worker-queue',
      script: './worker.js',
      instances: 2,
      exec_mode: 'cluster',
      env: {
        WORKER_TYPE: 'queue-processor'
      }
    },
    {
      name: 'scheduled-task',
      script: './tasks/cleanup.js',
      cron_restart: '0 2 * * *',
      autorestart: false,
      watch: false
    }
  ]
};
```

---

## 五、常用命令速查

### 5.1 基础命令

```bash
# 启动
pm2 start ecosystem.config.js
pm2 start server.js --name my-app -i 4

# 环境切换
pm2 start ecosystem.config.js --env production
pm2 start ecosystem.config.js --env staging

# 重载（零停机）
pm2 reload my-app

# 重启
pm2 restart my-app

# 停止
pm2 stop my-app

# 删除
pm2 delete my-app

# 列出所有进程
pm2 list
pm2 l          # 简写
pm2 status
```

### 5.2 监控命令

```bash
# 实时监控（显示每个进程的 CPU/内存）
pm2 monit

# 查看日志
pm2 logs              # 所有日志
pm2 logs my-app       # 指定应用日志
pm2 logs --lines 100  # 最近 100 行
pm2 logs --err        # 仅错误日志

# 查看详情
pm2 show my-app
pm2 describe my-app

# 查看详细信息
pm2 info my-app
```

### 5.3 集群管理

```bash
# 扩展实例数
pm2 scale my-app 8      # 扩展到 8 个实例
pm2 scale my-app +3     # 当前数量 +3
pm2 scale my-app -2     # 当前数量 -2

# 负载均衡模式（集群）
pm2 start server.js -i 4        # 4 个实例
pm2 start server.js -i max      # 所有 CPU 核心
pm2 start server.js -i -1       # CPU 核心数 -1
```

### 5.4 日志管理

```bash
# 安装日志轮转
pm2 install pm2-logrotate

# 配置日志轮转
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 30
pm2 set pm2-logrotate:compress true

# 清理日志
pm2 flush              # 清空所有日志
pm2 flush my-app       # 清空指定应用日志
```

### 5.5 开机自启

```bash
# 保存当前进程列表
pm2 save

# 生成启动脚本
pm2 startup

# 常用启动方式
pm2 startup systemd
pm2 startup upstart
pm2 startup launchd
pm2 startup systemv

# 恢复保存的进程
pm2 resurrect
```

### 5.6 其他命令

```bash
# 压缩内存（减少内存占用）
pm2 gc

# 重置元数据
pm2 reset my-app

# 发送消息到进程
pm2 sendSignal SIGTERM my-app

# 导出/导入进程列表
pm2 dump            # 导出
pm2 resurrect      # 导入

# 更新 PM2
pm2 update

# 诊断
pm2 doctor
```

### 5.7 JSON 格式启动

```bash
# 使用 JSON 配置文件启动
pm2 start ecosystem.json

# 命令行参数覆盖
pm2 start ecosystem.json --env production
pm2 start server.js -i 4 --max-memory-restart 500M
```

---

## 附录

### A. 环境变量

PM2 会自动注入以下环境变量：

| 变量 | 说明 |
|------|------|
| `PM2_HOME` | PM2 主目录（通常 ~/.pm2） |
| `PM2_PID` | PM2 守护进程 PID |
| `PM2_INSTANCE_ID` | 实例唯一 ID（cluster 模式） |
| `PM2_INSTANCE_PID` | 进程 PID |
| `NODE_ENV` | 当前环境 |

### B. 信号处理流程

```
PM2 停止/重启进程时：

1. 发送 SIGINT 信号
   ↓
2. 应用收到信号，执行清理（关闭数据库、保存状态等）
   ↓
3. 应用在 kill_timeout (默认 1.6s) 内退出
   ↓
4. 优雅退出成功
   ↓
5. 如果超时 → 发送 SIGKILL 强制终止
```

### C. 资源链接

- 官方文档：https://pm2.keymetrics.io/
- GitHub：https://github.com/Unitech/pm2
- 源码：https://github.com/Unitech/pm2/tree/master

---

*文档最后更新：2026-02-25*
