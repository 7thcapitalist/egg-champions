# Egg Champions: qualidade e preparacao para lancamento

Data: 2026-10-16. Implementacao local da task 44. Sem push ou publicacao.
Lista executada: [LAUNCH-WORK.md](LAUNCH-WORK.md).
Aceitacao complementar posterior: [NIGHT-ACCEPTANCE.md](NIGHT-ACCEPTANCE.md),
com inicio sem recursos semeados, gyms 2/3 e preflight do clone isolado.
O complemento b9e6210 corrige seguidores presos no bloco apos chegada
tardia dos assets. Built foi reexecutado com sucesso; o hash do build final
e as novas evidencias estao no NIGHT-ACCEPTANCE.

## Avaliacao

O jogo tinha um loop funcional, mas problemas visiveis prejudicavam o uso:
retratos de costas, modelos com um cubo de efeito flutuante, cards pequenos,
falta de comandos de equipe e dificuldade para localizar um pet. Havia
tambem uma falha de layout real: limpar o grid preservava layouts antigos,
que se acumulavam e redimensionavam os cards de forma errada. No save,
autosave e saida podiam disputar a mesma sessao.

Esses problemas foram corrigidos. A versao local esta adequada para um
playtest de aceitacao no lugar de TESTE. A aprovacao para lancamento publico
continua dependendo dos testes externos listados no final deste documento.

## Entrega

| Area | Mudanca implementada |
| --- | --- |
| Retratos | Camera frontal em tres quartos, luz de frente, centralizacao e distancia calculadas pelas dimensoes reais do modelo e do card. Removido cubo decorativo dos assets reais. |
| Assets | Ate quatro carregamentos independentes; templates aparecem assim que ficam prontos. Um retrato aberto antes do template pode se atualizar sozinho quando o asset replica. |
| Equipe | BEST COINS, BEST BATTLE e UNEQUIP ALL. O servidor usa o inventario real, limita a tres pets e troca a equipe atomicamente. Alteracoes durante luta sao recusadas. |
| Recomendacao | Moedas considera variantes; batalha usa HP multiplicado por Attack ajustados por variante e rebirth, depois Speed. O aviso lembra que vantagem de tipo ainda importa. |
| Inventario | Busca por nome, tipo, raridade, ovo e variante; filtros recolhiveis; cards maiores; variantes nos retratos; recuperacao de busca vazia. |
| Colecao | Index e Fruit acessiveis desde o inicio, selecao coerente por aba e Equip/Unequip da forma possuida diretamente pelo detalhe. |
| Desempenho da UI | Moedas e tempo de jogo nao recriam grids de pets. Selecionar um pet preserva os cards; limpeza remove os layouts antigos. |
| Auto Hatch | Compras normais de um ovo por vez, com revelacao entre compras. STOP AUTO acessivel sobre a revelacao. Cancela por fechamento, troca de tela, saldo insuficiente, ovo bloqueado ou recusa. |
| Gym | Adversarios usam pets reais do mundo, mantendo todos os atributos ajustados. Prompt explica tipo, counter, taxa, tentativas gratuitas e retry. Cabecalho respeita os controles do Roblox. |
| Save | Gravacoes ordenadas por sessao; saida fecha a fila imediatamente e espera autosave ativo. Gravacao exige a propria trava de sessao, inclusive quando a trava esta ausente. |
| Loja | Altura limitada, lista rolavel e Fechar fixo, inclusive em tela curta. |
| QA | Builder de cenarios locais separados do projeto de distribuicao; guards de Studio e PlaceId zero. Marketplace e analytics externos desativados apenas no lugar local nao publicado. |

## Verificacao automatizada

Suite do jogo: **759/759 testes**, mais **6 autotestes do runner**.
Selene: zero erros e avisos. StyLua: check aprovado. Rojo: build aprovado.
Os testes novos cobrem recomendacao por variantes, desempates, limite da
equipe, validacao de requests, ordem do save, busca, assinatura do
inventario, camera, layouts e cancelamento do Auto Hatch.

Gates finais aprovados: `planned` (44 tarefas), `built` (44 done, suite,
Rojo, Selene e StyLua) e `assets` (36 modelos atuais, mapeados e com
verificacao Roblox existente valida). Estado atualizado por `state.py`.
[Saida do gate built](reports/launch-2026-10-16/built-gate.txt).

O projeto de distribuicao e `build/game.rbxl`, sem fixture de QA.
SHA-256 deste build antes dos gates finais:
`0D0A00BBEC6B005161E677A0B690DF09CB562C79E4C3EDC7E9CE86FB2639D418`.
O arquivo inspecionado para os ajustes finais de UI foi
`build/playtest/launch-final.rbxl`, SHA-256
`DDA201FE6CBBA4AEF2D0F7AAB5E1A97165B9839102B61493BD983E1A9467410C`.
Builds Rojo posteriores podem ter hashes diferentes.

## Playtest real no Studio

As imagens e o Output estao em [reports/launch-2026-10-16](reports/launch-2026-10-16).
Foi usado perfil temporario com colecao semeada, para acessar os fluxos sem
esperar horas por moedas. Isso verifica interacao e integracao, sem provar
o ritmo de progressao natural nem persistencia.

- Retratos frontais observados em pets das tres regioes e nos tres Fruit.
  [Inventario](reports/launch-2026-10-16/inventory-final.png).
- BEST COINS e BEST BATTLE produziram equipes diferentes; os pets seguidores
  e o poder de clique acompanharam a resposta do servidor. UNEQUIP ALL
  preservou os 32 pets possuidos. Busca por Leafpup mostrou normal e shiny;
  busca sem resultado ofereceu recuperacao.
- Auto Hatch realizou compras e revelou pets, com custo debitado. STOP AUTO
  interrompeu a sequencia; saldo permaneceu em 1.029.701 entre observacoes.
  [Revelacao](reports/launch-2026-10-16/auto-hatch-reveal.png),
  [parada](reports/launch-2026-10-16/auto-hatch-stopped.png).
- Gym 1: taxa de 50.000, Give Up, derrota com contador, nova tentativa sem
  segunda taxa, ataque normal, especial, cooldown, troca de tres oponentes
  e vitoria. O jogo informou badge e Coral Coast liberada.
  [Retry](reports/launch-2026-10-16/gym-retry.png),
  [vitoria](reports/launch-2026-10-16/gym-victory.png).
- Rebirth: confirmacao de custo, moedas zeradas, volta a Green Meadow,
  rebirth 1 e bonus permanente, com pets/equipe preservados.
  [Reset](reports/launch-2026-10-16/rebirth-reset.png).
- Portais: o cenario fisico confirmou toque e recusa do primeiro portal
  bloqueado, chegada em Coral Coast (x=400), chegada em Ember Volcano
  (x=800) e toque/recusa de coming soon. O handler real decidiu cada caso,
  sem ser substituido por uma simulacao. As primeiras tentativas expuseram
  falhas do movimento da fixture; foram corrigidas espera pelo spawn,
  controle de fisica, caminhada residual e intervalo entre toques. A
  execucao final teve os quatro PASS. Textos de Notice nao foram aferidos.
  [Output final](reports/launch-2026-10-16/portals-output.txt),
  [imagem](reports/launch-2026-10-16/portals-passed.png).
- iPhone XR emulado em paisagem: inventario, colecao Fruit com Equip,
  ovos/Auto Hatch, loja rolando ate Triple Hatch e Fechar acessivel. Nao
  substitui teste de desempenho e toque em um aparelho fisico.
  [Pets](reports/launch-2026-10-16/mobile-pets.png),
  [Fruit](reports/launch-2026-10-16/mobile-fruit.png),
  [loja](reports/launch-2026-10-16/mobile-shop-scroll.png).
- Cabecalho da luta corrigido e reinspecionado em celular e desktop.
  [Celular](reports/launch-2026-10-16/mobile-battle-header.png),
  [desktop](reports/launch-2026-10-16/desktop-battle-header.png).
- Output final: servidor e cliente prontos, 30 pets, 6 ovos, 3 mundos,
  6 stands, 3 gyms e 3 portais; **36/36 modelos carregados, zero
  placeholders**, cerca de 4,9 segundos apos servidor pronto nesta execucao.
  Sem benchmark anterior comparavel. Houve aviso UIBlox/CorePackages do
  Roblox; nenhum erro fatal do jogo neste Output.
  [Log completo](reports/launch-2026-10-16/studio-output.txt).

## Como repetir localmente

Na raiz do repositorio:

```powershell
python -B factory/tools/build_playtest.py games/egg-champions beginner
python -B factory/tools/build_playtest.py games/egg-champions gym1
python -B factory/tools/build_playtest.py games/egg-champions gym2
python -B factory/tools/build_playtest.py games/egg-champions gym3
python -B factory/tools/build_playtest.py games/egg-champions collection
python -B factory/tools/build_playtest.py games/egg-champions portals
python -B factory/tools/run_tests.py games/egg-champions
rojo build games/egg-champions -o games/egg-champions/build/game.rbxl
```

Abra o `.rbxl` correspondente em `build/playtest/`. Os cenarios de gym usam
equipe de referencia ajustada para QA, nao um save real. Nao publique esses
arquivos. O builder nao altera `default.project.json`, spec ou configuracao.

## Criterios restantes antes do lancamento publico

- [ ] No lugar de TESTE, salvar e reentrar com moedas, equipe, variantes,
  badges e rebirth; provocar autosave junto da saida e verificar o ultimo
  estado. A regressao pura passou; DataStore real nao foi exercitado.
- [ ] Validar trava do mesmo usuario entre dois servidores e recuperacao
  apos falha. Multi-client local sozinho nao comprova esse criterio.
- [ ] Testar compra, cancelamento e beneficio dos quatro passes no TESTE.
  O modo local exibe SOON deliberadamente e nao permite compras reais.
- [ ] Verificar progressao prolongada, ritmo e dificuldade dos gyms 2 e 3
  com equipe obtida naturalmente e entendimento com jogadores novos.
  A sessao curta do inicio sem recursos semeados e as lutas de integracao
  com equipes de referencia estao registradas no NIGHT-ACCEPTANCE;
  nao comprovam o ritmo completo.
- [ ] Testar em celular fisico, rede lenta e mais de um jogador, incluindo
  FPS, carregamento de modelos e tempo de resposta.
- [ ] Revisar titulo, descricao, icone, thumbnails e lugar alvo; aprovar
  publicacao. Nenhum push ou publish foi realizado nesta entrega.

`built` e `assets` tem gates; `worlds`, `playtested` e `published_test`
continuam pendentes porque os gates completos dessas etapas nao existem.

## Features interessantes para depois da aceitacao

1. Favoritos e protecao de pets: ajuda com colecoes grandes; requer definir
   se favoritos interferem em Equip Best ou somente em futuras exclusoes.
2. Metas curtas de colecao e missoes: dar objetivo entre gyms, com recompensas
   especificadas e economia simulada antes de implementar.
3. Recomendacao por adversario: sugerir counters do gym com comparacao de
   time; a recomendacao atual e geral.
4. Eventos e pets limitados originais: planejar calendario, regras e retorno
   dos eventos, sem depender deles para o primeiro lancamento.

Auto Hatch saiu da lista de ideias e foi entregue nesta versao. As ideias
acima sao backlog de produto, sem promessas de conclusao nesta task.
