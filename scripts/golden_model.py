"""Reference arithmetic for one Project 10 calculation."""

from collections.abc import Iterable, Sequence
from dataclasses import dataclass


@dataclass(frozen=True)
class Result:
    value: int
    overflow: bool
    readback: bytes


def calculate(
    codebook: Sequence[int],
    pairs: Iterable[tuple[int, int]],
    accumulator_width: int = 24,
) -> Result:
    """Accept signed input values and return the total and little-endian bytes."""
    if accumulator_width not in (16, 24):
        raise ValueError("accumulator width must be 16 or 24")
    if len(codebook) not in (8, 16, 32):
        raise ValueError("codebook must have 8, 16, or 32 entries")
    if any(not isinstance(weight, int) or not -128 <= weight <= 127 for weight in codebook):
        raise ValueError("weights must be signed 8-bit integers")

    sign_bit = 1 << (accumulator_width - 1)
    modulus = 2 * sign_bit
    total = 0
    overflow = False
    for index, input_value in pairs:
        if not isinstance(index, int) or not 0 <= index < len(codebook):
            raise ValueError("index is outside the codebook")
        if not isinstance(input_value, int) or not -128 <= input_value <= 127:
            raise ValueError("inputs must be signed 8-bit integers")
        exact_sum = total + input_value * codebook[index]
        if not -sign_bit <= exact_sum < sign_bit:
            overflow = True
        total = (exact_sum + sign_bit) % modulus - sign_bit

    return Result(total, overflow, total.to_bytes(accumulator_width // 8, "little", signed=True))


if __name__ == "__main__":
    codebook = [0] * 16
    codebook[3] = -2
    repeated = calculate(codebook, [(3, 5), (3, 4)])
    assert repeated == Result(-18, False, bytes.fromhex("EE FF FF"))
    print(f"Repeated index (24-bit): {repeated.value}, overflow={repeated.overflow}, "
          f"bytes={repeated.readback.hex(' ').upper()}")

    codebook[3] = -128
    overflowing = calculate(codebook, [(3, -128), (3, -128)], 16)
    assert overflowing == Result(-32768, True, bytes.fromhex("00 80"))
    print(f"Overflow (16-bit): {overflowing.value}, overflow={overflowing.overflow}, "
          f"bytes={overflowing.readback.hex(' ').upper()}")
