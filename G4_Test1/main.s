        AREA |.text|, CODE, READONLY, ALIGN=2
        THUMB
        REQUIRE8
        PRESERVE8

        EXPORT  main

; ---------------- Direcciones del Reference Manual RM0440 ----------------
RCC         EQU     0x40021000
AHB2ENR     EQU     0x4C

GPIOA       EQU     0x48000000      ; potenciometro en PA1
GPIOB       EQU     0x48000400      ; LEDs
MODER       EQU     0x00
ODR         EQU     0x14

ADC2        EQU     0x50000100
ADC_ISR     EQU     0x00
ADC_CR      EQU     0x08
ADC_CFGR    EQU     0x0C
ADC_SMPR1   EQU     0x14
ADC_SQR1    EQU     0x30
ADC_DR      EQU     0x40

ADC12COM    EQU     0x50000300
ADC_CCR     EQU     0x08

; ---------------- LEDs en el puerto B ----------------
; LD1 = PB0, LD2 = PB4, LD3 = PB5, LD4 = PB6
TODOS       EQU     0x00000071      ; (1<<0)|(1<<4)|(1<<5)|(1<<6)

; ---------------- Umbrales del recorrido del potenciometro ----------------
; resolucion de 10 bits: 0 a 1023, cada quinto son 1024/5 = 204.8
UN_QUINTO   EQU     205
DOS_QUINTOS EQU     410
TRES_QUINTOS EQU    614
CUATRO_QUINTOS EQU  819


main
        bl   leds_config
        bl   adc_config

lazo
        bl   adc_read           ; r0 = conversion del ADC
        bl   leds_write
        b    lazo


; ================= Configuracion de los LEDs =================
leds_config
        push {lr}

        ;RCC->AHB2ENR |= (1<<1);   reloj del puerto B
        ldr  r0, =RCC                   ;read
        ldr  r1, [r0,#AHB2ENR]
        movs r2, #0x2                   ;modify
        orrs r1, r1, r2
        str  r1, [r0,#AHB2ENR]          ;write

        ;GPIOB->MODER: PB0, PB4, PB5 y PB6 como salida (01)
        ldr  r0, =GPIOB                 ;read
        ldr  r1, [r0,#MODER]
        ldr  r2, =0x00003F03            ;modify, los dos bits de cada pin
        bics r1, r1, r2
        ldr  r2, =0x00001501            ;el bit de abajo de cada par
        orrs r1, r1, r2
        str  r1, [r0,#MODER]            ;write

        ;GPIOB->ODR &= ~TODOS;   los cuatro LEDs apagados al empezar
        ldr  r1, [r0,#ODR]
        ldr  r2, =TODOS
        bics r1, r1, r2
        str  r1, [r0,#ODR]

        pop  {pc}


; ================= Configuracion del ADC =================
adc_config
        push {lr}

        ;RCC->AHB2ENR |= GPIOAEN | ADC12EN;   relojes del puerto A y del ADC
        ldr  r0, =RCC                   ;read
        ldr  r1, [r0,#AHB2ENR]
        movs r2, #0x1                   ;modify, GPIOAEN, bit 0
        orrs r1, r1, r2
        ldr  r2, =0x00002000            ;ADC12EN, bit 13
        orrs r1, r1, r2
        str  r1, [r0,#AHB2ENR]          ;write

        ;GPIOA->MODER |= (3<<2);   PA1 como entrada analogica (11)
        ldr  r0, =GPIOA                 ;read
        ldr  r1, [r0,#MODER]
        movs r2, #0x0C                  ;modify
        orrs r1, r1, r2
        str  r1, [r0,#MODER]            ;write

        ;ADC2->CR &= ~(1<<29);   salir del modo deep power down (antes de configurar)
        ldr  r0, =ADC2
        ldr  r1, [r0,#ADC_CR]
        ldr  r2, =0x20000000
        bics r1, r1, r2
        str  r1, [r0,#ADC_CR]

        ;ADC2->CR |= (1<<28);   encender el regulador de voltaje del ADC
        ldr  r1, [r0,#ADC_CR]
        ldr  r2, =0x10000000
        orrs r1, r1, r2
        str  r1, [r0,#ADC_CR]

        ;esperar a que el regulador se estabilice
        ldr  r3, =2000
espera_reg
        subs r3, r3, #1
        bne  espera_reg

        ;ADC12_COMMON->CCR |= (3<<16);   reloj del ADC = HCLK/4
        ldr  r2, =ADC12COM
        ldr  r1, [r2,#ADC_CCR]
        ldr  r3, =0x00030000
        orrs r1, r1, r3
        str  r1, [r2,#ADC_CCR]

        ;ADC2->CFGR |= (1<<12)|(1<<3);   OVRMOD y resolucion de 10 bits
        ldr  r1, [r0,#ADC_CFGR]
        ldr  r2, =0x00001008
        orrs r1, r1, r2
        str  r1, [r0,#ADC_CFGR]

        ;ADC2->SQR1 |= (2<<6);   una conversion (L=0) en el canal 2
        ldr  r1, [r0,#ADC_SQR1]
        movs r2, #0x80
        orrs r1, r1, r2
        str  r1, [r0,#ADC_SQR1]

        ;ADC2->SMPR1 |= (7<<6);   tiempo de muestreo largo para el canal 2
        ldr  r1, [r0,#ADC_SMPR1]
        ldr  r2, =0x000001C0
        orrs r1, r1, r2
        str  r1, [r0,#ADC_SMPR1]

        ;ADC2->CR |= (1<<0);   habilitar el ADC
        ldr  r1, [r0,#ADC_CR]
        movs r2, #0x1
        orrs r1, r1, r2
        str  r1, [r0,#ADC_CR]

        ;while(!(ADC2->ISR & ADRDY));   esperar a que el ADC este listo
espera_listo
        ldr  r1, [r0,#ADC_ISR]
        movs r2, #0x1
        ands r1, r1, r2
        beq  espera_listo

        pop  {pc}


; ================= Una conversion, devuelve el dato en r0 =================
adc_read
        push {lr}

        ;ADC2->CR |= (1<<2);   iniciar la conversion
        ldr  r0, =ADC2                  ;read
        ldr  r1, [r0,#ADC_CR]
        movs r2, #0x4                   ;modify
        orrs r1, r1, r2
        str  r1, [r0,#ADC_CR]           ;write

        ;while(!(ADC2->ISR & EOC));   esperar a que termine
espera_fin
        ldr  r1, [r0,#ADC_ISR]
        movs r2, #0x4
        ands r1, r1, r2
        beq  espera_fin

        ;return ADC2->DR;
        ldr  r0, [r0,#ADC_DR]

        pop  {pc}


; ================= Enciende los LEDs segun el dato (r0) =================
leds_write
        push {lr}

        ldr  r1, =GPIOB                 ;read
        ldr  r2, [r1,#ODR]
        ldr  r3, =TODOS                 ;modify, apaga los cuatro
        bics r2, r2, r3

        ldr  r3, =UN_QUINTO             ; 0 a 1/5: todos apagados
        cmp  r0, r3
        blo  escribir
        movs r3, #0x40                  ; 1/5 a 2/5: LD4
        orrs r2, r2, r3

        ldr  r3, =DOS_QUINTOS
        cmp  r0, r3
        blo  escribir
        movs r3, #0x20                  ; 2/5 a 3/5: LD3 y LD4
        orrs r2, r2, r3

        ldr  r3, =TRES_QUINTOS
        cmp  r0, r3
        blo  escribir
        movs r3, #0x10
        orrs r2, r2, r3

        ldr  r3, =CUATRO_QUINTOS
        cmp  r0, r3
        blo  escribir
        movs r3, #0x01
        orrs r2, r2, r3

escribir
        str  r2, [r1,#ODR]              ;write
        pop  {pc}


        AREA    |.ARM.use_no_argv|, DATA, READWRITE, ALIGN=2
        EXPORT  __ARM_use_no_argv
__ARM_use_no_argv
        DCD     1

        end
