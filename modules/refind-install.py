#!@python3@/bin/python3 -B

import json
import os
import re
import shutil
import subprocess
from ctypes import CDLL
from dataclasses import dataclass
from datetime import datetime
from typing import Any

libc = CDLL("libc.so.6")
config = json.load(open("@configPath@", "r"))

boot_kernel_dir = "/efi/nixos"
kernel_dir = os.path.join(config["efiMountPoint"], "efi", "nixos")

refind_dir = os.path.join(
    config["efiMountPoint"],
    "efi",
    "boot" if config["efiInstallAsRemovable"] else "refind",
)


def to_snake_case(s: str) -> str:
    return re.sub(r"(?<!^)(?=[A-Z])", "_", s).lower()


def get_system_path(profile: str = "system", gen: str | None = None) -> str:
    basename = f"{profile}-{gen}-link" if gen is not None else profile
    profiles_dir = "/nix/var/nix/profiles"
    if profile == "system":
        result = os.path.join(profiles_dir, basename)
    else:
        result = os.path.join(profiles_dir, "system-profiles", basename)

    return result


def get_kernel_uri(kernel_path: str, needSignature=True) -> str:
    package_id = os.path.basename(os.path.dirname(kernel_path))
    suffix = os.path.basename(kernel_path)
    dest_file = f"{package_id}-{suffix}"
    dest_path = os.path.join(kernel_dir, dest_file)

    dirname = os.path.dirname(dest_path)

    if not os.path.exists(dirname):
        os.makedirs(dirname)

    if config["signWithLocalKeys"] and needSignature:
        result = subprocess.run(
            [
                os.path.join(config["sbsignPath"], "bin", "sbsign"),
                "--key",
                "/etc/refind.d/keys/refind_local.key",
                "--cert",
                "/etc/refind.d/keys/refind_local.crt",
                "--output",
                dest_path,
                kernel_path,
            ],
            universal_newlines=True,
        )
        result.check_returncode()
    elif not os.path.exists(dest_path):
        shutil.copyfile(kernel_path, dest_path)

    return os.path.join(boot_kernel_dir, dest_file)


def get_profiles() -> list[str]:
    profiles_dir = "/nix/var/nix/profiles/system-profiles/"
    dirs = os.listdir(profiles_dir) if os.path.isdir(profiles_dir) else []

    return [path for path in dirs if not path.endswith("-link")]


def get_gens(profile: str = "system") -> list[int]:
    nix_env = os.path.join(config["nixPath"], "bin", "nix-env")
    output = subprocess.check_output(
        [
            nix_env,
            "--list-generations",
            "-p",
            get_system_path(profile),
            "--option",
            "build-users-group",
            "",
        ],
        universal_newlines=True,
    )

    gen_lines = output.splitlines()
    gen_nums = [int(line.split()[0]) for line in gen_lines]

    return [gen for gen in gen_nums][-(config["maxGenerations"] or 0) :]


@dataclass
class BootSpec:
    system: str
    init: str
    kernel: str
    kernelParams: list[str]
    label: str
    toplevel: str
    specializations: dict[str, "BootSpec"]
    initrd: str | None = None
    initrdSecrets: str | None = None


Generations = list[tuple[int, BootSpec]]

Profiles = list[tuple[str, Generations]]


def boot_json_to_boot_spec(boot_json: dict) -> BootSpec:
    specializations = boot_json["org.nixos.specialisation.v1"]
    specializations = {k: boot_json_to_boot_spec(v) for k, v in specializations.items()}
    return BootSpec(
        **boot_json["org.nixos.bootspec.v1"],
        specializations=specializations,
    )


def get_gens_with_boot_specs(profile: str = "system") -> Generations:
    gens = get_gens(profile)
    return [
        (
            gen,
            boot_json_to_boot_spec(
                json.load(
                    open(os.path.join(get_system_path(profile, gen), "boot.json"), "r")
                )
            ),
        )
        for gen in reversed(gens)
    ]


def get_kernels_uri(boot_spec: BootSpec) -> list[str]:
    return [
        get_kernel_uri(boot_spec.kernel),
        get_kernel_uri(boot_spec.initrd, False) if boot_spec.initrd else None,
    ]


def get_options(boot_spec: BootSpec) -> str:
    return " ".join(["init=" + boot_spec.init] + boot_spec.kernelParams).strip()


def get_label(
    boot_spec: BootSpec, gen: int, profile: str | None = None, spec: str | None = None
) -> str:
    profile_name = (
        ""
        if profile is None
        else (" default profile" if profile == "system" else f' profile "{profile}"')
    )
    spec_name = f" ({spec})" if spec is not None else ""
    version = boot_spec.label.replace("NixOS", "").strip()

    return f"NixOS{profile_name} Generation {gen}{spec_name} {version}"


def get_refind_kernel_config(profiles: Profiles) -> str:
    content = ""

    for profile, gens in profiles:
        showed_profile = profile if len(profiles) > 1 else None
        for gen, boot_spec in gens:
            [loader, initrd] = get_kernels_uri(boot_spec)
            initrd_option = "" if initrd is None else f" initrd={initrd}"

            gen_label = get_label(boot_spec, gen, showed_profile)
            content += (
                f'"{gen_label}" "{loader} {get_options(boot_spec)}{initrd_option}"\n'
            )

            for spe, spe_boot_spec in boot_spec.specializations.items():
                get_kernels_uri(spe_boot_spec)

                spe_label = get_label(spe_boot_spec, gen, showed_profile, spe)
                content += f'"{spe_label}" "{loader} {get_options(spe_boot_spec)}{initrd_option}"\n'

    return content


def get_boot_spec_config(boot_spec: BootSpec) -> dict[str, str]:
    [loader, initrd] = get_kernels_uri(boot_spec)
    config = {
        "loader": loader,
        "options": get_options(boot_spec),
    }
    if initrd:
        config["initrd"] = initrd

    return config


def generate_config_entry(gens: Generations, profile: str | None = None) -> str:
    [(first_gen, first_bs), *rest] = gens

    subentries = {}

    for spe, spe_bs in first_bs.specializations.items():
        specialization_label = get_label(first_bs, first_gen, profile, spe)
        subentries[specialization_label] = get_boot_spec_config(spe_bs)

    for gen, boot_spec in rest:
        gen_label = get_label(boot_spec, gen, profile)
        subentries[gen_label] = get_boot_spec_config(boot_spec)

        for spe, spe_boot_spec in boot_spec.specializations.items():
            spe_label = get_label(boot_spec, gen, profile, spe)
            subentries[spe_label] = get_boot_spec_config(spe_boot_spec)

    return get_entry(
        get_label(first_bs, first_gen, profile),
        {
            **get_boot_spec_config(first_bs),
            "submenuEntries": subentries,
        },
    )


def get_config_line(key: str, value: Any, indent: str = "") -> str:
    if key == "defaultSelection" and type(value) == list:
        return "".join([get_config_line(key, line, indent) for line in value])
    else:
        if type(value) == bool:
            formatted_value = str(value).lower()
        elif type(value) == str:
            if key == "options" or key == "addOptions":
                formatted_value = f'"{value.replace('"', '""')}"'
            else:
                formatted_value = value
        elif type(value) == int or type(value) == float:
            formatted_value = str(value)
        elif type(value) == list:
            if key == "resolution":
                formatted_value = " ".join(value)
            else:
                formatted_value = ",".join(value)
        else:
            raise ValueError(f"Unsupported type: {type(value)} for key {key}")

        return f"{indent}{to_snake_case(key)} {formatted_value}\n"


def get_entry(name: str, entry_config: dict[str, Any], is_sub: bool = False) -> str:
    entry = ""
    indent = "    "
    if is_sub:
        entry += "    sub"
        indent += "    "

    entry += f'menuentry "{name}" {{\n'

    for key, value in entry_config.items():
        if value is not None:
            if key == "enable":
                if value == False:
                    entry += f"{indent}disabled\n"
            elif key == "submenuEntries":
                if is_sub:
                    raise ValueError("submenuEntries is not allowed in submenu entries")
                for name, entry_config in value.items():
                    entry += get_entry(name, entry_config, True)
            else:
                entry += get_config_line(key, value, indent)
    if is_sub:
        entry += "    "
    return entry + "}\n"


def copy_themes(value) -> str:
    if type(value) != str or not os.path.isdir(value):
        raise ValueError("theme must be a directory")

    theme_name = os.path.basename(value.rstrip("/\\"))

    dest_path = os.path.join(refind_dir, "themes", theme_name)

    dirname = os.path.dirname(dest_path)

    if not os.path.exists(dirname):
        os.makedirs(dirname)

    shutil.copytree(value, dest_path)

    return f'include {os.path.join("themes", theme_name, "theme.conf")}\n'


def copy_icons(value: list[tuple[str, str]]) -> str:
    icons_dir = os.path.join(refind_dir, "extra-icons")
    if not os.path.exists(icons_dir):
        os.makedirs(icons_dir)

    for icon_name, icon_path in value:
        shutil.copyfile(icon_path, os.path.join(icons_dir, icon_name))
    return f"icons_dir extra-icons\n"


def copy_asset(name: str, path: str) -> str:
    assets_dir = os.path.join(refind_dir, "assets")
    if not os.path.exists(assets_dir):
        os.makedirs(assets_dir)

    extension = os.path.splitext(path)[1]
    shutil.copyfile(path, os.path.join(assets_dir, name + extension))

    return f'{name} {os.path.join("assets", name + extension)}\n'


def get_refind_config(config: dict[str, Any], profiles: Profiles) -> str:
    # TODO: Only for per-generation config
    # last_gen = get_gens()[-1]
    # last_gen_json = json.load(
    #     open(os.path.join(get_system_path("system", last_gen), "boot.json"), "r")
    # )
    # last_gen_boot_spec = bootjson_to_bootspec(last_gen_json)
    # default_selection = 3 if len(last_gen_boot_spec.specialisations.items()) > 0 else 2
    content = ""
    for key, value in config.items():
        if value is not None:
            if key == "menuEntries":
                for name, entry_config in value.items():
                    content += get_entry(name, entry_config)
            elif key == "theme":
                content += copy_themes(value)
            elif key == "extraIcons":
                assert type(value) == dict
                icons = value.items()

                if len(icons) > 0:
                    content += copy_icons(icons)
            elif (
                key == "banner"
                or key == "selectionBig"
                or key == "selectionSmall"
                or key == "font"
            ):
                content += copy_asset(to_snake_case(key), value)
            elif key == "manageNixOSEntries":
                content += "\n# NixOS boot entries start here\n\n"
                if value == "by-profile":
                    for profile, gens in profiles:
                        showed_profile = profile if len(profiles) > 1 else None
                        content += generate_config_entry(gens, showed_profile)
                else:
                    for profile, gens in profiles:
                        showed_profile = profile if len(profiles) > 1 else None
                        for gen in gens:
                            content += generate_config_entry([gen], showed_profile)
                content += "\n# NixOS boot entries end here\n\n"
            else:
                content += get_config_line(key, value)
    return content


def delete_if_exists(path: str) -> None:
    path = os.path.join(refind_dir, path)
    if os.path.exists(path):
        if os.path.isdir(path):
            shutil.rmtree(path)
        else:
            os.remove(path)


def install_bootloader() -> None:
    print("Installing bootloader...")

    if config["installation"] != False:
        if not config["efiInstallAsRemovable"] and not config["canTouchEfiVariables"]:
            print(
                "warning: boot.loader.efi.canTouchEfiVariables is set to false while boot.loader.refind.efiInstallAsRemovable.\n  This may render the system unbootable."
            )

        print("running refind-install...")
        command = [os.path.join(config["refindPath"], "bin", "refind-install"), "--yes"]

        if config["efiInstallAsRemovable"]:
            command.append("--usedefault")

        if config["signWithLocalKeys"]:
            command.append("--localkeys")

        if config["installDrivers"] == "all":
            command.append("--alldrivers")
        elif config["installDrivers"] == "none":
            command.append("--nodrivers")

        if type(config["installation"]) == str:
            # --shim and --preloader are equivalent
            command += ["--shim", config["installation"]]

        # --notesp --ownhfs --root --encryptkeys --keepname
        result = subprocess.run(
            command,
            universal_newlines=True,
            env={
                "PATH": ":".join(
                    [
                        os.path.join(config["coreUtilsPath"], "bin"),
                        os.path.join(config["findUtilsPath"], "bin"),
                        os.path.join(config["utilLinuxPath"], "bin"),
                        os.path.join(config["gnuGrepPath"], "bin"),
                        os.path.join(config["gnuSedPath"], "bin"),
                        os.path.join(config["gnuAwkPath"], "bin"),
                        os.path.join(config["gptFDiskPath"], "bin"),
                        os.path.join(config["openSSLPath"], "bin"),
                        os.path.join(config["sbsignPath"], "bin"),
                        (
                            os.path.join(config["mokUtilPath"], "bin")
                            if config["canTouchEfiVariables"]
                            else ""
                        ),
                        os.path.join(config["glibcPath"], "bin"),
                        (
                            os.path.join(config["efiBootMgrPath"], "bin")
                            if config["canTouchEfiVariables"]
                            else ""
                        ),
                    ]
                )
            },
        )
        result.check_returncode()

        print("removing unused files...")

        delete_if_exists("icons-backup")
        delete_if_exists("refind.conf-sample")

        if config["installDrivers"] == "none":
            for unwanted_file in [
                "drivers",
                "drivers_ia32",
                "drivers_x64",
                "drivers_aa64",
            ]:
                delete_if_exists(unwanted_file)

        if not config["signWithLocalKeys"]:
            delete_if_exists("keys")

        if config["installation"] == True:
            for unwanted_file in [
                "grub.efi",
                "grubx64.efi",
                "grubaa64.efi",
                "shim.efi",
                "shimx64.efi",
                "shimx64.efi.signed",
                "shimaa64.efi",
                "mm.efi",
                "mmia32.efi",
                "mmx64.efi",
                "mmaa64.efi",
                "MokManager.efi",
                "loader.efi",
                "preloader.efi",
            ]:
                delete_if_exists(unwanted_file)
        else:
            for unwanted_file in [
                "refind.efi",
                "refind_ia32.efi",
                "refind_x64.efi",
                "refind_aa64.efi",
            ]:
                delete_if_exists(unwanted_file)

    for unwanted_file in ["themes", "extra-icons", "assets"]:
        delete_if_exists(unwanted_file)

    profiles = [("system", get_gens_with_boot_specs())]

    for profile in get_profiles():
        profiles += [(profile, get_gens_with_boot_specs(profile))]

    print("Removing old kernels...")
    shutil.rmtree(kernel_dir)

    if config["generateLinuxConf"]:
        print("updating refind_linux.conf...")

        config_file = get_refind_kernel_config(profiles)

        with open(os.path.join(kernel_dir, "refind_linux.conf"), "w") as file:
            file.truncate()
            file.write(config_file.strip())
            file.flush()
            os.fsync(file.fileno())

    if config["refindConfig"] != None:
        print("updating refind.conf...")
        config_file = get_refind_config(config["refindConfig"], profiles)

        with open(os.path.join(refind_dir, "refind.conf"), "w") as file:
            file.truncate()
            file.write(config_file.strip())
            file.flush()
            os.fsync(file.fileno())

    tools_dir = os.path.join(config["efiMountPoint"], "efi", "tools")
    for filename, source_path in config["tools"].items():
        dest_path = os.path.join(tools_dir, filename)
        shutil.copyfile(source_path, dest_path)


def main() -> None:
    try:
        install_bootloader()
    finally:
        # Since fat32 provides little recovery facilities after a crash,
        # it can leave the system in an unbootable state, when a crash/outage
        # happens shortly after an update. To decrease the likelihood of this
        # event sync the efi filesystem after each update.
        rc = libc.syncfs(os.open(f"{config["efiMountPoint"]}", os.O_RDONLY))
        if rc != 0:
            print(
                f"could not sync {config["efiMountPoint"]}: {os.strerror(rc)}",
                file=sys.stderr,
            )


if __name__ == "__main__":
    main()
