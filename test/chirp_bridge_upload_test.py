"""Protocol regression tests for CHIRP bridge uploads."""

from __future__ import annotations

import importlib.util
import struct
import sys
import unittest
from collections import deque
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = (
    ROOT / "build_support/chirp-20261023"
    if (ROOT / "build_support/chirp-20261023").is_dir()
    else ROOT.parent / "chirp-20260626"
)
VENDOR = ROOT / "assets/python/pyserial-3.5-py2.py3-none-any.whl"
TD_H3_IMAGE = SOURCE / "tests/images/TIDRADIO_TD-H3.img"

spec = importlib.util.spec_from_file_location(
    "newchirp_chirp_bridge", ROOT / "scripts/chirp_bridge.py"
)
if spec is None or spec.loader is None:
    raise RuntimeError("Could not load chirp_bridge.py")

bridge = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = bridge
spec.loader.exec_module(bridge)


class FakeTDH3Serial:
    def __init__(self):
        self.timeout = 0.25
        self.writes: list[bytes] = []
        self._responses: deque[bytes] = deque()
        self.ident_count = 0

    def write(self, data):
        self.writes.append(bytes(data))
        if data == b"PVOJH\x5c\x14":
            self.ident_count += 1
            if self.ident_count == 1:
                self._responses.append(b"\x06")
        elif data == b"\x02":
            self._responses.append(b"P31183\xff\xff")
        elif data == b"\x06":
            self._responses.append(b"\x06")
        elif data[:1] == b"R":
            command = bytes(data)
            self._responses.append(
                b"W" + command[1:] + b"\x00" * 0x20 + b"\x00"
            )
        elif data[:1] == b"W":
            self._responses.append(b"\x06")

    def read(self, size):
        result = bytearray()
        while self._responses and len(result) < size:
            chunk = self._responses[0]
            take = min(size - len(result), len(chunk))
            result.extend(chunk[:take])
            if take == len(chunk):
                self._responses.popleft()
            else:
                self._responses[0] = chunk[take:]
        return bytes(result)

    def close(self):
        pass


class UploadHandshakeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = bridge.load_chirp(str(SOURCE), str(VENDOR))
        from chirp import errors

        cls.errors = errors
        bridge.status_progress = lambda *_args, **_kwargs: None

    def test_td_h3_upload_handshakes_once_before_writing(self):
        serial = FakeTDH3Serial()
        bridge.open_serial = lambda _radio_class, _port: serial

        radio = bridge.radio_for(
            self.directory,
            "TIDRADIO_TD-H3",
            "fake",
            image=str(TD_H3_IMAGE),
            detect_serial=False,
        )
        self.assertEqual(serial.writes, [])

        radio.load_mmap(str(TD_H3_IMAGE))
        radio.sync_out()

        self.assertEqual(serial.ident_count, 1)
        write_blocks = [
            data for data in serial.writes if data[:1] == b"W"
        ]
        self.assertGreater(len(write_blocks), 0)
        self.assertEqual(serial.writes[-1], b"E")

    def test_probe_before_td_h3_upload_causes_second_handshake_failure(self):
        serial = FakeTDH3Serial()
        bridge.open_serial = lambda _radio_class, _port: serial

        radio = bridge.radio_for(
            self.directory,
            "TIDRADIO_TD-H3",
            "fake",
            image=str(TD_H3_IMAGE),
            detect_serial=True,
        )
        radio.load_mmap(str(TD_H3_IMAGE))

        with self.assertRaises(self.errors.RadioNoResponse):
            radio.sync_out()
        self.assertEqual(serial.ident_count, 2)


if __name__ == "__main__":
    unittest.main()
