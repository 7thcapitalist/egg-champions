# Relatorio de validacao

Data local do usuario: 2026-10-21. Sem IA real, publicacao ou acesso ao Studio.

## Evidencia desta rodada

- Verificacao do worktree mediante aprovacao de terminal: exit0, status limpo,
  branch hq/roblox-protected e Git comum deste repositorio.
- checks.json: baseline com hash correto, uma linha no ledger de quota,
  zero registros/chamadas no journal do executor, autorizacao 2/20000/1p.p.
- guard-local.json: UNKNOWN/exit3 por divergencia da janela de reset.
  Consumo atual 75%, baseline 67%, delta observado 8p.p.; atribuicao desconhecida.
- agents-before.json: quatro agentes inicialmente paused/process, heartbeat off.
- runs-started.json e runs-results.json: tres execucoes reais do Paperclip,
  sem modelos, todas succeeded/exit0. A saida JSON interna e a evidencia dos
  checks; o status succeeded do transporte nao significa release aprovado.
- agents-final.json e task-final.json: estado final dos agentes e ROB-13.

## Execucoes observadas

| Perfil | Run | Duracao | Resultado do script |
| --- | --- | --- | --- |
| Diretor | ddad6614-e2c2-48ae-9e4e-10ca2ed9d22c | 20,558s | Release bloqueado e medicao de quota ausente no ambiente Paperclip |
| Analista | 3ff787e1-862d-46a2-b372-3406202187f4 | 14,172s | Gate de economia exit0, seis alvos atingidos |
| Pesquisa | 96f94eae-3dcd-4ed9-aa20-439ffef5a222 | 2,559s | Evidencia existente sem erros; tendencias novas desconhecidas |

Duracoes acima sao do processo Paperclip, nao de chamadas de IA. Cada script
informou model_calls_requested=0. Modelo efetivo e tokens nao se aplicam a uma
chamada inexistente; nos campos de telemetria permanecem null/desconhecidos.

O Paperclip registrou workspace de fallback administrativo para estes scripts.
Isso nao foi usado para clonar o jogo, contornar negativa ou executar modelos:
os caminhos de leitura sao explicitos e o worker continua exigindo o worktree
hq/ aprovado. O diretor confirmou que essa pasta existe.

## Testes deterministas ja concluidos

A rodada imediatamente anterior executou a suite completa: 125 testes Python
em 69,647s, resultado OK, com fixtures/mocks. Nenhum codigo de executor ou teste
foi modificado nesta ativacao, portanto nao se declara uma nova execucao da
suite nem geracao real como validacao. Os testes cobrem tentativas, timeout,
duplicacao, modelo invalido/divergente, quota desconhecida/insuficiente, ledger,
ancora de baseline, credenciais ausentes no filho e preservacao de trabalho.
Fixtures sao temporarias e nao sobrescrevem policy/ledger/executor de producao.

## Limites da conclusao

As negacoes anteriores foram superadas por aprovacao explicita, nao por bypass.
A ponte esta instalada e tres perfis de scripts funcionam no Paperclip. A
geracao protegida ponta a ponta NAO foi validada: engenheiro pausado, janela
percentual excedida, reset divergente, medicao ausente no runtime e tarefas
do jogo ainda running/blocked. Nenhum desses bloqueios foi marcado como feito.
Politica legada e fontes do Dot preservadas; jogo, builds e sessoes Studio
nao foram modificados por esta ativacao. Relatorios antigos permanecem como
evidencia historica e nao descrevem o estado atual.
