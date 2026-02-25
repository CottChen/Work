# OpenClaw 定时任务与心跳机制完整分析

> 文档创建时间：2026-02-25
> 分析范围：定时任务调度器、心跳唤醒机制、任务执行流程

---

## 目录

1. [架构总览](#架构总览)
2. [定时任务的两种模式](#定时任务的两种模式)
3. [心跳机制](#心跳机制)
4. [心跳与定时任务的关系](#心跳与定时任务的关系)
5. [关键时序参数](#关键时序参数)
6. [数据流向](#数据流向)
7. [核心文件位置](#核心文件位置)

---

## 架构总览

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              OpenClaw 架构总览                                    │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│  定时任务调度器 (CronService)                                                   │
│  文件: src/cron/service/timer.ts                                                │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  任务执行核心 (executeJobCore)                                                  │
│  - main 模式: 主会话模式                                                         │
│  - isolated 模式: 独立代理模式                                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  心跳唤醒机制 (heartbeat-wake)                                                  │
│  文件: src/infra/heartbeat-wake.ts                                              │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│  心跳执行器 (heartbeat-runner)                                                  │
│  文件: src/infra/heartbeat-runner.ts                                            │
└─────────────────────────────────────────────────────────────────────────────────┘
```

```
  OpenClaw 定时任务与心跳机制关系
  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │                              OpenClaw 架构总览                                    │
  └─────────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │  定时任务调度器                            │
  │  ┌──────────────────────────────────────────────────────────────────────────┐   │
  │  │  armTimer()                                                              │   │
  │  │    ├─ 计算下次任务到期时间                            │   │
  │  │    ├─ 设置最大延迟 60 秒 (MAX_TIMER_DELAY_MS)                            │   │
  │  │    └─ setTimeout → onTimer()                                             │   │
  │  │                                                                          │   │
  │  │  onTimer() [定时器触发]                                                   │   │
  │  │    ├─ findDueJobs() → 找到所有到期的任务                                  │   │
  │  │    ├─ executeJobCore() → 执行每个任务                                     │   │
  │  │    └─ applyJobResult() → 更新任务状态 + 重新计算下次运行时间              │   │
  │  └──────────────────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │  任务执行核心                                         │
  │  ┌──────────────────────────────────────────────────────────────────────────┐   │
  │  │  executeJobCore(state, job)                                               │   │
  │  │                                                                          │   │
  │  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
  │  │  │ 模式一: main 模式 (主会话模式)                                         │  │   │
  │  │  │  ├─ resolveJobPayloadTextForMain(job) → 解析任务文本                 │  │   │
  │  │  │  ├─ enqueueSystemEvent(text) → 加入系统事件队列                      │  │   │
  │  │  │  │                                                                   │  │   │
  │  │  │  ├─ IF wakeMode == "now":                                            │  │   │
  │  │  │  │   └─ runHeartbeatOnce(reason, agentId, sessionKey)                │  │   │
  │  │  │  │      ├─ 循环等待直到心跳完成 (最多 2 分钟)                         │  │   │
  │  │  │  │      └─ 返回心跳结果                                               │  │   │
  │  │  │  │                                                                   │  │   │
  │  │  │  └─ ELSE:                                                            │  │   │
  │  │  │      └─ requestHeartbeatNow(reason, agentId, sessionKey)             │  │   │
  │  │  │          └─ 心跳将在下次周期执行时处理系统事件                        │  │   │
  │  │  │                                                                       │  │   │
  │  │  │  返回: { status, error?, summary? }                                  │  │   │
  │  │  └────────────────────────────────────────────────────────────────────┘  │   │
  │  │                                                                          │   │
  │  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
  │  │  │ 模式二: isolated 模式 (独立代理模式)                                    │  │   │
  │  │  │  ├─ runIsolatedAgentJob(job) → 在独立会话中运行代理                   │  │   │
  │  │  │  │                                                                   │  │   │
  │  │  │  ├─ IF wakeMode == "now":                                            │  │   │
  │  │  │  │   └─ requestHeartbeatNow() → 触发心跳发送摘要                      │  │   │
  │  │  │  │                                                                   │  │   │
  │  │  │  └─ 返回执行结果摘要                                                  │  │   │
  │  │  │                                                                       │  │   │
  │  │  │  返回: { status, error?, summary?, sessionId?, usage? }              │  │   │
  │  │  └────────────────────────────────────────────────────────────────────┘  │   │
  │  └──────────────────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │  心跳唤醒机制                                  │
  │  ┌──────────────────────────────────────────────────────────────────────────┐   │
  │  │  requestHeartbeatNow({ reason, agentId, sessionKey, coalesceMs })        │   │
  │  │    │                                                                     │   │
  │  │    ├─ queuePendingWakeReason() → 将唤醒请求加入队列                       │   │
  │  │    │   └─ 按优先级排序: RETRY(0) > INTERVAL(1) > DEFAULT(2) > ACTION(3)   │   │
  │  │    │                                                                     │   │
  │  │    └─ schedule(coalesceMs) → 安排心跳执行时间                             │   │
  │  │        └─ setTimeout → HeartbeatWakeHandler()                            │   │
  │  │                                                                          │   │
  │  │  HeartbeatWakeHandler(params) → 唤醒处理器                                │   │
  │  │    └─ 调用 runHeartbeatOnce(params)                                      │   │
  │  └──────────────────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │  心跳执行器                               │
  │  ┌──────────────────────────────────────────────────────────────────────────┐   │
  │  │  runHeartbeatOnce({ cfg, agentId, sessionKey, heartbeat, reason, deps }) │   │
  │  │                                                                          │   │
  │  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
  │  │  │ 1. 预检查                                     │  │   │
  │  │  │    ├─ 检查是否启用心跳                                               │  │   │
  │  │  │    ├─ 检查是否在活跃时间内                                           │  │   │
  │  │  │    ├─ 检查命令队列是否为空                    │  │   │
  │  │  │    └─ resolveHeartbeatPreflight() → 检查系统事件                       │  │   │
  │  │  │        └─ peekSystemEventEntries() → 获取待处理的系统事件             │  │   │
  │  │  │            └─ 包含定时任务的事件                   │  │   │
  │  │  └────────────────────────────────────────────────────────────────────┘  │   │
  │  │                                                                          │   │
  │  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
  │  │  │ 2. 构建心跳消息                                                       │  │   │
  │  │  │    ├─ IF 有定时任务事件 (isCronEventReason):                          │  │   │
  │  │  │    │   └─ buildCronEventPrompt(cronEvents) → 构建任务提示词          │  │   │
  │  │  │    │                                                                 │  │   │
  │  │  │    ├─ IF 有执行完成事件 (hasExecCompletion):                          │  │   │
  │  │  │    │   └─ EXEC_EVENT_PROMPT → "请将命令结果转达给用户"                │  │   │
  │  │  │    │                                                                 │  │   │
  │  │  │    └─ ELSE:                                                          │  │   │
  │  │  │        └─ resolveHeartbeatPrompt() → 默认心跳提示词                   │  │   │
  │  │  └────────────────────────────────────────────────────────────────────┘  │   │
  │  │                                                                          │   │
  │  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
  │  │  │ 3. 调用 AI 模型                                                       │  │   │
  │  │  │    └─ getReplyFromConfig(ctx, { isHeartbeat: true }, cfg)           │  │   │
  │  │  │        └─ 传入系统事件 + 心跳提示词，获取 AI 响应                     │  │   │
  │  │  └────────────────────────────────────────────────────────────────────┘  │   │
  │  │                                                                          │   │
  │  │  ┌────────────────────────────────────────────────────────────────────┐  │   │
  │  │  │ 4. 处理响应                                                           │  │   │
  │  │  │    ├─ normalizeHeartbeatReply() → 处理响应内容                        │  │   │
  │  │  │    │   └─ stripHeartbeatToken() → 移除 HEARTBEAT_OK 标记              │  │   │
  │  │  │    │                                                                 │  │   │
  │  │  │    ├─ IF 响应为空或只有 HEARTBEAT_OK:                                 │  │   │
  │  │  │    │   └─ pruneHeartbeatTranscript() → 清理会话记录                   │  │   │
  │  │  │    │                                                                 │  │   │
  │  │  │    └─ deliverOutboundPayloads() → 发送响应到用户                       │  │   │
  │  │  └────────────────────────────────────────────────────────────────────┘  │   │
  │  │                                                                          │   │
  │  │  返回: { status: "ran" | "skipped" | "failed", durationMs, reason? }     │   │
  │  └──────────────────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────────────────┘
                                        │
                                        ▼
  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │  心跳定时器                           │
  │  ┌──────────────────────────────────────────────────────────────────────────┐   │
  │  │  startHeartbeatRunner() → 启动心跳运行器                                  │   │
  │  │    │                                                                     │   │
  │  │    ├─ resolveHeartbeatAgents() → 获取需要心跳的代理列表                   │   │
  │  │    │                                                                     │   │
  │  │    ├─ scheduleNext() → 安排下次心跳                                       │   │
  │  │    │   └─ setTimeout(nextDue - now, requestHeartbeatNow("interval"))     │   │
  │  │    │       └─ 默认间隔: 60 秒 (DEFAULT_HEARTBEAT_EVERY)                   │   │
  │  │    │                                                                     │   │
  │  │    └─ setHeartbeatWakeHandler(run) → 注册唤醒处理器                       │   │
  │  └──────────────────────────────────────────────────────────────────────────┘   │
  └─────────────────────────────────────────────────────────────────────────────────┘


  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │                              数据流向总结                                        │
  └─────────────────────────────────────────────────────────────────────────────────┘

    定时任务到期 (Cron 触发)
           │
           ▼
    executeJobCore()
           │
           ├─── main 模式 ──→ enqueueSystemEvent() ──→ [系统事件队列]
           │                                                           │
           │                                                           ▼
           │                                                    runHeartbeatOnce()
           │                                                           │
           │                                                           ▼
           │                                                    peekSystemEventEntries()
           │                                                           │
           ▼                                                           ▼
    isolated 模式 ──→ runIsolatedAgentJob() ──→ requestHeartbeatNow()
                                                             │
           ┌──────────────────────────────────────────────────────┘
           │
           ▼
    [心跳唤醒队列]
           │
           ▼
    HeartbeatWakeHandler()
           │
           ▼
    runHeartbeatOnce() ──→ getReplyFromConfig() ──→ AI 处理系统事件
           │
           ▼
    deliverOutboundPayloads() ──→ 发送到用户


  ┌─────────────────────────────────────────────────────────────────────────────────┐
  │                              关键时序参数                                          │
  └─────────────────────────────────────────────────────────────────────────────────┘

    参数                          值                          说明
    ────────────────────────────────────────────────────────────────────────────────
    MAX_TIMER_DELAY_MS            60 秒                       定时器最大延迟
    MIN_REFIRE_GAP_MS             2 秒                        相同任务最小重触发间隔
    DEFAULT_JOB_TIMEOUT_MS        10 分钟                     默认任务超时
    DEFAULT_HEARTBEAT_EVERY       60 秒                       默认心跳间隔
    DEFAULT_COALESCE_MS           250 ms                      心跳唤醒合并延迟
    DEFAULT_RETRY_MS              1 秒                        心跳重试延迟
    wakeNowHeartbeatBusyMaxWaitMs 2 分钟                      等待心跳完成的最大时间
    wakeNowHeartbeatBusyRetryDelayMs 250 ms                  忙碌时重试延迟

  总结

  定时任务的两种模式
  ┌──────────┬──────────┬──────────────┬────────────────────────────────────────────────┬──────────────────────────────┐
  │   模式   │ 触发方式 │     输入     │                      输出                      │           心跳作用           │
  ├──────────┼──────────┼──────────────┼────────────────────────────────────────────────┼──────────────────────────────┤
  │ main     │ Cron到期 │ 系统事件文本 │ {status, error?, summary?}                     │ 心跳处理系统事件，调用AI响应 │
  ├──────────┼──────────┼──────────────┼────────────────────────────────────────────────┼──────────────────────────────┤
  │ isolated │ Cron到期 │ 代理任务配置 │ {status, error?, summary?, sessionId?, usage?} │ 心跳可选发送任务摘要         │
  └──────────┴──────────┴──────────────┴────────────────────────────────────────────────┴──────────────────────────────┘
  心跳在定时任务中的作用

  1. main 模式：定时任务将事件加入队列 → 心跳读取事件 → AI 处理 → 返回结果给用户
  2. isolated 模式：定时任务独立执行 → 心跳可选发送摘要通知

  心跳可获得的信息

  - 定时任务的系统事件（通过 peekSystemEventEntries()）
  - 任务执行状态（通过 job.state）
  - 心跳本身的运行状态（连接、消息数、运行时间等）
```

---

## 定时任务的两种模式

### 模式一：main 模式（主会话模式）

**代码位置：** `src/cron/service/timer.ts:459-522`

#### 输入参数

```typescript
{
  state: CronServiceState,  // 定时服务状态
  job: CronJob             // 定时任务对象
}
```

#### 执行流程

```typescript
// 1. 解析任务文本
const text = resolveJobPayloadTextForMain(job);

// 2. 将事件加入系统事件队列
state.deps.enqueueSystemEvent(text, {
  agentId: job.agentId,
  sessionKey: job.sessionKey,
  contextKey: `cron:${job.id}`,  // 标记为定时任务事件
});

// 3. 根据 wakeMode 决定是否立即触发心跳
if (job.wakeMode === "now" && state.deps.runHeartbeatOnce) {
  // 立即执行心跳，最多等待 2 分钟
  const heartbeatResult = await state.deps.runHeartbeatOnce({
    reason: `cron:${job.id}`,
    agentId: job.agentId,
    sessionKey: job.sessionKey,
  });
  return { status: "ok", summary: text };
} else {
  // 在下次心跳周期处理
  state.deps.requestHeartbeatNow({
    reason: `cron:${job.id}`,
    agentId: job.agentId,
    sessionKey: job.sessionKey,
  });
  return { status: "ok", summary: text };
}
```

#### 输出结果

```typescript
{
  status: "ok" | "skipped" | "error",
  error?: string,
  summary?: string
}
```

---

### 模式二：isolated 模式（独立代理模式）

**代码位置：** `src/cron/service/timer.ts:524-569`

#### 输入参数

```typescript
{
  state: CronServiceState,
  job: CronJob
}
```

#### 执行流程

```typescript
// 1. 在独立会话中运行代理任务
const res = await state.deps.runIsolatedAgentJob({
  job,
  agentId: job.agentId,
});

// 2. 根据 wakeMode 决定是否触发心跳
if (job.wakeMode === "now") {
  state.deps.requestHeartbeatNow({
    reason: `cron:${job.id}`,
    agentId: job.agentId,
    sessionKey: job.sessionKey,
  });
}

// 3. 返回执行结果
return {
  status: res.status,
  summary: res.summary,
  sessionId: res.sessionId,
  usage: res.usage,
};
```

#### 输出结果

```typescript
{
  status: "ok" | "error" | "skipped",
  error?: string,
  summary?: string,
  sessionId?: string,
  sessionKey?: string,
  model?: string,
  provider?: string,
  usage?: CronUsageSummary  // { tokens, cost, ... }
}
```

---

## 心跳机制

### 1. 心跳唤醒调度

**文件：** `src/infra/heartbeat-wake.ts`

#### 核心函数

```typescript
// 请求立即执行心跳
requestHeartbeatNow(opts?: {
  reason?: string;           // 触发原因
  coalesceMs?: number;       // 合并延迟（默认 250ms）
  agentId?: string;          // 目标代理 ID
  sessionKey?: string;       // 目标会话
})

// 注册心跳唤醒处理器
setHeartbeatWakeHandler(handler: HeartbeatWakeHandler | null)
```

#### 唤醒队列优先级

```typescript
const REASON_PRIORITY = {
  RETRY: 0,      // 重试
  INTERVAL: 1,   // 定时触发
  DEFAULT: 2,    // 默认
  ACTION: 3,     // 用户动作
};
```

### 2. 心跳执行器

**文件：** `src/infra/heartbeat-runner.ts`

#### 执行流程

```typescript
async function runHeartbeatOnce(opts: {
  cfg?: OpenClawConfig;
  agentId?: string;
  sessionKey?: string;
  heartbeat?: HeartbeatConfig;
  reason?: string;
  deps?: HeartbeatDeps;
}): Promise<HeartbeatRunResult>
```

#### 步骤详解

##### 步骤 1：预检查

```typescript
// 检查是否启用心跳
if (!heartbeatsEnabled) return { status: "skipped", reason: "disabled" };

// 检查是否在活跃时间内
if (!isWithinActiveHours(cfg, heartbeat, startedAt))
  return { status: "skipped", reason: "quiet-hours" };

// 检查命令队列是否为空
if (queueSize > 0) return { status: "skipped", reason: "requests-in-flight" };

// 获取待处理的系统事件
const preflight = await resolveHeartbeatPreflight({
  cfg, agentId, heartbeat, forcedSessionKey, reason
});
const pendingEventEntries = peekSystemEventEntries(sessionKey);
```

##### 步骤 2：构建心跳消息

```typescript
// 检查是否有定时任务事件
const cronEvents = pendingEventEntries
  .filter(event => event.contextKey?.startsWith("cron:"))
  .map(event => event.text);

// 检查是否有执行完成事件
const hasExecCompletion = pendingEvents.some(isExecCompletionEvent);

// 根据事件类型选择提示词
const prompt = hasExecCompletion
  ? EXEC_EVENT_PROMPT  // "请将命令结果转达给用户"
  : hasCronEvents
    ? buildCronEventPrompt(cronEvents)
    : resolveHeartbeatPrompt(cfg, heartbeat);
```

##### 步骤 3：调用 AI 模型

```typescript
const replyResult = await getReplyFromConfig(
  {
    Body: appendCronStyleCurrentTimeLine(prompt, cfg, startedAt),
    From: sender,
    To: sender,
    Provider: hasExecCompletion ? "exec-event" : hasCronEvents ? "cron-event" : "heartbeat",
    SessionKey: sessionKey,
  },
  { isHeartbeat: true },
  cfg
);
```

##### 步骤 4：处理响应

```typescript
// 处理响应内容
const normalized = normalizeHeartbeatReply(replyPayload, responsePrefix, ackMaxChars);

// 如果响应为空或只有 HEARTBEAT_OK，清理会话记录
if (!normalized.text && !normalized.hasMedia) {
  await pruneHeartbeatTranscript(transcriptState);
  return { status: "ran", durationMs };
}

// 发送响应到用户
await deliverOutboundPayloads({
  cfg,
  channel: delivery.channel,
  to: delivery.to,
  payloads: [{ text: normalized.text, mediaUrls }],
  agentId,
  deps,
});

return { status: "ran", durationMs };
```

### 3. 心跳定时器

**文件：** `src/infra/heartbeat-runner.ts:955-1189`

```typescript
export function startHeartbeatRunner(opts: {
  cfg?: OpenClawConfig;
  runtime?: RuntimeEnv;
  abortSignal?: AbortSignal;
}): HeartbeatRunner
```

#### 定时逻辑

```typescript
// 计算下次心跳时间
const nextDue = agent.lastRunMs + agent.intervalMs;

// 安排下次心跳
const delay = Math.max(0, nextDue - now);
state.timer = setTimeout(() => {
  requestHeartbeatNow({ reason: "interval", coalesceMs: 0 });
}, delay);
```

---

## 心跳与定时任务的关系

### 数据流向图

```
定时任务到期 (Cron 触发)
       │
       ▼
executeJobCore()
       │
       ├─── main 模式 ──→ enqueueSystemEvent() ──→ [系统事件队列]
       │                                                           │
       │                                                           ▼
       │                                                    runHeartbeatOnce()
       │                                                           │
       ▼                                                           ▼
isolated 模式 ──→ runIsolatedAgentJob() ──→ requestHeartbeatNow()
                                                           │
         ┌──────────────────────────────────────────────────────┘
         │
         ▼
[心跳唤醒队列]
       │
       ▼
HeartbeatWakeHandler()
       │
       ▼
runHeartbeatOnce() ──→ getReplyFromConfig() ──→ AI 处理系统事件
       │
       ▼
deliverOutboundPayloads() ──→ 发送到用户
```

### 交互时序图

```
┌─────────┐     ┌─────────┐     ┌───────────┐     ┌─────────┐     ┌─────────┐
│  Cron   │     │  Timer  │     │ Heartbeat │     │   AI    │     │  User   │
└────┬────┘     └────┬────┘     └─────┬─────┘     └────┬────┘     └────┬────┘
     │               │                │                │                │
     │  任务到期      │                │                │                │
     │──────────────>│                │                │                │
     │               │                │                │                │
     │               │  main模式      │                │                │
     │               │  enqueueSystemEvent            │                │
     │               │───────────────>│                │                │
     │               │                │                │                │
     │               │                │  peekSystemEventEntries        │
     │               │                │<───────────────┤                │
     │               │                │                │                │
     │               │                │  getReplyFromConfig            │
     │               │                │──────────────────────────────>│
     │               │                │                │                │
     │               │                │  AI Response                  │
     │               │                │<──────────────────────────────┤
     │               │                │                │                │
     │               │                │  deliverOutbound               │
     │               │                │───────────────────────────────>│
     │               │                │                │                │
```

### wakeMode 参数说明

| 值 | 说明 | 行为 |
|---|------|------|
| `"next-heartbeat"` | 下次心跳处理 | 任务执行后，心跳将在下次周期处理系统事件 |
| `"now"` | 立即处理 | 任务执行后立即触发心跳，最多等待 2 分钟直到完成 |

---

## 关键时序参数

### 定时器参数

| 参数 | 值 | 说明 | 文件位置 |
|------|---|------|----------|
| `MAX_TIMER_DELAY_MS` | 60 秒 | 定时器最大延迟 | `src/cron/service/timer.ts:16` |
| `MIN_REFIRE_GAP_MS` | 2 秒 | 相同任务最小重触发间隔 | `src/cron/service/timer.ts:25` |
| `DEFAULT_JOB_TIMEOUT_MS` | 10 分钟 | 默认任务超时 | `src/cron/service/timer.ts:32` |

### 心跳参数

| 参数 | 值 | 说明 | 文件位置 |
|------|---|------|----------|
| `DEFAULT_HEARTBEAT_EVERY` | 60 秒 | 默认心跳间隔 | `src/auto-reply/heartbeat.ts` |
| `DEFAULT_COALESCE_MS` | 250 ms | 心跳唤醒合并延迟 | `src/infra/heartbeat-wake.ts:36` |
| `DEFAULT_RETRY_MS` | 1 秒 | 心跳重试延迟 | `src/infra/heartbeat-wake.ts:37` |

### 等待参数

| 参数 | 值 | 说明 | 文件位置 |
|------|---|------|----------|
| `wakeNowHeartbeatBusyMaxWaitMs` | 2 分钟 | 等待心跳完成的最大时间 | `src/cron/service/timer.ts:479` |
| `wakeNowHeartbeatBusyRetryDelayMs` | 250 ms | 忙碌时重试延迟 | `src/cron/service/timer.ts:480` |

---

## 数据流向

### 系统事件流

```typescript
// 1. 定时任务创建系统事件
state.deps.enqueueSystemEvent(text, {
  agentId: job.agentId,
  sessionKey: job.sessionKey,
  contextKey: `cron:${job.id}`,
});

// 2. 心跳读取系统事件
const pendingEventEntries = peekSystemEventEntries(sessionKey);

// 3. 过滤定时任务事件
const cronEvents = pendingEventEntries
  .filter(event => event.contextKey?.startsWith("cron:"))
  .map(event => event.text);

// 4. 构建提示词
const prompt = buildCronEventPrompt(cronEvents);
```

### 任务状态流

```typescript
// 任务状态
type CronJobState = {
  nextRunAtMs?: number;        // 下次运行时间
  runningAtMs?: number;        // 开始运行时间
  lastRunAtMs?: number;        // 上次运行时间
  lastStatus?: "ok" | "error" | "skipped";
  lastError?: string;          // 上次错误信息
  lastDurationMs?: number;     // 上次执行时长
  consecutiveErrors?: number;  // 连续错误次数
  scheduleErrorCount?: number; // 调度错误次数
};

// 结果应用
function applyJobResult(state, job, result) {
  job.state.lastStatus = result.status;
  job.state.lastError = result.error;
  job.state.lastDurationMs = result.endedAt - result.startedAt;
  // ... 计算下次运行时间
}
```

### 心跳事件流

```typescript
// 发出心跳事件
emitHeartbeatEvent({
  status: "sent" | "ok-empty" | "ok-token" | "skipped" | "failed",
  to: delivery.to,
  preview: previewText?.slice(0, 200),
  durationMs: Date.now() - startedAt,
  hasMedia: mediaUrls.length > 0,
  channel: delivery.channel,
  accountId: delivery.accountId,
});
```

---

## 核心文件位置

### 定时任务相关

| 文件 | 功能 |
|------|------|
| `src/cron/service/timer.ts` | 定时器核心逻辑，`armTimer()`, `onTimer()`, `executeJobCore()` |
| `src/cron/service/store.ts` | 任务状态持久化 |
| `src/cron/service/state.ts` | 服务状态管理 |
| `src/cron/types.ts` | 类型定义 |
| `src/cron/delivery.ts` | 交付计划 |

### 心跳相关

| 文件 | 功能 |
|------|------|
| `src/infra/heartbeat-wake.ts` | 心跳唤醒调度，`requestHeartbeatNow()`, `setHeartbeatWakeHandler()` |
| `src/infra/heartbeat-runner.ts` | 心跳执行器，`runHeartbeatOnce()`, `startHeartbeatRunner()` |
| `src/infra/heartbeat-reason.ts` | 心跳原因分类 |
| `src/infra/heartbeat-events.ts` | 心跳事件 |
| `src/infra/heartbeat-events-filter.ts` | 心跳事件过滤 |
| `src/infra/heartbeat-visibility.ts` | 心跳可见性 |
| `src/infra/heartbeat-active-hours.ts` | 活跃时间检查 |
| `src/auto-reply/heartbeat.ts` | 心跳提示词 |

### 系统事件相关

| 文件 | 功能 |
|------|------|
| `src/infra/system-events.ts` | 系统事件管理，`peekSystemEventEntries()` |
| `src/cron/service/state.ts` | 事件队列 |

---

## 附录：错误处理

### 指数退避策略

```typescript
const ERROR_BACKOFF_SCHEDULE_MS = [
  30_000,        // 1st error  →  30 s
  60_000,        // 2nd error  →   1 min
  5 * 60_000,    // 3rd error  →   5 min
  15 * 60_000,   // 4th error  →  15 min
  60 * 60_000,   // 5th+ error →  60 min
];
```

### 自动禁用规则

- 连续调度错误达到 3 次后自动禁用任务
- 一次性任务（`at` 类型）执行后自动禁用

---

## 总结

### 关键理解

1. **定时任务和心跳是两个独立但协同的系统**
   - 定时任务负责按时间触发
   - 心跳负责处理事件并与 AI 交互

2. **main 模式是主要的集成方式**
   - 定时任务通过系统事件队列与心跳通信
   - 心跳读取事件并调用 AI 处理
   - AI 响应通过心跳发送给用户

3. **isolated 模式适合独立任务**
   - 在独立会话中执行代理任务
   - 心跳可选发送摘要通知

4. **心跳是定时任务结果传递的关键桥梁**
   - 没有心跳，定时任务的结果无法传递给用户
   - 心跳的 `wakeMode` 参数控制触发时机

### 快速参考

```typescript
// 创建定时任务（main 模式）
{
  name: "daily-summary",
  schedule: { kind: "cron", expression: "0 9 * * *" },
  payload: { kind: "systemEvent", text: "生成每日摘要" },
  sessionTarget: "main",
  wakeMode: "next-heartbeat",  // 或 "now"
}

// 心跳配置
{
  heartbeat: {
    every: "5m",      // 每 5 分钟
    prompt: "处理待办事项",
    target: "last",   // 发送给最后对话的用户
  }
}
```
