---
name: distributed-systems-security-hardening
description: 'Harden distributed-systems changes for security, CI, RBAC, dependencies, credentials, supply chain, feature-gate / version rollout, certificate rotation, and compatibility safety. Use when changing GitHub Actions, dependencies, base images, RBAC, credentials, webhook behavior, or any feature that needs safe defaults and operator-facing rollout protections.'
argument-hint: 'Change to harden'
---

# Distributed-Systems Security & Rollout Hardening (shared workflow)

Use this skill when hardening a change in any distributed-systems project (Gatekeeper, Kubernetes, cert-controller, frameworks/constraint, secrets-store-csi, etc.). Treat CI, dependencies, credentials, RBAC, certificates, and rollout behavior as production attack surface.

This is the **shared workflow**. Repo-scoped skills add project-specific anchors on top.

## Hardening Workflow

1. **Inventory the exposed surface:**
   - GitHub Actions and workflow permissions
   - container images and build inputs
   - RBAC, service accounts, and admission permissions
   - secrets, certificates, and credentials
   - external calls, retries, caches, and config reload paths
   - feature gates, version gates, compatibility boundaries, and rollout conditions

2. **Harden the supply chain:**
   - Pin third-party GitHub Actions to a SHA, not a tag.
   - Pin container images by digest where practical.
   - Tie dependency bumps to a compatibility or CVE reason.
   - Constrain workflow `permissions:` to least privilege.
   - Prefer boring, auditable mechanisms over custom cleverness.

3. **Harden runtime behavior:**
   - Use secure defaults; require explicit opt-in for risky behavior.
   - Avoid logging sensitive data (tokens, secrets, full request bodies, certificate keys).
   - Keep last-known-good behavior on reload or config failure when appropriate.
   - Emit warnings/events for unsafe modes so operators can detect them.

4. **Harden lifecycle behavior:**
   - Propagate real `context.Context`; never use `context.TODO()` in changed paths.
   - Prefer graceful shutdown over `time.Sleep` polling loops.
   - Preserve ownership and retry behavior on cleanup paths.
   - Avoid silent failure in paths that affect correctness or rollout safety.
   - Lock scope: walk every operation inside `Lock()/Unlock()` and verify shared reads share the lock.

5. **Add observability with the feature:**
   - metrics for reload, retries, unsafe modes, and failure states
   - logs and events with resource identifiers and actionable context
   - dashboards/alerts updates if the metric is operator-critical

6. **Protect performance and compatibility while hardening:**
   - Avoid unnecessary admission/hot-path latency.
   - Bound caches explicitly; design invalidation and retry before adding cache state.
   - Account for feature-gate / version-gate disablement, skew, and downgrade.
   - Preserve API/wire compatibility unless explicitly versioned and documented.

7. **Validate the change and summarize residual risk.** Name the threat model class (supply chain, runtime escape, credential exfiltration, denial-of-service, skew/downgrade) and how the change closes or constrains it.

## Output Format

Provide one of these:

1. **Hardening patch** — concrete diffs with a one-line rationale per change.
2. **Review report** — risks (with severity), required fixes, residual concerns.

## Rules

- Treat CI configuration as production code.
- Do not trade away least privilege for convenience.
- Prefer explicit rollback and rollout notes when behavior changes could affect cluster operators.
- Security boundaries are part of correctness, not a follow-up task.
