# Relatorio 1: implementacao revisada em 2026-10-20

Producao permanece pausada em factory/executor.json: orcamentos de chamadas
e tokens iguais a zero e quota desconhecida. Sem IA real, publicacao, push ou
interacao com Studio. Nenhum arquivo do jogo, credencial, permissao, cobranca
ou configuracao global foi alterado nesta revisao.

## Brechas encontradas e corrigidas

1. Politica em cache: pausa e reducao de orcamento podiam ficar desatualizadas.
   Agora o arquivo e relido a cada chamada e comparado novamente apos preparar
   a invocacao. Politica alterada nessa preparacao recusa o lancamento. Pausar
   bloqueia a proxima chamada; nao encerra uma chamada ja em andamento.
   Com a pausa ativa, o executor recusa antes de tentar gravar no diretorio Git.
2. Uso parcial: um turno completo seguido de erro, turno aberto, timeout ou
   saida com erro podia manter um total aparentemente medido. Agora o total
   fica desconhecido e bloqueia novas chamadas, preservando turnos conhecidos.
   Eventos duplicados conflitantes tambem deixam a medicao desconhecida.
3. Ledger ausente/truncado: antes podia parecer historico vazio e liberar
   novamente o orcamento. Agora ledger-head.json guarda quantidade de linhas
   e SHA-256. Perda de um dos arquivos, truncamento, divergencia ou queda entre
   gravacoes bloqueia admissao. Nao ha migracao nem reset automatico.
4. Estrutura do ledger: valida identidades inicio/fim, tentativas sequenciais
   ate duas, prazos, duracao, modelo divergente e totais reconciliados com os
   turnos. Conclusao exige a ultima invocacao medida e bem-sucedida da tarefa.
   --finish nao conclui tarefa sem essa prova nem repete tarefa concluida.
5. Reinicio: tentativa do prompt e relatorio podia voltar a 1 enquanto ledger
   registrava 2. Agora os tres usam a tentativa persistente. O prazo menor da
   CLI tambem e persistido; reiniciar nao o amplia. Relogio regressivo bloqueia.

## Controles mantidos

Modelo gpt-6-luna, esforco low, sem fallback no executor; ate duas invocacoes
totais por tarefa, 300 segundos por invocacao e 600 por tarefa por padrao.
Lock atomico compartilhado por worktrees. Orcamento cumulativo entre jogos,
quota com origem identificada e ate 300 segundos, acima do piso configurado.
Parsing, economia, verificacoes e status usam scripts. Contexto inicial e
feedback limitados; executor alternativo e push bloqueados.

Ledger registra tarefa, tentativa, modelo/esforco solicitado, modelo efetivo
quando informado, duracao, status e uso. Total = entrada + saida; cache e
subconjunto da entrada. Ausencias permanecem null; nao ha estimativa de dolares.

Arquivos revisados: factory/tools/executor_policy.py,
factory/tools/run_factory.py, factory/tests/test_executor_policy.py,
factory/tests/test_run_factory.py, factory/README.md e RUN-CODEX.md.
Politica factory/executor.json preservada pausada e com orcamento zero.
Relatorios/evidencias atualizados em factory/reports/.
