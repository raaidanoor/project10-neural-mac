# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import os
from pathlib import Path
import sys

import cocotb
from cocotb.triggers import Timer

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from golden_model import calculate

CLOCK_PERIOD_NS = int(os.environ.get("CLOCK_PERIOD_NS", "20"))

READY, BUSY, DONE, ERROR, BYTE_VALID, OVERFLOW = (1 << bit for bit in range(6))
WRITE, START, STREAM, FINAL, READ = 0x04, 0x25, 0x24, 0x26, 0x44
RELEASED = "ZZZZZZZZ"


class Host:
    def __init__(self, dut):
        self.dut = dut
        dut.clk.value = 0
        dut.rst_n.value = 1
        dut.ena.value = 1
        dut.ui_in.value = 0
        dut.host_drives.value = 0
        dut.host_data.value = 0

    def check(self, status, data=None, *, chip_drives=False):
        dut = self.dut
        actual_status = int(dut.uo_out.value)
        assert actual_status == status, f"status {actual_status:02X}, expected {status:02X}"
        oe = int(dut.uio_oe.value)
        assert oe == (0xFF if chip_drives else 0), f"unexpected chip OE {oe:02X}"
        assert not (oe and int(dut.host_drives.value)), "host and chip both drive the bus"
        assert int(dut.uio_out.value) == (data if chip_drives else 0)
        expected_bus = RELEASED if data is None else f"{data & 0xFF:08b}"
        actual_bus = str(dut.shared_bus.value).upper()
        assert actual_bus == expected_bus, f"bus {actual_bus}, expected {expected_bus}"

    async def cycle(self, command=0, data=None, *, status=READY, read_byte=None, sample=None):
        dut = self.dut
        dut.clk.value = 0
        dut.ui_in.value = command
        dut.host_drives.value = data is not None
        dut.host_data.value = 0 if data is None else data & 0xFF
        await Timer(CLOCK_PERIOD_NS / 2, unit="ns")
        assert not (int(dut.uio_oe.value) and data is not None), "bus contention before rising edge"
        if sample is not None:
            sample_status, sample_byte = sample
            self.check(sample_status, sample_byte, chip_drives=sample_byte is not None)
        dut.clk.value = 1
        await Timer(CLOCK_PERIOD_NS / 2, unit="ns")
        if read_byte is None:
            self.check(status, None if data is None else data & 0xFF)
        else:
            self.check(status, read_byte, chip_drives=True)

    async def reset(self):
        self.dut.clk.value = 0
        self.dut.host_drives.value = 0
        await Timer(1, unit="ns")
        self.dut.rst_n.value = 0
        await Timer(2, unit="ns")
        self.check(0)
        await self.cycle(START, status=0)
        self.dut.rst_n.value = 1
        await Timer(2, unit="ns")
        self.check(READY)

    async def write(self, slot, weight, *, status=READY):
        await self.cycle(WRITE, slot, status=status)
        await self.cycle(WRITE, weight, status=status)

    async def stream(self, codebook, pairs, width):
        status = READY
        for position, (index, feature) in enumerate(pairs, 1):
            await self.cycle(STREAM, index, status=status)
            result = calculate(codebook, pairs[:position], width)
            status = READY | (OVERFLOW if result.overflow else 0)
            if position == len(pairs):
                await self.cycle(FINAL, feature, status=status | DONE)
            else:
                await self.cycle(STREAM, feature, status=status)
        return result

    async def read(self, result, *, error=False):
        flags = DONE | (OVERFLOW if result.overflow else 0) | (ERROR if error else 0)
        handoff = flags | BUSY
        reading = handoff | BYTE_VALID

        # Release UIO from the request through the end of the return handoff.
        await self.cycle(READ, status=handoff)
        previous = (handoff, None)
        for byte in result.readback:
            await self.cycle(START, status=reading, read_byte=byte, sample=previous)
            previous = (reading, byte)
        await self.cycle(0xFC, status=handoff, sample=previous)
        await self.cycle(START, status=flags | READY, sample=(handoff, None))
        self.dut._log.info(
            "Read %s = %d, overflow=%s. Both handoffs released all eight pins.",
            result.readback.hex(" ").upper(), result.value, result.overflow,
        )


@cocotb.test()
async def test_host_protocol(dut):
    entries = int(os.environ.get("ENTRIES", "16"))
    width = int(os.environ.get("ACCW", "24"))
    codebook = [0] * entries
    host = Host(dut)
    await host.reset()

    codebook[3] = -2
    await host.write(3, -2)
    dut._log.info("Write slot 03 = FE (-2), START, stream 03 05 03 04 (LAST)")
    await host.cycle(START)
    repeated = [(3, 5), (3, 4)]
    result = await host.stream(codebook, repeated, width)
    await host.read(result)

    codebook = [-128 + 8 * index for index in range(entries)]
    for index, weight in enumerate(codebook):
        await host.write(index, weight, status=READY | DONE)
    for length in (16, 32):
        pairs = [(index % entries, (-128, -1, 1, 127)[index % 4]) for index in range(length)]
        dut._log.info("Stream %d signed pairs with %d programmed slots", length, entries)
        await host.cycle(START)
        result = await host.stream(codebook, pairs, width)
        await host.read(result)

    overflow_pairs = [(0, -128)] * 2
    await host.cycle(START)
    result = await host.stream(codebook, overflow_pairs, width)
    await host.read(result)
    flags = DONE | (OVERFLOW if result.overflow else 0)
    await host.cycle(0xFC, status=READY | flags | ERROR)
    await host.cycle(0, status=READY | flags | ERROR)
    await host.read(result, error=True)
    await host.cycle(START)


@cocotb.test()
async def test_recovery(dut):
    entries = int(os.environ.get("ENTRIES", "16"))
    width = int(os.environ.get("ACCW", "24"))
    codebook = [0] * entries
    host = Host(dut)
    await host.reset()

    fault = READY | ERROR
    await host.cycle(0xFB)  # VALID low even with the other command bits set.
    await host.cycle(READ, status=fault)
    for command in (0x05, 0x06, 0x0C, 0xE4):
        await host.cycle(command, 3, status=fault)
    await host.cycle(WRITE, entries, status=fault)
    await host.cycle(WRITE, 4, status=fault)
    await host.cycle(START)  # Cancels the pending weight.
    await host.cycle(STREAM, 4)
    await host.cycle(FINAL, 7, status=READY | DONE)
    await host.read(calculate(codebook, [(4, 7)], width))

    await host.cycle(WRITE, 3, status=READY | DONE)
    dut.host_drives.value = 0
    dut.ena.value = 0
    await Timer(2, unit="ns")
    host.check(0)
    await host.cycle(WRITE, 0x7F, status=0)
    dut.ena.value = 1
    await host.cycle(0x06, 0x7F, status=READY | DONE | ERROR)
    await host.cycle(WRITE, -2, status=READY | DONE | ERROR)
    codebook[3] = -2

    await host.cycle(START)
    await host.cycle(FINAL, 3, status=fault)
    await host.cycle(STREAM, entries, status=fault)
    await host.cycle(0x27, status=fault)  # START with LAST.
    await host.cycle(STREAM, 4, status=fault)
    await host.cycle(START)  # Cancels the pending calculation index.
    await host.cycle(STREAM, 3)
    await host.cycle(0xFB)  # Idle between index and input.
    await host.cycle(READ, status=fault)
    dut.ena.value = 0
    await host.cycle(FINAL, 0x7F, status=0)
    dut.ena.value = 1
    await host.cycle(FINAL, 5, status=READY | DONE | ERROR)
    result = calculate(codebook, [(3, 5)], width)
    dut._log.info("Malformed bytes rejected. Pending weight and input survived deselection.")

    flags = DONE | ERROR
    for advance in (0, 1, len(result.readback) + 1):
        await host.cycle(READ, status=flags | BUSY)
        for byte in result.readback[:advance]:
            await host.cycle(status=flags | BUSY | BYTE_VALID, read_byte=byte)
        if advance > len(result.readback):
            await host.cycle(status=flags | BUSY)
        dut.ena.value = 0
        await Timer(2, unit="ns")
        host.check(0)
        await host.cycle(START, status=0)
        dut.ena.value = 1
        await Timer(2, unit="ns")
        host.check(flags | READY)
        await host.read(result, error=True)

    await host.cycle(READ, status=flags | BUSY)
    await host.cycle(status=flags | BUSY | BYTE_VALID, read_byte=result.readback[0])
    await host.reset()
    await host.cycle(WRITE, 3)
    await host.reset()  # Reset during a pending weight write.
    await host.cycle(START)
    await host.cycle(STREAM, 3)
    await host.reset()  # Reset during a pending calculation.
    await host.cycle(READ, status=fault)
    await host.cycle(START)
    await host.cycle(STREAM, 3)
    await host.cycle(FINAL, 5, status=READY | DONE)
    await host.read(calculate([0] * entries, [(3, 5)], width))
