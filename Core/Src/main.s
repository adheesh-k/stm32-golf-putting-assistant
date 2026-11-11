    .syntax unified
    .cpu cortex-m4
    .thumb

@ clock registers
.equ RCC_AHB1ENR,    0x40023830
.equ RCC_APB1ENR,    RCC_AHB1ENR + 0x10

@ GPIOA
.equ GPIOA_MODER,    0x40020000
.equ GPIOA_PUPDR,    GPIOA_MODER + 0x0C
.equ GPIOA_IDR,      GPIOA_MODER + 0x10
.equ GPIOA_BSRR,     GPIOA_MODER + 0x18

@ GPIOB
.equ GPIOB_MODER,    0x40020400
.equ GPIOB_OTYPER,   GPIOB_MODER + 0x04
.equ GPIOB_OSPEEDR,  GPIOB_MODER + 0x08
.equ GPIOB_PUPDR,    GPIOB_MODER + 0x0C
.equ GPIOB_BSRR,     GPIOB_MODER + 0x18
.equ GPIOB_AFRH,     GPIOB_MODER + 0x24

@ I2C1
.equ I2C1_CR1,       0x40005400
.equ I2C1_CR2,       I2C1_CR1 + 0x04
.equ I2C1_DR,        I2C1_CR1 + 0x10
.equ I2C1_SR1,       I2C1_CR1 + 0x14
.equ I2C1_SR2,       I2C1_CR1 + 0x18
.equ I2C1_CCR,       I2C1_CR1 + 0x1C
.equ I2C1_TRISE,     I2C1_CR1 + 0x20

@ LCD (PCF8574 backpack, addr 0x27)
.equ LCD_ADDR,       0x27
.equ LCD_BL,         0x08        @ backlight bit
.equ LCD_EN,         0x04        @ enable strobe
.equ LCD_RS,         0x01        @ register select

@ motor pins
.equ M1_IA_BIT,      4           @ PB4
.equ M2_IA_BIT,      9           @ PA9

@ timing
.equ MS_COUNT,       42000       @ inner loop count for ~1ms at 84MHz
.equ MOTOR_RUN_MS,   10
.equ MOTOR2_RUN_MS,  300
.equ DEBOUNCE_MS,    200
.equ BALL_START,     8

    .section .data
balls_remaining:  .word BALL_START
putts_made:       .word 0
ball_in_play:     .word 0        @ 1 = ball has been dispensed
str_balls:        .asciz "Remaining: "
str_putts:        .asciz "Made Putts: "

    .section .text

    .global putting_main
    .type   putting_main, %function
putting_main:
    STMDB sp!, {r4-r7, lr}

    BL   setup_pins
    BL   setup_i2c
    BL   setup_lcd
    BL   update_display          @ show starting state

game_loop:
    @ check IR1 (PA0) - active low, so low = ball detected
    LDR  r0, =GPIOA_IDR
    LDR  r1, [r0]
    TST  r1, #(1 << 0)
    BNE  check_cup               @ pin high = nothing there

    LDR  r0, =balls_remaining
    LDR  r1, [r0]
    CMP  r1, #0
    BEQ  check_cup               @ out of balls, skip

    SUBS r1, r1, #1
    STR  r1, [r0]

    LDR  r0, =ball_in_play
    MOV  r1, #1
    STR  r1, [r0]

    BL   dispense_ball
    BL   update_display

    LDR  r0, =1000               @ wait before watching IR1 again
    BL   wait_ms

dispenser_released:
    LDR  r0, =GPIOA_IDR
    LDR  r1, [r0]
    TST  r1, #(1 << 0)
    BEQ  dispenser_released      @ wait for pin to go high
    LDR  r0, =DEBOUNCE_MS
    BL   wait_ms

check_cup:
    @ check IR2 (PA1) - active low
    LDR  r0, =GPIOA_IDR
    LDR  r1, [r0]
    TST  r1, #(1 << 1)
    BNE  game_loop               @ nothing in cup

    LDR  r0, =ball_in_play
    LDR  r1, [r0]
    CMP  r1, #0
    BEQ  cup_released            @ no ball was in play, ignore

    LDR  r0, =putts_made
    LDR  r1, [r0]
    CMP  r1, #BALL_START
    BEQ  ball_done               @ already at max, don't increment

    ADDS r1, r1, #1
    STR  r1, [r0]
    BL   update_display
    BL   clear_cup

ball_done:
    LDR  r0, =ball_in_play
    MOV  r1, #0
    STR  r1, [r0]

    LDR  r0, =500
    BL   wait_ms

cup_released:
    LDR  r0, =GPIOA_IDR
    LDR  r1, [r0]
    TST  r1, #(1 << 1)
    BEQ  cup_released
    LDR  r0, =DEBOUNCE_MS
    BL   wait_ms

    B    game_loop

    LDMIA sp!, {r4-r7, pc}
    .size putting_main, .-putting_main

    .type setup_pins, %function
setup_pins:
    STMDB sp!, {r0-r3, lr}

    @ enable GPIOA and GPIOB clocks
    LDR  r0, =RCC_AHB1ENR
    LDR  r1, [r0]
    ORR  r1, r1, #(1 << 0) | (1 << 1)
    STR  r1, [r0]

    @ PA0, PA1 as input
    LDR  r0, =GPIOA_MODER
    LDR  r1, [r0]
    MVN  r2, #(0xF)
    AND  r1, r1, r2
    STR  r1, [r0]

    @ pull-up on PA0 and PA1 (IR sensors are active low)
    LDR  r0, =GPIOA_PUPDR
    LDR  r1, [r0]
    MVN  r2, #(0xF)
    AND  r1, r1, r2
    ORR  r1, r1, #(0x5)
    STR  r1, [r0]

    @ PA9, PA10 as output (motor 2)
    LDR  r0, =GPIOA_MODER
    LDR  r1, [r0]
    MVN  r2, #(3 << 18)
    AND  r1, r1, r2
    ORR  r1, r1, #(1 << 18)
    MVN  r2, #(3 << 20)
    AND  r1, r1, r2
    ORR  r1, r1, #(1 << 20)
    STR  r1, [r0]

    @ PB4, PB5 as output (motor 1), PB8, PB9 as AF (I2C1)
    LDR  r0, =GPIOB_MODER
    LDR  r1, [r0]
    MVN  r2, #(3 << 8)
    AND  r1, r1, r2
    ORR  r1, r1, #(1 << 8)
    MVN  r2, #(3 << 10)
    AND  r1, r1, r2
    ORR  r1, r1, #(1 << 10)
    MVN  r2, #(3 << 16)
    AND  r1, r1, r2
    ORR  r1, r1, #(2 << 16)
    MVN  r2, #(3 << 18)
    AND  r1, r1, r2
    ORR  r1, r1, #(2 << 18)
    STR  r1, [r0]

    @ PB8, PB9 open-drain (required for I2C)
    LDR  r0, =GPIOB_OTYPER
    LDR  r1, [r0]
    ORR  r1, r1, #(1 << 8) | (1 << 9)
    STR  r1, [r0]

    @ high speed for I2C lines
    LDR  r0, =GPIOB_OSPEEDR
    LDR  r1, [r0]
    ORR  r1, r1, #(3 << 16) | (3 << 18)
    STR  r1, [r0]

    @ pull-up on PB8, PB9
    LDR  r0, =GPIOB_PUPDR
    LDR  r1, [r0]
    MVN  r2, #(0xF << 16)
    AND  r1, r1, r2
    ORR  r1, r1, #(1 << 16) | (1 << 18)
    STR  r1, [r0]

    @ AF4 = I2C1 on PB8, PB9
    LDR  r0, =GPIOB_AFRH
    LDR  r1, [r0]
    MVN  r2, #(0xFF)
    AND  r1, r1, r2
    ORR  r1, r1, #(4 << 0) | (4 << 4)
    STR  r1, [r0]

    @ drive motor pins low initially
    LDR  r0, =GPIOB_BSRR
    LDR  r1, =(1<<20)|(1<<21)
    STR  r1, [r0]
    LDR  r0, =GPIOA_BSRR
    LDR  r1, =(1<<25)|(1<<26)
    STR  r1, [r0]

    LDMIA sp!, {r0-r3, pc}
    .size setup_pins, .-setup_pins

    .type setup_i2c, %function
setup_i2c:
    STMDB sp!, {r0-r3, lr}

    @ enable I2C1 clock
    LDR  r0, =RCC_APB1ENR
    LDR  r1, [r0]
    ORR  r1, r1, #(1 << 21)
    STR  r1, [r0]

    @ reset then re-enable I2C1
    LDR  r0, =I2C1_CR1
    MOV  r1, #(1 << 15)
    STR  r1, [r0]
    MOV  r1, #0
    STR  r1, [r0]

    LDR  r0, =I2C1_CR2
    MOV  r1, #42                 @ APB1 = 42MHz
    STR  r1, [r0]

    LDR  r0, =I2C1_CCR
    MOV  r1, #210                @ 100kHz: 42MHz / (2 * 210)
    STR  r1, [r0]

    LDR  r0, =I2C1_TRISE
    MOV  r1, #43                 @ max rise time for 100kHz
    STR  r1, [r0]

    LDR  r0, =I2C1_CR1
    MOV  r1, #1                  @ PE bit, enable peripheral
    STR  r1, [r0]

    LDMIA sp!, {r0-r3, pc}
    .size setup_i2c, .-setup_i2c

@ r0 = device address, r1 = byte to send
    .type i2c_send, %function
i2c_send:
    STMDB sp!, {r2-r4, lr}
    MOV  r4, r1

    @ generate START
    LDR  r2, =I2C1_CR1
    LDR  r3, [r2]
    ORR  r3, r3, #(1 << 8)
    STR  r3, [r2]

1:  LDR  r2, =I2C1_SR1          @ wait for SB (start sent)
    LDR  r3, [r2]
    TST  r3, #1
    BEQ  1b

    LDR  r2, =I2C1_DR
    LSL  r3, r0, #1              @ address shifted left, bit0=0 for write
    STR  r3, [r2]

2:  LDR  r2, =I2C1_SR1          @ wait for ADDR ack
    LDR  r3, [r2]
    TST  r3, #(1 << 1)
    BEQ  2b
    LDR  r2, =I2C1_SR2          @ reading SR2 clears ADDR flag
    LDR  r3, [r2]

    LDR  r2, =I2C1_DR
    STR  r4, [r2]                @ send data byte

3:  LDR  r2, =I2C1_SR1          @ wait for BTF (transfer done)
    LDR  r3, [r2]
    TST  r3, #(1 << 2)
    BEQ  3b

    @ generate STOP
    LDR  r2, =I2C1_CR1
    LDR  r3, [r2]
    ORR  r3, r3, #(1 << 9)
    STR  r3, [r2]

    LDMIA sp!, {r2-r4, pc}
    .size i2c_send, .-i2c_send

@ toggles EN low->high->low to latch data into LCD
    .type lcd_strobe, %function
lcd_strobe:
    STMDB sp!, {r1, lr}

    MVN  r1, #LCD_EN             @ EN low
    AND  r1, r0, r1
    STMDB sp!, {r0}
    MOV  r0, #LCD_ADDR
    BL   i2c_send
    LDMIA sp!, {r0}

    ORR  r1, r0, #LCD_EN         @ EN high
    STMDB sp!, {r0}
    MOV  r0, #LCD_ADDR
    BL   i2c_send
    LDMIA sp!, {r0}

    MVN  r1, #LCD_EN             @ EN low again
    AND  r1, r0, r1
    STMDB sp!, {r0}
    MOV  r0, #LCD_ADDR
    BL   i2c_send
    MOV  r0, #2
    BL   wait_ms
    LDMIA sp!, {r0}

    LDMIA sp!, {r1, pc}
    .size lcd_strobe, .-lcd_strobe

@ r0 = byte (upper nibble used), r1 = RS flag
    .type lcd_4bit, %function
lcd_4bit:
    STMDB sp!, {r2, lr}
    AND  r2, r0, #0xF0           @ keep upper nibble only
    ORR  r2, r2, #LCD_BL
    ORR  r2, r2, r1
    MOV  r0, r2
    BL   lcd_strobe
    LDMIA sp!, {r2, pc}
    .size lcd_4bit, .-lcd_4bit

@ send full command byte (RS=0), high nibble first
    .global lcd_command
    .type   lcd_command, %function
lcd_command:
    STMDB sp!, {r4, lr}
    MOV  r4, r0
    MOV  r1, #0
    BL   lcd_4bit
    LSL  r0, r4, #4              @ shift low nibble up
    MOV  r1, #0
    BL   lcd_4bit
    LDMIA sp!, {r4, pc}
    .size lcd_command, .-lcd_command

@ send character byte (RS=1)
    .global lcd_char
    .type   lcd_char, %function
lcd_char:
    STMDB sp!, {r4, lr}
    MOV  r4, r0
    MOV  r1, #LCD_RS
    BL   lcd_4bit
    LSL  r0, r4, #4
    MOV  r1, #LCD_RS
    BL   lcd_4bit
    LDMIA sp!, {r4, pc}
    .size lcd_char, .-lcd_char

@ HD44780 power-on init sequence
    .type setup_lcd, %function
setup_lcd:
    STMDB sp!, {r0-r1, lr}

    MOV  r0, #100
    BL   wait_ms

    @ three 0x30 resets per datasheet
    MOV  r0, #0x30
    MOV  r1, #0
    BL   lcd_4bit
    MOV  r0, #10
    BL   wait_ms

    MOV  r0, #0x30
    MOV  r1, #0
    BL   lcd_4bit
    MOV  r0, #1
    BL   wait_ms

    MOV  r0, #0x30
    MOV  r1, #0
    BL   lcd_4bit
    MOV  r0, #1
    BL   wait_ms

    @ switch to 4-bit mode
    MOV  r0, #0x20
    MOV  r1, #0
    BL   lcd_4bit
    MOV  r0, #1
    BL   wait_ms

    MOV  r0, #0x28               @ 2 lines, 5x8 font
    BL   lcd_command
    MOV  r0, #1
    BL   wait_ms

    MOV  r0, #0x08               @ display off
    BL   lcd_command
    MOV  r0, #1
    BL   wait_ms

    MOV  r0, #0x01               @ clear display
    BL   lcd_command
    MOV  r0, #5
    BL   wait_ms

    MOV  r0, #0x06               @ entry mode: cursor moves right
    BL   lcd_command
    MOV  r0, #1
    BL   wait_ms

    MOV  r0, #0x0C               @ display on, cursor off
    BL   lcd_command
    MOV  r0, #1
    BL   wait_ms

    LDMIA sp!, {r0-r1, pc}
    .size setup_lcd, .-setup_lcd

    .type lcd_print, %function
lcd_print:
    STMDB sp!, {r4, lr}
    MOV  r4, r0
1:  LDRB r0, [r4], #1           @ load byte, post-increment
    CMP  r0, #0
    BEQ  2f                      @ null terminator, done
    BL   lcd_char
    B    1b
2:  LDMIA sp!, {r4, pc}
    .size lcd_print, .-lcd_print

    .type lcd_digit, %function
lcd_digit:
    STMDB sp!, {lr}
    ADD  r0, r0, #'0'            @ convert to ASCII
    BL   lcd_char
    LDMIA sp!, {pc}
    .size lcd_digit, .-lcd_digit

    .type lcd_number, %function
lcd_number:
    STMDB sp!, {r4, r5, lr}
    MOV  r4, r0
    CMP  r4, #10
    BLT  1f                      @ single digit, skip tens
    MOV  r5, #0
2:  SUBS r4, r4, #10
    BLT  3f
    ADD  r5, r5, #1
    B    2b
3:  ADD  r4, r4, #10
    MOV  r0, r5
    BL   lcd_digit               @ tens digit
1:  MOV  r0, r4
    BL   lcd_digit               @ ones digit
    LDMIA sp!, {r4, r5, pc}
    .size lcd_number, .-lcd_number

    .type update_display, %function
update_display:
    STMDB sp!, {r4-r5, lr}

    MOV  r0, #0x80               @ row 1
    BL   lcd_command
    LDR  r0, =str_balls
    BL   lcd_print
    LDR  r4, =balls_remaining
    LDR  r0, [r4]
    BL   lcd_number

    MOV  r0, #0xC0               @ row 2
    BL   lcd_command
    LDR  r0, =str_putts
    BL   lcd_print
    LDR  r4, =putts_made
    LDR  r0, [r4]
    BL   lcd_number

    LDMIA sp!, {r4-r5, pc}
    .size update_display, .-update_display

@ brief pulse on PB4 to advance one ball
    .type dispense_ball, %function
dispense_ball:
    STMDB sp!, {r0-r2, lr}

    LDR  r0, =GPIOB_BSRR
    MOV  r1, #(1 << M1_IA_BIT)
    ORR  r1, r1, #(1 << (M1_IA_BIT + 1 + 16))
    STR  r1, [r0]

    LDR  r0, =MOTOR_RUN_MS
    BL   wait_ms

    LDR  r0, =GPIOB_BSRR        @ stop motor
    MOV  r1, #(1 << (M1_IA_BIT + 16))
    STR  r1, [r0]

    LDMIA sp!, {r0-r2, pc}
    .size dispense_ball, .-dispense_ball

@ wait 1s for ball to settle, then run PA9 to clear cup
    .type clear_cup, %function
clear_cup:
    STMDB sp!, {r0-r2, lr}

    LDR  r0, =1000
    BL   wait_ms

    LDR  r0, =GPIOA_BSRR
    MOV  r1, #(1 << M2_IA_BIT)
    ORR  r1, r1, #(1 << (M2_IA_BIT + 1 + 16))
    STR  r1, [r0]

    LDR  r0, =MOTOR2_RUN_MS
    BL   wait_ms

    LDR  r0, =GPIOA_BSRR        @ stop motor
    MOV  r1, #(1 << (M2_IA_BIT + 16))
    STR  r1, [r0]

    LDMIA sp!, {r0-r2, pc}
    .size clear_cup, .-clear_cup

@ r0 = milliseconds to wait
    .type wait_ms, %function
wait_ms:
    STMDB sp!, {r1-r2, lr}
1:  CMP  r0, #0
    BEQ  2f
    LDR  r1, =MS_COUNT
3:  SUBS r1, r1, #1             @ inner busy-wait loop
    BNE  3b
    SUBS r0, r0, #1
    B    1b
2:  LDMIA sp!, {r1-r2, pc}
    .size wait_ms, .-wait_ms
