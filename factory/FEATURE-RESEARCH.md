# Evidence-led feature planning

Research is an input to bounded design, not proof of popularity or retention.
Record primary HTTPS sources in `<game>/design/feature-research.json`, including
the date checked, availability, observation and limitations. References expire
after 14 days. A claimed chart rank requires an available local snapshot and
matching SHA-256. An unavailable chart cannot support an adopted feature.

Record each original adaptation as adopt, defer or reject. Adoption requires
scoped approval, declared economy/save impacts, file scope and both automated
and engine checks. Economy/save changes require a local design contract;
contract existence does not certify economic balance or persistence safety.
The current game spec and tuning process still apply.

```
python -B factory/tools/feature_research.py <game> check
python -B factory/tools/feature_research.py <game> plan <game>/build/new-proposal
```

The first command checks indexed brief coverage. The second creates proposal
briefs in a new directory and refuses overwrites; it never registers tasks or
changes the spec, config, state, executor, budget or credentials. Review and
register approved briefs deliberately. `planned` validates research when this
optional input exists. Games without this file retain their existing workflow.

These commands use Python standard library only, with no network or model call.
They cannot verify source truth, originality, visual quality, fun or retention.
AI remains behind the existing executor controls; a research plan grants no
execution budget. Publication and resumption remain separate actions.
