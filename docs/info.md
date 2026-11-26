## How it works

The Codebook-Shared Neural MAC stores eight programmable signed 8-bit weights. Each input pair selects a weight by its 3-bit index and supplies a signed 8-bit input. The chip multiplies them and adds the product to a signed 16-bit accumulator. Consecutive pairs using the same index reuse the previous weight lookup. The total wraps on signed overflow and sets a sticky overflow flag.

The layout was verified at a 60 ns clock period (approximately 16.67 MHz).

## Host interface

| Pins | Function |
| --- | --- |
| `ui_in[7:5]` | Opcode. `000` writes the codebook, `001` starts or streams a calculation, and `010` requests readback. |
| `ui_in[4:3]` | Reserved. Drive zero. |
| `ui_in[2:0]` | `VALID`, `LAST`, and `START`, respectively. |
| `uo_out[7:0]` | Two zero bits, then `OVERFLOW`, `RESULT_BYTE_VALID`, `ERROR`, `DONE`, `BUSY`, and `READY` in descending bit order. |
| `uio[7:0]` | Shared data byte. The chip drives it while `RESULT_BYTE_VALID` is high. |

Commands are sampled on rising clock edges while `READY` and `VALID` are high. Present each byte for one accepted edge. A malformed command sets `ERROR` and leaves the current step available for retry. An accepted standalone `START` clears the accumulator and flags, cancels any pending slot or index, and preserves the codebook.

Active-low reset clears the codebook and transaction. With reset asserted or `ena` low, status outputs are zero and all shared pins are released. A pending write or calculation resumes after reselection. Deselecting across a rising edge during readback or a handoff cancels that transfer. Request readback again after reselecting to receive the saved result from byte zero.

## Example transaction

With the chip selected and reset released, send the following bytes in hexadecimal while `READY` is high.

| Step | `ui_in` | Host drives `uio` |
| --- | --- | --- |
| Select slot 3 to write | `04` | `03` |
| Write weight −2 | `04` | `FE` |
| Start calculation | `25` | Released |
| First index | `24` | `03` |
| First input (+5) | `24` | `05` |
| Second index | `24` | `03` |
| Final input (+4) | `26` | `04` |
| Request result once `DONE` is high | `44` | Released |

Keep the bus released through readback. The request is followed by one full released clock cycle. When `RESULT_BYTE_VALID` is high, sample a byte on each rising edge. The bytes are `EE FF`, the 16-bit two's-complement encoding of −18 in least-significant-byte-first order. After the last sample, the chip releases the bus for one full clock cycle before raising `READY`. Drive `VALID` low when idle.
