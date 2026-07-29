export const meta = {
  name: "academic-assemble",
  description: "Assemble canonical academic OCR artifacts, chunk, embed, index, and receipt",
  pools: ["academic-ocr-cpu", "coordinator-gpu"],
  argsSchema: {
    type: "object",
    required: [
      "paper",
      "pages",
      "protocols",
      "driver",
      "outputDir",
      "receiptPath",
      "chunkWords",
      "embedding"
    ],
    properties: {
      paper: {
        type: "object",
        required: ["paperId", "title", "sourceUrl", "sourceSha256"],
        properties: {
          paperId: {
            type: "string",
            pattern: "^[A-Za-z0-9._-]+$",
            minLength: 1,
            maxLength: 80
          },
          title: { type: "string", minLength: 1, maxLength: 500 },
          sourceUrl: { type: "string", pattern: "^https://" },
          sourceSha256: { type: "string", pattern: "^[0-9a-f]{64}$" }
        },
        additionalProperties: false
      },
      pages: {
        type: "array",
        minItems: 1,
        maxItems: 100,
        items: {
          type: "object",
          required: [
            "paperId",
            "pageNumber",
            "status",
            "resolution",
            "inputVariant",
            "chosenArtifactPath",
            "textDigest",
            "disagreementPermille",
            "agreementProtocols",
            "attemptCount",
            "proof"
          ],
          properties: {
            paperId: { type: "string", minLength: 1 },
            pageNumber: { type: "integer", minimum: 1 },
            status: { enum: ["converged", "arbitrated"] },
            resolution: { enum: ["tier", "mutation", "arbiter"] },
            inputVariant: { type: "string", minLength: 1 },
            chosenArtifactPath: { type: "string", pattern: "^/" },
            textDigest: { type: "string", pattern: "^sha256:[0-9a-f]{64}$" },
            disagreementPermille: {
              anyOf: [
                { type: "integer", minimum: 0, maximum: 1000 },
                { type: "null" }
              ]
            },
            agreementProtocols: {
              type: "array",
              uniqueItems: true,
              items: { type: "string", minLength: 1 }
            },
            attemptCount: { type: "integer", minimum: 1 },
            proof: {
              type: "object",
              required: ["taskUuid", "witnessSeq"],
              properties: {
                taskUuid: { type: "string", minLength: 1 },
                witnessSeq: { type: "integer", minimum: 1 }
              },
              additionalProperties: false
            }
          },
          additionalProperties: false
        }
      },
      protocols: {
        type: "array",
        minItems: 2,
        maxItems: 4,
        items: {
          type: "object",
          required: ["id", "tier"],
          properties: {
            id: { type: "string", minLength: 1 },
            tier: { enum: ["cheap", "standard", "specialist"] }
          },
          additionalProperties: false
        }
      },
      driver: {
        type: "object",
        required: ["adapter", "program", "runtimeMaxSec"],
        properties: {
          adapter: { type: "string", minLength: 1 },
          program: { type: "string", pattern: "^/" },
          runtimeMaxSec: { type: "integer", minimum: 1 }
        },
        additionalProperties: false
      },
      outputDir: { type: "string", pattern: "^/" },
      receiptPath: { type: "string", pattern: "^/" },
      chunkWords: { type: "integer", minimum: 64, maximum: 2048 },
      embedding: {
        type: "object",
        required: ["endpoint", "model", "batchSize", "dimensions"],
        properties: {
          endpoint: { const: "http://localhost:9292" },
          model: { const: "qwen3-embedding-8b" },
          batchSize: { type: "integer", minimum: 1, maximum: 64 },
          dimensions: { const: 4096 }
        },
        additionalProperties: false
      }
    },
    additionalProperties: false
  },
  maxNodes: 6,
  selectors: []
};

const digestSchema = { type: "string", pattern: "^sha256:[0-9a-f]{64}$" };

const assembleSchema = {
  type: "object",
  required: [
    "paperId",
    "artifactPath",
    "artifactDigest",
    "paperPath",
    "paperDigest",
    "pageCount"
  ],
  properties: {
    paperId: { type: "string", minLength: 1 },
    artifactPath: { type: "string", pattern: "^/" },
    artifactDigest: digestSchema,
    paperPath: { type: "string", pattern: "^/" },
    paperDigest: digestSchema,
    pageCount: { type: "integer", minimum: 1 }
  },
  additionalProperties: false
};

const chunkSchema = {
  type: "object",
  required: ["paperId", "artifactPath", "artifactDigest", "chunkCount", "embeddingModel"],
  properties: {
    paperId: { type: "string", minLength: 1 },
    artifactPath: { type: "string", pattern: "^/" },
    artifactDigest: digestSchema,
    chunkCount: { type: "integer", minimum: 1 },
    embeddingModel: { const: "qwen3-embedding-8b" }
  },
  additionalProperties: false
};

const embeddingSchema = {
  type: "object",
  required: [
    "paperId",
    "artifactPath",
    "artifactDigest",
    "vectorCount",
    "dimensions",
    "model"
  ],
  properties: {
    paperId: { type: "string", minLength: 1 },
    artifactPath: { type: "string", pattern: "^/" },
    artifactDigest: digestSchema,
    vectorCount: { type: "integer", minimum: 1 },
    dimensions: { const: 4096 },
    model: { const: "qwen3-embedding-8b" }
  },
  additionalProperties: false
};

const indexSchema = {
  type: "object",
  required: ["paperId", "artifactPath", "artifactDigest", "chunkCount", "indexKind"],
  properties: {
    paperId: { type: "string", minLength: 1 },
    artifactPath: { type: "string", pattern: "^/" },
    artifactDigest: digestSchema,
    chunkCount: { type: "integer", minimum: 1 },
    indexKind: { const: "sqlite-vec+fts5" }
  },
  additionalProperties: false
};

const receiptSchema = {
  type: "object",
  required: ["status", "paperId", "artifactPath", "artifactDigest"],
  properties: {
    status: { enum: ["complete", "failed"] },
    paperId: { type: "string", minLength: 1 },
    artifactPath: { type: "string", pattern: "^/" },
    artifactDigest: digestSchema
  },
  additionalProperties: false
};

function node(action, brief, artifactPath, pools, key, resultSchema) {
  return job({
    argv: [args.driver.program, action],
    adapter: args.driver.adapter,
    pools,
    priority: "low",
    runtimeMaxSec: args.driver.runtimeMaxSec,
    evidence: ["exit:0", `artifact:${artifactPath}`, "hash:sha256"],
    brief: { action, ...brief, artifactPath },
    key,
    label: `academic-${action}-${args.paper.paperId}`,
    resultSchema
  });
}

function witnessed(result) {
  return {
    result: result.result,
    proof: { taskUuid: result.taskUuid, witnessSeq: result.witnessSeq }
  };
}

(async () => {
  let stage = "assemble";
  try {
    const canonicalManifest = `${args.outputDir}/canonical/manifest.json`;
    const assembled = await node(
      "assemble",
      {
        paper: args.paper,
        pages: args.pages,
        outputDir: args.outputDir
      },
      canonicalManifest,
      ["academic-ocr-cpu"],
      "assemble",
      assembleSchema
    );

    stage = "chunk";
    const chunksPath = `${args.outputDir}/chunks.json`;
    const chunked = await node(
      "chunk",
      {
        paperId: args.paper.paperId,
        paperPath: assembled.result.paperPath,
        chunkWords: args.chunkWords,
        embeddingModel: args.embedding.model
      },
      chunksPath,
      ["academic-ocr-cpu"],
      "chunk",
      chunkSchema
    );

    stage = "embed";
    const embeddingsPath = `${args.outputDir}/embeddings.json`;
    const embedded = await node(
      "embed",
      {
        paperId: args.paper.paperId,
        chunksPath: chunked.result.artifactPath,
        embedding: args.embedding
      },
      embeddingsPath,
      ["coordinator-gpu"],
      "embed",
      embeddingSchema
    );

    stage = "index";
    const indexPath = `${args.outputDir}/index/papers.db`;
    const indexed = await node(
      "index",
      {
        paperId: args.paper.paperId,
        chunksPath: chunked.result.artifactPath,
        embeddingsPath: embedded.result.artifactPath
      },
      indexPath,
      ["academic-ocr-cpu"],
      "index",
      indexSchema
    );

    stage = "receipt";
    const receipt = await node(
      "receipt",
      {
        paper: args.paper,
        pages: args.pages,
        protocols: args.protocols,
        outputDir: args.outputDir,
        stages: {
          assemble: witnessed(assembled),
          chunk: witnessed(chunked),
          embed: witnessed(embedded),
          index: witnessed(indexed)
        }
      },
      args.receiptPath,
      ["academic-ocr-cpu"],
      "receipt",
      receiptSchema
    );

    return {
      schemaVersion: 1,
      status: "complete",
      paperId: args.paper.paperId,
      receiptPath: receipt.result.artifactPath,
      receiptDigest: receipt.result.artifactDigest,
      stages: {
        assemble: witnessed(assembled),
        chunk: witnessed(chunked),
        embed: witnessed(embedded),
        index: witnessed(indexed),
        receipt: witnessed(receipt)
      }
    };
  } catch (error) {
    await node(
      "failure",
      {
        paper: args.paper,
        error: {
          stage,
          name: error && error.name ? String(error.name) : "Error",
          code: error && error.code ? String(error.code) : null,
          message: error && error.message ? String(error.message) : String(error)
        }
      },
      args.receiptPath,
      ["academic-ocr-cpu"],
      "failure",
      receiptSchema
    );
    throw error;
  }
})();
