# Publicacao TESTE e aceitacao

## Task 50: build pronto, publicacao ainda sem confirmacao

- Terracos e rampas nos tres biomas, layout responsivo da batalha e recuperacao dos efeitos ao redimensionar. Seis rampas percorridas nos dois sentidos; batalha exercitada em desktop, portrait 320/390 e tela baixa.
- 876 testes Luau e seis self-tests; Selene, StyLua e Rojo passaram. Edit limpo tinha 143 fontes iguais ao build. [Revisao e evidencias](reports/elevation-battle-2026-10-17/REVIEW.md).
- Studio desconectou do servidor de edicao em 2026-10-17 01:34:44 America/New_York. Pedido de publicacao as 01:35:38 ficou em Publishing in progress, sem numero novo nem confirmacao. Nao considerar task 50 publicada. Ultima versao confirmada: 95.
- Checkpoint completo preservado em build/task50-studio-recovery.rbxl, alem do build/game.rbxl. Operacao nao foi cancelada nem repetida.

## Estado atual: versao 95

- Publicacao confirmada pelo Output em 2026-10-17 01:02, America/New_York: publish notes v95 e Published new changes in Egg Champions Test.
- TESTE reaberto da nuvem: place 101737317546942, universe 10769019206, PlaceVersion 95. As 139 fontes conferem por hash com o build; nenhuma fixture ou atributo de teste. Workspace de edicao: Terrain, SpawnLocation e Camera.
- Cenarios secundarios nos tres biomas: pergola e fonte em terracos; pavilhao listrado e coral ramificado; piscina mineral e jardim de cristais. Footprints reservados e caminhos de acesso mantem a decoracao fora das rotas principais.
- Ataque e recuo agora movem os modelos em 3D. Trinta especies usam oito familias de movimento, com curvas distintas para Tidewhale, Thundrake e Magmaroc. Um turno real pela interface e verificacoes de cancelamento, ocultacao e troca de modelo confirmaram retorno da pose no Studio.
- Fluxo inicial repetido com entrada real pela interface em viewport efetiva 390x844: chocar Shiny Puddlet, abrir Pets, equipar e fechar; ganho passou de +2 para +14 por clique. Perfil temporario e passes ja possuidos ativos; nao e teste de save nem de progressao sem passes.
- 871 testes Luau e seis self-tests; Rojo, Selene e StyLua passaram. A fabrica teve 18 testes Python aprovados. Evidencias: [revisao v95](reports/authored-scenes-2026-10-17/REVIEW.md), [fontes reabertas](reports/authored-scenes-2026-10-17/cloud-reopened.json) e [Output](reports/authored-scenes-2026-10-17/publish-output.txt).
- Publicar e passar built nao significam aceitar o lancamento. A revisao visual atual reprova composicao e animacao, ambas em 3,75/5. O gate economy_tuned agora considera rebirths e falha na mediana sete contra meta cinco. Save/rejoin completo nesta versao, novas compras de passes e telefone fisico continuam sem validacao completa. Os gates worlds, playtested e published_test permanecem sem implementacao.

## Interface em telas baixas: versao 92

- TESTE publicado em 2026-10-17 e reaberto da nuvem na PlaceVersion 92: 137 fontes iguais ao build local, sem fixtures.
- Menu horizontal em telas baixas, HATCH acessivel e EQUIP revelado automaticamente no inventario com rolagem; CLOSE permanece fixo. Layout nao restaura a faixa opcional de equipe sobre o menu ao trocar de tela.
- Fluxo de hatch/equip exercitado em viewport efetiva 720x239,333. Capturas em 320x720 e 390x844 usaram resolucao personalizada do Studio; nao representam teste em telefone fisico.
- 866 testes Luau e seis self-tests; gates planned e built passaram. Evidencias: [revisao v92](reports/short-viewport-2026-10-17/REVIEW.md) e [fontes reabertas](reports/short-viewport-2026-10-17/cloud-reopened.json).
- Essa entrega corrigiu a limitacao de tela baixa registrada na revisao v88. Nao validou save/rejoin publicado, compras novas ou progressao completa.

## Composicao e movimento: versao 88

- Publicada em 2026-10-17 00:20 local e reaberta da nuvem: place 101737317546942, universe 10769019206, PlaceVersion 88, 137 scripts iguais ao build e nenhuma fixture.
- Copas arredondadas, lagoas circulares, circuito de retorno com bancos/lanternas, detalhes no moinho, horizonte amplo e outros cenarios ocultos localmente. Seguidores viram na direcao do deslocamento e animam passadas pela distancia percorrida.
- 861 testes Luau, seis self-tests, Rojo, Selene e StyLua passaram. Evidencias: reports/composition-motion-2026-10-17/REVIEW.md e cloud-reopened.json.
- Nao e aprovacao visual final: composicao, animacao e onboarding desta revisao ficaram em 3,5/5. Mobile horizontal conferido; portrait do emulador ficou inconsistente e a barra inferior corta na viewport horizontal muito baixa. A meta mediana de cinco rebirths segue aberta; o balanceamento nao foi alterado com base em experimentos inconclusivos de politica de equipe. Save completo, novas compras e telefone fisico continuam sem validacao adicional.

## Mapas, efeitos, tutorial e valor dos pets: versao 84

- Publicacao confirmada em 2026-10-16 23:56 local pelo Output do Studio. TESTE: universe 10769019206, place 101737317546942.
- Studio reiniciado e TESTE reaberto da nuvem em 2026-10-17: PlaceVersion 84; todos os 137 scripts iguais ao build, sem scripts extras ou atributos de fixture. Workspace de edicao contem apenas Terrain, SpawnLocation e Camera.
- Tres mapas com novos marcos e horizontes abertos; moinho, ondas e particulas ambientais; novos modelos Tidewhale, Thundrake e Magmaroc; movimentos mais suaves, velocidade 22, celebracoes e tutorial com acoes diretas.
- Epic/Legendary antigos passam a ter piso de poder de moedas de 65%/85% do maior poder bruto possuido. Equip Best, servidor e interface usam a mesma regra. Combate permanece com seus atributos proprios.
- 859 testes Luau e seis self-tests; 13 testes Python, Selene, StyLua e Rojo aprovados. 36 modelos e texturas verificados, zero placeholders. Tutorial hatch/equip exercitado no Studio; layouts 320/390 revisados.
- Evidencias: reports/world-polish-2026-10-16/REVIEW.md, publish-output.txt, cloud-reopened.json e capturas finais.
- A revisao visual da fabrica ainda reprova composicao e animacao para lancamento final (3,5/5). Pacing simulado final de 7,70 h, mas 7 rebirths contra alvo 5. Save completo, compra nova de passes no TESTE e telefone fisico continuam pendentes; os testes abaixo nao foram repetidos no cliente publicado nesta versao.

## Atualizacao visual publicada: versao 72

- Publicada em 2026-10-16, 20:52 no horario local, no mesmo TESTE abaixo. Output: Published new changes in Egg Champions Test, publish notes v72.
- Fechado e reaberto da nuvem: PlaceVersion 72, universe 10769019206, place 101737317546942. Os 131 scripts conferem por hash com o build final; nenhum atributo ou script de fixture.
- Trinta pets segmentados, variantes shiny/golden, movimento de membros, tres mapas construidos, interface e inventario mobile revisados.
- 760 testes Luau, seis self-tests, tres testes Python, Selene, StyLua e Rojo passaram. Studio carregou 36 templates, zero placeholders, e verificou 90 variantes.
- HATCH pela interface adquiriu Emberkit e mostrou o modelo correto no efeito/revelacao. BEST COINS, BEST BATTLE e UNEQUIP ALL funcionaram pela interface. Seguidor acompanhou caminhada de 21 metros com articulacao e contato com o chao.
- Evidencias: reports/visual-rework-2026-10-16/publish-output.txt, cloud-reopened.json, runtime-qa.json, variants.json e capturas. Esses testes de Studio nao comprovam save/rejoin publicado.

## Save/rejoin no cliente publicado: 2026-10-16

- O usuario saiu e entrou novamente pelo link do TESTE. Captura apos retorno: Coral Coast, 0 rebirths, +232 por clique; equipe Zapeel (+80), Cinderhog (+25), Sparkit (+10).
- O usuario confirmou que havia comprado ovos e trocado para essa equipe antes de sair. A captura anterior (+162, Bubblecrab/Cinderhog/Zapmoth) antecedia essas mudancas.
- Aprovado neste ciclo manual: equipe equipada e acesso ao mundo mantidos apos rejoin. Ganho por clique observado compativel com a equipe e 2x Coins: (1 + 80 + 25 + 10) * 2 = 232.
- Saldo observado apos retorno: 45K, depois 51K. Nao ha captura imediatamente anterior a saida para validar saldo exato; inventario completo, index, taxas e rebirth nao foram exercitados neste ciclo.
- Evidencia: reports/published-rejoin-2026-10-16/after-rejoin.jpg. Captura do cliente no segundo monitor; o numero da versao do servidor nao aparece no HUD.

## Publicacao anterior: versao 54

- Experience: Egg Champions Test, universe 10769019206, place 101737317546942.
- Versao publicada: 54. Output confirmou "Published new changes".
- Place fechado e reaberto da nuvem: PlaceVersion 54, 128 scripts iguais ao build local c75ea86.
- Nenhuma fixture publicada. Atributo legado PlaytestNoPasses removido.
- Evidencias: reports/published-test-2026-10-16/publish-output.txt, published-v54.png, publish-sync.json e cloud-reopened.json.

## Testes executados na versao 54 pelo Studio

- Os 36 templates carregaram, sem placeholders restantes.
- MarketplaceService confirmou que jvcarvalho70 possui os quatro passes. Nao houve compra nem gasto de Robux.
- Auto Click: saldo passou de 520 para 526 em aproximadamente tres segundos sem outros cliques.
- 2x Coins: inicio sem pets rende 2; equipe Leafpup, Leafpup e Abacatudo (1 + 1 + 5) rende 16 por clique.
- Triple Hatch: Meadow x3 debitou 150 e criou tres UIDs distintos, com index atualizado.
- EquipBest coins equipou os tres pets realmente obtidos; tutorial avancou para a proxima meta.
- Lucky Eggs: payload habilitou o beneficio e a loja mostrou Epic 9% e Legendary 1%.
- Progressao inicial sem recursos semeados: 75 cliques normais, espaÃ§ados 0,4 s, mais Auto Click. Saldo final observado 3.362, poder 16, tres pets. Isso nao valida ritmo de jogador sem passes nem gyms finais.

## Pendencias concretas

- Save/rejoin: equipe e acesso ao mundo confirmados no cliente publicado no ciclo acima. Saldo exato, inventario completo, index e persistencia de rebirth continuam sem comparacao antes/depois. Studio permanece com acesso a APIs desativado e usa perfil temporario.
- Consulta publica da API Roblox: TESTE nao tem passes proprios; os quatro IDs configurados pertencem ao universe de producao 10769019314. Beneficios ja possuidos funcionam no TESTE, mas uma compra nova nele nao esta validada. Roblox desativou vendas entre jogos em 2026-05-30: https://create.roblox.com/docs/production/monetization/passes .
- Controle nativo no segundo monitor apresenta coordenadas inconsistentes e cliques que nao abrem os menus; entrada e rejoin foram feitos pelo usuario. Observacao do cliente publicado funciona. Navegador pessoal nao foi operado.
- Pacing completo de 6 a 8 horas e desempenho em telefone fisico continuam pendentes.

## Direcao visual posterior

O usuario rejeitou o acabamento visual e pediu reformulacao usando Steal An Egg (place 107778070777162) como referencia. Manter os conceitos e identidades dos pets, refazer sua linguagem visual, mapa, interface, efeitos e animacoes. A versao 54 e uma publicacao funcional anterior a essa reformulacao, sem aprovacao de lancamento publico.
