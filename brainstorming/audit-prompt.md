Role: Senior Infrastructure Architect, Security Expert, and Ansible Automation Engineer.

Context: 
This repository contains a pre-production homelab architecture plan hosted on GitHub. Nothing is live yet.
Read all conventions first.
Inputs Provided for Reference:
- [Qwen-bugs.md]: Contains existing known bugs.
- [todo.md]: Contains known tasks, issues, milestones, and current open questions. Cross-reference your audit against this roadmap.

Task:
1. Thoroughly review all repository conventions, inventory layouts, and style guides.
2. Analyze the contents of the `/docs` and `/IaC` (Ansible) folders.
3. Cross-examine the current state against `bugs.md` and `todo.md`.
4. Conduct an architectural, automation, and security audit tailored to this hybrid environment.

Specific Audit Focus Areas:
- Bug Patterns: Analyze `bugs.md` to find *root causes* (e.g., if multiple bugs stem from bad Traefik routing or 1Password timeout issues).
- Roadmap Alignment: Ensure your recommendations do not conflict with milestones in `todo.md`.
- Secret & GitOps Pipeline: Evaluate 1Password integration with Ansible. Verify no raw credentials leak into GitHub.
- Ingress, SSO & Identity: Audit Traefik and Authentik setup for local vs. external traffic.
- High Availability & Failover: Analyze the Home Assistant standby mechanism (RPi4 to Old PC).

Deliverables:
Create or update the markdown file `Qwen-architecture.md` with these exact sections:
1. Current Topology & Traffic Flow (Mapping of ingress through Traefik -> Authentik -> Services)
2. Root Cause Analysis of Existing Bugs (Grouping the 1500 lines of bugs into major systemic architectural flaws)
3. Security & Secrets Management Audit (Focus on 1Password integration and GitHub leakage risks)
4. Infrastructure & HA Audit (Focus on Home Assistant failover and network dependencies)
5. Updated Strategic Roadmap (Consolidate your findings with the tasks from `todo.md` into a unified High/Medium/Low priority execution plan)
6. Technical Open Questions (Filter out resolved questions from `todo.md` and list only critical, remaining design blockers)

