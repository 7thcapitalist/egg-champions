# Trabalho noturno: Roblox Factory

Data: 2026-10-16. Migracao e entrega local concluidas.
Estado atual: **759/759 testes do jogo, 6 autotestes do runner e 44 tarefas done**.
Built e assets passaram; worlds, playtested e published_test continuam pending.
Relatorios: [migracao](FACTORY-REPORT.md),
[qualidade](games/egg-champions/LAUNCH-REPORT.md) e
[aceitacao complementar](games/egg-champions/NIGHT-ACCEPTANCE.md).
Operacao reproduzivel em [RUN-CODEX.md](RUN-CODEX.md).

Objetivo: operar a fabrica a partir do Codex, executar testes reproduziveis e entregar um jogo local compilado com evidencias claras do que foi validado. Esta fila tem aproximadamente 4 a 8 horas de trabalho util; termine antes se todos os criterios forem atendidos. Nao mantenha agentes ocupados apenas para consumir o periodo.

Leia `AGENTS.md`, `factory/README.md`, `games/egg-champions/spec.md` e o codigo atual antes de implementar. O material importado em `claude-*` e `related-conversations/` e referencia historica. Este documento registra o pedido do usuario de executar as tarefas no Codex.

## Baseline historico da auditoria inicial

Snapshot anterior a migracao e a task 44. Os numeros abaixo sao historicos,
nao o estado atual. Auditoria somente leitura, sem publicacao:

| Verificacao | Resultado |
| --- | --- |
| Python | 3.13 disponivel |
| Rokit, Rojo, Selene, StyLua e Codex CLI | Disponiveis |
| `validate_config.py` | PASS |
| Gate `spec_parsed` | PASS; hash da spec atual |
| Gate `economy_tuned` | PASS; 3 metas de tempo |
| Gate `planned` | PASS; 43 tarefas, sem ciclo |
| Rojo build | PASS; `.rbxl` temporario de 402.954 bytes |
| Selene | 0 erros, 0 avisos, 0 erros de parse |
| StyLua check | PASS |
| Testes Luau | BLOQUEADOS: executavel `luau` ausente |
| Assets preservados | 36 verificacoes ok; hash corresponde ao `models.json` atual |
| Git | `main` 34 commits a frente de `origin/main`; material da importacao nao rastreado |

Na auditoria inicial, Luau 0.742 ainda nao estava instalado. Foi restaurado
na migracao; o pin em `rokit.toml` foi preservado.

Naquele snapshot havia 43 tarefas done, built pending e um relatorio antigo
de 21 tarefas. A migracao reconciliou esse estado e incluiu a suite no gate
built. A task 44 acrescentou os ajustes de qualidade e elevou a suite a 759.
Os gates worlds, playtested e published_test ainda nao estao implementados.
As evidencias manuais do Studio nao substituem esses gates.

## Limites de execucao

- Trabalhar nesta copia local; preservar os 34 commits existentes e o material importado.
- Manter todo o trabalho local, sem push automatico. O workflow `.github/workflows/roblox.yml` publica no lugar de TESTE quando um push em `main` altera `games/**` ou `factory/**`.
- Nao executar o orquestrador antigo na arvore principal durante a migracao: ele pode resetar tentativas, commitar e enviar mudancas. Usar fixtures ou um checkout isolado para provar esses caminhos.
- Nao ler, imprimir ou commitar segredos. Nesta copia nao existe `.env` e `ROBLOX_API_KEY` nao esta no ambiente.
- Para qualquer chamada Roblox, confirmar alvo de teste e acesso necessario. Nunca publicar em producao como parte desta fila.
- Respeitar o sandbox e as aprovacoes do Codex. Nao usar `--dangerously-bypass-approvals-and-sandbox`.
- Marcar como bloqueada uma etapa que precise de Studio, credenciais ou acesso indisponivel; continuar as tarefas independentes. Nao registrar um playtest que nao aconteceu.

## 1. Restaurar a suite e produzir baseline atual

Estimativa: 30 a 60 minutos.

Instalar o Luau pinado usando o gerenciador existente, depois executar os testes. Investigar falhas reais antes de ampliar o escopo. Nao mudar as regras do jogo apenas para fazer os testes passarem.

Comandos de verificacao:

```powershell
python -B factory/tools/run_tests.py games/egg-champions
python -B factory/tools/validate_config.py games/egg-champions/config
python -B factory/tools/gate.py games/egg-champions spec_parsed
python -B factory/tools/gate.py games/egg-champions economy_tuned
python -B factory/tools/gate.py games/egg-champions planned
rojo build games/egg-champions -o games/egg-champions/build/game.rbxl
selene games/egg-champions/src
stylua --check games/egg-champions/src
```

Criterios de aceite:

- [x] Luau 0.742 disponivel e pin preservado.
- [x] Suite executada: 6 autotestes e 759/759 testes do jogo, codigo de saida 0.
- [x] Build, validacao, lint e formatacao passam apos a correcao.
- [x] `FACTORY-REPORT.md` registra os resultados atuais.

## 2. Migrar o executor da fabrica para Codex

Estimativa: 1 a 2 horas.

Concluido: `factory/tools/run_factory.py` usa Codex por padrao, interpreta
JSONL e preserva resposta final e trace. O caminho `--agent-cmd` serve a
fixtures. As instrucoes de papel continuam em `.claude/agents/`, carregadas
sem frontmatter pelo executor.

Inspecionar `codex exec --help` na maquina antes de escolher flags. O CLI instalado oferece `--sandbox workspace-write`, `--approve-for-me`, `--ephemeral`, `--json` e `--output-last-message`. Integrar a resposta real do Codex, em vez de esperar o formato do Claude. Se uma opcao antiga de custo nao tiver equivalente, rejeita-la com mensagem clara ou documentar a limitacao; nunca simular um custo medido.

Criterios de aceite:

- [x] Codex e o backend padrao e nenhuma execucao normal depende do executavel Claude.
- [x] Cada papel recebe suas instrucoes e uma tarefa delimitada.
- [x] Tratamento de sucesso, erro, timeout e encerramento da arvore de processos implementado; teste Windows matou processo pai e filho. Timeout real do Codex ainda nao foi provocado.
- [x] Saida final e trace JSONL do agente ficam salvos em relatorio.
- [x] Atribuicao de commits e documentacao correspondem ao executor Codex.
- [x] Chamada real do Codex em fixture isolada retornou `CODEX_FIXTURE_OK`.
- [x] Teste controlado provou retry, guard de caminhos e preflight sem publicar nem enviar commits.

## 3. Tornar o gate built e a execucao local confiaveis

Estimativa: 1 a 2 horas.

Incluir a suite Luau no gate built. Tornar a execucao local sem push o comportamento padrao, com uma opcao explicita para qualquer envio futuro. Revisar guardas e isolamento antes de rodar tarefas autonomas: a arvore principal contem arquivos importados nao rastreados e o codigo antigo pode executar reset. Nao descartar esses arquivos para satisfazer a exigencia de arvore limpa.

Criterios de aceite:

- [x] Gate built so passa com testes, Rojo, Selene e StyLua aprovados.
- [x] Falha deliberada de teste em fixture impede built e preserva o trabalho original.
- [x] Alteracao de um caminho proibido e rejeitada em fixture isolada.
- [x] Execucao padrao nao faz push nem aciona o workflow remoto.
- [x] Preflight recusa arquivos importados nao rastreados sem apaga-los; retry em fixture passou.
- [x] Limites de tarefas, tentativas e tempo estao no executor e no relatorio; teste Windows matou processo pai e filho; timeout de uma chamada real do Codex nao foi provocado.
- [x] `RUN-CODEX.md` documenta comandos locais reproduziveis.

## 4. Reconciliar estado e documentacao

Estimativa: 30 a 60 minutos.

Atualizar o fluxo operacional para Codex. Depois do gate completo aprovado, usar `factory/tools/state.py` para registrar built. Nao marcar worlds, playtested ou published_test como aprovados apenas porque tarefas de codigo estao done. A verificacao preservada dos 36 modelos comprova somente o snapshot que ela identifica.

Criterios de aceite:

- [x] README e `RUN-CODEX.md` descrevem iniciar, limitar, interromper e retomar.
- [x] Indice com 44 briefs, estado e relatorio refletem as verificacoes executadas.
- [x] Built foi registrado como passed via `state.py` depois do gate completo.
- [x] Etapas sem gate/evidencia completa permanecem pending, com motivo no relatorio.

## 5. Executar playtest local no Roblox Studio

Estimativa: 1 a 2 horas, quando Studio estiver acessivel.

Abrir o build local e testar sem publicar. Confirmar inicializacao do servidor e cliente e capturar erros de Output. Usar o modo de playtest existente quando apropriado, sem modificar progresso de jogadores reais. Os IDs atuais em `roblox.json` sao: TESTE universe `10769019206`, place `101737317546942`; producao universe `10769019314`, place `115689918132204`.

Criterios de aceite:

- [x] Servidor e cliente iniciam sem erros fatais apos corrigir `GetDataStore` local.
- [x] Click concede moedas e atualiza a interface.
- [x] Hatch, inventario e equipar tres pets funcionam no Studio local.
- [x] Tutorial oferece proximo passo e ponteiro funcional no fluxo inicial.
- [x] Gym1: entrada, batalha, derrota/retry e vitoria no LAUNCH-REPORT. Gyms2/3: entrada, normal/especial/recarga e vitoria com referencia no NIGHT-ACCEPTANCE.
- [x] Portais/progressao e UI desktop e iPhone XR emulado tem evidencias no LAUNCH-REPORT.
- [ ] Save/rejoin exige ambiente de TESTE publicado com DataStore; limitacao registrada.
- [x] Observacoes do Studio, Output, hash do build e bug corrigido constam no relatorio.
- [x] Nenhuma publicacao ocorreu para produzir o playtest local.
- [x] Sessao curta do inicio sem moedas/pets semeados: 50 cliques, primeiro hatch, equip e bonus real.
- [x] Clone local isolado do HEAD b9e6210, sem remotes, preflight aprovado e origem preservada.

## 6. Entregar relatorio e proximos passos

Estimativa: 30 minutos.

Relatorio complementar entregue em `games/egg-champions/NIGHT-ACCEPTANCE.md` com o estado final, mudancas feitas, comandos e resultados, caminhos do build e das evidencias, falhas restantes e proximas acoes do usuario. Informar o que foi apenas verificado localmente e o que foi realmente executado no Roblox Studio. Se a operacao depender de credenciais ou acesso que nao existem, informar exatamente qual capacidade falta, sem pedir ou expor o valor de uma chave no relatorio.

Criterios de aceite:

- [x] Relatorio descreve funcionamento comprovado e limitacoes concretas.
- [x] Lista curta de proximos passos do usuario, em ordem.
- [x] Git preservado, com 34 commits originais a frente de `origin/main`; sem push.
- [x] Fila atualizada com caixas marcadas apenas para verificacoes executadas.
- [x] Nenhuma afirmacao de publicacao, playtest completo ou custo sem evidencia.


## Conclusao local e pendencias

- [x] Inicio curto sem recursos semeados, com tempos e limites registrados.
- [x] Gyms2/3 com equipes de referencia, recompensas e UI verificadas.
- [x] Corrigido seguidor que permanecia bloco apos chegada tardia do asset;
  gate built reexecutado e caso visual confirmado no Studio.
- [x] RUN-CODEX inclui clone Windows do HEAD local e preflight reproduzivel;
  clone final inclui codigo b9e6210, sem remotes, sem executar a fabrica.
- [x] Relatorios atuais apontam 759 testes/44 tarefas; baseline antigo
  identificado como historico. Evidencias anteriores preservadas.

Proximas acoes dependem de ambiente externo: DataStore real/save/rejoin e
trava entre servidores, passes no TESTE, progressao longa com jogadores
novos, celular fisico/rede lenta/multiplayer e revisao/publicacao. As tarefas
locais acima nao precisam ser refeitas por Joao. Nenhum push foi realizado.
