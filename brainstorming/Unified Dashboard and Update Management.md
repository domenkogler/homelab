

`# Isaac Homelab: Unified Dashboard and Update Management Plan`

`This document outlines the architectural blueprint and operational workflow for **Isaac**—a database-free, pure GitOps, and Ansible-driven homelab infrastructure. It centralizes lifecycle management, container update tracking, documentation visibility, and family usability by combining **Forgejo**, **Obsidian**, and **Homepage** into a single text-based ecosystem.`

`---`

`## 🏛️ System Architecture`

`The core philosophy of this plan is **Strict Git-as-a-Source-of-Truth**. All server states, application configurations, dashboards, and documentation assets are saved as plain text files in Git, eliminating the overhead and backup risks of database-driven applications.`

┌── \[ Renovate tracks Docker upstream registries \]  
│ └─ Applies 3-day stability delay to updates  
│  
\[ MANAGEMENT \] ──┼── \[ Forgejo Wiki displays live matrix \+ checkboxes \]  
│ └─ Clicking a checkbox generates a Git PR  
│  
└── \[ Forgejo Actions executes targeted Ansible scripts \]  
├─ Pulls fresh images and deploys locally  
└─ Regenerates family dashboard layout configurations

│ (Syncs changes via Git)  
▼  
┌── \[ Obsidian loads the Wiki Git repository locally \]  
\[ VISIBILITY \] ──┼── \[ Admins manage deep technical text runbooks and Canvas \]  
└── \[ Homepage serves as a sleek visual launchpad for family \]

`---`

`## 🛠️ Component Roles`

`### 1. Forgejo: Central Server Command Center`  
`[Forgejo](https://forgejo.org) handles the presentation, state evaluation, and execution components of the homelab directly through its web interface.`  
`*   **Integrated Wiki**: Displays a live service inventory matrix compiled automatically by Ansible templates [Integrated Wiki | Forgejo](https://forgejo.orgdocs/v15.0/user/wiki/). It hosts [Renovate's Dependency Dashboard](https://renovatebot.com) in markdown format directly beneath the inventory.`  
`*   **Renovate Bot Integration**: Automatically tracks Docker registry versions, enforces a **3-day stability delay**, and generates standard Git Pull Requests when update boxes are toggled on the wiki.`  
``*   **Forgejo Actions**: The integrated workflow runner. It features manual trigger execution buttons (`workflow_dispatch`) with tag parameters, ensuring you maintain absolute control over exactly when an Ansible playbook executes.``

`### 2. Ansible (Isaac): The Execution Engine`  
`Ansible controls container deployments and automatically updates the documentation and dashboard layouts based on its variables.`  
``*   **Targeted Runs**: Uses specific tasks and variables (e.g., `--tags "nextcloud"`) to limit execution to a single container stack, preventing slow deployments.``  
``*   **Automated Docs & Layout Generation**: Evaluates running `hostvars` and system parameters, uses Jinja2 templates to build the updated Markdown layouts for Forgejo Wiki, and updates the YAML configuration layout files for **Homepage**.``

`### 3. Homepage: The Consumer Landing Page & Status Panel`  
`[Homepage](https://gethomepage.dev) acts as the web-based, family-friendly interface for day-to-day use.`  
`*   **Clean Usability**: Replaces complex administrative charts with a highly polished grid layout that serves as an intuitive application launchpad for non-technical users.`  
``*   **Zero-Database GitOps Architecture**: Configured entirely via modular, flat YAML text files (`services.yaml`, `widgets.yaml`).``  
`*   **Dynamic Inventory Sync**: Ansible automatically appends or adjusts service links in the YAML structure whenever containers are added or updated, ensuring the layout never needs to be manually configured.`  
`*   **Integrated Privacy & Health**: Uses subtle live status indicators (green/red dots) to prove containers are responding, while isolating heavy developer metrics from family members using strict category visibility rules.`

`### 4. Obsidian: Desktop Writing Companion`  
`[Obsidian](https://obsidian.md) acts as your local, offline IDE for complex text management and system visualization.`  
``*   **Local Editing Environment**: Targets the cloned local directory of Forgejo’s background wiki Git repository (`.wiki.git`) [Integrated Wiki | Forgejo](https://forgejo.orgdocs/latest/user/getting-started/wiki/).``   
`*   **Obsidian Canvas**: Provides a digital whiteboard workspace on your desktop machine to manually stitch together visual network infrastructure graphs and cluster maps without relying on external design tools.`

`---`

`## 🔄 The Lifecycle Workflow`

\[ Update Pushed Upstream \]  
│  
▼ (Waits 3 Days for Stability)  
\[ Appears on Forgejo Wiki Dashboard \] ──\> Check Box to Authorize Change  
│  
▼ (Renovate Automatically Creates PR)  
\[ Review Release Notes & Merge PR \] ──\> Variable Saved into Git History  
│  
▼  
\[ Click "Run Workflow" in Actions \] ──\> Ansible Executes and Deploys Container  
│  
▼  
\[ Matrix & Homepage Automatically Reconstructed \] ──\> Wiki Updates & Live Site Refreshes

`1. **Vetting & Stability**: An update is pushed to an upstream repository. Renovate intercepts it but places it on a strict **3-day hold** to isolate your homelab from breaking changes.`  
`2. **Dashboard Review**: Once stable, the update populates as an available item on your unified **Forgejo Wiki** matrix page.`  
`3. **Approval**: Toggling the update checkbox instructs Renovate to generate a Pull Request. Merging this PR writes the upgraded container version string into your permanent Git configuration files.`  
``4. **Targeted Deployment**: You navigate to the Forgejo **Actions** tab, invoke the `Manual Infrastructure Deploy` script, pass the app's target tag, and click run.``   
``5. **Auto-Documentation & View Update**: Ansible pulls the new image layers, redeploys the target container, regenerates the markdown wiki table documenting the new current version, updates Homepage's `services.yaml` layout, and pushes the text revisions cleanly back to Git.``

`---`

`## 📂 Configuration Examples`

``### `renovate.json` (Root of Main Repo)``  
```` ```json ````  
`{`  
  `"\$schema": "https://renovatebot.com",`  
  `"platform": "forgejo",`  
  `"dependencyDashboard": true,`  
  `"dependencyDashboardAutoclose": false,`  
  `"dependencyDashboardTitle": "Homelab Dashboard Matrix",`  
  `"packageRules": [`  
    `{`  
      `"matchDatasources": ["docker"],`  
      `"stabilityDays": 3`  
    `}`  
  `]`  
`}`  
```` ``` ````

``### `.forgejo/workflows/deploy.yml` (Root of Main Repo)``  
```` ```yaml ````  
`name: Manual Infrastructure Deploy`

`on:`  
  `workflow_dispatch:`  
    `inputs:`  
      `target_tag:`  
        `description: 'Ansible Tag to Deploy (e.g. nextcloud, homepage)'`  
        `required: true`  
        `default: 'all'`

`jobs:`  
  `ansible-deploy:`  
    `runs-on: docker`  
    `steps:`  
      `- name: Checkout Code`  
        `uses: actions/checkout@v4`

      `- name: Run Ansible Playbook`  
        `run: |`  
          `ansible-playbook main_deploy.yml --tags "\${{ github.event.inputs.target_tag }}"`  
```` ``` ````

If you'd like, let me know:

> * Do you want a sample of the **Ansible task and Jinja2 template** that builds the Homepage services.yaml file automatically?  
> * Do you need help formatting **Mermaid.js diagram definitions** inside your automated wiki compiler?