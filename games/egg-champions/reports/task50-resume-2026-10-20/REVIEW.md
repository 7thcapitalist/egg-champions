# Relatorio 1: cenarios, batalha e colecao

Revisao local de 2026-10-20. Producao pausada, sem publicacao nem execucao real do executor. Outras sessoes do Studio e o checkpoint de recuperacao foram preservados. A tarefa 50 permanece aberta pela publicacao/reabertura historica nao confirmada e pela aprovacao visual geral pendente.

## Implementacao

Em paisagem curta, status ficam nas extremidades e pets usam a altura central. Nome, tipo e HP tem limites proprios; o layout regular retorna ao redimensionar. A alocacao calculada passou de 63 para 117 px em 720x239 com inset superior de 58 px. Botoes mantem pelo menos 44 px nos casos suportados. Efeitos continuam usando Effects.reflowBattle. Nenhuma regra de combate, forca, preco ou perfil persistente mudou.

Journey agora mostra conjuntos de pets normais, especies faltantes, bloqueios por mundo e o bonus de colecao existente. Sugere um conjunto incompleto desbloqueado, preferindo aquele com mais especies coletadas. Variantes nao contam como normais. O botao fecha Journey antes de abrir a loja do ovo alvo: isso corrige uma sobreposicao encontrada no teste real. Nao ha novo premio, moeda, campo salvo ou compra automatica.

## Studio e evidencia

Instancia separada c25e6b57-54f4-49e2-b086-8f7822647f45: task50-resume-2026-10-20.rbxl, PlaceId 0. O build inicial recebeu somente os fontes locais CollectionGoals/Journey para a revisao. O build final completo e build/task50-collection-review-2026-10-20.rbxl; nao foi reaberto como um segundo binario. O console confirmou DataStore indisponivel e perfis temporarios que nao seriam salvos. Fixtures existiram apenas durante Play, com passes desativados; nao fazem parte do build final.

- 720x239 solicitado: area efetiva medida 720x239.333; quadro do pet 117x117 e controles 44 px. Captura mostrou nome, tipo, HP e ambos os pets.
- 568x239: captura mostrou os dois status, criaturas e controles. Ataques reais passaram pela resposta do servidor; houve substituicao de Emberkit por Puddlet e depois Voltibun. Cliques durante animacao podem ser ignorados.
- Resize para 958x540 restaurou layout regular e log, com HP atualizado.
- Retrato: preset de telefone solicitado 390x844, area efetiva 390x748. A diferenca vem de insets/simulacao. HP, pets, log, moves e GIVE UP ficaram visiveis apos resize. Nao se afirma teste fisico de aparelho.
- Cura confirmada no log: Puddlet recuperou 82 HP, chegando a 357/357. A fixture usou 50 renascimentos temporarios para sobreviver ate a cura. Isso valida apresentacao/fluxo, nao dificuldade ou progressao natural.
- Journey foi observado no desktop e em retrato 390x748. Texto alvo mediu 232.67x64 dentro de 301x80; conjuntos usam altura automatica e scroll. Botao corrigido clicado no desktop: Journey=false, EggShop=true. O clique automatizado em retrato nao acionou a loja; toque fisico continua pendente. Nenhuma compra foi feita.
- As seis rampas foram percorridas para cima e para baixo com Humanoid:MoveTo, teletransportando apenas ao pe de cada rampa entre casos isolados. Todos chegaram ao destino na tolerancia horizontal. Veja ramp-traversal.json: alturas foram registradas, mas nao eram criterio automatico de aprovacao.
- Capturas na altura do personagem mostraram prado, costa e vulcao. Tentativas de camera geral nao produziram evidencia util de composicao: nenhuma aprovacao ou nova nota foi atribuida. Geometria dos cenarios foi preservada.

Capturas reais foram exibidas na conversa. A gravacao local foi recusada pelo limite de 64000 bytes da revisao automatica da ferramenta. Nao houve tentativa por outro caminho; nao existem PNGs novos dessas capturas. Estes JSONs e descricoes nao substituem evidencia visual arquivada.

Play foi parado na instancia separada, simulacao desativada e orientacao original LandscapeSensor restaurada. Fixtures de runtime desapareceram com Stop. O atributo QA adicionado durante a revisao foi removido no Edit. Nenhum arquivo aberto foi salvo por cima; outras sessoes nao foram fechadas. A instancia de QA permanece em Edit com os fontes locais desta revisao.

## Verificacoes e pendencias

882 testes Luau e 6 autotestes passaram. Selene: zero erros/avisos; StyLua e Rojo passaram. Os 58 testes Python passaram, incluindo 9 novos testes em fixtures temporarias. checks.json registra hashes e resultados.

Gate planned passou com 51 tarefas: confirma cobertura, nao conclusao. Gate economy_tuned continua falhando: terceiro ginasio exige 2 renascimentos a mais que a meta. Nenhum numero mudou para esconder a falha.

Pendentes: composicao geral (historicamente 3.75/5), capturas arquivadas, toque em aparelho, 320x720 nesta revisao e aprovacao de arte. Testes de limites cobrem mais resolucoes que a revisao visual. Publicacao, reabertura de lugar publicado, persistencia e multiplayer nao foram testados. v95 segue apenas como ultima publicacao TEST confirmada nos registros antigos.
