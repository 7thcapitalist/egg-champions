# Relatorio 2: validacao e limitacoes revisadas em 2026-10-20

A revisao encontrou divergencias entre as garantias descritas e o codigo
anterior. Elas foram corrigidas e documentadas no relatorio 1. O resultado
historico de 36 testes permanece nos arquivos antigos; a evidencia vigente
desta revisao e executor-review-tests.txt.

## Validacao

49/49 testes aprovados, sendo 40 de politica/executor. Comando:
python -B -m unittest discover -s factory/tests -p 'test_*.py' -v

Os 13 novos testes cobrem uso parcial apos turno completo, timeout com uso
parcial, ledger apagado/truncado, queda antes de atualizar a ancora, registros
inconsistentes, conclusao falsa, duplicata conflitante, prazo curto apos
reinicio, politica relida, reducao de orcamento, pausa durante preparacao,
retomada na tentativa 2, --finish sem medicao e saida com erro. Alguns testes
agrupam mais de um desses cenarios.

Todas as chamadas de IA foram mockadas. Fixtures temporarias ficam no
workspace autorizado; hashes do codigo/configuracao antes e depois iguais.
O teste de encerramento de processos usa apenas processos Python descartaveis.
A primeira passagem desta revisao revelou um mock amplo que tambem interceptava
Git; o mock foi limitado a chamada simulada do executor. A falha e preservada
em executor-review-first-run.txt. Nao houve geracao real ou troca de executor.

Git diff --check passou e nenhum arquivo rastreado de games/ foi alterado.
Status revisto por script: paused=true, authorized_calls=0, authorized_tokens=0,
quota desconhecida e ledger real vazio. A politica nao foi despausada. Studio,
publicacao, credenciais, permissoes e configuracoes globais nao foram tocados.

## Limites que permanecem

- Orcamento de chamadas conta reservas duraveis anteriores ao lancamento,
  inclusive falhas; tokens sao somados do uso completo reportado. Entrada ja
  inclui cache; o total e entrada + saida. Uso parcial nao vira zero nem libera
  novas chamadas. Nao ha conversao em dolares ou em percentual de assinatura.
- O teto de tokens e de admissao: uma chamada pode ultrapassa-lo antes de
  informar o total. Nao existe leitura automatica de quota da assinatura;
  snapshot manual e atestacao do responsavel, nao medicao independente.
- Duas tentativas limitam lancamentos do executor, nao requisicoes/retries
  internos da CLI. Modelo efetivo ausente permanece desconhecido. Nao existe
  fallback no wrapper; roteamento interno nao informado nao e certificado.
- A ancora SHA-256 detecta perda, truncamento e divergencia entre journal e
  ancora. Nao e assinada: remover ambos os arquivos ou reescrever ambos pode
  parecer repositorio novo ou historico valido. Clones independentes nao
  compartilham locks/orcamento. Nao e defesa contra adulteracao deliberada.
- Flags de contexto nao sao teto absoluto e compactacao pode consumir IA.
  Checks tem timeout separado de 600 segundos por comando; limpeza pode
  acrescentar tempo. Pausar impede novas chamadas, sem cancelar uma em curso.
- Nenhuma chamada real certificou opcoes desta instalacao. Nao foi feita nova
  consulta negada a CLI nem nova enumeracao de processos. Processos externos
  preexistentes nao foram certificados como parados.

Evidencias: executor-review-tests.txt e executor-status.json. Producao permanece
pausada, aguardando revisao humana; nenhuma retomada foi executada.
