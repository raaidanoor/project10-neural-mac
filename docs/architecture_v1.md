# Project 10 architecture v1

## Datapath

The default codebook has 16 weight slots. A 4-bit index selects a slot. Each operation multiplies the selected weight by a signed input and adds the product to the running total in the accumulator.

```text
Host index byte -> Pending index -> Select weight --+
                                                     +-> Multiply -> Add to accumulator
Host input byte ------------------------------------+
```

The host sends two bytes per operation, index first and input second. The chip holds the pending index until it accepts the input byte. It handles one pair at a time. The host waits for the chip to indicate that it is ready before sending the next pair.

The chip remembers the index and selected weight from the last completed pair. If the remembered pair is valid and the new index matches, the chip uses the remembered weight and skips the codebook lookup for that operation. It still multiplies by the new input and adds the product to the accumulator.

Reset, the start of a new calculation, and any accepted codebook write clear the validity of the remembered index and weight.

## Clock sequence for one pair

| Accepted byte | What updates on that clock edge | What the chip expects next |
| --- | --- | --- |
| Index | Save the pending index. The accumulator and remembered weight stay as they were. | Input byte |
| Input | Select the weight using the pending index, multiply by the incoming signed input, and save the updated accumulator and remembered index and weight. | Next index byte if the calculation has more pairs |

The two accepted bytes can arrive on consecutive clock edges. If the host pauses between them, the pending index and accumulator hold their values. The input byte is used directly for the calculation on its acceptance edge.

## Reset and start

Reset sets every codebook weight and the accumulator to zero, discards any unfinished index/input pair, and invalidates the remembered index and weight.

An accepted start clears the accumulator and invalidates the remembered index and weight. It preserves all codebook entries so the host can use the same weights for another calculation.

## Completion

The host marks the final pair by asserting `last` on its input byte. On the edge that accepts that byte, the chip adds the final product to the accumulator and asserts `done`. The updated total is then available for readback.

The host determines the number of pairs, including the 16- and 32-pair configurations used for the project sweep.

## Signed arithmetic and overflow

Inputs and codebook weights are signed 8-bit two's-complement values in the range −128 to +127. Multiply them to produce an exact signed 16-bit product. Sign-extend the product when adding it to a wider accumulator.

The accumulator is signed 24-bit by default, with a signed 16-bit option for the parameter sweep. The 24-bit accumulator can represent the exact sum of any 16 or 32 signed 8-bit products.

On each accepted input byte, check whether the sum of the current signed accumulator and the product is outside the accumulator's signed range. Store the low accumulator-width bits of the sum, which gives two's-complement wraparound. Latch the overflow flag if any addition overflows. The flag stays set until reset or an accepted start.

For example, in 16-bit mode two products of `(-128) × (-128)` give 16,384 each. The second addition reaches 32,768, stores −32,768, and sets the overflow flag.

## Control states

The [host protocol](protocol_v1.md) defines which commands are legal in each state and which pins carry each field.

| State | What changes on the rising edge | Next state |
| --- | --- | --- |
| Between calculations | A write saves the target slot. A start clears the accumulator and status for a new calculation. A read request begins the bus handoff. | Wait for weight, wait for index, or handoff to chip, respectively |
| Wait for weight | Store the signed weight and invalidate the remembered weight. | Between calculations |
| Wait for index | Save the index. | Wait for input |
| Wait for input | Add the product, update overflow and reuse state, and set done if `last` is asserted. | Between calculations on `last`, otherwise wait for index |
| Handoff to chip | After one released cycle, drive the first result byte and assert result byte valid. | Read result |
| Read result | The host samples the current byte. The chip advances to the next byte or releases the bus after the final byte. | Read result or handoff to host |
| Handoff to host | After one released cycle, indicate ready. | Between calculations |

Reset returns to the initial state between calculations. A standalone start in any waiting state discards the unfinished pair or weight write and returns to wait for index. With no accepted command, the waiting states hold their saved values. A malformed command while ready sets error and leaves the state unchanged. Deselecting the chip pauses the waiting states and ends any readback in progress.

## Clock target

Use the repository's existing 20 ns (50 MHz) setting as the initial timing target. Check the weight selection, multiplication, and accumulation path against that target during hardware implementation.

## Comparison and reporting

- **Baseline.** Feed the same signed inputs and the same decoded 8-bit weights to the full-weight MAC. Keep the vector length, accumulator width, overflow behavior, clock target, and physical build conditions the same for paired comparisons.
- **Reuse.** Count one lookup avoided when an accepted pair uses a valid remembered weight for the same index. Report the count and divide by all accepted pairs for the reuse fraction. The first pair counts as an operation and has no reuse. Use transition counts from equal-stimulus waveforms as an activity proxy.
- **Cycles.** Count rising edges from accepted start through done, inclusive. Without pauses, this is `1 + 2 × pairs`. Report codebook loading and readback separately, including both bus handoffs in readback.
- **Reconstruction error.** Use the fixed synthetic signed-byte weights `−125 + 8i` for `i = 0…31`. Use the first 16 values for the 16-pair case. For a codebook of size `E`, use centroid values `−128 + (256/E) × j` for `j = 0…E−1`. Map each original weight to the nearest centroid, choosing the smaller value on a tie. Report the mean absolute difference between original weights and selected centroids.
- **Storage and area.** Report logical storage as `(8 × codebook entries + index width × stored weights) / stored weights` bits per stored weight, alongside 8 bits for explicit weights. Compare functional placed standard-cell area under matched build conditions.

## Reference outputs

Run `python3 scripts/golden_model.py` from the repository root. Each example uses a 16-entry codebook with all slots zero except slot 3.

| Slot 3 weight | Index/input pairs | Accumulator width | Signed result | Overflow | Readback bytes |
| --- | --- | ---: | ---: | --- | --- |
| −2 | (3, 5), (3, 4) | 24 | −18 | No | `EE FF FF` |
| −128 | (3, −128), (3, −128) | 16 | −32,768 | Yes | `00 80` |
