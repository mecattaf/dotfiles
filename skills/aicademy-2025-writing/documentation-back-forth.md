the idea is that over time there may be a drift between some design decisions and the actual implementation. it is therefore important to constantly scan for these. a prompt i was previously successful with:
```
please thoroughly evaluate evetrything you see. let me know what was not clear from the documentatin.
i need one markdown artifact each where you highlight:
1) gaps in the docs
2) inconsistencies, and incongruities
3) direct contradictions in the approach
```

---

key tip for ai coding revolves around creating subagents with just the right amount of context.
You're noticing subagents drifting beyond their remit by absorbing excessive or irrelevant context. In classical software engineering, this relates most closely to scope creep, violations of separation of concerns, and leaky abstractions. The antidotes are tight contracts, clear module boundaries, and well-scoped interfaces.
this is why specific subtasks go into github issues, but we make sure that the right amount of context and instructions are supplied

---

look into docuwriter.ai and workik ai


https://github.com/AsyncFuncAI/deepwiki-open#js-repo-pjax-container
we ovserve the prompts from this project and understand how to index a specific repo

also look into the logic of gitingest
https://github.com/cyclotruc/gitingest

and the classic aider repo map
https://aider.chat/docs/repomap.html

this would be an auto-generated documentation translation for existing websites.

some more resources to investigate:
https://medium.com/@sjng/deepwiki-why-i-open-sourced-an-ai-powered-wiki-generator-b67b624e4679
https://deepwiki.com/PurCL/RepoAudit
https://deepwiki.com/asgeirtj/system_prompts_leaks
https://github.com/AIDotNet/OpenDeepWiki
https://github.com/AsyncFuncAI/deepwiki-open/tree/main/api

also see opendevin? devindocs?
