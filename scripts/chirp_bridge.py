#!/usr/bin/env python3
"""Small JSON boundary between NewChirp and the audited CHIRP driver tree."""
import argparse
import builtins
import json
import os
import sys
import tempfile

# CHIRP normally redirects stdout and stderr to ~/.chirp/debug.log when it is
# launched without a terminal. The bridge owns those streams as its JSON/error
# protocol, so keep them attached to the parent process.
os.environ.setdefault("CHIRP_TESTENV", "1")


def load_chirp(source, vendor):
    # pyserial is shipped as a pure-Python wheel inside NewChirp. Python can
    # import it directly without pip or a user-level installation.
    sys.path.insert(0, vendor)
    sys.path.insert(0, source)
    # Driver prompt/error strings use CHIRP's process-wide translation hook.
    # The headless bridge keeps the original English strings.
    builtins._ = lambda message: message
    try:
        import serial  # noqa: F401
    except ImportError as exc:
        raise RuntimeError(
            "NewChirp's bundled serial backend could not be loaded. "
            "Reinstall NewChirp so its support files are restored."
        ) from exc
    from chirp import directory
    directory.import_drivers()
    return directory


def memory_json(mem):
    return {
        "location": mem.number,
        "name": mem.name,
        "frequency": mem.freq / 1_000_000,
        "duplex": mem.duplex,
        "offset": mem.offset / 1_000_000,
        "tone": mem.tmode,
        "txTone": mem.rtone,
        "rxTone": mem.ctone,
        "dtcs": mem.dtcs,
        "dtcsPolarity": mem.dtcs_polarity,
        "rxDtcs": mem.rx_dtcs,
        "crossMode": mem.cross_mode,
        "mode": mem.mode,
        "step": mem.tuning_step,
        "skip": mem.skip,
        "power": str(mem.power or ""),
        "comment": mem.comment,
        "extras": extra_fields_json(mem),
    }


def extra_fields_json(mem):
    from chirp.settings import (
        RadioSettingValueBoolean,
        RadioSettingValueFloat,
        RadioSettingValueInteger,
        RadioSettingValueList,
    )

    fields = []
    for setting in mem.extra:
        value = setting.value
        current = value.get_value()
        choices = []
        if isinstance(value, RadioSettingValueBoolean):
            kind = "boolean"
            current = bool(current)
        elif isinstance(value, RadioSettingValueList):
            kind = "choice"
            choices = [str(option) for option in value.get_options()]
            current = str(current)
        elif isinstance(value, RadioSettingValueInteger):
            kind = "integer"
            current = int(current)
        elif isinstance(value, RadioSettingValueFloat):
            kind = "number"
            current = float(current)
        else:
            kind = "string"
            current = str(current).rstrip()
        fields.append({
            "name": setting.get_name(),
            "label": setting.get_shortname(),
            "kind": kind,
            "value": current,
            "choices": choices,
            "mutable": value.get_mutable(),
        })
    return fields


def features_json(radio):
    features = radio.get_features()
    return {
        "duplexes": list(features.valid_duplexes),
        "toneModes": list(features.valid_tmodes),
        "crossModes": list(features.valid_cross_modes),
        "modes": list(features.valid_modes),
        "steps": list(features.valid_tuning_steps),
        "skips": list(features.valid_skips),
        "powers": [str(level) for level in features.valid_power_levels],
        "tones": list(features.valid_tones),
        "dtcsCodes": list(features.valid_dtcs_codes),
        "nameLength": features.valid_name_length,
        "hasTuningStep": features.has_tuning_step,
    }


def apply_json(radio, mem, item):
    fields = {
        "name": "name", "duplex": "duplex", "tone": "tmode",
        "txTone": "rtone", "rxTone": "ctone", "dtcs": "dtcs",
        "dtcsPolarity": "dtcs_polarity", "rxDtcs": "rx_dtcs",
        "crossMode": "cross_mode", "mode": "mode", "step": "tuning_step",
        "skip": "skip", "comment": "comment",
    }
    skipped_fields = []

    def set_mem(name, value):
        if name in mem.immutable:
            if getattr(mem, name, None) != value:
                skipped_fields.append(name)
            return
        setattr(mem, name, value)

    set_mem("number", int(item["location"]))
    set_mem("freq", int(float(item["frequency"]) * 1_000_000))
    set_mem("offset", int(float(item["offset"]) * 1_000_000))
    for source, target in fields.items():
        set_mem(target, item[source])
    if item.get("power"):
        for level in radio.get_features().valid_power_levels:
            if str(level) == item["power"]:
                set_mem("power", level)
                break
    extra_values = {
        field["name"]: field.get("value")
        for field in item.get("extras", [])
    }
    for setting in mem.extra:
        if setting.get_name() in extra_values and setting.value.get_mutable():
            setting.value = extra_values[setting.get_name()]
    set_mem("empty", False)
    return skipped_fields


def open_serial(radio_class, port):
    import serial

    if "://" in port:
        handle = serial.serial_for_url(port, do_not_open=True)
        handle.timeout = 0.25
        handle.rtscts = radio_class.HARDWARE_FLOW
        handle.rts = radio_class.WANTS_RTS
        handle.dtr = radio_class.WANTS_DTR
        handle.open()
        handle.baudrate = radio_class.BAUD_RATE
    else:
        # Configure baud and modem-control lines before opening the device.
        # This mirrors CHIRP's clone dialog and avoids a pulse at the radio.
        handle = serial.Serial(
            baudrate=radio_class.BAUD_RATE,
            rtscts=radio_class.HARDWARE_FLOW,
            timeout=0.25,
        )
        handle.rts = radio_class.WANTS_RTS
        handle.dtr = radio_class.WANTS_DTR
        handle.port = port
        handle.open()
    # Some modern CHIRP drivers annotate the GUI's SerialTrace stream. The
    # headless bridge does not need a trace file, but it must expose the same
    # interface as CHIRP's serial wrapper.
    handle.log = lambda message: None
    return handle


def radio_for(directory, model, port):
    radio_class = directory.get_radio(model)
    handle = open_serial(radio_class, port)
    try:
        try:
            radio_class = radio_class.detect_from_serial(handle)
        except NotImplementedError:
            pass
        radio = radio_class(handle)
        # The GUI replaces CHIRP's console progress callback. Do the same so
        # progress text never contaminates the JSON response on stdout.
        radio.status_fn = lambda status: None
        return radio
    except Exception:
        handle.close()
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--vendor", required=True)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list-models")
    model_info = sub.add_parser("model-info")
    model_info.add_argument("--model", required=True)
    for name in ("download", "upload"):
        command = sub.add_parser(name)
        command.add_argument("--model", required=True)
        command.add_argument("--port", required=True)
        if name == "upload":
            command.add_argument("--image", required=True)
            command.add_argument("--channels", required=True)
            command.add_argument("--cleared", default="")
    args = parser.parse_args()
    try:
        directory = load_chirp(args.source, args.vendor)
        if args.command == "list-models":
            print(json.dumps({"models": sorted(directory.DRV_TO_RADIO.keys())}))
            return
        if args.command == "model-info":
            prompts = directory.get_radio(args.model).get_prompts()
            print(json.dumps({
                "info": prompts.info,
                "experimental": prompts.experimental,
                "preDownload": prompts.pre_download,
            }))
            return
        radio = radio_for(directory, args.model, args.port)
        try:
            if args.command == "download":
                radio.sync_in()
                fd, image = tempfile.mkstemp(prefix="newchirp-", suffix=".img")
                os.close(fd)
                radio.save_mmap(image)
                start, end = radio.get_features().memory_bounds
                channels = []
                for location in range(start, end + 1):
                    mem = radio.get_memory(location)
                    if not mem.empty:
                        channels.append(memory_json(mem))
                print(json.dumps({
                    "channels": channels,
                    "imagePath": image,
                    "features": features_json(radio),
                }))
            else:
                radio.load_mmap(args.image)
                with open(args.channels, encoding="utf-8") as handle:
                    items = json.load(handle)
                from chirp import chirp_common
                skipped = []
                adjusted = []
                for item in items:
                    try:
                        mem = radio.get_memory(int(item["location"]))
                    except Exception:
                        mem = chirp_common.Memory()
                    try:
                        locked_fields = apply_json(radio, mem, item)
                        errors = radio.validate_memory(mem)
                        if errors:
                            if locked_fields:
                                skipped.append({
                                    "location": int(item["location"]),
                                    "name": item.get("name", ""),
                                    "reason": (
                                        "locked field(s): %s left a required "
                                        "value unchanged" % ", ".join(locked_fields)
                                    ),
                                    "skipped": True,
                                })
                                continue
                            raise RuntimeError(
                                f"Channel {mem.number}: {errors[0]}")
                        radio.set_memory(mem)
                        if locked_fields:
                            adjusted.append({
                                "location": int(item["location"]),
                                "name": item.get("name", ""),
                                "fields": locked_fields,
                            })
                    except chirp_common.ImmutableValueError as exc:
                        skipped.append({
                            "location": int(item["location"]),
                            "name": item.get("name", ""),
                            "reason": str(exc),
                            "skipped": True,
                        })
                cleared = [
                    int(part) for part in args.cleared.split(",") if part.strip()
                ]
                for location in cleared:
                    try:
                        mem = radio.get_memory(location)
                        mem.empty = True
                        radio.set_memory(mem)
                    except Exception:
                        continue
                radio.sync_out()
                print(json.dumps({
                    "ok": True,
                    "skipped": skipped,
                    "adjusted": adjusted,
                }))
        finally:
            radio.pipe.close()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
