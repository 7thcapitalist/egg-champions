# Relatorio 2: capacidade da fabrica e referencias

Implementado em 2026-10-20, com producao pausada. Permissao para continuar usando IA nesta conversa nao foi convertida em orcamento do executor. Sem geracao real, publicacao, alteracao de credenciais ou configuracoes globais. run_factory.py, executor.json, ledger e os controles que o Dot trata nao mudaram. Nenhuma mensagem ou comando foi enviado ao Dot.

## Capacidade entregue

factory/tools/feature_research.py valida pesquisa por jogo e gera propostas de briefs com Python padrao, sem rede ou chamadas de modelo. factory/FEATURE-RESEARCH.md documenta o processo; README e instrucoes do planner o integram. gate.py valida pesquisa opcional no gate planned.

Fontes exigem HTTPS, consulta com no maximo 14 dias, disponibilidade, observacao e limitacoes. Rank numerico exige snapshot local disponivel e SHA-256 correspondente. Fonte indisponivel nao fundamenta funcionalidade. Cada ideia declara adopt/defer/reject e adaptacao original.

Adocao exige aprovacao de escopo, declaracao de impacto economico/persistente, arquivos delimitados, verificacoes automaticas, revisao no motor e tarefa indexada vinculada. Impactos economicos/persistentes exigem contrato de design local. Existencia do contrato nao prova balanceamento, migracao segura ou aprovacao humana por si so.

check valida referencias e cobertura. plan escreve briefs e manifesto proposal-only em diretorio novo dentro do jogo; recusa sobrescrita e nao muda index, spec, config, estado ou politica. Foi criada build/feature-proposal-2026-10-20, sem iniciar agentes. A tarefa 51 foi registrada deliberadamente, dependente da 50, ainda pending. Proposta nao equivale a implementacao.

Regras sao aplicadas pelo script e gate planned quando chamados. Nao interceptam edicoes manuais nem todos os processos externos; nao garantem verdade das fontes, qualidade, originalidade legal ou retencao. Outros gates continuam necessarios. Nenhuma verificacao extra por IA foi adicionada.

## Referencias e decisoes

Nao foi possivel confirmar rank atual em https://www.roblox.com/charts: pagina exigiu JavaScript. Nenhuma posicao, CCU ou promessa de sucesso foi usada. Referencias de mecanicas descritas pelos proprios criadores:

- https://www.biggames.io/post/pet-simulator-99-update-98, de 17/10/2026: encontro coletivo, exploracao e expedicoes. Referencia para propostas originais, sem prova de impacto em popularidade.
- https://www.biggames.io/post/pet-simulator-99-update-97, de 10/10/2026: missoes diarias e progressao sazonal. Requer design proprio e revisao de premios.
- https://www.roblox.com/games/126884695634066/Grow-a-Garden: descricao oficial enfatiza cultivo, colecao e crescimento offline. Apenas descricao consultada, sem teste de jogabilidade ou medicao de retencao.

Adotado: trilha de colecao em Journey, usando indice e bonus existentes. Autorizacao ampla de melhorar funcionalidades foi limitada a essa apresentacao; nenhum numero economico mudou. Implementacao e revisao constam no relatorio 1. Criaturas, identidade e assets devem continuar originais.

Adiadas em design/feature-research.json: diarias precisam de relogio/reset e premios; cooperativo precisa de contribuicao, antifraude e testes multiplayer; offline precisa de teto de acumulacao e saves atomicos; exploracao precisa de rotas autorais; eventos precisam de agenda, assets e economia. Nenhuma dessas cinco funcionalidades foi implementada.

## Resultados e limites

58 testes Python passaram, incluindo 9 casos novos deterministas para datas vencidas/futuras, fonte indisponivel/ausente, cobertura, aprovacao, contrato, fuga de caminho, duplicacao, hash de rank e recusa de sobrescrita. Fixtures temporarias preservaram arquivos originais; nenhum teste novo escreve no executor. A suite existente usa mocks para suas chamadas. check e gate planned passaram; plan criou somente proposta.

Controles existentes continuam separados: paused=true, authorized_calls=0, authorized_tokens=0 e quota desconhecida no arquivo local verificado. Nao ha retomada autorizada nem estimativa de dolares. O gate economico ainda falha na meta de renascimentos do terceiro ginasio. Alteracoes desta revisao ficaram locais, sem commit, push ou novo PR.
