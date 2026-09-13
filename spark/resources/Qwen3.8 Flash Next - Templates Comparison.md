# Qwen3.8 Flash Next - Templates Comparison

**Community:** r/LocalLLaMA · **Posted by:** u/HeDo88TH · **Score:** 79 upvotes · **Date:** September 5, 2026

**Source:** https://www.reddit.com/r/LocalLLaMA/comments/1w84mod/qwen38_flash_next_templates_comparison/

---

I was running into a lot of posts that praised both the [Fixed template](https://huggingface.co/froggeric/Qwen-Fixed-Chat-Templates) and the [Sharp template](https://huggingface.co/peculiar-ragdoll/Qwen-Sharp-Chat-Templates) in comparison to the stock one, so I put them to the test.

It's not as extensive as it should be for a paper-grade analysis, but it gives out the point of each template.

# Test setup

I used **SWE-bench Verified** with **mini-SWE-agent 2.4.6**, slice `0:100` (the identical 100 tasks for all runs)

# Hardware

* **CPU:** Ryzen 9 9900X
* **RAM:** 128 GB DDR5-5600
* **GPU:** RTX PRO 6000 WS

# Runtime

I containerized [`jpezzulli/sglang-rtxpro6000`](https://github.com/jpezzulli/sglang-rtxpro6000) and ran Flash Next with [RadixArk/Qwen3.8-Flash-Next-NVFP4](https://huggingface.co/RadixArk/Qwen3.8-Flash-Next-NVFP4) on **CUDA 13.3**.

* Full **262K context**
* **BF16 KV**
* **51.2 GB FP8 n-gram embedding table** pinned in RAM
* **32 GB HiCache** pinned in RAM

I ran all templates at both **medium** and **xhigh** reasoning efforts.

# Results

|Metric|Stock (medium)|Stock (xhigh)|Stock Δ|Fixed (medium)|Fixed (xhigh)|Fixed Δ|Sharp (medium)|Sharp (xhigh)|Sharp Δ|
|:-|:-|:-|:-|:-|:-|:-|:-|:-|:-|
|Resolved|91|**99**|\+8|87|**98**|\+11|94|94|\+0|
|Resolution rate|91%|**99%**|\+8 pts|87%|**98%**|\+11 pts|94%|94%|\+0 pts|
|Median output tokens|5,691|13,855|\+143.5%|6,956|14,819|\+113.0%|8,596|12,008|\+39.7%|
|Median reasoning tokens|3,050|8,759|\+187.2%|3,809|9,063|\+137.9%|5,437|7,967|\+46.5%|
|Median wall time|38s|1m 46s|\+180.4%|43s|1m 47s|\+152.3%|1m|1m 32s|\+53.4%|
|Total wall time|1h 47m 1s|4h 31m 22s|\+153.6%|1h 59m 53s|4h 4m 52s|\+104.3%|2h 29m 18s|3h 11m 36s|\+28.3%|

https://preview.redd.it/02geu81o8qnh1.png?width=1152&format=png&auto=webp&s=ad851853e5171288af8cb07b1d16fdb62e6e986d

https://preview.redd.it/v2mt6mgo8qnh1.png?width=1152&format=png&auto=webp&s=8e01524041f060508105cd5bdacb7abbf4389c35

https://preview.redd.it/ph1z36zo8qnh1.png?width=1152&format=png&auto=webp&s=1b2c7ef749cbb72d847120bf01f215bac7396f39

# Takeaways

https://preview.redd.it/6ydu12mp8qnh1.png?width=1152&format=png&auto=webp&s=8e8e360b0e2966e6807fb5fe16453ba0a3176eb0

* Raising reasoning effort to **xhigh** closes almost all of stock's and fixed's gap to Sharp. At medium, Sharp led resolution by **+3 tasks over stock** and **+7 over fixed**; at xhigh, stock and fixed instead **lead Sharp by +5 and +4 tasks**, respectively.
* Sharp barely moves on resolution (**94 → 94**) despite a real token/time cost increase, median reasoning tokens rise **+46.5%** and median wall time **+53.4%**. This suggests it was already extracting most of the benefit it could get from extra reasoning budget at medium, while stock and fixed still had headroom.
* Sharp remains the most token-efficient per resolved task at xhigh (**14,541 output tokens/resolved vs. \~17,000 for stock/fixed**), consistent with its medium-era efficiency edge, but it's no longer the highest-resolving template once reasoning effort is high.
* Absolute cost scales heavily with reasoning effort: total wall time roughly **2.3–2.5×** for stock/fixed and **+28%** for Sharp; total reasoning tokens roughly doubled for stock/fixed and increased **+35%** for Sharp.

# Conclusion

* **Sharp** should be used at medium and it keeps a reasonable accuracy at very good speed. I don't see the point in using it at xhigh. By sacrificing a small accuracy you complete the tasks in half the time.
* **Stock** is the slowest but the most precise.
* **Fixed** is the middle ground between Stock and Sharp both in accuracy and speed
* The next benchmark will be on a much extensive SWE-bench Multilingual + Terminal Bench.

*Disclaimer: I wrote the post myself then used AI to format it properly for readability*

---

## Comments (15 fetched)

---

**u/Tormeister** · 14 points · Sep 5, 2026

I'm sticking with the default one, thanks for the comparison

---

> **u/palewiCket1** · 5 points

> makes sense tbh, stock at xhigh just edges everything else out

**u/DustNearby2848** · 9 points · Sep 5, 2026

I’ve been using sharp, but looks like I should go to froggerics. Thanks!

---

**u/Healthy-Zebra-9856** · 9 points · Sep 5, 2026

You are probably the first one to mention accuracy while comparing, so kudos and thanks.  Yes,  in all my tests, I have found that medium effort is just not there.  Low & xhigh seems to be the best, however, low ends up costing the same as high as in many situations there are mistakes and thus more turns.   That said, Froggeric & Peculiar Ragdoll seems to swash the quality & precision.  

---

> **u/ex-arman68** · 13 points

> Author of the froggeric fixed template here: Initially I had the default to xhigh, matching the original template. However so many people were complaining about how the new Qwen 3.8 models were spending so much time thinking and filling their context, it seemed the consensus was that a default of medium would be better for most, and would avoid giving bad press to Qwen 3.8.
> 
> However, for me being used to coding with much bigger model, there is nothing wrong with xhigh as a default, and it matches what I see with frontier models. That's what I use and recommend, the difference in quality is worth it for coding tasks. For non coding tasks, medium is perfectly fine. It is easy to control and change with my template.

> > **u/Healthy-Zebra-9856** · 3 points

> >  I think it has a lot to do with their training it in xhigh.  Also, several of the arxiv papers are showing this mediocrity in medium effort lol.  I will try it again.  Thanks for the update.  I hope this happened in the last few days.

**u/Cautious_Chicken_604** · 4 points · Sep 5, 2026

So nice to see data rather than just vibes. I haven't adopted either of these yet because it all seemed so vibes based. Looks like Sharp on medium is a good trade-off.

---

**u/returnity** · 3 points · Sep 5, 2026

I’ve been wondering about this given the amount of love that we see here on the sub for the Sharp templates… this aligns directly with my intuition and some of [u/peculiar-ragdoll](u/peculiar-ragdoll) published results. Seems like there is a cost for speed, and it’s good to know what it is. Particularly interesting that it suppresses the high reasoning capabilities of the model — at least we know it’s having an effect, which was the other thing I was curious about.

Edit: just want to make it clear to people that while the difference between 94 and 99 is probably statistically significant (p=0.05), the difference between froggeric and stock is indisputably down to chance IMO. I still run modified froggeric for its QoL improvements. Thanks /u/ex-arman68 for your efforts!

---

**u/No_Algae1753** · 3 points · Sep 5, 2026

Very nice test! Afaik these templates do cause a lot of issues and it's nice to see someone trying out different templates, valuable info! Are there other templates which might be interesting to test ? 

---

**u/arkham00** · 3 points · Sep 5, 2026

Very informative test thank you. I'm really looking forward for the multilingual bench

---

**u/-_Apollo-_** · 3 points · Sep 5, 2026

I wonder what in the fixed version causes it to underperform stock at xhigh? Or is it margin of error?

---

**u/WonderRico** · 2 points · Sep 6, 2026

hmm, interesting... did you see my own tests results ? it's very similar to you setup. i run also 100 tasks from sw-verified, but from the django set only.

**I tested two quants** : the same radix version as your on the same sglang config, and another one in vLLM.
 
I only tested with the **stock chat template** (the one provided in both the versions I tests, and they are both identical)

https://old.reddit.com/r/LocalLLaMA/comments/1w7c4ej/updated_my_benchmark_with_a_new_vllm_based_recipe/

https://wonderrico.github.io/local_llm_benchmark/benchmark-main.html?filter=next

I tested both medium and xhigh, and I did not see any benefit to the score.

However, **the AWQ version on vLLM got me to 98/100 while the NFP4 in SGLANG stayed at 91**

---

> **u/WonderRico** · 2 points

> I tried the same run with two other templates (frogeric and sharp) and did not get any meaningful positive impact on score. I actually got (slightly) lower scores and significant lower efficiency
> 
> | model | template | reasoning effort | Weights quant | KV cache quant | PLE quant | Score /100 | Requests | req/pts | in Mtok | out Mtok |
> |---|---|---|---|---|---|---|---|---|---|---|---|
> | Qwen3.8-Flash-Next | stock | medium | NVFP4 | FP8 | FP8 | 91 | 2653 | 29 | 44 | 0,88 |
> | Qwen3.8-Flash-Next | sharp | medium | NVFP4 | FP8 | FP8 | 89 | 2903 | 33 | 50 | 0,97 |
> | Qwen3.8-Flash-Next | frogerric | medium | NVFP4 | FP8 | FP8 | 89 | 3017 | 34 | 50 | 0,96 |
> 
> https://wonderrico.github.io/local_llm_benchmark/benchmark-detail.html?filter=next

**u/jpezzulli** · 2 points · Sep 6, 2026

Glad to see my repo being used.  New release being published right now with about 15 percent increase c1 decode and 5 percent at c4.  Also a few maintenance items that were in a release early!  

I am too tired to dig into your results right now but it looks like good work at first glance!  I might have to make a change based off this info!

---

> **u/HeDo88TH** · 1 points

> Thanks for your amazing repo, I'm looking forward to update it! 

> > **u/jpezzulli** · 1 points

> > Update live :)

**u/Dany0** · 1 points · Sep 5, 2026

Your graphs are all wrong and don't agree with the table. I take it the table is the source of truth here?

---

**u/walden42** · 1 points · Sep 6, 2026

Sorry for slightly off topic question OP, but I tried the same solution from jpezzulli, and for certain tasks, it repeatedly mangled file paths, and quite possibly other similar typo errors, bust mostly file paths. For example, instead of \`/home/user/project\` it would do \`/home/user/project/home/user/project\` or \`/home/user/c://home/user/project\`. Did you encounter anything like this by any chance?

---

> **u/HeDo88TH** · 1 points

> It never happened to me. Sometimes in vscode it cuts off with "no response" or something like that but it's rare. 

> > **u/walden42** · 1 points

> > Hmm, alright. Thanks for confirming.

**u/jinnyjuice** · 1 points · Sep 6, 2026

You should know that using vLLM results in fewer tool call fails compared to SGLang, according to the benchmarks.

---

**u/Interpause** · 0 points · Sep 6, 2026

ive been using chromix's template which is supposed to exactly match the stock template while being more robust

---

**u/ResidentPositive4122** · -4 points · Sep 5, 2026

> I wrote the post myself 

...

> slice 0:100 (the identical 100 tasks for all runs)

:-----)

---

> **u/mrgreatheart** · 5 points

> This is useful and not unpleasant to read. The constant AI writing witch hunt in an AI enthusiast sub is getting very old. 
