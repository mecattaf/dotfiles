import { readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

type JsonObject = Record<string, unknown>;

interface HfFile {
  path: string;
  bytes: number | null;
  sha256: string | null;
  nix_sri: string | null;
}

interface HfInspection {
  id: string;
  repository: string;
  hf_url: string;
  requested_revision: string;
  revision: string;
  files: HfFile[];
  card_data: JsonObject;
  api_url: string;
}

function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function normalizeRepository(value: string): string {
  let candidate = value.trim();
  if (candidate.startsWith("https://huggingface.co/")) {
    candidate = candidate.slice("https://huggingface.co/".length);
  }
  candidate = candidate.replace(/^\/+|\/+$/g, "");
  const parts = candidate.split("/");
  if (
    parts.length !== 2 ||
    parts.some((part) => !/^[A-Za-z0-9._-]+$/.test(part))
  ) {
    throw new Error("repository must be an owner/name on huggingface.co");
  }
  return parts.join("/");
}

function sha256ToSri(sha256: string | null): string | null {
  if (!sha256 || !/^[0-9a-f]{64}$/.test(sha256)) return null;
  return `sha256-${Buffer.from(sha256, "hex").toString("base64")}`;
}

function selectedCardData(raw: unknown): JsonObject {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const source = raw as JsonObject;
  const keep = [
    "license",
    "library_name",
    "pipeline_tag",
    "base_model",
    "datasets",
    "language",
    "tags",
  ];
  return Object.fromEntries(
    keep.filter((key) => key in source).map((key) => [key, source[key]]),
  );
}

export default async function localAiMonthlyExtension(pi: ExtensionAPI) {
  const bundlePath = requiredEnv("LOCAL_AI_MONTHLY_BUNDLE");
  const outputPath = requiredEnv("LOCAL_AI_MONTHLY_OUTPUT");
  const bundle = JSON.parse(await readFile(bundlePath, "utf8")) as JsonObject;
  const allowedRows = bundle.allowed_hf_repositories;
  const allowed = new Set(
    Array.isArray(allowedRows)
      ? allowedRows
          .filter((row): row is string => typeof row === "string")
          .map(normalizeRepository)
      : [],
  );
  const quotas = bundle.tool_quotas as JsonObject | undefined;
  const rawQuota = quotas?.hf_inspections;
  const inspectionQuota =
    typeof rawQuota === "number" && Number.isInteger(rawQuota) ? rawQuota : 0;
  const inspections: HfInspection[] = [];
  let contextInjected = false;
  let submitted = false;

  pi.on("before_agent_start", async () => {
    if (contextInjected) return;
    contextInjected = true;
    return {
      message: {
        customType: "local-ai-monthly-evidence",
        content: JSON.stringify(bundle),
        display: false,
      },
    };
  });

  pi.registerTool({
    name: "local_ai_inspect_hf",
    label: "Inspect HF metadata",
    description:
      "Resolve immutable Hugging Face metadata for an evidence-named repository and exact proposed files. Never downloads model blobs.",
    promptSnippet:
      "Resolve exact HF revisions, file sizes, LFS SHA-256 values, and Nix SRI hashes",
    promptGuidelines: [
      "Call local_ai_inspect_hf only for a serious roster proposal whose Hugging Face repository appears in the supplied evidence.",
      "Request only exact artifact or auxiliary filenames named by the evidence.",
    ],
    parameters: Type.Object({
      repository: Type.String({
        description: "Allowed owner/name or https://huggingface.co/owner/name",
      }),
      revision: Type.Optional(
        Type.String({
          description:
            "Revision named in evidence; omit to resolve the repository default branch",
        }),
      ),
      files: Type.Array(Type.String(), {
        minItems: 1,
        maxItems: 32,
        description: "Exact repository-relative artifact filenames to resolve",
      }),
    }),
    executionMode: "sequential",
    async execute(_toolCallId, params, signal) {
      if (!contextInjected)
        throw new Error("the prepared evidence context was not injected");
      if (inspections.length >= inspectionQuota) {
        throw new Error(`HF inspection quota exhausted (${inspectionQuota})`);
      }
      const repository = normalizeRepository(params.repository);
      if (!allowed.has(repository)) {
        throw new Error(`${repository} was not named in the supplied evidence`);
      }
      const requestedRevision = params.revision ?? "main";
      if (
        !/^[A-Za-z0-9._/-]+$/.test(requestedRevision) ||
        requestedRevision.includes("..")
      ) {
        throw new Error("invalid Hugging Face revision");
      }
      const [owner, name] = repository.split("/");
      const apiUrl = `https://huggingface.co/api/models/${encodeURIComponent(owner)}/${encodeURIComponent(name)}/revision/${encodeURIComponent(requestedRevision)}?blobs=true`;
      const response = await fetch(apiUrl, {
        headers: {
          Accept: "application/json",
          "User-Agent": "mecattaf-local-ai-monthly/1",
        },
        signal,
      });
      if (!response.ok)
        throw new Error(
          `Hugging Face metadata request failed: HTTP ${response.status}`,
        );
      const metadata = (await response.json()) as JsonObject;
      const revision = metadata.sha;
      if (typeof revision !== "string" || !/^[0-9a-f]{40}$/.test(revision)) {
        throw new Error(
          "Hugging Face response lacks an immutable 40-character SHA",
        );
      }
      const siblings = Array.isArray(metadata.siblings)
        ? (metadata.siblings as JsonObject[])
        : [];
      const requestedFiles = [...new Set(params.files)];
      const files: HfFile[] = requestedFiles.map((path) => {
        const sibling = siblings.find((row) => row.rfilename === path);
        if (!sibling)
          throw new Error(`file does not exist at ${revision}: ${path}`);
        const lfs =
          sibling.lfs && typeof sibling.lfs === "object"
            ? (sibling.lfs as JsonObject)
            : {};
        const rawOid =
          typeof lfs.oid === "string" ? lfs.oid.replace(/^sha256:/, "") : null;
        const sha256 = rawOid && /^[0-9a-f]{64}$/.test(rawOid) ? rawOid : null;
        const rawBytes = typeof lfs.size === "number" ? lfs.size : sibling.size;
        const bytes =
          typeof rawBytes === "number" && Number.isSafeInteger(rawBytes)
            ? rawBytes
            : null;
        return { path, bytes, sha256, nix_sri: sha256ToSri(sha256) };
      });
      const inspection: HfInspection = {
        id: `HF${String(inspections.length + 1).padStart(3, "0")}`,
        repository,
        hf_url: `https://huggingface.co/${repository}`,
        requested_revision: requestedRevision,
        revision,
        files,
        card_data: selectedCardData(metadata.cardData),
        api_url: apiUrl,
      };
      inspections.push(inspection);
      return {
        content: [{ type: "text", text: JSON.stringify(inspection) }],
        details: { inspection_id: inspection.id, repository, revision },
      };
    },
  });

  pi.registerTool({
    name: "local_ai_submit_review",
    label: "Submit monthly review",
    description:
      "Submit the complete evidence-bound review and terminate this atomic task.",
    promptSnippet: "Submit the complete local-AI review as the final action",
    parameters: Type.Object({
      brief: Type.Any({
        description:
          "Complete review object matching the loaded skill contract",
      }),
    }),
    executionMode: "sequential",
    async execute(_toolCallId, params) {
      if (!contextInjected)
        throw new Error("the prepared evidence context was not injected");
      if (submitted)
        throw new Error("local_ai_submit_review may be called only once");
      if (
        !params.brief ||
        typeof params.brief !== "object" ||
        Array.isArray(params.brief)
      ) {
        throw new Error("brief must be an object");
      }
      const brief = params.brief as JsonObject;
      if (brief.task_id !== bundle.task_id)
        throw new Error("brief task_id does not match the bundle");
      submitted = true;
      const temporary = `${outputPath}.tmp-${process.pid}`;
      await writeFile(
        temporary,
        `${JSON.stringify({ brief, hf_inspections: inspections }, null, 2)}\n`,
        {
          encoding: "utf8",
          mode: 0o600,
        },
      );
      await rename(temporary, outputPath);
      return {
        content: [{ type: "text", text: "Review recorded." }],
        details: {
          task_id: bundle.task_id,
          hf_inspection_count: inspections.length,
          output_dir: dirname(outputPath),
        },
        terminate: true,
      };
    },
  });
}
