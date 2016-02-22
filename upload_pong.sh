#!/bin/sh
[ -e "/dev/tty.usbserial-A8008VmU" ] && PORT=/dev/tty.usbserial-A8008VmU || PORT=/dev/ttyUSB0
avrdude -F -P $PORT -p attiny45 -c avrisp -b 19200 -U flash:w:pong.hex
# fuses
#avrdude -F -P $PORT -p attiny45 -c avrisp -Ulfuse:w:0xce:m -Uhfuse:w:0xdf:m -Uefuse:w:0xff:m
# WARNING: fuses with PB5 as I/O port
#avrdude -F -P $PORT -p attiny45 -c avrisp -b 19200 -U flash:w:pong.hex -Ulfuse:w:0xce:m -Uhfuse:w:0x5f:m -Uefuse:w:0xff:m
