import struct
import math

def bits_to_float(val: int) -> float:
    return struct.unpack('>f', struct.pack('>I', val & 0xFFFFFFFF))[0]

def float_to_bits(val: float) -> int:
    return struct.unpack('>I', struct.pack('>f', val))[0]

def is_nan(bits: int) -> bool:
    exp = (bits >> 23) & 0xFF
    mant = bits & 0x7FFFFF
    return exp == 0xFF and mant != 0

def is_inf(bits: int) -> bool:
    exp = (bits >> 23) & 0xFF
    mant = bits & 0x7FFFFF
    return exp == 0xFF and mant == 0

def is_zero(bits: int) -> bool:
    return (bits & 0x7FFFFFFF) == 0

def get_sign(bits: int) -> int:
    return (bits >> 31) & 1

def get_exp(bits: int) -> int:
    return (bits >> 23) & 0xFF

def get_mant(bits: int) -> int:
    return bits & 0x7FFFFF

CANONICAL_QNAN = 0x7FC00000
POS_INF        = 0x7F800000
NEG_INF        = 0xFF800000
POS_ZERO       = 0x00000000
NEG_ZERO       = 0x80000000
