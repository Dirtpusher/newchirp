#!/usr/bin/env python3
"""Small JSON boundary between NewChirp and the audited CHIRP driver tree."""
import argparse
import builtins
import json
import os
import re
import sys
import tempfile
PROGRESS_PREFIX = "__NEWCHIRP_PROGRESS__ "

# CHIRP normally redirects stdout and stderr to ~/.chirp/debug.log when it is
# launched without a terminal. The bridge owns those streams as its JSON/error
# protocol, so keep them attached to the parent process.
os.environ.setdefault("CHIRP_TESTENV", "1")


def emit_progress(label, fraction=None):
    """Send structured transfer progress without touching the JSON stdout."""
    message = str(label).replace("\r", " ").replace("\n", " ").strip()
    payload = {"label": message or "Working..."}
    if fraction is not None:
        try:
            payload["fraction"] = max(0.0, min(1.0, float(fraction)))
        except (TypeError, ValueError):
            pass
    sys.stderr.write(
        PROGRESS_PREFIX + json.dumps(payload, separators=(",", ":")) + "\n"
    )
    sys.stderr.flush()


def status_progress(status, start=0.0, end=1.0):
    """Translate a CHIRP Status message into a structured progress event."""
    label = getattr(status, "msg", None) or str(status)
    raw = None
    current = getattr(status, "cur", None)
    maximum = getattr(status, "max", None)
    if isinstance(current, (int, float)) and isinstance(maximum, (int, float)):
        if maximum > 0:
            raw = float(current) / float(maximum)
    if raw is None:
        match = re.search(r"(\d+(?:\.\d+)?)\s*%", str(status))
        if match:
            raw = float(match.group(1)) / 100.0
    if raw is None:
        emit_progress(label)
    else:
        raw = max(0.0, min(1.0, raw))
        emit_progress(label, start + (end - start) * raw)


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
        "validCharacters": features.valid_characters,
        "hasTuningStep": features.has_tuning_step,
    }


def setting_doc(element):
    doc = getattr(element, "__doc__", None)
    if not isinstance(doc, str):
        return None
    doc = doc.strip()
    if not doc or doc == element.get_name():
        return None
    return doc


def setting_value_json(setting):
    from chirp.settings import (
        RadioSettingValueBoolean,
        RadioSettingValueFloat,
        RadioSettingValueInteger,
        RadioSettingValueList,
        RadioSettingValueString,
    )

    value = setting.value
    current = value.get_value()
    options = []
    minimum = None
    maximum = None
    step = None
    min_length = None
    max_length = None
    if isinstance(value, RadioSettingValueBoolean):
        kind = "boolean"
        current = bool(current)
    elif isinstance(value, RadioSettingValueList):
        kind = "choice"
        options = [str(option) for option in value.get_options()]
        current = str(current)
    elif isinstance(value, RadioSettingValueInteger):
        kind = "integer"
        current = int(current)
        minimum = int(value.get_min())
        maximum = int(value.get_max())
        step = int(value.get_step())
    elif isinstance(value, RadioSettingValueFloat):
        kind = "number"
        current = float(current)
        minimum = float(value.get_min())
        maximum = float(value.get_max())
    else:
        kind = "string"
        current = str(current).rstrip()
        if isinstance(value, RadioSettingValueString):
            min_length = int(value.minlength)
            max_length = int(value.maxlength)
    return {
        "kind": kind,
        "value": current,
        "options": options,
        "mutable": bool(value.get_mutable()),
        "min": minimum,
        "max": maximum,
        "step": step,
        "minLength": min_length,
        "maxLength": max_length,
    }


def settings_tree_json(elements, prefix=()):
    from chirp.settings import RadioSetting, RadioSettingGroup

    result = []
    for index, element in enumerate(elements):
        path = list(prefix + (index,))
        base = {
            "id": path,
            "name": element.get_name(),
            "shortName": element.get_shortname(),
            "documentation": setting_doc(element),
        }
        if isinstance(element, RadioSetting):
            if len(element) != 1:
                result.append({
                    **base,
                    "kind": "unsupported",
                    "value": None,
                    "options": [],
                    "mutable": False,
                    "min": None,
                    "max": None,
                    "step": None,
                    "minLength": None,
                    "maxLength": None,
                })
                continue
            result.append({**base, **setting_value_json(element)})
        elif isinstance(element, RadioSettingGroup):
            result.append({
                **base,
                "kind": "group",
                "value": None,
                "options": [],
                "mutable": False,
                "min": None,
                "max": None,
                "step": None,
                "minLength": None,
                "maxLength": None,
                "children": settings_tree_json(element, tuple(path)),
            })
    return result


def apply_setting_changes(settings, changes):
    from chirp.settings import RadioSetting

    for change in changes:
        path = change.get("id")
        if not isinstance(path, list) or not path:
            raise RuntimeError("A radio setting change was missing its path.")
        element = settings
        try:
            for index in path:
                element = list(element)[int(index)]
        except (IndexError, TypeError, ValueError) as exc:
            raise RuntimeError(
                "A radio setting change no longer matches the image."
            ) from exc
        if not isinstance(element, RadioSetting) or len(element) != 1:
            raise RuntimeError(
                "A radio setting change targeted an unsupported value."
            )
        if not element.value.get_mutable():
            continue
        element.value = change.get("value")


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


def radio_for(directory, model, port, progress_range=(0.0, 1.0)):
    radio_class = directory.get_radio(model)
    handle = open_serial(radio_class, port)
    try:
        try:
            radio_class = radio_class.detect_from_serial(handle)
        except NotImplementedError:
            pass
        radio = radio_class(handle)
        # CHIRP's status callbacks become structured progress events on
        # stderr, leaving stdout available for the final JSON response.
        radio.status_fn = lambda status: status_progress(
            status, *progress_range
        )
        return radio
    except Exception:
        handle.close()
        raise


def radio_from_image(directory, model, image):
    """Build a driver instance backed only by a saved radio image."""
    radio = directory.get_radio(model)(None)
    radio.load_mmap(image)
    return radio


def settings_payload(radio):
    settings = radio.get_settings()
    return {
        "hasSettings": bool(
            getattr(radio.get_features(), "has_settings", False)
        ),
        "settings": settings_tree_json(settings or []),
    }


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
    read_settings = sub.add_parser("read-settings")
    read_settings.add_argument("--model", required=True)
    settings_source = read_settings.add_mutually_exclusive_group(required=True)
    settings_source.add_argument("--image")
    settings_source.add_argument("--port")
    write_settings = sub.add_parser("write-settings")
    write_settings.add_argument("--model", required=True)
    write_settings.add_argument("--port", required=True)
    write_settings.add_argument("--image", required=True)
    write_settings.add_argument("--settings", required=True)
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
        if args.command == "read-settings":
            if args.port is not None:
                radio = radio_for(
                    directory,
                    args.model,
                    args.port,
                    progress_range=(0.02, 0.97),
                )
                try:
                    emit_progress("Reading radio settings...", 0.01)
                    radio.sync_in()
                    fd, image = tempfile.mkstemp(
                        prefix="newchirp-", suffix=".img"
                    )
                    os.close(fd)
                    radio.save_mmap(image)
                    payload = settings_payload(radio)
                    payload["imagePath"] = image
                    emit_progress("Radio settings read.", 1.0)
                    print(json.dumps(payload))
                finally:
                    radio.pipe.close()
            else:
                radio = radio_from_image(directory, args.model, args.image)
                print(json.dumps(settings_payload(radio)))
            return
        if args.command == "download":
            progress_range = (0.02, 0.92)
        elif args.command == "upload":
            progress_range = (0.10, 0.98)
        else:
            progress_range = (0.12, 0.97)
        radio = radio_for(
            directory, args.model, args.port, progress_range=progress_range
        )
        try:
            if args.command == "download":
                emit_progress("Connecting to radio...", 0.01)
                radio.sync_in()
                emit_progress("Saving the radio image...", 0.93)
                fd, image = tempfile.mkstemp(prefix="newchirp-", suffix=".img")
                os.close(fd)
                radio.save_mmap(image)
                start, end = radio.get_features().memory_bounds
                locations = list(range(start, end + 1))
                channels = []
                for index, location in enumerate(locations):
                    mem = radio.get_memory(location)
                    if not mem.empty:
                        channels.append(memory_json(mem))
                    if locations and (
                        index % 20 == 0 or index == len(locations) - 1
                    ):
                        emit_progress(
                            "Building the channel list...",
                            0.94 + 0.05 * (index + 1) / len(locations),
                        )
                emit_progress("Read complete.", 1.0)
                print(json.dumps({
                    "channels": channels,
                    "imagePath": image,
                    "features": features_json(radio),
                }))
            elif args.command == "upload":
                emit_progress("Preparing channels...", 0.02)
                radio.load_mmap(args.image)
                with open(args.channels, encoding="utf-8") as handle:
                    items = json.load(handle)
                from chirp import chirp_common
                skipped = []
                adjusted = []
                for index, item in enumerate(items):
                    requested_name = str(item.get("name", ""))
                    filtered_name = radio.filter_name(requested_name)
                    item = dict(item)
                    item["name"] = filtered_name
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
                                    "name": filtered_name,
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
                        if locked_fields or filtered_name != requested_name:
                            adjusted.append({
                                "location": int(item["location"]),
                                "name": filtered_name,
                                "fields": locked_fields,
                                "nameFrom": requested_name,
                                "nameTo": filtered_name,
                            })
                    except chirp_common.ImmutableValueError as exc:
                        skipped.append({
                            "location": int(item["location"]),
                            "name": filtered_name,
                            "reason": str(exc),
                            "skipped": True,
                        })
                    if items and (
                        index % 10 == 0 or index == len(items) - 1
                    ):
                        emit_progress(
                            "Preparing channels...",
                            0.03 + 0.06 * (index + 1) / len(items),
                        )
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
                emit_progress("Writing the image to the radio...", 0.10)
                radio.sync_out()
                emit_progress("Saving the updated image...", 0.99)
                radio.save_mmap(args.image)
                emit_progress("Write complete.", 1.0)
                print(json.dumps({
                    "ok": True,
                    "skipped": skipped,
                    "adjusted": adjusted,
                }))
            else:
                emit_progress("Preparing radio settings...", 0.02)
                radio.load_mmap(args.image)
                with open(args.settings, encoding="utf-8") as handle:
                    payload = json.load(handle)
                settings = radio.get_settings()
                if settings is None:
                    raise RuntimeError(
                        "This radio does not expose global settings."
                    )
                changes = payload.get("changes", [])
                apply_setting_changes(settings, changes)
                emit_progress("Applying settings...", 0.10)
                radio.set_settings(settings)
                emit_progress("Writing settings to the radio...", 0.12)
                radio.sync_out()
                emit_progress("Saving the updated image...", 0.99)
                radio.save_mmap(args.image)
                emit_progress("Settings write complete.", 1.0)
                print(json.dumps({"ok": True, "changed": len(changes)}))
        finally:
            radio.pipe.close()
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
