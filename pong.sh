#!/bin/sh
avr-gcc -mmcu=attiny45 -mmcu=attiny45 -Wall -gdwarf-2 -Os -std=gnu99 -funsigned-char -funsigned-bitfields -fpack-struct -fshort-enums -MD -MP -MT pong.o -MF pong.o.d  -x assembler-with-cpp -Wa,-gdwarf2 -c pong.S tables.S
avr-gcc -mmcu=attiny45 -Wl,-Map=pong.map pong.o tables.o -o pong.elf
avr-objcopy -O ihex -R .eeprom -R .fuse -R .lock -R .signature pong.elf pong.hex
avr-objcopy -j .eeprom --set-section-flags=.eeprom="alloc,load" --change-section-lma .eeprom=0 --no-change-warnings -O ihex pong.elf pong.eep || exit 0
avr-size -C --mcu=attiny45 pong.elf
rm *.o
rm *.o.d
rm pong.eep
rm pong.elf
rm pong.map
