"""Compatibility fixes for the Yaesu FT-817/FT-857 clone drivers.

These radios store AM and SSB tuning steps in bitfields that can represent
values beyond CHIRP's shorter lookup tables. Some live clone images contain
reserved values, which make CHIRP abort the entire download with an
``IndexError``. Pad the tables to the bitfield width so every value remains
readable and maps to a valid step.
"""

from chirp.drivers import ft817, ft857


_DEFAULT_STEP = 5.0


def _complete_steps(steps, width):
    size = 1 << width
    if len(steps) >= size:
        return list(steps)
    return list(steps) + [_DEFAULT_STEP] * (size - len(steps))


for _radio in (ft817.FT817Radio, ft857.FT857Radio):
    _radio.STEPSAM = _complete_steps(_radio.STEPSAM, 3)
    _radio.STEPSSSB = _complete_steps(_radio.STEPSSSB, 2)
