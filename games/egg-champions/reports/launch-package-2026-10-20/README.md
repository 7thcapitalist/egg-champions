# Avanço de lançamento: 2026-10-20

Jogo ainda não aprovado para lançamento. Nenhum upload, publicação, compra,
execução da factory ou mudança de orçamento ocorreu nesta rodada.

## Entregas

- marketing/: ícone e duas thumbnails originais, descrições em inglês e
  português, nome preservado, referências, revisão crítica e manifesto SHA-256.
  Ícone e thumbnail de hatch receberam versões v2 após a inspeção: orelhas
  inteiras, texto fora do rodapé e cenário simplificado. Cinco versões de imagem
  preservadas, três candidatas selecionadas. Cada PNG tem menos de 3 MB.
- Battle.luau: subtítulo do golpe básico reduzido para "Always ready" para
  caber em celulares sem perder a informação de disponibilidade.
- Task 53 registrada no índice, com revisão de arte e publicação pendentes.
- Build normal separado: build/launch-package-2026-10-20.rbxl. O build anterior
  e as mudanças preexistentes do usuário foram preservados.

## Verificação

109 testes Python, 882 testes Luau e seis autotestes passaram. Selene sem
findings, StyLua e Rojo passaram. Gates spec_parsed, economy_tuned e planned
passaram. O planned gate reconhece 53 tarefas sem ciclo. Nenhuma tarefa nova
foi marcada concluída nem um stage de lançamento promovido.

A saída Python contém falhas e commits de fixtures sintéticas. O resultado final
da suite foi OK; não houve execução de agente ou commit real por essas fixtures.

## QA observado

Sessão beta-local.rbxl, PlaceId 0, BetaQA e PlaytestNoPasses ativos. Somente a
cópia de QA recebeu a alteração de texto em memória. Perfil temporário recebeu
três Emberkits e taxa paga para acessar o gym 1. Esses números são condições de
fixture, não mudanças na economia. A sessão já existia com fontes anteriores:
o resultado é verificação parcial da apresentação, não evidência do novo build
normal nem certificação da sua economia, save ou servidor.

Landscape solicitado 720x335, viewport efetivo 720x335.200012. Painéis de HP e
controles visíveis, com criaturas no centro. Em override temporário de retrato
320x720, "Always ready", nomes dos golpes, cooldown e HP informaram TextFits=true.
Botões 144x58, Give Up 296x44. Clique real no ataque passou do turno 1 para 2;
HP exibido depois: Emberkit 62/98, líder 119/146.

O log longo continua com TextFits=false e a última frase não aparece inteira na
janela pequena. Isso impede aprovação completa. Capturas foram inspecionadas e
exibidas na conversa, sem arquivo local vinculado. Não usar este relatório como
substituto do quality_review. O shipping continua LandscapeSensor; override
Sensor existiu apenas no PlayerGui do playtest. Play parado e simulador restaurado.
A única edição de Source nessa sessão de QA foi revertida ao texto original ao
final, preservando a correção no repositório. Nenhum arquivo Studio foi salvo.

Duas tentativas de consultar módulos State/Profiles pelo contexto de comandos
não acessaram o cache da sessão: State era nil e Profiles informou unloaded.
Foram usados drivers descartáveis Script/LocalScript no runtime de QA para
consultar o perfil temporário e abrir a interface normal. Nenhuma guarda do
jogo foi relaxada. Drivers e perfil desapareceram ao parar o teste.

## Pendências por impacto

1. Corrigir/revisar a apresentação do log longo e concluir a matriz mobile,
   incluindo entrada real por toque e aparelho físico sob rede lenta.
2. Revisar mundos, animação e modelos atuais com capturas arquivadas e notas
   visuais >=4. Finalizar margens/exportação das artes e preview no Dashboard.
3. Publicar candidato autorizado no TEST, reabrir e comparar fontes da versão.
4. Observar save/rejoin com DataStore real e disconnect/rejoin multiplayer.
5. Jogar gyms 2/3 sem equipe semeada ou passes e registrar tempo e rebirths.
6. Validar compras e efeitos de passes somente com autorização própria.
7. Reassociar manifesto de release ao novo candidato, preencher evidências reais
   e executar gates worlds/playtested/published_test.

O manifesto existente fica desatualizado após a mudança de Battle.luau. O novo
hash e build estão em checks.json; evidência antiga não foi transferida para
fazê-los passar. Os três gates de release bloqueiam corretamente. A política
do executor continua paused=true e sem orçamento autorizado. Testes do código
da factory não significam que o fluxo completo produziu um jogo lançado.

Comparação com jogos em alta permanece objetivo de produto. Não há evidência
de equivalência de retenção, performance, satisfação ou alcance. A consulta ao
Charts não revelou um ranking atual confiável; as descrições oficiais e a
documentação de mídia foram usadas apenas para orientar o pacote.
