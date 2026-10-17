# Reformulacao visual

Pedido do usuario em 2026-10-16. Referencia: https://www.roblox.com/games/107778070777162/Steal-An-Egg .
Captura oficial e captura de gameplay analisadas. Referencia de linguagem visual, sem reutilizar personagens ou assets daquele jogo.

## Direcao

Superficies limpas com studs discretos, cores saturadas, limites de biomas construidos, volumes grandes e caminhos claros. Pets originais com formas facetadas, rostos legiveis, anatomia separada e caracteristicas elementais grandes. Movimentos de patas, asas e caudas devem funcionar sem depender de IDs de animacoes externos.

## Lista de trabalho

- [x] Confirmar referencia e identidade a preservar com o usuario.
- [x] Inspecionar mapa, pets e sistema de animacao existentes.
- [x] Refazer os 30 pets em malhas facetadas segmentadas com silhuetas por especie e variantes.
- [x] Implementar movimento articulado de patas, asas e caudas; seguidores acompanhando o chao.
- [x] Refazer os tres biomas com piso construido, limites, caminhos e pontos de interesse.
- [x] Reforcar stands, gyms, portais, vegetacao e sinalizacao na mesma direcao.
- [x] Atualizar cores e hierarquia da interface, revelacao e batalha.
- [x] Verificar todos os pets, variantes e tres mapas no Studio; corrigir defeitos visiveis.
- [x] Executar gates existentes, publicar no TESTE e conferir a versao reaberta.
- [ ] Retomar save/rejoin e progressao no cliente publicado; registrar separadamente as pendencias externas.

## Evidencia e limites

Na versao 54, os pets eram malhas estaticas com texturas detalhadas. Followers apenas aplica bob e interpolacao ao modelo inteiro; nao ha articulacao. O mapa usa Terrain Grass/Sand/Basalt, mares quadrados e props de bolas/cilindros. Isso explica a distancia visual para a referencia, independentemente dos testes funcionais ja aprovados.

## Implementacao e verificacao

- Nova importacao suporta ate oito partes por pet, com tamanho e CFrame local.
- Trinta pets importados; 36 templates incluindo seis ovos. As 164 partes tiveram malhas e texturas carregadas com sucesso no Studio.
- Noventa combinacoes de especie/variante verificadas, com capturas em seis galerias. Golden usa uma cobertura dourada que preserva os rostos; shiny tem brilho discreto.
- Leafpup apareceu de frente no inventario apos compra normal de 50 moedas. HATCH clicado na interface adquiriu Emberkit, mostrando o ovo 3D e o mesmo modelo no efeito e na revelacao.
- BEST COINS e BEST BATTLE clicados na interface equiparam Leafpup. UNEQUIP ALL removeu a equipe e o seguidor. Nenhum perfil foi semeado para esses testes.
- Caminhada de 21,33 studs: seguidor percorreu 21,36 studs, patas mudaram de angulo e base ficou em Y=0,000006. Movimento usa partes locais, sem IDs de animacao externos.
- Inventario em Samsung A06 simulado: cartoes horizontais cabem na area util 706x281. Corrigida a corrida de atualizacao que reabria a barra do tutorial sobre os botoes.
- Correcao de placas: TextWrapped=false desativava TextScaled e deixava texto em 8 px.
- Retratos agora antecipam carregamento e mostram estado enquanto malhas chegam.
- Mapas: Meadow 590 partes, Coast 519, Volcano 454. Capturas feitas com camera de inspecao; visitar biomas para QA nao conta como progressao natural.
- PetSculpt de blocos foi descartado apos inspecao visual.
- 760 testes Luau, seis self-tests do runner e tres testes Python de assets passaram. Selene sem erros/avisos, StyLua e build Rojo aprovados.
- Fontes do Studio comparadas por hash: 131 de 131 iguais ao build, nenhum script extra ou atributo de fixture. Evidencias em reports/visual-rework-2026-10-16.
- Publicacao: Output confirmou a versao 72 no Egg Champions Test. Fechado e reaberto da nuvem: PlaceVersion 72, universe 10769019206, place 101737317546942, 131 fontes identicas ao build local e nenhum atributo de fixture.

## Limites de lancamento

Save/rejoin no cliente publicado, compra nova de passe e pacing completo continuam pendentes. O Studio usa perfil temporario porque API access esta desativado; o usuario preferiu testar persistencia no aplicativo Roblox. Beneficios dos passes ja possuidos foram observados, sem compras. Nao houve publicacao em producao. Ver TEST-PUBLICATION.md.
