---
title: check_doc_domain fixture — the legal tree
role: reference
domain: meta
status: active
tags: [fixture, docs, gate]
---
# Fixture for `check_doc_domain`

Six documents, six frontmatter blocks, nothing else. This is the LEGAL shape the checker must read
GREEN: one domain with an index hub plus a detail doc plus a review/rejected pair, one single-doc
domain whose only doc is its own entry point, and one dispatcher doc that is itself an index.

Every canary the self-test breeds is ONE LINE changed in one of these files, applied in memory and
reverted before the next arm — so the fixture on disk is always the green control, and a mutation
that cannot be reverted is a bug in the self-test.
