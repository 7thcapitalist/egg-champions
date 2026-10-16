# Operar a Roblox Factory com Codex

Trabalhe nesta copia local. `main` foi importada 34 commits a frente de
`origin/main`; nao use push para validar. Um push em `main` que altera `games/**`
ou `factory/**` aciona o workflow que publica no lugar de TESTE.

## Validar Egg Champions

No PowerShell, na raiz deste repositorio:

```powershell
python -B factory/tools/validate_config.py games/egg-champions/config
python -B factory/tools/run_tests.py games/egg-champions
python -B factory/tools/gate.py games/egg-champions spec_parsed
python -B factory/tools/gate.py games/egg-champions economy_tuned
python -B factory/tools/gate.py games/egg-champions planned
python -B factory/tools/gate.py games/egg-champions built
python -B factory/tools/gate.py games/egg-champions assets
python -B factory/tools/state.py show games/egg-champions
python -B -m unittest discover -s factory/tests -p test_run_factory.py -v
```

Opcionalmente, `python -B factory/tests/real_codex_smoke.py` testa uma chamada
real de `Run.run_agent` em fixture descartavel. A CLI precisa gravar seu banco
de estado local fora do workspace; um sandbox que bloqueie esse acesso deve
autorizar apenas essa chamada ou registrar o bloqueio.

`built` inclui Luau 0.742 (pin em `rokit.toml`), Rojo, Selene e StyLua. Se
`luau` nao estiver disponivel, execute `rokit install`. A suite usa arquivos
temporarios no `build/` ignorado pelo Git.

Para gerar um lugar local e abrir no Roblox Studio:

```powershell
rojo build games/egg-champions -o games/egg-champions/build/game.rbxl
```

Abra `game.rbxl` pelo menu File > Open from File. O Studio usa perfil
temporario quando um `.rbxl` local nao consegue acessar DataStore; esse modo
nao prova save/rejoin. Verifique o painel Output durante o playtest.

## Continuar tarefas com o executor

Use um checkout Git isolado e limpo para rodar o orquestrador. A copia
principal ainda contem referencias importadas nao rastreadas e o preflight
recusa executa-la para protege-las. Execute os comandos de validacao acima na
copia principal quando precisar apenas checar o jogo.

```powershell
python -B factory/tools/run_factory.py games/egg-champions --max-tasks 1 --attempts 2 --task-minutes 30
```

O backend padrao e `codex exec`; cada tentativa recebe as instrucoes do papel
correspondente em `.claude/agents/` e um brief especifico. `--agent-cmd` e
somente para testar o orquestrador com uma fixture. O executor faz commits
locais por padrao. `--push` e opt-in e nao faz parte deste procedimento.
`--budget-usd` e rejeitado, pois nao ha medicao de custo em USD integrada.

Interrompa com Ctrl+C. Depois, consulte
`games/egg-champions/reports/latest.md`, `reports/run-log.md` e
`reports/agents/` no checkout da execucao. Para um bloqueio, leia o patch em
`reports/blocked/`, corrija a causa e retome com `--unblock ID`. Nunca aplique
um patch sem revisa-lo. Se um agente editar um caminho proibido, a tentativa
e rejeitada. O preflight exige arvore limpa justamente porque tentativas
falhas sao revertidas no checkout isolado.

`state.json` muda somente por `factory/tools/state.py`; marque `passed` apenas
depois de executar o gate correspondente. `worlds`, `playtested` e
`published_test` nao tem gates completos e permanecem pendentes.
