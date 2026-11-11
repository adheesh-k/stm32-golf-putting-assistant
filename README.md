# STM32 Golf Putting Assistant

An automated putting practice machine built as the final project for ESET 349 (Microcontroller Architecture) at Texas A&M. It dispenses golf balls one at a time, detects made putts with an IR sensor in the cup, keeps score on an LCD, and clears the cup with a second motor.

The game logic and all peripheral drivers are written in **ARM Thumb assembly** with direct register access (no HAL for the application code). `main.c` only starts the clock setup and calls `putting_main`.

<!-- TODO: add a photo or demo video of the build here -->

## Hardware

| Part | Notes |
|---|---|
| STM32 Nucleo-F401RE (STM32F401RE, Cortex-M4, 84 MHz) | main controller |
| IR sensor 1 | detects a ball at the dispenser (active low) |
| IR sensor 2 | detects a ball in the cup (active low) |
| Motor 1 + driver | advances one ball from the dispenser |
| Motor 2 + driver | clears the cup after a made putt |
| 16x2 HD44780 LCD with PCF8574 I2C backpack | I2C address 0x27 |

### Pin map

| Signal | Pin |
|---|---|
| IR sensor 1 (dispenser) | PA0 (pull-up) |
| IR sensor 2 (cup) | PA1 (pull-up) |
| Motor 1 control | PB4 |
| Motor 2 control | PA9 |
| I2C1 SCL / SDA (LCD) | PB8 / PB9 (open-drain, AF4) |

## How it works

1. The firmware starts with 8 balls and shows `Remaining` and `Made Putts` on the LCD.
2. A ball detected at IR sensor 1 triggers a short pulse on motor 1 and decrements the remaining count.
3. A ball detected at IR sensor 2 while a ball is in play counts as a made putt, updates the display, waits for the ball to settle, then runs motor 2 to clear the cup.
4. Both sensor inputs are debounced in software (200 ms) and wait for release before re-arming.

## What is implemented in assembly (`Core/Src/main.s`)

- Clock enable and GPIO configuration through RCC and GPIO registers (inputs with pull-ups, push-pull outputs, open-drain alternate function for I2C)
- I2C1 master driver at 100 kHz (polling on SB, ADDR, and BTF flags)
- HD44780 initialization sequence and 4-bit LCD driver over the PCF8574 backpack
- Number-to-ASCII conversion for the display
- Calibrated millisecond busy-wait delay for 84 MHz
- Polling state machine for ball dispense and cup detection

## Build

Generated with STM32CubeMX (`349_Final_Project.ioc`) and built with CMake and the Arm GNU toolchain.

```bash
cmake --preset Debug
cmake --build --preset Debug
```

Flash `build/Debug/349_Final_Project.elf` with STM32CubeProgrammer or OpenOCD.

## Possible improvements

- Replace busy-wait delays with a hardware timer
- Use EXTI interrupts for the IR sensors instead of polling
- Drive the motors with PWM for speed control

## Third-party code

`Drivers/` contains ST's CMSIS and STM32F4xx HAL driver packages under their own licenses (see the license files in each folder).
