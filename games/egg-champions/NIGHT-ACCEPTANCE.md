# Egg Champions: aceitacao local complementar

Data: 2026-10-16. Continuacao da entrega de qualidade do commit 14759c3.
Sem push, publicacao, compras reais ou alteracao de jogadores persistentes.
Evidencias em [night-acceptance-2026-10-16](reports/night-acceptance-2026-10-16).

## Estado atual

759/759 testes do jogo e 6 autotestes do runner; 44 tarefas done.
Apos a correcao dos seguidores descrita abaixo, o gate built passou novamente
com run_tests, Rojo, Selene e StyLua. Nao foi acrescentado teste que apenas
espelhasse a implementacao; o problema de replicacao foi reinspecionado no
Studio. [Resultado do gate](reports/night-acceptance-2026-10-16/built-after-followers.txt).
Built foi registrado novamente por state.py. Worlds, playtested e
published_test permanecem pending: nao existem gates completos para eles.

A migracao inicial (738 testes/43 tarefas) permanece como historico em
[FACTORY-REPORT](../../FACTORY-REPORT.md). A entrega principal e suas
imagens estao em [LAUNCH-REPORT](LAUNCH-REPORT.md).

## Inicio sem recursos semeados

Foi aberto beginner-acceptance.rbxl local, com perfil temporario. A fixture
beginner nao escreve moedas, pets, rebirths ou progresso de tutorial.
O Output confirmou coins=0 pets=0 rebirths=0. Nao houve moedas por console,
colecao semeada, passes ou Auto Hatch nessa sessao.

1. Tutorial iniciou com clique, saldo zero e meta de 50 moedas.
2. Foram emitidos 50 cliques normais de interface (lotes de 10 e 40 via
   click_count da automacao). O handler real concedeu exatamente 50 moedas
   a +1 por clique. O tutorial destacou EGGS e depois HATCH.
3. Comprar Meadow Egg debitou 50 para zero e executou a revelacao. A imagem
   intermediaria da animacao nao foi capturada nesta sessao.
4. Inventario mostrou um Puddlet Uncommon, Click Power 3, equipe 0/3 e
   Index 1/30. EQUIP mudou para 1/3 e HUD +4 por clique.
5. Fechar mostrou o seguidor e a proxima meta Hatch 2 more pets. Mais 13
   cliques normais produziram 52 moedas. A sessao foi encerrada nesse ponto.

Evidencias: [zero](reports/night-acceptance-2026-10-16/beginner-zero.png),
[50 moedas](reports/night-acceptance-2026-10-16/beginner-first-egg-ready.png),
[primeiro pet](reports/night-acceptance-2026-10-16/beginner-first-pet.png),
[equipado](reports/night-acceptance-2026-10-16/beginner-equipped.png),
[bonus](reports/night-acceptance-2026-10-16/beginner-normal-bonus.png) e
[Output](reports/night-acceptance-2026-10-16/beginner-output.txt).

Tempos observados pelo relogio da automacao: primeira captura carregada a
27,2 s depois de Play; saldo 50 observado a 24,7 s depois do primeiro lote
de cliques (71,8 s depois de Play); pedido do primeiro hatch aceito a
106,3 s depois de Play e 59,2 s depois do primeiro lote. Esses intervalos
incluem pausas de ferramentas, captura e leitura. Nao medem o tempo puro de
clique nem aprovam a meta de primeiro hatch em um minuto para jogadores
novos. Nao foi jogada progressao longa, primeiro gym natural ou rebirth
natural. O fluxo inicial curto funcionou, com essa limitacao explicita.

## Gyms com equipes de referencia

Os cenarios gym2 e gym3 semeiam os tres pets da equipe de referencia do
tuning em variante golden, target_rebirths + 1, duas vezes a taxa de entrada
e badges/gyms anteriores concluidos. Sao cenarios de integracao, nao
prova de balanceamento ou obtencao natural dessa equipe. A fixture mantem
um tutorial parcial; SKIP foi usado para exibir o objetivo do gym atual.
O personagem nasce em Meadow; o botao TO THE GYM abre o prompt real do gym
desbloqueado. A travessia fisica dos portais foi testada na entrega anterior.

### Gym 2: Coral Coast

Perfil observado: 10M, 3 rebirths, golden Bananao, Zapeel e Sparkit.
Prompt informou Water, counter Electric, taxa 5M e regras de retry.
Ataques reais: normal, especial Smash, dois turnos de recarga e novos
ataques normais/especial. Bubblecrab, Pearlotter e Tidewhale apareceram como
oponentes com seus modelos. A luta terminou em sete acoes do jogador,
com Bananao ainda ativo (285/849 HP). VICTORY informou badge de Coral Coast
e Ember Volcano liberada. Ao fechar, saldo 5M, objetivo do Ember Egg e
cabecalho Ember Volcano confirmaram o estado de progressao retornado.

Evidencias: [entrada](reports/night-acceptance-2026-10-16/gym2-entry.png),
[normal](reports/night-acceptance-2026-10-16/gym2-normal.png),
[especial/recarga](reports/night-acceptance-2026-10-16/gym2-special-cooldown.png),
[vitoria](reports/night-acceptance-2026-10-16/gym2-victory.png),
[desbloqueio](reports/night-acceptance-2026-10-16/gym2-unlocked.png),
[Output](reports/night-acceptance-2026-10-16/gym2-output.txt).

### Gym 3: Ember Volcano

Perfil observado: 20B, 6 rebirths, golden Voltscorp, Moranguete e Bananao.
Prompt informou Fire, counter Water, taxa 10B e regras de retry. Foram
usados Electric Strike e Smash, com recarga de dois turnos. Coalmole,
Moranguete e Ashwolf apareceram como oponentes reais. A luta terminou em
sete acoes, Voltscorp ainda ativo com 867/2779 HP. VICTORY informou a badge
de Ember Volcano e que esse era o ultimo gym. Ao fechar, saldo 10B,
seguidores preservados e objetivo Rebirth. Nao houve desbloqueio de um
quarto mundo, coerente com o ultimo gym.

Evidencias: [entrada](reports/night-acceptance-2026-10-16/gym3-entry.png),
[normal](reports/night-acceptance-2026-10-16/gym3-normal.png),
[especial/recarga](reports/night-acceptance-2026-10-16/gym3-special-cooldown.png),
[vitoria](reports/night-acceptance-2026-10-16/gym3-victory.png),
[retorno](reports/night-acceptance-2026-10-16/gym3-complete.png),
[Output](reports/night-acceptance-2026-10-16/gym3-output.txt).

Derrota/retry foi exercitado no gym1 na entrega anterior, com contador e
segunda tentativa sem nova taxa. Nesta continuacao gym2 e gym3 percorreram
o ramo de vitoria. Nenhuma afirmacao de derrota natural nesses dois gyms.

## Correcao concreta encontrada

No gym2, os seguidores semeados antes dos assets ficaram como blocos mesmo
apos o Output informar 36/36 modelos carregados. O cache de seguidores so
reconstruia quando a equipe mudava. A atualizacao tardia dos retratos ja
existia; faltava a dos modelos no mundo.

Followers agora observa chegada de templates e de suas partes, atualiza o
mapeamento e invalida apenas equipes que ainda usam bloco para aquele pet.
O proximo frame reconstrui a equipe com escala e movimento existentes.
Nao adiciona consulta por frame ou pedido remoto. No gym3, os tres modelos
reais apareceram sem mudar a equipe, validando o caso de entrada com equipe
ja equipada. [Seguidores corrigidos](reports/night-acceptance-2026-10-16/followers-late-assets-fixed.png).

## Checkout isolado operacional

Preparado por clone local --no-hardlinks --no-checkout, checkout do HEAD
capturado na origem e remocao de origin. Caminho:
C:/Users/joaov/Documents/Codex/2026-10-15/roblox-factory-acceptance-clean-2026-10-16.
Branch codex/factory-local, HEAD b9e62108dbfa500fa604e37a141a0dd45148099f.
Inclui os 34 commits importados mais a migracao, a entrega principal e
a correcao de seguidores, 37 a frente da referencia origin/main preservada na origem.

O Run.preflight() existente passou: HEAD exato, arvore limpa e sem remotes.
Nao foi chamado Run.go(), nenhum agente foi despachado e nao houve reset,
fetch, push ou publicacao. Os arquivos importados nao rastreados da origem
foram preservados. [Saida](reports/night-acceptance-2026-10-16/preflight-final.txt).
RUN-CODEX documenta do clone ao preflight e a chamada limitada para um brief
futuro. O clone inclui o codigo final b9e6210; para
incluir commits posteriores de relatorio, repetir em uma pasta nova,
que captura dinamicamente o HEAD atual.

## Pendencias externas para lancamento

- Save/rejoin e disputa da mesma sessao entre servidores em TESTE publicado,
  incluindo autosave junto da saida e recuperacao apos falha.
- Compra, cancelamento e beneficios reais dos quatro passes no TESTE.
- Progressao longa com equipe obtida naturalmente e jogadores novos.
- Celular fisico, toque, rede lenta, FPS e mais de um jogador.
- Revisao de titulo, descricao, icone/thumbnails e alvo; aprovacao e
  publicacao. Nada foi enviado nesta entrega.

Avisos de DataStore indisponivel sao esperados no arquivo local. Os Outputs
incluem avisos internos do Roblox UIBlox/Studio, sem erro fatal de script do
jogo observado nos fluxos executados. Perfil temporario nao comprova save.

## Builds identificados

Os arquivos abaixo foram produzidos localmente; QA nunca entra no projeto
de distribuicao. Hashes SHA-256 dos arquivos inspecionados:

| Arquivo em build/ | SHA-256 |
| --- | --- |
| game.rbxl | `C6CEAE408D60459DF2A3CD60DE3E1D6547ADE463F37846A6D5A2BA07CA302337` |
| playtest/beginner-acceptance.rbxl | `9391EE274BA0715A444354102A23AF2EE004C1A3DE331A2A5475A04C0820A5EE` |
| playtest/gym2-acceptance.rbxl | `3B8D462523FB7EF5B846FC1CFE922B94CE60E1454B52BB7B1E32BE080339D885` |
| playtest/gym3-acceptance-final.rbxl | `41C1BB0E2B77F9CABC5830CA39E0B0EE1D03428B4E3F90E5EF5C95BB33F57FC5` |

Beginner e gym2 usam o codigo 14759c3. Gym3-final e game.rbxl incluem a
correcao b9e6210. Reconstrucoes posteriores podem ter hashes diferentes.
