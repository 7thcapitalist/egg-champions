# Egg Champions: melhoria para lancamento

Pedido do Joao, 2026-10-16: melhorar o jogo visualmente, corrigir retratos de
costas, acrescentar Equipar melhores, analisar o que falta e executar uma
fila concreta de melhorias. Trabalho local; publicacao continua separada.

## Fila desta entrega

Os dez itens abaixo pertencem ao brief 44 do indice da factory.

- [x] 1. Retratos frontais em tres quartos, enquadrados pelo modelo e pela proporcao do card, com iluminacao de frente.
- [x] 2. Equipar melhores para moedas e para batalha, e desequipar todos, decididos atomicamente no servidor.
- [x] 3. Inventario utilizavel: busca, filtros claros, retratos maiores, variantes corretas nos cards, acesso ao indice e feedback das acoes.
- [x] 4. Evitar reconstruir retratos e grids em cada atualizacao de moedas; manter selecao e rolagem durante uso.
- [x] 5. Corrigir a corrida entre autosave e saida; uma gravacao atrasada nao pode reabrir o save liberado. Regressao pura aprovada, DataStore real ainda pendente.
- [x] 6. Loja de passes responsiva com rolagem, altura limitada e botao Fechar acessivel.
- [x] 7. Criar cenario local explicito para QA de gym e portais; executar teste visual de inventario, hatch, equipe e progressao no Studio.
- [x] 8. Rodar suite, build, lint e formatacao; registrar evidencias, bugs restantes e checklist de lancamento honesto.
- [x] 9. Auto Hatch com compra normal, uma requisicao por vez, parada durante a revelacao e cancelamento ao fechar, ficar sem moedas ou receber recusa.
- [x] 10. Adversarios de gym com pets reais do mundo, preservando todos os atributos ajustados; explicar tipo, counter, taxa e retry antes da luta.

Cada item tem verificacao em teste automatizado quando ha regra verificavel,
e inspecao no Studio para aparencia/interacao. O tempo pedido e uma estimativa
de trabalho util, nao uma espera artificial.

## O que falta para aprovar lancamento

- Validar em celular fisico e rede lenta; desktop e emulador foram inspecionados.
- Completar sessao sem fixture, progressao natural e lutas dos gyms 2 e 3; o fluxo do gym 1, derrota/retry, vitoria e rebirth foi executado.
- Testar save/rejoin e concorrencia entre servidores no lugar de TESTE publicado com DataStore.
- Testar compra, cancelamento e beneficio dos quatro passes no ambiente de TESTE.
- Revisar titulo, descricao, icone e thumbnails finais e os IDs do lugar alvo antes de publicar.

## Ideias para a proxima versao

Favoritos/protecao contra exclusao, colecao com metas visuais,
recomendacao por adversario, missoes curtas e eventos podem ajudar retencao. Essas ideias
precisam de design e balanceamento especificos antes de entrarem no jogo.
Esta entrega prioriza os comandos de equipe, descoberta e leitura dos pets,
e a confiabilidade do fluxo existente.

Auto Hatch foi implementado nesta entrega. Resultados, imagens e criterios
de aceitacao estao em [LAUNCH-REPORT.md](LAUNCH-REPORT.md).
