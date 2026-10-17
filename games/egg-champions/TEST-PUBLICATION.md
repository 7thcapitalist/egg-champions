# Publicacao TESTE e aceitacao

## Atualizacao visual publicada: versao 72

- Publicada em 2026-10-16, 20:52 no horario local, no mesmo TESTE abaixo. Output: Published new changes in Egg Champions Test, publish notes v72.
- Fechado e reaberto da nuvem: PlaceVersion 72, universe 10769019206, place 101737317546942. Os 131 scripts conferem por hash com o build final; nenhum atributo ou script de fixture.
- Trinta pets segmentados, variantes shiny/golden, movimento de membros, tres mapas construidos, interface e inventario mobile revisados.
- 760 testes Luau, seis self-tests, tres testes Python, Selene, StyLua e Rojo passaram. Studio carregou 36 templates, zero placeholders, e verificou 90 variantes.
- HATCH pela interface adquiriu Emberkit e mostrou o modelo correto no efeito/revelacao. BEST COINS, BEST BATTLE e UNEQUIP ALL funcionaram pela interface. Seguidor acompanhou caminhada de 21 metros com articulacao e contato com o chao.
- Evidencias: reports/visual-rework-2026-10-16/publish-output.txt, cloud-reopened.json, runtime-qa.json, variants.json e capturas. Esses testes de Studio nao comprovam save/rejoin publicado.

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
- Progressao inicial sem recursos semeados: 75 cliques normais, espaçados 0,4 s, mais Auto Click. Saldo final observado 3.362, poder 16, tres pets. Isso nao valida ritmo de jogador sem passes nem gyms finais.

## Pendencias concretas

- Save/rejoin: Studio recusou UpdateAsync com StudioAccessToApisNotAllowed. Perfil desta sessao era temporario e nao foi salvo. O usuario prefere validar no Roblox publicado; esse teste continua pendente.
- Consulta publica da API Roblox: TESTE nao tem passes proprios; os quatro IDs configurados pertencem ao universe de producao 10769019314. Beneficios ja possuidos funcionam no TESTE, mas uma compra nova nele nao esta validada. Roblox desativou vendas entre jogos em 2026-05-30: https://create.roblox.com/docs/production/monetization/passes .
- Controle nativo no segundo monitor apresentou erro de coordenadas e de janela em primeiro plano; nao foi possivel concluir a entrada no cliente publicado por automacao. Navegador pessoal nao foi operado.
- Pacing completo de 6 a 8 horas e desempenho em telefone fisico continuam pendentes.

## Direcao visual posterior

O usuario rejeitou o acabamento visual e pediu reformulacao usando Steal An Egg (place 107778070777162) como referencia. Manter os conceitos e identidades dos pets, refazer sua linguagem visual, mapa, interface, efeitos e animacoes. A versao 54 e uma publicacao funcional anterior a essa reformulacao, sem aprovacao de lancamento publico.
