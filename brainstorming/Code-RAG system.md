This document provides the definitive architectural design for a multi-tenant, context-aware Knowledge and Code-RAG (Retrieval-Augmented Generation) infrastructure designed for your Homelab.

It synthesizes every concept discussed throughout our session—including discarded variants, architecture alternatives, data flows, exact multi-token isolation strategies, and IDE integration configurations—providing a detailed blueprint ready for immediate implementation.

## ---

**1\. COMPREHENSIVE COMPONENT MAP & HISTORICAL ANALYSIS**

The system design focuses on handling multiple projects with mixed extensions (.cs, .yml, .j2, .md, .pdf) across different user personas.

       `[ DEVELOPER FLOW ]                                         [ RESEARCHER FLOW ]`  
  `Visual Studio / VS Code / Git Push                        PDF Upload / Chat Interface via HTTPS`  
                 `│                                                          │`  
                 `▼                                                          ▼`  
         `┌───────────────┐                                          ┌───────────────┐`  
         `│  Forgejo Git  │                                          │  Open WebUI   │`  
         `└───────┬───────┘                                          └───────┬───────┘`  
                 `│ (Webhook)                                                │ (Direct / API)`  
                 `▼                                                          ▼`  
        `┌───────────────────────────────────────────────────────────────────────────┐`  
        `│                        n8n AUTOMATION ROUTER                              │`  
        `└───────┬───────────────────────────┬───────────────────────────────┬───────┘`  
                `│                           │                               │`  
  `(Match: .cs)  ▼             (Match: .yml / .j2) ▼           (Match: .md / .pdf) ▼`  
   `┌─────────────────────────┐ ┌─────────────────────────┐     ┌─────────────────────────┐`  
   `│      rager-roslyn       │ │      rager-ansible      │     │      rager-docling      │`  
   `│ (AST Method Extraction) │ │ (Tree-Sitter / Capture) │     │ (Layout-Aware Chunking) │`  
   `└────────────┬────────────┘ └────────────┬────────────┘     └────────────┬────────────┘`  
                `│                           │                               │`  
                `└───────────────────────────┼───────────────────────────────┘`  
                                            `▼ (Normalized JSON Object with Calculated Deduplication Determinant)`  
                               `┌─────────────────────────┐`  
                               `│       FastGPT API       │`  
                               `└────────────┬────────────┘`  
                                            `│ (Vectorization & Storage Request)`  
                                            `▼`  
                     `┌───────────────────────────────────────────────┐`  
                     `│            CENTRAL DATA LAYER                 │`  
                     `│  ┌───────────────────┐ ┌───────────────────┐  │`  
                     `│  │      Ollama       │ │    Qdrant DB      │  │`  
                     `│  │ (nomic-embed-text)│ │ (Multi-Tenant)    │  │`  
                     `│  └───────────────────┘ └───────────────────┘  │`  
                     `└──────────────────────┬────────────────────────┘`  
                                            `│`  
               `┌────────────────────────────┴────────────────────────────┐`  
               `▼                                                         ▼`  
       `[ CONSUMER LAYER ]                                        [ AGENT LAYER ]`  
   `Open WebUI Models (Scoped)                               OpenHands Autonomous Execution`  
   ``- `Homelab Koda Asistent`                                - Code Repair & Generation``  
   ``- `Znanstveni Pomočnik`                                  - Pull Request Submission``  
   `IDE Plugins (Continue.dev)`

## **The Discarded Alternatives: Why They Fell Short**

> * **Standalone Claw AI (Claude Code/Cowork):** Discarded due to systemic architectural isolation. It operates as an ephemeral terminal session with native localized runtime restrictions. It cannot monitor background workflows, lacks native multi-tenancy, and cannot consume external unstructured datasets like scientific PDFs.  
> * **Pure OpenClaw Execution Engine:** Discarded as the core developer tool. While highly capable for ambient mobile monitoring (via chat clients), it lacks structural awareness for parsing codebases spread across deeply nested directories. It acts as an ambient general assistant rather than an advanced software engineer agent.  
> * **Direct Open WebUI Internal Document Storage:** Discarded as the system-wide source of truth. Its native ingestion pipelines are structurally monolithic and isolated. Exposing its vector embeddings to external tools like OpenHands or IDE extensions is difficult, creating fractured knowledge bases.  
> * **Generic Dify Ingestion Engine:** Discarded because its ingestion engines utilize basic linear character-count segmentations. For complex program code, it breaks multi-line structures indiscriminately, isolating class fields from method logic and introducing noise into the embeddings.  
> * **Pure LlamaIndex Local Service Stack:** Discarded for the primary ingestion layer. Writing custom orchestration servers using FastAPI to handle manual database collection management, state updates, and indexing introduces unnecessary code complexity when stable platforms exist.

## ---

**2\. ADVANCED DATA INGESTION PIPELINE & INGESTION MECHANICS**

The ingress engine runs on an asynchronous event-driven model orchestrated by n8n.

## **The Webhook Routing Topography**

When an explicit git push event occurs on Forgejo, or an alternative automated upload route initiates, a Webhook payload delivers file structural information to n8n. The router isolates each filename array item and runs a Conditional Switch Engine matching the specific file extensions:

## **The C\# Ingestion Strategy (AST Decomposition)**

Files terminating in .cs are dispatched via HTTP POST to the local isolated runtime container rager-roslyn. This service uses C\# code analysis libraries (Microsoft.CodeAnalysis.CSharp) to run a custom syntax parsing agent.

> * **Granular Boundary Selection:** The file is broken down exactly into method units (MethodDeclarationSyntax) and class containers (ClassDeclarationSyntax).  
> * **Calculated Context Retention:** If an isolated method is pulled, its parent structure data is retained. The namespace declarations, field initializations, and class inheritance attributes are extracted and pre-pended or nested as clean string headers.

## **The Ansible & Jinja Ingestion Strategy (Tree-Sitter Structuring)**

Files terminating in .yml, .yaml, or .j2 are processed inside rager-ansible, a lightweight Python deployment executing an explicit **Tree-Sitter syntax mapping model**.

> * **YAML Split Boundaries:** The division logic is bound to structural array targets: \["\\n- name:", "\\n---", "\\n\\n"\]. This guarantees that an Ansible task container remains intact, preserving structural module values alongside its operational metadata block.  
> * **Jinja Template Handling:** For .j2 configuration engines, if the document size remains below a threshold of 4000 tokens, chunking is skipped entirely. The template is ingested as an atomic entity to maintain loop structures ({% for %} to {% endfor %}) and variable contexts ({{ value }}).

## **Unstructured Document Handling (Layout-Aware Chunking via Docling)**

For .pdf files, scientific studies, and fallback documentation files, the workflow channels data through a rager-docling node. Docling identifies document structures (H1, H2, complex tables, cross-page text flows) rather than performing linear string parsing. This formatting is transformed into a highly organized Markdown sequence.

## **Normalization of JSON & Structural Context Ingress**

Every isolated data chunk exiting the extraction phase is formatted into a standardized JSON package prior to sending it to FastGPT:

`{`  
  `"dataId": "cf14a1b0-13a8-5e4d-910a-cb8a3f87deaa",`  
  `"datasetId": "homelab-core-knowledge",`  
  `"collectionName": "source_code_base",`  
  `"chunks": [`  
    `{`  
      `"q": "Method: StartForgejoContainer | Class: ContainerManager",`  
      `"a": "public async Task StartForgejoContainer(string networkId)\n{\n    var config = new ContainerConfig();\n    await _docker.Containers.CreateAsync(config);\n}",`  
      `"metadata": {`  
        `"project_id": "homelab-iac-main",`  
        `"file_path": "services/infrastructure/ContainerManager.cs",`  
        `"file_type": "csharp_source",`  
        `"commit_sha": "a4fbc87192bc9321ef9a",`  
        `"structural_parent": "ContainerManager",`  
        `"ingest_timestamp": "2026-09-13T19:41:00Z"`  
      `}`  
    `}`  
  `]`  
`}`

## ---

**3\. MULTI-TENANT STORAGE, EMBEDDINGS & COMPACTION ARCHITECTURE**

The vector layer establishes strong multi-tenant database separation while maintaining a unified hardware resource architecture.

## **Unified Vector Space Properties**

> * **Embedding Pipeline Configuration:** Supported by a central Ollama or HuggingFace-TEI execution hub deploying the **nomic-embed-text** mathematical vector calculation engine (generating exactly 768 vector dimensions).  
> * **Reranking Configuration:** Powered by **bge-reranker-large**, acting as a deterministic post-retrieval verification filter. It analyses candidate chunks and drops those falling below a strictly defined relevance boundary before the context window payload transfers to the LLM.

## **Complete Partitioning and Deduplication Mechanics via FastGPT**

The application layers do not write directly to Qdrant. They interact exclusively with the **FastGPT Data Management API**, which coordinates storage operations and payload formatting.

## **Execution of Clean State Updates (The Upsert Process)**

To prevent the system from returning conflicting historic fragments (e.g., matching a stale network configuration schema against a modified Ansible task), deterministic ID allocation is used:

$$\\text{Chunk ID} \= \\text{UUIDv5}(\\text{Namespace\\\_DNS}, \\text{project\\\_id} \+ \\text{file\\\_path} \+ \\text{chunk\\\_index})$$

When an asset is modified and pushed to Git:

> 1. n8n recalculates the array of consistent UUIDv5 keys matching the newly chunked fragments.  
> 2. The payload hits the FastGPT push gateway (/api/core/dataset/data/pushData).  
> 3. FastGPT runs a targeted update against Qdrant. Points matching active structural IDs are updated inline, replacing the previous vectors and payload blocks.  
> 4. For files where the new chunk sequence has fewer segments than before, n8n invokes a targeted payload cleanup step to remove trailing stale indices (file\_path reference query via Qdrant's filter API).

## **Tenant Isolation Topology**

Data partitioning is enforced by maintaining separate collections inside FastGPT, which isolates security contexts using distinct API key headers.

                  `┌───────────────────────────────┐`  
                  `│      FastGPT Gateway API      │`  
                  `└───────┬───────────────┬───────┘`  
                          `│               │`  
      `[Auth Token A]      ▼               ▼      [Auth Token B]`  
                 `┌────────────────┬───────────────┐`  
                 `│  Collection A  │  Collection B │`  
                 `│ (Developer IaC)│ (Researcher)  │`  
                 `└────────┬───────┴───────┬───────┘`  
                          `│               │`  
  `Qdrant Payloads:        ▼               ▼`  
                 `{project_id: "X"} {user_scope: "researcher"}`

## ---

**4\. SECURE USER SEGREGATION & APP INTEGRATION INTERFACES**

The API delivery configuration separates administrative engineering tasks from research operations while serving both through a single Open WebUI installation.

## **Open WebUI User Scopes and Model Permissions**

The endpoint mappings expose FastGPT application connections via standard OpenAI-compatible abstraction layers.

> 1. **System-Wide Model Registrations:** Under Admin Settings \-\> Connections, two distinct bearer tokens are registered:  
   * Endpoint URL A $\\rightarrow$ FastGPT App Core-Developer-Agent  
   * Endpoint URL B $\\rightarrow$ FastGPT App Academic-Research-Engine  
> 2. **Role-Based Access Control (RBAC):**  
   * **Developer Profile:** Access keys are explicitly configured to reveal Core-Developer-Agent. This system passes targeted payload filters (project\_id) behind the scenes, searching exclusively through selected configuration playbooks and C\# code bases.  
   * **Researcher Profile:** Restricted solely to the Academic-Research-Engine endpoint. This workspace interacts only with vectorized PDF assets, isolating raw database scripts and systems engineering data from research tasks.

## **External Integration Setups (OpenHands, VS Code, and Visual Studio)**

`┌───────────────────────────────────────────────────────────────────────────┐`  
`│                           DEVELOPER SYSTEM INFRA                          │`  
`│                                                                           │`  
`│  ┌──────────────────────┐   ┌──────────────────────┐   ┌───────────────┐  │`  
`│  │     OpenHands        │   │    VS Code / VS      │   │ Signal Client │  │`  
`│  │ (Autonomous Agent)   │   │ (Continue.dev Plugin)│   │ (Mobile Cmd)  │  │`  
`│  └──────────┬───────────┘   └──────────┬───────────┘   └───────┬───────┘  │`  
`└─────────────┼──────────────────────────┼───────────────────────┼──────────┘`  
              `│                          │                       │`  
              `▼                          ▼                       ▼`  
      `[ Forgejo Repo ]            [ FastGPT API ]        [ n8n Hook Event ]`  
      `(Direct Access)         (OpenAI-Compatible Spec)   (Trigger Run Command)`

## **OpenHands Setup**

OpenHands bypasses the general search endpoint for writing new code, running its own processing steps on cloning target repositories directly from Forgejo. However, for context validation (e.g., cross-referencing system constraints defined in .md files), OpenHands can be configured to use FastGPT as an external LLM provider by targeting the Core-Developer-Agent API endpoint.

## **Continue.dev Integration (VS Code & Visual Studio Community)**

To embed this centralized knowledge directly into your active development workflow, modify your local user configuration file (\~/.continue/config.json) to register the internal FastGPT endpoints:

`{`  
  `"models": [`  
    `{`  
      `"title": "Homelab Central Intelligence",`  
      `"provider": "openai",`  
      `"model": "Core-Developer-Agent",`  
      `"apiBase": "http://192.168.1",`  
      `"apiKey": "fastgpt-dev-token-string-here"`  
    `}`  
  `],`  
  `"contextProviders": [`  
    `{`  
      `"name": "http",`  
      `"options": {`  
        `"url": "http://192.168.1",`  
        `"method": "POST",`  
        `"headers": {`  
          `"Authorization": "Bearer fastgpt-dev-token-string-here"`  
        `}`  
      `}`  
    `}`  
  `]`  
`}`

## ---

**5\. RE-EVALUATION OF SYSTEM COMPONENT ROLES**

To ensure system stability, it is helpful to contrast this production architecture with the capabilities of the alternative configurations evaluated during design:

## **OpenClaw Deployment Assessment**

> * **Production Functionality:** Restricted to non-blocking system monitoring and remote event triggers via Signal. It interfaces with n8n using simple webhook calls, running tasks like checking repository sync flags or confirming backup statuses.  
> * **System Constraints:** It does not manage active file chunking, structural code evaluations, or direct vector generation workflows. These tasks remain under the control of the specialized ingestion services (rager-roslyn and rager-ansible).

## **n8n vs. Dedicated Search Orchestrators**

> * **Production Functionality:** n8n operates exclusively as an **ETL Pipeline Director and Event Router**. It processes file structures, manages system API endpoints, and coordinates data formatting.  
> * **System Constraints:** n8n does not directly manage vector distances or index generation inside Qdrant. FastGPT handles these database tasks, ensuring reliable query execution and maintaining data isolation across all system services.

## ---

**6\. PRODUCTION CONTEXT AND STEP-BY-STEP DEPLOYMENT MANIFEST**

## **Step 1: Deploy Core Services Stack**

Apply the base infrastructure configuration to launch Qdrant, the centralized Embedding Engine (TEI), and the FastGPT Management abstraction engine.

`version: '3.8'`

`services:`  
  `qdrant:`  
    `image: qdrant/qdrant:v1.11.0`  
    `container_name: iac-qdrant-db`  
    `restart: unless-stopped`  
    `ports:`  
      `- "6333:6333"`  
    `volumes:`  
      `- /mnt/storage/data/qdrant:/qdrant/storage`  
    `networks:`  
      `- rag-isolated-net`

  `tei-embedding-engine:`  
    `image: ghcr.io/huggingface/text-embeddings-inference:cpu-1.5`  
    `container_name: iac-tei-embedding`  
    `restart: unless-stopped`  
    `command: --model-id nomic-ai/nomic-embed-text-v1.5 --port 8080`  
    `ports:`  
      `- "8081:8080"`  
    `networks:`  
      `- rag-isolated-net`

  `fastgpt:`  
    `image: canthia/fastgpt:v4.8.1`  
    `container_name: iac-fastgpt-core`  
    `restart: unless-stopped`  
    `ports:`  
      `- "3000:3000"`  
    `environment:`  
      `- MongoUrl=mongodb://mongo-user:pass@192.168.1.51:27017/fastgpt`  
      `- QdrantUrl=http://qdrant:6333`  
    `volumes:`  
      `- /mnt/storage/data/fastgpt:/app/data`  
    `depends_on:`  
      `- qdrant`  
    `networks:`  
      `- rag-isolated-net`

`networks:`  
  `rag-isolated-net:`  
    `driver: bridge`

## **Step 2: Establish Source-Level Protections in Forgejo**

To secure code history and prevent unauthorized deletions across all connected development projects:

> 1. Navigate to target repositories within the Forgejo web panel.  
> 2. Enter **Settings** $\\rightarrow$ **Branches**.  
> 3. Create a rule protecting the default path pattern: main or master.  
> 4. Check **Disable Force Push** to block state corruption from automated systems or incorrect CLI entries.  
> 5. Grant API Token permissions using a restricted operational profile (repository: write, admin: deny).

## **Step 3: Configure the n8n Routing Node Logic**

Import a routing model using an internal JavaScript Switch Expression to handle inbound file array lists from your Git webhooks:

*`// n8n Code Node Switch logic definition`*  
`const filename = $input.item.json.commit_file_path;`  
`const extension = filename.split('.').pop().toLowerCase();`

`if (extension === 'cs') {`  
    `return { branch: "csharp-processing", processor_url: "http://rager-roslyn:5000/parse" };`  
`} else if (extension === 'yml' || extension === 'yaml' || extension === 'j2') {`  
    `return { branch: "ansible-processing", processor_url: "http://rager-ansible:5001/chunk" };`  
`} else if (extension === 'pdf' || extension === 'md') {`  
    `return { branch: "docling-processing", processor_url: "http://rager-docling:5002/extract" };`  
`} else {`  
    `return { branch: "unsupported-skip", processor_url: null };`  
`}`

## **Step 4: Map Multi-Tenant Scopes in Open WebUI**

> 1. Access the Open WebUI Control Panel using an administrator account.  
> 2. Navigate to **Admin Panel** $\\rightarrow$ **Connections** and provide your authentication keys.  
> 3. Map the OpenAI API connection string directly to the FastGPT interface (http://192.168.1).  
> 4. Enter **Users** or **Groups**, locate the target Developer Profile, and verify visibility permissions for the Core-Developer-Agent model context.  
> 5. Select the Researcher Profile and configure access permissions to link it exclusively with the Academic-Research-Engine database collection.

## ---

**Verification and Next Steps**

This production architecture is now fully specified. To begin implementation, ensure your system is ready by verifying the following environments:

> * Confirm the host system has sufficient compute resources to support **CPU-bound vector operations** via HuggingFace-TEI.  
> * Verify the **network paths** between your Docker instance, Forgejo, and the n8n webhook listener port.  
> * Check that your .md and .yml files follow structured patterns, such as using consistent header prefixes (\#, \#\#) or standard metadata keys.

Let me know which component you would like to deploy first. I can provide the **complete Python script for the Tree-Sitter Ansible chunking service** or help you build the **Roslyn AST extraction service** container.