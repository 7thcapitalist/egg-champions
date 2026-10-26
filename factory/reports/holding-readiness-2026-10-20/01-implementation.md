# Holding e fabrica: implementacao revisada

2026-10-20. Nova prioridade do Joao: construir uma fabrica confiavel antes de
acelerar conteudo. Nenhuma geracao real, compra ou publicacao nesta rodada.

## Paperclip atualizado

Acesso localhost:3100 autorizado pelo mecanismo de permissoes, sem credencial
ou configuracao global. Foram atualizadas as doze tarefas Roblox com evidencias
locais, mantendo o texto anterior e acrescentando secao datada. Nao foram enviados
prompts para outros chats, criados agentes ou executadas tarefas.

ROB-1/2 continuam done no seu escopo anterior. ROB-3/4/5/7/8/9/10 ficaram blocked;
ROB-6/11/12 ficam in_review, com pendencias explicitas. ROB-12 voltou a revisao
porque data/roblox.json nao foi atualizado aqui. Snapshots tasks-before/after.json
preservam o conteudo e os estados observados. Nao houve nova aprovacao de beta.

Depois das nossas escritas, outro ator/processo alterou estados as 22:25 UTC:
ROB-4/7/8/9/10 voltaram a todo e ROB-11 passou a done. A autoria nao foi
identificada e nao se presume que tenha sido o Dot. As notas de evidencia foram
preservadas; nao sobrescrevemos as alteracoes concorrentes. Snapshot
paperclip-final.json registra a divergencia. ROB-11 done no board nao certifica
capturas/revisao visual ausentes: os gates locais continuam bloqueados.

Criada ROB-13, prioridade high, blocked, sem agente atribuido, para concluir a
integracao da holding ao executor protegido. As descricoes incluem caminhos
locais; isso nao significa que alteracoes nao commitadas ja chegaram ao remoto.

Os quatro agentes Roblox estavam idle e foram pausados antes das atualizacoes.
Motivo: adapters Claude/Codex diretos, fora da guarda do executor, diretor com
heartbeat habilitado a cada duas horas e maxConcurrentRuns configurado em20.
A empresa continua active, mas seus quatro agentes foram confirmados paused.
Outras empresas e o trabalho do Dot nao foram alterados.

## Guarda da holding corrigida e instalada

Originais preservados em before/. Fontes versionadas em factory/holding/;
deployment-installed.json vincula os arquivos finais instalados a seus hashes.
Foi concedida escrita especifica somente em HQ/scripts/guard.mjs e quota.mjs.

UNKNOWN antes devolvia exit0; agora somente OK devolve0. STOP/UNKNOWN devolvem3.
Metrica ausente, antiga (>300s), futura, percentual invalido, reset desconhecido
ou estado de creditos Codex diferente de false bloqueiam. Codigo invalido ou
falha de arquivo tambem e nao zero; consumidores nao devem tratar isso como OK.

Janela curta Codex nao substitui a semanal; usa a amostra com timestamp mais
recente entre os arquivos examinados. Claude nao usa mtime como medida nem
escolhe uma conta arbitraria quando ha mais de uma valida. O guard pode checar
apenas o provedor solicitado; a ponte exige provider_scope=[codex], recusando
o contrato legado e sem fallback para Claude.

Tambem bloqueia janela de cinco horas explicitamente esgotada. O coletor Codex
agora preserva esse percentual quando informado; ausencia permanece null.
Janela curta desconhecida nao vira zero e nao oferece garantia de disponibilidade.

Ledger semanal ausente/vazio, incompleto, corrompido, duplicado, regressivo ou
atravessando reset sem medicao reconhecida bloqueia, mantendo consumo null.
Sem arredondamento para baixo na comparacao ao teto. budget.json, ledger de
quota e limites de assinatura nao foram alterados. Nao foi criado baseline zero.

## Ponte protegida preparada

holding_worker.py tem inspecao por padrao. --execute e opt-in independente.
Exige worktree hq/ limpa dentro da raiz declarada, mesma pasta Git comum do
repositorio canonico, primeiro trabalho da etapa built, ID/dependencias corretos,
politica autorizada, ledger integro/sem lock e admissao da holding.

Clones independentes sao recusados para nao reiniciar tentativas. Nenhuma copia,
worktree ou branch foi criada e nenhum arquivo do usuario foi limpo/stashed.
O teste real de inspecao recusou corretamente esta pasta ativa do Joao.

Execucao futura toma lock unico da holding, confere admissao, registra quota
antes/depois e delega no maximo uma tarefa ao run_factory existente, com duas
tentativas. Medicao final e tentada mesmo em falha. O executor continua dono de
modelo/esforco, prazo, exclusao Git e ledger de uso; seus fontes/configuracao
nao foram alterados. Nao ha autorizacao automatica, desbloqueio ou publicacao.

Nenhum adapter foi substituido/retomado. O novo caminho foi testado com mocks;
os adapters diretos precisam continuar pausados ate integracao revisada em uma
worktree com codigo entregue e orcamento valido. A ponte cobre built, nao todo
o manager, planejamento, arte ou playtest publicado autonomos.

## Situacao real e limites

guard check roblox codex retorna UNKNOWN/exit3: ledger semanal ausente.
executor.json segue paused=true, authorized_calls=0, authorized_tokens=0. A fala
do usuario permite usar a fabrica, mas nao substitui uma medicao ausente por zero
nem fornece limites numericos diferentes dos preservados no arquivo.

Para iniciar trabalho real falta conciliar/autorizar contabilizacao inicial da
holding, dispor de medicao fresca, integrar adapter/worktree e registrar limites
de chamadas/tokens autorizados junto ao responsavel pela integracao do Dot.
Sem inventar consumo historico, apagar ledger/locks ou trocar runtime.

Quota por assinatura nao equivale a preco de API. Nao calculamos dolares. O
ledger existente registra tokens informados, cache como subconjunto de entrada,
modelo efetivo somente quando informado, duracao e tentativas. Nada foi inferido
de modelos que nao foram chamados. Snapshot de porcentagem nao reserva quota
contra outros chats. Uma chamada admitida pode ultrapassar limiar antes de
reportar tokens; retries internos/requisicoes do provedor podem nao ser expostos.
Locks e hashes locais nao sao barreira contra adulteracao deliberada ou adapters
que nao usem a ponte. Os agentes diretos estao pausados, nao tecnicamente governados
por esse wrapper. Nao foi declarada uma garantia inexistente de custo maximo.

O jogo mantem as pendencias anteriores: visual, DataStore real, compras, celular
fisico/rede lenta, desconexao/reentrada e progressao natural. Os testes locais
nao substituem essas observacoes. Sem publicacao nesta sessao.
