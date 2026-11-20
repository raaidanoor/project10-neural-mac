# Project 10 host protocol v1

## Byte exchange

The host sends commands on the dedicated inputs. The chip reports status on the dedicated outputs. The eight bidirectional pins carry one data byte at a time.

| Operation | Byte sequence |
| --- | --- |
| Write one codebook weight | Send the slot index, then the signed weight byte. |
| Begin a calculation | Send a separate `START` command. The chip clears the running total on that edge. |
| Stream calculation pairs | Send the index byte, then the signed input byte for each pair. Assert `last` on the input byte of the final pair. |
| Read the result | Request readback once. The chip sends two bytes for a 16-bit result or three for a 24-bit result, least-significant byte first. Status indicates when a result byte is valid. |

A signed result of −18 in 24-bit mode is sent as `EE FF FF` in hexadecimal.

## Shared bus handoff

Allow one full clock cycle with both sides releasing all eight shared pins whenever the bus changes direction. The host releases the bus for the handoff before the chip drives its first result byte. After the chip releases the bus, the host waits through the handoff before driving another data byte.

## Command and status pins

| Dedicated inputs | Meaning |
| --- | --- |
| `ui_in[7:5]` | `000` codebook write, `001` start or stream, `010` readback request |
| `ui_in[4:3]` | Reserved, drive zero |
| `ui_in[2]` | `valid`, a command or byte is presented for acceptance on the rising edge |
| `ui_in[1]` | `last`, asserted only on the final input byte |
| `ui_in[0]` | `start`, asserted with opcode `001` for a standalone start command |

| Dedicated outputs | Meaning |
| --- | --- |
| `uo_out[7:6]` | Zero |
| `uo_out[5]` | Overflow, sticky until start or reset |
| `uo_out[4]` | Result byte valid |
| `uo_out[3]` | Error, sticky until start or reset |
| `uo_out[2]` | Done, sticky until start or reset |
| `uo_out[1]` | Busy during readback and bus handoffs |
| `uo_out[0]` | Ready for a command or byte appropriate to the current step |

A malformed command presented while ready sets error and leaves the current step and data intact so the host can retry. For example, the chip discards an index byte that has `last` asserted and keeps waiting for an index.

## Example clock sequence

| Rising edge | Transaction |
| --- | --- |
| 1–2 | Host sends slot `03`, then weight `FE` (−2). |
| 3 | Host sends standalone start. |
| 4–7 | Host sends index/input bytes `03 05 03 04`, with `last` on `04`. The chip sets done and saves −18. |
| 8 | Chip accepts the readback request. The host has released the shared bus. |
| 9–11 | Just after each edge, the chip drives the next byte with result byte valid asserted. The bytes are `EE FF FF`. The host samples each byte at the following rising edge. |
| 12 | Host samples the last byte. The chip then releases the bus and deasserts result byte valid. |
| 13 | The return handoff ends. The host may drive a new data byte after this edge. |

## Allowed commands and recovery

| Current step | Commands accepted |
| --- | --- |
| Between calculations | Codebook write slot or standalone `START`. Readback is also allowed if `done` is set. |
| Waiting for a weight | Codebook weight byte or standalone `START`. |
| Waiting for a calculation index | Stream index byte or standalone `START`. |
| Waiting for a calculation input | Stream input byte, with optional `last`, or standalone `START`. |
| Readback and bus handoff | No command or data byte is accepted. |

An accepted `START` drops any pending slot or index and begins a new calculation. A slot or index byte must be less than the configured codebook size. Weight writes and read requests require both `start` and `last` to be zero. Standalone `START` requires `last` to be zero and uses no shared data byte. Reserved opcodes and nonzero reserved bits are malformed. With `valid` low, command bits have no effect.

The chip sets `uio_oe` to `FF` only while presenting a valid readback byte. Otherwise `uio_oe` and `uio_out` are zero. Ready is low while busy.

## Reset and deselection

During reset or deselection (`ena` low), the chip accepts no bytes, reports zero on the dedicated outputs, and releases all shared pins. Reset clears the transaction and returns the chip to the initial state between calculations.

Deselection preserves the codebook, accumulator, flags, and any pending slot or calculation index. A pending write or calculation can then continue when selected again. Deselection during readback or its handoff ends the transfer and preserves the completed result. After reselection, the host requests readback again and receives the result from its first byte.
