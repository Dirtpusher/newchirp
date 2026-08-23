#!/usr/bin/env python3
"""Generate a single-page color PDF for the US FRS/GMRS channel plan.

This script is intentionally dependency-free; it writes a small PDF directly
using the standard Helvetica font family.
"""

from __future__ import annotations

import pathlib


OUT_PATH = pathlib.Path(
    __file__
).resolve().parents[1] / "GMRS_FRS_Frequency_Chart.pdf"

PAGE_W = 612.0
PAGE_H = 792.0
MARGIN = 34.0
CONTENT_W = PAGE_W - (MARGIN * 2)

INK = (0.082, 0.129, 0.114)
MUTED = (0.33, 0.37, 0.35)
WHITE = (1.0, 1.0, 1.0)

HEADER_BG = (0.122, 0.455, 0.333)
HEADER_FG = (1.0, 1.0, 1.0)

BAND_1_7 = (0.918, 0.953, 0.980)
BAND_8_14 = (1.0, 0.957, 0.878)
BAND_15_22 = (0.918, 0.957, 0.937)
REPEATER_BG = (0.953, 0.925, 0.976)

GRID = (0.855, 0.875, 0.867)


def _esc(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace("(", "\\(")
        .replace(")", "\\)")
    )


def _rgb(color: tuple[float, float, float]) -> str:
    return f"{color[0]:.3f} {color[1]:.3f} {color[2]:.3f}"


class PdfWriter:
    def __init__(self) -> None:
        self._content: list[str] = []

    def set_fill(self, color: tuple[float, float, float]) -> None:
        self._content.append(f"{_rgb(color)} rg\n")

    def set_stroke(self, color: tuple[float, float, float]) -> None:
        self._content.append(f"{_rgb(color)} RG\n")

    def rect(
        self,
        x: float,
        y: float,
        width: float,
        height: float,
        color: tuple[float, float, float],
    ) -> None:
        self.set_fill(color)
        self._content.append(
            f"{x:.2f} {y:.2f} {width:.2f} {height:.2f} re f\n"
        )

    def line(
        self,
        x1: float,
        y1: float,
        x2: float,
        y2: float,
        color: tuple[float, float, float],
        width: float = 0.5,
    ) -> None:
        self.set_stroke(color)
        self._content.append(f"{width:.2f} w\n")
        self._content.append(
            f"{x1:.2f} {y1:.2f} m {x2:.2f} {y2:.2f} l S\n"
        )

    def text(
        self,
        x: float,
        y: float,
        text: str,
        font: str,
        size: float,
        color: tuple[float, float, float],
    ) -> None:
        self.set_fill(color)
        self._content.append(
            f"BT /{font} {size:.2f} Tf {x:.2f} {y:.2f} Td "
            f"({_esc(text)}) Tj ET\n"
        )

    def text_in_rect(
        self,
        *,
        top: float,
        height: float,
        x: float,
        width: float,
        text: str,
        font: str,
        size: float,
        color: tuple[float, float, float],
        align: str = "left",
        pad_left: float = 4.0,
    ) -> None:
        baseline = (
            top
            - height
            + (height - size) / 2
            + size * 0.28
        )
        if align == "center":
            approx_width = len(text) * size * 0.52
            tx = x + (width - approx_width) / 2
        else:
            tx = x + pad_left
        self.text(tx, baseline, text, font, size, color)

    def table_cell(
        self,
        *,
        top: float,
        left: float,
        width: float,
        height: float,
        text: str,
        font: str,
        size: float,
        color: tuple[float, float, float],
        fill: tuple[float, float, float] | None = None,
        align: str = "left",
    ) -> None:
        bottom = top - height
        if fill is not None:
            self.rect(left, bottom, width, height, fill)
        self.line(left, bottom, left + width, bottom, GRID, 0.35)
        self.line(left, bottom, left, top, GRID, 0.35)
        self.text_in_rect(
            top=top,
            height=height,
            x=left,
            width=width,
            text=text,
            font=font,
            size=size,
            color=color,
            align=align,
        )

    def as_pdf(self) -> bytes:
        content = "".join(self._content).encode("latin-1", errors="replace")
        objects: list[bytes] = []

        objects.append(b"<< /Type /Catalog /Pages 2 0 R >>")
        objects.append(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
        objects.append(
            b"<< /Type /Page /Parent 2 0 R "
            b"/MediaBox [0 0 612 792] "
            b"/Resources << /Font << "
            b"/F1 4 0 R /F2 5 0 R /F3 6 0 R "
            b">> >> /Contents 7 0 R >>"
        )
        objects.append(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
        objects.append(
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"
        )
        objects.append(
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>"
        )
        objects.append(
            b"<< /Length "
            + str(len(content)).encode()
            + b" >>\nstream\n"
            + content
            + b"\nendstream"
        )

        out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
        offsets: list[int] = []
        for number, obj in enumerate(objects, start=1):
            offsets.append(len(out))
            out += f"{number} 0 obj\n".encode()
            out += obj
            out += b"\nendobj\n"

        xref = len(out)
        out += b"xref\n"
        out += f"0 {len(objects) + 1}\n".encode()
        out += b"0000000000 65535 f \n"
        for offset in offsets:
            out += f"{offset:010d} 00000 n \n".encode()
        out += (
            b"trailer\n<< /Size "
            + str(len(objects) + 1).encode()
            + b" /Root 1 0 R >>\n"
            b"startxref\n"
            + str(xref).encode()
            + b"\n%%EOF\n"
        )
        return bytes(out)


def _row_color(channel: int) -> tuple[float, float, float]:
    if channel <= 7:
        return BAND_1_7
    if channel <= 14:
        return BAND_8_14
    return BAND_15_22


def main() -> None:
    pdf = PdfWriter()

    # Page background and outer margin guides.
    pdf.rect(0, 0, PAGE_W, PAGE_H, (0.965, 0.976, 0.969))
    pdf.rect(MARGIN - 10, MARGIN - 10, CONTENT_W + 20, PAGE_H - 2 * MARGIN + 20, WHITE)

    # Title block.
    pdf.text(
        MARGIN,
        726,
        "GMRS & FRS Frequency Reference",
        "F2",
        23,
        HEADER_BG,
    )
    pdf.text(
        MARGIN,
        705,
        "United States Part 95 channel plan - color-coded by frequency band and power class",
        "F1",
        10,
        MUTED,
    )

    # Legend.
    legend_items = [
        (BAND_1_7, "Ch 1-7: 462 MHz interstitial"),
        (BAND_8_14, "Ch 8-14: 467 MHz interstitial"),
        (BAND_15_22, "Ch 15-22: 462 MHz main"),
    ]
    legend_top = 680
    legend_x = MARGIN
    for color, label in legend_items:
        pdf.rect(legend_x, legend_top - 9, 10, 10, color)
        pdf.text(
            legend_x + 15,
            legend_top - 1,
            label,
            "F1",
            8,
            INK,
        )
        legend_x += 188

    # Main FRS/GMRS table.
    table_top = 654
    header_h = 20
    row_h = 15.2
    columns = [
        ("Ch", 30, "center"),
        ("Frequency (MHz)", 82, "center"),
        ("FRS Power", 60, "center"),
        ("FRS BW", 52, "center"),
        ("GMRS Power", 88, "center"),
        ("GMRS BW", 62, "center"),
        ("Notes", 170, "left"),
    ]

    x = MARGIN
    for label, width, _align in columns:
        pdf.table_cell(
            top=table_top,
            left=x,
            width=width,
            height=header_h,
            text=label,
            font="F2",
            size=8,
            color=HEADER_FG,
            fill=HEADER_BG,
            align="center" if label != "Notes" else "left",
        )
        x += width

    channels = [
        (1, "462.5625", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (2, "462.5875", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (3, "462.6125", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (4, "462.6375", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (5, "462.6625", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (6, "462.6875", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (7, "462.7125", "2 W", "12.5 kHz", "5 W", "20 kHz", "Shared 462 MHz interstitial"),
        (8, "467.5625", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (9, "467.5875", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (10, "467.6125", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (11, "467.6375", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (12, "467.6625", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (13, "467.6875", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (14, "467.7125", "0.5 W", "12.5 kHz", "0.5 W", "12.5 kHz", "Handheld only"),
        (15, "462.5500", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (16, "462.5750", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (17, "462.6000", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (18, "462.6250", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (19, "462.6500", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (20, "462.6750", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (21, "462.7000", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
        (22, "462.7250", "2 W", "12.5 kHz", "50 W", "20 kHz", "Main / repeater output"),
    ]

    row_top = table_top - header_h
    for channel, frequency, frs_power, frs_bw, gmrs_power, gmrs_bw, notes in channels:
        row_color = _row_color(channel)
        values = [
            (str(channel), "center"),
            (frequency, "center"),
            (frs_power, "center"),
            (frs_bw, "center"),
            (gmrs_power, "center"),
            (gmrs_bw, "center"),
            (notes, "left"),
        ]
        x = MARGIN
        for (value, align), (_label, width, _col_align) in zip(values, columns):
            pdf.table_cell(
                top=row_top,
                left=x,
                width=width,
                height=row_h,
                text=value,
                font="F1",
                size=7.8,
                color=INK,
                fill=row_color,
                align=align,
            )
            x += width
        row_top -= row_h
    main_bottom = row_top
    pdf.line(
        MARGIN + CONTENT_W,
        main_bottom,
        MARGIN + CONTENT_W,
        table_top,
        GRID,
        0.35,
    )

    # Repeater heading and table.
    pdf.text(
        MARGIN,
        288,
        "Repeater Pairs (GMRS Only)",
        "F2",
        11,
        HEADER_BG,
    )
    repeater_top = 277
    repeater_header_h = 18
    repeater_row_h = 15.2
    repeater_columns = [
        ("Repeater", 118, "left"),
        ("Input - You Transmit", 128, "center"),
        ("Output - You Listen", 128, "center"),
        ("Notes", 170, "left"),
    ]

    x = MARGIN
    for label, width, align in repeater_columns:
        pdf.table_cell(
            top=repeater_top,
            left=x,
            width=width,
            height=repeater_header_h,
            text=label,
            font="F2",
            size=8,
            color=HEADER_FG,
            fill=HEADER_BG,
            align=align,
        )
        x += width

    repeaters = [
        ("RPT15", "467.5500", "462.5500"),
        ("RPT16", "467.5750", "462.5750"),
        ("RPT17", "467.6000", "462.6000"),
        ("RPT18", "467.6250", "462.6250"),
        ("RPT19", "467.6500", "462.6500"),
        ("RPT20", "467.6750", "462.6750"),
        ("RPT21", "467.7000", "462.7000"),
        ("RPT22", "467.7250", "462.7250"),
    ]

    row_top = repeater_top - repeater_header_h
    for repeater, input_freq, output_freq in repeaters:
        values = [
            (repeater, "left"),
            (input_freq, "center"),
            (output_freq, "center"),
            ("Input = output + 5 MHz", "left"),
        ]
        x = MARGIN
        for (value, align), (_label, width, _col_align) in zip(
            values, repeater_columns
        ):
            pdf.table_cell(
                top=row_top,
                left=x,
                width=width,
                height=repeater_row_h,
                text=value,
                font="F1",
                size=7.8,
                color=INK,
                fill=REPEATER_BG,
                align=align,
            )
            x += width
        row_top -= repeater_row_h
    repeater_bottom = row_top
    pdf.line(
        MARGIN + CONTENT_W,
        repeater_bottom,
        MARGIN + CONTENT_W,
        repeater_top,
        GRID,
        0.35,
    )

    # Footer notes.
    notes = [
        "All frequencies are in MHz. GMRS requires an FCC license; FRS is license-by-rule.",
        "GMRS mobile/base radios may not transmit on channels 8-14. Repeater inputs are GMRS-only.",
        "Community convention: Channel 20 (462.675 MHz) with CTCSS 141.3 Hz is often used as a travel/assistance channel.",
        "Reference only - verify against current FCC Part 95 rules and your radio manual.",
    ]
    note_y = 96
    for note in notes:
        pdf.text(MARGIN, note_y, note, "F3", 8.2, MUTED)
        note_y -= 14

    OUT_PATH.write_bytes(pdf.as_pdf())
    print(OUT_PATH)


if __name__ == "__main__":
    main()
