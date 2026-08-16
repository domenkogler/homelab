Here is the complete and precise technical description of the system architecture and the selected tools translated into English.

## ---

**🌐 1\. System Architecture Description**

The system operates on a **hybrid mirrored architecture** principles. Instead of two completely separate systems, the server (VPS) and the client (Windows 11 PC) are connected into a unified data and logical ecosystem.

> * **Network Layer (Security Isolation):** A fully encrypted, hardware-accelerated, and private Mesh VPN network runs on top of the public internet. All communication between the databases and the local interfaces takes place inside this tunnel. Database ports are completely closed to the outside world.  
> * **Data Layer (Single Source of Truth):** All data regarding users, chat history, sessions, and vector indexes (RAG) is stored centrally. The local and remote interfaces read from the same source, enabling a seamless real-time transition between devices.  
> * **Logical Layer (Distributed Execution):** Heavy cognitive tasks (RAG search, synthesis of multi-hundred-page reports, and calls to external LLM models) are executed via the VPS server. Visual design and direct application management, however, are securely executed locally on the client's device.

## ---

**🖥️ 2\. Tools on the VPS (Server Side)**

The VPS serves as the central "heart" of the system, where your documents are stored and where the main processing power is executed.

> * **Headscale:** An open-source, self-hosted alternative to the Tailscale control server. It acts as the coordinator of your private WireGuard VPN network, handling secure IP address assignment (from the 100.64.0.0/10 range) and device authentication.  
> * **PostgreSQL & pgvector:** The central relational database upgraded with the pgvector extension. It stores Open WebUI system settings, chat history, and the entire RAG database (storing vector embeddings from your multi-page reports). It is configured to accept calls exclusively from Headscale network IPs.  
> * **LiteLLM:** An advanced, lightweight proxy server that unifies and manages API calls. It connects to your **OpenRouter** subscription in the background. It provides a standardized OpenAI-compatible API endpoint to both the local and server-side Open WebUI, managing security, budget consumption, and virtual keys.  
> * **Open WebUI (Server Instance):** The web chat interface running in Docker on the VPS. It allows users to access the system from anywhere (e.g., via the web or a mobile device). It is connected to the local PostgreSQL and LiteLLM.

## ---

**💻 3\. Tools on the End-User Device (Windows 11\)**

The local device is dedicated to visual interaction with the user and directly manipulating active applications within the operating system.

> * **Tailscale Client:** A classic, lightweight Windows application running in the system tray. It is configured to connect to your private **Headscale** server instead of the public Tailscale cloud, creating a secure cryptographic tunnel to your VPS.  
> * **Open WebUI (Local Instance):** Installed locally on Windows 11 (via Docker Desktop or Python). In its .env configuration, it points to the PostgreSQL database, pgvector, and LiteLLM located on the VPS (accessed via Headscale IPs). It is accessible to the user at http://localhost:3000.  
> * **ppt-mcp (@ykuwai/ppt-mcp):** A local server based on the **Model Context Protocol (MCP)** running in a Node.js environment on Windows 11\. It hooks directly into the active powerpoint.exe process via Windows COM automation, providing the local Open WebUI with over 150 programmatic tools to manipulate the open presentation in real time.  
> * **Microsoft PowerPoint:** The official desktop application where the user has their PPTX template open. Changes to the slides are executed live right in front of the user's eyes.

## ---

**📝 4\. Summary of Addressed Topics**

During our discussion, we systematically analyzed the workflow and weighed different architectural choices to achieve your goal. We covered the following key points:

> * **Initial Idea and Automation with Images:** We established that your VPS configuration (LiteLLM \+ OpenRouter) allows for full automation. Free APIs (Pexels, Unsplash) or Python libraries like duckduckgo\_search combined with python-pptx can be used to download free images (Creative Commons) and insert them into the PPTX template.  
> * **RAG and Comparing Multiple Documents:** We analyzed how classic RAG performs when comparing massive international reports. We concluded that due to the limitations of semantic search on local chunks, a two-step approach is best: a long-context model (e.g., Claude 3.5 Sonnet via OpenRouter) first extracts structured data (JSON/table) for individual countries, and then the model synthesizes this refined data into the final 10 slides.  
> * **External LLMs and Tool Calling:** We clarified how models use functions (Function Calling / Tools) via OpenRouter to search your local RAG database. The model does not need to know file names; the tool searches the entire database and returns only the relevant paragraphs.  
> * **Open WebUI vs. OpenClaw:** We defined the roles of both platforms. Open WebUI is an excellent visual interface for chat and RAG analysis, while OpenClaw is an autonomous agent with code execution capabilities that can independently write and run Python scripts on the VPS terminal to generate the final .pptx files.  
> * **PowerPoint Application Plugins:** We reviewed the market of commercial AI plugins (Plus AI, Beautiful.ai, Copilot). We found that they are closed to external integrations and cannot read your local RAG on the VPS. Advanced MCP servers (ppt-mcp) were identified as the ideal technical alternative for live editing.  
> * **Security Analysis and Client Integration:** We looked for the most secure and user-friendly path for non-technical users who want to see editing results live in an open PowerPoint. We rejected risky port forwarding to the public internet and simple copy-paste methods. A **Headscale VPN tunnel** was selected as the best and most secure solution, allowing the local Open WebUI to use the full VPS backend while safely managing PowerPoint locally via the MCP protocol.

---

When you are ready to begin implementation, let me know which part of the configuration (**Headscale settings on the VPS** or the **Docker environment on Windows 11**) we should set up first\!