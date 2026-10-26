# Integracao dos agentes e janela autorizada

Data do usuario: 2026-10-20, America/New_York. Os timestamps UTC de execucao
podem estar em 2026-10-21. Nao houve publicacao, compra ou geracao real de IA.

## Implementado

Os quatro agentes Roblox foram alterados, ainda pausados, de claude_local /
codex_local para process. Comando Python e argumentos fixos apontam para
factory/tools/paperclip_agent.py nesta copia. Heartbeat desabilitado e
maxConcurrentRuns=1. Nenhuma outra empresa ou permissao de agente foi alterada.
Snapshots sem segredos: agents-before.json e agents-configured.json.

Diretor verifica gates, setup e admissao; analista verifica a economia; pesquisa
valida as evidencias existentes, sem inventar tendencias atuais. Sao scripts,
sem modelo. Engenheiro so pode delegar a fila ROB-5 atribuida ao proprio agente,
em todo/in_progress, com proxima tarefa pending e dependencias satisfeitas.
Uma tarefa running/blocked impede geracao duplicada. A tarefa50 running atual
nao foi alterada. Testes externos do jogo nao viram tarefas de IA automaticamente.

O engenheiro chama exclusivamente holding_worker.py. Exige worktree limpa hq/,
mesmo Git common dir e ledger persistente, tarefa correta, exclusao global e
admissao. Nao ha fallback de modelo/runtime/clone nem para a politica antiga.
O timeout externo encerra a arvore do worker, sem retry automatico. O filho de
modelo nao recebe bearer Paperclip, ROBLOX_API_KEY ou chaves de API paga.

ProtectedRun reutiliza o executor existente e seus controles de tentativas,
timeouts, contexto e uso. Le a politica central da holding e quota fresca antes
de chamadas. Recusa rollback destrutivo e commits inesperados, preservando
trabalho parcial. Instrucoes proibem Studio, publicacao, upload, compras,
credenciais e chamadas aninhadas de IA. O executor/config do Dot nao mudou.

## Autorizacao recebida

O usuario escolheu explicitamente uma janela pequena daqui para frente:
ate2 chamadas, 20.000 tokens informados e 1 ponto percentual de quota,
preservando15% da assinatura. Historico anterior continua desconhecido.
authorization-intent.json registra a escolha, com installed=false.

holding_authorization.py implementa a instalacao inicial explicita. Cria baseline
com used_pct atual, historical_usage_pct=null, reset/provedor e limites; vincula
seu SHA-256 a studios/roblox/executor-runtime.json. Recusa arquivos existentes,
quota ausente/antiga, creditos pagos, falta de reserva e modelo diferente do
central economico. Nao renova/resetta a janela automaticamente.

guard.mjs instalado no HQ suporta esse contrato, preservando o protocolo antigo.
Mostra consumo historico desconhecido e consumo da janela em campos diferentes.
Cobra conservadoramente toda diferenca da quota global desde o baseline,
incluindo outros chats, e bloqueia a1 p.p. ou na reserva. Token/cache/modelo
efetivo continuam no ledger do executor: cache nao e acrescido de novo, dados
nao informados permanecem desconhecidos e nao se estimam dolares de assinatura.

## Bloqueio real de instalacao

A criacao da worktree hq/roblox-protected falhou ao criar a referencia Git.
Nao havia colisao de branch hq/ e nenhuma nova worktree foi registrada.
Nao repetimos o comando nem usamos outro clone, pasta ou executor.

A tentativa unica de instalar o baseline parou antes de escrever o ledger:
Windows retornou WinError5, Access is denied, em
C:/Users/joaov/dev/holding-hq/runtime. A permissao de pasta havia sido concedida
pelo cliente, mas nao resultou em escrita efetiva para criar o diretorio.
Nao houve rejeicao explicita de auto-review: o erro observado veio do terminal/FS.

Os quatro caminhos foram verificados como ausentes: runtime, quota.jsonl,
executor-runtime.json e worktree. Nao ha instalacao parcial a declarar como
sucesso. Nao tentamos outro caminho ou nova autorizacao para repetir a escrita.
Os agentes permaneceram pausados. A politica legada segue paused=true e
authorized_calls=authorized_tokens=0; a nova autorizacao nao foi aplicada.

Falta uma aprovacao efetiva de terminal para essas mesmas operacoes antes de
retomar a instalacao. O codigo esta concreto e testado; nao se declara a fabrica
ativa ou a geracao end-to-end funcionando enquanto esse bloqueio existir.

## Limites

Dois lancamentos totais por tarefa no ledger Git, prazo compartilhado e dados
de uso informados sao controles do executor. Retries internos do provedor e
metricas nao expostas pelo CLI nao podem ser garantidos pelo wrapper. Tokens
e porcentagem sao limiares de admissao; uma chamada pode exceder o limiar antes
de reportar uso. A janela nao reserva quota contra outras conversas.

Hashes/policies locais nao sao assinaturas ou barreira contra adulteracao
deliberada. Proibicoes de publicacao na orquestracao/prompt nao sao um bloqueio
na plataforma Roblox. Nenhuma acao de publicacao foi executada nesta rodada.
O jogo ainda exige QA real de saves, compras, celular/rede lenta, visual e
progressao natural. Esses testes nao sao substituidos por mocks.
