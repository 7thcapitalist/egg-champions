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

Os cenarios locais de QA de inventario, gyms e portais estao documentados em
[LAUNCH-REPORT.md](games/egg-champions/LAUNCH-REPORT.md). Para construir um:

```powershell
python -B factory/tools/build_playtest.py games/egg-champions collection
```

Abra o resultado em `build/playtest/` como arquivo local. Essas fixtures
exigem Studio e PlaceId zero, nao fazem parte do build de distribuicao e nao
devem ser publicadas.

## Continuar tarefas com o executor

Use um checkout Git isolado e limpo para rodar o orquestrador. A copia
principal ainda contem referencias importadas nao rastreadas e o preflight
recusa executa-la para protege-las. Execute os comandos de validacao acima na
copia principal quando precisar apenas checar o jogo.

### Preparar o checkout no Windows

Abra PowerShell na raiz desta copia. Escolha uma pasta de destino nova.
Esta sequencia copia o historico local e faz checkout do HEAD lido na
origem. Nao usa fetch/push nem copia arquivos nao rastreados ou alteracoes
nao commitadas. O remote que o clone local cria e removido ao final.

```powershell
$factorySource = (Resolve-Path -LiteralPath '.').Path
$factoryRun = 'C:\Users\joaov\Documents\Codex\2026-10-15\roblox-factory-acceptance-clean-2026-10-16'
if (Test-Path -LiteralPath $factoryRun) { throw 'O destino ja existe; escolha uma pasta nova.' }
$factoryHead = (git -C $factorySource rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel ler HEAD.' }
git clone --no-hardlinks --no-checkout -- $factorySource $factoryRun
if ($LASTEXITCODE -ne 0) { throw 'Clone local falhou.' }
git -C $factoryRun switch -c codex/factory-local $factoryHead
if ($LASTEXITCODE -ne 0) { throw 'Checkout do HEAD falhou.' }
git -C $factoryRun remote remove origin
if ($LASTEXITCODE -ne 0) { throw 'Remocao do remote local falhou.' }
$factoryRunHead = (git -C $factoryRun rev-parse HEAD).Trim()
if ($factoryRunHead -ne $factoryHead) { throw 'HEAD do clone divergiu.' }
if (git -C $factoryRun status --porcelain) { throw 'O clone nao esta limpo.' }
git -C $factoryRun remote -v
Set-Location -LiteralPath $factoryRun
```

`remote -v` deve ficar vazio. `--no-hardlinks` deixa os objetos Git
independentes da origem. O clone preparado nesta entrega esta no caminho
acima, branch `codex/factory-local`, HEAD
`b9e62108dbfa500fa604e37a141a0dd45148099f`, que contem os 34 commits
importados mais `3786b2c`, `14759c3` e `b9e6210`, incluindo a correcao
dos seguidores. Uma repeticao futura deve escolher
outro destino e lera o HEAD atual, inclusive commits locais posteriores.

### Provar somente o preflight

Ainda dentro do clone, rode o preflight existente diretamente. Ele inspeciona
Git e metadados de `.env`, sem ler seu conteudo; nao inicia agentes, nao
executa etapas e nao faz commit/reset. `python -B` evita criar `__pycache__`.

```powershell
@'
from pathlib import Path
from types import SimpleNamespace
import subprocess
import sys
sys.path.insert(0, str(Path('factory/tools').resolve()))
from run_factory import Run
Run(SimpleNamespace(game_dir='games/egg-champions')).preflight()
assert subprocess.check_output(['git', 'status', '--porcelain'], text=True) == ''
assert subprocess.check_output(['git', 'remote', '-v'], text=True) == ''
print('preflight: PASS; working tree clean; no remotes')
print('HEAD: ' + subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip())
'@ | python -B -
if ($LASTEXITCODE -ne 0) { throw 'Preflight falhou; nao execute a fabrica.' }
```

Esse procedimento foi executado no clone indicado e passou. O historico e
os arquivos importados nao rastreados da origem foram preservados. A
evidencia esta em [preflight-final.txt](games/egg-champions/reports/night-acceptance-2026-10-16/preflight-final.txt).

### Executar uma tarefa futura

Quando houver um brief pendente, ainda dentro desse clone limpo:

```powershell
python -B factory/tools/run_factory.py games/egg-champions --max-tasks 1 --attempts 2 --task-minutes 30
```

As 44 tarefas atuais ja estao done. Rodar o executor agora nao implementa
os gates ausentes de `worlds`, `playtested` ou `published_test`.

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
