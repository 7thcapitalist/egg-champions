# Relatorio da Roblox Factory no Codex

Data: 2026-10-16. Trabalho local, sem push nem publicacao.

Este documento registra a migracao inicial da factory. A entrega posterior
de qualidade do jogo, com novos testes e evidencias, esta em
[LAUNCH-REPORT.md](games/egg-champions/LAUNCH-REPORT.md).
O estado atual e **759 testes do jogo, 6 autotestes e 44 tarefas done**.
A aceitacao complementar e o clone isolado operacional estao em
[NIGHT-ACCEPTANCE.md](games/egg-champions/NIGHT-ACCEPTANCE.md).
Os numeros de 738/43 abaixo pertencem ao snapshot da migracao.

## Resultado comprovado

| Area | Resultado |
| --- | --- |
| Luau | 0.742 instalado, pin preservado; 6 autotestes do runner e 738/738 testes do jogo passaram. |
| Configuracao e plano | `validate_config` e gates `spec_parsed`, `economy_tuned`, `planned` passaram; 43 briefs estao done. |
| Build | Gate `built` passou exigindo testes, Rojo, Selene e StyLua; build local em `games/egg-champions/build/game-playtest.rbxl`, SHA-256 `E998FFFAA6E402C41A5BD14FA5DE40CA858A435B260BEC690644D1966AF33604`. |
| Assets | Gate `assets` passou para o snapshot atual de 36 modelos; no Studio, `ModelLibrary` carregou 36/36, zero placeholders. |
| Executor | Codex CLI e o backend padrao; 9 testes isolados passaram (JSONL, erro, retry, guard de caminhos, preflight, commit local e encerramento da arvore de processos Windows). `Run.run_agent` chamou o Codex real em fixture temporaria e retornou `CODEX_FIXTURE_OK`, 4 eventos JSONL e `turn.completed`. |
| Estado | `built` passou somente apos o novo gate, via `state.py`; `worlds`, `playtested` e `published_test` continuam pending. |

O teste deliberadamente quebrado em copia isolada fez o gate `built` falhar.
Outra fixture confirmou que edicao fora do escopo e recusada, e que arquivo
importado nao rastreado bloqueia o preflight sem ser apagado. A chamada real
do Codex precisou de aprovacao de sandbox para gravar o banco de estado da CLI
fora deste workspace; a fixture foi removida apos o teste. O comando real foi
`python -B factory/tests/real_codex_smoke.py`. O script cria e remove seu
repositorio temporario em `build/`.

## Playtest no Roblox Studio

Abri o `.rbxl` local no Studio e iniciei cliente e servidor. A primeira
execucao revelou uma falha real: `Profiles` chamava `GetDataStore` durante o
carregamento do modulo, e um lugar local nao publicado gerava erro antes de
ativar o fallback de perfil temporario. Corrigi a inicializacao para capturar
essa falha apenas no Studio; em servidor publicado, o erro continua fatal.

No build corrigido, o Output registrou servidor pronto (30 pets, 6 ovos,
3 mundos), 6 stands, 3 gyms, 3 portais e cliente pronto. Observei mundo,
HUD e tutorial; clique aumentou moedas; a compra de um Meadow Egg gerou um
Leafpup Common; o inventario exibiu o pet e Equip mudou a equipe de 0/3 para
1/3, com bonus de click e proxima instrucao do tutorial. A interface exibiu
um ponteiro para as acoes de hatch e equipe. Em seguida, comprei mais dois
Meadow Eggs e equipei Puddlet e outro Leafpup; a equipe mostrou 3/3 e o
bonus de click passou a +12. O Output registrou 36/36 modelos
carregados. Houve aviso de CorePackages/Roblox UIBlox, sem erro fatal do jogo
na execucao corrigida.

Este foi um playtest parcial. Nao executei fee e batalha de gym,
derrota/retry, vitoria, teleporte, layouts de outras resolucoes nem
save/rejoin. O `.rbxl` local usa perfil temporario sem persistencia porque
DataStore exige lugar publicado; o Output confirmou esse fallback. A etapa
`playtested` nao foi aprovada.

## Arquivos e verificacao

- `factory/tools/run_tests.py`: temporarios do runner em `build/` para o sandbox Windows.
- `factory/tools/gate.py`: suite Luau adicionada ao gate `built`.
- `factory/tools/run_factory.py` e `factory/tests/test_run_factory.py`: backend Codex, traces JSONL, limites, retry e execucao local por padrao.
- `games/egg-champions/src/server/Profiles.luau`: fallback Studio para `GetDataStore` indisponivel no carregamento.
- `games/egg-champions/state.json`: `planned` e `built` reconciliados por `state.py`.

Comandos reproduziveis estao em `RUN-CODEX.md`. Na verificacao final,
`python -B factory/tools/gate.py games/egg-champions built` retornou
`OK: 43 task(s) done, and run_tests, rojo, selene and stylua all pass`.
`python -B -m unittest discover -s factory/tests -p test_run_factory.py -v`
retornou 9 testes, `OK`. O caminho de timeout tem tratamento implementado;
um timeout real de 60 segundos do Codex ainda nao foi provocado.

O Git iniciou 34 commits a frente de `origin/main`. Nenhum push foi feito.
Os arquivos importados em `claude-*`, `related-conversations/` e outros
nao rastreados foram preservados; o executor nao rodou nessa arvore suja.

## Proximos passos do Joao (atualizados apos aceitacao)

Gym1, portais, UI desktop/celular emulado, inicio curto sem recursos
semeados, gyms2/3 com referencia e preflight isolado ja foram executados.
Resultados em LAUNCH-REPORT e NIGHT-ACCEPTANCE; nao precisam ser repetidos
como tarefas locais pendentes.

1. Testar save/rejoin, autosave junto da saida e trava entre servidores em
   TESTE publicado, incluindo recuperacao de falha.
2. Validar compra/cancelamento/beneficios dos passes no TESTE; jogar
   progressao longa natural com jogadores novos e testar celular fisico,
   rede lenta e mais de um jogador.
3. Revisar titulo, descricao, icone/thumbnails, lugar alvo e commits antes
   de aprovar publicacao. Um push relevante em main publica no TESTE.

Os gates completos worlds, playtested e published_test continuam ausentes;
as etapas permanecem pending. Isso e uma limitacao da fabrica, nao uma
validacao que Joao deva marcar como passed manualmente.
