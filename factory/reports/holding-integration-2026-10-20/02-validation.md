# Validacao da integracao

Data do usuario: 2026-10-20. Nada publicado, nenhum modelo real chamado.

## Evidencia executada

- Suite completa:124 testes Python passaram, tests-final.txt. A execucao anterior
  com123 testes esta preservada em tests.txt.
- Apos o ultimo tratamento de erro de instalacao,39 testes focados holding*
  passaram. Eles incluem38 casos anteriores e um caso de PermissionError:
  resposta JSON bloqueada, uma tentativa e nenhuma pasta/ledger alternativos.
- Node syntax checks e checks de diff sem erros, registrados em checks.json.
- Probes locais dos quatro perfis foram executadas por script, sem iniciar
  agentes no Paperclip: diretor checked, analista checked, pesquisa checked,
  engenheiro blocked. Todos model_calls_requested=0. local-script-checks.json
  separa esses probes de um teste real do runtime Paperclip ou de geracao.
- agents-configured.json confirma os quatro adapters process, todos paused,
  heartbeat desabilitado e concorrencia1. Nenhuma invocacao heartbeat/resume foi
  solicitada apos o bloqueio de filesystem.

## Cobertura deterministica

Fixtures temporarias cobrem baseline autorizado, historico null, delta da
janela, limite1p.p., ancora alterada, provedor errado, ledger incompleto,
regressao/reset, atualizacao de medida sem reescrever a autorizacao, reserva,
creditos e quota desconhecida/antiga. Baseline existente nunca e sobrescrito.

Mocks cobrem fila/atribuicao do proprio agente, proxima tarefa, tarefa running
duplicada, lock, clone independente, politica ausente sem fallback, limites de
chamadas/tokens, contrato antigo da guarda, timeout e encerramento da arvore,
ausencia de chaves no filho, preservacao de trabalho parcial e registro final.
O dispatcher de geracao e mocked; nenhum teste chama codex exec real.

Todos os arquivos de policy/ledger usados nos testes de autorizacao ficam em
fixtures temporarias. Testes nao sobrescreveram o executor ou politica reais.
Mensagens de coder/commit no stdout sao fixtures, nao execucao de producao.

## Negativas observadas

Git: falha ao criar refs/heads/hq/roblox-protected. Verificacao read-only nao
encontrou branch nova ou worktree criada; nao houve nova tentativa.

Instalacao: PermissionError WinError5 em HQ/runtime. O erro ocorreu antes das
aberturas exclusivas do ledger/policy. filesystem-blocks.json registra que
runtime, quota.jsonl, executor-runtime.json e worktree nao existem.
Nao foi usado caminho alternativo nem relaxada a guarda para fabricar OK.

O guard real portanto continua sem admissao valida, porque o baseline aprovado
nao pode ser instalado nesta permissao efetiva. A aprovacao de orçamento esta
registrada como intencao, nao como saldo gasto zero nem autorizacao ativa.

## Nao validado

Nao houve geracao real, runtime Paperclip retomado, teste completo de escrita
em worktree ou nova publicacao. O modelo efetivo e os tokens de uma chamada
que nao ocorreu nao foram inventados. A politica legada/Dot e o jogo foram
preservados. A aprovacao de beta e lancamento continua pendente.

## Mudancas concorrentes no jogo

Durante a auditoria final, o hash do jogo divergiu do launch-readiness anterior:
Battle.luau passou a ter diff e surgiram marketing/, launch-package-2026-10-20/
e tarefa53-launch-presentation.md. Esta integracao nao escreveu nesses caminhos;
as alteracoes foram preservadas, sem atribuir autoria ao Dot ou a outro agente.
O checks.json registra os hashes anterior/atual e os gates ainda bloqueados.
Nao atualizamos o manifesto para fingir evidencia atual nem declaramos os
fontes concorrentes aprovados pelos testes visuais/gameplay anteriores.
