#!/usr/bin/env python3
"""McNemar exact test — fast vs reasoning arms on the owner's 5-category subset.

Inputs: --fast-csv <mmlu-fast-items.csv> (committed), --reasoning <item JSON list>
Output: n, discordant cells (b,c), binomial-exact p (two-sided), 95% CI, delta pts,
        verdict vs the PRE-REGISTERED rule (Δ<=2 keep · 3-5 decide on L3 · >5 void).
Pairing key: question_id, restricted to the 5 categories both arms ran
(other|health|computer science|math|biology). Unpaired items are reported.
"""
import argparse
import json
import csv
import math


def binom_exact_two_sided(b, c):
    """McNemar exact test (Edwards): p = 2 * sum_{k=0}^{min(b,c)} C(n,k) 0.5^n."""
    n = b + c
    if n == 0:
        return 1.0
    def comb(nn, kk):
        return math.comb(nn, kk)
    lo = comb(n, min(b, c))
    p = 0.0
    for k in range(0, min(b, c) + 1):
        p += comb(n, k) * (0.5 ** n)
    p *= 2.0
    return min(1.0, p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fast-csv", required=True)
    ap.add_argument("--reasoning-json", required=True)
    a = ap.parse_args()

    fast = {}
    with open(a.fast_csv) as f:
        for row in csv.DictReader(f):
            fast[int(row["question_id"])] = {
                "cat": row["category"], "correct": int(row["correct"]),
                "pred": row["pred"], "answer": row["answer"],
            }
    items = json.load(open(a.reasoning_json))
    reasoning = {}
    for it in items:
        qid = int(it["question_id"])
        reasoning[qid] = {"cat": it["category"], "correct": int(it["correct"]),
                          "pred": it["pred"], "answer": it["answer"]}

    cats = {"other", "health", "computer science", "math", "biology"}
    paired = sorted(set(fast) & set(reasoning))
    paired = [q for q in paired if fast[q]["cat"] in cats and reasoning[q]["cat"] == fast[q]["cat"]]
    only_fast = [q for q in sorted(set(fast) - set(reasoning)) if fast[q]["cat"] in cats]
    only_reason = [q for q in sorted(set(reasoning) - set(fast)) if reasoning[q]["cat"] in cats]

    b = c = 0
    cat_b = {}
    for q in paired:
        f_c, r_c = fast[q]["correct"], reasoning[q]["correct"]
        if f_c == 1 and r_c == 0:
            b += 1
            cat_b.setdefault(fast[q]["cat"], [0, 0])[0] += 1
        elif f_c == 0 and r_c == 1:
            c += 1
            cat_b.setdefault(fast[q]["cat"], [0, 0])[1] += 1
    n = len(paired)
    deltas = {cat: (v[0] - v[1]) for cat, v in cat_b.items()}
    f_corr = sum(1 for q in paired if fast[q]["correct"]) / n
    r_corr = sum(1 for q in paired if reasoning[q]["correct"]) / n
    p = binom_exact_two_sided(b, c)
    delta_pts = round((f_corr - r_corr) * 100, 2)  # >0 => fast better

    rule = "keep (Δ<=2 pts)" if abs(delta_pts) <= 2 else (
        "decide on L3 (3-5 pts)" if abs(delta_pts) <= 5 else "speed win VOID (>5 pts)"
    )
    print(f"n_paired={n} (categories: {','.join(sorted(cats))})")
    print(f"not-in-fast={len(only_fast)} not-in-reasoning={len(only_reason)} (excluded from pairing)")
    print(f"fast correct {f_corr:.4f} reasoning correct {r_corr:.4f} delta={delta_pts:+.2f} pts")
    print(f"discordant cells: b(fast=1,reason=0)={b}  c(fast=0,reason=1)={c}  n_discordant={b+c}")
    print(f"per-category discordant (b,c): {cat_b}")
    print(f"cmh/mcnemar exact two-sided p={p:.4f} (binomial, b+c discordant)")
    print(f"95% CI for delta (Wald, p_disc): ongoing — see raw responses for the needle")
    print(f"PREREGISTERED RULE: {rule}")


if __name__ == "__main__":
    main()