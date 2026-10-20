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

Nao execute `factory/tests/real_codex_smoke.py`: geracao real permanece
proibida durante esta revisao. Use somente testes com mocks.

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

Os cenarios locais de QA de inventario, gyms e portais estao documentados em
[LAUNCH-REPORT.md](games/egg-champions/LAUNCH-REPORT.md). Para construir um:

```powershell
python -B factory/tools/build_playtest.py games/egg-champions collection
```

Abra o resultado em `build/playtest/` como arquivo local. Essas fixtures
exigem Studio e PlaceId zero, nao fazem parte do build de distribuicao e nao
devem ser publicadas.

## Executor pausado para revisao

A politica central esta em `factory/executor.json`: modelo economico
`gpt-6-luna`, esforco `low`, duas tentativas totais persistentes, timeout,
orcamento zero e pausa ativa. Nao retome a producao antes da revisao dos dois
relatorios em `factory/reports/`. Nao copie o projeto nem troque de executor
para contornar negativas de acesso.

Verificacao sem IA, publicacao ou alteracao do Studio:

```powershell
python -B factory/tools/run_factory.py games/egg-champions --executor-status
python -B -m unittest discover -s factory/tests -p 'test_*.py' -v
```

Leia a secao Run the factory em `factory/README.md` para os limites reais,
a medicao exigida, o ledger persistente e as limitacoes da quota de assinatura.
Nao use push como validacao: o workflow existente pode publicar no TESTE.
Nenhum comando de retomada esta autorizado nesta entrega.

Revisao do executor em 2026-10-20: politica relida por chamada, ledger com
ancora de integridade e validacao estrutural, tentativas/prazos persistentes
tambem nos prompts e relatorios. --finish exige chamada medida bem-sucedida
registrada para a propria tarefa. Leia os dois relatorios atualizados; a
producao permanece pausada e nao ha autorizacao de retomada.
