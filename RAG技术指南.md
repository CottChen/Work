# DB-GPT RAG 技术指南

本文档整理了 DB-GPT 项目中 RAG（检索增强生成）相关技术的问答内容。

---

## 1. Rerank (重排序)

### 1.1 项目中的 Rerank 实现

DB-GPT 项目中有多层 rerank 实现：

| 层级 | 文件位置 | 说明 |
|------|----------|------|
| Embedding 层 | `packages/dbgpt-core/src/dbgpt/rag/embedding/rerank.py` | 各种 rerank 模型实现 |
| Retriever 层 | `packages/dbgpt-core/src/dbgpt/rag/retriever/rerank.py` | 排序器实现 |
| Operator 层 | `packages/dbgpt-core/src/dbgpt/rag/operators/rerank.py` | AWEL 算子 |

**支持的 Rerank 模型**：

- **本地模型**：
  - `CrossEncoderRerankEmbeddings` - HuggingFace sentence-transformers CrossEncoder
  - `QwenRerankEmbeddings` - Qwen3-Reranker 系列

- **云 API 模型**：
  - `SiliconFlowRerankEmbeddings` - SiliconFlow API
  - `OpenAPIRerankEmbeddings` - 通用 OpenAPI
  - `TeiRerankEmbeddings` - HuggingFace TEI
  - `InfiniAIRerankEmbeddings` - InfiniAI API

### 1.2 Reranker 模型大小

| 模型 | 参数量 | 模型大小 (FP16) |
|------|--------|----------------|
| BAAI/bge-reranker-base | ~270M | ~540MB |
| BAAI/bge-reranker-v2-m3 | ~560M | ~1.1GB |
| BAAI/bge-reranker-large | ~1B | ~2GB |
| Qwen/Qwen3-Reranker-0.6B | ~600M | ~1.2GB |

**推荐配置**：
- CPU 环境：bge-reranker-base (270M)
- GPU 环境：bge-reranker-v2-m3 或更大

### 1.3 非模型 Rerank 方式

| 方式 | 说明 |
|------|------|
| **RRF** | Reciprocal Rank Fusion，倒数排名融合 |
| **DefaultRanker** | 按原始分数排序并去重 |
| **BM25** | 基于词项的统计排序 |
| **自定义排序** | 传入自定义排序函数 |

---

## 2. 排序算法原理

### 2.1 BM25 (Okapi BM25)

BM25 是 Elasticsearch/Lucene 默认的相似度算法，是 TF-IDF 的改进版本。

**核心公式**：

```
score(Q, D) = Σ IDF(qi) × (f(qi, D) × (k1 + 1)) / (f(qi, D) + k1 × (1 - b + b × |D| / avgdl))
```

**关键概念**：
- **TF (Term Frequency)**：词在文档中出现次数越多，越相关
- **IDF (Inverse Document Frequency)**：词在越多文档中出现，权重越低
- **Document Length**：文档长度归一化

### 2.2 RRF (Reciprocal Rank Fusion)

**核心公式**：

```
RRF_score(d) = Σ 1 / (k + rank_i(d))
```

- `k`：常数（默认 60），防止除零
- `rank_i(d)`：文档 d 在第 i 个检索结果中的排名

**特点**：
- ✅ 无需训练，无需调参
- ✅ 可融合任意类型的检索器
- ✅ 对分数不可靠的检索器也能工作

**原始论文**：
> Cormack & Clarke, "Reciprocal rank fusion: A baseline method for combining retrieval systems with no training," SIGIR 2007/2009.

### 2.3 Cross-Encoder (神经网络重排序)

**工作方式**：将 query 和 document 一起输入神经网络，输出相关性分数。

```python
from sentence_transformers import CrossEncoder

model = CrossEncoder('cross-encoder/ms-marco-MiniLM-L-6-v2')
scores = model.predict([
    ("How many people live in Berlin?", "Berlin had 3.5 million inhabitants"),
])
# 输出: [8.61]
```

### 2.4 效果对比

| 方法 | 精度 | 速度 | 资源 |
|------|------|------|------|
| BM25 | 中 | 快 | 低 |
| RRF | 中高 | 快 | 低 |
| Cross-Encoder | 最高 | 慢 | 高 |

**RRF vs Cross-Encoder 效果差距**：Cross-Encoder 普遍比 RRF 在 NDCG@10 上高 **5-15%**，但计算成本高 10-100 倍。

---

## 3. 文档去重

### 3.1 方法对比

| 方法 | 复杂度 | 适合场景 | 阈值建议 |
|------|--------|----------|----------|
| **精确哈希** | O(n) | 完全相同文档 | = 100% |
| **编辑距离** | O(n×m) | 小规模精确匹配 | ≥ 90% |
| **SimHash** | O(n) + LSH | 大规模近似匹配 | ≥ 0.8 |
| **MinHash+LSH** | O(n) | 大规模相似检测 | ≥ 0.5 |

### 3.2 SimHash 示例

```python
from simhash import Simhash

def simhash_similarity(doc1: str, doc2: str) -> float:
    h1 = Simhash(doc1)
    h2 = Simhash(doc2)
    distance = h1.distance(h2)
    return 1 - distance / 64
```

### 3.3 MinHash + LSH 示例

```python
from datasketch import MinHash, MinHashLSH

lsh = MinHashLSH(threshold=0.5, num_perm=128)
m = MinHash()
m.update("document content".encode())
lsh.insert("doc_id", m)
matches = lsh.query(m)
```

---

## 4. 文档 Chunk 切分

DB-GPT 支持 5 种切分策略：

| 策略 | 切分类 | 说明 |
|------|--------|------|
| `CHUNK_BY_SIZE` | RecursiveCharacterTextSplitter | 按大小递归切分（默认） |
| `CHUNK_BY_PAGE` | PageTextSplitter | 按页面切分 |
| `CHUNK_BY_PARAGRAPH` | ParagraphTextSplitter | 按段落切分 |
| `CHUNK_BY_SEPARATOR` | SeparatorTextSplitter | 按分隔符切分 |
| `CHUNK_BY_MARKDOWN_HEADER` | MarkdownHeaderTextSplitter | 按 Markdown 标题切分 |

### 配置示例

```python
from dbgpt_ext.rag import ChunkParameters

# 默认策略
params = ChunkParameters(
    chunk_size=512,
    chunk_overlap=50,
)

# Markdown 标题切分
params = ChunkParameters(
    chunk_strategy="CHUNK_BY_MARKDOWN_HEADER",
    chunk_size=1000,
    chunk_overlap=100,
)
```

---

## 5. 知识图谱提取

### 5.1 提取流程

```
文档 → 切分(Chunk) → LLM提取 → 图谱存储 → 图谱检索
```

### 5.2 LLM 提示词提取

DB-GPT 使用精心设计的提示词让 LLM 提取实体和关系：

**输出格式**：
```
Entities:
(实体名#实体总结)
...

Relationships:
(来源实体名#关系名#目标实体名#关系总结)
...
```

**示例**：
- 输入: "Philz Coffee was founded by Phil Jabber in 1978..."
- 输出:
  ```
  Entities:
  (Phil Jabber#Founder of Philz Coffee)
  (Philz Coffee#Coffee brand founded in Berkeley)

  Relationships:
  (Phil Jabber#Founded#Philz Coffee#Founded in 1978)
  ```

### 5.3 支持的图数据库

| 数据库 | 说明 |
|--------|------|
| TuGraph | 蚂蚁图数据库 |
| Neo4j | 主流图数据库 |
| MemGraph | 内存图数据库 |

---

## 6. 模糊搜索

### 6.1 与 BM25 的区别

| 特性 | BM25 | 模糊搜索 |
|------|------|----------|
| 匹配方式 | 精确词项 | 近似匹配 |
| 容错能力 | 无 | 有 |
| 原理 | 倒排索引 + TF-IDF | 编辑距离 / n-gram |

### 6.2 Java 实现

```java
// Lucene FuzzyQuery
FuzzyQuery fuzzyQuery = new FuzzyQuery(new Term("content", "machne"), 2);

// Elasticsearch
Query fuzzyQuery = Query.of(q -> q
    .fuzzy(f -> f
        .field("content")
        .value("machne")
        .fuzziness("AUTO")
    )
);

// 编辑距离
public static int levenshteinDistance(String s1, String s2) {
    // O(n×m) 复杂度
}
```

---

## 7. 模型微调 (DB-GPT-Hub)

### 7.1 支持的微调类型

| 类型 | 参数值 | 说明 |
|------|--------|------|
| LoRA | `lora` | 低秩适配，最常用 |
| QLoRA | `lora` + `quantization_bit=4/8` | 量化 LoRA |
| Prefix Tuning | `ptuning` | 前缀微调 |
| Freeze | `freeze` | 冻结部分层 |

### 7.2 训练脚本

```bash
python dbgpt_hub/train/sft_train.py \
    --model_name_or_path codellama/CodeLlama-13b-Instruct-hf \
    --finetuning_type lora \
    --lora_rank 64 \
    --lora_alpha 32 \
    --learning_rate 2e-4 \
    --num_train_epochs 8
```

### 7.3 效果

在 Spider 数据集上，CodeLlama-13B + LoRA 可达到约 **78.9%** 的执行准确率。

---

## 8. LoRA 原理

### 8.1 什么是低秩 (Low Rank)

**秩 (Rank)** 是矩阵的固有属性，表示矩阵中**线性无关的行/列数量**。

```python
# 例子
A = [[1, 2],
     [2, 4]]  # 第二行是第一行的 2 倍，线性相关

rank(A) = 1  # 只有 1 个线性无关的行
```

**低秩 vs 低维度**：

| 概念 | 含义 | 区别 |
|------|------|------|
| **低秩** | 矩阵的秩小于矩阵的行列数 | 描述**矩阵结构** |
| **低维** | 向量/数据分布在低维空间 | 描述**数据分布** |

```python
# 低秩矩阵
W = [[1, 2, 3],      # 第 3 行 = 第 1 行 + 第 2 行
     [2, 4, 6],
     [1, 2, 3]]       # rank = 1 (远小于 3×3)

# 低维数据 (3D 点分布在 2D 平面上)
points = [(1,2,3), (2,4,6), (3,6,9)]  # 实际只需要 1 个参数描述
```

### 8.2 LoRA 为什么有效

LoRA 假设预训练模型的权重变化是低秩的：

```
输出 = W × input + ΔW × input
     = W × input + B × A × input

其中 ΔW = BA，r 远小于 d,k
```

例如：d=4096, k=4096, r=8
- 全参数：16,777,216 参数
- LoRA: 65,536 参数 (减少 256 倍)

**为什么低秩适配有效？**

| 观点 | 解释 |
|------|------|
| **内在维度** | 预训练模型的知识分布在低维子空间中，只需少量参数即可捕获 |
| **渐进式学习** | 微调时模型先学习粗粒度知识，再细化到低秩空间 |
| **参数效率** | 相比全参数微调，LoRA 只需 0.1%-5% 的参数量 |

### 8.3 为什么 LoRA 比前缀微调和全参数微调更流行？

#### 成本对比

| 方法 | GPU 显存 | 存储成本 | 训练成本 |
|------|----------|----------|----------|
| 全参数微调 (7B) | 28GB+ | 14GB/模型 | 高 |
| LoRA (7B) | 14GB+ | 16MB/适配器 | 低 |
| 前缀微调 | 14GB+ | 16MB/适配器 | 低 |

#### 工程优势

```
全参数微调:
- 每次微调需要替换整个模型文件 (14GB+)
- 无法同时部署多个任务版本
- A/B 测试成本高

LoRA:
- 基础模型不变 (14GB)
- 只替换 LoRA 权重 (16MB)
- 可以同时加载多个 LoRA (一个模型+N 个任务)
```

#### 与前缀微调的对比

| 特性 | LoRA | 前缀微调 |
|------|------|----------|
| 参数效率 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| 性能 | 略优 | 略差 |
| 部署灵活性 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ |
| 推理延迟 | 无额外开销 | 前缀增加长度 |
| 社区支持 | ✅ PEFT 主推 | 较少 |

#### 为什么"几个点"的提升仍然重要？

```
模型效果：85% → 88% (提升 3%)
看似不大

但:
- 边际成本 ≈ 0
- 积累多个"几个点" = 质变
- 竞争对手也在用
- 用户无感知但用脚投票
```

**总结**：LoRA 不是因为效果最好而流行，而是因为在"效果足够好"的前提下，成本最低、部署最灵活、迭代最快。

### 8.4 与蒸馏的关系

- **知识蒸馏**：压缩模型大小
- **LoRA**：高效微调
- **组合使用**：蒸馏得到小模型 → LoRA 微调适配任务

---

## 9. 参考资源

- DB-GPT 官方文档：https://dbgpt.cn
- DB-GPT-Hub：https://github.com/eosphoros-ai/DB-GPT-Hub
- RRF 原始论文：Cormack & Clarke, SIGIR 2009
- BEIR 基准测试：https://github.com/beir-cellar/beir
