<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# Como verificar que está tudo funcionando

Guia em português direto. Sem precisar entender SystemVerilog.

## O jeito mais fácil — olhar o badge no GitHub

Vá em https://github.com/popsolutions/MAST. No topo do README aparece um
badge:

- **Verde "ci passing"** = todos os 15 testes de hardware passaram no
  último commit. Pode dormir tranquilo.
- **Vermelho "ci failing"** = algum teste quebrou. Algo está errado e
  precisa ser olhado antes de mais código entrar.

O badge atualiza automaticamente a cada commit. Se o último commit é
verde, o estado da árvore está saudável.

## Se quiser confirmar localmente

Basta uma vez rodar o setup:

```bash
~/.pyenv/versions/3.12.10/bin/python3 -m venv ~/Projects/pop.coop/MAST/verif/.venv
source ~/Projects/pop.coop/MAST/verif/.venv/bin/activate
pip install cocotb cocotb-bus pytest
deactivate
```

Depois, sempre que quiser checar:

```bash
source ~/Projects/pop.coop/MAST/verif/.venv/bin/activate

cd ~/Projects/pop.coop/MAST/verif/axi4_mem_model && make
cd ../axi4_master_simple                            && make
cd ../core_axi4_adapter                             && make

deactivate
```

Cada um dos 3 comandos faz um monte de simulação rolar e termina com uma
tabela. **O que importa olhar:**

```
** TESTS=5 PASS=5 FAIL=0 SKIP=0 **
```

- Se `FAIL=0` em todos os 3, está tudo no lugar.
- Se aparecer `FAIL>0` em algum, alguma coisa está quebrada — me chama,
  não tente arrumar.

## Para ver visualmente o que aconteceu

Roda com `WAVES=1` e abre o ficheiro de waves no GTKWave:

```bash
cd ~/Projects/pop.coop/MAST/verif/axi4_mem_model
make WAVES=1
gtkwave sim_build/dump.vcd
```

Isso mostra cada sinal mudando ao longo do tempo. É como ver o circuito
fazendo o trabalho — útil quando algo está errado e quero te mostrar
"olha, aqui faltou um clock", mas opcional pra rotina.

## Que testes existem hoje

Três directórios em `verif/`, um por módulo de hardware verificado:

| Módulo | Testes | O que cada um prova |
|---|---|---|
| `axi4_mem_model` | 5 | A memória responde reads/writes corretamente, rejeita pedidos fora do perfil. |
| `axi4_master_simple` | 5 | O lado mestre converte pedidos simples em transações AXI4. |
| `core_axi4_adapter` | 5 | A ponte entre o RISC-V (palavras de 32-bit) e o barramento AXI4 (linhas de cache de 256-bit) preserva os dados. |

**Total: 15 testes**, todos passando atualmente.

## E sobre o que ainda não tem teste

Se um arquivo de RTL está em `src/` mas **não tem** uma pasta correspondente
em `verif/`, ele ainda não foi verificado. A regra do projeto é: nenhuma
mudança em RTL entra sem testes — então isso só acontece em código herdado
do upstream VeriGPU, não em código nosso.

Para checar quais módulos PopSolutions estão sem teste:

```bash
ls /home/navigator/Projects/pop.coop/MAST/src/popsolutions/axi4/
ls /home/navigator/Projects/pop.coop/MAST/verif/
```

Se aparecer algum `.sv` em `src/popsolutions/axi4/` que não tem pasta com
o mesmo nome em `verif/`, é dívida técnica que precisa ser fechada.

(Hoje está tudo coberto.)
