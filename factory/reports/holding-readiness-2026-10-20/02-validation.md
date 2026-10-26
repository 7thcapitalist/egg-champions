# Holding e fabrica: validacao e limites

2026-10-20. Somente scripts, fixtures temporarias e mocks. Nenhuma chamada
real de modelo, publicacao, compra, checkout ou alteracao de credencial.

## Checagens executadas

- test_holding_guard.py: onze testes iniciais e um caso adicional de janela
  curta esgotada, total doze. Fixtures instalam os fontes em pastas temporarias,
  com budget, quota, ledger e relogio controlados. Homes/dirs de quota reais nao
  sao usados nesses testes. Testa medicao ausente/antiga/futura, creditos,
  limites, ledger vazio/ausente/corrompido/duplicado/incompleto, regressao/reset,
  percentual sem arredondar, janela semanal explicita, escolha de provedor,
  ambiguidade de conta Claude e timestamp ausente.
- test_holding_worker.py: onze testes; dispatch da fabrica sempre mocked.
  Cobre somente inspecao, isolamento/pasta ativa/branch/dirty, politica pausada,
  autorizacao zero, quota antiga, ID incorreto, clone independente, lock global,
  lock de executor preexistente, tentativas persistentes com o mesmo label real,
  UNKNOWN/contrato legado da guarda e registro final mesmo apos falha.
- Suite completa da fabrica: saida preservada em tests-final-109.txt; resumo
  verificavel e hashes em checks.json. A suite anterior de108 testes esta
  preservada em tests-final.txt, nao sobrescrita. Depois do ultimo ajuste,
  os23 testes focados tambem passaram antes da instalacao final.
- node --check passou em ambos os scripts da holding.
- git diff confirmou nenhuma mudanca em executor.json, executor_policy.py ou
  run_factory.py; os controles/integracao do Dot foram preservados.
- O jogo nao recebeu mudancas de fonte nesta rodada. Os882 testes Luau e seis
  autotestes, lint/formatacao e builds anteriores constam no relatorio de
  launch-readiness-2026-10-20. Nao declaramos repeticao desses testes nesta rodada.

Mensagens de coder start/commit/failed e arquivos temporarios no log da suite
sao fixtures de testes, nao despacho real da fabrica. Os arquivos reais do
executor e suas autorizacoes nao foram sobrescritos durante os testes.

## Observacoes reais separadas dos mocks

O guard instalado recebeu uma consulta read-only check roblox codex e respondeu
UNKNOWN/exit3: ledger semanal ausente. Percentual desconhecido ficou null, nao
zero; nao foi criado arquivo quota.jsonl ou atribuido consumo historico.
live-admission-final.json preserva o resultado real, distinto da fixture OK.
O coletor le logs locais de uso e emite somente metadados de quota; nao chama IA.

A inspecao real da ponte recusou esta pasta ativa por estar fora da raiz das
worktrees do manager. Nenhuma execucao --execute ocorreu fora das fixtures.
Os snapshots de Paperclip provam as atualizacoes e os quatro agentes paused.
Nao provam pausa das outras empresas ou ausencia de processos externos.

Houve mudancas concorrentes no board depois de nossas escritas: ROB-11 done e
ROB-4/7/8/9/10 todo. Nao sobrescrevemos. Autoria desconhecida; nao atribuimos ao
Dot. O teste local de release continua bloqueado independentemente desse done.

## O que estes testes nao garantem

A admissao e conservadora e pode bloquear a fabrica ate existir contabilizacao
e autorizacao valida; esse e o estado real atual. Ela nao fornece uma quota
reservada, limite financeiro de API ou teto rigido de tokens durante a resposta.
Cache nao e somado duas vezes; a ponte nao inventa metricas que o executor nao
recebeu. Limites de duas tentativas se referem a lancamentos do executor no
mesmo ledger Git, nao retries internos desconhecidos do provedor.

O lock da holding coordena quem usa esta ponte. Adapters diretos e outros chats
nao passam por ela; os quatro agentes Roblox diretos permanecem pausados.
Hashes, policies e ledgers locais nao sao assinados nem impedem adulteracao
deliberada. Nao foi demonstrada geracao end-to-end real nem liberacao automatica
de arte/planner/playtester. A ponte atual atende uma tarefa da etapa built.

Publicacao, DataStore persistente, compras, telefone/rede lenta, revisao visual
e progressao natural continuam exigindo evidencias proprias. Os mocks nao as
substituem. Nenhum gate ou etapa do jogo foi promovido nesta rodada.
