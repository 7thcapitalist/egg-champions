# Roteiro: teste em celular fisico e rede lenta

Item do checklist de lancamento: "Teste em celular fisico e rede lenta".
Quem executa: Joao (precisa de celular com Roblox e login). Tempo: cerca de 25 min.
Onde: lugar TESTE, "Egg Champions Test" (place 101737317546942). Nunca producao.

## Antes
- [ ] Celular com app Roblox atualizado. Anote modelo, Android/iOS, versao do app.
- [ ] Entrar na conta, abrir o place TESTE pelo link da pagina do jogo.
- [ ] Ativar o display de desempenho: Roblox Settings > Show Performance Stats (FPS, ping).
- [ ] Gravar a tela do celular durante todo o roteiro (prova).
- [ ] Para rede lenta: Android, modo "limite de dados" ou um hotspot com 3G; iOS, Ajustes > Desenvolvedor > Network Link Conditioner ("3G" e "Very Bad Network"). Alternativa: ficar longe do roteador (1 barra de Wi-Fi) ou usar 4G fraco.

## Bloco A: rede boa (baseline), 8 min
Para cada item marque OK/FALHA e anote o numero pedido.

| # | Verificacao | Esperado | Resultado |
|---|---|---|---|
| A1 | Entrar no jogo | Carrega em ate 30 s, sem erro de script | tempo: |
| A2 | UI cabe na tela | Barra de moedas, menu lateral, meta (goal) e slots de pets visiveis, sem cortar no notch/cantos | |
| A3 | Toque: clicar na tela | Cada toque gera moeda e efeito; nao precisa tocar em lugar especifico | |
| A4 | Tamanho dos botoes | Menu, passes e botao da meta tocaveis de primeira com o dedo (alvo minimo 44 px no codigo) | erros de toque: |
| A5 | Loja de ovos | Abre ao tocar no stand; rolagem com o dedo funciona; comprar choca e mostra o pet | |
| A6 | Pets e Index | Abre, rola, equipar/desequipar funciona | |
| A7 | Rebirth | Tela abre e fecha | |
| A8 | Batalha no Gym 1 | Tela de batalha legivel, botoes tocaveis, resultado aparece | |
| A9 | Portal para outro mundo | Teleporta ao tocar/andar | |
| A10 | Rotacao | Se girar o celular, a UI continua usavel | |
| A11 | FPS | Medir parado, clicando rapido por 20 s, chocando ovo, em batalha | FPS: / / / |
| A12 | Temperatura/bateria | Apos 10 min, aparelho nao esquenta demais | % bateria: |

Meta de FPS: 30 ou mais em todas as situacoes; abaixo de 20 e falha.

## Bloco B: rede lenta, 10 min
Ligar o limitador (3G / Very Bad Network). Anotar ping do display.

| # | Verificacao | Esperado | Resultado |
|---|---|---|---|
| B1 | Entrar no jogo com rede lenta | Entra em ate 90 s, sem tela travada | tempo: |
| B2 | Clicar 30 vezes seguidas | Moedas sobem de forma coerente; ao parar, o total bate com o do servidor (sem "voltar" valores) | |
| B3 | Chocar 3 ovos | Cada choca termina e mostra o pet; sem choca duplicada, sem moeda cobrada sem pet | |
| B4 | Batalha | Inicia e termina; resultado nao some | |
| B5 | Equipar pets | Muda e persiste apos fechar a tela | |
| B6 | Queda de rede de 15 s (modo aviao e voltar) | Jogo volta sem erro, ou reconecta; progresso nao se perde | |
| B7 | Sair e reentrar | Moedas, pets e mundo salvos | |

Falhas a observar: botao que fica "preso", moeda cobrada sem item, pet duplicado, tela vazia, personagem preso.

## O que mandar de volta
1. Video(s) da tela.
2. Preencher as tabelas acima (pode ser foto do roteiro anotado).
3. Modelo do aparelho e tipo de rede usada no Bloco B.

## Criterio de aprovacao
- Todos os itens A2 a A10 e B1 a B7 em OK.
- FPS de 30 ou mais (A11).
- Nenhum prejuizo de progresso (B3, B6, B7).
Se algum falhar, o time abre uma tarefa de correcao por item.

## Observacoes de codigo (para quem corrigir)
- UI usa IgnoreGuiInset e design de 1280 px de largura (`src/client/UI/Theme.luau`, `designWidth = 1280`); em telas estreitas o escalonamento depende de `Main.luau`.
- Servidor decide moedas e choca (CLAUDE.md); a rede lenta so atrasa a resposta. B2 e B3 testam isso.
- Limite do que o time ja checou sem celular: nada. Este roteiro e a primeira verificacao em aparelho real.
