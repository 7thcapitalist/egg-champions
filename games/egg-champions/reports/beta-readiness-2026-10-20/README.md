# Economia do terceiro ginasio e preparacao da beta

Revisao local de 2026-10-20. Sem publicacao, fabrica, IA externa, compras ou
alteracao do executor que o Dot esta tratando. Nenhuma sessao do Studio foi
aberta, parada, fechada ou modificada nesta rodada. Trabalho nao salvo preservado.
Este relatorio atualiza a pendencia economica do relatorio da tarefa 50; nao
reescreve suas evidencias historicas nem aprova seus itens visuais pendentes.

## Correcao aplicada

Foi adicionado Cohort power na tabela de mundos da spec: 100%, 100%, 80%.
O parser gera cohort_power_factor; o validator e o tuner rejeitam valores
invalidos, inclusive bool, zero, negativo, NaN e infinito. Specs antigas sem
a coluna usam fator 1. O jogo continua lendo os lideres gerados pelo tuner.

O tuner calcula primeiro a potencia de referencia, depois aplica o fator
explicito antes de gerar HP/Attack. Report e JSON mostram potencia de referencia,
fator e resultado. Os 80% de vitoria continuam sendo a calibracao da potencia
de referencia; a taxa medida contra o lider ajustado e informada separadamente.
Nao se afirma que o lider final mantem exatamente 80% de vitoria de referencia.

Terceiro lider: potencia 1.324 -> 1.059, HP 1324 -> 1059, ataque 265 -> 212.
Os lideres dos mundos 1 e 2 mantiveram seus atributos. Precos, taxas, chances
de hatch, pets, multiplicadores do jogador, metas e formato dos saves nao mudaram.
Experimentos com precos e atributos de pets nao foram aplicados.

| Meta canonica, 4 cliques/s | Antes | Depois | Meta mantida |
| --- | --- | --- | --- |
| Primeiro hatch | 16 s | 16 s | ate 60 s |
| Primeiro ginasio | 25.7 min | 25.4 min | 20-30 min |
| Ultimo ginasio | 7.70 h | 6.83 h | 6-8 h |
| Renascimentos, ginasio 1 | 0 | 0 | 0 |
| Renascimentos, ginasio 2 | 2 | 2 | 2 |
| Renascimentos, ginasio 3 | 7 | 5 | 5 |

Simulacao canonica: seed 1, 300 jogadores por taxa, 2/4/8 cliques/s, limite
40 horas. Gate economy_tuned passou nas seis metas; spec_parsed tambem passou.
O state foi atualizado pelo state.py, sem iniciar orquestracao. Nenhuma etapa
de playtest, publicacao ou beta foi marcada como aprovada.

## Sensibilidade e limites economicos

Nas seeds extras 2 e 3, tambem com 300 jogadores por taxa, o terceiro ginasio
ficou em cinco renascimentos. Conclusao em 6.52 h e 6.83 h, respectivamente.
Seed 2 deu tres renascimentos no segundo ginasio, acima da meta de dois;
seed 3 passou todas as metas. Portanto, nao ha garantia de todas as metas
em toda amostra. Ver economy-sensitivity.json.

O simulador usa um RNG compartilhado por taxa: alterar o fim da progressao
muda os sorteios dos jogadores seguintes. Na seed 2, a amostra anterior dava
dois renascimentos no segundo ginasio. Os atributos desse lider nao mudaram;
a comparacao nao e pareada por jogador e nao prova regressao mecanica ali.
Isso exige observacao de progressao real, sem mascarar a sensibilidade.
A referencia ainda tem a limitacao de nao possuir Rare de agua nesse mundo.

## Saves

Profiles agora informa persistenceMode, apenas no servidor, sem mudar saves.
Um registro opt-in de resultado pode ser habilitado por atributos de QA;
esta desativado por padrao. Registra persistencia, sucesso e liberacao de lock
com alias e versao/hash. Temporario nunca informa sucesso persistente. Falha
na serializacao dessa evidencia nao impede salvar/liberar a sessao.

Cinco testes executam os fontes reais Profiles/SaveOrder no interpretador
Luau com DataStore em memoria e servicos simulados. Cobrimos save/rejoin,
isolamento entre jogadores, deadline definido antes do save, perfil temporario,
falha de escrita, lock estrangeiro e logging opcional. O helper de schema e
simulado nesse harness; migracao/validacao do Profile tem a suite compartilhada.
Nao sao chamadas ao DataStore da Roblox nem prova de persistencia publicada.

beta_snapshot.server.luau prepara captura somente leitura. beta_checks.py
compara todos os campos do schema v5, preservando ordem da equipe e identidade
dos pets/variantes; playSeconds deve ser monotono. Exige mesma versao/hash,
alias, sessoes diferentes, DataStore real e arquivo de evento de liberacao
vinculado por SHA-256. Valores ausentes ficam desconhecidos e bloqueiam.

## Mobile e multiplayer

Matriz preparada: desktop 1280x720, retrato 320x720 e 390x844, paisagem curta
568x239 e telefone fisico. Solicitado e efetivo ficam separados. Cobertura inclui
hatch, equip, alvo de Journey, ataque, cura, resize, texto e controles. O
recorder mobile e somente leitura e fica desativado ate configuracao explicita.
Metricas e hashes nao substituem revisao visual nem toque real.

O novo build QA tem drivers cliente/servidor exclusivos para duas sessoes
locais, com InvokeServer real: isolamento, taxa cobrada uma vez, batalhas
paralelas, inicio duplicado, sessao/pet alheio, retry e rate limit por jogador.
Recusa perfil persistente ou progresso existente antes de semear a fixture.
Tem espera maxima por clientes e timeout por comando. InvokeClient pendente
nao pode ser cancelado por esse driver; depois de timeout ele bloqueia novos
comandos, e Stop limpa a sessao. Desconexao/rejoin continua um caso separado.

Os drivers ainda nao foram executados no motor nesta rodada. Save real,
multiplayer observado e toque fisico continuam pendentes. Os tres validadores
retornam blocked nas evidencias preparadas: pending-validation.json. Os
templates possuem valores unknown/null, sem transformar mocks em aprovacao.

## Arquivos entregues e verificacoes

- Build normal, sem fixtures: build/beta-candidate-2026-10-20.rbxl.
- Build QA isolado: build/beta-review-2026-10-20/beta-local.rbxl.
- Roteiro e comandos: factory/BETA-QA.md.
- Testes: test_cohort_tuning.py, test_beta_checks.py, test_profiles_runtime.py.
- 882 testes Luau, seis autotestes e 77 testes Python passaram.
- Selene zero erros/avisos; StyLua, Rojo e gate planned passaram.
- Checks e hashes dos arquivos: checks.json.

O build normal tambem nao foi aberto/revalidado no Studio nesta rodada.
O diretorio build/beta-2026-10-20 e um prototipo anterior, nao a entrega final.
As tarefas 50/51/52 continuam com pendencias de revisao. Beta ainda nao esta
aprovada; publicacao e retomada da fabrica seguem fora do escopo. Controles,
ledger, credenciais, permissoes e configuracoes globais nao foram alterados.
