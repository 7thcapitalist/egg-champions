# Revisao do lancamento e integracao com a holding

2026-10-20. Jogo ainda bloqueado para lancamento. Fabrica pausada; nenhuma
publicacao, compra, geracao real de IA, despacho de agente ou mudanca do Dot.

## O que foi verificado e corrigido nesta rodada

O Git local ja tem bedc503, merge do PR #1 em codex/task-50-wip. O STATE da
holding ainda dizia que esse merge faltava e continha instrucoes antigas para
despausar. Foi adicionada uma reconciliacao datada, preservando o historico,
e LOCAL-RELEASE.md com ordem de trabalho, limites e comando de status sem IA.
Somente esses dois documentos foram alterados no HQ, com acesso de escrita
especifico concedido. Orcamento, Paperclip, agentes e infraestrutura intactos.

Foi implementado gate deterministico para worlds/playtested/published_test,
vinculado a fontes/config/tuning/build e hashes locais das evidencias. Acrescentada
exigencia de rede lenta em aparelho fisico: ela constava no GOAL da holding,
mas ainda nao estava representada no novo gate. Ausencia, alteracao, build
divergente, perfil temporario, resultado unknown ou compra nao observada bloqueiam.

O CLI release_readiness.py emite JSON e exit 1 enquanto bloqueado. Nao chama
modelo, Studio, build, publicacao ou executor. O resultado cobre evidencias
de lancamento; nao aprova por si so a economia, tarefas ou publicacao.
Manifesto real criado com referencias null, sem transformar testes em evidencia.
Schemas e procedimento: release/README.md e os validadores em factory/tools/.

## Multiplayer observado

Foi aberta uma sessao separada, local e nao publicada do Studio com o build QA.
As sessoes anteriores e seu trabalho nao salvo foram preservados. Dois clientes
reais executaram requests por InvokeServer atraves de drivers exclusivos de QA.

Tentativa 1: foreign-pet encontrou in_battle porque a fixture tentava equipar
durante batalha. A ordem da fixture foi corrigida para testar posse antes do
inicio da batalha. Nenhuma guarda do jogo foi relaxada para fazer o teste passar.

Tentativa 2 passou nove casos: profile-isolation, fee-once, duplicate-start,
foreign-pet, parallel-battles, remote-transport, foreign-session,
retry-isolation, rate-limit-isolation. Desconexao/reentrada permanece unknown.
Os resultados retornados por StudioTestService estao em multiplayer-attempt-1.json
e multiplayer-attempt-2.json, incluindo a primeira falha, sem ocultar a revisao.

As fixtures exigiram PlaceId 0, passes desligados, perfis novos e temporarios.
O hash informado identifica o candidato normal; nao e o hash do binario QA
modificado em memoria. Completion/EndTest e watchdog de 120 segundos foram
adicionados somente na sessao QA. Um novo build reproduz a fixture corrigida
em build/launch-review-2026-10-20/beta-local.rbxl; esse build nao foi publicado.

## Mobile observado

Na mesma sessao QA, solo, solicitado retrato 320x720, viewport efetivo 320x624,
inset superior 58. A orientacao Sensor foi usada somente nessa sessao.
Foi observado o prompt do gym 3, taxa ja paga, e batalha com equipe de referencia
e cinco rebirths semeados exclusivamente em perfil temporario. Um ataque real
passou ao turno 2: lider 1059 -> 690 HP, jogador 1707 -> 1280 HP. Nomes e HP
informaram TextFits=true; botoes de golpes mediram 144x58, Give Up 296x44.

Capturas foram exibidas na conversa. Arquivos de imagem nao foram arquivados
nesta rodada. A legenda secundaria de golpe truncou no retrato pequeno e
algumas linhas longas do log informaram TextFits=false apesar de AutoSize e
wrap; isso exige revisao visual adicional, nao uma aprovacao automatica.
Nao foi repetida a matriz completa, cura, resize, toque fisico ou rede lenta.
Este teste semeado nao prova progressao natural nem save publicado.

Somente a sessao QA foi parada; orientacao LandscapeSensor do StarterGui foi
restaurada e Device Simulator desligado. Arquivo de shipping nao foi salvo
pelo Studio, nenhuma outra sessao foi parada/fechada. Recovery e build/game.rbxl
nao foram sobrescritos.

## Resultados

- 86 testes Python passaram, incluindo nove testes sinteticos do novo gate.
- 882 testes Luau e seis autotestes do runner passaram.
- Selene: zero erros, avisos e erros de parse. StyLua --check passou.
- Rojo construiu novo QA isolado, sem sobrescrever diretorios anteriores.
- Gates reais worlds/playtested/published_test: bloqueados, referencias ausentes.
- Economia canonica anterior: seis metas passaram, gym 3 mediano em cinco
  rebirths, final em 6.83h. Seed 2 gym 2 em tres vs meta dois continua risco.

Uma invocacao inicial de run_tests com opcao --self-test nao suportada apenas
mostrou uso; foi corrigida para o comando real, que ja roda os seis autotestes.
Mensagens de falha/commit no stdout da suite Python pertencem a fixtures de
teste em diretorios temporarios; nao representam execucao real ou commit daqui.

## O que falta para o jogo ser aprovado

1. Composicao e animacao >=4 com imagens vinculadas e revisao atual. Os novos
   testes nao aumentam notas. Legibilidade do log pequeno ainda requer revisao.
2. Completar matriz mobile, toque fisico, rede lenta e desconexao/reentrada.
3. Save/rejoin com DataStore real na mesma versao TEST e evidencia de release.
4. Compras reais e efeitos de todos os passes no TEST, com autorizacao propria.
5. Jogar gyms 2/3 naturalmente, sem equipe semeada/pass, e registrar sensibilidade.
6. Confirmar fontes reabertas da versao TEST revisada; completar tarefas 50/51/52,
   vincular manifestos e obter aprovacao dos gates. Publicar exige nova autorizacao.

As etapas externas nao foram executadas: a proibicao de publicar permanece.
Nenhum status de etapa foi promovido nesta rodada. Hashes verificam integridade
e consistencia; nao provam a honestidade de uma observacao humana nem desempenho
em todo telefone/rede. O CLI nao e um bloqueio na plataforma Roblox.

## Limite da holding

A leitura de localhost:3100 foi negada pela permissao de rede desta sessao.
Nao houve repeticao por outra interface ou tentativa de contorno. Estado global
dos agentes Paperclip permanece desconhecido. executor.json local segue
paused=true, authorized_calls=0, authorized_tokens=0. Nenhum controle do Dot,
ledger, credencial, cobranca, configuracao global ou permissao de conta mudou.
