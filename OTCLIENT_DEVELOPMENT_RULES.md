Module Controller System — Regras Oficiais

Este documento define as regras obrigatórias para qualquer IA, script ou desenvolvedor recriar módulos usando o Module Controller System.

O objetivo é garantir:

ciclo de vida seguro

zero vazamento de eventos

zero estado zumbi

UI previsível

módulos descartáveis sem efeitos colaterais

1. Princípio Fundamental

Todo módulo DEVE ser controlado por um Controller.

Se algo não tem dono claro, ciclo de vida claro e ponto de destruição claro, não pode existir.

2. Controller é Obrigatório

Todo módulo DEVE usar Controller:new()

Não é permitido lógica solta em init.lua

Não é permitido módulo sem ciclo de vida

Ciclo de vida obrigatório

onInit

onGameStart

onGameEnd

onTerminate

3. Registro de Eventos (Regra Crítica)
Proibido

connect(...)

disconnect(...)

eventos registrados fora do controller

Obrigatório

Todos os eventos DEVEM ser registrados via:

controller:registerEvents(obj, callbacks)

Garantias

Eventos morrem junto com o controller

Nenhum callback pode sobreviver ao terminate

4. Timers e Schedulers
Proibido

timers globais

scheduleEvent direto

timers anônimos

Obrigatório

Todo timer DEVE usar:

controller:scheduleEvent(fn, delay, 'nomeUnico')

Regras

Todo timer deve ser nomeado

Todo timer deve morrer no terminate

Timers recursivos só são permitidos se forem controlados pelo controller

5. UI e Widgets
Regras

UI SÓ pode ser acessada via controller.ui

É proibido cache global de widgets

É proibido buscar widgets fora do controller

Proibido

g_ui.getWidgetById

referências globais para widgets internos

6. Destruição de Widgets
Proibido

widget:destroy() para widgets pertencentes ao controller

Permitido

destruir apenas widgets externos ao controller (ex: ícones de TopMenu)

7. Estado do Módulo
Regras

Estado lógico deve ser isolado

Estado visual nunca deve conter lógica

Exemplo correto

variável lógica → função de refresh visual

Proibido

misturar cálculo com atualização visual

8. Callbacks e Segurança

Todo callback DEVE assumir que:

player pode não existir

UI pode estar invisível

widgets podem estar em transição

Nenhum callback pode assumir estado válido sem validação.

9. GameStart e GameEnd
onGameStart

Pode:

registrar eventos

inicializar estado

carregar dados

onGameEnd

Pode:

salvar dados

limpar estado transitório

Proibido

criar UI nova

lógica visual pesada

10. Funções Globais
Regras

Funções globais NÃO podem conter estado

Funções globais NÃO podem registrar eventos

Funções globais APENAS delegam chamadas ao controller

11. Teclas e Input
Regras

Teclas só podem ser bindadas enquanto o estado exigir

Teclas DEVEM ser desbindadas ao sair do estado

Proibido

binds permanentes

binds fora do ciclo do controller

12. Regra Suprema

Se não estiver absolutamente claro quando algo nasce e quando algo morre, isso não pode existir.

13. Validação Final

Todo módulo deve poder responder claramente:

Quem criou isso?

Onde isso vive?

Quando isso morre?

Se alguma resposta for incerta, o módulo está incorreto.